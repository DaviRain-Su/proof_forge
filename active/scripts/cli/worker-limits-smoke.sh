#!/usr/bin/env bash
# PF-P3-03: worker resource-limit surface (local simulation).
#
# Hosted isolation still refuses under PROOF_FORGE_HOSTED_ISOLATION (gate1 of
# hosted-isolation). This smoke documents the next boundary: a *local* worker
# wrapper that enforces wall-clock time so runaway elaboration cannot hang CI.
#
# This gate proves wall-clock and process-tree cleanup. The companion
# `worker-cgroup` gate exercises the CPU/memory wrapper and cgroup fallback.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.foundry/bin:${HOME}/.local/bin:${PATH}"

fail() { echo "worker-limits: $*" >&2; exit 1; }

# Prefer GNU timeout / gtimeout; fall back to python if missing.
run_with_timeout() {
  local secs="$1"; shift
  if [[ "${PROOF_FORGE_FORCE_PYTHON_TIMEOUT:-0}" != "1" ]] && command -v timeout >/dev/null 2>&1; then
    timeout -k 1 "$secs" "$@"
  elif [[ "${PROOF_FORGE_FORCE_PYTHON_TIMEOUT:-0}" != "1" ]] && command -v gtimeout >/dev/null 2>&1; then
    gtimeout -k 1 "$secs" "$@"
  else
    python3 - "$secs" "$@" <<'PY'
import os, signal, subprocess, sys, time
secs = float(sys.argv[1])
cmd = sys.argv[2:]
proc = subprocess.Popen(cmd, start_new_session=True)

def live_group_members():
    result = subprocess.run(
        ["ps", "-Ao", "pid=,pgid=,stat="],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    members = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) < 3:
            continue
        pid, pgid, state = fields[:3]
        if int(pgid) == proc.pid and not state.startswith("Z"):
            members.append(int(pid))
    return members

def wait_for_group_exit():
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
        members = live_group_members()
        if members is None:
            return False
        if not members:
            return True
        time.sleep(0.02)
    return False

try:
    returncode = proc.wait(timeout=secs)
    sys.exit(returncode if returncode >= 0 else 128 - returncode)
except subprocess.TimeoutExpired:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        try:
            proc.terminate()
        except (ProcessLookupError, PermissionError):
            pass
    # Keep the group leader unreaped during the grace period so its PID cannot
    # be reused before the descendant cleanup signal.
    time.sleep(1)
    cleanup_failed = False
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except PermissionError:
        members = live_group_members()
        if members is None or members:
            cleanup_failed = True
        try:
            proc.kill()
        except (ProcessLookupError, PermissionError):
            pass
    if not wait_for_group_exit():
        cleanup_failed = True
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        cleanup_failed = True
    sys.exit(125 if cleanup_failed else 124)
PY
  fi
}

lake build proof-forge >/dev/null

OUT="${PROOF_FORGE_WORKER_LIMITS_OUT:-build/worker-limits-smoke}"
rm -rf "$OUT"
mkdir -p "$OUT"

# Gate 1: hosted isolation still refuse (cross-check with hosted-isolation smoke).
set +e
err="$(
  PROOF_FORGE_HOSTED_ISOLATION=1 \
    lake env proof-forge build --target wasm-near --root . \
      -o "$OUT/hosted-refused" \
      Examples/Product/Counter.lean 2>&1
)"
st=$?
set -e
[[ "$st" -ne 0 ]] || fail "hosted isolation must refuse"
echo "$err" | grep -Fq "hosted isolation is not ready" \
  || fail "missing hosted isolation diagnostic"
echo "worker-limits: gate1 hosted isolation refuse ok"

# Gate 2: trusted local build completes under a generous wall-clock limit.
set +e
out="$(
  run_with_timeout 120 lake env proof-forge build --target wasm-near --root . \
    -o "$OUT/local-ok" \
    Examples/Product/Counter.lean 2>&1
)"
st=$?
set -e
[[ "$st" -eq 0 ]] || fail "trusted local build under timeout wrapper failed (exit $st): $out"
[[ -f "$OUT/local-ok/counter.wat" || -f "$OUT/local-ok/counter.wasm" ]] \
  || fail "missing NEAR Counter artifact under $OUT/local-ok"
echo "worker-limits: gate2 local build under 120s wall-clock ok"

# Gate 3: zero-second timeout fails closed (proves the limit is enforced).
set +e
run_with_timeout 0.01 sleep 2 >/dev/null 2>&1
st=$?
set -e
# 124 is timeout(1) convention; Python fallback deliberately matches it.
[[ "$st" -eq 124 ]] || fail "expected timeout wrapper exit 124, got unrelated exit $st"
echo "worker-limits: gate3 timeout enforcement ok (exit $st)"

# Gate 4: the Python fallback must terminate the entire process group, not only
# its direct child. Otherwise compiler/tool descendants can outlive the worker.
descendant_pid_file="$OUT/descendant.pid"
descendant_token="pf-worker-descendant-$$-${RANDOM:-0}"
set +e
PROOF_FORGE_FORCE_PYTHON_TIMEOUT=1 run_with_timeout 0.3 \
  python3 -c 'import subprocess,sys,time; code="import os,signal,sys,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); open(sys.argv[1],\"w\").write(str(os.getpid())); time.sleep(30)"; subprocess.Popen([sys.executable,"-c",code,sys.argv[1],sys.argv[2]]); time.sleep(30)' \
  "$descendant_pid_file" "$descendant_token" >/dev/null 2>&1
st=$?
set -e
[[ "$st" -eq 124 ]] || fail "Python timeout fallback returned $st instead of 124"
[[ -s "$descendant_pid_file" ]] || fail "Python timeout fallback descendant did not publish its PID"
descendant_pid="$(cat "$descendant_pid_file")"
descendant_is_test_process() {
  if ! kill -0 "$descendant_pid" 2>/dev/null; then
    return 1
  fi
  local command
  if ! command="$(ps -p "$descendant_pid" -o command= 2>/dev/null)"; then
    if ! kill -0 "$descendant_pid" 2>/dev/null; then
      return 1
    fi
    fail "could not inspect descendant PID $descendant_pid"
  fi
  [[ "$command" == *"$descendant_token"* ]]
}
for _ in $(seq 1 50); do
  if ! descendant_is_test_process; then
    break
  fi
  sleep 0.05
done
if descendant_is_test_process; then
  kill -9 "$descendant_pid" 2>/dev/null || true
  fail "Python timeout fallback left descendant PID $descendant_pid alive"
fi
echo "worker-limits: gate4 Python fallback process-group cleanup ok"

echo "worker-limits: ok (PF-P3-03 wall-clock worker control; see just worker-cgroup for CPU/mem)"

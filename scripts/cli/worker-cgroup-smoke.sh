#!/usr/bin/env bash
# PF-P3-03: worker CPU/memory isolation surface beyond wall-clock.
#
# Extends `worker-limits` (wall-clock) with:
#   - RLIMIT_CPU enforcement (portable Linux + macOS)
#   - memory limit when cgroup v2 or RLIMIT_AS/DATA is available
#   - process-session cleanup on wall-clock timeout
#   - honest skip/fail reporting when memory backend is absent
#
# Full multi-tenant hosted isolation still refuses under
# PROOF_FORGE_HOSTED_ISOLATION; this smoke proves local worker resource
# controls exist and hostile processes cannot freely burn CPU / (when
# supported) RAM under the wrapper.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.foundry/bin:${HOME}/.local/bin:${PATH}"

fail() { echo "worker-cgroup: $*" >&2; exit 1; }

WRAPPER="$ROOT/scripts/cli/worker-resource-limit.py"
[[ -f "$WRAPPER" ]] || fail "missing $WRAPPER"
chmod +x "$WRAPPER" 2>/dev/null || true

OUT="${PROOF_FORGE_WORKER_CGROUP_OUT:-build/worker-cgroup-smoke}"
rm -rf "$OUT"
mkdir -p "$OUT"

# Gate 1: CPU limit kills a busy-loop (portable; uses RLIMIT_CPU).
set +e
out="$(
  python3 "$WRAPPER" --wall-sec 10 --cpu-sec 1 -- \
    python3 -c 'import math
x=0.0
while True:
    x+=math.sin(x)
' 2>&1
)"
st=$?
set -e
# RLIMIT_CPU normally yields SIGXCPU (152) or a hard SIGKILL (137).
[[ "$st" -eq 152 || "$st" -eq 137 ]] \
  || fail "CPU-limited busy loop exited unexpectedly (exit $st); out=$out"
echo "$out" | grep -Fq "mem_backend=" || fail "wrapper did not report mem_backend: $out"
echo "worker-cgroup: gate1 RLIMIT_CPU kills busy-loop ok (exit $st)"

# Gate 2: memory bomb under tight limit — only when a backend can apply.
mem_probe_log="$OUT/mem-backend-probe.log"
# Probe with require-mem to see availability without a bomb.
set +e
python3 "$WRAPPER" --wall-sec 2 --mem-bytes 33554432 --require-mem -- \
  python3 -c 'print("mem-backend-ok")' >"$mem_probe_log" 2>&1
mem_probe_st=$?
set -e
if [[ "$mem_probe_st" -eq 0 ]]; then
  set +e
  bomb_out="$(
    python3 "$WRAPPER" --wall-sec 15 --mem-bytes 33554432 -- \
      python3 -c '
chunks = []
while True:
    chunks.append(bytearray(2_000_000))
' 2>&1
  )"
  bomb_st=$?
  set -e
  [[ "$bomb_st" -ne 0 ]] || fail "memory bomb must not exit 0 under 32MiB limit (exit $bomb_st); $bomb_out"
  echo "worker-cgroup: gate2 memory bomb killed under limit ok (exit $bomb_st)"
  echo "mem" >"$OUT/mem-backend-enforced"
else
  # Honest skip: platform cannot lower memory (common on macOS without cgroup).
  # Hosted deployments must set PROOF_FORGE_REQUIRE_CGROUP_MEM=1 on Linux workers.
  if [[ "${PROOF_FORGE_REQUIRE_CGROUP_MEM:-0}" == "1" ]]; then
    fail "memory backend required but unavailable (probe exit $mem_probe_st); $(cat "$mem_probe_log" 2>/dev/null || true)"
  fi
  echo "worker-cgroup: gate2 SKIP memory backend unavailable on this host (CPU+wall still enforced)"
  echo "skip" >"$OUT/mem-backend-enforced"
fi

# Gate 3: wall-clock still enforced by the same wrapper.
set +e
python3 "$WRAPPER" --wall-sec 0.2 -- \
  python3 -c 'import time; time.sleep(5)' >/dev/null 2>&1
st=$?
set -e
[[ "$st" -eq 124 ]] || fail "wall-clock timeout returned $st instead of 124"
echo "worker-cgroup: gate3 wall-clock timeout ok (exit $st)"

# Gate 4: timeout terminates descendants too, including one that ignores TERM.
descendant_pid_file="$OUT/descendant.pid"
set +e
python3 "$WRAPPER" --wall-sec 0.4 -- python3 - "$descendant_pid_file" \
  >"$OUT/descendant-timeout.log" 2>&1 <<'PY'
import subprocess
import sys
import time

code = (
    "import signal,sys,time; "
    "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
    "open(sys.argv[1], 'w').write(str(__import__('os').getpid())); "
    "time.sleep(30)"
)
subprocess.Popen([sys.executable, "-c", code, sys.argv[1]])
time.sleep(30)
PY
st=$?
set -e
[[ "$st" -eq 124 ]] || fail "descendant timeout returned $st instead of 124"
[[ -s "$descendant_pid_file" ]] || fail "descendant did not publish its PID"
descendant_pid="$(cat "$descendant_pid_file")"
for _ in $(seq 1 50); do
  if ! kill -0 "$descendant_pid" 2>/dev/null; then
    break
  fi
  sleep 0.05
done
if kill -0 "$descendant_pid" 2>/dev/null; then
  kill -9 "$descendant_pid" 2>/dev/null || true
  fail "worker wrapper left descendant PID $descendant_pid alive"
fi
echo "worker-cgroup: gate4 process-group timeout cleanup ok"

# Gate 5: trusted local Counter build under generous worker limits succeeds.
lake build proof-forge >/dev/null
set +e
build_out="$(
  python3 "$WRAPPER" --wall-sec 180 --cpu-sec 120 -- \
    lake env proof-forge build --target wasm-near --root . \
      -o "$OUT/local-ok" \
      Examples/Product/Counter.lean 2>&1
)"
st=$?
set -e
[[ "$st" -eq 0 ]] || fail "Counter build under worker limits failed (exit $st): $build_out"
[[ -f "$OUT/local-ok/counter.wat" || -f "$OUT/local-ok/counter.wasm" ]] \
  || fail "missing NEAR Counter artifact under $OUT/local-ok"
echo "worker-cgroup: gate5 Counter build under generous CPU+wall limits ok"

# Gate 6: hosted isolation still refuses (does not claim cgroup is enough alone).
set +e
err="$(
  PROOF_FORGE_HOSTED_ISOLATION=1 \
    lake env proof-forge build --target wasm-near --root . \
      -o "$OUT/hosted-refused" \
      Examples/Product/Counter.lean 2>&1
)"
st=$?
set -e
[[ "$st" -ne 0 ]] || fail "hosted isolation must still refuse"
echo "$err" | grep -Fq "hosted isolation is not ready" \
  || fail "missing hosted isolation diagnostic"
echo "worker-cgroup: gate6 hosted isolation still refuse ok"

echo "worker-cgroup: ok (PF-P3-03 CPU+wall worker limits; mem when platform supports)"

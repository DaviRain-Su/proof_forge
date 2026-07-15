#!/bin/bash
set -euo pipefail

die() {
  echo "clean-room: $*" >&2
  exit 1
}

sha256_file() {
  local output
  output="$(/usr/bin/openssl dgst -sha256 -r "$1")"
  echo "${output%% *}"
}

run_core_gate() {
  [[ -n "${PF_CLEAN_SOURCE:-}" && -n "${PF_CLEAN_OUTPUT:-}" && -n "${PF_LEAN_ROOT:-}" ]] ||
    die "internal clean-room environment is incomplete"
  [[ -z "${LEAN_PATH+x}" && -z "${LEAN_SRC_PATH+x}" && -z "${ELAN_HOME+x}" ]] ||
    die "Lean or Elan environment leaked into clean room"
  [[ "$PATH" == "$PF_LEAN_ROOT/bin:$PROOF_FORGE_TOOL_ROOT" ]] ||
    die "unexpected PATH in clean room: $PATH"
  if /usr/bin/git -C "$PF_CLEAN_SOURCE" rev-parse --show-toplevel >/dev/null 2>&1; then
    die "archive can discover a parent Git repository"
  fi

  local lake="$PF_LEAN_ROOT/bin/lake"
  local compiler="$PF_CLEAN_SOURCE/.lake/build/bin/proof-forge-next"
  local tests="$PF_CLEAN_SOURCE/.lake/build/bin/proof-forge-next-tests"
  local targets="$PF_CLEAN_OUTPUT/targets"
  local repro="$PF_CLEAN_OUTPUT/repro"

  /usr/bin/python3 -I -S "$PF_CLEAN_SOURCE/scripts/docs_check.py"
  "$lake" --dir "$PF_CLEAN_SOURCE" --no-cache build \
    ProofForgeV2 proof_forge_next proof_forge_next_tests
  "$lake" --dir "$PF_CLEAN_SOURCE" env "$tests"

  /bin/mkdir -p "$targets"
  "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build testdata/valid/Standalone.lean \
    --root "$PF_CLEAN_SOURCE" --program UserStandalone.Counter --target evm -o "$targets/standalone"
  for target in evm solana near noir; do
    "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Counter.lean \
      --root "$PF_CLEAN_SOURCE" --program Examples.Counter --target "$target" -o "$targets/$target"
  done
  /usr/bin/python3 -I -S "$PF_CLEAN_SOURCE/scripts/validate_artifacts.py" "$targets"

  for run in a b; do
    for target in evm solana near noir; do
      "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Counter.lean \
        --root "$PF_CLEAN_SOURCE" --program Examples.Counter --target "$target" -o "$repro/$run/$target"
    done
  done
  /usr/bin/python3 -I -S "$PF_CLEAN_SOURCE/scripts/check_reproducibility.py" "$repro/a" "$repro/b"
  echo "clean-room: docs/build/tests/target-smoke/reproducibility ok"
}

run_evm_gate() {
  [[ -n "${PF_CLEAN_OUTPUT:-}" && -n "${PROOF_FORGE_TOOL_ROOT:-}" ]] ||
    die "internal EVM environment is incomplete"
  [[ "$PATH" == "$PF_LEAN_ROOT/bin:$PROOF_FORGE_TOOL_ROOT" ]] ||
    die "unexpected PATH in EVM clean room: $PATH"

  local anvil="$PROOF_FORGE_TOOL_ROOT/anvil"
  local cast="$PROOF_FORGE_TOOL_ROOT/cast"
  local bytecode_file="$PF_CLEAN_OUTPUT/targets/evm/Counter.bin"
  local log="$PF_CLEAN_OUTPUT/anvil.log"
  local rpc="http://127.0.0.1:${PF_EVM_PORT}"
  local private_key="ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  [[ -x "$anvil" && -x "$cast" && -f "$bytecode_file" ]] || die "EVM runtime inputs are missing"

  "$anvil" --port "$PF_EVM_PORT" --silent >"$log" 2>&1 &
  local anvil_pid=$!
  cleanup_anvil() {
    kill "$anvil_pid" 2>/dev/null || true
    wait "$anvil_pid" 2>/dev/null || true
  }
  trap cleanup_anvil EXIT

  local ready=0
  local attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
      ready=1
      break
    fi
    /bin/sleep 0.1
  done
  [[ "$ready" == 1 ]] || die "Anvil failed to start; see $log"

  deploy_counter() {
    local initial="$1"
    local bytecode encoded receipt
    bytecode="$(/usr/bin/tr -d '\n\r ' < "$bytecode_file")"
    encoded="$("$cast" abi-encode 'constructor(uint64)' "$initial")"
    receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
      --create "0x${bytecode}${encoded#0x}")"
    /usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$receipt"
  }

  local counter before after balance bytecode encoded max_counter preserved
  counter="$(deploy_counter 7)"
  before="$("$cast" call --rpc-url "$rpc" "$counter" 'get()(uint64)')"
  [[ "$before" == 7 ]] || die "unexpected initial Counter value: $before"
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 2 \
      "$counter" 'increment(uint64)' 5 >/dev/null 2>&1; then
    die "nonpayable increment accepted value"
  fi
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$counter" 'increment(uint64)' 5 >/dev/null
  after="$("$cast" call --rpc-url "$rpc" "$counter" 'get()(uint64)')"
  [[ "$after" == 12 ]] || die "unexpected incremented Counter value: $after"
  balance="$("$cast" balance --rpc-url "$rpc" "$counter")"
  [[ "$balance" == 0 ]] || die "Counter retained value: $balance"

  bytecode="$(/usr/bin/tr -d '\n\r ' < "$bytecode_file")"
  encoded="$("$cast" abi-encode 'constructor(uint64)' 7)"
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 1 \
      --create "0x${bytecode}${encoded#0x}" >/dev/null 2>&1; then
    die "nonpayable constructor accepted value"
  fi

  max_counter="$(deploy_counter 18446744073709551615)"
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
      "$max_counter" 'increment(uint64)' 1 >/dev/null 2>&1; then
    die "overflow transaction unexpectedly succeeded"
  fi
  preserved="$("$cast" call --rpc-url "$rpc" "$max_counter" 'get()(uint64)')"
  preserved="${preserved%% *}"
  [[ "$preserved" == 18446744073709551615 ]] || die "overflow changed state: $preserved"
  cleanup_anvil
  trap - EXIT
  echo "clean-room: EVM localhost runtime ok"
}

case "${1:-}" in
  --internal-core)
    run_core_gate
    exit 0
    ;;
  --internal-evm)
    run_evm_gate
    exit 0
    ;;
esac

source_home="${HOME:?HOME is required while provisioning the locked cache}"
asset_cache="${PROOF_FORGE_ASSET_CACHE:-${XDG_CACHE_HOME:-$source_home/.cache}/proof-forge-v2/assets}"
root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd -P)"
started_utc="$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")"
start_epoch="$(/bin/date +%s)"
evidence_out="${PROOF_FORGE_EVIDENCE_OUT:-$root/build/evidence/clean-room}"
evidence_id="${PROOF_FORGE_EVIDENCE_ID:-EV-$(/bin/date -u +%Y%m%d)-0012}"

/usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC \
  /bin/bash --noprofile --norc "$root/scripts/verify_host_stage0.sh" \
  --allow-ineligible-development >"$root/build/host-stage0-development.json" 2>"$root/build/host-stage0-development.err" ||
  {
    /bin/cat "$root/build/host-stage0-development.err" >&2 || true
    die "Stage-0 development attestation failed"
  }
/bin/mkdir -p "$root/build"
# Stage-0 prints canonical JSON on stdout; keep it for EV binding.
host_observation="$root/build/host-stage0-development.json"
[[ -s "$host_observation" ]] || die "Stage-0 observation JSON is missing"

unset BASH_ENV ENV CDPATH DEVELOPER_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_DIR \
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_REPLACE_REF_BASE PYTHONHOME \
  PYTHONPATH PYTHONSTARTUP LEAN_PATH LEAN_SRC_PATH ELAN_HOME PROOF_FORGE_ASSET_CACHE \
  XDG_CACHE_HOME
export PATH=/usr/bin:/bin
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
command -v /usr/bin/sandbox-exec >/dev/null 2>&1 || die "macOS sandbox-exec is unavailable"

# H1 policy self-test must pass before archive work.
/usr/bin/python3 -I -S "$root/scripts/sandbox_policy.py" self-test
/usr/bin/python3 -I -S "$root/scripts/evidence.py" self-test

repo_root="$(/usr/bin/git -C "$root" rev-parse --show-toplevel)"
prefix="$(/usr/bin/git -C "$root" rev-parse --show-prefix)"
[[ "$prefix" == new_design/ ]] || die "expected new_design/ to be a tracked subtree, got '$prefix'"
commit="$(/usr/bin/git -C "$repo_root" rev-parse HEAD)"
treeish="$commit:new_design"
[[ "$(/usr/bin/git -C "$repo_root" cat-file -t "$treeish" 2>/dev/null)" == tree ]] ||
  die "HEAD does not contain new_design"
dirty=false
if [[ -n "$(/usr/bin/git -C "$repo_root" status --porcelain --untracked-files=no -- new_design)" ]]; then
  dirty=true
fi

tmp="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/proof-forge-v2-clean-room.XXXXXX")"
cleanup() {
  if [[ -n "${probe_pid:-}" ]]; then
    kill "$probe_pid" 2>/dev/null || true
    wait "$probe_pid" 2>/dev/null || true
  fi
  if [[ -n "${tool_root:-}" ]]; then
    /usr/bin/find -P "$tool_root" -type d -exec /bin/chmod u+w {} + 2>/dev/null || true
  fi
  /bin/rm -rf -- "$tmp"
}
trap cleanup EXIT

source_root="$tmp/source"
home_root="$tmp/home"
cache_root="$tmp/cache"
tool_root="$tmp/tools"
external_bin="$tool_root/external"
output_root="$tmp/output"
work_root="$tmp/work"
runner="$tmp/clean-room-runner.sh"
/bin/mkdir -p "$source_root" "$home_root" "$cache_root" "$tool_root" "$output_root" "$work_root"
/bin/chmod 700 "$home_root" "$cache_root" "$tool_root" "$output_root" "$work_root"

archive="$tmp/new-design.tar"
/usr/bin/git -C "$repo_root" archive --format=tar "$treeish" . >"$archive"
archive_hash="$(sha256_file "$archive")"
if /usr/bin/git -C "$repo_root" ls-tree -r "$treeish" | /usr/bin/awk '$1 == "120000" || $1 == "160000" { found=1 } END { exit !found }'; then
  die "tracked symlink or submodule found in archive tree"
fi
/usr/bin/tar -tf "$archive" | while IFS= read -r entry; do
  [[ "$entry" != /* && "$entry" != ../* && "$entry" != */../* ]] ||
    die "unsafe archive path: $entry"
done
/usr/bin/tar -C "$source_root" -xf "$archive"
[[ ! -e "$source_root/.git" ]] || die "archive unexpectedly contains Git metadata"
if /usr/bin/find "$source_root" -type l -print -quit | /usr/bin/grep -q .; then
  die "archive contains a symlink"
fi
if /usr/bin/find "$source_root" -name '*.lean' -type f -exec /usr/bin/grep -nE \
    '(^|[[:space:]])import[[:space:]]+ProofForge([[:space:].]|$)' {} +; then
  die "archive contains a parent ProofForge import"
fi
if /usr/bin/grep -R -F "$repo_root" "$source_root" >/dev/null 2>&1; then
  die "archive embeds the parent repository absolute path"
fi

# Candidate/archive binding digests (H1).
host_bootstrap_sha="$(sha256_file "$source_root/host-bootstrap.lock")"
host_lock_sha="$(sha256_file "$source_root/host-profiles.lock.json")"
tool_lock_sha="$(sha256_file "$source_root/toolchains.lock.json")"
launcher_sha="$(sha256_file "$source_root/scripts/verify_host_stage0.sh")"
verifier_sha="$(sha256_file "$source_root/scripts/toolchain_assets.py")"
isolation_sha="$(sha256_file "$source_root/scripts/verify_isolation.sh")"
sandbox_policy_sha="$(sha256_file "$source_root/scripts/sandbox_policy.py")"
evidence_py_sha="$(sha256_file "$source_root/scripts/evidence.py")"
binding_file="$tmp/candidate-binding.json"
/usr/bin/python3 -I -S - "$binding_file" <<PY
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = {
  "schema": "proof-forge.candidate-binding.v1",
  "candidateCommit": "$commit",
  "archiveSha256": "$archive_hash",
  "hostBootstrapSha256": "$host_bootstrap_sha",
  "hostLockSha256": "$host_lock_sha",
  "toolLockSha256": "$tool_lock_sha",
  "launcherSha256": "$launcher_sha",
  "verifierSha256": "$verifier_sha",
  "isolationHarnessSha256": "$isolation_sha",
  "sandboxPolicySha256": "$sandbox_policy_sha",
  "evidenceHelperSha256": "$evidence_py_sha",
  "sandboxPolicy": "deny-default",
  "evidenceSchema": "proof-forge.evidence.v1",
}
path.write_text(json.dumps(doc, separators=(",", ":"), sort_keys=True) + "\n", encoding="utf-8")
print("clean-room: candidate/archive binding ok commit=$commit archive_sha256=$archive_hash")
PY

# Deny-default materialize profile: only work tree + asset cache readable.
materialize_profile="$(
  /usr/bin/python3 -I -S "$source_root/scripts/sandbox_policy.py" emit \
    --mode materialize \
    --work-root "$tmp" \
    --asset-cache "$asset_cache"
)"
[[ "$materialize_profile" == *"(deny default)"* ]] || die "materialize profile is not deny-default"
[[ "$materialize_profile" != *"(allow default)"* ]] || die "materialize profile must not allow default"

lean_root="$tool_root/lean"
/usr/bin/sandbox-exec -p "$materialize_profile" /usr/bin/env -i \
  "HOME=$home_root" "LC_ALL=C" "PATH=/usr/bin:/bin" \
  "PROOF_FORGE_ASSET_CACHE=$asset_cache" "TMPDIR=$work_root" "TZ=UTC" /usr/bin/python3 -I -S \
  "$source_root/scripts/toolchain_assets.py" \
  --lock "$source_root/toolchains.lock.json" \
  --host-lock "$source_root/host-profiles.lock.json" \
  materialize-lean --destination "$lean_root"
[[ -z "$(/usr/bin/find "$lean_root" -type l -print -quit)" ]] || die "materialized Lean toolchain contains symlinks"
/usr/bin/sandbox-exec -p "$materialize_profile" /usr/bin/env -i \
  "HOME=$home_root" "LC_ALL=C" "PATH=$lean_root/bin:/usr/bin:/bin" "TMPDIR=$work_root" "TZ=UTC" \
  "$lean_root/bin/lean" --version | /usr/bin/grep -Fq 'version 4.31.0'
/usr/bin/sandbox-exec -p "$materialize_profile" /usr/bin/env -i \
  "HOME=$home_root" "LC_ALL=C" "PATH=$lean_root/bin:/usr/bin:/bin" "TMPDIR=$work_root" "TZ=UTC" \
  "$lean_root/bin/lean" --version | /usr/bin/grep -Fq 'commit 68218e876d2a38b1985b8590fff244a83c321783'
/usr/bin/sandbox-exec -p "$materialize_profile" /usr/bin/env -i \
  "HOME=$home_root" "LC_ALL=C" "PATH=$lean_root/bin:/usr/bin:/bin" "TMPDIR=$work_root" "TZ=UTC" \
  "$lean_root/bin/lake" --version | /usr/bin/grep -Fq 'Lean version 4.31.0'
echo "clean-room: materialized locked Lean sha256=$(sha256_file "$lean_root/bin/lean")"
echo "clean-room: materialized locked Lake sha256=$(sha256_file "$lean_root/bin/lake")"

/usr/bin/sandbox-exec -p "$materialize_profile" /usr/bin/env -i \
  "HOME=$home_root" "LC_ALL=C" "PATH=/usr/bin:/bin" \
  "PROOF_FORGE_ASSET_CACHE=$asset_cache" "TMPDIR=$work_root" "TZ=UTC" /usr/bin/python3 -I -S \
  "$source_root/scripts/toolchain_assets.py" \
  --lock "$source_root/toolchains.lock.json" \
  --host-lock "$source_root/host-profiles.lock.json" \
  materialize-external --destination "$external_bin"
echo "clean-room: materialized locked external asset bundle"

/bin/cp "$source_root/scripts/verify_isolation.sh" "$runner"
/bin/chmod 500 "$runner"

deny_network_profile="$(
  /usr/bin/python3 -I -S "$source_root/scripts/sandbox_policy.py" emit \
    --mode core \
    --work-root "$tmp" \
    --source-root "$source_root" \
    --home-root "$home_root" \
    --cache-root "$cache_root" \
    --tool-root "$tool_root" \
    --output-root "$output_root"
)"
localhost_profile="$(
  /usr/bin/python3 -I -S "$source_root/scripts/sandbox_policy.py" emit \
    --mode localhost \
    --work-root "$tmp" \
    --source-root "$source_root" \
    --home-root "$home_root" \
    --cache-root "$cache_root" \
    --tool-root "$tool_root" \
    --output-root "$output_root"
)"
[[ "$deny_network_profile" == *"(deny default)"* ]] || die "core profile is not deny-default"
[[ "$deny_network_profile" != *"(allow default)"* ]] || die "core profile must not allow default"
[[ "$localhost_profile" == *"(deny default)"* ]] || die "localhost profile is not deny-default"

# Negative probes against original developer HOME and parent repo.
if /usr/bin/sandbox-exec -p "$deny_network_profile" /bin/cat "$source_home/.zshrc" >/dev/null 2>&1; then
  die "deny-default policy allowed developer HOME read"
fi
if /usr/bin/sandbox-exec -p "$deny_network_profile" /bin/ls "$repo_root" >/dev/null 2>&1; then
  die "deny-default policy allowed parent repository read"
fi
if /usr/bin/sandbox-exec -p "$deny_network_profile" /bin/ls /opt/homebrew >/dev/null 2>&1; then
  die "deny-default policy allowed /opt/homebrew"
fi

probe_port_file="$tmp/network-probe.port"
/usr/bin/python3 -I -S - "$probe_port_file" <<'PY' &
import pathlib
import socket
import sys

listener = socket.socket()
listener.bind(("127.0.0.1", 0))
listener.listen(1)
pathlib.Path(sys.argv[1]).write_text(str(listener.getsockname()[1]), encoding="ascii")
connection, _ = listener.accept()
connection.close()
listener.close()
PY
probe_pid=$!
for ((attempt = 0; attempt < 50; attempt++)); do
  [[ -s "$probe_port_file" ]] && break
  /bin/sleep 0.02
done
[[ -s "$probe_port_file" ]] || die "could not start sandbox network probe"
probe_port="$(<"$probe_port_file")"
if (cd "$tmp" && /usr/bin/sandbox-exec -p "$deny_network_profile" /usr/bin/python3 -I -S -c \
    "import socket; socket.create_connection(('127.0.0.1',$probe_port),1)") >/dev/null 2>&1; then
  die "deny-default core policy allowed a localhost connection"
fi
(cd "$tmp" && /usr/bin/sandbox-exec -p "$localhost_profile" /usr/bin/python3 -I -S -c \
  "import socket; socket.create_connection(('127.0.0.1',$probe_port),1)")
wait "$probe_pid"
probe_pid=""
network_error="$tmp/network-probe.err"
if (cd "$tmp" && /usr/bin/sandbox-exec -p "$localhost_profile" /usr/bin/python3 -I -S -c \
    "import socket; socket.create_connection(('192.0.2.1',9),1)") 2>"$network_error"; then
  die "localhost-only deny-default policy allowed a non-local connection"
fi
/usr/bin/grep -Eq 'PermissionError|Operation not permitted|timed out|Errno' "$network_error" ||
  die "localhost-only policy failed without a sandbox permission denial"
echo "clean-room: deny-default sandbox verified (core=no-network, runtime=localhost-only, home/repo denied)"

common_env=(
  "HOME=$home_root"
  "XDG_CACHE_HOME=$cache_root/xdg"
  "LAKE_HOME=$cache_root/lake"
  "LAKE_CACHE_DIR=$cache_root/lake-packages"
  "LAKE_NO_CACHE=1"
  "TMPDIR=$work_root"
  "TZ=UTC"
  "LC_ALL=C"
  "SOURCE_DATE_EPOCH=0"
  "PATH=$lean_root/bin:$external_bin"
  "PROOF_FORGE_TOOL_ROOT=$external_bin"
  "PF_CLEAN_SOURCE=$source_root"
  "PF_CLEAN_OUTPUT=$output_root"
  "PF_LEAN_ROOT=$lean_root"
)

(cd "$tmp" && /usr/bin/sandbox-exec -p "$deny_network_profile" /usr/bin/env -i "${common_env[@]}" \
  /bin/bash "$runner" --internal-core)

evm_port="$(/usr/bin/python3 -I -S -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
(cd "$tmp" && /usr/bin/sandbox-exec -p "$localhost_profile" /usr/bin/env -i "${common_env[@]}" \
  "PF_EVM_PORT=$evm_port" /bin/bash "$runner" --internal-evm)

end_epoch="$(/bin/date +%s)"
duration_ms=$(( (end_epoch - start_epoch) * 1000 ))
lean_sha="$(sha256_file "$lean_root/bin/lean")"
lake_sha="$(sha256_file "$lean_root/bin/lake")"
solc_sha="$(sha256_file "$external_bin/solc")"
eligible_for_hermetic="$(/usr/bin/python3 -I -S -c 'import json,sys; print("true" if json.load(open(sys.argv[1],encoding="utf-8")).get("eligibleForHermetic") else "false")' "$host_observation")"
host_profile_id="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["profileId"])' "$host_observation" 2>/dev/null || true)"
if [[ -z "$host_profile_id" ]]; then
  host_profile_id="$(/usr/bin/python3 -I -S -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print(d.get("profile",{}).get("id") or d.get("id") or "unknown")' "$host_observation")"
fi
os_version="$(/usr/bin/python3 -I -S -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print(d.get("platform",{}).get("productVersion") or d.get("productVersion") or "unknown")' "$host_observation")"
arch_value="$(/usr/bin/python3 -I -S -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print(d.get("platform",{}).get("arch") or d.get("arch") or "arm64")' "$host_observation")"
env_digest="$(/usr/bin/python3 -I -S -c 'import hashlib,json,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$host_observation")"

# Emit schema-complete immutable EV (development clean-room; not formal hermetic).
/bin/mkdir -p "$evidence_out"
evidence_path="$evidence_out/${evidence_id}.json"
log_path="$tmp/clean-room.log"
{
  echo "commit=$commit"
  echo "archive_sha256=$archive_hash"
  echo "sandboxPolicy=deny-default"
  echo "eligibleForHermetic=$eligible_for_hermetic"
} >"$log_path"
log_sha="$(sha256_file "$log_path")"
binding_sha="$(sha256_file "$binding_file")"

/usr/bin/python3 -I -S - "$evidence_path" <<PY
import json, pathlib, sys
from pathlib import Path
sys.path.insert(0, "$source_root/scripts")
# Import by path without relying on package install.
import importlib.util
spec = importlib.util.spec_from_file_location("evidence", "$source_root/scripts/evidence.py")
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)

document = {
  "schema": "proof-forge.evidence.v1",
  "id": "$evidence_id",
  "gateId": "v2-clean-room-h1",
  "testIds": ["TST-HOST-001", "TST-ISO-001", "TST-EVIDENCE-001", "TST-TOOL-001"],
  "taskId": "TASK-D0-03/H1",
  "repository": {
    "commit": "$commit",
    "dirty": $dirty,
    "diffDigest": None,
  },
  "environment": {
    "os": "macOS $os_version",
    "arch": "$arch_value",
    "envDigest": "$env_digest",
    "cleanRoom": True,
    "cacheMode": "empty",
    "sandboxPolicy": "deny-default",
    "eligibleForHermetic": True if "$eligible_for_hermetic" == "true" else False,
    "hostProfileId": "$host_profile_id",
  },
  "toolchains": [
    {"id": "lean", "version": "4.31.0", "executableSha256": "$lean_sha"},
    {"id": "lake", "version": "4.31.0", "executableSha256": "$lake_sha"},
    {"id": "solc", "version": "0.8.34", "executableSha256": "$solc_sha"},
  ],
  "command": {
    "argv": ["scripts/verify_isolation.sh"],
    "cwdRelative": "new_design",
    "startedUtc": "$started_utc",
    "durationMs": $duration_ms,
    "exitCode": 0,
  },
  "inputs": [
    {"path": "host-bootstrap.lock", "sha256": "$host_bootstrap_sha"},
    {"path": "host-profiles.lock.json", "sha256": "$host_lock_sha"},
    {"path": "toolchains.lock.json", "sha256": "$tool_lock_sha"},
    {"path": "scripts/verify_isolation.sh", "sha256": "$isolation_sha"},
    {"path": "scripts/sandbox_policy.py", "sha256": "$sandbox_policy_sha"},
  ],
  "outputs": [
    {"path": "new-design.tar", "sha256": "$archive_hash", "size": $(/usr/bin/stat -f%z "$archive")},
    {"path": "candidate-binding.json", "sha256": "$binding_sha", "size": $(/usr/bin/stat -f%z "$binding_file")},
  ],
  "observations": [
    {"step": "stage0-development", "status": "ok", "return": None, "logicalState": None, "effects": [], "errorClass": None},
    {"step": "deny-default-sandbox", "status": "ok", "return": None, "logicalState": None, "effects": [], "errorClass": None},
    {"step": "candidate-archive-binding", "status": "ok", "return": None, "logicalState": {"archiveSha256": "$archive_hash"}, "effects": [], "errorClass": None},
    {"step": "core-build-test-repro", "status": "ok", "return": None, "logicalState": None, "effects": [], "errorClass": None},
    {"step": "evm-localhost-runtime", "status": "ok", "return": None, "logicalState": None, "effects": [], "errorClass": None},
  ],
  "result": "passed",
  "logs": [{"path": "clean-room.log", "sha256": "$log_sha", "truncated": False}],
  "bindings": {
    "candidateCommit": "$commit",
    "archiveSha256": "$archive_hash",
    "hostBootstrapSha256": "$host_bootstrap_sha",
    "hostLockSha256": "$host_lock_sha",
    "toolLockSha256": "$tool_lock_sha",
    "launcherSha256": "$launcher_sha",
    "verifierSha256": "$verifier_sha",
    "isolationHarnessSha256": "$isolation_sha",
    "sandboxPolicySha256": "$sandbox_policy_sha",
    "evidenceSchema": "proof-forge.evidence.v1",
  },
}
# If an earlier development EV id collides, allocate a unique suffix under the same day.
target = Path("$evidence_path")
if target.exists():
    stem = target.stem
    parent = target.parent
    for n in range(13, 10000):
        candidate = parent / f"EV-$(/bin/date -u +%Y%m%d)-{n:04d}.json"
        if not candidate.exists():
            target = candidate
            document["id"] = candidate.stem
            break
evidence.write_evidence(target, document)
print(f"clean-room: schema-complete evidence wrote {target}")
print(f"clean-room: evidence.eligibleForHermetic={document['environment']['eligibleForHermetic']}")
PY

echo "clean-room: ok commit=$commit archive_sha256=$archive_hash sandbox=deny-default"
if [[ "$eligible_for_hermetic" == "true" ]]; then
  echo "clean-room: host is eligibleForHermetic=true; formal TST-ISO-002 may proceed on this host"
else
  echo "clean-room: NOT formal hermetic: host eligibleForHermetic=false (PF-HOST-INELIGIBLE). H1 deny-default + binding + schema EV closed; TASK-D0-04 remains blocked until an eligible host exists."
fi

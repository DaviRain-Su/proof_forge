#!/bin/bash
set -euo pipefail

die() {
  echo "clean-room-alpha: $*" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'usage: verify_isolation.sh --development' \
    '         [--candidate-commit <oid> --candidate-tree <oid>' \
    '          --candidate-archive-sha256 <sha256>]' \
    '         [--asset-cache <absolute-path>]' \
    '' \
    'Development mode derives the committed candidate from the current checkout.' \
    'Supplying all three candidate fields additionally checks an external anchor.' \
    'The formal gate is not exposed here: it must start at Stage-0 and hand off to' \
    'a digest-bound continuation, which remains an H1 prerequisite.' >&2
  exit 2
}

require_sha256() {
  [[ ${#1} -eq 64 && "$1" != *[!0-9a-f]* ]] || die "$2 must be a lowercase SHA-256"
}

require_git_oid() {
  [[ ${#1} -eq 40 && "$1" != *[!0-9a-f]* ]] || die "$2 must be a full lowercase SHA-1 object id"
}

sha256_file() {
  local output
  output="$(/usr/bin/openssl dgst -sha256 -r "$1")"
  echo "${output%% *}"
}

run_core_gate() {
  [[ -n "${PF_CLEAN_SOURCE:-}" && -n "${PF_CLEAN_OUTPUT:-}" &&
    -n "${PF_CLEAN_WORK:-}" && -n "${PF_LEAN_ROOT:-}" &&
    -n "${PF_XCODE_PYTHON:-}" && -n "${PF_XCODE_GIT:-}" ]] ||
    die "internal clean-room environment is incomplete"
  [[ -x "$PF_XCODE_PYTHON" && -x "$PF_XCODE_GIT" ]] ||
    die "locked direct Xcode tools are unavailable"
  [[ -z "${LEAN_PATH+x}" && -z "${LEAN_SRC_PATH+x}" && -z "${ELAN_HOME+x}" ]] ||
    die "Lean or Elan environment leaked into clean room"
  [[ "$PATH" == "$PF_LEAN_ROOT/bin:$PROOF_FORGE_TOOL_ROOT" ]] ||
    die "unexpected PATH in clean room: $PATH"
  if "$PF_XCODE_GIT" --no-replace-objects -C "$PF_CLEAN_SOURCE" \
      rev-parse --show-toplevel >/dev/null 2>&1; then
    die "archive can discover a parent Git repository"
  fi

  local lake="$PF_LEAN_ROOT/bin/lake"
  local compiler="$PF_CLEAN_SOURCE/.lake/build/bin/proof-forge-next"
  local tests="$PF_CLEAN_SOURCE/.lake/build/bin/proof-forge-next-tests"
  local targets="$PF_CLEAN_OUTPUT/targets"
  local repro="$PF_CLEAN_OUTPUT/repro"

  "$PF_XCODE_PYTHON" -I -S "$PF_CLEAN_SOURCE/scripts/docs_check.py"
  "$lake" --dir "$PF_CLEAN_SOURCE" --no-cache build \
    ProofForgeV2 proof_forge_next proof_forge_next_tests
  # The CLI emission tests intentionally exercise relative build/v2 paths.
  # Keep those scratch writes in the stage-owned work root, never in source or
  # the clean-room top-level directory.
  (
    cd "$PF_CLEAN_WORK"
    "$lake" --dir "$PF_CLEAN_SOURCE" env "$tests"
  )

  /bin/mkdir -p "$targets"
  "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build testdata/valid/Standalone.lean \
    --root "$PF_CLEAN_SOURCE" --program UserStandalone.Counter --target evm -o "$targets/standalone"
  for target in evm solana near noir; do
    "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Counter.lean \
      --root "$PF_CLEAN_SOURCE" --program Examples.Counter --target "$target" -o "$targets/$target"
  done
  "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Accumulator.lean \
    --root "$PF_CLEAN_SOURCE" --program Examples.Accumulator --target evm \
    -o "$targets/evm-accumulator"
  "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Accumulator.lean \
    --root "$PF_CLEAN_SOURCE" --program Examples.Accumulator --target solana \
    -o "$targets/solana-accumulator"
  "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Accumulator.lean \
    --root "$PF_CLEAN_SOURCE" --program Examples.Accumulator --target near \
    -o "$targets/near-accumulator"
  "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Accumulator.lean \
    --root "$PF_CLEAN_SOURCE" --program Examples.Accumulator --target noir \
    -o "$targets/noir-accumulator"
  "$PF_XCODE_PYTHON" -I -S "$PF_CLEAN_SOURCE/scripts/validate_artifacts.py" "$targets"

  for run in a b; do
    for target in evm solana near noir; do
      "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Counter.lean \
        --root "$PF_CLEAN_SOURCE" --program Examples.Counter --target "$target" -o "$repro/$run/$target"
    done
    "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Accumulator.lean \
      --root "$PF_CLEAN_SOURCE" --program Examples.Accumulator --target evm \
      -o "$repro/$run/evm-accumulator"
    "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Accumulator.lean \
      --root "$PF_CLEAN_SOURCE" --program Examples.Accumulator --target solana \
      -o "$repro/$run/solana-accumulator"
    "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Accumulator.lean \
      --root "$PF_CLEAN_SOURCE" --program Examples.Accumulator --target near \
      -o "$repro/$run/near-accumulator"
    "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Accumulator.lean \
      --root "$PF_CLEAN_SOURCE" --program Examples.Accumulator --target noir \
      -o "$repro/$run/noir-accumulator"
  done
  "$PF_XCODE_PYTHON" -I -S "$PF_CLEAN_SOURCE/scripts/check_reproducibility.py" \
    "$repro/a" "$repro/b"
  echo "clean-room-alpha: docs/build/tests/target-smoke/reproducibility ok"
}

run_evm_gate() {
  local lan_probe_ip="$1"
  local expected_chain_id="$2"
  [[ "$expected_chain_id" =~ ^[1-9][0-9]{0,9}$ && "$expected_chain_id" -le 2147483647 ]] ||
    die "internal EVM gate received an invalid chain id"
  [[ -n "${PF_CLEAN_OUTPUT:-}" && -n "${PF_CLEAN_WORK:-}" &&
    -n "${PROOF_FORGE_TOOL_ROOT:-}" && -n "${PF_XCODE_PYTHON:-}" ]] ||
    die "internal EVM environment is incomplete"
  [[ "$PATH" == "$PROOF_FORGE_TOOL_ROOT" ]] ||
    die "unexpected PATH in EVM clean room: $PATH"
  [[ -x "$PF_XCODE_PYTHON" ]] || die "locked direct Xcode Python is unavailable"

  local anvil="$PROOF_FORGE_TOOL_ROOT/anvil"
  local cast="$PROOF_FORGE_TOOL_ROOT/cast"
  local bytecode_file="$PF_CLEAN_OUTPUT/targets/evm/Counter.bin"
  local log="$PF_CLEAN_WORK/anvil.log"
  local rpc="http://127.0.0.1:${PF_EVM_PORT}"
  local private_key="ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  [[ -x "$anvil" && -x "$cast" && -f "$bytecode_file" ]] || die "EVM runtime inputs are missing"

  "$anvil" --host 127.0.0.1 --port "$PF_EVM_PORT" \
    --chain-id "$expected_chain_id" --silent >"$log" 2>&1 &
  local anvil_pid=$!
  cleanup_anvil() {
    if [[ -n "$anvil_pid" ]]; then
      kill "$anvil_pid" 2>/dev/null || true
      wait "$anvil_pid" 2>/dev/null || true
      anvil_pid=""
    fi
  }
  require_anvil_running() {
    local running_jobs
    running_jobs="$(jobs -pr)"
    if [[ "$running_jobs" != "$anvil_pid" ]]; then
      wait "$anvil_pid" 2>/dev/null || true
      anvil_pid=""
      die "the launched Anvil process is not the running child; see $log"
    fi
  }
  trap cleanup_anvil EXIT

  local ready=0
  local attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    require_anvil_running
    if [[ "$("$cast" chain-id --rpc-url "$rpc" 2>/dev/null || true)" == \
        "$expected_chain_id" ]]; then
      ready=1
      break
    fi
    /bin/sleep 0.1
  done
  [[ "$ready" == 1 ]] || die "Anvil failed to start; see $log"
  /bin/sleep 0.1
  require_anvil_running
  [[ "$("$cast" chain-id --rpc-url "$rpc" 2>/dev/null || true)" == \
      "$expected_chain_id" ]] || die "Anvil identity changed after readiness"

  "$PF_XCODE_PYTHON" -I -S -c '
import errno
import ipaddress
import socket
import sys

address = ipaddress.ip_address(sys.argv[1])
if address.version != 4 or address.is_loopback or address.is_unspecified:
    raise SystemExit("invalid non-loopback probe address")
try:
    connection = socket.create_connection((str(address), int(sys.argv[2])), 0.5)
except OSError as error:
    if error.errno != errno.ECONNREFUSED:
        raise
else:
    connection.close()
    raise SystemExit("Anvil is reachable through a non-loopback interface")
' "$lan_probe_ip" "$PF_EVM_PORT"

  deploy_counter() {
    local initial="$1"
    local bytecode encoded receipt
    bytecode="$(/usr/bin/tr -d '\n\r ' < "$bytecode_file")"
    encoded="$("$cast" abi-encode 'constructor(uint64)' "$initial")"
    receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
      --create "0x${bytecode}${encoded#0x}")"
    "$PF_XCODE_PYTHON" -I -S -c \
      'import json,sys; print(json.loads(sys.argv[1])["contractAddress"])' "$receipt"
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
  require_anvil_running
  [[ "$("$cast" chain-id --rpc-url "$rpc" 2>/dev/null || true)" == \
      "$expected_chain_id" ]] || die "Anvil identity changed during the runtime gate"
  cleanup_anvil
  trap - EXIT
  echo "clean-room-alpha: EVM localhost runtime ok"
}

case "${1:-}" in
  --internal-core)
    run_core_gate
    exit 0
    ;;
  --internal-evm)
    [[ $# -eq 3 ]] || die "internal EVM gate requires LAN address and chain id"
    run_evm_gate "$2" "$3"
    exit 0
    ;;
esac

qualification=development
mode_seen=0
expected_commit=""
expected_tree=""
expected_archive_hash=""
asset_cache_arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --development)
      [[ "$mode_seen" == 0 ]] || usage
      mode_seen=1
      shift
      ;;
    --candidate-commit)
      [[ $# -ge 2 && -z "$expected_commit" ]] || usage
      expected_commit="$2"
      shift 2
      ;;
    --candidate-tree)
      [[ $# -ge 2 && -z "$expected_tree" ]] || usage
      expected_tree="$2"
      shift 2
      ;;
    --candidate-archive-sha256)
      [[ $# -ge 2 && -z "$expected_archive_hash" ]] || usage
      expected_archive_hash="$2"
      shift 2
      ;;
    --asset-cache)
      [[ $# -ge 2 && -z "$asset_cache_arg" ]] || usage
      asset_cache_arg="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ "$mode_seen" == 1 ]] || usage

if [[ -n "$expected_commit" || -n "$expected_tree" || -n "$expected_archive_hash" ]]; then
  [[ -n "$expected_commit" && -n "$expected_tree" && -n "$expected_archive_hash" ]] || usage
  require_git_oid "$expected_commit" candidate-commit
  require_git_oid "$expected_tree" candidate-tree
  require_sha256 "$expected_archive_hash" candidate-archive-sha256
fi

source_home="${HOME:?HOME is required while provisioning the locked cache}"
if [[ -n "$asset_cache_arg" ]]; then
  asset_cache="$asset_cache_arg"
else
  asset_cache="${PROOF_FORGE_ASSET_CACHE:-${XDG_CACHE_HOME:-$source_home/.cache}/proof-forge-v2/assets}"
fi
[[ "$asset_cache" == /* ]] || die "asset cache must be an absolute path"
root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd -P)"
/usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC \
  /bin/bash --noprofile --norc "$root/scripts/verify_host_stage0.sh" \
  --allow-ineligible-development
unset BASH_ENV ENV CDPATH DEVELOPER_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_DIR \
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_REPLACE_REF_BASE PYTHONHOME \
  PYTHONPATH PYTHONSTARTUP LEAN_PATH LEAN_SRC_PATH ELAN_HOME PROOF_FORGE_ASSET_CACHE \
  XDG_CACHE_HOME
export PATH=/usr/bin:/bin
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_NO_REPLACE_OBJECTS=1
export GIT_OPTIONAL_LOCKS=0
command -v /usr/bin/sandbox-exec >/dev/null 2>&1 || die "macOS sandbox-exec is unavailable"

git_bin=/Applications/Xcode.app/Contents/Developer/usr/bin/git
xcode_python=/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9
[[ -x "$git_bin" && ! -L "$git_bin" ]] || die "verified direct Git is unavailable"
[[ -x "$xcode_python" && ! -L "$xcode_python" ]] ||
  die "verified direct Xcode Python is unavailable"
repo_root="$("$git_bin" --no-replace-objects -C "$root" rev-parse --show-toplevel)"
prefix="$("$git_bin" --no-replace-objects -C "$root" rev-parse --show-prefix)"
[[ "$prefix" == new_design/ ]] || die "expected new_design/ to be a tracked subtree, got '$prefix'"
commit="$("$git_bin" --no-replace-objects -C "$repo_root" rev-parse --verify 'HEAD^{commit}')"
require_git_oid "$commit" candidate-commit
if [[ -n "$expected_commit" && "$commit" != "$expected_commit" ]]; then
  die "candidate commit mismatch: expected $expected_commit, got $commit"
fi
treeish="$commit:new_design"
[[ "$("$git_bin" --no-replace-objects -C "$repo_root" cat-file -t "$treeish" 2>/dev/null)" == tree ]] ||
  die "HEAD does not contain new_design"
tree_oid="$("$git_bin" --no-replace-objects -C "$repo_root" rev-parse --verify "$treeish")"
require_git_oid "$tree_oid" candidate-tree-object
if [[ -n "$expected_tree" && "$tree_oid" != "$expected_tree" ]]; then
  die "candidate tree mismatch: expected $expected_tree, got $tree_oid"
fi

tmp="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/proof-forge-v2-clean-room.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
/bin/chmod 700 "$tmp"
cleanup() {
  # Locked tool trees are deliberately materialized read-only. Restore only
  # owner write permission inside this private temporary root so rm can remove
  # the exact-tree directories without leaving multi-gigabyte residue.
  if [[ -n "${tool_root:-}" ]]; then
    /usr/bin/find -P "$tool_root" -type d -exec /bin/chmod u+w {} + 2>/dev/null || true
  fi
  /bin/rm -rf -- "$tmp"
}
trap cleanup EXIT

candidate_status_before_file="$tmp/candidate-status-before"
"$git_bin" --no-replace-objects -C "$repo_root" status --porcelain=v2 -z \
  --untracked-files=all -- new_design >"$candidate_status_before_file"
candidate_status_before_hash="$(sha256_file "$candidate_status_before_file")"

source_root="$tmp/source"
home_root="$tmp/home"
cache_root="$tmp/cache"
tool_root="$tmp/tools"
lean_root="$tool_root/lean"
external_bin="$tool_root/external"
output_root="$tmp/output"
work_root="$tmp/work"
policies_root="$tmp/policies"
runner="$tmp/clean-room-runner.sh"
/bin/mkdir -p "$source_root" "$home_root" "$cache_root" "$tool_root" \
  "$output_root" "$work_root" "$policies_root"
/bin/chmod 700 "$source_root" "$home_root" "$cache_root" "$tool_root" \
  "$output_root" "$work_root" "$policies_root"

archive="$tmp/new-design.tar"
"$git_bin" --no-replace-objects -C "$repo_root" archive --format=tar "$commit" -- new_design >"$archive"
archive_hash="$(sha256_file "$archive")"
archive_commit="$("$git_bin" get-tar-commit-id <"$archive")"
[[ "$archive_commit" == "$commit" ]] || die "candidate archive does not bind the selected commit"
if [[ -n "$expected_archive_hash" && "$archive_hash" != "$expected_archive_hash" ]]; then
  die "candidate archive mismatch: expected $expected_archive_hash, got $archive_hash"
fi
if "$git_bin" --no-replace-objects -C "$repo_root" ls-tree -r "$treeish" | /usr/bin/awk '$1 == "120000" || $1 == "160000" { found=1 } END { exit !found }'; then
  die "tracked symlink or submodule found in archive tree"
fi
/usr/bin/tar -tf "$archive" | while IFS= read -r entry; do
  [[ "$entry" == new_design || "$entry" == new_design/ || "$entry" == new_design/* ]] ||
    die "archive escaped the new_design subtree: $entry"
  relative_entry="${entry#new_design/}"
  [[ "$relative_entry" != /* && "$relative_entry" != ../* && "$relative_entry" != */../* ]] ||
    die "unsafe archive path: $entry"
done
/usr/bin/tar -C "$source_root" --strip-components=1 -xf "$archive"
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

/bin/mkdir -p "$source_root/.lake"
/bin/chmod 700 "$source_root/.lake"
/bin/cp "$source_root/scripts/verify_isolation.sh" "$runner"
/bin/chmod 500 "$runner"

render_policy() {
  local stage="$1"
  shift
  /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC \
    PYTHONDONTWRITEBYTECODE=1 "$xcode_python" -I -S \
    "$source_root/scripts/sandbox_policy.py" render "$stage" \
    --temp-root "$tmp" --asset-cache "$asset_cache" \
    --xcode-python "$xcode_python" --lean-root "$lean_root" \
    --external-root "$external_bin" --source-root "$source_root" "$@" \
    -o "$policies_root/$stage.sb"
}

sandbox_run() {
  /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC \
    PYTHONDONTWRITEBYTECODE=1 "$xcode_python" -I -S \
    "$source_root/scripts/sandbox_exec.py" run "$@"
}

sandbox_must_succeed() {
  local stage="$1"
  local invocation="$2"
  local stdout_receipt="$policies_root/sandbox-$stage-$invocation.stdout.log"
  local stderr_receipt="$policies_root/sandbox-$stage-$invocation.stderr.log"
  shift 2
  if sandbox_run "$stage" --invocation "$invocation" "$@"; then
    return 0
  fi
  echo "clean-room-alpha: $stage/$invocation failed" >&2
  if [[ -f "$stdout_receipt" ]]; then
    echo "clean-room-alpha: protected stdout sha256=$(sha256_file \
      "$stdout_receipt") (ASCII-escaped last 32768 bytes follow)" >&2
    "$xcode_python" -I -S -c \
      'import pathlib,sys; print(ascii(pathlib.Path(sys.argv[1]).read_bytes()[-32768:]))' \
      "$stdout_receipt" >&2 || true
  else
    echo "clean-room-alpha: launcher published no child stdout receipt" >&2
  fi
  if [[ -f "$stderr_receipt" ]]; then
    echo "clean-room-alpha: protected stderr sha256=$(sha256_file \
      "$stderr_receipt") (ASCII-escaped last 32768 bytes follow)" >&2
    "$xcode_python" -I -S -c \
      'import pathlib,sys; print(ascii(pathlib.Path(sys.argv[1]).read_bytes()[-32768:]))' \
      "$stderr_receipt" >&2 || true
  else
    echo "clean-room-alpha: launcher published no child stderr receipt" >&2
  fi
  die "$stage/$invocation did not complete"
}

expect_permission_denied() {
  local stage="$1"
  local invocation="$2"
  local stderr_receipt="$policies_root/sandbox-$stage-$invocation.stderr.log"
  shift 2
  if sandbox_run "$stage" --invocation "$invocation" --temp-root "$tmp" "$@"; then
    die "$stage/$invocation unexpectedly succeeded"
  fi
  [[ -f "$stderr_receipt" ]] || die "$stage/$invocation produced no stderr receipt"
  /usr/bin/grep -Eq 'PermissionError|Operation not permitted' "$stderr_receipt" ||
    die "$stage/$invocation failed without a sandbox permission denial"
}

render_policy materialize
echo "clean-room-alpha: materialize policy sha256=$(sha256_file "$policies_root/materialize.sb")"

source_probe="$source_root/lakefile.lean"
source_probe_hash="$(sha256_file "$source_probe")"
expect_permission_denied materialize source-write \
  --asset-cache "$asset_cache" -- "$xcode_python" -I -S -c \
  'import pathlib,sys; pathlib.Path(sys.argv[1]).write_bytes(b"mutated")' "$source_probe"
[[ "$(sha256_file "$source_probe")" == "$source_probe_hash" ]] ||
  die "materialize source-write probe changed the source"

sandbox_must_succeed materialize lean-materialize --temp-root "$tmp" \
  --asset-cache "$asset_cache" -- "$xcode_python" -I -S \
  "$source_root/scripts/toolchain_assets.py" \
  --lock "$source_root/toolchains.lock.json" \
  --host-lock "$source_root/host-profiles.lock.json" \
  materialize-lean --destination "$lean_root"
[[ -z "$(/usr/bin/find "$lean_root" -type l -print -quit)" ]] ||
  die "materialized Lean toolchain contains symlinks"

sandbox_must_succeed materialize lean-version --temp-root "$tmp" \
  --asset-cache "$asset_cache" -- "$lean_root/bin/lean" --version
/usr/bin/grep -Fq 'version 4.31.0' \
  "$policies_root/sandbox-materialize-lean-version.stdout.log"
/usr/bin/grep -Fq 'commit 68218e876d2a38b1985b8590fff244a83c321783' \
  "$policies_root/sandbox-materialize-lean-version.stdout.log"
sandbox_must_succeed materialize lake-version --temp-root "$tmp" \
  --asset-cache "$asset_cache" -- "$lean_root/bin/lake" --version
/usr/bin/grep -Fq 'Lean version 4.31.0' \
  "$policies_root/sandbox-materialize-lake-version.stdout.log"
echo "clean-room-alpha: materialized locked Lean sha256=$(sha256_file "$lean_root/bin/lean")"
echo "clean-room-alpha: materialized locked Lake sha256=$(sha256_file "$lean_root/bin/lake")"

sandbox_must_succeed materialize external-materialize --temp-root "$tmp" \
  --asset-cache "$asset_cache" -- "$xcode_python" -I -S \
  "$source_root/scripts/toolchain_assets.py" \
  --lock "$source_root/toolchains.lock.json" \
  --host-lock "$source_root/host-profiles.lock.json" \
  materialize-external --destination "$external_bin"
echo "clean-room-alpha: materialized locked external asset bundle"

render_policy core
echo "clean-room-alpha: core policy sha256=$(sha256_file "$policies_root/core.sb")"
expect_permission_denied core network \
  -- "$xcode_python" -I -S -c \
  'import socket; socket.create_connection(("127.0.0.1", 9), 0.2)'
expect_permission_denied core policy-read \
  -- "$xcode_python" -I -S -c \
  'import pathlib,sys; pathlib.Path(sys.argv[1]).read_bytes()' "$policies_root/core.sb"
source_probe_hash="$(sha256_file "$source_probe")"
expect_permission_denied core source-write \
  -- "$xcode_python" -I -S -c \
  'import pathlib,sys; pathlib.Path(sys.argv[1]).write_bytes(b"mutated")' "$source_probe"
[[ "$(sha256_file "$source_probe")" == "$source_probe_hash" ]] ||
  die "core source-write probe changed the source"
expect_permission_denied core exec \
  -- /bin/echo forbidden

sandbox_must_succeed core build-test --temp-root "$tmp" -- \
  /bin/bash "$runner" --internal-core

evm_port="$(/usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC \
  "$xcode_python" -I -S -c \
  'import socket; s=socket.socket(); s.bind(("0.0.0.0",0)); print(s.getsockname()[1]); s.close()')"
evm_chain_id="$(/usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC \
  "$xcode_python" -I -S -c \
  'import secrets; print(secrets.randbelow(2147483647) + 1)')"
lan_probe_ip="$(/usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC \
  "$xcode_python" -I -S -c '
import ipaddress
import socket

addresses = {
    item[4][0]
    for item in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)
    if not ipaddress.ip_address(item[4][0]).is_loopback
}
if not addresses:
    raise SystemExit("no non-loopback IPv4 address for runtime exposure probe")
print(sorted(addresses)[0])
')"
render_policy evm-runtime --port "$evm_port"
echo "clean-room-alpha: runtime exact-local-port policy sha256=$(sha256_file \
  "$policies_root/evm-runtime.sb")"

evm_artifact="$output_root/targets/evm/Counter.bin"
evm_artifact_hash="$(sha256_file "$evm_artifact")"
expect_permission_denied evm-runtime output-write \
  --runtime-port "$evm_port" -- "$xcode_python" -I -S -c \
  'import pathlib,sys; pathlib.Path(sys.argv[1]).write_bytes(b"mutated")' "$evm_artifact"
[[ "$(sha256_file "$evm_artifact")" == "$evm_artifact_hash" ]] ||
  die "runtime output-write probe changed the core artifact"
expect_permission_denied evm-runtime source-read \
  --runtime-port "$evm_port" -- "$xcode_python" -I -S -c \
  'import pathlib,sys; pathlib.Path(sys.argv[1]).read_bytes()' "$source_probe"
if [[ "$evm_port" -lt 65535 ]]; then
  adjacent_port=$((evm_port + 1))
else
  adjacent_port=$((evm_port - 1))
fi
expect_permission_denied evm-runtime adjacent-port \
  --runtime-port "$evm_port" -- "$xcode_python" -I -S -c \
  'import socket,sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 0.2)' \
  "$adjacent_port"
expect_permission_denied evm-runtime non-local \
  --runtime-port "$evm_port" -- "$xcode_python" -I -S -c \
  'import socket,sys; socket.create_connection(("192.0.2.1", int(sys.argv[1])), 0.2)' \
  "$evm_port"

sandbox_must_succeed evm-runtime anvil-counter --temp-root "$tmp" \
  --runtime-port "$evm_port" -- /bin/bash "$runner" --internal-evm \
  "$lan_probe_ip" "$evm_chain_id"

while IFS= read -r -d '' receipt; do
  [[ "$(/usr/bin/stat -f %Lp "$receipt")" == 400 ]] ||
    die "sandbox receipt is not mode 0400: $receipt"
  [[ "$(/usr/bin/stat -f %l "$receipt")" == 1 ]] ||
    die "sandbox receipt has multiple hard links: $receipt"
done < <(/usr/bin/find -P "$policies_root" -type f -print0)
echo "clean-room-alpha: sandbox verified (materialize/core=no-network;"
echo "clean-room-alpha: runtime=exact-local-port + 127.0.0.1 bind/LAN negative)"
echo "clean-room-alpha: sandbox engine sha256=$(sha256_file /usr/bin/sandbox-exec)"
echo "clean-room-alpha: sandbox renderer sha256=$(sha256_file \
  "$source_root/scripts/sandbox_policy.py")"
echo "clean-room-alpha: sandbox launcher sha256=$(sha256_file \
  "$source_root/scripts/sandbox_exec.py")"

[[ "$("$git_bin" --no-replace-objects -C "$repo_root" rev-parse --verify 'HEAD^{commit}')" == "$commit" ]] ||
  die "candidate HEAD changed during the gate"
[[ "$("$git_bin" --no-replace-objects -C "$repo_root" rev-parse --verify "$treeish")" == "$tree_oid" ]] ||
  die "candidate subtree changed during the gate"
candidate_status_after_file="$tmp/candidate-status-after"
"$git_bin" --no-replace-objects -C "$repo_root" status --porcelain=v2 -z \
  --untracked-files=all -- new_design >"$candidate_status_after_file"
candidate_status_after_hash="$(sha256_file "$candidate_status_after_file")"
[[ "$candidate_status_after_hash" == "$candidate_status_before_hash" ]] ||
  die "candidate worktree status changed during the gate"

echo "clean-room-alpha: ok qualification=$qualification commit=$commit tree=$tree_oid archive_sha256=$archive_hash"
echo "clean-room-alpha: NOT hermetic: deny-default development stages are integrated,"
echo "clean-room-alpha: but the host is ineligible and formal Stage-0 handoff, process-session"
echo "clean-room-alpha: containment, gate catalog, freshness/revocation/private scan/finalizer"
echo "clean-room-alpha: remain open; D0-03/D0-04 remain open"

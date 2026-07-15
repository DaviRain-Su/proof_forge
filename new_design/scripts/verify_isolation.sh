#!/bin/bash
set -euo pipefail

die() {
  echo "clean-room-alpha: $*" >&2
  exit 1
}

sha256_file() {
  local output
  output="$(/usr/bin/openssl dgst -sha256 -r "$1")"
  echo "${output%% *}"
}

copy_tree() {
  local source="$1"
  local destination="$2"
  if ! /bin/cp -cR "$source" "$destination" 2>/dev/null; then
    /bin/cp -R "$source" "$destination"
  fi
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

  /usr/bin/python3 "$PF_CLEAN_SOURCE/scripts/docs_check.py"
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
  /usr/bin/python3 "$PF_CLEAN_SOURCE/scripts/validate_artifacts.py" "$targets"

  for run in a b; do
    for target in evm solana near noir; do
      "$lake" --dir "$PF_CLEAN_SOURCE" env "$compiler" build Examples/Counter.lean \
        --root "$PF_CLEAN_SOURCE" --program Examples.Counter --target "$target" -o "$repro/$run/$target"
    done
  done
  /usr/bin/python3 "$PF_CLEAN_SOURCE/scripts/check_reproducibility.py" "$repro/a" "$repro/b"
  echo "clean-room-alpha: docs/build/tests/target-smoke/reproducibility ok"
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
    /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$receipt"
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
  echo "clean-room-alpha: EVM localhost runtime ok"
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
unset BASH_ENV ENV CDPATH DEVELOPER_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_DIR \
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_REPLACE_REF_BASE PYTHONHOME \
  PYTHONPATH PYTHONSTARTUP LEAN_PATH LEAN_SRC_PATH ELAN_HOME
export PATH=/usr/bin:/bin
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
kat_output="$(printf abc | /usr/bin/openssl dgst -sha256)"
[[ "${kat_output##* }" == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]] ||
  die "SHA-256 bootstrap known-answer test failed"

[[ "$(/usr/bin/uname -s)" == Darwin && "$(/usr/bin/uname -m)" == arm64 ]] ||
  die "this locked clean-room profile currently supports darwin-arm64 only"
command -v /usr/bin/sandbox-exec >/dev/null 2>&1 || die "macOS sandbox-exec is unavailable"

root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
repo_root="$(/usr/bin/git -C "$root" rev-parse --show-toplevel)"
prefix="$(/usr/bin/git -C "$root" rev-parse --show-prefix)"
[[ "$prefix" == new_design/ ]] || die "expected new_design/ to be a tracked subtree, got '$prefix'"
commit="$(/usr/bin/git -C "$repo_root" rev-parse HEAD)"
treeish="$commit:new_design"
[[ "$(/usr/bin/git -C "$repo_root" cat-file -t "$treeish" 2>/dev/null)" == tree ]] ||
  die "HEAD does not contain new_design"

tmp="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/proof-forge-v2-clean-room.XXXXXX")"
cleanup() {
  if [[ -n "${probe_pid:-}" ]]; then
    kill "$probe_pid" 2>/dev/null || true
    wait "$probe_pid" 2>/dev/null || true
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
runner="$tmp/clean-room-runner.sh"
/bin/mkdir -p "$source_root" "$home_root" "$cache_root" "$tool_root" "$output_root" "$tmp/work"
/bin/chmod 700 "$home_root" "$cache_root" "$tool_root" "$output_root" "$tmp/work"

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

elan="$source_home/.elan/bin/elan"
[[ -x "$elan" ]] || die "elan is required only for audited Lean toolchain provisioning"
lean_source="$(cd "$root" && "$elan" which lean)"
lake_source="$(cd "$root" && "$elan" which lake)"
lean_source_root="${lean_source%/bin/lean}"
[[ "$lake_source" == "$lean_source_root/bin/lake" ]] || die "Lean and Lake resolve to different toolchains"
copy_tree "$lean_source_root" "$tool_root/lean"
lean_root="$tool_root/lean"
[[ -z "$(/usr/bin/find "$lean_root" -type l -print -quit)" ]] || die "copied Lean toolchain contains symlinks"
[[ "$(sha256_file "$lean_source")" == "$(sha256_file "$lean_root/bin/lean")" ]] || die "Lean changed while copying"
[[ "$(sha256_file "$lake_source")" == "$(sha256_file "$lean_root/bin/lake")" ]] || die "Lake changed while copying"
"$lean_root/bin/lean" --version | /usr/bin/grep -Fq 'version 4.31.0'
"$lean_root/bin/lean" --version | /usr/bin/grep -Fq 'commit 68218e876d2a38b1985b8590fff244a83c321783'
"$lean_root/bin/lake" --version | /usr/bin/grep -Fq 'Lean version 4.31.0'
echo "clean-room-alpha: provisioned Lean sha256=$(sha256_file "$lean_root/bin/lean")"
echo "clean-room-alpha: provisioned Lake sha256=$(sha256_file "$lean_root/bin/lake")"

/usr/bin/python3 "$source_root/scripts/toolchain_assets.py" \
  --lock "$source_root/toolchains.lock.json" \
  --host-lock "$source_root/host-profiles.lock.json" \
  materialize-external --destination "$external_bin"
echo "clean-room-alpha: materialized locked external asset bundle"

/bin/cp "$source_root/scripts/verify_isolation.sh" "$runner"
/bin/chmod 500 "$runner"

escape_sandbox_string() {
  /usr/bin/python3 -c 'import sys; print(sys.argv[1].replace("\\", "\\\\").replace("\"", "\\\""))' "$1"
}
denied_home="$(escape_sandbox_string "$source_home")"
denied_repo="$(escape_sandbox_string "$repo_root")"
deny_network_profile="(version 1)(allow default)(deny network*)(deny file-read* (subpath \"/opt/homebrew\"))(deny file-write* (subpath \"/opt/homebrew\"))(deny file-read* (subpath \"$denied_home\"))(deny file-write* (subpath \"$denied_home\"))(deny file-read* (subpath \"$denied_repo\"))(deny file-write* (subpath \"$denied_repo\"))"
localhost_profile="(version 1)(allow default)(deny network*)(allow network-inbound (local ip \"localhost:*\"))(allow network-outbound (remote ip \"localhost:*\"))(deny file-read* (subpath \"/opt/homebrew\"))(deny file-write* (subpath \"/opt/homebrew\"))(deny file-read* (subpath \"$denied_home\"))(deny file-write* (subpath \"$denied_home\"))(deny file-read* (subpath \"$denied_repo\"))(deny file-write* (subpath \"$denied_repo\"))"

probe_port_file="$tmp/network-probe.port"
/usr/bin/python3 - "$probe_port_file" <<'PY' &
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
if (cd "$tmp" && /usr/bin/sandbox-exec -p "$deny_network_profile" /usr/bin/python3 -c \
    "import socket; socket.create_connection(('127.0.0.1',$probe_port),1)") >/dev/null 2>&1; then
  die "sandbox network-deny policy allowed a localhost connection"
fi
(cd "$tmp" && /usr/bin/sandbox-exec -p "$localhost_profile" /usr/bin/python3 -c \
  "import socket; socket.create_connection(('127.0.0.1',$probe_port),1)")
wait "$probe_pid"
probe_pid=""
network_error="$tmp/network-probe.err"
if (cd "$tmp" && /usr/bin/sandbox-exec -p "$localhost_profile" /usr/bin/python3 -c \
    "import socket; socket.create_connection(('192.0.2.1',9),1)") 2>"$network_error"; then
  die "localhost-only sandbox policy allowed a non-local connection"
fi
/usr/bin/grep -Eq 'PermissionError|Operation not permitted' "$network_error" ||
  die "localhost-only policy failed without a sandbox permission denial"
echo "clean-room-alpha: sandbox policy verified (core=no-network, runtime=localhost-only)"

common_env=(
  "HOME=$home_root"
  "XDG_CACHE_HOME=$cache_root/xdg"
  "LAKE_HOME=$cache_root/lake"
  "LAKE_CACHE_DIR=$cache_root/lake-packages"
  "LAKE_NO_CACHE=1"
  "TMPDIR=$tmp/work"
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

evm_port="$(/usr/bin/python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
(cd "$tmp" && /usr/bin/sandbox-exec -p "$localhost_profile" /usr/bin/env -i "${common_env[@]}" \
  "PF_EVM_PORT=$evm_port" /bin/bash "$runner" --internal-evm)

echo "clean-room-alpha: ok commit=$commit archive_sha256=$archive_hash"
echo "clean-room-alpha: NOT hermetic: Lean still comes from the elan tree, the current host profile is ineligible, and deny-default/evidence closure remain open; D0-03/D0-04 remain open"

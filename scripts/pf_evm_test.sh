#!/usr/bin/env bash
# Minimal EVM Anvil local test for `pf test -t evm` (D7c).
#
# Inputs:
#   PF_EVM_ARTIFACT_DIR  — OutputSet dir with *.bin (required)
#   PROOF_FORGE_TOOL_ROOT / FOUNDRY_BIN — locked anvil+cast root
#
# Behavior:
#   - Missing anvil/cast → skip-clean exit 0 (host-optional; not a pass claim)
#   - Tools present + assertion fail → exit 1
#   - Never fabricates results; never network-writes beyond local anvil
#
# Not formal / not mainnet / not full differential corpus.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="${PF_EVM_ARTIFACT_DIR:-${1:-}}"
if [[ -z "$artifact_dir" ]]; then
  echo "pf-evm-test: usage: PF_EVM_ARTIFACT_DIR=<dir> $0" >&2
  exit 2
fi
if [[ ! -d "$artifact_dir" ]]; then
  echo "pf-evm-test: artifact dir missing: $artifact_dir" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    ;;
  *)
    echo "pf-evm-test: skipped: unsupported host platform $(uname -s)" >&2
    exit 0
    ;;
esac

foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil="$foundry_bin/anvil"
cast="$foundry_bin/cast"

if [[ ! -x "$anvil" || ! -x "$cast" ]]; then
  echo "pf-evm-test: skipped: missing locked anvil/cast under $foundry_bin (optional; not pass)" >&2
  exit 0
fi

die() { echo "pf-evm-test: FAIL: $*" >&2; exit 1; }

# Resolve primary bytecode: prefer StateCell.bin, else first *.bin (bash3-safe).
bin_path=""
if [[ -f "$artifact_dir/StateCell.bin" ]]; then
  bin_path="$artifact_dir/StateCell.bin"
else
  bin_path="$(find "$artifact_dir" -maxdepth 1 -type f -name '*.bin' | sort | head -n 1 || true)"
  [[ -n "$bin_path" ]] || die "no *.bin under $artifact_dir (run pf build -t evm first)"
fi
[[ -s "$bin_path" ]] || die "empty bytecode: $bin_path"
program_name="$(basename "$bin_path" .bin)"

to_dec() {
  local x="$1"
  if [[ "$x" =~ ^0x[0-9a-fA-F]+$ ]]; then
    /usr/bin/python3 -I -S -c "print(int('$x', 16))" 2>/dev/null || echo "$x"
  elif [[ "$x" =~ ^([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$x"
  fi
}

require_uint_equal() {
  local actual="$1" expected="$2" message="$3" canonical
  canonical="$(to_dec "$actual")"
  [[ -n "$canonical" ]] || die "$message (empty uint, raw='$actual')"
  [[ "$canonical" == "$expected" ]] || die "$message (expected '$expected', got '$canonical' raw='$actual')"
}

# Ephemeral anvil
port="${PF_EVM_PORT:-$((18000 + RANDOM % 2000))}"
chain_id="${PF_EVM_CHAIN_ID:-31338}"
rpc="http://127.0.0.1:$port"
# Anvil default account #0
private_key="${PF_EVM_PRIVATE_KEY:-ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
log="$(mktemp "${TMPDIR:-/tmp}/pf-evm-test-anvil.XXXXXX.log")"
anvil_pid=""

cleanup() {
  if [[ -n "${anvil_pid:-}" ]]; then
    kill "$anvil_pid" 2>/dev/null || true
    wait "$anvil_pid" 2>/dev/null || true
  fi
  rm -f "$log"
}
trap cleanup EXIT

"$anvil" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" --silent >"$log" 2>&1 &
anvil_pid=$!

ready=0
for _ in $(seq 1 50); do
  if ! kill -0 "$anvil_pid" 2>/dev/null; then
    die "anvil exited before ready (see $log)"
  fi
  if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
[[ "$ready" == 1 ]] || die "anvil failed to start (see $log)"
got_chain="$("$cast" chain-id --rpc-url "$rpc")"
[[ "$(to_dec "$got_chain")" == "$chain_id" ]] || die "chain-id mismatch (got $got_chain)"

bytecode="$(tr -d '\n\r ' < "$bin_path")"
[[ -n "$bytecode" ]] || die "empty bytecode after strip"
encoded="$("$cast" abi-encode 'constructor(uint64)' 7)"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$receipt")"
[[ -n "$addr" && "$addr" != "null" ]] || die "deploy failed: $receipt"

before="$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$before" "7" "$program_name constructor/get mismatch"

sim="$("$cast" call --rpc-url "$rpc" "$addr" 'increment(uint64)(uint64)' 5)"
require_uint_equal "$sim" "12" "$program_name eth_call increment return"
# eth_call must not commit
still="$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$still" "7" "$program_name eth_call unexpectedly committed"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'increment(uint64)' 5 >/dev/null
after="$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$after" "12" "$program_name increment state"

# Minimal overflow hold (optional strength): deploy max, increment reverts, state holds
uint64_max="18446744073709551615"
enc_max="$("$cast" abi-encode 'constructor(uint64)' "$uint64_max")"
receipt_max="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${enc_max#0x}")"
addr_max="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$receipt_max")"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr_max" 'increment(uint64)' 1 >/dev/null 2>&1; then
  die "$program_name overflow increment unexpectedly succeeded"
fi
hold="$("$cast" call --rpc-url "$rpc" "$addr_max" 'get()(uint64)')"
require_uint_equal "$hold" "$uint64_max" "$program_name overflow changed state"

echo "pf-evm-test: ok program=$program_name addr=$addr path=init7+inc5+overflow-hold artifact=$artifact_dir"
echo "pf-evm-test: notes=local-anvil-only;not-formal;not-mainnet;not-full-differential"

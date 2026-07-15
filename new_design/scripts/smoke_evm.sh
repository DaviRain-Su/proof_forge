#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64}}"
anvil="$foundry_bin/anvil"
cast="$foundry_bin/cast"
port="${PF_EVM_PORT:-18545}"
rpc="http://127.0.0.1:$port"
private_key="${PF_EVM_PRIVATE_KEY:-ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
log="$root/build/v2/anvil.log"

for tool in "$anvil" "$cast"; do
  if [[ ! -x "$tool" ]]; then
    echo "evm-smoke: missing $tool" >&2
    exit 2
  fi
done

expected_hash() {
  python3 -c 'import json,sys; data=json.load(open(sys.argv[1], encoding="utf-8")); print(next(tool["executableSha256"] for tool in data["tools"] if tool["id"] == sys.argv[2]))' \
    "$root/toolchains.lock.json" "$1"
}

actual_anvil_hash="$(shasum -a 256 "$anvil" | awk '{print $1}')"
actual_cast_hash="$(shasum -a 256 "$cast" | awk '{print $1}')"
[[ "$actual_anvil_hash" == "$(expected_hash anvil)" ]]
[[ "$actual_cast_hash" == "$(expected_hash cast)" ]]

"$anvil" --version | grep -Fq '0.3.0 (5a8bd89'
"$cast" --version | grep -Fq '0.3.0 (5a8bd89'

mkdir -p "$root/build/v2"
"$anvil" --port "$port" --silent >"$log" 2>&1 &
anvil_pid=$!
cleanup() {
  kill "$anvil_pid" 2>/dev/null || true
  wait "$anvil_pid" 2>/dev/null || true
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 50); do
  if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != 1 ]]; then
  echo "evm-smoke: anvil failed to start; see $log" >&2
  exit 1
fi

deploy() {
  local initial="$1"
  local bytecode encoded receipt
  bytecode="$(tr -d '\n\r ' < "$root/build/v2/evm/Counter.bin")"
  encoded="$($cast abi-encode 'constructor(uint64)' "$initial")"
  receipt="$($cast send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x${bytecode}${encoded#0x}")"
  python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$receipt"
}

counter="$(deploy 7)"
before="$($cast call --rpc-url "$rpc" "$counter" 'get()(uint64)')"
[[ "$before" == "7" ]]
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 2 \
    "$counter" 'increment(uint64)' 5 >/dev/null 2>&1; then
  echo "evm-smoke: nonpayable increment unexpectedly accepted value" >&2
  exit 1
fi
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$counter" 'increment(uint64)' 5 >/dev/null
after="$($cast call --rpc-url "$rpc" "$counter" 'get()(uint64)')"
[[ "$after" == "12" ]]
balance="$($cast balance --rpc-url "$rpc" "$counter")"
[[ "$balance" == "0" ]]

bytecode="$(tr -d '\n\r ' < "$root/build/v2/evm/Counter.bin")"
encoded="$($cast abi-encode 'constructor(uint64)' 7)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 1 --create \
    "0x${bytecode}${encoded#0x}" >/dev/null 2>&1; then
  echo "evm-smoke: nonpayable constructor unexpectedly accepted value" >&2
  exit 1
fi

max_counter="$(deploy 18446744073709551615)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$max_counter" 'increment(uint64)' 1 >/dev/null 2>&1; then
  echo "evm-smoke: overflow transaction unexpectedly succeeded" >&2
  exit 1
fi
preserved="$($cast call --rpc-url "$rpc" "$max_counter" 'get()(uint64)')"
[[ "$preserved" == "18446744073709551615" ]]

echo "evm-smoke: ok (nonpayable enforced, initial=7, increment=12, overflow preserved max)"

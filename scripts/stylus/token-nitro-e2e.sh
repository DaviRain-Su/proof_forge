#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"
endpoint="${PROOF_FORGE_STYLUS_ENDPOINT:-http://127.0.0.1:8547}"
wasm="$root/build/stylus/token/token.wasm"
evidence="$root/build/evidence/stylus/token"

[[ "$endpoint" == "http://127.0.0.1:8547" ]] || {
  echo "stylus-token-nitro-e2e: local Nitro E2E only accepts http://127.0.0.1:8547" >&2
  exit 1
}
command -v cast >/dev/null || { echo "stylus-token-nitro-e2e: cast is required" >&2; exit 1; }

just --justfile "$root/justfile" stylus-token-evm-interop
key_path="${PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH:-$("$root/tools/stylus-nitro/manage.sh" key)}"
key="$(tr -d '[:space:]' < "$key_path")"
alice="$(cast wallet address --private-key "$key")"
bob="0x$(printf '22%.0s' {1..20})"
spender_key="${PROOF_FORGE_STYLUS_SPENDER_PRIVATE_KEY:-0x$(printf '0%.0s' {1..63})2}"
spender="$(cast wallet address --private-key "$spender_key")"

PROOF_FORGE_STYLUS_WASM="$wasm" "$root/scripts/stylus/nitro-deploy.sh"
address="$(tr -d '[:space:]' < "$root/build/stylus/nitro/address")"
mkdir -p "$evidence"

# Fund the deterministic local-only spender so it can submit transferFrom.
cast send --json --rpc-url "$endpoint" --private-key "$key" "$spender" \
  --value 1ether > "$evidence/fund-spender.json"

cast send --json --rpc-url "$endpoint" --private-key "$key" "$address" \
  "mint(address,uint256)" "$alice" 100 > "$evidence/mint.json"
cast send --json --rpc-url "$endpoint" --private-key "$key" "$address" \
  "transfer(address,uint256)" "$bob" 30 > "$evidence/transfer.json"
cast send --json --rpc-url "$endpoint" --private-key "$key" "$address" \
  "approve(address,uint256)" "$spender" 40 > "$evidence/approve.json"

cast send --json --rpc-url "$endpoint" --private-key "$spender_key" "$address" \
  "transferFrom(address,address,uint256)" "$alice" "$bob" 25 > "$evidence/transfer-from.json"

alice_balance="$(cast call --rpc-url "$endpoint" "$address" "balanceOf(address)(uint256)" "$alice")"
bob_balance="$(cast call --rpc-url "$endpoint" "$address" "balanceOf(address)(uint256)" "$bob")"
remaining="$(cast call --rpc-url "$endpoint" "$address" "allowance(address,address)(uint256)" "$alice" "$spender")"

python3 - "$address" "$alice_balance" "$bob_balance" "$remaining" "$evidence/summary.json" <<'PY'
import json
import sys

address, alice, bob, allowance, output = sys.argv[1:]
decode = lambda value: int(value, 16) if value.startswith("0x") else int(value.split()[0])
summary = {
    "address": address,
    "aliceBalance": decode(alice),
    "bobBalance": decode(bob),
    "allowance": decode(allowance),
}
assert summary["aliceBalance"] == 45
assert summary["bobBalance"] == 55
assert summary["allowance"] == 15
with open(output, "w", encoding="utf-8") as stream:
    json.dump(summary, stream, sort_keys=True)
    stream.write("\n")
print(f"stylus-token-nitro-e2e: ok ({address})")
PY

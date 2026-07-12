#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"
endpoint="${PROOF_FORGE_STYLUS_ENDPOINT:-http://127.0.0.1:8547}"
wasm="$root/build/stylus/value-vault-canonical/value-vault.wasm"
evidence="$root/build/evidence/stylus/value-vault"

[[ "$endpoint" == "http://127.0.0.1:8547" ]] || {
  echo "stylus-value-vault-nitro-e2e: local Nitro E2E only accepts http://127.0.0.1:8547" >&2
  exit 1
}
command -v cast >/dev/null || { echo "stylus-value-vault-nitro-e2e: cast is required" >&2; exit 1; }

just --justfile "$root/justfile" stylus-value-vault-canonical
key_path="${PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH:-$("$root/tools/stylus-nitro/manage.sh" key)}"
key="$(tr -d '[:space:]' < "$key_path")"
PROOF_FORGE_STYLUS_WASM="$wasm" "$root/scripts/stylus/nitro-deploy.sh"
address="$(tr -d '[:space:]' < "$root/build/stylus/nitro/address")"

mkdir -p "$evidence"
cast send --json --rpc-url "$endpoint" --private-key "$key" "$address" \
  "initialize(uint64)" 5 > "$evidence/initialize.json"
cast send --json --rpc-url "$endpoint" --private-key "$key" "$address" \
  "charge_fee(uint64,uint64)" 1000 100 > "$evidence/charge-fee.json"
cast send --json --rpc-url "$endpoint" --private-key "$key" "$address" \
  "release(uint64)" 3 > "$evidence/release.json"
balance="$(cast call --rpc-url "$endpoint" "$address" "get_balance()(uint64)")"
net="$(cast call --rpc-url "$endpoint" "$address" "get_net_value()(uint64)")"

python3 - "$address" "$balance" "$net" "$evidence/summary.json" <<'PY'
import json
import sys

address, balance, net, output = sys.argv[1:]
decode = lambda value: int(value, 16) if value.startswith("0x") else int(value)
assert decode(balance) == 992
assert decode(net) == 982
with open(output, "w", encoding="utf-8") as stream:
    json.dump({"address": address, "balance": decode(balance), "net": decode(net)}, stream, sort_keys=True)
    stream.write("\n")
print(f"stylus-value-vault-nitro-e2e: ok ({address})")
PY

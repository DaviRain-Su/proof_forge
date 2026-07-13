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
"$root/scripts/stylus/require-nitro-ready.sh" stylus-value-vault-nitro-e2e

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
chain_id="$(cast chain-id --rpc-url "$endpoint")"

python3 - "$address" "$balance" "$net" "$chain_id" "$wasm" "$evidence" \
  "$evidence/summary.json" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

address, balance, net, chain_id, wasm, evidence_dir, output = sys.argv[1:]
decode = lambda value: int(value, 16) if value.startswith("0x") else int(value)
assert decode(balance) == 992
assert decode(net) == 982
transactions = {}
for name in ("initialize", "charge-fee", "release"):
    receipt = json.loads((Path(evidence_dir) / f"{name}.json").read_text())
    assert receipt.get("status") in ("0x1", 1, "1")
    transaction_hash = receipt.get("transactionHash")
    assert isinstance(transaction_hash, str) and transaction_hash.startswith("0x")
    transactions[name] = transaction_hash
summary = {
    "schema": "proof-forge.stylus.nitro-gate.v1",
    "gate": "valueVault",
    "state": "passed",
    "skipped": False,
    "provenance": "nitro-testnode",
    "chainId": int(chain_id),
    "addresses": {"valueVault": address},
    "transactions": transactions,
    "results": {"balance": decode(balance), "net": decode(net)},
    "artifacts": {"wasmSha256": hashlib.sha256(Path(wasm).read_bytes()).hexdigest()},
}
Path(output).write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
print(f"stylus-value-vault-nitro-e2e: ok ({address})")
PY

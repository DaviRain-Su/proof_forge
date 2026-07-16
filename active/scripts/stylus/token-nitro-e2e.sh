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
"$root/scripts/stylus/require-nitro-ready.sh" stylus-token-nitro-e2e

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
chain_id="$(cast chain-id --rpc-url "$endpoint")"
transfer_topic="$(cast keccak 'Transfer(address,address,uint256)')"
approval_topic="$(cast keccak 'Approval(address,address,uint256)')"

python3 - "$address" "$alice_balance" "$bob_balance" "$remaining" "$chain_id" \
  "$wasm" "$transfer_topic" "$approval_topic" "$evidence" \
  "$evidence/summary.json" "$evidence/mapping-events-summary.json" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

address, alice, bob, allowance, chain_id, wasm, transfer_topic, approval_topic, evidence_dir, output, mapping_output = sys.argv[1:]
decode = lambda value: int(value, 16) if value.startswith("0x") else int(value.split()[0])
results = {"aliceBalance": decode(alice), "bobBalance": decode(bob), "allowance": decode(allowance)}
assert results == {"aliceBalance": 45, "bobBalance": 55, "allowance": 15}
transactions = {}
receipts = {}
for name in ("mint", "transfer", "approve", "transfer-from"):
    receipt = json.loads((Path(evidence_dir) / f"{name}.json").read_text())
    assert receipt.get("status") in ("0x1", 1, "1")
    transaction_hash = receipt.get("transactionHash")
    assert isinstance(transaction_hash, str) and transaction_hash.startswith("0x")
    transactions[name] = transaction_hash
    receipts[name] = receipt

def topics(receipt):
    return {log["topics"][0].lower() for log in receipt.get("logs", []) if log.get("topics")}

assert transfer_topic.lower() in topics(receipts["mint"])
assert transfer_topic.lower() in topics(receipts["transfer"])
assert approval_topic.lower() in topics(receipts["approve"])
assert transfer_topic.lower() in topics(receipts["transfer-from"])
artifact = {"wasmSha256": hashlib.sha256(Path(wasm).read_bytes()).hexdigest()}
base = {
    "schema": "proof-forge.stylus.nitro-gate.v1",
    "state": "passed",
    "skipped": False,
    "provenance": "nitro-testnode",
    "chainId": int(chain_id),
    "addresses": {"token": address},
    "transactions": transactions,
    "artifacts": artifact,
}
summary = {**base, "gate": "token", "results": results}
mapping = {**base, "gate": "mappingEvents", "results": {
    "transferTopic": transfer_topic.lower(), "approvalTopic": approval_topic.lower()}}
Path(output).write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
Path(mapping_output).write_text(json.dumps(mapping, indent=2, sort_keys=True) + "\n")
print(f"stylus-token-nitro-e2e: ok ({address})")
PY

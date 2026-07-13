#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"
endpoint="${PROOF_FORGE_STYLUS_ENDPOINT:-http://127.0.0.1:8547}"
out="$root/build/stylus/nitro-aggregate"
evidence="$root/build/evidence/stylus/aggregate"
missing_evidence="$out/unavailable-evidence.json"

[[ "$endpoint" == "http://127.0.0.1:8547" ]] || {
  echo "stylus-aggregate-nitro-e2e: local Nitro E2E only accepts http://127.0.0.1:8547" >&2
  exit 1
}
command -v cast >/dev/null || { echo "stylus-aggregate-nitro-e2e: cast is required" >&2; exit 1; }

cd "$root"
lake build proof-forge Examples.Product.Aggregate
rm -rf "$out"
mkdir -p "$out" "$evidence"
PROOF_FORGE_STYLUS_EVIDENCE="$missing_evidence" \
  lake env proof-forge build --target wasm-arbitrum-stylus --root . \
    -o "$out/contract" Examples/Product/Aggregate.lean
PROOF_FORGE_STYLUS_WASM="$out/contract/contract.wasm" "$root/scripts/stylus/nitro-deploy.sh"
address="$(tr -d '[:space:]' < "$root/build/stylus/nitro/address")"
cp "$root/build/stylus/nitro/deploy.log" "$evidence/deploy.log"
key_path="${PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH:-$("$root/tools/stylus-nitro/manage.sh" key)}"
key="$(tr -d '[:space:]' < "$key_path")"

bytes_data="$(cast calldata 'echo_bytes(bytes)' 0x68656c6c6f)"
string_data="$(cast calldata 'echo_string(string)' hello)"
fixed_data="$(cast calldata 'echo_fixed(uint64[2])' '[7,9]')"
cast send --json --rpc-url "$endpoint" --private-key "$key" "$address" \
  --data "$bytes_data" > "$evidence/echo-bytes.json"
cast send --json --rpc-url "$endpoint" --private-key "$key" "$address" \
  --data "$string_data" > "$evidence/echo-string.json"
cast send --json --rpc-url "$endpoint" --private-key "$key" "$address" \
  --data "$fixed_data" > "$evidence/echo-fixed.json"
bytes_result="$(cast call --rpc-url "$endpoint" "$address" --data "$bytes_data")"
string_result="$(cast call --rpc-url "$endpoint" "$address" --data "$string_data")"
fixed_result="$(cast call --rpc-url "$endpoint" "$address" --data "$fixed_data")"
bytes_expected="$(cast abi-encode 'f(bytes)' 0x68656c6c6f)"
string_expected="$(cast abi-encode 'f(string)' hello)"
fixed_expected="$(cast abi-encode 'f(uint64[2])' '[7,9]')"
chain_id="$(cast chain-id --rpc-url "$endpoint")"

python3 - "$address" "$chain_id" "$out/contract/contract.wasm" \
  "$bytes_result" "$bytes_expected" "$string_result" "$string_expected" \
  "$fixed_result" "$fixed_expected" "$evidence" "$evidence/summary.json" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

(address, chain_id, wasm, bytes_result, bytes_expected, string_result,
 string_expected, fixed_result, fixed_expected, evidence_dir, output) = sys.argv[1:]
normalize = lambda value: value.strip().lower().removeprefix("0x")
assert normalize(bytes_result) == normalize(bytes_expected)
assert normalize(string_result) == normalize(string_expected)
assert normalize(fixed_result) == normalize(fixed_expected)
receipts = {}
for name in ("echo-bytes", "echo-string", "echo-fixed"):
    receipt = json.loads((Path(evidence_dir) / f"{name}.json").read_text())
    assert receipt.get("status") in ("0x1", 1, "1")
    transaction_hash = receipt.get("transactionHash")
    assert isinstance(transaction_hash, str) and transaction_hash.startswith("0x")
    receipts[name] = transaction_hash
summary = {
    "schema": "proof-forge.stylus.nitro-gate.v1",
    "gate": "aggregate",
    "state": "passed",
    "skipped": False,
    "provenance": "nitro-testnode",
    "chainId": int(chain_id),
    "addresses": {"aggregate": address},
    "transactions": receipts,
    "results": {
        "echoBytes": bytes_result,
        "echoString": string_result,
        "echoFixed": fixed_result,
    },
    "artifacts": {"wasmSha256": hashlib.sha256(Path(wasm).read_bytes()).hexdigest()},
}
Path(output).write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
print(f"stylus-aggregate-nitro-e2e: ok ({address})")
PY

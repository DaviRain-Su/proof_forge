#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"
endpoint="${PROOF_FORGE_STYLUS_ENDPOINT:-http://127.0.0.1:8547}"
out="$root/build/stylus/nitro-remote"
evidence="$root/build/evidence/stylus/remote-call"
missing_evidence="$out/unavailable-evidence.json"

[[ "$endpoint" == "http://127.0.0.1:8547" ]] || {
  echo "stylus-remote-call-nitro-e2e: local Nitro E2E only accepts http://127.0.0.1:8547" >&2
  exit 1
}
command -v cast >/dev/null || { echo "stylus-remote-call-nitro-e2e: cast is required" >&2; exit 1; }
"$root/scripts/stylus/require-nitro-ready.sh" stylus-remote-call-nitro-e2e

cd "$root"
lake build proof-forge Examples.Backend.Stylus.RemoteCallee Examples.Product.RemoteCall
rm -rf "$out"
mkdir -p "$out" "$evidence"

PROOF_FORGE_STYLUS_EVIDENCE="$missing_evidence" \
  lake env proof-forge build --target wasm-arbitrum-stylus --root . \
    -o "$out/callee" Examples/Backend/Stylus/RemoteCallee.lean
PROOF_FORGE_STYLUS_WASM="$out/callee/contract.wasm" "$root/scripts/stylus/nitro-deploy.sh"
callee="$(tr -d '[:space:]' < "$root/build/stylus/nitro/address")"
cp "$root/build/stylus/nitro/deploy.log" "$evidence/callee-deploy.log"

PROOF_FORGE_STYLUS_EVIDENCE="$missing_evidence" \
  lake env proof-forge build --target wasm-arbitrum-stylus --root . \
    --peer "peer.callee=$callee" -o "$out/caller" Examples/Product/RemoteCall.lean
PROOF_FORGE_STYLUS_WASM="$out/caller/contract.wasm" "$root/scripts/stylus/nitro-deploy.sh"
caller="$(tr -d '[:space:]' < "$root/build/stylus/nitro/address")"
cp "$root/build/stylus/nitro/deploy.log" "$evidence/caller-deploy.log"

key_path="${PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH:-$("$root/tools/stylus-nitro/manage.sh" key)}"
key="$(tr -d '[:space:]' < "$key_path")"
cast send --json --rpc-url "$endpoint" --private-key "$key" "$caller" \
  "call_remote()" > "$evidence/call-remote.json"
result="$(cast call --rpc-url "$endpoint" "$caller" "call_remote()(uint64)")"
chain_id="$(cast chain-id --rpc-url "$endpoint")"

python3 - "$caller" "$callee" "$result" "$chain_id" \
  "$out/caller/contract.wasm" "$out/callee/contract.wasm" \
  "$evidence/call-remote.json" "$evidence/summary.json" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

caller, callee, result, chain_id, caller_wasm, callee_wasm, receipt_path, output = sys.argv[1:]
decode = lambda value: int(value, 16) if value.startswith("0x") else int(value.split()[0])
assert decode(result) == 42
receipt = json.loads(Path(receipt_path).read_text())
status = receipt.get("status")
assert status in ("0x1", 1, "1")
transaction_hash = receipt.get("transactionHash")
assert isinstance(transaction_hash, str) and transaction_hash.startswith("0x")
summary = {
    "schema": "proof-forge.stylus.nitro-gate.v1",
    "gate": "remoteCall",
    "state": "passed",
    "skipped": False,
    "provenance": "nitro-testnode",
    "chainId": int(chain_id),
    "addresses": {"caller": caller, "callee": callee},
    "transactions": {"callRemote": transaction_hash},
    "results": {"callRemote": decode(result)},
    "artifacts": {
        "callerWasmSha256": hashlib.sha256(Path(caller_wasm).read_bytes()).hexdigest(),
        "calleeWasmSha256": hashlib.sha256(Path(callee_wasm).read_bytes()).hexdigest(),
    },
}
Path(output).write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
print(f"stylus-remote-call-nitro-e2e: ok ({caller} -> {callee})")
PY

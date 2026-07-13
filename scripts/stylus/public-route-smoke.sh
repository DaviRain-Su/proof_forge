#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/stylus/public-route"
TOKEN_OUT="$ROOT/build/stylus/public-token-route"
export PATH="$HOME/.foundry/bin:$PATH"
cd "$ROOT"

lake build proof-forge
rm -rf "$OUT"
rm -rf "$OUT".bundle-tmp-*
lake env proof-forge build --target wasm-arbitrum-stylus --root . \
  -o "$OUT" Examples/Product/Counter.lean

python3 - "$OUT" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
data = json.loads((root / "proof-forge-artifact.json").read_text())
assert data["target"] == "wasm-arbitrum-stylus"
bundle = data["artifactBundle"]
assert bundle["finalOutput"] is None
assert data["plan"]["selectors"] == {
    "initialize": "8129fc1c", "increment": "d09de08a", "get": "6d4ce63c"
}
for output in bundle["outputs"]:
    path = root / output["path"]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == output["sha256"]
assert (root / "contract.wasm").read_bytes()[:4] == b"\x00asm"
assert json.loads((root / "proof-forge-abi.json").read_text())[0]["name"] == "initialize"
assert "export const ABI" in (root / "proof-forge-client.ts").read_text()
deploy = json.loads((root / "proof-forge-deploy.json").read_text())
assert deploy["broadcast"] is False and deploy["activationValidation"] == "notRun"
assert not list(root.parent.glob(root.name + ".bundle-tmp-*"))
print("stylus-public-route-artifact: ok")
PY

rm -rf "$TOKEN_OUT"
rm -rf "$TOKEN_OUT".bundle-tmp-*
lake env proof-forge build --target wasm-arbitrum-stylus --token --root . \
  -o "$TOKEN_OUT" Examples/Product/FungibleToken.lean

python3 - "$TOKEN_OUT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
artifact = json.loads((root / "proof-forge-artifact.json").read_text())
assert artifact["target"] == "wasm-arbitrum-stylus"
selectors = artifact["plan"]["selectors"]
assert selectors["transfer"] == "a9059cbb"
assert selectors["approve"] == "095ea7b3"
assert selectors["transferFrom"] == "23b872dd"
abi = json.loads((root / "proof-forge-abi.json").read_text())
assert {entry["name"] for entry in abi} >= {
    "totalSupply", "balanceOf", "transfer", "allowance", "approve", "transferFrom"
}
client = (root / "proof-forge-client.ts").read_text()
assert "export async function transfer(recipient: string, amount: bigint)" in client
assert "export async function approve(spender: string, amount: bigint)" in client
assert "export async function transferFrom(src: string, dst: string, amount: bigint)" in client
assert (root / "contract.wasm").read_bytes()[:4] == b"\x00asm"
print("stylus-public-token-route: ok")
PY

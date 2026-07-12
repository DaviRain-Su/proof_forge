#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/stylus/public-route"
export PATH="$HOME/.foundry/bin:$PATH"
cd "$ROOT"

lake build proof-forge
rm -rf "$OUT"
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
assert not (root / "contract.wasm").exists()
print("stylus-public-route-artifact: ok")
PY

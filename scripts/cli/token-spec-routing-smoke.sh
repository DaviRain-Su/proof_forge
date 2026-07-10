#!/usr/bin/env bash
# wasm-near build auto-detects TokenSpec modules without requiring --token.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="${PROOF_FORGE_TOKEN_SPEC_ROUTING_OUT:-build/cli/token-spec-routing}"
rm -rf "$OUT"
mkdir -p "$OUT"

lake build proof-forge >/dev/null

ARTIFACT_DIR="$OUT/FungibleToken.bare"
lake env proof-forge build --target wasm-near --root . \
  -o "$ARTIFACT_DIR" Examples/Product/FungibleToken.lean >/dev/null

test -s "$ARTIFACT_DIR/prf.wasm"
test -s "$ARTIFACT_DIR/PRF.contract-spec.json"
test -s "$ARTIFACT_DIR/proof-forge-artifact.json"

python3 - "$ARTIFACT_DIR" <<'PY'
import json
import pathlib
import sys

artifact_dir = pathlib.Path(sys.argv[1])
spec = json.loads((artifact_dir / "PRF.contract-spec.json").read_text())
artifact = json.loads((artifact_dir / "proof-forge-artifact.json").read_text())

assert spec["name"] == "PRF", spec
assert artifact["target"] == "wasm-near", artifact
assert artifact["sourceKind"] == "contract-sdk", artifact
assert artifact["sourceModule"] == "PRF", artifact
PY

echo "token-spec-routing: ok (bare TokenSpec auto-detected for wasm-near)"

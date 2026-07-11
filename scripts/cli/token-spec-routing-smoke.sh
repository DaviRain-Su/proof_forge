#!/usr/bin/env bash
# TokenSpec modules: bare build on non-NEAR targets must fail closed and point to --token.
# On wasm-near, P0-NEAR-1 auto-detection makes bare build succeed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="${PROOF_FORGE_TOKEN_SPEC_ROUTING_OUT:-build/cli/token-spec-routing}"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() {
  echo "token-spec-routing: $*" >&2
  exit 1
}

lake build proof-forge >/dev/null

# EVM: bare TokenSpec build must fail and recommend --token.
set +e
err="$(lake env proof-forge build --target evm --root . \
  -o "$OUT/FungibleToken.bare" Examples/Product/FungibleToken.lean 2>&1)"
status=$?
set -e

[[ "$status" -ne 0 ]] || fail "bare TokenSpec EVM build unexpectedly succeeded"
echo "$err" | grep -Fq "not ContractSpec" || \
  fail "bare TokenSpec EVM diagnostic did not identify the ContractSpec mismatch: $err"
echo "$err" | grep -Fq -- "--token" || \
  fail "bare TokenSpec EVM diagnostic did not recommend --token: $err"
[[ ! -e "$OUT/FungibleToken.bare" ]] || \
  fail "bare TokenSpec EVM build wrote an artifact despite failing"

# NEAR: bare TokenSpec build succeeds and emits the complete artifact set.
ARTIFACT_DIR="$OUT/FungibleToken.near"
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

echo "token-spec-routing: ok"

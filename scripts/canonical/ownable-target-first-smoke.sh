#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

OUT="${OWNABLE_TARGET_FIRST_OUT:-build/canonical/ownable-target-first}"
SOURCE=Examples/Product/Ownable.lean

fail() {
  printf 'ownable-target-first: %s\n' "$1" >&2
  exit 1
}

for tool in lake python3 solc cast wat2wasm; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

rm -rf "$OUT"
mkdir -p "$OUT/evm" "$OUT/solana" "$OUT/near"

lake build proof-forge Examples.Product.Ownable >/dev/null

lake env proof-forge build --target evm --root . \
  -o "$OUT/evm/Ownable.bin" \
  --yul-output "$OUT/evm/Ownable.yul" \
  --artifact-output "$OUT/evm/Ownable.proof-forge-artifact.json" \
  "$SOURCE"
python3 scripts/evm/validate-artifact-metadata.py \
  --root "$ROOT" \
  --expect-fixture Ownable \
  --expect-source-kind contract-source-authored \
  --expect-entrypoint init:e1c7392a \
  --expect-entrypoint owner:8da5cb5b \
  --expect-entrypoint transferOwnership:f2fde38b \
  --expect-entrypoint renounceOwnership:715018a6 \
  "$OUT/evm/Ownable.proof-forge-artifact.json"
cmp Examples/Backend/Evm/Contracts/stdlib/Ownable.golden.yul "$OUT/evm/Ownable.yul" ||
  fail 'direct EVM Yul differs from the reviewed golden'
rg -q 'caller\(\)' "$OUT/evm/Ownable.yul" || fail 'EVM artifact lost caller authorization'

lake env proof-forge build --target solana-sbpf-asm --format s --root . \
  -o "$OUT/solana/Ownable.s" \
  --artifact-output "$OUT/solana/Ownable.proof-forge-artifact.json" \
  "$SOURCE"
rg -q 'authority' "$OUT/solana/Ownable.s" || fail 'Solana artifact lost signer authority'
rg -q 'assert' "$OUT/solana/Ownable.s" || fail 'Solana artifact lost authorization assertions'

lake env proof-forge build --target wasm-near --root . \
  -o "$OUT/near" \
  --artifact-output "$OUT/near/Ownable.proof-forge-artifact.json" \
  "$SOURCE"
python3 scripts/near/validate-emitwat-metadata.py \
  "$OUT/near/Ownable.proof-forge-artifact.json" \
  --expected-fixture ownable \
  --expected-module Ownable \
  --expected-entrypoints init,owner,transferOwnership,renounceOwnership \
  --expected-source-kind contract-source-authored
test -s "$OUT/near/ownable.wasm" || fail 'NEAR final Wasm artifact is missing'

python3 - "$OUT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
artifacts = [
    ("evm", root / "evm/Ownable.proof-forge-artifact.json"),
    ("solana-sbpf-asm", root / "solana/Ownable.proof-forge-artifact.json"),
    ("wasm-near", root / "near/Ownable.proof-forge-artifact.json"),
]
for target, path in artifacts:
    artifact = json.loads(path.read_text())
    assert artifact["target"] == target, (path, artifact.get("target"))
    assert artifact["sourceKind"] == "contract-source-authored", path
    assert artifact["sourceModule"] == "Ownable", path
    assert artifact["irVersion"] == "canonical-core-v1", path

retired = list(root.rglob("*contract-spec*")) + list(root.rglob("*ir-module*"))
assert not retired, f"retired compatibility sidecars emitted: {retired}"
PY

printf 'ownable-target-first: ok\n'

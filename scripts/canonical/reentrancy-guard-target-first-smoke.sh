#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

OUT="${REENTRANCY_GUARD_TARGET_FIRST_OUT:-build/canonical/reentrancy-guard-target-first}"
SOURCE=Examples/Product/ReentrancyGuard.lean

fail() {
  printf 'reentrancy-guard-target-first: %s\n' "$1" >&2
  exit 1
}

for tool in lake python3 solc cast wat2wasm; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

rm -rf "$OUT"
mkdir -p "$OUT/evm" "$OUT/solana" "$OUT/near"

lake build proof-forge Examples.Product.ReentrancyGuard >/dev/null

lake env proof-forge build --target evm --root . \
  -o "$OUT/evm/ReentrancyGuard.bin" \
  --yul-output "$OUT/evm/ReentrancyGuard.yul" \
  --artifact-output "$OUT/evm/ReentrancyGuard.proof-forge-artifact.json" \
  "$SOURCE"
python3 scripts/evm/validate-artifact-metadata.py \
  --root "$ROOT" \
  --expect-fixture ReentrancyGuard \
  --expect-source-kind contract-source-authored \
  --expect-entrypoint acquire:a7134f73 \
  --expect-entrypoint release:86d1a69f \
  --expect-entrypoint locked:cf309012 \
  "$OUT/evm/ReentrancyGuard.proof-forge-artifact.json"
cmp Examples/Backend/Evm/Contracts/stdlib/ReentrancyGuard.golden.yul \
    "$OUT/evm/ReentrancyGuard.yul" ||
  fail 'direct EVM Yul differs from the reviewed golden'

lake env proof-forge build --target solana-sbpf-asm --format s --root . \
  -o "$OUT/solana/ReentrancyGuard.s" \
  --artifact-output "$OUT/solana/ReentrancyGuard.proof-forge-artifact.json" \
  "$SOURCE"
rg -q 'assert_fail' "$OUT/solana/ReentrancyGuard.s" ||
  fail 'Solana artifact lost lock guards'
rg -q 'stxdw \[r1\+96\]' "$OUT/solana/ReentrancyGuard.s" ||
  fail 'Solana artifact lost lock-state writes'

lake env proof-forge build --target wasm-near --root . \
  -o "$OUT/near" \
  --artifact-output "$OUT/near/ReentrancyGuard.proof-forge-artifact.json" \
  "$SOURCE"
python3 scripts/near/validate-emitwat-metadata.py \
  "$OUT/near/ReentrancyGuard.proof-forge-artifact.json" \
  --expected-fixture reentrancyguard \
  --expected-module ReentrancyGuard \
  --expected-entrypoints acquire,release,locked \
  --expected-source-kind contract-source-authored
test -s "$OUT/near/reentrancyguard.wasm" ||
  fail 'NEAR final Wasm artifact is missing'

python3 - "$OUT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
artifacts = [
    ("evm", root / "evm/ReentrancyGuard.proof-forge-artifact.json"),
    ("solana-sbpf-asm", root / "solana/ReentrancyGuard.proof-forge-artifact.json"),
    ("wasm-near", root / "near/ReentrancyGuard.proof-forge-artifact.json"),
]
for target, path in artifacts:
    artifact = json.loads(path.read_text())
    assert artifact["target"] == target, (path, artifact.get("target"))
    assert artifact["sourceKind"] == "contract-source-authored", path
    assert artifact["sourceModule"] == "ReentrancyGuard", path
    assert artifact["irVersion"] == "canonical-core-v1", path

retired = list(root.rglob("*contract-spec*")) + list(root.rglob("*ir-module*"))
assert not retired, f"retired compatibility sidecars emitted: {retired}"
PY

printf 'reentrancy-guard-target-first: ok\n'

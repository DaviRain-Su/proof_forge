#!/usr/bin/env bash
set -euo pipefail

# Solana canonical parity script: runs both legacy and canonical pipelines
# for the Counter and ValueVault fixtures.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_BASE="$ROOT/build/canonical/solana"
mkdir -p "$OUT_BASE"

FIXTURES="counter value-vault"

for fixture in $FIXTURES; do
  echo "=== Emitting legacy $fixture ==="
  lake env lean --run Tests/Canonical/Emit.lean -- \
    --pipeline legacy --target solana-sbpf-asm --fixture "$fixture" \
    --out "$OUT_BASE/legacy-$fixture"

  echo "=== Emitting canonical $fixture ==="
  lake env lean --run Tests/Canonical/Emit.lean -- \
    --pipeline canonical --target solana-sbpf-asm --fixture "$fixture" \
    --out "$OUT_BASE/core-$fixture"
done

for fixture in $FIXTURES; do
  test -s "$OUT_BASE/legacy-$fixture/contract.s"
  test -s "$OUT_BASE/core-$fixture/contract.s"
done

echo "=== Running canonical sBPF encoder/interpreter parity ==="
lake env lean --run Tests/Canonical/SolanaParity.lean

if command -v sbpf >/dev/null 2>&1; then
  echo "=== Building canonical assembly with the external sbpf toolchain ==="
  for fixture in $FIXTURES; do
    project_name="${fixture//-/_}"
    project="$OUT_BASE/sbpf-$fixture"
    mkdir -p "$project/src/$project_name"
    cp "$OUT_BASE/core-$fixture/contract.s" "$project/src/$project_name/$project_name.s"
    (cd "$project" && sbpf build)
    test -s "$project/deploy/$project_name.so"
  done
else
  echo "SKIP: sbpf not installed; internal encoder/interpreter parity passed"
fi

echo "=== Solana canonical parity check complete ==="

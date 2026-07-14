#!/usr/bin/env bash
set -euo pipefail

# EVM canonical parity script: runs both legacy and canonical pipelines
# for the Counter and ValueVault fixtures, then compares the Yul output.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_BASE="$ROOT/build/canonical/evm"
mkdir -p "$OUT_BASE"

FIXTURES="counter value-vault"

for fixture in $FIXTURES; do
  echo "=== Emitting legacy $fixture ==="
  lake env lean --run Tests/Canonical/Emit.lean -- \
    --pipeline legacy --target evm --fixture "$fixture" \
    --out "$OUT_BASE/legacy-$fixture"

  echo "=== Emitting canonical $fixture ==="
  lake env lean --run Tests/Canonical/Emit.lean -- \
    --pipeline canonical --target evm --fixture "$fixture" \
    --out "$OUT_BASE/core-$fixture"
done

command -v solc >/dev/null 2>&1 || {
  echo "solc is required for canonical EVM parity" >&2
  exit 1
}

SOLC_OUT="$OUT_BASE/solc"
mkdir -p "$SOLC_OUT"
for fixture in $FIXTURES; do
  LEGACY_YUL="$OUT_BASE/legacy-$fixture/contract.yul"
  CORE_YUL="$OUT_BASE/core-$fixture/contract.yul"
  test -s "$LEGACY_YUL" || {
    echo "missing legacy EVM artifact: $LEGACY_YUL" >&2
    exit 1
  }
  test -s "$CORE_YUL" || {
    echo "missing canonical EVM artifact: $CORE_YUL" >&2
    exit 1
  }
  echo "=== Compiling legacy $fixture Yul ==="
  solc --strict-assembly --bin "$LEGACY_YUL" > "$SOLC_OUT/legacy-$fixture.txt"
  echo "=== Compiling canonical $fixture Yul ==="
  solc --strict-assembly --bin "$CORE_YUL" > "$SOLC_OUT/core-$fixture.txt"
done

echo "=== Running EVM canonical runtime parity ==="
bash "$ROOT/scripts/canonical/evm-runtime-parity.sh"

echo "=== EVM canonical parity gate complete ==="

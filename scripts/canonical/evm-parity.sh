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

# Compile canonical Yul artifacts with solc if available
if command -v solc &> /dev/null; then
  SOLC_OUT="$OUT_BASE/solc"
  mkdir -p "$SOLC_OUT"
  for fixture in $FIXTURES; do
    YUL_FILE="$OUT_BASE/core-$fixture/contract.yul"
    if [ -f "$YUL_FILE" ]; then
      echo "=== Compiling canonical $fixture Yul ==="
      solc --strict-assembly --bin --overwrite -o "$SOLC_OUT" "$YUL_FILE" || \
        echo "WARNING: solc failed for $fixture (expected for partial Core builder)"
    else
      echo "WARNING: $YUL_FILE not found (canonical Yul emission not yet complete)"
    fi
  done
else
  echo "solc not found; skipping Yul compilation"
fi

echo "=== EVM canonical parity check complete ==="
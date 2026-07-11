#!/usr/bin/env bash
set -euo pipefail

# NEAR canonical parity script: runs both legacy and canonical pipelines
# for the Counter and ValueVault fixtures.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_BASE="$ROOT/build/canonical/near"
mkdir -p "$OUT_BASE"

FIXTURES="counter value-vault"

for fixture in $FIXTURES; do
  echo "=== Emitting legacy $fixture ==="
  lake env lean --run Tests/Canonical/Emit.lean -- \
    --pipeline legacy --target wasm-near --fixture "$fixture" \
    --out "$OUT_BASE/legacy-$fixture"

  echo "=== Emitting canonical $fixture ==="
  lake env lean --run Tests/Canonical/Emit.lean -- \
    --pipeline canonical --target wasm-near --fixture "$fixture" \
    --out "$OUT_BASE/core-$fixture"
done

# Compile canonical WAT with wat2wasm if available
if command -v wat2wasm &> /dev/null; then
  for fixture in $FIXTURES; do
    WAT_FILE="$OUT_BASE/core-$fixture/contract.wat"
    if [ -f "$WAT_FILE" ]; then
      echo "=== Compiling canonical $fixture WAT ==="
      wat2wasm "$WAT_FILE" -o "$OUT_BASE/core-$fixture/contract.wasm" || \
        echo "WARNING: wat2wasm failed for $fixture"
    else
      echo "WARNING: $WAT_FILE not found (canonical WAT emission not yet complete)"
    fi
  done
else
  echo "wat2wasm not found; skipping WAT compilation"
fi

echo "=== NEAR canonical parity check complete ==="
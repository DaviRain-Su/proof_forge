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

echo "=== Solana canonical parity check complete ==="
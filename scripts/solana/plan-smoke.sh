#!/usr/bin/env bash
# V-GATE-SOLANA-06: SolanaModulePlan golden smoke.
#
# Builds the Solana semantic plan for each fixture and compares it to the
# golden copy at Examples/Solana/<Fixture>/golden/plan.txt.
#
# Fixtures (RFC 0014 Tier B — array/map/struct state extension):
#   Counter               — scalar state (original MVP)
#   EvmStorageArrayProbe  — array state (`values`, length 3)
#   EvmMapProbe           — map state (`balances`, capacity 128)
#   EvmStorageStructProbe — struct state (`current` : Point)
#
# This is the Tier B gate for the Solana backend: it validates that the
# semantic plan artifact is stable and deterministic before assembly lowering.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

FIXTURES=(
  "Counter"
  "EvmStorageArrayProbe"
  "EvmMapProbe"
  "EvmStorageStructProbe"
)

mkdir -p build/solana

echo "=== V-GATE-SOLANA-06: SolanaModulePlan golden smoke ==="

total=${#FIXTURES[@]}
step=0
fail=0

for fixture in "${FIXTURES[@]}"; do
  step=$((step + 1))
  GOLDEN="$REPO_ROOT/Examples/Solana/${fixture}/golden/plan.txt"
  OUTPUT="$REPO_ROOT/build/solana/${fixture}.plan.txt"

  if [ ! -f "$GOLDEN" ]; then
    echo "FAIL: golden plan not found: $GOLDEN" >&2
    fail=$((fail + 1))
    continue
  fi

  echo "[${step}/${total}] generating ${fixture} SolanaModulePlan..."
  if ! lake env lean --run Tests/SolanaModulePlan.lean "$fixture" "$OUTPUT"; then
    echo "FAIL: plan generation failed for ${fixture}" >&2
    fail=$((fail + 1))
    continue
  fi

  echo "  diff against golden..."
  if ! diff -u "$GOLDEN" "$OUTPUT"; then
    echo "FAIL: generated plan differs from golden for ${fixture}" >&2
    fail=$((fail + 1))
    continue
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "V-GATE-SOLANA-06: FAIL (${fail}/${total} fixtures failed)" >&2
  exit 1
fi

echo "V-GATE-SOLANA-06: PASS (${total}/${total} fixtures)"
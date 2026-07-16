#!/usr/bin/env bash
# V-GATE-SOLANA-06: SolanaModulePlan golden + single-path render smoke.
#
# Builds the Solana semantic plan for each fixture, compares it to the golden
# copy at Examples/Backend/Solana/<Fixture>/golden/plan.txt, AND (Step C) runs the
# single-path render check: plan-driven sBPF assembly must emit cleanly for
# each fixture.
#
# Fixtures (RFC 0014 Phase 2 — Step C plan-driven lowering, single path):
#   Counter               — scalar state (the original MVP)
#   EvmStorageArrayProbe  — array state (`values`, length 3)
#   EvmMapProbe           — map state (`balances`, capacity 128)
#   EvmStorageStructProbe — struct state (`current` : Point)
#
# This is the Tier B gate for the Solana backend's semantic plan. Step C made
# the plan-driven path the ONLY lowering path: SbpfAsm.lowerModuleCore derives
# its LowerCtx via SbpfAsm.buildLowerCtx -> SbpfAsm.LowerCtx.fromPlanSeed, the
# same reconstruction Solana.Plan.LowerCtx.fromSeed uses, so the plan is the
# authoritative source for lowering decisions. The dual-path parity check that
# landed in Phase 2 is retired (there is no second path to agree with); this
# gate is now a single-path regression gate: the plan golden diff pins the
# semantic artifact and the --render flag confirms the plan-driven lowering
# still emits sBPF assembly for each fixture, with the char count surfaced in
# CI logs so byte-churn is observable.

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

echo "=== V-GATE-SOLANA-06: SolanaModulePlan golden + render smoke ==="

total=${#FIXTURES[@]}
step=0
fail=0

for fixture in "${FIXTURES[@]}"; do
  step=$((step + 1))
  GOLDEN="$REPO_ROOT/Examples/Backend/Solana/${fixture}/golden/plan.txt"
  OUTPUT="$REPO_ROOT/build/solana/${fixture}.plan.txt"

  if [ ! -f "$GOLDEN" ]; then
    echo "FAIL: golden plan not found: $GOLDEN" >&2
    fail=$((fail + 1))
    continue
  fi

  echo "[${step}/${total}] generating ${fixture} SolanaModulePlan + render check..."
  if ! lake env lean --run Tests/Backend/Solana/SolanaModulePlan.lean "$fixture" "$OUTPUT" --render; then
    echo "FAIL: plan generation / render failed for ${fixture}" >&2
    fail=$((fail + 1))
    continue
  fi

  echo "  diff plan against golden..."
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
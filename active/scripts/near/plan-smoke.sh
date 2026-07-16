#!/usr/bin/env bash
# V-GATE-NEAR-06: NearModulePlan golden + single-path render smoke.
#
# Builds the NearModulePlan for each fixture, compares it to the golden copy
# at Examples/Backend/WasmNear/<Fixture>/golden/plan.txt, AND (Step C) runs the
# single-path render check: plan-driven WAT must emit cleanly for each fixture.
#
# Fixtures (RFC 0014 Phase 4 — Step C plan-driven lowering, single path):
#   Counter               — scalar state (the original MVP)
#   EvmMapProbe           — map state (`balances`, u64-keyed, sub-module)
#   EvmStorageArrayProbe  — array state (`values`, length 3, sub-module)
#   EvmStorageStructProbe — struct state (`current` : Point, sub-module)
#
# This is the Tier B gate for the NEAR backend's data-layout plan. Step C made
# the plan-driven path the ONLY lowering path: EmitWat.lowerModule derives its
# Ctx via EmitWat.buildLowerCtx -> EmitWat.Ctx.fromPlanSeed, the same
# reconstruction NearModulePlan.Ctx.fromPlanSeed uses, so the plan is the
# authoritative source for lowering decisions. The dual-path parity check that
# landed in Step B/B.2 is retired (there is no second path to agree with);
# this gate is now a single-path regression gate: the plan golden diff pins
# the layout artifact and the --render flag confirms the plan-driven lowering
# still emits WAT for each fixture, with the char count surfaced in CI logs
# so byte-churn is observable.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

FIXTURES=(
  "Counter"
  "EvmMapProbe"
  "EvmStorageArrayProbe"
  "EvmStorageStructProbe"
)

mkdir -p build/wasm-near

echo "=== V-GATE-NEAR-06: NearModulePlan golden + render smoke ==="

# This module is imported only by the test runner, so the default executable
# build does not necessarily refresh its olean after an IR structure change.
lake build ProofForge.Backend.WasmHost.NearModulePlan

total=${#FIXTURES[@]}
step=0
fail=0

for fixture in "${FIXTURES[@]}"; do
  step=$((step + 1))
  GOLDEN="$REPO_ROOT/Examples/Backend/WasmNear/${fixture}/golden/plan.txt"
  OUTPUT="$REPO_ROOT/build/wasm-near/${fixture}.plan.txt"

  if [ ! -f "$GOLDEN" ]; then
    echo "FAIL: golden plan not found: $GOLDEN" >&2
    fail=$((fail + 1))
    continue
  fi

  echo "[${step}/${total}] generating ${fixture} NearModulePlan + render check..."
  if ! lake env lean --run Tests/NearModulePlan.lean "$fixture" "$OUTPUT" --render; then
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
  echo "V-GATE-NEAR-06: FAIL (${fail}/${total} fixtures failed)" >&2
  exit 1
fi

echo "V-GATE-NEAR-06: PASS (${total}/${total} fixtures)"

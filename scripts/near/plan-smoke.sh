#!/usr/bin/env bash
# V-GATE-NEAR-06: NearModulePlan golden + dual-path parity smoke.
#
# Builds the NearModulePlan for each fixture, compares it to the golden copy
# at Examples/WasmNear/<Fixture>/golden/plan.txt, AND (Step B / B.2) runs the
# dual-path parity check: plan-driven WAT vs inline EmitWat WAT must be
# byte-identical.
#
# Fixtures (RFC 0014 Phase 4 — Step B plan-driven lowering + Step B.2 coverage):
#   Counter               — scalar state (the original MVP)
#   EvmMapProbe           — map state (`balances`, u64-keyed, sub-module)
#   EvmStorageArrayProbe  — array state (`values`, length 3, sub-module)
#   EvmStorageStructProbe — struct state (`current` : Point, sub-module)
#
# This is the Tier B gate for the NEAR backend's data-layout plan. Step B
# wires the plan into lowering via NearModulePlan.lowerModuleFromPlan, which
# reuses EmitWat.lowerModuleCoreWithCtx (the shared body extracted from the
# inline path). Step B.2 widens parity coverage to non-scalar state shapes
# (map / array / struct) before Step C deletes the inline path. The inline Ctx
# construction in EmitWat.lowerModule is kept (dual-path) until Step C.

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

echo "=== V-GATE-NEAR-06: NearModulePlan golden + parity smoke ==="

total=${#FIXTURES[@]}
step=0
fail=0

for fixture in "${FIXTURES[@]}"; do
  step=$((step + 1))
  GOLDEN="$REPO_ROOT/Examples/WasmNear/${fixture}/golden/plan.txt"
  OUTPUT="$REPO_ROOT/build/wasm-near/${fixture}.plan.txt"

  if [ ! -f "$GOLDEN" ]; then
    echo "FAIL: golden plan not found: $GOLDEN" >&2
    fail=$((fail + 1))
    continue
  fi

  echo "[${step}/${total}] generating ${fixture} NearModulePlan + parity check..."
  if ! lake env lean --run Tests/NearModulePlan.lean "$fixture" "$OUTPUT" --parity; then
    echo "FAIL: plan generation / parity failed for ${fixture}" >&2
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
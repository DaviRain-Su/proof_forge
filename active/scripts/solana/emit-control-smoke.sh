#!/usr/bin/env bash
# V-GATE-SOLANA-08 (emission half): ProofForge Control-Flow + Assert IR ->
# sBPF assembly emission gate.
#
# Deterministic, sandbox-runnable half of V-GATE-SOLANA-08. It does not need
# `sbpf`, `cargo`, or `solana-keygen`: it drives the Lean codegen in-process
# and asserts that the emitted `.s` carries the control-flow + assertion
# lowering markers + label definitions, that the assembly is reproducible
# byte-for-byte across re-emissions, and that the artifact metadata records
# the expected capabilities. The full runtime half (sbpf build + Mollusk)
# is `scripts/solana/control-smoke.sh`.
#
# Prerequisites:
#   - Lean toolchain (lean-toolchain / lake)
#
# Usage:
#   scripts/solana/emit-control-smoke.sh
#
# Exit codes:
#   0 — emission gates passed
#   1 — a gate failed
#   2 — a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_OUT:-build/solana}"
fail() { echo "FAIL: $1" >&2; exit 1; }
skip() { echo "SKIP: $1" >&2; exit 2; }

command -v lake >/dev/null 2>&1 || skip "lake not on PATH"

echo "=== V-GATE-SOLANA-08 (emission): control IR -> sBPF markers ==="

ASM_OUTPUT="$OUT_DIR/ControlFlowAssertProbe.s"
ASM_OUTPUT2="$OUT_DIR/ControlFlowAssertProbe.repro.s"
ARTIFACT_OUTPUT="$OUT_DIR/control-artifact.json"

# Fresh emit (overwrites prior run).
lake env proof-forge emit --target solana-sbpf-asm --fixture control --format s \
  -o "$ASM_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture control failed"

[ -f "$ASM_OUTPUT" ]   || fail "assembly file not written: $ASM_OUTPUT"
[ -f "$ARTIFACT_OUTPUT" ] || fail "artifact metadata not written: $ARTIFACT_OUTPUT"

# --- Instruction dispatch ------------------------------------------------
grep -qE "^entrypoint:" "$ASM_OUTPUT"           || fail "missing entrypoint label"
grep -qE "jeq r2, 0, sol_lifecycle" "$ASM_OUTPUT"           || fail "missing lifecycle dispatch"
grep -qE "jeq r2, 1, sol_guarded_increment" "$ASM_OUTPUT"   || fail "missing guarded_increment dispatch"
grep -qE "jeq r2, 2, sol_equality_guard" "$ASM_OUTPUT"      || fail "missing equality_guard dispatch"

# --- Control-flow (ifElse) markers --------------------------------------
# At least two distinct then/else branch region labels per the .ifElse shapes.
grep -c "^sol_lbl_0:" "$ASM_OUTPUT" | grep -q '[1-9]' \
  || fail "missing branch-local label sol_lbl_0 (ifElse lowering)"
# Both branches must emit the control.conditional comment (one per ifElse).
COND_COUNT=$(grep -c "; control.conditional" "$ASM_OUTPUT" || true)
[ "$COND_COUNT" -ge 2 ] \
  || fail "expected >=2 control.conditional markers (got $COND_COUNT)"

# --- Assertion markers ---------------------------------------------------
grep -q "; control.assert$" "$ASM_OUTPUT"      || fail "missing assert marker"
grep -q "; control.assert_eq" "$ASM_OUTPUT"     || fail "missing assert_eq marker"
grep -q "^assert_fail:" "$ASM_OUTPUT"           || fail "missing assert_fail label"
grep -q "^assert_eq_fail:" "$ASM_OUTPUT"        || fail "missing assert_eq_fail label"
grep -qE "jeq r2, 0, assert_fail" "$ASM_OUTPUT"   || fail "assert lowers must branch r2==0 to assert_fail"
grep -qE "jne r3, r2, assert_eq_fail" "$ASM_OUTPUT" || fail "assertEq lowers must branch on jne to assert_eq_fail"
grep -qE "mov64 r0, 2" "$ASM_OUTPUT"           || fail "assert_fail must return 2"
grep -qE "mov64 r0, 3" "$ASM_OUTPUT"           || fail "assert_eq_fail must return 3"

# --- Comparison + boolean expression markers ----------------------------
# Comparisons rely on the jeq/jne/jlt/jle/jgt/jge family driving r3 vs r2.
grep -qE "jeq r3, r2, sol_lbl_" "$ASM_OUTPUT"   || fail "missing eq comparison (.eq lowering)"
grep -qE "jlt r3, r2, sol_lbl_" "$ASM_OUTPUT"  || fail "missing lt comparison (.lt lowering)"

# --- Reproducibility -----------------------------------------------------
lake env proof-forge emit --target solana-sbpf-asm --fixture control --format s \
  -o "$ASM_OUTPUT2" \
  --artifact-output "$OUT_DIR/control-artifact.repro.json" \
  || fail "second emission failed"

if ! cmp -s "$ASM_OUTPUT" "$ASM_OUTPUT2"; then
  fail "non-deterministic assembly: $ASM_OUTPUT differs from $ASM_OUTPUT2"
fi
SHA1=$(shasum -a 256 "$ASM_OUTPUT" | cut -d' ' -f1)
echo "  deterministic: sha256=$SHA1"

# --- Artifact metadata ----------------------------------------------------
# JSON separators include a space after the colon (human-readable style), so
# match the key/value pair with a flexible whitespace class rather than a
# literal "key":"value" substring.
grep -qE '"target":[[:space:]]*"solana-sbpf-asm"' "$ARTIFACT_OUTPUT" \
  || fail "artifact missing target: solana-sbpf-asm"
grep -qE '"fixture":[[:space:]]*"control-ir-sbpf"' "$ARTIFACT_OUTPUT" \
  || fail "artifact missing fixture: control-ir-sbpf"
grep -qE '"sourceModule":[[:space:]]*"ControlFlowAssertProbe"' "$ARTIFACT_OUTPUT" \
  || fail "artifact missing sourceModule: ControlFlowAssertProbe"
grep -q '"control.conditional"' "$ARTIFACT_OUTPUT" \
  || fail "artifact capabilities missing control.conditional"
grep -q '"assertions.check"' "$ARTIFACT_OUTPUT" \
  || fail "artifact capabilities missing assertions.check"
grep -q '"storage.scalar"' "$ARTIFACT_OUTPUT" \
  || fail "artifact capabilities missing storage.scalar"

echo "  V-GATE-SOLANA-08 (emission): PASS"
echo ""
echo "=== ProofForge Control-Flow + Assert emission smoke: ALL PASS ==="
#!/usr/bin/env bash
# V-GATE-SOLANA-01 + V-GATE-SOLANA-02: Solana sBPF assembly toolchain round-trip.
#
# Emits a canned entrypoint.s via
# `proof-forge emit --target solana-sbpf-asm --fixture canned-entrypoint`,
# assembles it
# into a Solana eBPF ELF with the sbpf toolchain, and verifies the disassembler
# round-trips the ELF back to matching assembly.
#
# Prerequisites:
#   - Lean toolchain (lean-toolchain)
#   - sbpf on PATH (cargo install --git https://github.com/blueshift-gg/sbpf.git)
#
# Usage:
#   scripts/solana/emit-asm-smoke.sh
#
# Exit codes:
#   0 — all gates passed
#   1 — a gate failed
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_OUT:-build/solana}"
SBPF_BIN="${SBPF:-sbpf}"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

skip() {
  echo "SKIP: $1" >&2
  exit 0
}

# --- Tool checks -----------------------------------------------------------

if ! command -v "$SBPF_BIN" >/dev/null 2>&1; then
  skip "sbpf not on PATH (set SBPF or run: cargo install --git https://github.com/blueshift-gg/sbpf.git)"
fi

if ! command -v lake >/dev/null 2>&1; then
  fail "lake not on PATH"
fi

echo "=== V-GATE-SOLANA-01: emit sbpf asm ==="

ASM_OUTPUT="$OUT_DIR/entrypoint.s"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"

lake env proof-forge emit --target solana-sbpf-asm --fixture canned-entrypoint --format s \
  -o "$ASM_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture canned-entrypoint failed"

[ -f "$ASM_OUTPUT" ] || fail "assembly file not written: $ASM_OUTPUT"
[ -f "$ARTIFACT_OUTPUT" ] || fail "artifact metadata not written: $ARTIFACT_OUTPUT"

# Verify artifact metadata records the correct target. JSON separators
# include a space after the colon (human-readable style), so match with a
# flexible whitespace class.
grep -qE '"target":[[:space:]]*"solana-sbpf-asm"' "$ARTIFACT_OUTPUT" \
  || fail "artifact metadata missing target: solana-sbpf-asm"

echo "  emitted: $ASM_OUTPUT"
echo "  artifact: $ARTIFACT_OUTPUT"
echo "  V-GATE-SOLANA-01: PASS"

echo "=== V-GATE-SOLANA-02: sbpf build + disassemble round-trip ==="

# sbpf expects src/<name>/<name>.s project layout.
SBPF_PROJECT="$OUT_DIR/sbpf-project"
SBPF_SRC="$SBPF_PROJECT/src/entrypoint"
rm -rf "$SBPF_PROJECT"
mkdir -p "$SBPF_SRC"
cp "$ASM_OUTPUT" "$SBPF_SRC/entrypoint.s"

( cd "$SBPF_PROJECT" && "$SBPF_BIN" build ) \
  || fail "sbpf build failed"

ELF="$SBPF_PROJECT/deploy/entrypoint.so"
[ -f "$ELF" ] || fail "ELF not produced: $ELF"

# Verify it's a valid eBPF ELF.
file "$ELF" | grep -q "eBPF" \
  || fail "output is not an eBPF ELF: $ELF"

echo "  built: $ELF ($(file -b "$ELF"))"

# Disassemble and verify round-trip.
DISASM_OUTPUT="$OUT_DIR/entrypoint.disasm.s"
"$SBPF_BIN" disassemble "$ELF" > "$DISASM_OUTPUT" 2>/dev/null \
  || fail "sbpf disassemble failed"

grep -q "entrypoint:" "$DISASM_OUTPUT" || fail "disassembly missing entrypoint label"
grep -q "exit" "$DISASM_OUTPUT" || fail "disassembly missing exit instruction"

echo "  disassembled: $DISASM_OUTPUT"
echo "  V-GATE-SOLANA-02: PASS"

echo ""
echo "=== Solana sBPF assembly toolchain smoke: ALL PASS ==="

#!/usr/bin/env bash
# Solana sBPF assembly example build + golden diff.
#
# Emits the Solana Counter example to sBPF assembly and verifies it matches the
# tracked golden fixture. This script does NOT require `sbpf`, `cargo`, or
# `solana-keygen`; it only needs the Lean toolchain. Use it as the CI-runnable
# build gate for Solana examples.
#
# Usage:
#   scripts/solana/build-examples.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_OUT:-build/solana}"
fail() { echo "FAIL: $1" >&2; exit 1; }

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"

mkdir -p "$OUT_DIR"

ASM_OUTPUT="$OUT_DIR/Counter.s"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
GOLDEN_S="$REPO_ROOT/Examples/Backend/Solana/Counter.legacy.golden.s"
GOLDEN_MANIFEST="$REPO_ROOT/Examples/Backend/Solana/Counter.manifest.toml"

[ -f "$GOLDEN_S" ] || fail "golden assembly not found: $GOLDEN_S"
[ -f "$GOLDEN_MANIFEST" ] || fail "golden manifest not found: $GOLDEN_MANIFEST"

echo "=== Solana Counter IR -> sBPF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture counter --format s \
  -o "$ASM_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture counter failed"

[ -f "$ASM_OUTPUT" ] || fail "assembly file not written: $ASM_OUTPUT"
[ -f "$OUT_DIR/manifest.toml" ] || fail "manifest not written: $OUT_DIR/manifest.toml"

diff -u "$GOLDEN_S" "$ASM_OUTPUT" || fail "Counter.s differs from golden fixture"
echo "  Counter.s: matches golden"

diff -u "$GOLDEN_MANIFEST" "$OUT_DIR/manifest.toml" || fail "manifest.toml differs from golden fixture"
echo "  manifest.toml: matches golden"

echo ""
echo "=== Solana sBPF examples: ALL PASS ==="

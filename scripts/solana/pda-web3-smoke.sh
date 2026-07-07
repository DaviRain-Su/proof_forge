#!/usr/bin/env bash
# Solana PDA typed-seed Rust derivation smoke.
#
# This optional gate emits the SDK Vault artifact, reads its PDA typed seed
# descriptors, and verifies that the descriptor semantics match the standard
# Solana PDA APIs:
#
#   Address::find_program_address(base seeds, program_id)
#   Address::create_program_address(base seeds + bump, program_id)
#
# Exit codes:
#   0 — all gates passed
#   1 — a gate failed
#   2 — a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_PDA_WEB3_OUT:-build/solana-pda-web3}"
ASM_OUTPUT="$OUT_DIR/SolanaVault.s"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"

fail() { echo "FAIL: $1" >&2; exit 1; }

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v cargo >/dev/null 2>&1 || fail "cargo not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "=== Solana PDA Rust step 1: emit SDK fixture ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture solana-sdk --format s \
  -o "$ASM_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture solana-sdk failed"

[ -f "$ARTIFACT_OUTPUT" ] || fail "artifact metadata not written: $ARTIFACT_OUTPUT"

echo "=== Solana PDA Rust step 2: validate typed seed descriptors ==="
cargo run --manifest-path testkit/harness-solana/Cargo.toml \
  --bin pda_derivation_smoke -- "$ARTIFACT_OUTPUT" \
  || fail "PDA Rust descriptor validation failed"

echo "=== Solana PDA Rust smoke: PASS ==="

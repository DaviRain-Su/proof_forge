#!/usr/bin/env bash
# V-GATE-SOLANA-03: ProofForge Counter IR -> sBPF -> Mollusk runtime smoke.
#
# Emits the Counter sBPF assembly via
# `proof-forge emit --target solana-sbpf-asm --fixture counter`,
# assembles it into a Solana eBPF ELF with the sbpf toolchain, and verifies
# the program's runtime behavior against the Counter IR contract using the
# Mollusk SVM test harness:
#
#   initialize  -> account data becomes 0u64
#   increment   -> account data increases by 1
#   get         -> return_data is the 8-byte little-endian count
#
# Prerequisites:
#   - Lean toolchain (lean-toolchain / lake)
#   - sbpf on PATH, or set SBPF=/path/to/sbpf
#     (cargo install --git https://github.com/blueshift-gg/sbpf.git)
#   - cargo (for the Mollusk test crate)
#   - solana-keygen on PATH, or set SOLANA_KEYGEN=/path/to/solana-keygen
#
# Usage:
#   scripts/solana/counter-smoke.sh
#
# Exit codes:
#   0 — all gates passed
#   1 — a gate failed
#   2 — a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_OUT:-build/solana}"
SBPF_BIN="${SBPF:-sbpf}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"

PROJECT_NAME="proofforge-counter"

# Template / source locations in the repo.
TPL_RS="$REPO_ROOT/Tests/solana/counter_mollusk.rs.tpl"

fail() { echo "FAIL: $1" >&2; exit 1; }
skip() { echo "SKIP: $1" >&2; exit 2; }

# --- Prerequisite checks --------------------------------------------------

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
if ! command -v "$SBPF_BIN" >/dev/null 2>&1; then
  skip "sbpf not on PATH (set SBPF or run: cargo install --git https://github.com/blueshift-gg/sbpf.git)"
fi
if ! command -v "$KEYGEN" >/dev/null 2>&1; then
  skip "solana-keygen not on PATH (set SOLANA_KEYGEN)"
fi
command -v cargo >/dev/null 2>&1 || fail "cargo not on PATH"
[ -f "$TPL_RS" ] || fail "Mollusk test template not found: $TPL_RS"

# --- 1. Emit Counter sBPF assembly ---------------------------------------

echo "=== V-GATE-SOLANA-03 step 1: emit Counter IR -> sBPF ==="

ASM_OUTPUT="$OUT_DIR/Counter.s"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"

lake env proof-forge emit --target solana-sbpf-asm --fixture counter --format s -o "$ASM_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture counter failed"

[ -f "$ASM_OUTPUT" ] || fail "assembly file not written: $ASM_OUTPUT"
echo "  emitted: $ASM_OUTPUT"

GOLDEN_S="$REPO_ROOT/Examples/Backend/Solana/Counter.legacy.golden.s"
[ -f "$GOLDEN_S" ] || fail "golden sBPF assembly not found: $GOLDEN_S"
diff -u "$GOLDEN_S" "$ASM_OUTPUT" || fail "emitted .s differs from golden fixture"
echo "  golden diff: ok"

# --- 2. Scaffold sbpf test project ---------------------------------------

echo "=== V-GATE-SOLANA-03 step 2: scaffold sbpf test project ==="

PROJECT_DIR="$OUT_DIR/counter-test"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/deploy" "$PROJECT_DIR/src/$PROJECT_NAME"

# Generate program keypair (Mollusk reads the first 32 raw bytes of the JSON
# file as the program id — see the sbpf init template).
"$KEYGEN" new --no-bip39-passphrase --silent \
  -o "$PROJECT_DIR/deploy/$PROJECT_NAME-keypair.json" --force \
  || fail "solana-keygen failed"

# Copy the emitted assembly into the sbpf expected layout:
#   src/<project-name>/<project-name>.s
cp "$ASM_OUTPUT" "$PROJECT_DIR/src/$PROJECT_NAME/$PROJECT_NAME.s"

# Render the Mollusk test from the template (substitute __PROGRAM_NAME__).
sed "s/__PROGRAM_NAME__/$PROJECT_NAME/g" "$TPL_RS" \
  > "$PROJECT_DIR/src/lib.rs"

# Write the Cargo.toml.
cat > "$PROJECT_DIR/Cargo.toml" <<CARGO_EOF
[package]
name = "$PROJECT_NAME"
version = "0.1.0"
edition = "2021"

[dev-dependencies]
mollusk-svm = "0.13.4"
solana-account = "3.4.0"
solana-address = "2.6.1"
solana-instruction = "3.3.0"

[features]
test-sbf = []
CARGO_EOF

echo "  project: $PROJECT_DIR"

# --- 3. Build the Solana eBPF ELF ----------------------------------------

echo "=== V-GATE-SOLANA-03 step 3: sbpf build ==="

( cd "$PROJECT_DIR" && "$SBPF_BIN" build ) \
  || fail "sbpf build failed"

ELF="$PROJECT_DIR/deploy/$PROJECT_NAME.so"
[ -f "$ELF" ] || fail "ELF not produced: $ELF"
echo "  built: $ELF"

# --- 4. Run Mollusk tests ------------------------------------------------

echo "=== V-GATE-SOLANA-03 step 4: Mollusk runtime tests ==="

( cd "$PROJECT_DIR" && cargo test --features test-sbf -- --nocapture ) \
  || fail "Mollusk tests failed"

echo "  V-GATE-SOLANA-03: PASS"
echo ""
echo "=== ProofForge Counter Mollusk smoke: ALL PASS ==="

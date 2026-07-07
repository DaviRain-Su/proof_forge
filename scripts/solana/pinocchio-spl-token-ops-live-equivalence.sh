#!/usr/bin/env bash
# ProofForge vs Pinocchio SPL Token ops live equivalence on Surfpool.
#
# Builds the generated ProofForge SPL Token mint_to/burn/approve/revoke CPI ELF
# and the checked-in Pinocchio reference ELF, deploys both programs to the same
# Surfpool instance, invokes the same Rust token operations scenario against
# each program, and compares token deltas plus state writes.
#
# Exit codes:
#   0 - live equivalence passed
#   1 - a gate failed
#   2 - a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_PINOCCHIO_SPL_TOKEN_OPS_LIVE_OUT:-build/solana-pinocchio-spl-token-ops-live}"
REFERENCE_DIR="$REPO_ROOT/references/solana/pinocchio/spl-token-ops"
PROOF_FORGE_PROJECT_NAME="proofforge-spl-token-ops-live"
PINOCCHIO_PROJECT_NAME="pinocchio-spl-token-ops-reference"
PROOF_FORGE_ELF="$OUT_DIR/$PROOF_FORGE_PROJECT_NAME.so"
PROOF_FORGE_ARTIFACT="$OUT_DIR/proof-forge-artifact.json"
PINOCCHIO_BUILD_DIR="$OUT_DIR/pinocchio-build"
PINOCCHIO_ELF="$OUT_DIR/$PINOCCHIO_PROJECT_NAME.so"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROOF_FORGE_PROGRAM_KEYPAIR="$OUT_DIR/proofforge-program-keypair.json"
PINOCCHIO_PROGRAM_KEYPAIR="$OUT_DIR/pinocchio-program-keypair.json"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
CARGO_BUILD_SBF_BIN="${CARGO_BUILD_SBF:-cargo-build-sbf}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_SPL_TOKEN_OPS_CPI_SBPF_ARCH:-v0}"
SOLANA_RUSTUP_TOOLCHAIN="${PROOF_FORGE_PINOCCHIO_RUSTUP_TOOLCHAIN:-1.89.0-sbpf-solana-v1.52}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_PINOCCHIO_SPL_TOKEN_OPS_SURFPOOL_PORT:-8914}"
WS_PORT="${PROOF_FORGE_PINOCCHIO_SPL_TOKEN_OPS_SURFPOOL_WS_PORT:-8915}"
RPC_URL="http://$RPC_HOST:$RPC_PORT"
SURFPOOL_LOG_DIR="$OUT_DIR/surfpool-logs"
TOKEN_DECIMALS="${PROOF_FORGE_SOLANA_TOKEN_DECIMALS:-9}"
INITIAL_SOURCE_AMOUNT="${PROOF_FORGE_SOLANA_TOKEN_INITIAL_SOURCE_AMOUNT:-1000000000}"
MINT_AMOUNT="${PROOF_FORGE_SOLANA_TOKEN_MINT_AMOUNT:-125000000}"
BURN_AMOUNT="${PROOF_FORGE_SOLANA_TOKEN_BURN_AMOUNT:-75000000}"
APPROVE_AMOUNT="${PROOF_FORGE_SOLANA_TOKEN_APPROVE_AMOUNT:-333000000}"
SURFPOOL_PID=""

PINOCCHIO_LIVE_SCRIPT="scripts/solana/pinocchio-spl-token-ops-live-equivalence.sh"
. "$REPO_ROOT/scripts/solana/pinocchio-live-common.sh"
trap cleanup EXIT

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v "$SURFPOOL_BIN" >/dev/null 2>&1 || skip "surfpool not on PATH (set SURFPOOL=/path/to/surfpool)"
command -v "$SOLANA_BIN" >/dev/null 2>&1 || skip "solana CLI not on PATH (set SOLANA=/path/to/solana)"
command -v "$KEYGEN" >/dev/null 2>&1 || skip "solana-keygen not on PATH (set SOLANA_KEYGEN=/path/to/solana-keygen)"
command -v "$CARGO_BUILD_SBF_BIN" >/dev/null 2>&1 || skip "cargo-build-sbf not on PATH"
command -v sbpf >/dev/null 2>&1 || skip "sbpf not on PATH"
command -v cargo >/dev/null 2>&1 || skip "cargo not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"
[ -f "$REFERENCE_DIR/Cargo.toml" ] || fail "Pinocchio reference Cargo.toml missing: $REFERENCE_DIR/Cargo.toml"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$PINOCCHIO_BUILD_DIR" "$SURFPOOL_LOG_DIR"

echo "=== Pinocchio SPL Token ops live equivalence step 1: build ProofForge fixture ELF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture spl-token-ops-cpi --format elf --solana-sbpf-arch "$SBPF_ARCH" \
  -o "$PROOF_FORGE_ELF" \
  --artifact-output "$PROOF_FORGE_ARTIFACT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture spl-token-ops-cpi --format elf failed"
[ -f "$PROOF_FORGE_ELF" ] || fail "ProofForge ELF not produced: $PROOF_FORGE_ELF"
[ -f "$PROOF_FORGE_ARTIFACT" ] || fail "ProofForge artifact not produced: $PROOF_FORGE_ARTIFACT"

echo "=== Pinocchio SPL Token ops live equivalence step 2: build Pinocchio reference ELF ==="
selectPinocchioSbfBuildMode
if ! buildPinocchioReference \
    > "$OUT_DIR/pinocchio-build.stdout.log" \
    2> "$OUT_DIR/pinocchio-build.stderr.log"; then
  echo "Pinocchio cargo-build-sbf stdout:" >&2
  sed -n '1,160p' "$OUT_DIR/pinocchio-build.stdout.log" >&2 || true
  echo "Pinocchio cargo-build-sbf stderr:" >&2
  sed -n '1,160p' "$OUT_DIR/pinocchio-build.stderr.log" >&2 || true
  printSbfToolchainHint
  skip "Pinocchio reference SBF build failed"
fi
copyPinocchioReferenceElf "$PINOCCHIO_ELF"

echo "=== Pinocchio SPL Token ops live equivalence step 3: generate local keypairs ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROOF_FORGE_PROGRAM_KEYPAIR" --force \
  || fail "ProofForge program keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PINOCCHIO_PROGRAM_KEYPAIR" --force \
  || fail "Pinocchio program keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROOF_FORGE_PROGRAM_ID="$("$KEYGEN" pubkey "$PROOF_FORGE_PROGRAM_KEYPAIR")"
PINOCCHIO_PROGRAM_ID="$("$KEYGEN" pubkey "$PINOCCHIO_PROGRAM_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"
echo "  ProofForge program id: $PROOF_FORGE_PROGRAM_ID"
echo "  Pinocchio program id: $PINOCCHIO_PROGRAM_ID"

echo "=== Pinocchio SPL Token ops live equivalence step 4: start Surfpool ==="
"$SURFPOOL_BIN" start \
  --host "$RPC_HOST" \
  --port "$RPC_PORT" \
  --ws-port "$WS_PORT" \
  --offline \
  --no-tui \
  --no-studio \
  --no-deploy \
  --airdrop-keypair-path "$PAYER_KEYPAIR" \
  --log-path "$SURFPOOL_LOG_DIR" \
  > "$OUT_DIR/surfpool.stdout.log" 2> "$OUT_DIR/surfpool.stderr.log" &
SURFPOOL_PID="$!"

for _ in $(seq 1 60); do
  if "$SOLANA_BIN" --url "$RPC_URL" cluster-version >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$SURFPOOL_PID" >/dev/null 2>&1; then
    echo "Surfpool stdout:" >&2
    sed -n '1,160p' "$OUT_DIR/surfpool.stdout.log" >&2 || true
    echo "Surfpool stderr:" >&2
    sed -n '1,160p' "$OUT_DIR/surfpool.stderr.log" >&2 || true
    fail "surfpool exited before RPC became available"
  fi
  sleep 1
done
"$SOLANA_BIN" --url "$RPC_URL" cluster-version >/dev/null 2>&1 \
  || fail "surfpool RPC did not become ready at $RPC_URL"
echo "  RPC ready: $RPC_URL"
"$SOLANA_BIN" --url "$RPC_URL" airdrop 40 "$PAYER_PUBKEY" >/dev/null \
  || fail "airdrop to payer failed"

echo "=== Pinocchio SPL Token ops live equivalence step 5: deploy both programs ==="
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROOF_FORGE_PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$PROOF_FORGE_ELF" \
  || fail "ProofForge program deploy failed"
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PINOCCHIO_PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$PINOCCHIO_ELF" \
  || fail "Pinocchio program deploy failed"

echo "=== Pinocchio SPL Token ops live equivalence step 6: run Rust behavior checks ==="
PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROOF_FORGE_PROGRAM_ID" \
PROOF_FORGE_SOLANA_ARTIFACT="$PROOF_FORGE_ARTIFACT" \
PROOF_FORGE_SOLANA_TOKEN_DECIMALS="$TOKEN_DECIMALS" \
PROOF_FORGE_SOLANA_TOKEN_INITIAL_SOURCE_AMOUNT="$INITIAL_SOURCE_AMOUNT" \
PROOF_FORGE_SOLANA_TOKEN_MINT_AMOUNT="$MINT_AMOUNT" \
PROOF_FORGE_SOLANA_TOKEN_BURN_AMOUNT="$BURN_AMOUNT" \
PROOF_FORGE_SOLANA_TOKEN_APPROVE_AMOUNT="$APPROVE_AMOUNT" \
  cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana --bin spl_token_ops_cpi_live_smoke > "$OUT_DIR/proofforge-result.json" \
  || fail "Rust ProofForge SPL Token ops CPI checks failed"
PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PINOCCHIO_PROGRAM_ID" \
PROOF_FORGE_SOLANA_ARTIFACT="$PROOF_FORGE_ARTIFACT" \
PROOF_FORGE_SOLANA_TOKEN_DECIMALS="$TOKEN_DECIMALS" \
PROOF_FORGE_SOLANA_TOKEN_INITIAL_SOURCE_AMOUNT="$INITIAL_SOURCE_AMOUNT" \
PROOF_FORGE_SOLANA_TOKEN_MINT_AMOUNT="$MINT_AMOUNT" \
PROOF_FORGE_SOLANA_TOKEN_BURN_AMOUNT="$BURN_AMOUNT" \
PROOF_FORGE_SOLANA_TOKEN_APPROVE_AMOUNT="$APPROVE_AMOUNT" \
  cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana --bin spl_token_ops_cpi_live_smoke > "$OUT_DIR/pinocchio-result.json" \
  || fail "Rust Pinocchio SPL Token ops CPI checks failed"

python3 - "$OUT_DIR/proofforge-result.json" "$OUT_DIR/pinocchio-result.json" <<'PY'
import json
import pathlib
import sys

proof = json.loads(pathlib.Path(sys.argv[1]).read_text())
reference = json.loads(pathlib.Path(sys.argv[2]).read_text())

def require(condition, message):
    if not condition:
        raise SystemExit(message)

for label, result in (("ProofForge", proof), ("Pinocchio", reference)):
    mint_amount = int(result["mintAmount"])
    burn_amount = int(result["burnAmount"])
    approve_amount = int(result["approveAmount"])
    require(int(result["destinationAfterMint"]) - int(result["destinationBefore"]) == mint_amount,
            f"{label} destination mint delta mismatch: {result}")
    require(int(result["supplyAfterMint"]) - int(result["supplyBefore"]) == mint_amount,
            f"{label} mint supply delta mismatch: {result}")
    require(int(result["sourceBefore"]) - int(result["sourceAfterBurn"]) == burn_amount,
            f"{label} source burn delta mismatch: {result}")
    require(int(result["supplyAfterMint"]) - int(result["supplyAfterBurn"]) == burn_amount,
            f"{label} burn supply delta mismatch: {result}")
    require(int(result["recordedMint"]) == mint_amount,
            f"{label} mint state write mismatch: {result}")
    require(int(result["recordedBurn"]) == burn_amount,
            f"{label} burn state write mismatch: {result}")
    require(int(result["recordedApprove"]) == approve_amount,
            f"{label} approve state write mismatch: {result}")
    require(int(result["recordedRevoke"]) == 1,
            f"{label} revoke marker mismatch: {result}")

for field in ("decimals", "mintAmount", "burnAmount", "approveAmount",
              "recordedMint", "recordedBurn", "recordedApprove", "recordedRevoke"):
    require(proof[field] == reference[field],
            f"{field} mismatch: proof={proof[field]} reference={reference[field]}")

print(json.dumps({
    "proofForgeProgramId": proof["programId"],
    "pinocchioProgramId": reference["programId"],
    "decimals": proof["decimals"],
    "mintAmount": proof["mintAmount"],
    "burnAmount": proof["burnAmount"],
    "approveAmount": proof["approveAmount"],
    "proofForgeRecordedMint": proof["recordedMint"],
    "pinocchioRecordedMint": reference["recordedMint"],
    "proofForgeRecordedBurn": proof["recordedBurn"],
    "pinocchioRecordedBurn": reference["recordedBurn"],
    "proofForgeRecordedApprove": proof["recordedApprove"],
    "pinocchioRecordedApprove": reference["recordedApprove"],
    "proofForgeRecordedRevoke": proof["recordedRevoke"],
    "pinocchioRecordedRevoke": reference["recordedRevoke"],
}, sort_keys=True))
PY

echo "=== Pinocchio SPL Token ops live equivalence: PASS ==="

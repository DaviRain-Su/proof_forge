#!/usr/bin/env bash
# ProofForge Solana SPL Token transfer_checked CPI live smoke on Surfpool.
#
# Builds the SPL Token transfer_checked CPI SDK fixture, starts Surfpool,
# deploys the generated ELF with Solana CLI, invokes the Rust live RPC harness,
# and verifies token balance deltas plus the recorded state amount.
#
# Exit codes:
#   0 - all gates passed
#   1 - a gate failed
#   2 - a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_SPL_TOKEN_TRANSFER_CPI_OUT:-build/solana-spl-token-transfer-cpi-live}"
PROJECT_NAME="proofforge-spl-token-transfer-cpi-live"
ELF_OUTPUT="$OUT_DIR/$PROJECT_NAME.so"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROGRAM_KEYPAIR="$OUT_DIR/program-keypair.json"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_SPL_TOKEN_TRANSFER_CPI_SBPF_ARCH:-v0}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_SPL_TOKEN_TRANSFER_CPI_SURFPOOL_PORT:-8898}"
WS_PORT="${PROOF_FORGE_SPL_TOKEN_TRANSFER_CPI_SURFPOOL_WS_PORT:-8897}"
RPC_URL="http://$RPC_HOST:$RPC_PORT"
SURFPOOL_LOG_DIR="$OUT_DIR/surfpool-logs"
TOKEN_DECIMALS="${PROOF_FORGE_SOLANA_TOKEN_DECIMALS:-9}"
TRANSFER_AMOUNT="${PROOF_FORGE_SOLANA_TOKEN_TRANSFER_AMOUNT:-250000000}"
INITIAL_AMOUNT="${PROOF_FORGE_SOLANA_TOKEN_INITIAL_AMOUNT:-1000000000}"
SURFPOOL_PID=""

fail() { echo "FAIL: $1" >&2; exit 1; }
skip() { echo "SKIP: $1" >&2; exit 2; }

cleanup() {
  if [ -n "$SURFPOOL_PID" ] && kill -0 "$SURFPOOL_PID" >/dev/null 2>&1; then
    kill "$SURFPOOL_PID" >/dev/null 2>&1 || true
    for _ in $(seq 1 10); do
      if ! kill -0 "$SURFPOOL_PID" >/dev/null 2>&1; then
        wait "$SURFPOOL_PID" >/dev/null 2>&1 || true
        return
      fi
      sleep 1
    done
    kill -9 "$SURFPOOL_PID" >/dev/null 2>&1 || true
    wait "$SURFPOOL_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v "$SURFPOOL_BIN" >/dev/null 2>&1 || skip "surfpool not on PATH (set SURFPOOL=/path/to/surfpool)"
command -v "$SOLANA_BIN" >/dev/null 2>&1 || skip "solana CLI not on PATH (set SOLANA=/path/to/solana)"
command -v "$KEYGEN" >/dev/null 2>&1 || skip "solana-keygen not on PATH (set SOLANA_KEYGEN=/path/to/solana-keygen)"
command -v sbpf >/dev/null 2>&1 || skip "sbpf not on PATH"
command -v cargo >/dev/null 2>&1 || skip "cargo not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$SURFPOOL_LOG_DIR"

echo "=== Solana SPL Token transfer_checked CPI step 1: build fixture ELF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture spl-token-transfer-cpi --format elf --solana-sbpf-arch "$SBPF_ARCH" \
  -o "$ELF_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture spl-token-transfer-cpi --format elf failed"
[ -f "$ELF_OUTPUT" ] || fail "ELF not produced: $ELF_OUTPUT"

python3 - "$ARTIFACT_OUTPUT" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
if artifact.get("fixture") != "solana-spl-token-transfer-cpi-elf":
    raise SystemExit("artifact fixture mismatch")
instructions = artifact.get("solanaInstructions", [])
if len(instructions) != 1 or instructions[0].get("name") != "transfer":
    raise SystemExit(f"instruction schema mismatch: {instructions}")
accounts = [account.get("name") for account in instructions[0].get("accounts", [])]
expected_accounts = [
    "last_transfer_amount",
    "source",
    "mint",
    "destination",
    "authority",
    "spl_token",
]
if accounts != expected_accounts:
    raise SystemExit(f"account schema mismatch: {accounts}")
params = instructions[0].get("params", [])
expected_params = [
    {"name": "amount", "type": "U64", "offset": 1, "byteSize": 8, "encoding": "le-u64"},
]
if params != expected_params:
    raise SystemExit(f"parameter schema mismatch: {params}")
cpis = artifact.get("solanaExtensions", {}).get("cpis", [])
if len(cpis) != 1 or cpis[0].get("name") != "token_transfer":
    raise SystemExit(f"CPI schema mismatch: {cpis}")
if cpis[0].get("protocol") != "spl-token":
    raise SystemExit(f"CPI protocol mismatch: {cpis}")
if cpis[0].get("dataLayout") != "spl-token.transfer_checked":
    raise SystemExit(f"CPI layout mismatch: {cpis}")
if cpis[0].get("amountSource") != "amount":
    raise SystemExit(f"CPI amount source mismatch: {cpis}")
if cpis[0].get("decimals") != "9":
    raise SystemExit(f"CPI decimals mismatch: {cpis}")
print("artifact validation: ok")
PY

echo "=== Solana SPL Token transfer_checked CPI step 2: generate local keypairs ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROGRAM_KEYPAIR" --force \
  || fail "program keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROGRAM_ID="$("$KEYGEN" pubkey "$PROGRAM_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"
echo "  program id: $PROGRAM_ID"

echo "=== Solana SPL Token transfer_checked CPI step 3: start Surfpool ==="
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
"$SOLANA_BIN" --url "$RPC_URL" airdrop 20 "$PAYER_PUBKEY" >/dev/null \
  || fail "airdrop to payer failed"

echo "=== Solana SPL Token transfer_checked CPI step 4: deploy program ==="
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$ELF_OUTPUT" \
  || fail "solana program deploy failed"

echo "=== Solana SPL Token transfer_checked CPI step 5: run Rust behavior checks ==="
PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROGRAM_ID" \
PROOF_FORGE_SOLANA_TOKEN_DECIMALS="$TOKEN_DECIMALS" \
PROOF_FORGE_SOLANA_TOKEN_TRANSFER_AMOUNT="$TRANSFER_AMOUNT" \
PROOF_FORGE_SOLANA_TOKEN_INITIAL_AMOUNT="$INITIAL_AMOUNT" \
  cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana --bin spl_token_transfer_cpi_live_smoke \
  || fail "Rust SPL Token transfer_checked CPI checks failed"

echo "=== Solana SPL Token transfer_checked CPI Surfpool/Rust smoke: PASS ==="

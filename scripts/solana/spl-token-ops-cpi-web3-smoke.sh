#!/usr/bin/env bash
# ProofForge Solana SPL Token mint_to/burn/approve/revoke CPI live smoke on Surfpool.
#
# Builds the SPL Token operations CPI SDK fixture, starts Surfpool, deploys the
# generated ELF with Solana CLI, invokes the Rust live RPC harness, and verifies
# mint/burn/approve/revoke token effects plus recorded state values.
#
# Exit codes:
#   0 - all gates passed
#   1 - a gate failed
#   2 - a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_SPL_TOKEN_OPS_CPI_OUT:-build/solana-spl-token-ops-cpi-live}"
PROJECT_NAME="proofforge-spl-token-ops-cpi-live"
ELF_OUTPUT="$OUT_DIR/$PROJECT_NAME.so"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROGRAM_KEYPAIR="$OUT_DIR/program-keypair.json"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_SPL_TOKEN_OPS_CPI_SBPF_ARCH:-v0}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_SPL_TOKEN_OPS_CPI_SURFPOOL_PORT:-8900}"
WS_PORT="${PROOF_FORGE_SPL_TOKEN_OPS_CPI_SURFPOOL_WS_PORT:-8896}"
RPC_URL="http://$RPC_HOST:$RPC_PORT"
SURFPOOL_LOG_DIR="$OUT_DIR/surfpool-logs"
TOKEN_DECIMALS="${PROOF_FORGE_SOLANA_TOKEN_DECIMALS:-9}"
INITIAL_SOURCE_AMOUNT="${PROOF_FORGE_SOLANA_TOKEN_INITIAL_SOURCE_AMOUNT:-1000000000}"
MINT_AMOUNT="${PROOF_FORGE_SOLANA_TOKEN_MINT_AMOUNT:-125000000}"
BURN_AMOUNT="${PROOF_FORGE_SOLANA_TOKEN_BURN_AMOUNT:-75000000}"
APPROVE_AMOUNT="${PROOF_FORGE_SOLANA_TOKEN_APPROVE_AMOUNT:-333000000}"
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

echo "=== Solana SPL Token ops CPI step 1: build fixture ELF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture spl-token-ops-cpi --format elf --solana-sbpf-arch "$SBPF_ARCH" \
  -o "$ELF_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture spl-token-ops-cpi --format elf failed"
[ -f "$ELF_OUTPUT" ] || fail "ELF not produced: $ELF_OUTPUT"

python3 - "$ARTIFACT_OUTPUT" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
if artifact.get("fixture") != "solana-spl-token-ops-cpi-elf":
    raise SystemExit("artifact fixture mismatch")
instructions = artifact.get("solanaInstructions", [])
expected_names = ["mint", "burn", "approve", "revoke"]
names = [instruction.get("name") for instruction in instructions]
if names != expected_names:
    raise SystemExit(f"instruction schema mismatch: {names}")
expected_accounts = [
    "last_mint_amount",
    "mint",
    "destination",
    "authority",
    "spl_token",
    "source",
    "delegate",
]
for instruction in instructions:
    accounts = [account.get("name") for account in instruction.get("accounts", [])]
    if accounts != expected_accounts:
        raise SystemExit(f"{instruction.get('name')} account schema mismatch: {accounts}")
for instruction in instructions[:3]:
    params = instruction.get("params", [])
    expected_params = [
        {"name": "amount", "type": "U64", "offset": 1, "byteSize": 8, "encoding": "le-u64"},
    ]
    if params != expected_params:
        raise SystemExit(f"{instruction.get('name')} parameter schema mismatch: {params}")
if instructions[3].get("params", []) != []:
    raise SystemExit(f"revoke parameter schema mismatch: {instructions[3].get('params')}")
cpis = {cpi.get("name"): cpi for cpi in artifact.get("solanaExtensions", {}).get("cpis", [])}
expected_cpis = {
    "token_mint": ("mint_to", "spl-token.mint_to"),
    "token_burn": ("burn", "spl-token.burn"),
    "token_approve": ("approve", "spl-token.approve"),
    "token_revoke": ("revoke", "spl-token.revoke"),
}
if set(cpis) != set(expected_cpis):
    raise SystemExit(f"CPI schema mismatch: {cpis}")
for name, (instruction, layout) in expected_cpis.items():
    cpi = cpis[name]
    if cpi.get("protocol") != "spl-token":
        raise SystemExit(f"{name} protocol mismatch: {cpi}")
    if cpi.get("instruction") != instruction:
        raise SystemExit(f"{name} instruction mismatch: {cpi}")
    if cpi.get("dataLayout") != layout:
        raise SystemExit(f"{name} data layout mismatch: {cpi}")
    if name != "token_revoke" and cpi.get("amountSource") != "amount":
        raise SystemExit(f"{name} amount source mismatch: {cpi}")
print("artifact validation: ok")
PY

echo "=== Solana SPL Token ops CPI step 2: generate local keypairs ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROGRAM_KEYPAIR" --force \
  || fail "program keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROGRAM_ID="$("$KEYGEN" pubkey "$PROGRAM_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"
echo "  program id: $PROGRAM_ID"

echo "=== Solana SPL Token ops CPI step 3: start Surfpool ==="
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

echo "=== Solana SPL Token ops CPI step 4: deploy program ==="
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$ELF_OUTPUT" \
  || fail "solana program deploy failed"

echo "=== Solana SPL Token ops CPI step 5: run Rust behavior checks ==="
PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROGRAM_ID" \
PROOF_FORGE_SOLANA_ARTIFACT="$ARTIFACT_OUTPUT" \
PROOF_FORGE_SOLANA_TOKEN_DECIMALS="$TOKEN_DECIMALS" \
PROOF_FORGE_SOLANA_TOKEN_INITIAL_SOURCE_AMOUNT="$INITIAL_SOURCE_AMOUNT" \
PROOF_FORGE_SOLANA_TOKEN_MINT_AMOUNT="$MINT_AMOUNT" \
PROOF_FORGE_SOLANA_TOKEN_BURN_AMOUNT="$BURN_AMOUNT" \
PROOF_FORGE_SOLANA_TOKEN_APPROVE_AMOUNT="$APPROVE_AMOUNT" \
  cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana --bin spl_token_ops_cpi_live_smoke \
  || fail "Rust SPL Token ops CPI checks failed"

echo "=== Solana SPL Token ops CPI Surfpool/Rust smoke: PASS ==="

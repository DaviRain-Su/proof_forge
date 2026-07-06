#!/usr/bin/env bash
# ProofForge Solana Associated Token Account create_idempotent CPI live smoke.
#
# Builds the Associated Token CPI SDK fixture, starts Surfpool, deploys the
# generated ELF with Solana CLI, creates an SPL mint through @solana/spl-token,
# invokes the generated program through @solana/web3.js, and verifies that the
# canonical associated token account was created while state records the call.
#
# Exit codes:
#   0 - all gates passed
#   1 - a gate failed
#   2 - a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_ASSOCIATED_TOKEN_CPI_OUT:-build/solana-associated-token-cpi-live}"
PROJECT_NAME="proofforge-associated-token-cpi-live"
ELF_OUTPUT="$OUT_DIR/$PROJECT_NAME.so"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROGRAM_KEYPAIR="$OUT_DIR/program-keypair.json"
JS_TEMPLATE="$REPO_ROOT/Tests/solana/associated_token_cpi_web3_smoke.mjs"
NODE_PROJECT="$OUT_DIR/web3"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
NPM_BIN="${NPM:-npm}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_ASSOCIATED_TOKEN_CPI_SBPF_ARCH:-v0}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_ASSOCIATED_TOKEN_CPI_SURFPOOL_PORT:-8918}"
WS_PORT="${PROOF_FORGE_ASSOCIATED_TOKEN_CPI_SURFPOOL_WS_PORT:-8919}"
RPC_URL="http://$RPC_HOST:$RPC_PORT"
WS_URL="ws://$RPC_HOST:$WS_PORT"
SURFPOOL_LOG_DIR="$OUT_DIR/surfpool-logs"
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
command -v node >/dev/null 2>&1 || skip "node not on PATH"
command -v "$NPM_BIN" >/dev/null 2>&1 || skip "npm not on PATH (set NPM=/path/to/npm)"
[ -f "$JS_TEMPLATE" ] || fail "Web3.js smoke template not found: $JS_TEMPLATE"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$NODE_PROJECT" "$SURFPOOL_LOG_DIR"

echo "=== Solana Associated Token CPI step 1: build fixture ELF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture associated-token-cpi --format elf \
  --solana-sbpf-arch "$SBPF_ARCH" \
  -o "$ELF_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge associated-token-cpi target-first emit failed"
[ -f "$ELF_OUTPUT" ] || fail "ELF not produced: $ELF_OUTPUT"

python3 - "$ARTIFACT_OUTPUT" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
if artifact.get("fixture") != "solana-associated-token-cpi-elf":
    raise SystemExit("artifact fixture mismatch")
instructions = artifact.get("solanaInstructions", [])
if [instruction.get("name") for instruction in instructions] != ["create_associated"]:
    raise SystemExit(f"instruction schema mismatch: {instructions}")
instruction = instructions[0]
expected_accounts = [
    "last_created_marker",
    "payer",
    "associated_account",
    "wallet",
    "mint",
    "system_program",
    "spl_token",
    "associated_token",
]
accounts = [account.get("name") for account in instruction.get("accounts", [])]
if accounts != expected_accounts:
    raise SystemExit(f"account schema mismatch: {accounts}")
if instruction.get("params", []) != [] or instruction.get("tag") != 0 or instruction.get("minDataLen") != 1:
    raise SystemExit(f"instruction ABI mismatch: {instruction}")
cpis = artifact.get("solanaExtensions", {}).get("cpis", [])
if len(cpis) != 1:
    raise SystemExit(f"CPI schema mismatch: {cpis}")
cpi = cpis[0]
expected = {
    "name": "create_associated_token",
    "program": "associated_token",
    "protocol": "associated-token",
    "instruction": "create_idempotent",
    "dataLayout": "associated-token.create_idempotent",
    "tokenProgram": "spl_token",
    "signed": False,
}
for key, value in expected.items():
    if cpi.get(key) != value:
        raise SystemExit(f"CPI {key} mismatch: {cpi}")
if [account.get("name") for account in cpi.get("accounts", [])] != [
    "payer",
    "associated_account",
    "wallet",
    "mint",
    "system_program",
    "spl_token",
]:
    raise SystemExit(f"CPI account order mismatch: {cpi.get('accounts')}")
print("artifact validation: ok")
PY

echo "=== Solana Associated Token CPI step 2: generate local keypairs ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROGRAM_KEYPAIR" --force \
  || fail "program keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROGRAM_ID="$("$KEYGEN" pubkey "$PROGRAM_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"
echo "  program id: $PROGRAM_ID"

echo "=== Solana Associated Token CPI step 3: start Surfpool ==="
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

echo "=== Solana Associated Token CPI step 4: deploy program ==="
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$ELF_OUTPUT" \
  || fail "solana program deploy failed"

echo "=== Solana Associated Token CPI step 5: run Web3.js behavior checks ==="
cp "$JS_TEMPLATE" "$NODE_PROJECT/associated_token_cpi_web3_smoke.mjs"
if [ ! -f "$NODE_PROJECT/package.json" ]; then
  ( cd "$NODE_PROJECT" && "$NPM_BIN" init -y >/dev/null ) \
    || fail "npm init failed"
fi
( cd "$NODE_PROJECT" && "$NPM_BIN" install --silent @solana/web3.js@^1.98.0 @solana/spl-token@^0.4.14 ) \
  || fail "npm install @solana/web3.js @solana/spl-token failed"

PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_WS_URL="$WS_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROGRAM_ID" \
PROOF_FORGE_SOLANA_ARTIFACT="$ARTIFACT_OUTPUT" \
  node "$NODE_PROJECT/associated_token_cpi_web3_smoke.mjs" \
  || fail "Web3.js Associated Token CPI checks failed"

echo "=== Solana Associated Token CPI Surfpool/Web3.js smoke: PASS ==="

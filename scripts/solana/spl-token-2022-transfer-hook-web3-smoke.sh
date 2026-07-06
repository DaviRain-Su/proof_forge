#!/usr/bin/env bash
# ProofForge Solana Token-2022 transfer-hook live smoke on Surfpool.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_SPL_TOKEN_2022_TRANSFER_HOOK_OUT:-build/solana-spl-token-2022-transfer-hook-live}"
PROJECT_NAME="proofforge-spl-token-2022-transfer-hook-live"
ELF_OUTPUT="$OUT_DIR/$PROJECT_NAME.so"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROGRAM_KEYPAIR="$OUT_DIR/program-keypair.json"
JS_TEMPLATE="$REPO_ROOT/Tests/solana/spl_token_2022_transfer_hook_web3_smoke.mjs"
NODE_PROJECT="$OUT_DIR/web3"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
NPM_BIN="${NPM:-npm}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_SPL_TOKEN_2022_TRANSFER_HOOK_SBPF_ARCH:-v0}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_SPL_TOKEN_2022_TRANSFER_HOOK_SURFPOOL_PORT:-8922}"
WS_PORT="${PROOF_FORGE_SPL_TOKEN_2022_TRANSFER_HOOK_SURFPOOL_WS_PORT:-8923}"
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
command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"
command -v "$SURFPOOL_BIN" >/dev/null 2>&1 || skip "surfpool not on PATH (set SURFPOOL=/path/to/surfpool)"
command -v "$SOLANA_BIN" >/dev/null 2>&1 || skip "solana CLI not on PATH (set SOLANA=/path/to/solana)"
command -v "$KEYGEN" >/dev/null 2>&1 || skip "solana-keygen not on PATH (set SOLANA_KEYGEN=/path/to/solana-keygen)"
command -v sbpf >/dev/null 2>&1 || skip "sbpf not on PATH"
command -v node >/dev/null 2>&1 || skip "node not on PATH"
command -v "$NPM_BIN" >/dev/null 2>&1 || skip "npm not on PATH (set NPM=/path/to/npm)"
[ -f "$JS_TEMPLATE" ] || fail "Web3.js smoke template not found: $JS_TEMPLATE"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$NODE_PROJECT" "$SURFPOOL_LOG_DIR"

echo "=== Solana Token-2022 transfer-hook step 1: build fixture ELF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture spl-token-2022-transfer-hook --format elf --solana-sbpf-arch "$SBPF_ARCH" \
  -o "$ELF_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture spl-token-2022-transfer-hook --format elf failed"
[ -f "$ELF_OUTPUT" ] || fail "ELF not produced: $ELF_OUTPUT"

python3 - "$ARTIFACT_OUTPUT" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
if artifact.get("fixture") != "solana-spl-token-2022-transfer-hook-elf":
    raise SystemExit("artifact fixture mismatch")

instructions = artifact.get("solanaInstructions", [])
names = [instruction.get("name") for instruction in instructions]
if names != ["initialize_extra_account_meta_list", "execute"]:
    raise SystemExit(f"instruction schema mismatch: {names}")

expected_accounts = [
    "source",
    "mint",
    "destination",
    "authority",
    "extra_account_meta_list",
    "sentinel",
    "system_program",
]
for instruction in instructions:
    accounts = [account.get("name") for account in instruction.get("accounts", [])]
    if accounts != expected_accounts:
        raise SystemExit(f"{instruction.get('name')} account schema mismatch: {accounts}")

init, execute = instructions
if init.get("minDataLen") != 25 or [param.get("offset") for param in init.get("params", [])] != [1, 9, 17]:
    raise SystemExit(f"init ABI mismatch: {init}")
if execute.get("minDataLen") != 16 or execute.get("params", [{}])[0].get("offset") != 8:
    raise SystemExit(f"execute ABI mismatch: {execute}")
if init["accounts"][0].get("signer") is not True or init["accounts"][0].get("writable") is not True:
    raise SystemExit("init source must be signer+writable")
if execute["accounts"][0].get("signer") is not False or execute["accounts"][0].get("writable") is not False:
    raise SystemExit("execute source must be readonly/non-signer")

actions = artifact.get("solanaIdl", {}).get("entrypointActions", {}).get("transferHookExtraMetas", [])
if len(actions) != 1:
    raise SystemExit(f"transfer-hook action schema mismatch: {actions}")
action = actions[0]
if action.get("extraAccounts") != ["sentinel", "system_program"]:
    raise SystemExit(f"extra account routing mismatch: {action}")
if action.get("executeDiscriminator") != "692565c54bfb661a" or action.get("extraAccountCount") != 2:
    raise SystemExit(f"extra account discriminator/count mismatch: {action}")
print("artifact validation: ok")
PY

echo "=== Solana Token-2022 transfer-hook step 2: generate local keypairs ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROGRAM_KEYPAIR" --force \
  || fail "program keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROGRAM_ID="$("$KEYGEN" pubkey "$PROGRAM_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"
echo "  program id: $PROGRAM_ID"

echo "=== Solana Token-2022 transfer-hook step 3: start Surfpool ==="
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

echo "=== Solana Token-2022 transfer-hook step 4: deploy program ==="
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$ELF_OUTPUT" \
  || fail "solana program deploy failed"

echo "=== Solana Token-2022 transfer-hook step 5: run Web3.js behavior checks ==="
cp "$JS_TEMPLATE" "$NODE_PROJECT/spl_token_2022_transfer_hook_web3_smoke.mjs"
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
  node "$NODE_PROJECT/spl_token_2022_transfer_hook_web3_smoke.mjs" \
  || fail "Web3.js Token-2022 transfer-hook checks failed"

echo "=== Solana Token-2022 transfer-hook Surfpool/Web3.js smoke: PASS ==="

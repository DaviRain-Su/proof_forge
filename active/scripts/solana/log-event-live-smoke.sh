#!/usr/bin/env bash
# ProofForge Solana log/event live smoke on Surfpool.
#
# Builds the generated event-log ELF, starts Surfpool, deploys with Solana CLI,
# invokes the program through the Rust live RPC harness, and verifies state plus
# transaction log output from sol_log_64_, sol_log_pubkey, and sol_log_data.
#
# Exit codes:
#   0 - all gates passed
#   1 - a gate failed
#   2 - a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_LOG_EVENT_OUT:-build/solana-log-event-live}"
PROJECT_NAME="proofforge-log-event-live"
ELF_OUTPUT="$OUT_DIR/$PROJECT_NAME.so"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROGRAM_KEYPAIR="$OUT_DIR/program-keypair.json"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_LOG_EVENT_SBPF_ARCH:-v0}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_LOG_EVENT_SURFPOOL_PORT:-8901}"
WS_PORT="${PROOF_FORGE_LOG_EVENT_SURFPOOL_WS_PORT:-8895}"
RPC_URL="http://$RPC_HOST:$RPC_PORT"
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
command -v cargo >/dev/null 2>&1 || skip "cargo not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$SURFPOOL_LOG_DIR"

echo "=== Solana log event step 1: build fixture ELF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture log-event --format elf --solana-sbpf-arch "$SBPF_ARCH" \
  -o "$ELF_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture log-event --format elf failed"
[ -f "$ELF_OUTPUT" ] || fail "ELF not produced: $ELF_OUTPUT"

python3 - "$ARTIFACT_OUTPUT" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
if artifact.get("fixture") != "solana-log-event-elf":
    raise SystemExit("artifact fixture mismatch")
capabilities = artifact.get("capabilities", [])
if "events.emit" not in capabilities:
    raise SystemExit(f"artifact missing events.emit capability: {capabilities}")
instructions = artifact.get("solanaInstructions", [])
instruction_names = [instruction.get("name") for instruction in instructions]
if instruction_names != ["emit", "log_state_pubkey", "log_state_data"]:
    raise SystemExit(f"instruction schema mismatch: {instructions}")
for instruction in instructions:
    accounts = [account.get("name") for account in instruction.get("accounts", [])]
    if accounts != ["last_logged_amount"]:
        raise SystemExit(f"account schema mismatch for {instruction.get('name')}: {accounts}")
params = instructions[0].get("params", [])
expected_params = [
    {"name": "amount", "type": "U64", "offset": 1, "byteSize": 8, "encoding": "le-u64"},
]
if params != expected_params:
    raise SystemExit(f"parameter schema mismatch: {params}")
if instructions[1].get("params", []) != []:
    raise SystemExit(f"log_state_pubkey should not have params: {instructions[1].get('params')}")
if instructions[2].get("params", []) != []:
    raise SystemExit(f"log_state_data should not have params: {instructions[2].get('params')}")
extensions = artifact.get("solanaExtensions", {})
pubkey_actions = extensions.get("pubkeyLogActions", [])
expected_pubkey_actions = [
    {
        "entrypoint": "log_state_pubkey",
        "log": "log_state_account",
        "op": "pubkey",
        "account": "last_logged_amount",
    }
]
if pubkey_actions != expected_pubkey_actions:
    raise SystemExit(f"pubkey log action schema mismatch: {pubkey_actions}")
data_actions = extensions.get("dataLogActions", [])
expected_data_actions = [
    {
        "entrypoint": "log_state_data",
        "log": "log_amount_data",
        "op": "data",
        "sourceState": "last_logged_amount",
        "bytes": 8,
    }
]
if data_actions != expected_data_actions:
    raise SystemExit(f"data log action schema mismatch: {data_actions}")
print("artifact validation: ok")
PY

echo "=== Solana log event step 2: generate local keypairs ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROGRAM_KEYPAIR" --force \
  || fail "program keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROGRAM_ID="$("$KEYGEN" pubkey "$PROGRAM_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"
echo "  program id: $PROGRAM_ID"

echo "=== Solana log event step 3: start Surfpool ==="
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

echo "=== Solana log event step 4: deploy program ==="
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$ELF_OUTPUT" \
  || fail "solana program deploy failed"

echo "=== Solana log event step 5: run Rust behavior checks ==="

PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROGRAM_ID" \
  cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana --bin log_event_live_smoke \
  || fail "Rust log event checks failed"

echo "=== Solana log event Surfpool/Rust smoke: PASS ==="

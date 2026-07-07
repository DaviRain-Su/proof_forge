#!/usr/bin/env bash
# ProofForge Solana EpochSchedule sysvar live smoke on Surfpool.
#
# Builds the generated EpochSchedule sysvar ELF, starts Surfpool, deploys with
# Solana CLI, invokes the program through the Rust live RPC harness, and
# verifies that the SDK sysvar target extension records the EpochSchedule
# fields into a program-owned state account.
#
# Exit codes:
#   0 - all gates passed
#   1 - a gate failed
#   2 - a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_EPOCH_SCHEDULE_OUT:-build/solana-epoch-schedule-sysvar-live}"
PROJECT_NAME="proofforge-epoch-schedule-sysvar-live"
ELF_OUTPUT="$OUT_DIR/$PROJECT_NAME.so"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROGRAM_KEYPAIR="$OUT_DIR/program-keypair.json"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_EPOCH_SCHEDULE_SBPF_ARCH:-v0}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_EPOCH_SCHEDULE_SURFPOOL_PORT:-8907}"
WS_PORT="${PROOF_FORGE_EPOCH_SCHEDULE_SURFPOOL_WS_PORT:-8908}"
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
command -v cargo >/dev/null 2>&1 || fail "cargo not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$SURFPOOL_LOG_DIR"

echo "=== Solana EpochSchedule sysvar step 1: build fixture ELF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture solana-epoch-schedule-sysvar --format elf --solana-sbpf-arch "$SBPF_ARCH" \
  -o "$ELF_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture solana-epoch-schedule-sysvar --format elf failed"
[ -f "$ELF_OUTPUT" ] || fail "ELF not produced: $ELF_OUTPUT"

python3 - "$ARTIFACT_OUTPUT" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
if artifact.get("fixture") != "solana-epoch-schedule-sysvar-elf":
    raise SystemExit("artifact fixture mismatch")
capabilities = artifact.get("capabilities", [])
for capability in ["env.block", "storage.scalar"]:
    if capability not in capabilities:
        raise SystemExit(f"artifact missing {capability} capability: {capabilities}")
instructions = artifact.get("solanaInstructions", [])
if len(instructions) != 1 or instructions[0].get("name") != "record_epoch_schedule":
    raise SystemExit(f"instruction schema mismatch: {instructions}")
accounts = [account.get("name") for account in instructions[0].get("accounts", [])]
if accounts != ["slots_per_epoch"]:
    raise SystemExit(f"account schema mismatch: {accounts}")
params = instructions[0].get("params", [])
if params != []:
    raise SystemExit(f"expected no parameters, got: {params}")
extensions = artifact.get("solanaExtensions", {})
sysvar_actions = extensions.get("sysvarActions", [])
expected = [{
    "entrypoint": "record_epoch_schedule",
    "sysvar": "read_epoch_schedule",
    "kind": "epoch_schedule",
    "field": "slots_per_epoch",
    "outputState": "slots_per_epoch",
    "featureGated": False,
}, {
    "entrypoint": "record_epoch_schedule",
    "sysvar": "read_leader_schedule_slot_offset",
    "kind": "epoch_schedule",
    "field": "leader_schedule_slot_offset",
    "outputState": "leader_schedule_slot_offset",
    "featureGated": False,
}, {
    "entrypoint": "record_epoch_schedule",
    "sysvar": "read_warmup",
    "kind": "epoch_schedule",
    "field": "warmup",
    "outputState": "warmup",
    "featureGated": False,
}, {
    "entrypoint": "record_epoch_schedule",
    "sysvar": "read_first_normal_epoch",
    "kind": "epoch_schedule",
    "field": "first_normal_epoch",
    "outputState": "first_normal_epoch",
    "featureGated": False,
}, {
    "entrypoint": "record_epoch_schedule",
    "sysvar": "read_first_normal_slot",
    "kind": "epoch_schedule",
    "field": "first_normal_slot",
    "outputState": "first_normal_slot",
    "featureGated": False,
}]
if sysvar_actions != expected:
    raise SystemExit(f"sysvar action mismatch: {sysvar_actions}")
print("artifact validation: ok")
PY

echo "=== Solana EpochSchedule sysvar step 2: generate local keypairs ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROGRAM_KEYPAIR" --force \
  || fail "program keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROGRAM_ID="$("$KEYGEN" pubkey "$PROGRAM_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"
echo "  program id: $PROGRAM_ID"

echo "=== Solana EpochSchedule sysvar step 3: start Surfpool ==="
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

echo "=== Solana EpochSchedule sysvar step 4: deploy program ==="
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$ELF_OUTPUT" \
  || fail "solana program deploy failed"

echo "=== Solana EpochSchedule sysvar step 5: run Rust behavior checks ==="
PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROGRAM_ID" \
  cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana --bin epoch_schedule_sysvar_live_smoke \
  || fail "Rust EpochSchedule sysvar checks failed"

echo "=== Solana EpochSchedule sysvar Surfpool/Rust smoke: PASS ==="

#!/usr/bin/env bash
# ProofForge Solana Token-2022 non-transferable plan live smoke on Surfpool.
#
# Generates the current Lean token fixture into a TokenSpec-backed Token-2022
# plan, starts Surfpool, then uses the Rust Solana harness to prove a token
# with NonTransferable can mint and burn but rejects TransferChecked.
#
# Exit codes:
#   0 - all gates passed
#   1 - a gate failed
#   2 - a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_TOKEN_2022_NON_TRANSFERABLE_LIVE_OUT:-build/solana-token-2022-non-transferable-live}"
TOKEN_SOURCE="${PROOF_FORGE_SOLANA_TOKEN_2022_NON_TRANSFERABLE_SOURCE:-ProofForge/Contract/Token/Examples/SoulboundToken.lean}"
TOKEN_PLAN="$OUT_DIR/SoulboundToken.solana-token-2022-plan.json"
PLAN_EMITTER="${PROOF_FORGE_SOLANA_TOKEN_2022_NON_TRANSFERABLE_PLAN_EMITTER:-Tests/TokenPlanEmit.lean}"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_SOLANA_TOKEN_2022_NON_TRANSFERABLE_SURFPOOL_PORT:-8896}"
WS_PORT="${PROOF_FORGE_SOLANA_TOKEN_2022_NON_TRANSFERABLE_SURFPOOL_WS_PORT:-8895}"
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
command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"
command -v "$SURFPOOL_BIN" >/dev/null 2>&1 || skip "surfpool not on PATH (set SURFPOOL=/path/to/surfpool)"
command -v "$SOLANA_BIN" >/dev/null 2>&1 || skip "solana CLI not on PATH (set SOLANA=/path/to/solana)"
command -v "$KEYGEN" >/dev/null 2>&1 || skip "solana-keygen not on PATH (set SOLANA_KEYGEN=/path/to/solana-keygen)"
command -v cargo >/dev/null 2>&1 || skip "cargo not on PATH"
[ -f "$TOKEN_SOURCE" ] || fail "token source not found: $TOKEN_SOURCE"
[ -f "$PLAN_EMITTER" ] || fail "Lean token plan emitter not found: $PLAN_EMITTER"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$SURFPOOL_LOG_DIR"

echo "=== Solana Token-2022 non-transferable live step 1: emit structured token plan ==="
lake env lean --run "$PLAN_EMITTER" soulbound "$TOKEN_PLAN" \
  || fail "Lean token plan emission failed"
[ -f "$TOKEN_PLAN" ] || fail "token plan not written: $TOKEN_PLAN"

python3 - "$TOKEN_PLAN" <<'PY'
import json
import sys

plan = json.load(open(sys.argv[1]))
if plan.get("format") != "proof-forge-token-plan-v0":
    raise SystemExit("token plan format mismatch")
if plan.get("sourceKind") != "lean-token-source":
    raise SystemExit(f"this live gate expects a Lean token source plan, got {plan.get('sourceKind')}")
if plan.get("standard") != "spl-token-2022":
    raise SystemExit(f"this live gate expects a Token-2022 plan, got {plan.get('standard')}")
if "token-2022.extension.non_transferable" not in plan.get("operations", []):
    raise SystemExit("plan missing non-transferable operation")
if plan.get("solana", {}).get("programs", {}).get("token") != "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb":
    raise SystemExit("Token-2022 program id mismatch")
extensions = [extension.get("extension") for extension in plan.get("solana", {}).get("extensions", [])]
if "non_transferable" not in extensions:
    raise SystemExit("plan missing non_transferable extension")
names = [instruction.get("name") for instruction in plan.get("solana", {}).get("instructions", [])]
for name in [
    "create_mint_account",
    "initialize_non_transferable_mint",
    "initialize_mint",
    "create_owner_ata",
    "create_recipient_ata",
    "mint_to_initial_supply",
    "transfer_checked",
    "burn",
]:
    if name not in names:
        raise SystemExit(f"missing planned instruction: {name}")
if names.index("initialize_non_transferable_mint") >= names.index("initialize_mint"):
    raise SystemExit("non-transferable mint should initialize before mint")
print("token-2022 non-transferable plan schema: ok")
PY

echo "=== Solana Token-2022 non-transferable live step 2: generate local payer keypair ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"

echo "=== Solana Token-2022 non-transferable live step 3: start Surfpool ==="
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

echo "=== Solana Token-2022 non-transferable live step 4: run Rust behavior checks ==="

PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_TOKEN_PLAN="$TOKEN_PLAN" \
  cargo run --quiet --manifest-path testkit/Cargo.toml \
    -p proof-forge-testkit-harness-solana \
    --bin token_2022_non_transferable_plan_live_smoke \
  || fail "Rust Solana Token-2022 non-transferable checks failed"

echo "=== Solana Token-2022 non-transferable Surfpool/Rust smoke: PASS ==="

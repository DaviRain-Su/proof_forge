#!/usr/bin/env bash
# Generated ELF smoke for [payer, payer, system_program] account roles.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_DUPLICATE_OUT:-build/solana-duplicate-accounts-live}"
PROJECT_NAME="proofforge-duplicate-accounts-live"
ASM_OUTPUT="$OUT_DIR/$PROJECT_NAME.s"
PROJECT_DIR="$OUT_DIR/$PROJECT_NAME-sbpf-project"
ELF_OUTPUT="$PROJECT_DIR/deploy/$PROJECT_NAME.so"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROGRAM_KEYPAIR="$OUT_DIR/program-keypair.json"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
SBPF_BIN="${SBPF:-sbpf}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_LIVE_SBPF_ARCH:-v0}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_SURFPOOL_PORT:-8899}"
WS_PORT="${PROOF_FORGE_SURFPOOL_WS_PORT:-8900}"
RPC_URL="http://$RPC_HOST:$RPC_PORT"
SURFPOOL_PID=""

fail() { echo "FAIL: $1" >&2; exit 1; }
skip() { echo "SKIP: $1" >&2; exit 2; }

cleanup() {
  if [ -n "$SURFPOOL_PID" ] && kill -0 "$SURFPOOL_PID" >/dev/null 2>&1; then
    "$REPO_ROOT/scripts/solana/stop-background-process.sh" "$SURFPOOL_PID" || true
    wait "$SURFPOOL_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v cargo >/dev/null 2>&1 || fail "cargo not on PATH"
command -v "$SBPF_BIN" >/dev/null 2>&1 || skip "sbpf not on PATH"
command -v "$SURFPOOL_BIN" >/dev/null 2>&1 || skip "surfpool not on PATH"
command -v "$SOLANA_BIN" >/dev/null 2>&1 || skip "solana CLI not on PATH"
command -v "$KEYGEN" >/dev/null 2>&1 || skip "solana-keygen not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$PROJECT_DIR/src/$PROJECT_NAME" "$OUT_DIR/surfpool-logs"

echo "=== Solana duplicate accounts step 1: emit and build generated ELF ==="
lake env lean --run Tests/Backend/Solana/EmitDuplicateAccountProgram.lean "$ASM_OUTPUT" \
  || fail "duplicate-account assembly emission failed"
cp "$ASM_OUTPUT" "$PROJECT_DIR/src/$PROJECT_NAME/$PROJECT_NAME.s"
(cd "$PROJECT_DIR" && "$SBPF_BIN" build --arch "$SBPF_ARCH") \
  || fail "sbpf build failed"
[ -f "$ELF_OUTPUT" ] || fail "ELF not produced: $ELF_OUTPUT"

echo "=== Solana duplicate accounts step 2: start Surfpool and deploy ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROGRAM_KEYPAIR" --force
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROGRAM_ID="$("$KEYGEN" pubkey "$PROGRAM_KEYPAIR")"

"$SURFPOOL_BIN" start \
  --host "$RPC_HOST" --port "$RPC_PORT" --ws-port "$WS_PORT" \
  --offline --no-tui --no-studio --no-deploy \
  --airdrop-keypair-path "$PAYER_KEYPAIR" \
  --log-path "$OUT_DIR/surfpool-logs" \
  > "$OUT_DIR/surfpool.stdout.log" 2> "$OUT_DIR/surfpool.stderr.log" &
SURFPOOL_PID="$!"

for _ in $(seq 1 60); do
  if "$SOLANA_BIN" --url "$RPC_URL" cluster-version >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$SURFPOOL_PID" >/dev/null 2>&1; then
    sed -n '1,160p' "$OUT_DIR/surfpool.stderr.log" >&2 || true
    fail "surfpool exited before RPC became available"
  fi
  sleep 1
done
"$SOLANA_BIN" --url "$RPC_URL" cluster-version >/dev/null 2>&1 \
  || fail "surfpool RPC did not become ready"
"$SOLANA_BIN" --url "$RPC_URL" airdrop 20 "$PAYER_PUBKEY" >/dev/null
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROGRAM_KEYPAIR" --skip-feature-verify --skip-preflight --use-rpc \
  "$ELF_OUTPUT" \
  || fail "program deploy failed"

echo "=== Solana duplicate accounts step 3: invoke [payer, payer, system_program] ==="
PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROGRAM_ID" \
  cargo run --manifest-path testkit/Cargo.toml \
    -p proof-forge-testkit-harness-solana --bin duplicate_accounts_live_smoke \
  || fail "duplicate-account live invocation failed"

echo "=== Solana duplicate account Surfpool smoke: PASS ==="

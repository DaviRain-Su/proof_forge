#!/usr/bin/env bash
# ProofForge Solana Token-2022 Pausable direct CPI live smoke on Surfpool.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_SPL_TOKEN_2022_PAUSABLE_CPI_OUT:-build/solana-spl-token-2022-pausable-cpi-live}"
PROJECT_NAME="proofforge-spl-token-2022-pausable-cpi-live"
PROJECT_DIR="$OUT_DIR/$PROJECT_NAME-sbpf-project"
ELF_OUTPUT="$OUT_DIR/$PROJECT_NAME.so"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
IDL_OUTPUT="$PROJECT_DIR/proof-forge-idl.json"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROGRAM_KEYPAIR="$OUT_DIR/program-keypair.json"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_SPL_TOKEN_2022_PAUSABLE_CPI_SBPF_ARCH:-v0}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_SPL_TOKEN_2022_PAUSABLE_CPI_SURFPOOL_PORT:-8904}"
WS_PORT="${PROOF_FORGE_SPL_TOKEN_2022_PAUSABLE_CPI_SURFPOOL_WS_PORT:-8897}"
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
command -v sbpf >/dev/null 2>&1 || skip "sbpf not on PATH"
command -v cargo >/dev/null 2>&1 || skip "cargo not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$SURFPOOL_LOG_DIR"

echo "=== Solana Token-2022 Pausable direct CPI step 1: build fixture ELF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture spl-token-2022-pausable-cpi --format elf --solana-sbpf-arch "$SBPF_ARCH" \
  -o "$ELF_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture spl-token-2022-pausable-cpi --format elf failed"
[ -f "$ELF_OUTPUT" ] || fail "ELF not produced: $ELF_OUTPUT"

python3 - "$ARTIFACT_OUTPUT" "$IDL_OUTPUT" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
idl = json.loads(pathlib.Path(sys.argv[2]).read_text())
if artifact.get("fixture") != "solana-spl-token-2022-pausable-cpi-elf":
    raise SystemExit("artifact fixture mismatch")

instructions = artifact.get("solanaInstructions", [])
expected_names = ["initialize_pausable_config", "pause", "resume"]
names = [instruction.get("name") for instruction in instructions]
if names != expected_names:
    raise SystemExit(f"instruction schema mismatch: {names}")

expected_accounts = ["last_marker", "pausable_mint", "spl_token_2022", "pausable_authority"]
for instruction in instructions:
    accounts = [account.get("name") for account in instruction.get("accounts", [])]
    if accounts != expected_accounts:
        raise SystemExit(f"{instruction.get('name')} account schema mismatch: {accounts}")
    if instruction.get("params"):
        raise SystemExit(f"{instruction.get('name')} should not declare params: {instruction.get('params')}")

cpis = {cpi.get("name"): cpi for cpi in artifact.get("solanaExtensions", {}).get("cpis", [])}
expected_cpis = {
    "token_2022_init_pausable_config": "token-2022.initialize_pausable_config",
    "token_2022_pause": "token-2022.pause",
    "token_2022_resume": "token-2022.resume",
}
if list(cpis) != list(expected_cpis):
    raise SystemExit(f"CPI schema mismatch: {list(cpis)}")
for name, layout in expected_cpis.items():
    cpi = cpis[name]
    if cpi.get("program") != "spl_token_2022":
        raise SystemExit(f"{name} program mismatch: {cpi}")
    if cpi.get("protocol") != "token-2022":
        raise SystemExit(f"{name} protocol mismatch: {cpi}")
    if cpi.get("dataLayout") != layout:
        raise SystemExit(f"{name} data layout mismatch: {cpi}")

idl_cpis = {cpi.get("name"): cpi for cpi in idl.get("cpis", [])}
init_pausable = idl_cpis.get("token_2022_init_pausable_config")
if not init_pausable:
    raise SystemExit("IDL missing token_2022_init_pausable_config CPI")
if init_pausable.get("pausableAuthority") != "pausable_authority":
    raise SystemExit("IDL pausable config authority source mismatch")
print("artifact validation: ok")
PY

echo "=== Solana Token-2022 Pausable direct CPI step 2: generate local keypairs ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROGRAM_KEYPAIR" --force \
  || fail "program keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROGRAM_ID="$("$KEYGEN" pubkey "$PROGRAM_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"
echo "  program id: $PROGRAM_ID"

echo "=== Solana Token-2022 Pausable direct CPI step 3: start Surfpool ==="
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

echo "=== Solana Token-2022 Pausable direct CPI step 4: deploy program ==="
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$ELF_OUTPUT" \
  || fail "solana program deploy failed"

echo "=== Solana Token-2022 Pausable direct CPI step 5: run Rust behavior checks ==="

PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROGRAM_ID" \
  cargo run --quiet --manifest-path testkit/Cargo.toml \
    -p proof-forge-testkit-harness-solana \
    --bin spl_token_2022_pausable_cpi_live_smoke \
  || fail "Rust Token-2022 Pausable direct CPI checks failed"

echo "=== Solana Token-2022 Pausable direct CPI Surfpool/Rust smoke: PASS ==="

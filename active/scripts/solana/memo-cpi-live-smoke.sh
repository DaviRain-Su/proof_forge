#!/usr/bin/env bash
# ProofForge Solana Memo Program CPI live smoke on Surfpool.
#
# Builds the Memo CPI SDK fixture, starts Surfpool, deploys the generated ELF,
# invokes it through the Rust live RPC harness, and verifies that the generated program
# records the raw one-word memo payload while the transaction logs include the
# native Memo program invocation.
#
# Exit codes:
#   0 - all gates passed
#   1 - a gate failed
#   2 - a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_MEMO_CPI_OUT:-build/solana-memo-cpi-live}"
PROJECT_NAME="proofforge-memo-cpi-live"
ELF_OUTPUT="$OUT_DIR/$PROJECT_NAME.so"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROGRAM_KEYPAIR="$OUT_DIR/program-keypair.json"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_MEMO_CPI_SBPF_ARCH:-v0}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_MEMO_CPI_SURFPOOL_PORT:-8914}"
WS_PORT="${PROOF_FORGE_MEMO_CPI_SURFPOOL_WS_PORT:-8913}"
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
command -v cargo >/dev/null 2>&1 || fail "cargo not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$SURFPOOL_LOG_DIR"

echo "=== Solana Memo CPI step 1: build fixture ELF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture solana-memo-cpi --format elf --solana-sbpf-arch "$SBPF_ARCH" \
  -o "$ELF_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture solana-memo-cpi --format elf failed"
[ -f "$ELF_OUTPUT" ] || fail "ELF not produced: $ELF_OUTPUT"

python3 - "$ARTIFACT_OUTPUT" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
if artifact.get("fixture") != "solana-memo-cpi-elf":
    raise SystemExit("artifact fixture mismatch")
capabilities = artifact.get("capabilities", [])
for capability in ["crosscall.cpi", "storage.scalar"]:
    if capability not in capabilities:
        raise SystemExit(f"artifact missing {capability}: {capabilities}")
instructions = artifact.get("solanaInstructions", [])
names = [ix.get("name") for ix in instructions]
if names != ["log_memo", "log_memo_bytes"]:
    raise SystemExit(f"instruction schema mismatch: {names}")
log_memo = instructions[0]
accounts = [account.get("name") for account in log_memo.get("accounts", [])]
if accounts != ["last_memo_word", "memo"]:
    raise SystemExit(f"account schema mismatch: {accounts}")
params = log_memo.get("params", [])
expected_params = [
    {"name": "memoArg", "type": "U64", "offset": 1, "byteSize": 8, "encoding": "le-u64"},
]
if params != expected_params:
    raise SystemExit(f"parameter schema mismatch: {params}")
log_bytes = instructions[1]
bytes_params = log_bytes.get("params", [])
expected_bytes_params = [
    {
        "name": "memoBytes",
        "type": "Array<U8,16>",
        "offset": 1,
        "byteSize": 16,
        "encoding": "raw-bytes",
    },
]
if bytes_params != expected_bytes_params:
    raise SystemExit(f"multi-byte parameter schema mismatch: {bytes_params}")
cpis = artifact.get("solanaExtensions", {}).get("cpis", [])
if len(cpis) != 2:
    raise SystemExit(f"CPI schema count mismatch: {cpis}")
by_name = {c.get("name"): c for c in cpis}
for name, source in (("memo_call", "memoArg"), ("memo_bytes_call", "memoBytes")):
    cpi = by_name.get(name)
    if cpi is None:
        raise SystemExit(f"missing CPI {name}: {cpis}")
    expected = {
        "name": name,
        "program": "memo",
        "instruction": "memo",
        "protocol": "memo",
        "dataLayout": "memo.memo",
        "memoSource": source,
    }
    for key, value in expected.items():
        if cpi.get(key) != value:
            raise SystemExit(f"CPI field {key} mismatch for {name}: {cpi}")
    if cpi.get("accounts") != []:
        raise SystemExit(f"Memo CPI should not declare CPI account metas: {cpi}")
print("artifact validation: ok")
PY

echo "=== Solana Memo CPI step 2: generate local keypairs ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROGRAM_KEYPAIR" --force \
  || fail "program keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROGRAM_ID="$("$KEYGEN" pubkey "$PROGRAM_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"
echo "  program id: $PROGRAM_ID"

echo "=== Solana Memo CPI step 3: start Surfpool ==="
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

echo "=== Solana Memo CPI step 4: deploy program ==="
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$ELF_OUTPUT" \
  || fail "solana program deploy failed"

echo "=== Solana Memo CPI step 5: run Rust behavior checks ==="
PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROGRAM_ID" \
  cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana --bin memo_cpi_live_smoke \
  || fail "Rust Memo CPI checks failed"

echo "=== Solana Memo CPI Surfpool/Rust smoke: PASS ==="

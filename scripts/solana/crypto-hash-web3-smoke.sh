#!/usr/bin/env bash
# ProofForge Solana SHA-256/Keccak-256/Blake3 syscall live smoke on Surfpool.
#
# Builds the generated crypto.hash ELF, starts Surfpool, deploys with Solana
# CLI, invokes it through the Rust live RPC harness, and compares the state
# digests against Rust SHA-256, Keccak-256, and Blake3 references.
#
# Exit codes:
#   0 - all gates passed
#   1 - a gate failed
#   2 - a prerequisite is missing (skipped)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_SOLANA_CRYPTO_HASH_OUT:-build/solana-crypto-hash-live}"
PROJECT_NAME="proofforge-crypto-hash-live"
ELF_OUTPUT="$OUT_DIR/$PROJECT_NAME.so"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
PAYER_KEYPAIR="$OUT_DIR/payer.json"
PROGRAM_KEYPAIR="$OUT_DIR/program-keypair.json"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
SBPF_ARCH="${PROOF_FORGE_SOLANA_CRYPTO_HASH_SBPF_ARCH:-v0}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_CRYPTO_HASH_SURFPOOL_PORT:-8904}"
WS_PORT="${PROOF_FORGE_CRYPTO_HASH_SURFPOOL_WS_PORT:-8898}"
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

echo "=== Solana crypto hash step 1: build fixture ELF ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture solana-crypto-hash --format elf --solana-sbpf-arch "$SBPF_ARCH" \
  -o "$ELF_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture solana-crypto-hash --format elf failed"
[ -f "$ELF_OUTPUT" ] || fail "ELF not produced: $ELF_OUTPUT"

python3 - "$ARTIFACT_OUTPUT" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text())
if artifact.get("fixture") != "solana-crypto-hash-elf":
    raise SystemExit("artifact fixture mismatch")
capabilities = artifact.get("capabilities", [])
for capability in ["crypto.hash", "storage.scalar"]:
    if capability not in capabilities:
        raise SystemExit(f"artifact missing {capability} capability: {capabilities}")
instructions = artifact.get("solanaInstructions", [])
names = [instruction.get("name") for instruction in instructions]
if names != ["set_preimage", "hash_preimage", "keccak_preimage", "blake3_preimage"]:
    raise SystemExit(f"instruction schema mismatch: {names}")
params = instructions[0].get("params", [])
if len(params) != 1 or params[0].get("name") != "value" or params[0].get("offset") != 1:
    raise SystemExit(f"set_preimage parameter schema mismatch: {params}")
extensions = artifact.get("solanaExtensions", {})
crypto_actions = extensions.get("cryptoHashActions", [])
if len(crypto_actions) != 3:
    raise SystemExit(f"expected three crypto hash actions: {crypto_actions}")
actions = {(action.get("crypto"), action.get("op")): action for action in crypto_actions}
expected_actions = {
    ("hash_preimage", "sha256"): (["hash0", "hash1", "hash2", "hash3"], False),
    ("keccak_preimage", "keccak256"): (["keccak0", "keccak1", "keccak2", "keccak3"], False),
    ("blake3_preimage", "blake3"): (["blake0", "blake1", "blake2", "blake3"], True),
}
for key, (output_states, feature_gated) in expected_actions.items():
    action = actions.get(key)
    if action is None:
        raise SystemExit(f"missing crypto action {key}: {crypto_actions}")
    if action.get("inputState") != "preimage" or action.get("bytes") != 8:
        raise SystemExit(f"crypto action input mismatch: {action}")
    if action.get("outputStates") != output_states:
        raise SystemExit(f"crypto action output mismatch: {action}")
    if action.get("featureGated") is not feature_gated:
        raise SystemExit(f"crypto action feature gate mismatch: {action}")
print("artifact validation: ok")
PY

echo "=== Solana crypto hash step 2: generate local keypairs ==="
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PAYER_KEYPAIR" --force \
  || fail "payer keypair generation failed"
"$KEYGEN" new --no-bip39-passphrase --silent -o "$PROGRAM_KEYPAIR" --force \
  || fail "program keypair generation failed"
PAYER_PUBKEY="$("$KEYGEN" pubkey "$PAYER_KEYPAIR")"
PROGRAM_ID="$("$KEYGEN" pubkey "$PROGRAM_KEYPAIR")"
echo "  payer: $PAYER_PUBKEY"
echo "  program id: $PROGRAM_ID"

echo "=== Solana crypto hash step 3: start Surfpool ==="
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

echo "=== Solana crypto hash step 4: deploy program ==="
"$SOLANA_BIN" program deploy \
  --url "$RPC_URL" \
  --keypair "$PAYER_KEYPAIR" \
  --program-id "$PROGRAM_KEYPAIR" \
  --skip-feature-verify \
  --skip-preflight \
  --use-rpc \
  "$ELF_OUTPUT" \
  || fail "solana program deploy failed"

echo "=== Solana crypto hash step 5: run Rust behavior checks ==="

PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$PAYER_KEYPAIR" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROGRAM_ID" \
  cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana --bin crypto_hash_live_smoke \
  || fail "Rust crypto hash checks failed"

echo "=== Solana crypto hash Surfpool/Rust smoke: PASS ==="

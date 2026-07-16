#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OUT="${PROOF_FORGE_SOLANA_NFT_LIVE_OUT:-build/solana-nft-live}"
RPC_HOST="${PROOF_FORGE_SURFPOOL_HOST:-127.0.0.1}"
RPC_PORT="${PROOF_FORGE_SURFPOOL_PORT:-8899}"
WS_PORT="${PROOF_FORGE_SURFPOOL_WS_PORT:-8900}"
RPC_URL="http://$RPC_HOST:$RPC_PORT"
SURFPOOL_BIN="${SURFPOOL:-surfpool}"
SOLANA_BIN="${SOLANA:-solana}"
KEYGEN="${SOLANA_KEYGEN:-solana-keygen}"
SURFPOOL_PID=""

fail() { echo "FAIL: $1" >&2; exit 1; }
cleanup() {
  if [[ -n "$SURFPOOL_PID" ]] && kill -0 "$SURFPOOL_PID" 2>/dev/null; then
    kill "$SURFPOOL_PID" 2>/dev/null || true
    wait "$SURFPOOL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for tool in lake sbpf cargo "$SURFPOOL_BIN" "$SOLANA_BIN" "$KEYGEN"; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool not on PATH"
done

rm -rf "$OUT"
mkdir -p "$OUT/project/src/nft" "$OUT/logs"
if [[ -n "${PROOF_FORGE_SOLANA_NFT_ASM:-}" ]]; then
  cp "$PROOF_FORGE_SOLANA_NFT_ASM" "$OUT/project/src/nft/nft.s"
else
  NFT_OUT="$OUT/artifacts" scripts/portable/nft-multi-target.sh >/dev/null
  cp "$OUT/artifacts/solana/Nft.s" "$OUT/project/src/nft/nft.s"
fi
(cd "$OUT/project" && sbpf build --arch v0) || fail "sbpf NFT build failed"
ELF="$OUT/project/deploy/nft.so"
[[ -f "$ELF" ]] || fail "NFT ELF missing"

"$KEYGEN" new --no-bip39-passphrase --silent -o "$OUT/payer.json" --force
"$KEYGEN" new --no-bip39-passphrase --silent -o "$OUT/program.json" --force
PAYER="$($KEYGEN pubkey "$OUT/payer.json")"
PROGRAM_ID="$($KEYGEN pubkey "$OUT/program.json")"

"$SURFPOOL_BIN" start --host "$RPC_HOST" --port "$RPC_PORT" --ws-port "$WS_PORT" \
  --offline --no-tui --no-studio --no-deploy \
  --airdrop-keypair-path "$OUT/payer.json" --log-path "$OUT/logs" \
  >"$OUT/surfpool.stdout.log" 2>"$OUT/surfpool.stderr.log" &
SURFPOOL_PID="$!"
for _ in $(seq 1 60); do
  "$SOLANA_BIN" --url "$RPC_URL" cluster-version >/dev/null 2>&1 && break
  kill -0 "$SURFPOOL_PID" 2>/dev/null || fail "surfpool exited before RPC ready"
  sleep 1
done
"$SOLANA_BIN" --url "$RPC_URL" cluster-version >/dev/null 2>&1 || fail "Surfpool RPC not ready"
"$SOLANA_BIN" --url "$RPC_URL" airdrop 20 "$PAYER" >/dev/null
"$SOLANA_BIN" program deploy --url "$RPC_URL" --keypair "$OUT/payer.json" \
  --program-id "$OUT/program.json" --skip-feature-verify --skip-preflight --use-rpc "$ELF"

PROOF_FORGE_SOLANA_RPC_URL="$RPC_URL" \
PROOF_FORGE_SOLANA_PAYER="$OUT/payer.json" \
PROOF_FORGE_SOLANA_PROGRAM_ID="$PROGRAM_ID" \
  cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana \
    --bin nft_live_smoke

echo "solana-nft-live: ok (mint · owner/balance · transfer · rejection)"

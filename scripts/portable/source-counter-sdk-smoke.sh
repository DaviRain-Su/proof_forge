#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.foundry/bin:$PATH"

SOURCE="${PROOF_FORGE_SOURCE_COUNTER:-Examples/Product/Counter.lean}"
OUT_ROOT="${PROOF_FORGE_SOURCE_COUNTER_SDK_OUT:-build/source-counter-sdk}"

rm -rf "$OUT_ROOT"
mkdir -p "$OUT_ROOT"/{evm,solana-sbpf-asm,wasm-near}

lake build proof-forge >/dev/null
lake env proof-forge build --target evm --root . --format bytecode \
  -o "$OUT_ROOT/evm/Counter.bin" \
  --yul-output "$OUT_ROOT/evm/Counter.yul" \
  "$SOURCE"
lake env proof-forge build --target solana-sbpf-asm --format s --root . \
  -o "$OUT_ROOT/solana-sbpf-asm/Counter.s" \
  "$SOURCE"
lake env proof-forge build --target wasm-near --root . --format wat \
  -o "$OUT_ROOT/wasm-near" \
  "$SOURCE"

python3 scripts/sdk/validate-sdk-schema.py \
  "$OUT_ROOT/evm/proof-forge-sdk.json" \
  "$OUT_ROOT/solana-sbpf-asm/proof-forge-sdk.json" \
  "$OUT_ROOT/wasm-near/proof-forge-sdk.json" \
  --expect-schema proof-forge.sdk-schema.v0
python3 scripts/sdk/validate-sdk-artifact-refs.py \
  --require-relative \
  --reject-absolute \
  "$OUT_ROOT/evm/proof-forge-sdk.json" \
  "$OUT_ROOT/solana-sbpf-asm/proof-forge-sdk.json" \
  "$OUT_ROOT/wasm-near/proof-forge-sdk.json"

SUI_LOG="$OUT_ROOT/move-sui-source.log"
if lake env proof-forge build --target move-sui --root . -o "$OUT_ROOT/move-sui" "$SOURCE" >"$SUI_LOG" 2>&1; then
  python3 scripts/sdk/validate-sdk-schema.py \
    "$OUT_ROOT/move-sui/proof-forge-sdk.json" \
    --expect-schema proof-forge.sdk-schema.v0 \
    --expect-target move-sui
  python3 scripts/sdk/validate-sdk-artifact-refs.py \
    --require-relative \
    --reject-absolute \
    "$OUT_ROOT/move-sui/proof-forge-sdk.json"
else
  grep -Fq "move-sui" "$SUI_LOG"
  grep -Fq "source" "$SUI_LOG"
  grep -Fq "out of scope" "$SUI_LOG"
fi

echo "source-counter-sdk-smoke: ok"

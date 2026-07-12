#!/usr/bin/env bash
# Portable NFT multi-target smoke.
#
# One NFTSpec source → EVM ERC-721 · Solana Metaplex · NEAR NEP-171.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.foundry/bin:$PATH"

SOURCE="${NFT_SOURCE:-Examples/Product/Nft.lean}"
OUT="${NFT_OUT:-build/portable-nft}"

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

command -v lake >/dev/null 2>&1 || { echo "lake not on PATH" >&2; exit 1; }
mkdir -p "$OUT/evm" "$OUT/solana" "$OUT/near"

(cd "$ROOT" && lake build proof-forge Examples.Product.Nft >/dev/null)

echo "portable-nft: EVM"
"${proof_forge[@]}" build --target evm --nft --root . \
  -o "$OUT/evm/Nft.bin" \
  --yul-output "$OUT/evm/Nft.yul" \
  --artifact-output "$OUT/evm/Nft.evm-artifact.json" \
  "$SOURCE" || { echo "EVM NFT build failed" >&2; exit 1; }
[[ -f "$OUT/evm/Nft.bin" ]] || { echo "EVM NFT: missing .bin" >&2; exit 1; }

echo "portable-nft: Solana sBPF"
"${proof_forge[@]}" build --target solana-sbpf-asm --nft --root . \
  -o "$OUT/solana/Nft.s" \
  --artifact-output "$OUT/solana/Nft.solana-artifact.json" \
  "$SOURCE" || { echo "Solana NFT build failed" >&2; exit 1; }
[[ -f "$OUT/solana/Nft.s" ]] || { echo "Solana NFT: missing .s" >&2; exit 1; }

echo "portable-nft: NEAR/Wasm"
"${proof_forge[@]}" build --target wasm-near --nft --root . \
  -o "$OUT/near" \
  --artifact-output "$OUT/near/Nft.near-artifact.json" \
  "$SOURCE" || { echo "NEAR NFT build failed" >&2; exit 1; }
[[ -f "$OUT/near/nft.wat" ]] || [[ -f "$OUT/near/erc721.wat" ]] || [[ -f "$OUT/near/erc721mixin.wat" ]] || {
  echo "NEAR NFT: missing .wat" >&2; exit 1; }

echo "portable-nft-multi-target: ok (evm · solana · near)"
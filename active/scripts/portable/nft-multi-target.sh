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
[[ -f "$OUT/near/nearnft.wat" ]] || {
  echo "NEAR NFT: missing .wat" >&2; exit 1; }

python3 - "$OUT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
cases = [
    (root / "evm/Nft.evm-artifact.json", "evm", "erc-721", "ERC721", "evm-bytecode"),
    (root / "solana/Nft.solana-artifact.json", "solana-sbpf-asm", "metaplex", "MetaplexNft", "sbpf-asm"),
    (root / "near/Nft.near-artifact.json", "wasm-near", "nep-171", "NearNft", "wasm"),
]
for path, target, standard, module, output_kind in cases:
    data = json.loads(path.read_text())
    assert data["target"] == target, (path, data.get("target"))
    assert data["standardId"] == standard, (path, data.get("standardId"))
    bundle = data["artifactBundle"]
    assert bundle["targetId"] == target
    assert bundle["source"]["moduleName"] == module
    assert any(item["kind"] == output_kind for item in bundle["outputs"])
    for item in bundle["outputs"]:
        assert item.get("path") and item.get("sha256") and item.get("bytes", 0) > 0
print("portable-nft-artifacts: ok (target + standard + source + digests)")
PY

echo "portable-nft-multi-target: ok (evm · solana · near)"

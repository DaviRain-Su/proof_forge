#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

CATALOG="Examples/Product/catalog.json"
CANONICAL_DIR="Examples/Product/Canonical"
OUT="${PROOF_FORGE_EVM_CANONICAL_PRODUCT_OUT:-build/evm-canonical-products}"
EXPECTED="$OUT/expected.txt"

rm -rf "$OUT"
mkdir -p "$OUT"

jq -r '.sources[] | select(.targets | index("evm")) | .file' "$CATALOG" | sort > "$EXPECTED"

while IFS= read -r file; do
  base="${file%.lean}"
  if [[ ! -f "$CANONICAL_DIR/$file" ]]; then
    echo "missing canonical EVM product source: $CANONICAL_DIR/$file" >&2
    exit 1
  fi
  lake env proof-forge build \
    --target evm \
    --format yul \
    --root . \
    --peer peer.callee=0x000000000000000000000000000000000000ca11 \
    --peer usdc.peer=0x000000000000000000000000000000000000ca12 \
    --peer vault.peer=0x000000000000000000000000000000000000ca13 \
    -o "$OUT/$base.yul" \
    "$CANONICAL_DIR/$file" >/dev/null
  grep -Fq "object \"" "$OUT/$base.yul"
done < "$EXPECTED"

echo "evm-canonical-product-route: ok ($(wc -l < "$EXPECTED" | tr -d ' ') products)"

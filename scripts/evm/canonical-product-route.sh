#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

CATALOG="Examples/Product/catalog.json"
FIXTURE_DIR="TestFixtures/SurfaceProducts"
OUT="${PROOF_FORGE_EVM_CANONICAL_PRODUCT_OUT:-build/evm-canonical-products}"
EXPECTED="$OUT/expected.txt"

rm -rf "$OUT"
mkdir -p "$OUT"

jq -r '.sources[] | select(.targets | index("evm")) | .file' "$CATALOG" | sort > "$EXPECTED"

while IFS= read -r file; do
  base="${file%.lean}"
  if [[ ! -f "$FIXTURE_DIR/$file" ]]; then
    echo "missing internal EVM Surface fixture: $FIXTURE_DIR/$file" >&2
    exit 1
  fi
  if ! lake env proof-forge build \
    --target evm \
    --format yul \
    --root . \
    --peer peer.callee=0x000000000000000000000000000000000000ca11 \
    --peer usdc.peer=0x000000000000000000000000000000000000ca12 \
    --peer vault.peer=0x000000000000000000000000000000000000ca13 \
    -o "$OUT/$base.yul" \
    "$FIXTURE_DIR/$file"
  then
    echo "canonical product route failed for fixture: $FIXTURE_DIR/$file" >&2
    exit 1
  fi
  grep -Fq "object \"" "$OUT/$base.yul"
done < "$EXPECTED"

echo "evm-canonical-product-route: ok ($(wc -l < "$EXPECTED" | tr -d ' ') products)"

#!/usr/bin/env bash
# Wave ε: portable external ERC-4626 vault protocol intent (EVM-first).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

SOURCE="${PORTABLE_PROTOCOL_VAULT_SOURCE:-Examples/Product/ExternalVault.lean}"
OUT="${PORTABLE_PROTOCOL_VAULT_OUT:-build/portable/protocol-vault}"

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

fail() { echo "product-protocol-vault: FAIL: $1" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "missing $1"; }
require_contains() { grep -Fq -- "$2" "$1" || fail "$3 missing '$2' in $1"; }

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
rm -rf "$OUT"
mkdir -p "$OUT/evm" "$OUT/solana" "$OUT/near"

echo "=== product-protocol-vault: build ==="
lake build Examples.Product.ExternalVault >/dev/null || fail "lake build ExternalVault"

echo "=== product-protocol-vault: EVM IERC4626 selectors ==="
if command -v solc >/dev/null 2>&1; then
  "${proof_forge[@]}" build --target evm --root . \
    -o "$OUT/evm/ExternalVault.bin" \
    --yul-output "$OUT/evm/ExternalVault.yul" \
    "$SOURCE" || fail "EVM build failed"
  require_file "$OUT/evm/ExternalVault.yul"
  # deposit 0x6e553f65
  require_contains "$OUT/evm/ExternalVault.yul" "1851080549" "deposit selector"
  # convertToShares 0xc6e6f592
  require_contains "$OUT/evm/ExternalVault.yul" "3337024914" "convertToShares selector"
  # totalAssets 0x01e1d114
  require_contains "$OUT/evm/ExternalVault.yul" "31576340" "totalAssets selector"
  echo "evm vault protocol: ok"
else
  echo "SKIP: solc missing; EVM emit skipped"
fi

echo "=== product-protocol-vault: Solana / NEAR portable smoke ==="
"${proof_forge[@]}" build --target solana-sbpf-asm --format s --root . \
  -o "$OUT/solana/ExternalVault.s" "$SOURCE" || fail "Solana build"
require_file "$OUT/solana/ExternalVault.s"
require_contains "$OUT/solana/ExternalVault.s" "sol_invoke_signed_c" "Solana CPI"

"${proof_forge[@]}" build --target wasm-near --root . \
  -o "$OUT/near/ExternalVault.wat" "$SOURCE" || fail "NEAR build"
NEAR_WAT=""
for cand in "$OUT/near/externalvault.wat" "$OUT/near/ExternalVault.wat" "$OUT/near/"*.wat; do
  [[ -f "$cand" ]] && NEAR_WAT="$cand" && break
done
[[ -n "$NEAR_WAT" ]] || fail "missing NEAR wat"
require_contains "$NEAR_WAT" "deposit" "NEAR pool deposit"
require_contains "$NEAR_WAT" "promise_create" "NEAR promise"

echo "product-protocol-vault: ok"

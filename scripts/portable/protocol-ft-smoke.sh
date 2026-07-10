#!/usr/bin/env bash
# Wave γ: portable protocol-intent external FT multi-target smoke.
#
# Product source uses external_token / externalTokenTransfer — no Protocols.*
# import. Materialize:
#   EVM  → IERC20 transfer selector 0xa9059cbb in Yul
#   NEAR → ft_transfer + NEP-141 JSON object packing
#   Solana → portable CPI (honesty: not live Tokenkeg dataLayout)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

SOURCE="${PORTABLE_PROTOCOL_FT_SOURCE:-Examples/Product/ExternalTokenTransfer.lean}"
OUT="${PORTABLE_PROTOCOL_FT_OUT:-build/portable/protocol-ft}"

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

fail() {
  echo "product-protocol-ft: FAIL: $1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_contains() {
  grep -Fq -- "$2" "$1" || fail "$3 missing '$2' in $1"
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"

rm -rf "$OUT"
mkdir -p "$OUT/evm" "$OUT/solana" "$OUT/near"

echo "=== product-protocol-ft: build Lean product example ==="
(cd "$ROOT" && lake build Examples.Product.ExternalTokenTransfer ProofForge.Target.ProtocolMaterialize >/dev/null) \
  || fail "lake build ExternalTokenTransfer failed"

echo "=== product-protocol-ft: EVM (IERC20 selector packing) ==="
if command -v solc >/dev/null 2>&1; then
  "${proof_forge[@]}" build --target evm --root . \
    -o "$OUT/evm/ExternalTokenTransfer.bin" \
    --yul-output "$OUT/evm/ExternalTokenTransfer.yul" \
    "$SOURCE" \
    || fail "EVM build failed"
  require_file "$OUT/evm/ExternalTokenTransfer.yul"
  # Selector 0xa9059cbb as decimal appears in Yul as literal after resolve.
  # Also accept hex-ish forms and crosscall helper presence.
  if ! grep -Eqi 'a9059cbb|2835717307|crosscall|call\(' "$OUT/evm/ExternalTokenTransfer.yul"; then
    fail "EVM Yul should pack IERC20 transfer / CALL after protocol materialize"
  fi
  # Decimal form of 0xa9059cbb
  require_contains "$OUT/evm/ExternalTokenTransfer.yul" "2835717307" \
    "EVM Yul should contain IERC20 transfer selector (0xa9059cbb = 2835717307)"
  # approve selector 0x095ea7b3 = 157198259
  require_contains "$OUT/evm/ExternalTokenTransfer.yul" "157198259" \
    "EVM Yul should contain IERC20 approve selector (0x095ea7b3)"
  echo "evm protocol ft: ok"
else
  echo "product-protocol-ft: solc missing; EVM emit skipped (Lean + other hosts still run)"
fi

echo "=== product-protocol-ft: Solana portable CPI smoke ==="
"${proof_forge[@]}" build --target solana-sbpf-asm --format s --root . \
  -o "$OUT/solana/ExternalTokenTransfer.s" \
  --artifact-output "$OUT/solana/ExternalTokenTransfer.solana-artifact.json" \
  "$SOURCE" \
  || fail "Solana build failed"
require_file "$OUT/solana/ExternalTokenTransfer.s"
require_contains "$OUT/solana/ExternalTokenTransfer.s" "sol_invoke_signed_c" "Solana CPI invoke"
echo "solana protocol ft (portable CPI smoke): ok"

echo "=== product-protocol-ft: NEAR NEP-141 JSON packing ==="
"${proof_forge[@]}" build --target wasm-near --root . \
  -o "$OUT/near/ExternalTokenTransfer.wat" \
  "$SOURCE" \
  || fail "NEAR build failed"
# CLI lowercases fixture stem for EmitWat primary artifact.
NEAR_WAT=""
for cand in \
  "$OUT/near/externaltokentransfer.wat" \
  "$OUT/near/ExternalTokenTransfer.wat" \
  "$OUT/near/"*.wat
do
  if [[ -f "$cand" ]]; then
    NEAR_WAT="$cand"
    break
  fi
done
[[ -n "$NEAR_WAT" ]] || fail "missing NEAR WAT under $OUT/near"
require_contains "$NEAR_WAT" "ft_transfer" "NEAR method ft_transfer"
require_contains "$NEAR_WAT" "promise_create" "NEAR promise_create"
require_contains "$NEAR_WAT" "ft_balance_of" "NEAR ft_balance_of"
require_contains "$NEAR_WAT" "ft_total_supply" "NEAR ft_total_supply"
require_contains "$NEAR_WAT" "approve" "NEAR pool registers approve method id"
# NEP-141 object JSON is lowered as putc of field name chars (not a data string).
# Object start `{` = 123 and `__pf_crosscall_args_putc` mark object packing.
require_contains "$NEAR_WAT" "__pf_crosscall_args_putc" "NEAR JsonEncode putc packing"
require_contains "$NEAR_WAT" "__pf_crosscall_args_putstr" "NEAR pool string into JSON"
require_contains "$NEAR_WAT" "__pf_crosscall_args_putu64" "NEAR amount JSON string"
# ASCII 'r' (114) begins receiver_id; present in pay's NEP-141 object lower.
if ! grep -Eq 'i32\.const 114' "$NEAR_WAT"; then
  fail "NEAR WAT should emit NEP-141 receiver_id key chars (i32.const 114 = 'r')"
fi
echo "near protocol ft: ok"

echo "product-protocol-ft: ok (EVM selector · Solana CPI smoke · NEAR NEP-141)"

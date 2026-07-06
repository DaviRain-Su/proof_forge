#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_DIR="${PROOF_FORGE_NEAR_FT_TRANSFER_CALL_OUT:-build/wasm-near/FungibleToken}"
WAT="$OUT_DIR/nearfungibletoken.wat"
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "$needle" <<<"$haystack"; then
    echo "ft-transfer-call-smoke: expected ${label} to contain: ${needle}" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_order() {
  local haystack="$1"
  local first="$2"
  local second="$3"
  local first_line
  local second_line
  first_line="$(grep -Fn "$first" <<<"$haystack" | head -n 1 | cut -d: -f1 || true)"
  second_line="$(grep -Fn "$second" <<<"$haystack" | head -n 1 | cut -d: -f1 || true)"
  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    echo "ft-transfer-call-smoke: expected ${first} to appear before ${second}" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

eval "$(python3 - <<'PY'
import hashlib
import struct

sender = hashlib.sha256(b"alice.testnet").digest()
receiver = hashlib.sha256(b"demo.receiver.testnet").digest()
spender = hashlib.sha256(b"spender.testnet").digest()
mint_amount = 100
approve_amount = 13
transfer_amount = 70
receiver_idx = 0
unused_amount = 25

inputs = [
    b"",
    sender + struct.pack("<Q", mint_amount),
    spender + struct.pack("<Q", approve_amount),
    sender,
    receiver,
    receiver + struct.pack("<I", receiver_idx) + struct.pack("<Q", transfer_amount),
    sender,
    receiver,
    b"",
    sender,
    receiver,
]

print(f'SENDER_HASH="{sender.hex()}"')
print(f'RECEIVER_HASH="{receiver.hex()}"')
print(f'UNUSED_AMOUNT="{unused_amount}"')
print(f'INPUTS_HEX="{",".join(item.hex() for item in inputs)}"')
PY
)"

rm -rf "$OUT_DIR"

lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken >/dev/null
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/WasmNear/FungibleToken.lean
test -s "$WAT"

out="$("${HOST[@]}" "$WAT" \
  init \
  ft_mint \
  ft_approve \
  ft_balance_of \
  ft_balance_of \
  ft_transfer_call \
  ft_balance_of \
  ft_balance_of \
  ft_resolve_transfer \
  ft_balance_of \
  ft_balance_of \
  --predecessor-account-id alice.testnet \
  --signer-account-id alice.testnet \
  --current-account-id proof-forge.testnet \
  --promise-result-u64 "$UNUSED_AMOUNT" \
  --inputs-hex "$INPUTS_HEX")"
echo "$out"

assert_contains "$out" "call 1:ft_mint: return=<none>" "mint call"
assert_contains "$out" "call 1:ft_approve: return=<none>" "approve call"
assert_contains "$out" "call 1:ft_balance_of: return_hex=6400000000000000 return_u64=100" "sender balance after mint"
assert_contains "$out" "call 1:ft_balance_of: return_hex=0000000000000000 return_u64=0" "receiver balance before transfer"
assert_contains "$out" "call 1:ft_transfer_call: return=<none>" "promise-returned transfer call"
assert_contains "$out" "promise_create id=0 account=demo.receiver.testnet method=ft_on_transfer args=[\"$SENDER_HASH\",70] deposit=0 gas=50000000000000" "promise_create trace"
assert_contains "$out" "promise_then id=1 parent=0 account=proof-forge.testnet method=ft_resolve_transfer args=[] deposit=0 gas=50000000000000" "promise_then trace"
assert_contains "$out" "promise_return id=1" "promise_return trace"
assert_order "$out" "promise_create id=0" "promise_then id=1 parent=0"
assert_contains "$out" "promise_result index=0 status=1 return_u64=25" "promise result stub"
assert_contains "$out" "call 1:ft_resolve_transfer: return_hex=2d00000000000000 return_u64=45" "resolve used amount"
assert_contains "$out" "call 1:ft_balance_of: return_hex=1e00000000000000 return_u64=30" "sender balance before resolve"
assert_contains "$out" "call 1:ft_balance_of: return_hex=4600000000000000 return_u64=70" "receiver balance before resolve"
assert_contains "$out" "call 1:ft_balance_of: return_hex=3700000000000000 return_u64=55" "sender balance after refund"
assert_contains "$out" "call 1:ft_balance_of: return_hex=2d00000000000000 return_u64=45" "receiver balance after refund"

echo "ft-transfer-call-smoke: ok"

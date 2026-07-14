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

assert_traps() {
  local label="$1"
  shift
  local output
  local status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]] || ! grep -Fq "trapped" <<<"$output"; then
    echo "ft-transfer-call-smoke: expected ${label} to trap" >&2
    echo "$output" >&2
    exit 1
  fi
}

eval "$(python3 - <<'PY'
import struct
import hashlib

def acct_slot(name):
    b = name.encode()
    assert len(b) <= 256
    return struct.pack("<I", len(b)) + b + b"\0" * (256 - len(b))
def balance_json(name):
    return ('{"account_id":"' + name + '"}').encode()
def u128(v):
    return struct.pack("<QQ", v, 0)
def u64(v):
    return struct.pack("<Q", v)
def transfer_call_json(receiver, amount, msg):
    return ('{"receiver_id":"' + receiver + '","amount":"' + str(amount) +
            '","msg":"' + msg + '"}').encode()
def resolve_json(transfer_id, sender, receiver):
    return ('{"transfer_id":' + str(transfer_id) + ',"sender":"' + sender +
            '","receiver":"' + receiver + '"}').encode()

sender = "proof-forge.testnet"
receiver = "demo.receiver.testnet"
# ft_approve keeps a 32-byte hash spender_id (allowances stay hash-keyed).
spender = hashlib.sha256(b"spender.testnet").digest()
mint_amount = 100
approve_amount = 13
transfer_amount = 70
unused_amount = 25

inputs = [
    b"",
    acct_slot(sender) + u128(mint_amount),
    spender + u128(approve_amount),
    balance_json(sender),
    balance_json(receiver),
    acct_slot(receiver),
    transfer_call_json(receiver, transfer_amount, 'refund'),
    balance_json(sender),
    balance_json(receiver),
    resolve_json(0, sender, receiver),
    balance_json(sender),
    balance_json(receiver),
]

print(f'SENDER_ACCT="{sender}"')
print(f'RECEIVER_ACCT="{receiver}"')
print(f'UNUSED_AMOUNT="{unused_amount}"')
print(f'INPUTS_HEX="{",".join(item.hex() for item in inputs)}"')

receiver2 = "second.receiver.testnet"
refund_inputs = [
    b"",
    acct_slot(sender) + u128(mint_amount),
    acct_slot(receiver),
    transfer_call_json(receiver, transfer_amount, 'refund-all'),
    resolve_json(0, sender, receiver),
    balance_json(sender),
    balance_json(receiver),
]
concurrent_inputs = [
    b"",
    acct_slot(sender) + u128(mint_amount),
    acct_slot(receiver),
    acct_slot(receiver2),
    transfer_call_json(receiver, 30, 'first'),
    transfer_call_json(receiver2, 20, 'second'),
    resolve_json(1, sender, receiver2),
    resolve_json(0, sender, receiver),
    balance_json(sender),
    balance_json(receiver),
    balance_json(receiver2),
]
callback_input = resolve_json(0, sender, receiver)
print(f'RECEIVER2_ACCT="{receiver2}"')
print(f'REFUND_INPUTS_HEX="{",".join(item.hex() for item in refund_inputs)}"')
print(f'CONCURRENT_INPUTS_HEX="{",".join(item.hex() for item in concurrent_inputs)}"')
print(f'CALLBACK_INPUT_HEX="{callback_input.hex()}"')
PY
)"

rm -rf "$OUT_DIR"

lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken >/dev/null
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/Backend/WasmNear/FungibleToken.lean
test -s "$WAT"

out="$("${HOST[@]}" "$WAT" \
  init \
  ft_mint \
  ft_approve \
  ft_balance_of \
  ft_balance_of \
  storage_deposit \
  ft_transfer_call \
  ft_balance_of \
  ft_balance_of \
  ft_resolve_transfer \
  ft_balance_of \
  ft_balance_of \
  --predecessor-account-id proof-forge.testnet \
  --signer-account-id proof-forge.testnet \
  --current-account-id proof-forge.testnet \
  --attached-deposit 1 \
  --promise-result-u64 "$UNUSED_AMOUNT" \
  --inputs-hex "$INPUTS_HEX")"
echo "$out"

assert_contains "$out" "call 1:ft_mint: return=<none>" "mint call"
assert_contains "$out" "call 1:ft_approve: return=<none>" "approve call"
assert_contains "$out" "call 1:ft_balance_of: return_hex=2231303022" "sender JSON balance after mint"
assert_contains "$out" "call 1:ft_balance_of: return_hex=223022" "receiver JSON balance before transfer"
assert_contains "$out" "call 1:ft_transfer_call: return=<none>" "promise-returned transfer call"
# deposit is near-sys amount_ptr → offline-host reads the full u128 LE value.
# Both receiver hook and private callback receive standard named JSON objects.
assert_contains "$out" "promise_create id=0 account=demo.receiver.testnet method=ft_on_transfer args={\"sender_id\":\"$SENDER_ACCT\",\"amount\":\"70\",\"msg\":\"refund\"} deposit=0 gas=50000000000000" "promise_create trace"
assert_contains "$out" "promise_then id=1 parent=0 account=proof-forge.testnet method=ft_resolve_transfer args={\"transfer_id\":0,\"sender\":\"$SENDER_ACCT\",\"receiver\":\"$RECEIVER_ACCT\"} deposit=0 gas=50000000000000" "promise_then trace"
assert_contains "$out" "promise_return id=1" "promise_return trace"
assert_order "$out" "promise_create id=0" "promise_then id=1 parent=0"
assert_contains "$out" "promise_result index=0 status=1 return_u64=25" "promise result stub"
assert_contains "$out" "call 1:ft_resolve_transfer: return_hex=22343522" "resolve used amount"
assert_contains "$out" "call 1:ft_balance_of: return_hex=22333022" "sender JSON balance before resolve"
assert_contains "$out" "call 1:ft_balance_of: return_hex=22373022" "receiver JSON balance before resolve"
assert_contains "$out" "call 1:ft_balance_of: return_hex=22353522" "sender JSON balance after refund"
assert_contains "$out" "call 1:ft_balance_of: return_hex=22343522" "receiver JSON balance after refund"

assert_traps "repeat init" "${HOST[@]}" "$WAT" init init \
  --predecessor-account-id proof-forge.testnet \
  --current-account-id proof-forge.testnet \
  --attached-deposit 1 \
  --inputs-hex ","

assert_traps "external resolver call" "${HOST[@]}" "$WAT" ft_resolve_transfer \
  --predecessor-account-id attacker.testnet \
  --current-account-id proof-forge.testnet \
  --attached-deposit 1 \
  --promise-result-u64 5 \
  --inputs-hex "$CALLBACK_INPUT_HEX"

refund_out="$("${HOST[@]}" "$WAT" \
  init ft_mint storage_deposit ft_transfer_call ft_resolve_transfer ft_balance_of ft_balance_of \
  --predecessor-account-id proof-forge.testnet \
  --signer-account-id proof-forge.testnet \
  --current-account-id proof-forge.testnet \
  --attached-deposit 1 \
  --promise-result-u64 1000 \
  --inputs-hex "$REFUND_INPUTS_HEX")"
assert_contains "$refund_out" "call 1:ft_resolve_transfer: return_hex=223022 return_len=3" "refund bounded to original amount"
assert_contains "$refund_out" "call 1:ft_balance_of: return_hex=2231303022" "sender JSON balance after bounded refund"
assert_contains "$refund_out" "call 1:ft_balance_of: return_hex=223022" "receiver JSON balance after bounded refund"

concurrent_out="$("${HOST[@]}" "$WAT" \
  init ft_mint storage_deposit storage_deposit ft_transfer_call ft_transfer_call \
  ft_resolve_transfer ft_resolve_transfer \
  ft_balance_of ft_balance_of ft_balance_of \
  --predecessor-account-id proof-forge.testnet \
  --signer-account-id proof-forge.testnet \
  --current-account-id proof-forge.testnet \
  --attached-deposit 1 \
  --promise-result-u64 5 \
  --inputs-hex "$CONCURRENT_INPUTS_HEX")"
assert_contains "$concurrent_out" "call 1:ft_balance_of: return_hex=22363022" "sender JSON balance after out-of-order callbacks"
assert_contains "$concurrent_out" "call 1:ft_balance_of: return_hex=22323522" "first receiver JSON balance after out-of-order callbacks"
assert_contains "$concurrent_out" "call 1:ft_balance_of: return_hex=22313522" "second receiver JSON balance after out-of-order callbacks"

echo "ft-transfer-call-smoke: ok (happy path, repeat-init, private callback, bounded refund, concurrent contexts)"

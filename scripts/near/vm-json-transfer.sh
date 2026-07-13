#!/usr/bin/env bash
# NEP-141 multi-field JSON transfer conformance on the upstream NEAR VM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_DIR="${PROOF_FORGE_NEAR_VM_JSON_TRANSFER_OUT:-build/wasm-near/FungibleTokenJsonTransfer}"
WAT="$OUT_DIR/nearfungibletoken.wat"
WASM="$OUT_DIR/nearfungibletoken.wasm"
RUNNER=(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml --)

fail() {
  echo "vm-json-transfer: $*" >&2
  exit 1
}

for tool in cargo wat2wasm python3 lake; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool '$tool'"
done

lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken >/dev/null
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/Backend/WasmNear/FungibleToken.lean >/dev/null
test -s "$WAT"
wat2wasm "$WAT" -o "$WASM"
test -s "$WASM"

eval "$(python3 - <<'PY'
import struct

def account_slot(name):
    payload = name.encode()
    return struct.pack("<I", len(payload)) + payload + b"\0" * (256 - len(payload))

def u128(value):
    return struct.pack("<QQ", value & ((1 << 64) - 1), value >> 64)

def balance_json(name):
    return ('{"account_id":"' + name + '"}').encode()

sender = "alice.testnet"
receiver = "bob.testnet"
maximum = (1 << 128) - 1
transfer = ('{"receiver_id":"' + receiver + '","amount":"' + str(maximum) + '"}').encode()
inputs = [b"", account_slot(sender) + u128(maximum), transfer,
          balance_json(sender), balance_json(receiver)]
overflow = ('{"receiver_id":"bob.testnet","amount":"' + str(1 << 128) + '"}').encode()
leading_zero = b'{"receiver_id":"bob.testnet","amount":"01"}'
reordered = b' { "amount" : "1" , "receiver_id" : "bob.testnet" } '
reordered_inputs = [b"", account_slot(sender) + u128(1), reordered,
                    balance_json(sender), balance_json(receiver)]
unknown = b'{"receiver_id":"bob.testnet","amount":"1","extra":"x"}'
duplicate = b'{"receiver_id":"bob.testnet","amount":"1","amount":"1"}'
print(f'INPUTS_HEX="{",".join(value.hex() for value in inputs)}"')
print(f'REORDERED_INPUTS_HEX="{",".join(value.hex() for value in reordered_inputs)}"')
print(f'EXPECTED_MAX_JSON_HEX="{(chr(34) + str(maximum) + chr(34)).encode().hex()}"')
print(f'OVERFLOW_HEX="{overflow.hex()}"')
print(f'LEADING_ZERO_HEX="{leading_zero.hex()}"')
print(f'UNKNOWN_HEX="{unknown.hex()}"')
print(f'DUPLICATE_HEX="{duplicate.hex()}"')
PY
)"

out="$("${RUNNER[@]}" "$WASM" init ft_mint ft_transfer ft_balance_of ft_balance_of \
  --inputs-hex "$INPUTS_HEX" --predecessor-account-id alice.testnet)"
echo "$out"
grep -qF 'call ft_balance_of: return_hex=223022' <<<"$out" \
  || fail 'sender balance was not JSON "0" after U128::MAX transfer'
grep -qF "call ft_balance_of: return_hex=$EXPECTED_MAX_JSON_HEX" <<<"$out" \
  || fail "receiver balance was not JSON U128::MAX"
grep -qF '5 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "valid JSON transfer sequence did not complete"

reordered_out="$("${RUNNER[@]}" "$WASM" init ft_mint ft_transfer ft_balance_of ft_balance_of \
  --inputs-hex "$REORDERED_INPUTS_HEX" --predecessor-account-id alice.testnet)"
echo "$reordered_out"
grep -qF 'call ft_balance_of: return_hex=223022' <<<"$reordered_out" \
  || fail 'sender balance was not JSON "0" after reordered transfer'
grep -qF 'call ft_balance_of: return_hex=223122' <<<"$reordered_out" \
  || fail 'receiver balance was not JSON "1" after reordered transfer'
grep -qF '5 methods executed successfully on real NEAR VM' <<<"$reordered_out" \
  || fail "whitespace/reordered JSON transfer sequence did not complete"

assert_rejected() {
  local label="$1"
  local input_hex="$2"
  local rejected_out
  local rejected_status
  set +e
  rejected_out="$("${RUNNER[@]}" "$WASM" ft_transfer --input-hex "$input_hex" \
    --predecessor-account-id alice.testnet 2>&1)"
  rejected_status=$?
  set -e
  echo "$rejected_out"
  [[ $rejected_status -ne 0 ]] || fail "$label unexpectedly succeeded"
  grep -qF 'call ft_transfer: ABORTED:' <<<"$rejected_out" \
    || fail "$label did not abort inside the real NEAR VM"
}

assert_rejected "U128 overflow JSON amount" "$OVERFLOW_HEX"
assert_rejected "non-canonical leading-zero JSON amount" "$LEADING_ZERO_HEX"
assert_rejected "unknown JSON field" "$UNKNOWN_HEX"
assert_rejected "duplicate JSON field" "$DUPLICATE_HEX"

echo "vm-json-transfer: ok (schema field order/whitespace + U128::MAX + unknown/duplicate rejection)"

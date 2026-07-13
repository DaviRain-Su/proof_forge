#!/usr/bin/env bash
# NEP-141 JSON ABI conformance on the unmodified upstream NEAR VM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_DIR="${PROOF_FORGE_NEAR_VM_JSON_OUT:-build/wasm-near/FungibleTokenJson}"
WAT="$OUT_DIR/nearfungibletoken.wat"
WASM="$OUT_DIR/nearfungibletoken.wasm"
RUNNER=(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml --)

fail() {
  echo "vm-json-balance: $*" >&2
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

INPUTS_HEX="$(python3 - <<'PY'
import struct

def account_slot(name):
    payload = name.encode()
    return struct.pack("<I", len(payload)) + payload + b"\0" * (256 - len(payload))

def u128(value):
    return struct.pack("<QQ", value, 0)

account = "alice.testnet"
json_query = (' \n{ "account_id" : "' + account + '" }\t').encode()
escaped_query = b'{"account_id":"alice\\u002etestnet"}'
print(",".join(value.hex() for value in [
    b"", account_slot(account) + u128(100), b" \n{ }\t", json_query, escaped_query
]))
PY
)"

out="$("${RUNNER[@]}" "$WASM" init ft_mint ft_total_supply ft_balance_of ft_balance_of --inputs-hex "$INPUTS_HEX")"
echo "$out"
grep -qF 'call ft_total_supply: return_hex=2231303022' <<<"$out" \
  || fail 'ft_total_supply did not return the JSON U128 string "100"'
[[ "$(grep -cF 'call ft_balance_of: return_hex=2231303022' <<<"$out")" -eq 2 ]] \
  || fail 'raw and Unicode-escaped ft_balance_of did not both return JSON "100"'
grep -qF '5 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "valid JSON balance sequence did not complete"

set +e
malformed_out="$("${RUNNER[@]}" "$WASM" ft_balance_of --input-hex 00 2>&1)"
malformed_status=$?
set -e
echo "$malformed_out"
[[ $malformed_status -ne 0 ]] || fail "malformed JSON input unexpectedly succeeded"
grep -qF 'call ft_balance_of: ABORTED:' <<<"$malformed_out" \
  || fail "malformed JSON input did not abort inside the real NEAR VM"

echo "vm-json-balance: ok (schema whitespace + Unicode escape + JSON supply/balance + malformed rejection)"

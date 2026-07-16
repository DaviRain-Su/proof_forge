#!/usr/bin/env bash
# Full NEP-145 storage-management conformance on the upstream NEAR VM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_DIR="${PROOF_FORGE_NEAR_VM_NEP145_OUT:-build/wasm-near/NearFungibleTokenNep145}"
WASM="$OUT_DIR/nearfungibletoken.wasm"
RUNNER=(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml --)
MIN=3900000000000000000000
ALICE_REQUIRED=3900000000000000000000
ALICE_UNDERFUNDED=3899999999999999999999
ALICE_REFUND=3900000000000000000001

fail() { echo "vm-nep145: $*" >&2; exit 1; }
for tool in cargo wat2wasm python3 lake; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool '$tool'"
done

lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken >/dev/null
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/Backend/WasmNear/FungibleToken.lean >/dev/null
test -s "$WASM"

eval "$(python3 - <<'PY'
import struct

def seq(values):
    return ','.join(value.hex() for value in values)

def slot(name):
    raw = name.encode()
    return struct.pack('<I', len(raw)) + raw + b'\0' * (256 - len(raw))

def u128(value):
    return struct.pack('<QQ', value & ((1 << 64) - 1), value >> 64)

alice = 'alice.testnet'
positive = [b'', b'{}', b'{"account_id":"alice.testnet"}',
            b'{"account_id":"alice.testnet"}', b'{"account_id":"alice.testnet"}',
            b'{}', b'{}', b'{"force":false}', b'{"account_id":"alice.testnet"}']
setup = [b'', b'{}', b'{}']
force = [b'', b'{}', slot(alice) + u128(5), b'{"force":true}', b'{}',
         b'{"account_id":"alice.testnet"}']
deny_force = [b'', b'{}', slot(alice) + u128(5), b'{"force":false}']
print(f'POSITIVE_INPUTS="{seq(positive)}"')
print(f'SETUP_INPUTS="{seq(setup)}"')
print(f'FORCE_INPUTS="{seq(force)}"')
print(f'DENY_FORCE_INPUTS="{seq(deny_force)}"')
bounds_hex = b'{"min":"3900000000000000000000","max":null}'.hex()
balance_hex = b'{"total":"3900000000000000000000","available":"0"}'.hex()
print(f'BOUNDS_HEX="{bounds_hex}"')
print(f'BALANCE_HEX="{balance_hex}"')
PY
)"

echo "=== NEP-145 positive lifecycle + refunds + byte accounting ==="
out="$("${RUNNER[@]}" "$WASM" init storage_balance_bounds storage_balance_of \
  storage_deposit storage_balance_of storage_deposit storage_withdraw \
  storage_unregister storage_balance_of --inputs-hex "$POSITIVE_INPUTS" \
  --predecessor-account-id alice.testnet \
  --attached-deposits-yocto "0,0,0,$ALICE_REQUIRED,0,7,1,1,0")"
echo "$out"
grep -qF "call storage_balance_bounds: return_hex=$BOUNDS_HEX" <<<"$out" \
  || fail "storage_balance_bounds did not return the standard min/max object"
[[ "$(grep -cF 'call storage_balance_of: return_hex=6e756c6c' <<<"$out")" -eq 2 ]] \
  || fail "unregistered balances must be JSON null before registration and after unregister"
grep -qF "call storage_deposit: return_hex=$BALANCE_HEX" <<<"$out" \
  || fail "storage_deposit did not return the measured maximum registration cost"
grep -qF 'call storage_deposit: action=Transfer { receipt_index: 0, deposit: NearToken { inner: 7 } }' <<<"$out" \
  || fail "repeat storage_deposit did not refund the full attached deposit"
grep -qF 'call storage_unregister: return_hex=74727565' <<<"$out" \
  || fail "storage_unregister did not return JSON true"
grep -qF "deposit: NearToken { inner: $ALICE_REFUND }" <<<"$out" \
  || fail "storage_unregister did not refund locked balance plus one yoctoNEAR"
grep -qF 'call storage_deposit: storage_usage=762' <<<"$out" \
  || fail "registration did not add the measured 237 storage bytes"
grep -qF 'call storage_unregister: storage_usage=525' <<<"$out" \
  || fail "unregister did not restore the pre-registration storage usage"

expect_abort() {
  local label="$1" deposits="$2" inputs="$3"; shift 3
  local output status
  set +e
  output="$("${RUNNER[@]}" "$WASM" "$@" --inputs-hex "$inputs" \
    --predecessor-account-id alice.testnet --attached-deposits-yocto "$deposits" 2>&1)"
  status=$?
  set -e
  echo "$output"
  [[ $status -ne 0 ]] || fail "$label unexpectedly succeeded"
  grep -qF 'ABORTED:' <<<"$output" || fail "$label did not abort inside the NEAR VM"
}

echo "=== NEP-145 attack paths ==="
expect_abort "underfunded registration" "0,$ALICE_UNDERFUNDED" \
  "${POSITIVE_INPUTS%%,*},7b7d" init storage_deposit
for deposit in 0 2; do
  expect_abort "storage_withdraw with $deposit yoctoNEAR" "0,$ALICE_REQUIRED,$deposit" \
    "$SETUP_INPUTS" init storage_deposit storage_withdraw
done
expect_abort "unregister without force and positive token balance" \
  "0,$ALICE_REQUIRED,0,1" "$DENY_FORCE_INPUTS" \
  init storage_deposit ft_mint storage_unregister

echo "=== NEP-145 forced unregister burns balance and refunds storage ==="
force_out="$("${RUNNER[@]}" "$WASM" init storage_deposit ft_mint storage_unregister \
  ft_total_supply storage_balance_of --inputs-hex "$FORCE_INPUTS" \
  --predecessor-account-id alice.testnet \
  --attached-deposits-yocto "0,$ALICE_REQUIRED,0,1,0,0")"
echo "$force_out"
grep -qF 'call storage_unregister: return_hex=74727565' <<<"$force_out" \
  || fail "forced unregister did not return true"
grep -qF 'call ft_total_supply: return_hex=223022' <<<"$force_out" \
  || fail "forced unregister did not burn the account token balance"
grep -qF 'call storage_balance_of: return_hex=6e756c6c' <<<"$force_out" \
  || fail "forced unregister did not remove registration"
grep -qF "deposit: NearToken { inner: $ALICE_REFUND }" <<<"$force_out" \
  || fail "forced unregister refund amount is wrong"

echo "vm-nep145: ok"

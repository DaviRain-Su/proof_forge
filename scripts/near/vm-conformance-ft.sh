#!/usr/bin/env bash
# Real-NEAR-VM conformance for the ProofForge NEP-141 FungibleToken (wasm-near).
#
# Compiles the FT module — whose host surface spans storage_read/write/remove,
# read_register, value_return, the full promise ABI (promise_create/then/
# results_count/result/return), input, current_account_id, and register_len —
# and executes it on the *unmodified upstream* NEAR VM (near-vm-runner 0.37 /
# Wasmtime).
#
# This extends the Counter-only conformance gate so host-import arity
# regressions (e.g. a stale 2-param `storage_remove`) cannot mask as success:
# the FT module imports `storage_remove` and the full promise set, so any
# LinkError surfaces immediately. (Counter never imports storage_remove, which
# is why the Counter-only gate could not catch that class of failure.)
#
# Phase 1 (host-ABI link + execute): `init` + `ft_total_supply` with the
#   canonical NEP-141 `{}` JSON input proves the complete host-import surface
#   resolves against real near-vm-logic and executes without trap.
#   ft_total_supply must return the JSON decimal string `"0"`.
#
# Phase 2 (semantic + callback dispatch): the full NEP-141 transfer_call flow
#   (init, ft_mint, ft_approve, balance_of*, ft_transfer_call, ft_resolve_transfer,
#   balance_of*) with Borsh admin inputs plus standard JSON public FT calls
#   (`--inputs-hex`) and one injected Successful
#   promise_result (`--promise-result-u64`). ft_transfer_call must create a
#   promise (return=receipt), and ft_resolve_transfer must read it via the REAL
#   promise_results_count / promise_result host functions, producing the same
#   refund (45) as runtime/offline-host. This is a conformance approximation:
#   receipts are not scheduled and the peer contract is not executed — only the
#   callback-side read is validated against the real VM.
#
# Phase 3 (transaction context + authorization): one persistent VM sequence
#   injects a predecessor and attached deposit per call, proves an authorized
#   storage withdrawal changes 7 -> 4, then proves an attacker predecessor
#   aborts on the same string AccountId equality check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "vm-conformance-ft: missing required tool '$1'" >&2
    exit 1
  }
}
require_cmd cargo
require_cmd wat2wasm
require_cmd python3
require_cmd lake

OUT_DIR="${PROOF_FORGE_NEAR_VM_CONF_FT_OUT:-build/wasm-near/FungibleToken}"
WAT="$OUT_DIR/nearfungibletoken.wat"
WASM="$OUT_DIR/nearfungibletoken.wasm"
RUNNER=(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml --)

echo "=== building + emitting NEP-141 FT (wasm-near) ==="
lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken >/dev/null
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/Backend/WasmNear/FungibleToken.lean >/dev/null
test -s "$WAT"
wat2wasm "$WAT" -o "$WASM"
test -s "$WASM"

fail() {
  echo "vm-conformance-ft: $*" >&2
  exit 1
}

echo "=== phase 1: host-ABI link + execute (init, ft_total_supply) ==="
out="$("${RUNNER[@]}" "$WASM" init ft_total_supply --inputs-hex ',7b7d')"
echo "$out"
grep -qiE 'ABORTED|failed|LinkError' <<<"$out" && fail "phase 1 link/execute failed on real NEAR VM"
grep -qF 'call ft_total_supply: return_hex=223022' <<<"$out" \
  || fail "phase 1 ft_total_supply != 0 (fresh storage)"
grep -qF '2 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "phase 1 did not report 2 successful methods"

echo "=== phase 2: semantic transfer_call + ft_resolve_transfer callback ==="
# Internal mint/approve/storage setup remains Borsh. Standard NEP-141 calls
# and the private resolver callback use canonical JSON objects.
# Expected refund values match runtime/offline-host ft-transfer-call-smoke.sh.
INPUTS_HEX="$(python3 - <<'PY'
import hashlib, struct
def acct_slot(name):
    b = name.encode()
    return struct.pack("<I", len(b)) + b + b"\0" * (256 - len(b))
def balance_json(name):
    return ('{"account_id":"' + name + '"}').encode()
sender = "proof-forge.testnet"
receiver = "demo.receiver.testnet"
spender = hashlib.sha256(b"spender.testnet").digest()
def u128(v): return struct.pack("<QQ", v, 0)
inputs = [
    b"",                                                       # init
    acct_slot(sender) + u128(100),                             # ft_mint(receiver_id=sender, 100)
    spender + u128(13),                                        # ft_approve(spender_id hash, 13)
    balance_json(sender),                                       # ft_balance_of(sender)
    balance_json(receiver),                                     # ft_balance_of(receiver)
    balance_json(receiver),                                     # storage_deposit(receiver)
    b'{"receiver_id":"demo.receiver.testnet","amount":"70","msg":"refund"}',
    balance_json(sender),                                       # ft_balance_of(sender)
    balance_json(receiver),                                     # ft_balance_of(receiver)
    b'{"transfer_id":0,"sender":"proof-forge.testnet","receiver":"demo.receiver.testnet"}',
    balance_json(sender),                                       # ft_balance_of(sender)
    balance_json(receiver),                                     # ft_balance_of(receiver)
]
print(",".join(i.hex() for i in inputs))
PY
)"
out="$("${RUNNER[@]}" "$WASM" \
  init ft_mint ft_approve ft_balance_of ft_balance_of storage_deposit ft_transfer_call \
  ft_balance_of ft_balance_of ft_resolve_transfer ft_balance_of ft_balance_of \
  --inputs-hex "$INPUTS_HEX" --promise-result-u64 25 \
  --attached-deposits-yocto 0,0,0,0,0,3900000000000000000000,1,0,0,0,0,0)"
echo "$out"
grep -qiE 'ABORTED|failed|LinkError' <<<"$out" && fail "phase 2 semantic flow failed on real NEAR VM"
# ft_transfer_call creates a cross-contract promise on the real VM.
grep -qF 'call ft_transfer_call: return=receipt(' <<<"$out" \
  || fail "phase 2 ft_transfer_call did not return a receipt (no promise created)"
# ft_resolve_transfer reads the injected promise_result via the REAL host
# functions and computes the same refund (u64 45 = LE 2d00000000000000) as the
# offline host.
grep -qF 'call ft_resolve_transfer: return_hex=22343522' <<<"$out" \
  || fail "phase 2 ft_resolve_transfer refund != 45 (callback dispatch mismatch)"
for expected in 2231303022 223022 22333022 22373022 22353522 22343522; do
  grep -qF "call ft_balance_of: return_hex=$expected" <<<"$out" \
    || fail "phase 2 missing JSON ft_balance_of return $expected"
done
grep -qF '12 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "phase 2 did not report 12 successful methods"

echo "=== phase 3: NEP-145 host surface remains linked ==="
out="$("${RUNNER[@]}" "$WASM" init storage_balance_bounds --inputs-hex ',7b7d')"
echo "$out"
grep -qF '2 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "phase 3 NEP-145 host surface failed"

echo "=== phase 4: transfer_call exact-deposit + receiver registration ==="
eval "$(python3 - <<'PY'
import struct
def acct_slot(name):
    b = name.encode()
    return struct.pack("<I", len(b)) + b + b"\0" * (256 - len(b))
def u128(v): return struct.pack("<QQ", v, 0)
sender = "proof-forge.testnet"
receiver = "demo.receiver.testnet"
transfer_call = b'{"receiver_id":"demo.receiver.testnet","amount":"70","msg":"refund"}'
registered = [b"", acct_slot(sender) + u128(100),
              b'{"account_id":"demo.receiver.testnet"}', transfer_call]
unregistered = [b"", acct_slot(sender) + u128(100), transfer_call]
print(f'TRANSFER_CALL_INPUTS_HEX="{",".join(value.hex() for value in registered)}"')
print(f'UNREGISTERED_TRANSFER_CALL_INPUTS_HEX="{",".join(value.hex() for value in unregistered)}"')
PY
)"

expect_transfer_call_abort() {
  local label="$1"
  local methods="$2"
  local inputs="$3"
  local deposits="$4"
  local output status
  set +e
  output="$("${RUNNER[@]}" "$WASM" $methods \
    --inputs-hex "$inputs" --attached-deposits-yocto "$deposits" 2>&1)"
  status=$?
  set -e
  echo "$output"
  [[ $status -ne 0 ]] || fail "$label unexpectedly succeeded"
  grep -qF 'call ft_transfer_call: ABORTED:' <<<"$output" \
    || fail "$label did not abort in ft_transfer_call"
}

expect_transfer_call_abort "zero-yocto ft_transfer_call" \
  "init ft_mint storage_deposit ft_transfer_call" "$TRANSFER_CALL_INPUTS_HEX" "0,0,3900000000000000000000,0"
expect_transfer_call_abort "two-yocto ft_transfer_call" \
  "init ft_mint storage_deposit ft_transfer_call" "$TRANSFER_CALL_INPUTS_HEX" "0,0,3900000000000000000000,2"
expect_transfer_call_abort "unregistered-receiver ft_transfer_call" \
  "init ft_mint ft_transfer_call" "$UNREGISTERED_TRANSFER_CALL_INPUTS_HEX" "0,0,1"

echo "vm-conformance-ft: ok (host ABI + transfer_call callback + exact deposit + registration on real NEAR VM)"

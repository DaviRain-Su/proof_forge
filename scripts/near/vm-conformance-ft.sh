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
# Phase 1 (host-ABI link + execute): `init` + `ft_total_supply` with no input —
#   proves the complete host-import surface resolves against real
#   near-vm-logic and executes without trap. ft_total_supply must read 0.
#
# Phase 2 (semantic + callback dispatch): the full NEP-141 transfer_call flow
#   (init, ft_mint, ft_approve, balance_of*, ft_transfer_call, ft_resolve_transfer,
#   balance_of*) with Borsh inputs (`--inputs-hex`) and one injected Successful
#   promise_result (`--promise-result-u64`). ft_transfer_call must create a
#   promise (return=receipt), and ft_resolve_transfer must read it via the REAL
#   promise_results_count / promise_result host functions, producing the same
#   refund (45) as runtime/offline-host. This is a conformance approximation:
#   receipts are not scheduled and the peer contract is not executed — only the
#   callback-side read is validated against the real VM.
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
out="$("${RUNNER[@]}" "$WASM" init ft_total_supply)"
echo "$out"
grep -qiE 'ABORTED|failed|LinkError' <<<"$out" && fail "phase 1 link/execute failed on real NEAR VM"
grep -qF 'call ft_total_supply: return_hex=0000000000000000' <<<"$out" \
  || fail "phase 1 ft_total_supply != 0 (fresh storage)"
grep -qF '2 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "phase 1 did not report 2 successful methods"

echo "=== phase 2: semantic transfer_call + ft_resolve_transfer callback ==="
# Borsh inputs mirror runtime/offline-host ft-transfer-call-smoke.sh exactly,
# so the expected refund values are directly comparable.
INPUTS_HEX="$(python3 - <<'PY'
import hashlib, struct
sender = hashlib.sha256(b"proof-forge.testnet").digest()
receiver = hashlib.sha256(b"demo.receiver.testnet").digest()
spender = hashlib.sha256(b"spender.testnet").digest()
inputs = [
    b"",
    sender + struct.pack("<Q", 100),
    spender + struct.pack("<Q", 13),
    sender,
    receiver,
    receiver + struct.pack("<I", 0) + struct.pack("<Q", 70),
    sender,
    receiver,
    struct.pack("<Q", 0) + sender + receiver,
    sender,
    receiver,
]
print(",".join(i.hex() for i in inputs))
PY
)"
out="$("${RUNNER[@]}" "$WASM" \
  init ft_mint ft_approve ft_balance_of ft_balance_of ft_transfer_call \
  ft_balance_of ft_balance_of ft_resolve_transfer ft_balance_of ft_balance_of \
  --inputs-hex "$INPUTS_HEX" --promise-result-u64 25)"
echo "$out"
grep -qiE 'ABORTED|failed|LinkError' <<<"$out" && fail "phase 2 semantic flow failed on real NEAR VM"
# ft_transfer_call creates a cross-contract promise on the real VM.
grep -qF 'call ft_transfer_call: return=receipt(' <<<"$out" \
  || fail "phase 2 ft_transfer_call did not return a receipt (no promise created)"
# ft_resolve_transfer reads the injected promise_result via the REAL host
# functions and computes the same refund (u64 45 = LE 2d00000000000000) as the
# offline host.
grep -qF 'call ft_resolve_transfer: return_hex=2d00000000000000' <<<"$out" \
  || fail "phase 2 ft_resolve_transfer refund != 45 (callback dispatch mismatch)"
grep -qF '11 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "phase 2 did not report 11 successful methods"

echo "vm-conformance-ft: ok (host-ABI link + NEP-141 transfer_call + callback on real NEAR VM)"

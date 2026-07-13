#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
export PATH="$HOME/.foundry/bin:$PATH"

lake env lean --run Tests/Stylus/RemoteCallDifferential.lean
lake env lean --run Tests/Stylus/RemoteCallDirect.lean
lake env lean --run Tests/Stylus/ReentrantDirect.lean
wat2wasm build/stylus/remote-call/call.wat -o build/stylus/remote-call/call.wasm
wat2wasm build/stylus/reentrant/reentrant.wat -o build/stylus/reentrant/reentrant.wasm
target="$(printf '22%.0s' {1..20})"
target_word="$(printf '00%.0s' {1..12})${target}"
selector="$(cast sig 'ping()' | sed 's/^0x//')"
success_word="$(printf '%064x' 42)"

success="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$success_word" \
  --calldata ca110001${target_word} --invoke user_entrypoint)"
revert="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=1:deadbeef" \
  --calldata ca110001${target_word} --invoke user_entrypoint)"
static="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$success_word" \
  --calldata ca110002${target_word} --invoke user_entrypoint)"
delegate="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$success_word" \
  --calldata ca110003${target_word} --invoke user_entrypoint)"
args_selector="$(cast sig 'ping(uint64,uint64)' | sed 's/^0x//')"
args="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$success_word" \
  --calldata ca110004${target_word}$(printf '%064x' 42)$(printf '%064x' 7) --invoke user_entrypoint)"
wide_value="0000000000000001000000000000002a"
value_call="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$success_word" \
  --calldata ca110005${target_word}$(printf '00%.0s' {1..16})${wide_value} --invoke user_entrypoint)"
gas_call="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$success_word" \
  --calldata ca110006${target_word}$(printf '%064x' 12345) --invoke user_entrypoint)"
empty_return="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:" \
  --calldata ca110001${target_word} --invoke user_entrypoint)"
oversized_return="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$(printf 'aa%.0s' {1..4097})" \
  --calldata ca110001${target_word} --invoke user_entrypoint)"
abi_offset="$(printf '%064x' 32)"
abi_empty="${abi_offset}$(printf '%064x' 0)"
abi_hello="${abi_offset}$(printf '%064x' 5)68656c6c6f$(printf '00%.0s' {1..27})"
abi_bad_offset="$(printf '%064x' 64)$(printf '%064x' 0)"
abi_bad_padding="${abi_offset}$(printf '%064x' 5)68656c6c6f"
abi_nonzero_padding="${abi_offset}$(printf '%064x' 5)68656c6c6f$(printf '00%.0s' {1..26})ff"
abi_too_long="${abi_offset}$(printf '%064x' 65)$(printf 'aa%.0s' {1..65})$(printf '00%.0s' {1..31})"
bytes_empty="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$abi_empty" \
  --calldata ca110007${target_word} --invoke user_entrypoint)"
bytes_hello="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$abi_hello" \
  --calldata ca110007${target_word} --invoke user_entrypoint)"
bytes_bad_offset="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$abi_bad_offset" \
  --calldata ca110007${target_word} --invoke user_entrypoint)"
bytes_bad_padding="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$abi_bad_padding" \
  --calldata ca110007${target_word} --invoke user_entrypoint)"
bytes_nonzero_padding="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$abi_nonzero_padding" \
  --calldata ca110007${target_word} --invoke user_entrypoint)"
bytes_too_long="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/remote-call/call.wasm --mock-call "$target=0:$abi_too_long" \
  --calldata ca110007${target_word} --invoke user_entrypoint)"
reentrant_success="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/reentrant/reentrant.wasm --mock-reentrant "$target=ca120002" \
  --calldata ca120001${target_word} --invoke user_entrypoint)"
reentrant_revert="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/reentrant/reentrant.wasm --mock-reentrant "$target=ca120003" \
  --calldata ca120001${target_word} --invoke user_entrypoint)"
outer_revert="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/reentrant/reentrant.wasm --mock-reentrant "$target=ca120002" \
  --calldata ca120004${target_word} --invoke user_entrypoint)"

python3 - "$selector" "$args_selector" "$target" "$abi_empty" "$abi_hello" "$success" "$revert" "$static" "$delegate" "$args" "$value_call" "$gas_call" "$empty_return" "$oversized_return" "$bytes_empty" "$bytes_hello" "$bytes_bad_offset" "$bytes_bad_padding" "$bytes_nonzero_padding" "$bytes_too_long" "$reentrant_success" "$reentrant_revert" "$outer_revert" <<'PY'
import json
import sys

selector, args_selector, target, abi_empty, abi_hello = sys.argv[1:6]
success, revert, static, delegate, args, value_call, gas_call, empty_return, oversized_return, bytes_empty, bytes_hello, bytes_bad_offset, bytes_bad_padding, bytes_nonzero_padding, bytes_too_long, reentrant_success, reentrant_revert, outer_revert = map(json.loads, sys.argv[6:24])
def require_pre_call_cache(trace, event, clear):
    index = next(i for i, item in enumerate(trace) if item["event"] == event)
    assert index > 0
    assert trace[index - 1]["event"] == "storage_flush"
    assert trace[index - 1]["clear"] is clear

assert success["calls"][0]["status"] == 0
assert success["result"] == "00" * 31 + "2a"
calls = [item for item in success["trace"] if item["event"] == "call_contract"]
assert len(calls) == 1 and calls[0]["address"] == target and calls[0]["calldata"] == selector
require_pre_call_cache(success["trace"], "call_contract", True)
assert revert["calls"][0]["status"] == 1 and revert["result"] == "deadbeef"
assert any(item["event"] == "read_return_data" for item in revert["trace"])
assert static["calls"][0]["status"] == 0
assert any(item["event"] == "static_call_contract" for item in static["trace"])
require_pre_call_cache(static["trace"], "static_call_contract", False)
assert delegate["calls"][0]["status"] == 0
assert any(item["event"] == "delegate_call_contract" for item in delegate["trace"])
require_pre_call_cache(delegate["trace"], "delegate_call_contract", True)
arg_calls = [item for item in args["trace"] if item["event"] == "call_contract"]
assert len(arg_calls) == 1
assert arg_calls[0]["calldata"] == args_selector + "00" * 31 + "2a" + "00" * 31 + "07"
pay_calls = [item for item in value_call["trace"] if item["event"] == "call_contract"]
assert len(pay_calls) == 1
assert pay_calls[0]["value"] == "00" * 16 + "0000000000000001000000000000002a"
gas_calls = [item for item in gas_call["trace"] if item["event"] == "call_contract"]
assert len(gas_calls) == 1 and gas_calls[0]["gas"] == 12345
assert empty_return["calls"][0]["status"] == 1
assert empty_return["result"] == "stylus: malformed return data".encode().hex()
assert oversized_return["calls"][0]["status"] == 1
assert oversized_return["result"] == "stylus: return data exceeds limit".encode().hex()
assert bytes_empty["calls"][0]["status"] == 0 and bytes_empty["result"] == abi_empty
assert bytes_hello["calls"][0]["status"] == 0 and bytes_hello["result"] == abi_hello
assert bytes_bad_offset["calls"][0]["status"] == 1
assert bytes_bad_offset["result"] == "stylus: malformed dynamic return data".encode().hex()
assert bytes_bad_padding["calls"][0]["status"] == 1
assert bytes_bad_padding["result"] == "stylus: malformed dynamic return data".encode().hex()
assert bytes_nonzero_padding["calls"][0]["status"] == 1
assert bytes_nonzero_padding["result"] == "stylus: malformed dynamic return data".encode().hex()
assert bytes_too_long["calls"][0]["status"] == 1
assert bytes_too_long["result"] == "stylus: return data exceeds limit".encode().hex()
slot_zero = "00" * 32
word_42 = "00" * 31 + "2a"
assert reentrant_success["calls"][0]["status"] == 0
assert reentrant_success["result"] == word_42
assert reentrant_success["storage"][slot_zero] == word_42
enters = [item for item in reentrant_success["trace"] if item["event"] == "frame_enter"]
exits = [item for item in reentrant_success["trace"] if item["event"] == "frame_exit"]
assert len(enters) == len(exits) == 1
assert enters[0]["sender"] == target and enters[0]["value"] == "00" * 32
assert enters[0]["calldata"] == "ca120002"
assert exits[0]["restoredSender"] == "00" * 20
assert exits[0]["restoredValue"] == "00" * 32
assert exits[0]["restoredCalldata"] == "ca120001" + "00" * 12 + target
assert reentrant_revert["calls"][0]["status"] == 1
assert reentrant_revert["result"] == "callback reverted".encode().hex()
assert slot_zero not in reentrant_revert["storage"]
assert any(item["event"] == "frame_exit" and item["status"] == 1 for item in reentrant_revert["trace"])
assert outer_revert["calls"][0]["status"] == 1
assert outer_revert["result"] == "outer reverted".encode().hex()
assert slot_zero not in outer_revert["storage"]
print("stylus-remote-call-differential-runtime: ok")
PY

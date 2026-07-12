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
reentrant_success="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/reentrant/reentrant.wasm --mock-reentrant "$target=ca120002" \
  --calldata ca120001${target_word} --invoke user_entrypoint)"
reentrant_revert="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/reentrant/reentrant.wasm --mock-reentrant "$target=ca120003" \
  --calldata ca120001${target_word} --invoke user_entrypoint)"
outer_revert="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/reentrant/reentrant.wasm --mock-reentrant "$target=ca120002" \
  --calldata ca120004${target_word} --invoke user_entrypoint)"

python3 - "$selector" "$args_selector" "$target" "$success" "$revert" "$static" "$delegate" "$args" "$value_call" "$reentrant_success" "$reentrant_revert" "$outer_revert" <<'PY'
import json
import sys

selector, args_selector, target = sys.argv[1:4]
success, revert, static, delegate, args, value_call, reentrant_success, reentrant_revert, outer_revert = map(json.loads, sys.argv[4:13])
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

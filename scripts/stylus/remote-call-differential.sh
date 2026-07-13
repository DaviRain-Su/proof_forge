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
caller="$(printf '33%.0s' {1..20})"
sender="$(printf '44%.0s' {1..20})"
delegate_value="$(printf '00%.0s' {1..31})2a"
static_write="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/reentrant/reentrant.wasm --contract "$caller" --sender "$sender" \
  --mock-static "$target=ca120002" --calldata ca120005${target_word} --invoke user_entrypoint)"
delegate_context="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/reentrant/reentrant.wasm --contract "$caller" --sender "$sender" \
  --value "$delegate_value" --mock-delegate "$target=ca120007" \
  --calldata ca120006${target_word} --invoke user_entrypoint)"

python3 - "$selector" "$args_selector" "$target" "$abi_empty" "$abi_hello" "$caller" "$sender" "$delegate_value" "$success" "$revert" "$static" "$delegate" "$args" "$value_call" "$gas_call" "$empty_return" "$oversized_return" "$bytes_empty" "$bytes_hello" "$bytes_bad_offset" "$bytes_bad_padding" "$bytes_nonzero_padding" "$bytes_too_long" "$reentrant_success" "$reentrant_revert" "$outer_revert" "$static_write" "$delegate_context" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

selector, args_selector, target, abi_empty, abi_hello, caller, sender, delegate_value = sys.argv[1:9]
success, revert, static, delegate, args, value_call, gas_call, empty_return, oversized_return, bytes_empty, bytes_hello, bytes_bad_offset, bytes_bad_padding, bytes_nonzero_padding, bytes_too_long, reentrant_success, reentrant_revert, outer_revert, static_write, delegate_context = map(json.loads, sys.argv[9:29])
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
assert static_write["calls"][0]["status"] == 1
assert slot_zero not in static_write["storage"]
assert any(item["event"] == "static_write_rejected" for item in static_write["trace"])
static_frames = [item for item in static_write["trace"] if item["event"] == "frame_enter"]
assert len(static_frames) == 1 and static_frames[0]["mode"] == "static"
assert static_frames[0]["sender"] == caller and static_frames[0]["contract"] == target
assert static_frames[0]["value"] == "00" * 32
assert delegate_context["calls"][0]["status"] == 0
assert delegate_context["result"] == word_42
slot_one, slot_two, slot_three = "00" * 31 + "01", "00" * 31 + "02", "00" * 31 + "03"
assert delegate_context["storage"][slot_one] == "00" * 12 + sender
assert delegate_context["storage"][slot_two] == "00" * 16 + delegate_value[32:]
assert delegate_context["storage"][slot_three] == "00" * 12 + caller
delegate_frames = [item for item in delegate_context["trace"] if item["event"] == "frame_enter"]
assert len(delegate_frames) == 1 and delegate_frames[0]["mode"] == "delegate"
assert delegate_frames[0]["sender"] == sender
assert delegate_frames[0]["value"] == delegate_value
assert delegate_frames[0]["contract"] == caller

def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def call_event(result, event):
    matches = [item for item in result["trace"] if item["event"] == event]
    assert len(matches) == 1
    return matches[0]

def normalized_step(id, mode, run, event, result=None):
    observed = call_event(run, event)
    return {
        "id": id,
        "mode": mode,
        "target": observed["address"],
        "calldata": observed["calldata"],
        "value": observed.get("value", "00" * 32),
        "status": observed["status"],
        "result": run["result"] if result is None else result,
    }

direct_trace = {
    "schema": "proof-forge.stylus.remote-common.v1",
    "renderer": "direct-wasm-local-runner",
    "observability": {"cacheTransitions": True, "nestedFrames": True},
    "steps": [
        normalized_step("call-success", "call", success, "call_contract"),
        normalized_step("call-revert", "call", revert, "call_contract"),
        normalized_step("static-success", "static", static, "static_call_contract"),
        normalized_step("delegate-success", "delegate", delegate, "delegate_call_contract"),
        normalized_step("args-success", "call", args, "call_contract"),
        normalized_step("value-success", "call", value_call, "call_contract"),
        normalized_step("bytes-success", "call", bytes_hello, "call_contract", "68656c6c6f"),
    ],
}
direct_trace_path = Path("build/stylus/remote-call/direct-normalized.json")
direct_trace_path.write_text(json.dumps(direct_trace, indent=2, sort_keys=True) + "\n")

evidence = {
    "schema": "proof-forge.stylus.remote-local.v1",
    "environment": "local-wasmtime",
    "nitro": False,
    "artifacts": {
        "remoteWasmSha256": sha256("build/stylus/remote-call/call.wasm"),
        "reentrantWasmSha256": sha256("build/stylus/reentrant/reentrant.wasm"),
    },
    "contracts": {"caller": caller, "callee": target},
    "scenarios": {
        "call": {"status": success["calls"][0]["status"], "result": success["result"]},
        "staticWrite": {"status": static_write["calls"][0]["status"], "storage": static_write["storage"]},
        "delegateContext": {"status": delegate_context["calls"][0]["status"], "storage": delegate_context["storage"]},
        "reentrantSuccess": {"status": reentrant_success["calls"][0]["status"], "storage": reentrant_success["storage"]},
        "reentrantRevert": {"status": reentrant_revert["calls"][0]["status"], "storage": reentrant_revert["storage"]},
    },
}
evidence_path = Path("build/evidence/stylus/remote-local.json")
evidence_path.parent.mkdir(parents=True, exist_ok=True)
evidence_path.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
print("stylus-remote-call-differential-runtime: ok")
PY

rust_trace="$root/build/stylus/remote-call/rust-normalized.json"
rm -f "$rust_trace"
PROOF_FORGE_STYLUS_RUST_TRACE="$rust_trace" \
RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo test --manifest-path build/stylus/remote-call/rust/Cargo.toml --features stylus-test
test -s "$rust_trace"
python3 - "$root/build/stylus/remote-call/direct-normalized.json" "$rust_trace" <<'PY'
import json
from pathlib import Path
import sys

direct = json.loads(Path(sys.argv[1]).read_text())
rust = json.loads(Path(sys.argv[2]).read_text())
assert direct["schema"] == rust["schema"] == "proof-forge.stylus.remote-common.v1"
assert direct["steps"] == rust["steps"]
assert direct["observability"] == {"cacheTransitions": True, "nestedFrames": True}
assert rust["observability"] == {"cacheTransitions": False, "nestedFrames": False}
print("stylus-remote-call-normalized-parity: ok")
PY
python3 scripts/stylus/audit-remote-hostio.py

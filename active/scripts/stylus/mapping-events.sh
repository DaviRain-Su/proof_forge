#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
export PATH="$HOME/.foundry/bin:$PATH"

lake env lean --run Tests/Stylus/MappingEventVectors.lean
wat2wasm build/stylus/mapping-events/map.wat -o build/stylus/mapping-events/map.wasm

key="$(printf '%064x' 7)"
base="$(printf '%064x' 0)"
slot="$(cast keccak "0x${key}${base}" | sed 's/^0x//')"
topic="$(cast keccak 'ValueSet(uint64,uint64)' | sed 's/^0x//')"
set_output="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/mapping-events/map.wasm \
  --calldata 1ab06ee5$(printf '%064x' 7)$(printf '%064x' 99) --invoke user_entrypoint)"
get_output="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/mapping-events/map.wasm --storage "$slot=$(printf '%064x' 99)" \
  --calldata 9507d39a$(printf '%064x' 7) --invoke user_entrypoint)"
address="$(printf '11%.0s' {1..20})"
address_word="$(printf '00%.0s' {1..12})${address}"
wide_value="0000000000000001000000000000002a"
wide_word="$(printf '00%.0s' {1..16})${wide_value}"
wide_slot="$(cast keccak "0x${address_word}$(printf '%064x' 1)" | sed 's/^0x//')"
wide_set="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/mapping-events/map.wasm \
  --calldata aabbcc01${address_word}$(printf '00%.0s' {1..16})${wide_value} \
  --invoke user_entrypoint)"
wide_get="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/mapping-events/map.wasm --storage "$wide_slot=$wide_word" \
  --calldata aabbcc02${address_word} --invoke user_entrypoint)"
other_address="$(printf '22%.0s' {1..20})"
other_word="$(printf '00%.0s' {1..12})${other_address}"
event_value="$(printf '%064x' 42)"
transfer_topic="$(cast keccak 'Transfer(address,address,uint256)' | sed 's/^0x//')"
approval_topic="$(cast keccak 'Approval(address,address,uint256)' | sed 's/^0x//')"
transfer_output="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/mapping-events/map.wasm \
  --calldata "aabbcc03${address_word}${other_word}${event_value}" --invoke user_entrypoint)"
approval_output="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/mapping-events/map.wasm \
  --calldata "aabbcc04${address_word}${other_word}${event_value}" --invoke user_entrypoint)"

python3 - "$slot" "$topic" "$wide_slot" "$wide_word" "$transfer_topic" \
  "$approval_topic" "$address_word" "$other_word" "$event_value" \
  "$set_output" "$get_output" "$wide_set" "$wide_get" "$transfer_output" \
  "$approval_output" <<'PY'
import json
import sys

slot, topic, wide_slot, wide_word, transfer_topic, approval_topic, owner, other, value = sys.argv[1:10]
set_data, get_data, wide_set, wide_get, transfer, approval = map(json.loads, sys.argv[10:16])
assert set_data["calls"][0]["status"] == 0
assert set_data["storage"][slot] == "00" * 31 + "63"
assert get_data["calls"][0]["status"] == 0
assert get_data["result"] == "00" * 31 + "63"
hashes = [item for item in set_data["trace"] if item["event"] == "native_keccak256"]
assert any(item["output"] == slot for item in hashes)
logs = [item for item in set_data["trace"] if item["event"] == "emit_log"]
assert logs == [{
    "event": "emit_log", "topics": 2,
    "value": topic + "00" * 31 + "07" + "00" * 31 + "63",
}]
assert wide_set["calls"][0]["status"] == 0
assert wide_set["storage"][wide_slot] == wide_word
assert wide_get["calls"][0]["status"] == 0 and wide_get["result"] == wide_word
expected_transfer = transfer_topic + owner + other + value
expected_approval = approval_topic + owner + other + value
assert transfer["calls"][0]["status"] == 0
assert [item for item in transfer["trace"] if item["event"] == "emit_log"] == [{
    "event": "emit_log", "topics": 3, "value": expected_transfer,
}]
assert approval["calls"][0]["status"] == 0
assert [item for item in approval["trace"] if item["event"] == "emit_log"] == [{
    "event": "emit_log", "topics": 3, "value": expected_approval,
}]
print("stylus-mapping-events-runtime: ok")
PY

RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo test --manifest-path build/stylus/mapping-events/rust/Cargo.toml --features stylus-test

#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
export PATH="$HOME/.foundry/bin:$PATH"

lake env lean --run Tests/Canonical/NestedMapShape.lean
wat2wasm build/stylus/nested-map/nested.wat -o build/stylus/nested-map/nested.wasm

owner="$(printf '11%.0s' {1..20})"
spender="$(printf '22%.0s' {1..20})"
owner_word="$(printf '00%.0s' {1..12})${owner}"
spender_word="$(printf '00%.0s' {1..12})${spender}"
base="$(printf '%064x' 0)"
owner_slot="$(cast keccak "0x${owner_word}${base}" | sed 's/^0x//')"
allowance_slot="$(cast keccak "0x${spender_word}${owner_slot}" | sed 's/^0x//')"
foundry_owner_slot="$(cast index address "0x${owner}" 0 | sed 's/^0x//')"
foundry_allowance_slot="$(cast index address "0x${spender}" "0x${foundry_owner_slot}" | sed 's/^0x//')"
test "$owner_slot" = "$foundry_owner_slot"
test "$allowance_slot" = "$foundry_allowance_slot"
value_word="$(printf '%064x' 42)"

set_output="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/nested-map/nested.wasm \
  --calldata "095ea7b3${owner_word}${spender_word}${value_word}" --invoke user_entrypoint)"
get_output="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/nested-map/nested.wasm --storage "${allowance_slot}=${value_word}" \
  --calldata "dd62ed3e${owner_word}${spender_word}" --invoke user_entrypoint)"

python3 - "$allowance_slot" "$value_word" "$set_output" "$get_output" <<'PY'
import json
import sys

slot, value, set_raw, get_raw = sys.argv[1:]
set_data = json.loads(set_raw)
get_data = json.loads(get_raw)
assert set_data["calls"][0]["status"] == 0
assert set_data["storage"][slot] == value
assert get_data["calls"][0]["status"] == 0
assert get_data["result"] == value
set_hashes = [item for item in set_data["trace"] if item["event"] == "native_keccak256"]
assert len(set_hashes) >= 2 and set_hashes[-1]["output"] == slot
print("stylus-nested-map-runtime: ok")
PY

RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo test --manifest-path build/stylus/nested-map/rust/Cargo.toml --features stylus-test

#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

lake build ProofForge.Backend.Stylus.DirectWasm.Module ProofForge.Backend.Stylus.RustSdk.Render
lake env lean --run Tests/Stylus/WideValues.lean
wat2wasm build/stylus/wide-values/wide.wat -o build/stylus/wide-values/wide.wasm

value=18446744073709551658
word="0000000000000001000000000000002a"
expected="$(printf '00%.0s' {1..16})${word}"
calldata="12345678$(printf '00%.0s' {1..16})${word}"
echo_out="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/wide-values/wide.wasm --calldata "$calldata" --invoke user_entrypoint)"
value_out="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/wide-values/wide.wasm --value "$value" --calldata 87654321 --invoke user_entrypoint)"
overflow_out="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/wide-values/wide.wasm \
  --value 010000000000000000000000000000000000000000000000000000000000002a \
  --calldata 87654321 --invoke user_entrypoint)"

python3 - "$expected" "$echo_out" "$value_out" "$overflow_out" <<'PY'
import json
import sys

expected = sys.argv[1]
echo, value, overflow = map(json.loads, sys.argv[2:])
assert echo["calls"][0]["status"] == 0 and echo["result"] == expected
assert value["calls"][0]["status"] == 0 and value["result"] == expected
assert overflow["calls"][0]["status"] == 1
assert bytes.fromhex(overflow["result"]) == b"stylus: msg.value exceeds uint128"
print("stylus-wide-values-runtime: ok")
PY

RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target cargo test \
  --manifest-path build/stylus/wide-values/rust/Cargo.toml --features stylus-test

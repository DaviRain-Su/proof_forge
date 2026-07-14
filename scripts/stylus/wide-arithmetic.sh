#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

lake build ProofForge.Backend.Stylus.DirectWasm.Module
lake env lean --run Tests/Stylus/WideArithmetic.lean
wat2wasm build/stylus/wide-arithmetic/add.wat -o build/stylus/wide-arithmetic/add.wasm

slot="$(printf '00%.0s' {1..32})"
prefix="$(printf '00%.0s' {1..16})"
base=00000000000000010000000000000005
amount=00000000000000000000000000000007
success="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/wide-arithmetic/add.wasm --storage "$slot=${prefix}${base}" \
  --calldata "aabbccdd${prefix}${amount}" --invoke user_entrypoint)"

max="$(printf 'ff%.0s' {1..16})"
one=00000000000000000000000000000001
overflow="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/wide-arithmetic/add.wasm --storage "$slot=${prefix}${max}" \
  --calldata "aabbccdd${prefix}${one}" --invoke user_entrypoint)"
literal="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/wide-arithmetic/add.wasm --calldata deadbeef --invoke user_entrypoint)"
wrapped="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/wide-arithmetic/add.wasm --storage "$slot=${prefix}${max}" \
  --calldata "cafebabe${prefix}${one}" --invoke user_entrypoint)"

python3 - "$slot" "$success" "$overflow" "$literal" "$wrapped" <<'PY'
import json
import sys

slot = sys.argv[1]
success, overflow, literal, wrapped = map(json.loads, sys.argv[2:])
result = "00" * 16 + "0000000000000001000000000000000c"
assert success["calls"][0]["status"] == 0
assert success["result"] == result and success["storage"][slot] == result
assert overflow["calls"][0]["status"] == 1
assert bytes.fromhex(overflow["result"]) == b"checked arithmetic overflow"
assert overflow["storage"][slot] == "00" * 16 + "ff" * 16
assert literal["calls"][0]["status"] == 0
assert literal["result"] == "00" * 16 + "00000000000000010000000000000005"
assert wrapped["calls"][0]["status"] == 0
assert wrapped["result"] == "00" * 32 and wrapped["storage"][slot] == "00" * 32
print("stylus-wide-arithmetic-runtime: ok")
PY

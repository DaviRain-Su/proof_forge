#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

lake env lean --run Tests/Stylus/AggregateDifferential.lean
wat2wasm build/stylus/aggregate-differential/echo.wat -o build/stylus/aggregate-differential/echo.wasm

runner_target="${CARGO_TARGET_DIR:-build/stylus/cargo-target}"
CARGO_TARGET_DIR="$runner_target" cargo build --quiet \
  --manifest-path tools/stylus-vm-runner/Cargo.toml
runner="$runner_target/debug/stylus-vm-runner"
batch_input="build/stylus/aggregate-differential/calldata.batch"
: > "$batch_input"

call() {
  printf '%s\n' "$1" >> "$batch_input"
}

head="$(printf '%064x' 32)"
empty="$(call "deadbe01${head}$(printf '%064x' 0)")"
hello_payload="68656c6c6f"
hello="$(call "deadbe01${head}$(printf '%064x' 5)${hello_payload}$(printf '00%.0s' {1..27})")"
utf8_payload="e4bda0e5a5bd"
utf8="$(call "deadbe02${head}$(printf '%064x' 6)${utf8_payload}$(printf '00%.0s' {1..26})")"
unaligned="$(call "deadbe01$(printf '%064x' 33)$(printf '%064x' 0)")"
truncated="$(call "deadbe01${head}$(printf '%064x' 33)$(printf '00%.0s' {1..32})")"
over_limit="$(call "deadbe01${head}$(printf '%064x' 4097)$(printf '00%.0s' {1..4128})")"
fixed="$(call "deadbe03$(printf '%064x' 7)$(printf '%064x' 9)")"
fixed_bad="$(call "deadbe03ff$(printf '00%.0s' {1..31})$(printf '%064x' 9)")"
address_word="$(printf '00%.0s' {1..12})$(printf '11%.0s' {1..20})"
tuple="$(call "deadbe04${address_word}$(printf '%064x' 7)$(printf '%064x' 9)")"
tuple_bad="$(call "deadbe0401$(printf '00%.0s' {1..11})$(printf '11%.0s' {1..20})$(printf '%064x' 7)$(printf '%064x' 9)")"
mixed_head="$(printf '%064x' 7)$(printf '%064x' 9)$(printf '%064x' 96)"
mixed="$(call "deadbe05${mixed_head}$(printf '%064x' 5)${hello_payload}$(printf '00%.0s' {1..27})")"
mixed_bad="$(call "deadbe05$(printf '%064x' 7)$(printf '%064x' 9)$(printf '%064x' 64)$(printf '%064x' 0)")"
array="$(call "deadbe06${head}$(printf '%064x' 2)$(printf '%064x' 7)$(printf '%064x' 9)")"
array_bad="$(call "deadbe06${head}$(printf '%064x' 2)$(printf '%064x' 7)01$(printf '00%.0s' {1..31})")"
array_truncated="$(call "deadbe06${head}$(printf '%064x' 2)$(printf '%064x' 7)")"
tuple_array="$(call "deadbe07${head}$(printf '%064x' 1)${address_word}$(printf '%064x' 7)$(printf '%064x' 9)")"
tuple_array_bad="$(call "deadbe07${head}$(printf '%064x' 1)01$(printf '00%.0s' {1..11})$(printf '11%.0s' {1..20})$(printf '%064x' 7)$(printf '%064x' 9)")"
dynamic_tuple="$(call "deadbe08${head}$(printf '%064x' 7)$(printf '%064x' 64)$(printf '%064x' 5)${hello_payload}$(printf '00%.0s' {1..27})")"
dynamic_tuple_bad="$(call "deadbe08${head}$(printf '%064x' 7)${head}$(printf '%064x' 0)")"
dynamic_tuple_high_length="$(call "deadbe08${head}$(printf '%064x' 7)$(printf '%064x' 64)01$(printf '00%.0s' {1..31})")"
multi_tuple_payload="$(printf '%064x' 7)$(printf '%064x' 96)$(printf '%064x' 160)$(printf '%064x' 5)${hello_payload}$(printf '00%.0s' {1..27})$(printf '%064x' 6)${utf8_payload}$(printf '00%.0s' {1..26})"
multi_dynamic_tuple="$(call "deadbe09${head}${multi_tuple_payload}")"
multi_dynamic_inside_head="$(call "deadbe09${head}$(printf '%064x' 7)$(printf '%064x' 64)$(printf '%064x' 160)$(printf '%064x' 0)$(printf '%064x' 0)$(printf '%064x' 0)")"
multi_dynamic_over_limit="$(call "deadbe09${head}$(printf '%064x' 7)$(printf '%064x' 96)$(printf '%064x' 224)$(printf '%064x' 65)$(printf '00%.0s' {1..96})$(printf '%064x' 0)")"
multi_dynamic_truncated="$(call "deadbe09${head}$(printf '%064x' 7)$(printf '%064x' 96)$(printf '%064x' 128)$(printf '%064x' 0)$(printf '%064x' 33)$(printf '00%.0s' {1..32})")"
bytes_array_payload="$(printf '%064x' 2)$(printf '%064x' 64)$(printf '%064x' 128)$(printf '%064x' 2)6869$(printf '00%.0s' {1..30})$(printf '%064x' 5)776f726c64$(printf '00%.0s' {1..27})"
bytes_array="$(call "deadbe0a${head}${bytes_array_payload}")"
bytes_array_inside_head="$(call "deadbe0a${head}$(printf '%064x' 2)$(printf '%064x' 32)$(printf '%064x' 128)$(printf '00%.0s' {1..128})")"
bytes_array_unaligned="$(call "deadbe0a${head}$(printf '%064x' 1)$(printf '%064x' 65)$(printf '00%.0s' {1..96})")"
bytes_array_high_offset="$(call "deadbe0a${head}$(printf '%064x' 1)$(printf '%064x' 4294967264)$(printf '00%.0s' {1..96})")"
bytes_array_over_limit="$(call "deadbe0a${head}$(printf '%064x' 1)$(printf '%064x' 32)$(printf '%064x' 17)$(printf '00%.0s' {1..32})")"
bytes_array_truncated="$(call "deadbe0a${head}$(printf '%064x' 2)$(printf '%064x' 64)$(printf '%064x' 128)$(printf '%064x' 0)$(printf '00%.0s' {1..32})$(printf '%064x' 10)776f726c64")"
nested_array_tuple="$(call "deadbe0b${head}$(printf '%064x' 7)$(printf '%064x' 64)$(printf '%064x' 2)$(printf '%064x' 7)$(printf '%064x' 9)")"
nested_array_tuple_inside_head="$(call "deadbe0b${head}$(printf '%064x' 7)$(printf '%064x' 32)$(printf '00%.0s' {1..96})")"
nested_array_tuple_high_offset="$(call "deadbe0b${head}$(printf '%064x' 7)$(printf '%064x' 4294967264)$(printf '00%.0s' {1..96})")"
nested_array_tuple_over_limit="$(call "deadbe0b${head}$(printf '%064x' 7)$(printf '%064x' 64)$(printf '%064x' 4)$(printf '00%.0s' {1..128})")"
nested_array_tuple_bad="$(call "deadbe0b${head}$(printf '%064x' 7)$(printf '%064x' 64)$(printf '%064x' 2)$(printf '%064x' 7)01$(printf '00%.0s' {1..31})")"
nested_array_tuple_truncated="$(call "deadbe0b${head}$(printf '%064x' 7)$(printf '%064x' 64)$(printf '%064x' 2)$(printf '%064x' 7)")"
batch_output="$("$runner" build/stylus/aggregate-differential/echo.wasm \
  --calldata-file "$batch_input" --invoke user_entrypoint)"

python3 - "$batch_output" <<'PY'
import json
import sys

batch = json.loads(sys.argv[1])["batch"]
(empty, hello, utf8, unaligned, truncated, over_limit, fixed, fixed_bad, tuple,
 tuple_bad, mixed, mixed_bad, array, array_bad, array_truncated, tuple_array,
 tuple_array_bad, dynamic_tuple, dynamic_tuple_bad, dynamic_tuple_high_length,
 multi_dynamic_tuple, multi_dynamic_inside_head, multi_dynamic_over_limit,
 multi_dynamic_truncated, bytes_array, bytes_array_inside_head,
 bytes_array_unaligned, bytes_array_high_offset, bytes_array_over_limit,
 bytes_array_truncated, nested_array_tuple, nested_array_tuple_inside_head,
 nested_array_tuple_high_offset, nested_array_tuple_over_limit,
 nested_array_tuple_bad, nested_array_tuple_truncated) = batch
assert empty["calls"][0]["status"] == 0
assert empty["result"] == "00" * 31 + "20" + "00" * 32
assert hello["calls"][0]["status"] == 0 and bytes.fromhex(hello["result"])[64:69] == b"hello"
assert utf8["calls"][0]["status"] == 0 and bytes.fromhex(utf8["result"])[64:70] == "你好".encode()
for rejected in (unaligned, truncated, over_limit):
    assert rejected["calls"][0]["status"] == 1
    assert bytes.fromhex(rejected["result"]) == b"stylus: malformed calldata"
assert fixed["calls"][0]["status"] == 0
assert fixed["result"] == f"{7:064x}{9:064x}"
assert fixed_bad["calls"][0]["status"] == 1
assert bytes.fromhex(fixed_bad["result"]) == b"stylus: malformed calldata"
assert tuple["calls"][0]["status"] == 0
assert tuple["result"] == "00" * 12 + "11" * 20 + f"{7:064x}{9:064x}"
assert tuple_bad["calls"][0]["status"] == 1
assert bytes.fromhex(tuple_bad["result"]) == b"stylus: malformed calldata"
assert mixed["calls"][0]["status"] == 0 and bytes.fromhex(mixed["result"])[64:69] == b"hello"
assert mixed_bad["calls"][0]["status"] == 1
assert bytes.fromhex(mixed_bad["result"]) == b"stylus: malformed calldata"
assert array["calls"][0]["status"] == 0
assert array["result"] == f"{32:064x}{2:064x}{7:064x}{9:064x}"
for rejected in (array_bad, array_truncated):
    assert rejected["calls"][0]["status"] == 1
    assert bytes.fromhex(rejected["result"]) == b"stylus: malformed calldata"
assert tuple_array["calls"][0]["status"] == 0
assert tuple_array["result"] == f"{32:064x}{1:064x}" + "00" * 12 + "11" * 20 + f"{7:064x}{9:064x}"
assert tuple_array_bad["calls"][0]["status"] == 1
assert bytes.fromhex(tuple_array_bad["result"]) == b"stylus: malformed calldata"
assert dynamic_tuple["calls"][0]["status"] == 0 and dynamic_tuple["result"] == ""
assert dynamic_tuple_bad["calls"][0]["status"] == 1
assert bytes.fromhex(dynamic_tuple_bad["result"]) == b"stylus: malformed calldata"
assert dynamic_tuple_high_length["calls"][0]["status"] == 1
assert bytes.fromhex(dynamic_tuple_high_length["result"]) == b"stylus: malformed calldata"
assert multi_dynamic_tuple["calls"][0]["status"] == 0
for rejected in (multi_dynamic_inside_head, multi_dynamic_over_limit, multi_dynamic_truncated):
    assert rejected["calls"][0]["status"] == 1
    assert bytes.fromhex(rejected["result"]) == b"stylus: malformed calldata"
assert bytes_array["calls"][0]["status"] == 0 and bytes_array["result"] == ""
for rejected in (bytes_array_inside_head, bytes_array_unaligned, bytes_array_high_offset, bytes_array_over_limit, bytes_array_truncated):
    assert rejected["calls"][0]["status"] == 1
    assert bytes.fromhex(rejected["result"]) == b"stylus: malformed calldata"
assert nested_array_tuple["calls"][0]["status"] == 0 and nested_array_tuple["result"] == ""
for rejected in (nested_array_tuple_inside_head, nested_array_tuple_high_offset,
                 nested_array_tuple_over_limit, nested_array_tuple_bad,
                 nested_array_tuple_truncated):
    assert rejected["calls"][0]["status"] == 1
    assert bytes.fromhex(rejected["result"]) == b"stylus: malformed calldata"
print("stylus-aggregate-differential-runtime: ok")
PY

lock_cache="build/stylus/aggregate-differential/rust.Cargo.lock"
if [[ -f "$lock_cache" ]]; then
  cp "$lock_cache" build/stylus/aggregate-differential/rust/Cargo.lock
fi
RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo test --manifest-path build/stylus/aggregate-differential/rust/Cargo.toml --features stylus-test
cp build/stylus/aggregate-differential/rust/Cargo.lock "$lock_cache"

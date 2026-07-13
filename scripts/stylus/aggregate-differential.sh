#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

lake env lean --run Tests/Stylus/AggregateDifferential.lean
wat2wasm build/stylus/aggregate-differential/echo.wat -o build/stylus/aggregate-differential/echo.wasm

call() {
  cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
    build/stylus/aggregate-differential/echo.wasm --calldata "$1" --invoke user_entrypoint
}

head="$(printf '%064x' 32)"
empty="$(call "deadbe01${head}$(printf '%064x' 0)")"
hello_payload="68656c6c6f"
hello="$(call "deadbe01${head}$(printf '%064x' 5)${hello_payload}$(printf '00%.0s' {1..27})")"
utf8_payload="e4bda0e5a5bd"
utf8="$(call "deadbe02${head}$(printf '%064x' 6)${utf8_payload}$(printf '00%.0s' {1..26})")"
unaligned="$(call "deadbe01$(printf '%064x' 33)$(printf '%064x' 0)")"
truncated="$(call "deadbe01${head}$(printf '%064x' 33)$(printf '00%.0s' {1..32})")"
over_limit="$(call "deadbe01${head}$(printf '%064x' 65)$(printf '00%.0s' {1..96})")"
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

python3 - "$empty" "$hello" "$utf8" "$unaligned" "$truncated" "$over_limit" "$fixed" "$fixed_bad" "$tuple" "$tuple_bad" "$mixed" "$mixed_bad" "$array" "$array_bad" "$array_truncated" "$tuple_array" "$tuple_array_bad" <<'PY'
import json
import sys

empty, hello, utf8, unaligned, truncated, over_limit, fixed, fixed_bad, tuple, tuple_bad, mixed, mixed_bad, array, array_bad, array_truncated, tuple_array, tuple_array_bad = map(json.loads, sys.argv[1:])
assert empty["calls"][0]["status"] == 0
assert empty["result"] == "00" * 31 + "20" + "00" * 32
assert hello["calls"][0]["status"] == 0 and bytes.fromhex(hello["result"])[64:69] == b"hello"
assert utf8["calls"][0]["status"] == 0 and bytes.fromhex(utf8["result"])[64:70] == "你好".encode()
for rejected in (unaligned, truncated, over_limit):
    assert rejected["calls"][0]["status"] == 1
    assert bytes.fromhex(rejected["result"]) == b"stylus: malformed calldata"
assert fixed["calls"][0]["status"] == 0 and fixed["result"] == ""
assert fixed_bad["calls"][0]["status"] == 1
assert bytes.fromhex(fixed_bad["result"]) == b"stylus: malformed calldata"
assert tuple["calls"][0]["status"] == 0 and tuple["result"] == ""
assert tuple_bad["calls"][0]["status"] == 1
assert bytes.fromhex(tuple_bad["result"]) == b"stylus: malformed calldata"
assert mixed["calls"][0]["status"] == 0 and bytes.fromhex(mixed["result"])[64:69] == b"hello"
assert mixed_bad["calls"][0]["status"] == 1
assert bytes.fromhex(mixed_bad["result"]) == b"stylus: malformed calldata"
assert array["calls"][0]["status"] == 0 and array["result"] == ""
for rejected in (array_bad, array_truncated):
    assert rejected["calls"][0]["status"] == 1
    assert bytes.fromhex(rejected["result"]) == b"stylus: malformed calldata"
assert tuple_array["calls"][0]["status"] == 0 and tuple_array["result"] == ""
assert tuple_array_bad["calls"][0]["status"] == 1
assert bytes.fromhex(tuple_array_bad["result"]) == b"stylus: malformed calldata"
print("stylus-aggregate-differential-runtime: ok")
PY

RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo test --manifest-path build/stylus/aggregate-differential/rust/Cargo.toml --features stylus-test

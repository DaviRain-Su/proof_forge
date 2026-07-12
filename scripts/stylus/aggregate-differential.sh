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

python3 - "$empty" "$hello" "$utf8" "$unaligned" "$truncated" "$over_limit" <<'PY'
import json
import sys

empty, hello, utf8, unaligned, truncated, over_limit = map(json.loads, sys.argv[1:])
assert empty["calls"][0]["status"] == 0
assert empty["result"] == "00" * 31 + "20" + "00" * 32
assert hello["calls"][0]["status"] == 0 and bytes.fromhex(hello["result"])[64:69] == b"hello"
assert utf8["calls"][0]["status"] == 0 and bytes.fromhex(utf8["result"])[64:70] == "你好".encode()
for rejected in (unaligned, truncated, over_limit):
    assert rejected["calls"][0]["status"] == 1
    assert bytes.fromhex(rejected["result"]) == b"stylus: malformed calldata"
print("stylus-aggregate-differential-runtime: ok")
PY

RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo test --manifest-path build/stylus/aggregate-differential/rust/Cargo.toml --features stylus-test

#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

lake env lean --run Tests/Stylus/AggregateStorage.lean
wat2wasm build/stylus/aggregate-storage/storage.wat \
  -o build/stylus/aggregate-storage/storage.wasm
RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo test --quiet --features stylus-test \
    --manifest-path build/stylus/aggregate-storage/rust/Cargo.toml
for variant in bool uint16 uint128 address; do
  wat2wasm "build/stylus/aggregate-storage/scalars/$variant/storage.wat" \
    -o "build/stylus/aggregate-storage/scalars/$variant/storage.wasm"
  RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
    cargo check --quiet --manifest-path \
      "build/stylus/aggregate-storage/scalars/$variant/rust/Cargo.toml"
done

runner_target="${CARGO_TARGET_DIR:-build/stylus/cargo-target}"
CARGO_TARGET_DIR="$runner_target" cargo build --quiet \
  --manifest-path tools/stylus-vm-runner/Cargo.toml
runner="$runner_target/debug/stylus-vm-runner"
batch="build/stylus/aggregate-storage/calldata.batch"
python3 - "$batch" <<'PY'
import sys

path = sys.argv[1]

def word(value):
    return f"{value:064x}"

def set_payload(payload):
    padding = "00" * ((32 - len(payload) % 32) % 32)
    return "aabbcc01" + word(32) + word(len(payload)) + payload.hex() + padding

with open(path, "w", encoding="ascii") as output:
    for calldata in (
        set_payload(b"hello"), "aabbcc02",
        set_payload(bytes(range(64))), "aabbcc02",
        set_payload(b"bye"), "aabbcc02",
    ):
        output.write(calldata + "\n")
PY

runtime="$($runner build/stylus/aggregate-storage/storage.wasm \
  --calldata-file "$batch" --shared-storage-batch --invoke user_entrypoint)"
python3 - "$runtime" <<'PY'
import json
import sys

batch = json.loads(sys.argv[1])["batch"]
assert all(item["calls"][0]["status"] == 0 for item in batch)

def decode(result):
    encoded = bytes.fromhex(result)
    assert int.from_bytes(encoded[:32], "big") == 32
    length = int.from_bytes(encoded[32:64], "big")
    return encoded[64:64 + length]

assert decode(batch[1]["result"]) == b"hello"
assert decode(batch[3]["result"]) == bytes(range(64))
assert decode(batch[5]["result"]) == b"bye"
assert len(batch[3]["storage"]) == 3
assert len(batch[5]["storage"]) == 3
assert sum(value != "00" * 32 for value in batch[5]["storage"].values()) == 1
print("stylus-aggregate-storage-runtime: ok")
PY

text_batch="build/stylus/aggregate-storage/string-calldata.batch"
python3 - "$text_batch" <<'PY'
import sys

path = sys.argv[1]

def word(value):
    return f"{value:064x}"

def set_text(text):
    payload = text.encode("utf-8")
    padding = "00" * ((32 - len(payload) % 32) % 32)
    return "aabbcc03" + word(32) + word(len(payload)) + payload.hex() + padding

with open(path, "w", encoding="ascii") as output:
    for calldata in (
        set_text("hello"), "aabbcc04",
        set_text("x" * 64), "aabbcc04",
        set_text("你好"), "aabbcc04",
    ):
        output.write(calldata + "\n")
PY

text_runtime="$($runner build/stylus/aggregate-storage/storage.wasm \
  --calldata-file "$text_batch" --shared-storage-batch --invoke user_entrypoint)"
python3 - "$text_runtime" <<'PY'
import json
import sys

batch = json.loads(sys.argv[1])["batch"]
assert all(item["calls"][0]["status"] == 0 for item in batch)

def decode(result):
    encoded = bytes.fromhex(result)
    length = int.from_bytes(encoded[32:64], "big")
    return encoded[64:64 + length].decode("utf-8")

assert decode(batch[1]["result"]) == "hello"
assert decode(batch[3]["result"]) == "x" * 64
assert decode(batch[5]["result"]) == "你好"
assert sum(value != "00" * 32 for value in batch[5]["storage"].values()) == 1
print("stylus-aggregate-string-storage-runtime: ok")
PY

array_batch="build/stylus/aggregate-storage/array-calldata.batch"
python3 - "$array_batch" <<'PY'
import sys

path = sys.argv[1]

def word(value):
    return f"{value:064x}"

def set_values(values):
    return "aabbcc05" + word(32) + word(len(values)) + "".join(word(value) for value in values)

with open(path, "w", encoding="ascii") as output:
    for calldata in (
        set_values([1, 2, 3]), "aabbcc06",
        set_values([10, 20, 30, 40, 50, 60, 70, 80]), "aabbcc06",
        set_values([9]), "aabbcc06",
    ):
        output.write(calldata + "\n")
PY

array_runtime="$($runner build/stylus/aggregate-storage/storage.wasm \
  --calldata-file "$array_batch" --shared-storage-batch --invoke user_entrypoint)"
python3 - "$array_runtime" <<'PY'
import json
import sys

batch = json.loads(sys.argv[1])["batch"]
assert all(item["calls"][0]["status"] == 0 for item in batch)

def decode(result):
    encoded = bytes.fromhex(result)
    length = int.from_bytes(encoded[32:64], "big")
    return [int.from_bytes(encoded[64 + 32 * index:96 + 32 * index], "big")
            for index in range(length)]

assert decode(batch[1]["result"]) == [1, 2, 3]
assert decode(batch[3]["result"]) == [10, 20, 30, 40, 50, 60, 70, 80]
assert decode(batch[5]["result"]) == [9]
assert len(batch[3]["storage"]) == 3
assert len(batch[5]["storage"]) == 3
assert sum(value != "00" * 32 for value in batch[5]["storage"].values()) == 2
print("stylus-aggregate-array-storage-runtime: ok")
PY

array_over_limit="aabbcc05$(printf '%064x' 32)$(printf '%064x' 9)"
for value in {1..9}; do array_over_limit+="$(printf '%064x' "$value")"; done
rejected="$($runner build/stylus/aggregate-storage/storage.wasm \
  --calldata "$array_over_limit" --invoke user_entrypoint)"
python3 - "$rejected" <<'PY'
import json
import sys
case = json.loads(sys.argv[1])
assert case["calls"][0]["status"] == 1
assert bytes.fromhex(case["result"]) == b"stylus: malformed calldata"
print("stylus-aggregate-array-over-limit: ok")
PY

slot_two="$(printf '%064x' 2)"
length_nine="$(printf '%064x' 9)"
corrupt="$($runner build/stylus/aggregate-storage/storage.wasm \
  --storage "$slot_two=$length_nine" --calldata aabbcc06 --invoke user_entrypoint)"
python3 - "$corrupt" <<'PY'
import json
import sys
case = json.loads(sys.argv[1])
assert case["calls"][0]["status"] == 1
assert bytes.fromhex(case["result"]) == b"stylus: corrupt dynamic array length"
print("stylus-aggregate-array-corrupt-root: ok")
PY

echo "stylus-aggregate-storage-artifacts: ok"

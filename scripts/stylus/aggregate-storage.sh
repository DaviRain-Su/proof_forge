#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

lake env lean --run Tests/Stylus/AggregateStorage.lean
wat2wasm build/stylus/aggregate-storage/storage.wat \
  -o build/stylus/aggregate-storage/storage.wasm
RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo check --quiet --manifest-path build/stylus/aggregate-storage/rust/Cargo.toml

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
        set_payload(bytes(range(40))), "aabbcc02",
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
assert decode(batch[3]["result"]) == bytes(range(40))
assert decode(batch[5]["result"]) == b"bye"
assert len(batch[3]["storage"]) == 3
assert len(batch[5]["storage"]) == 3
assert sum(value != "00" * 32 for value in batch[5]["storage"].values()) == 1
print("stylus-aggregate-storage-runtime: ok")
PY

echo "stylus-aggregate-storage-artifacts: ok"

#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

lake env lean --run Tests/Stylus/ValueVaultCanonical.lean
wat2wasm build/stylus/value-vault-canonical/value-vault.wat \
  -o build/stylus/value-vault-canonical/value-vault.wasm

output="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/value-vault-canonical/value-vault.wasm \
  --block-number 42 \
  --calldata 8129fc1c0000000000000000000000000000000000000000000000000000000000000005 \
  --invoke user_entrypoint)"
slot0="$(printf '%064x' 0)"
slot1="$(printf '%064x' 1)"
slot2="$(printf '%064x' 2)"
slot3="$(printf '%064x' 3)"
slot5="$(printf '%064x' 5)"
charge="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/value-vault-canonical/value-vault.wasm \
  --storage "$slot0=$(printf '%064x' 5)" --storage "$slot2=$(printf '%064x' 0)" \
  --storage "$slot3=$(printf '%064x' 5)" --storage "$slot5=$(printf '%064x' 1)" \
  --calldata 4ef4885b$(printf '%064x' 1000)$(printf '%064x' 100) --invoke user_entrypoint)"
release="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/value-vault-canonical/value-vault.wasm \
  --storage "$slot0=$(printf '%064x' 5)" --storage "$slot1=$(printf '%064x' 0)" \
  --storage "$slot3=$(printf '%064x' 5)" --storage "$slot5=$(printf '%064x' 1)" \
  --calldata b214faa5$(printf '%064x' 3) --invoke user_entrypoint)"
net="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/value-vault-canonical/value-vault.wasm \
  --storage "$slot0=$(printf '%064x' 5)" --storage "$slot2=$(printf '%064x' 2)" \
  --calldata 1a381be1 --invoke user_entrypoint)"

python3 - "$output" "$charge" "$release" "$net" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
charge = json.loads(sys.argv[2])
release = json.loads(sys.argv[3])
net = json.loads(sys.argv[4])
assert data["calls"] == [{"export": "user_entrypoint", "result": "", "status": 0}]
words = list(data["storage"].values())
assert words == [
    "00" * 31 + "05", "00" * 32, "00" * 32,
    "00" * 31 + "05", "00" * 31 + "2a", "00" * 31 + "01",
]
logs = [event for event in data["trace"] if event["event"] == "emit_log"]
flushes = [event for event in data["trace"] if event["event"] == "storage_flush"]
assert len(logs) == 1 and logs[0]["topics"] == 1
assert logs[0]["value"].endswith("00" * 31 + "05" + "00" * 31 + "2a")
assert flushes == [{"clear": False, "event": "storage_flush", "writes": 6}]
assert charge["calls"][0]["status"] == 0
assert int(charge["storage"]["00" * 31 + "00"], 16) == 995
assert int(charge["storage"]["00" * 31 + "02"], 16) == 10
assert int(charge["storage"]["00" * 31 + "03"], 16) == 990
assert int(charge["storage"]["00" * 31 + "05"], 16) == 2
assert release["calls"][0]["status"] == 0
assert int(release["storage"]["00" * 31 + "00"], 16) == 2
assert int(release["storage"]["00" * 31 + "01"], 16) == 3
assert net["calls"][0]["status"] == 0 and int(net["result"], 16) == 3
print("stylus-value-vault-canonical-runtime: ok")
PY

RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo test --manifest-path build/stylus/value-vault-canonical/rust/Cargo.toml \
  --features stylus-test

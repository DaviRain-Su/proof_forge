#!/usr/bin/env bash
set -euo pipefail

lake build ProofForge.Backend.Stylus.DirectWasm.Module ProofForge.Backend.Stylus.Differential \
  ProofForge.Backend.Stylus.ValueVaultSemantics ProofForge.Backend.Stylus.RustSdk.Render
lake env lean --run Tests/Stylus/CounterDifferential.lean
wat2wasm build/stylus/counter-differential/counter.wat \
  -o build/stylus/counter-differential/counter.wasm

output="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/counter-differential/counter.wasm \
  __pf_initialize __pf_increment __pf_get)"

python3 - "$output" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
assert [call["status"] for call in data["calls"]] == [0, 0, 0]
word_one = "00" * 31 + "01"
assert data["storage"]["00" * 32] == word_one
assert data["result"] == word_one
events = [event["event"] for event in data["trace"]]
assert "storage_load" in events
assert "storage_cache" in events
assert "storage_flush" in events
assert "write_result" in events
print("stylus-vm-runner: ok")
PY

entrypoint="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/counter-differential/counter.wasm \
  --storage "$(printf '00%.0s' {1..32})=$(printf '00%.0s' {1..31})01" \
  --calldata 6d4ce63c --invoke user_entrypoint)"
python3 - "$entrypoint" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
assert data["calls"][0]["status"] == 0
assert data["result"] == "00" * 31 + "01"
assert any(event["event"] == "read_args" for event in data["trace"])
print("stylus-vm-runner-entrypoint: ok")
PY

lake env lean --run Tests/Stylus/ValueVaultDifferential.lean
wat2wasm build/stylus/value-vault-differential/authorization.wat \
  -o build/stylus/value-vault-differential/authorization.wasm

owner="1111111111111111111111111111111111111111"
slot="$(printf '00%.0s' {1..32})"
owner_word="$(printf '00%.0s' {1..12})${owner}"
authorized="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/value-vault-differential/authorization.wasm \
  --sender "$owner" --storage "$slot=$owner_word" --invoke __pf_withdraw)"
rejected="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/value-vault-differential/authorization.wasm \
  --sender "$owner" --value 1 --storage "$slot=$owner_word" --invoke __pf_withdraw)"

python3 - "$authorized" "$rejected" <<'PY'
import json
import sys

authorized = json.loads(sys.argv[1])
rejected = json.loads(sys.argv[2])
assert authorized["calls"][0]["status"] == 0
assert rejected["calls"][0]["status"] == 1
assert bytes.fromhex(rejected["result"]) == b"stylus: nonpayable"
print("stylus-vm-runner-context: ok")
PY

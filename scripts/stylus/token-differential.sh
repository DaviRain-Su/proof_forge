#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
export PATH="$HOME/.foundry/bin:$PATH"

lake env lean --run Tests/Stylus/TokenDifferential.lean
wat2wasm build/stylus/token/token.wat -o build/stylus/token/token.wasm

alice="0x$(printf '11%.0s' {1..20})"
bob="0x$(printf '22%.0s' {1..20})"
spender="0x$(printf '33%.0s' {1..20})"
alice_balance="$(cast index address "$alice" 2 | sed 's/^0x//')"
bob_balance="$(cast index address "$bob" 2 | sed 's/^0x//')"
allowance_owner="$(cast index address "$alice" 3 | sed 's/^0x//')"
allowance_slot="$(cast index address "$spender" "0x${allowance_owner}" | sed 's/^0x//')"
transfer_topic="$(cast keccak 'Transfer(address,address,uint256)' | sed 's/^0x//')"
approval_topic="$(cast keccak 'Approval(address,address,uint256)' | sed 's/^0x//')"

python3 - "$alice" "$bob" "$spender" "$alice_balance" "$bob_balance" \
  "$allowance_slot" "$transfer_topic" "$approval_topic" <<'PY'
import json
import subprocess
import sys

alice, bob, spender, alice_slot, bob_slot, allowance_slot, transfer_topic, approval_topic = sys.argv[1:]
wasm = "build/stylus/token/token.wasm"
manifest = "tools/stylus-vm-runner/Cargo.toml"

def word(value):
    return f"{value:064x}"

def address_word(address):
    return "00" * 12 + address.removeprefix("0x")

def invoke(selector, args, sender, storage):
    command = ["cargo", "run", "--quiet", "--manifest-path", manifest, "--", wasm,
               "--sender", sender.removeprefix("0x"), "--calldata", selector + "".join(args)]
    for slot, value in storage.items():
        command += ["--storage", f"{slot}={value}"]
    command += ["--invoke", "user_entrypoint"]
    return json.loads(subprocess.check_output(command, text=True))

def emitted(output):
    return [item for item in output["trace"] if item["event"] == "emit_log"]

storage = {}
mint = invoke("40c10f19", [address_word(alice), word(100)], alice, storage)
assert mint["calls"][0]["status"] == 0
storage = mint["storage"]
assert storage[word(0)] == word(100)
assert storage[alice_slot] == word(100)
assert emitted(mint)[0]["value"] == transfer_topic + word(0) + address_word(alice) + word(100)

transfer = invoke("a9059cbb", [address_word(bob), word(30)], alice, storage)
assert transfer["calls"][0]["status"] == 0 and transfer["result"] == word(1)
storage = transfer["storage"]
assert storage[alice_slot] == word(70) and storage[bob_slot] == word(30), (storage, transfer["trace"])
assert emitted(transfer)[0]["value"] == transfer_topic + address_word(alice) + address_word(bob) + word(30)

approval = invoke("095ea7b3", [address_word(spender), word(40)], alice, storage)
assert approval["calls"][0]["status"] == 0 and approval["result"] == word(1)
storage = approval["storage"]
assert storage[allowance_slot] == word(40)
assert emitted(approval)[0]["value"] == approval_topic + address_word(alice) + address_word(spender) + word(40)

spent = invoke("23b872dd", [address_word(alice), address_word(bob), word(25)], spender, storage)
assert spent["calls"][0]["status"] == 0 and spent["result"] == word(1)
storage = spent["storage"]
assert storage[allowance_slot] == word(15)
assert storage[alice_slot] == word(45) and storage[bob_slot] == word(55)

before_failure = storage.copy()
failed = invoke("23b872dd", [address_word(alice), address_word(bob), word(20)], spender, storage)
assert failed["calls"][0]["status"] == 1
assert failed["storage"] == before_failure

zero = invoke("a9059cbb", [word(0), word(1)], alice, storage)
assert zero["calls"][0]["status"] == 1 and zero["storage"] == storage

balance = invoke("70a08231", [address_word(alice)], alice, storage)
assert balance["calls"][0]["status"] == 0 and balance["result"] == word(45)

insufficient = invoke("a9059cbb", [address_word(alice), word(1000)], bob, storage)
assert insufficient["calls"][0]["status"] == 1 and insufficient["storage"] == storage

self_transfer = invoke("a9059cbb", [address_word(alice), word(5)], alice, storage)
assert self_transfer["calls"][0]["status"] == 0
assert self_transfer["storage"] == storage
assert emitted(self_transfer)[0]["value"] == transfer_topic + address_word(alice) + address_word(alice) + word(5)

maximum = (1 << 64) - 1
unlimited = invoke("095ea7b3", [address_word(spender), word(maximum)], alice, storage)
assert unlimited["calls"][0]["status"] == 0
storage = unlimited["storage"]
unlimited_spent = invoke("23b872dd", [address_word(alice), address_word(bob), word(1)], spender, storage)
assert unlimited_spent["calls"][0]["status"] == 0
storage = unlimited_spent["storage"]
assert storage[allowance_slot] == word(maximum)
assert storage[alice_slot] == word(44) and storage[bob_slot] == word(56)
print("stylus-token-differential-runtime: ok")
PY

RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo test --manifest-path build/stylus/token/rust/Cargo.toml --features stylus-test

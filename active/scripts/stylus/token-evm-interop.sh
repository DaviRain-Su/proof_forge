#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
export PATH="$HOME/.foundry/bin:$PATH"

command -v cast >/dev/null || { echo "stylus-token-evm-interop: cast is required" >&2; exit 1; }

lake env lean --run Tests/Stylus/TokenDifferential.lean
wat2wasm build/stylus/token/token.wat -o build/stylus/token/token.wasm

python3 - <<'PY'
import json
import subprocess

wasm = "build/stylus/token/token.wasm"
runner = "tools/stylus-vm-runner/Cargo.toml"
alice = "0x" + "11" * 20
bob = "0x" + "22" * 20
spender = "0x" + "33" * 20

def cast(*args):
    return subprocess.check_output(["cast", *args], text=True).strip().removeprefix("0x")

def word(value):
    return f"{value:064x}"

def slot(signature, key, base):
    return cast("index", signature, key, base)

alice_slot = slot("address", alice, "2")
bob_slot = slot("address", bob, "2")
owner_slot = slot("address", alice, "3")
allowance_slot = slot("address", spender, "0x" + owner_slot)
transfer_topic = cast("keccak", "Transfer(address,address,uint256)")
approval_topic = cast("keccak", "Approval(address,address,uint256)")

def invoke(signature, args, sender, storage):
    calldata = cast("calldata", signature, *map(str, args))
    command = [
        "cargo", "run", "--quiet", "--manifest-path", runner, "--", wasm,
        "--sender", sender.removeprefix("0x"), "--calldata", calldata,
    ]
    for key, value in storage.items():
        command += ["--storage", f"{key}={value}"]
    command += ["--invoke", "user_entrypoint"]
    return json.loads(subprocess.check_output(command, text=True))

def log(output):
    return next(item["value"] for item in output["trace"] if item["event"] == "emit_log")

storage = {}
mint = invoke("mint(address,uint256)", [alice, 100], alice, storage)
assert mint["calls"][0]["status"] == 0
storage = mint["storage"]
assert storage[word(0)] == word(100) and storage[alice_slot] == word(100)
assert log(mint) == transfer_topic + word(0) + word(int(alice, 16)) + word(100)

transfer = invoke("transfer(address,uint256)", [bob, 30], alice, storage)
assert transfer["calls"][0]["status"] == 0 and transfer["result"] == word(1)
storage = transfer["storage"]
assert storage[alice_slot] == word(70) and storage[bob_slot] == word(30)
assert log(transfer) == transfer_topic + word(int(alice, 16)) + word(int(bob, 16)) + word(30)

approve = invoke("approve(address,uint256)", [spender, 40], alice, storage)
assert approve["calls"][0]["status"] == 0 and approve["result"] == word(1)
storage = approve["storage"]
assert storage[allowance_slot] == word(40)
assert log(approve) == approval_topic + word(int(alice, 16)) + word(int(spender, 16)) + word(40)

spent = invoke("transferFrom(address,address,uint256)", [alice, bob, 25], spender, storage)
assert spent["calls"][0]["status"] == 0 and spent["result"] == word(1)
storage = spent["storage"]
assert storage[alice_slot] == word(45) and storage[bob_slot] == word(55)
assert storage[allowance_slot] == word(15)

balance = invoke("balanceOf(address)", [alice], alice, storage)
allowance = invoke("allowance(address,address)", [alice, spender], alice, storage)
assert balance["result"] == word(45)
assert allowance["result"] == word(15)

rejected = invoke("transferFrom(address,address,uint256)", [alice, bob, 20], spender, storage)
assert rejected["calls"][0]["status"] == 1 and rejected["storage"] == storage

print("stylus-token-evm-interop: standard cast ABI/direct Wasm parity ok")
PY

#!/usr/bin/env python3
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "Tests/fixtures/stylus/abi-vectors.json"

data = json.loads(FIXTURE.read_text())
for name in ("initialize", "increment", "get"):
    observed = subprocess.check_output(["cast", "sig", f"{name}()"], text=True).strip()
    assert observed == "0x" + data["counter"][name], (name, observed)

assert len(bytes.fromhex(data["canonicalWords"]["u256Max"])) == 32
assert set(data["scheduledTypes"]) == {
    "tuple", "fixedArray", "dynamicBytes", "string", "dynamicArray"
}
assert {"dynamicOffsetOverflow", "dynamicTailTruncated", "overlappingTail"} <= set(data["malformed"])
print("stylus-abi-vectors: ok (Foundry cast / Alloy ABI selectors)")

#!/usr/bin/env python3
import json
import re
import subprocess
from pathlib import Path


manifest = "build/stylus/remote-call/rust/Cargo.toml"
metadata = json.loads(subprocess.check_output([
    "cargo", "metadata", "--format-version", "1", "--manifest-path", manifest,
]))
sdk = next(
    package for package in metadata["packages"]
    if package["name"] == "stylus-sdk" and package["version"] == "0.10.8"
)
hostio = Path(sdk["manifest_path"]).parent / "src" / "hostio.rs"
source = hostio.read_text()

expected = {
    "call_contract": (
        "contract: *const u8", "calldata: *const u8", "calldata_len: usize",
        "value: *const u8", "gas: u64", "return_data_len: *mut usize",
    ),
    "static_call_contract": (
        "contract: *const u8", "calldata: *const u8", "calldata_len: usize",
        "gas: u64", "return_data_len: *mut usize",
    ),
    "delegate_call_contract": (
        "contract: *const u8", "calldata: *const u8", "calldata_len: usize",
        "gas: u64", "return_data_len: *mut usize",
    ),
    "read_return_data": ("dest: *mut u8", "offset: usize", "size: usize"),
    "return_data_size": (),
}
returns = {
    "call_contract": "u8",
    "static_call_contract": "u8",
    "delegate_call_contract": "u8",
    "read_return_data": "usize",
    "return_data_size": "usize",
}

for name, parameters in expected.items():
    match = re.search(
        rf"pub fn {name}\s*\((.*?)\)\s*(?:->\s*([^;]+))?;",
        source,
        flags=re.DOTALL,
    )
    assert match, f"stylus-sdk 0.10.8 is missing hostio::{name}"
    actual_parameters = tuple(
        part.strip() for part in re.sub(r"\s+", " ", match.group(1)).split(",")
        if part.strip()
    )
    actual_return = (match.group(2) or "()").strip()
    assert actual_parameters == parameters, (
        f"hostio::{name} parameters drifted: {actual_parameters!r}"
    )
    assert actual_return == returns[name], (
        f"hostio::{name} return drifted: {actual_return!r}"
    )

print(f"stylus-remote-hostio-audit: ok ({hostio})")

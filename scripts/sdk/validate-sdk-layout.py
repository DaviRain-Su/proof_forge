#!/usr/bin/env python3
import argparse
import json
import pathlib
import sys


REQUIRED_BY_TARGET = {
    "evm": [
        "proof-forge-sdk.json",
        "proof-forge-client.ts",
        "proof-forge-artifact.json",
        "Counter.bin",
        "Counter.init.bin",
        "Counter.yul",
        "proof-forge-deploy.json",
    ],
    "solana-sbpf-asm": [
        "proof-forge-sdk.json",
        "proof-forge-client.ts",
        "proof-forge-artifact.json",
        "Counter.s",
        "manifest.toml",
        "proof-forge-idl.json",
    ],
    "wasm-near": [
        "proof-forge-sdk.json",
        "proof-forge-client.ts",
        "proof-forge-artifact.json",
        "counter.wat",
        "proof-forge-deploy.json",
    ],
    "move-sui": [
        "proof-forge-sdk.json",
        "proof-forge-client.ts",
        "proof-forge-artifact.json",
        "Move.toml",
        "sources/counter.move",
        "tests/counter_tests.move",
    ],
}


def fail(message: str) -> None:
    print(f"sdk-layout: error: {message}", file=sys.stderr)
    raise SystemExit(1)


def validate_target(root: pathlib.Path, target: str) -> None:
    target_dir = root / target
    if not target_dir.is_dir():
        fail(f"{target_dir}: target SDK directory is missing")
    for rel in REQUIRED_BY_TARGET[target]:
        path = target_dir / rel
        if not path.exists():
            fail(f"{target_dir}: required file is missing: {rel}")
        if path.is_file() and path.stat().st_size == 0:
            fail(f"{target_dir}: required file is empty: {rel}")
    schema = json.loads((target_dir / "proof-forge-sdk.json").read_text())
    if schema.get("target") != target:
        fail(f"{target_dir}: proof-forge-sdk.json target mismatch")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=pathlib.Path)
    args = parser.parse_args()

    for target in REQUIRED_BY_TARGET:
        validate_target(args.root, target)

    print("sdk-layout: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

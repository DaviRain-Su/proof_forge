#!/usr/bin/env python3
import argparse
import json
import pathlib
import sys

ROOT_FIELDS = [
    "schema",
    "schemaVersion",
    "contract",
    "target",
    "irVersion",
    "state",
    "types",
    "entrypoints",
    "errors",
    "events",
    "capabilities",
    "artifacts",
    "clients",
    "extensions",
]

EXTENSION_KEYS = {
    "evm": "evm",
    "solana-sbpf-asm": "solana",
    "wasm-near": "near",
    "move-sui": "sui",
}


def fail(message: str) -> None:
    print(f"sdk-schema-validate: error: {message}", file=sys.stderr)
    raise SystemExit(1)


def validate(path: pathlib.Path, args: argparse.Namespace) -> None:
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        fail(f"{path}: invalid JSON: {exc}")

    missing = [field for field in ROOT_FIELDS if field not in data]
    if missing:
        fail(f"{path}: missing root fields: {', '.join(missing)}")

    extra = [field for field in data.keys() if field not in ROOT_FIELDS]
    if extra:
        fail(f"{path}: unexpected target-specific or unknown root fields: {', '.join(extra)}")

    if args.expect_schema is not None and data["schema"] != args.expect_schema:
        fail(f"{path}: schema {data['schema']!r} != {args.expect_schema!r}")
    if not isinstance(data["schemaVersion"], int):
        fail(f"{path}: schemaVersion must be numeric")
    if args.expect_ir is not None and data["irVersion"] != args.expect_ir:
        fail(f"{path}: irVersion {data['irVersion']!r} != {args.expect_ir!r}")
    if args.expect_target is not None and data["target"] != args.expect_target:
        fail(f"{path}: target {data['target']!r} != {args.expect_target!r}")

    target = data["target"]
    expected_extension = EXTENSION_KEYS.get(target, target)
    extensions = data["extensions"]
    if not isinstance(extensions, dict):
        fail(f"{path}: extensions must be an object")
    populated = [key for key, value in extensions.items() if value not in ({}, None)]
    if populated != [expected_extension]:
        fail(
            f"{path}: expected exactly one populated extension block "
            f"{expected_extension!r}, got {populated!r}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("schemas", nargs="+", type=pathlib.Path)
    parser.add_argument("--expect-schema")
    parser.add_argument("--expect-ir")
    parser.add_argument("--expect-target")
    args = parser.parse_args()

    for schema in args.schemas:
        if not schema.exists():
            fail(f"{schema}: file does not exist")
        validate(schema, args)

    print("sdk-schema-validate: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

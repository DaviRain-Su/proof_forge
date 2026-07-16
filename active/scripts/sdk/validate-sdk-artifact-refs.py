#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import sys
import tempfile


def fail(message: str) -> None:
    print(f"sdk-artifact-refs: error: {message}", file=sys.stderr)
    raise SystemExit(1)


def iter_refs(section: object, prefix: str):
    if not isinstance(section, dict):
        fail(f"{prefix}: section must be an object")
    for name, value in section.items():
        label = f"{prefix}.{name}"
        if not isinstance(value, dict):
            fail(f"{label}: reference must be an object")
        yield label, value


def validate_ref(schema_path: pathlib.Path, label: str, ref: dict, args: argparse.Namespace) -> None:
    rel = ref.get("path")
    if not isinstance(rel, str) or not rel:
        fail(f"{schema_path}: {label}.path must be a non-empty string")
    if args.reject_absolute and os.path.isabs(rel):
        fail(f"{schema_path}: {label}.path must be relative, got {rel}")
    if args.require_relative and (os.path.isabs(rel) or ".." in pathlib.PurePosixPath(rel).parts):
        fail(f"{schema_path}: {label}.path is not relocatable: {rel}")

    target = schema_path.parent / rel
    if not target.exists():
        fail(f"{schema_path}: {label}.path does not exist relative to schema: {rel}")
    data = target.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if ref.get("sha256") != digest:
        fail(f"{schema_path}: {label}.sha256 mismatch for {rel}")
    if ref.get("bytes") != len(data):
        fail(f"{schema_path}: {label}.bytes mismatch for {rel}")


def validate_schema(schema_path: pathlib.Path, args: argparse.Namespace) -> None:
    try:
        data = json.loads(schema_path.read_text())
    except Exception as exc:
        fail(f"{schema_path}: invalid JSON: {exc}")
    for label, ref in iter_refs(data.get("artifacts"), "artifacts"):
        validate_ref(schema_path, label, ref, args)
    for label, ref in iter_refs(data.get("clients"), "clients"):
        validate_ref(schema_path, label, ref, args)


def relocation_smoke(schema_path: pathlib.Path, args: argparse.Namespace) -> None:
    with tempfile.TemporaryDirectory(prefix="proof-forge-sdk-relocate-") as tmp:
        dest = pathlib.Path(tmp) / schema_path.parent.name
        shutil.copytree(schema_path.parent, dest)
        validate_schema(dest / schema_path.name, args)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-relative", action="store_true")
    parser.add_argument("--reject-absolute", action="store_true")
    parser.add_argument("schemas", nargs="+", type=pathlib.Path)
    args = parser.parse_args()

    for schema in args.schemas:
        if not schema.exists():
            fail(f"{schema}: file does not exist")
        validate_schema(schema, args)
        if args.require_relative:
            relocation_smoke(schema, args)

    print("sdk-artifact-refs: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

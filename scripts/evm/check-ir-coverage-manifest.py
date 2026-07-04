#!/usr/bin/env python3
"""Validate that the EVM IR coverage manifest tracks all portable IR variants."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ALLOWED_INDUCTIVES = {
    "ValueType",
    "StateKind",
    "Literal",
    "ContextField",
    "AssignOp",
    "Expr",
    "Effect",
    "StoragePathSegment",
    "Statement",
    "EntrypointKind",
}

ALLOWED_STATUSES = {
    "lowered",
    "validated",
    "unsupported",
    "structural",
}

INDUCTIVE_RE = re.compile(r"^\s*inductive\s+([A-Za-z_][A-Za-z0-9_]*)\s+where\b")
CONSTRUCTOR_RE = re.compile(r"^\s*\|\s*\.?([A-Za-z_][A-Za-z0-9_]*)\b")
DERIVING_RE = re.compile(r"^\s*deriving\b")


def read_ir_constructors(path: Path) -> set[tuple[str, str]]:
    constructors: set[tuple[str, str]] = set()
    current: str | None = None

    for line_no, line in enumerate(path.read_text().splitlines(), start=1):
        inductive_match = INDUCTIVE_RE.match(line)
        if inductive_match:
            name = inductive_match.group(1)
            current = name if name in ALLOWED_INDUCTIVES else None
            continue

        if current is None:
            continue

        if DERIVING_RE.match(line):
            current = None
            continue

        constructor_match = CONSTRUCTOR_RE.match(line)
        if constructor_match:
            constructors.add((current, constructor_match.group(1)))
        elif line.strip().startswith("|"):
            raise SystemExit(
                f"evm-ir-coverage: could not parse constructor at {path}:{line_no}: {line}"
            )

    return constructors


def read_manifest(path: Path) -> tuple[set[tuple[str, str]], list[str]]:
    entries: set[tuple[str, str]] = set()
    errors: list[str] = []

    for line_no, line in enumerate(path.read_text().splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        fields = line.split("\t")
        if len(fields) != 4:
            errors.append(
                f"{path}:{line_no}: expected 4 tab-separated fields: inductive, constructor, status, evidence"
            )
            continue

        inductive, constructor, status, evidence = fields
        key = (inductive, constructor)

        if inductive not in ALLOWED_INDUCTIVES:
            errors.append(f"{path}:{line_no}: unknown inductive `{inductive}`")
        if status not in ALLOWED_STATUSES:
            errors.append(f"{path}:{line_no}: unsupported status `{status}`")
        if not evidence.strip():
            errors.append(f"{path}:{line_no}: evidence must not be empty")
        if key in entries:
            errors.append(f"{path}:{line_no}: duplicate entry for {inductive}.{constructor}")

        entries.add(key)

    return entries, errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ir", default="ProofForge/IR/Contract.lean")
    parser.add_argument("--manifest", default="Tests/EvmCoverage.tsv")
    args = parser.parse_args()

    ir_path = Path(args.ir)
    manifest_path = Path(args.manifest)
    actual = read_ir_constructors(ir_path)
    manifest, errors = read_manifest(manifest_path)

    missing = sorted(actual - manifest)
    stale = sorted(manifest - actual)

    for inductive, constructor in missing:
        errors.append(f"{manifest_path}: missing entry for {inductive}.{constructor}")
    for inductive, constructor in stale:
        errors.append(f"{manifest_path}: stale entry for unknown constructor {inductive}.{constructor}")

    if errors:
        for error in errors:
            print(f"evm-ir-coverage: {error}", file=sys.stderr)
        return 1

    print(f"evm-ir-coverage: {len(manifest)} constructor entries match {ir_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

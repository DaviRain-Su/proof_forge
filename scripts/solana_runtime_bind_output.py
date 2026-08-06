#!/usr/bin/env python3
"""Bind one Solana Mollusk input tree to proof-forge.output.v1.

This is an independent engineering validator, not the product authority. The
runtime script first runs `proof-forge-next inspect --output-dir`; this helper
then reuses the repository's existing exact-closure validator and pins the four
Solana ELF-profile leaves that Mollusk is allowed to consume.
"""

from __future__ import annotations

import json
import os
import stat
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from validate_artifacts import (  # noqa: E402
    artifact_paths_from_manifest,
    exact_physical_closure,
    validate_engineering_output_manifest,
    verify_descriptor_contents,
    verify_evidence_sha256,
)

# ADR-0032 U1 sole rail (plan/elf shims removed).
_EXPECTED_PROFILE = "solana-sbpf-cpi-elf-v1"
_EXPECTED_LEAVES = {
    ".cpi-plan.json": "materialized-base",
    ".cpi-ir.json": "materialized-base",
    ".idl.json": "materialized-base",
    ".s": "materialized-base",
    ".cpi-bindings.json": "materialized-base",
    ".so": "finalized-extra",
}


def _fail(message: str) -> None:
    raise SystemExit(f"solana-runtime-bind: {message}")


def _reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    out: dict = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key {key!r}")
        out[key] = value
    return out


def _read_manifest(root: Path, *, label: str) -> dict:
    path = root / "manifest.json"
    try:
        metadata = os.lstat(path)
    except FileNotFoundError as exc:
        _fail(f"{label}: missing manifest.json")
        raise AssertionError("unreachable") from exc
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        _fail(f"{label}: manifest.json must be a regular non-symlink file")
    if metadata.st_nlink != 1:
        _fail(f"{label}: manifest.json must be a single-link file")
    try:
        text = path.read_bytes().decode("utf-8", errors="strict")
        value = json.loads(text, object_pairs_hook=_reject_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        _fail(f"{label}: invalid manifest.json: {exc}")
    if not isinstance(value, dict):
        _fail(f"{label}: manifest root must be an object")
    return value


def bind_output(root: Path, program_name: str) -> dict:
    """Validate and bind one published Solana ELF output tree.

    Returns the parsed manifest for tests. Any mismatch exits via SystemExit
    before Mollusk or Cargo is invoked by the caller.
    """
    label = f"Solana runtime {program_name}"
    if not program_name or "/" in program_name or "\\" in program_name:
        _fail(f"{label}: invalid artifact program name")
    try:
        root_metadata = os.lstat(root)
    except FileNotFoundError:
        _fail(f"{label}: output directory does not exist: {root}")
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        _fail(f"{label}: output root must be a non-symlink directory")

    manifest = _read_manifest(root, label=label)
    try:
        descriptors = validate_engineering_output_manifest(manifest, label=label)
        paths = artifact_paths_from_manifest(manifest)
    except SystemExit as exc:
        _fail(f"{label}: {exc}")

    if manifest["target"] != "solana":
        _fail(f"{label}: target must be 'solana', got {manifest['target']!r}")
    if manifest["codegenProfile"] != _EXPECTED_PROFILE:
        _fail(
            f"{label}: codegenProfile must be {_EXPECTED_PROFILE!r}, "
            f"got {manifest['codegenProfile']!r}"
        )
    if manifest["artifactProgramName"] != program_name:
        _fail(
            f"{label}: artifactProgramName mismatch: "
            f"{manifest['artifactProgramName']!r}"
        )
    if manifest["deployable"] is not True:
        _fail(f"{label}: ELF runtime input must be deployable=true")

    expected_roles = {
        f"{program_name}{suffix}": role
        for suffix, role in _EXPECTED_LEAVES.items()
    }
    if set(paths) != set(expected_roles) or len(paths) != len(expected_roles):
        _fail(
            f"{label}: files must be exactly {sorted(expected_roles)}, got {paths}"
        )
    by_path = {descriptor["path"]: descriptor for descriptor in descriptors}
    for path, expected_role in expected_roles.items():
        actual_role = by_path[path]["role"]
        if actual_role != expected_role:
            _fail(
                f"{label}: role mismatch for {path!r}: "
                f"{actual_role!r} != {expected_role!r}"
            )

    expected_files = set(paths) | {"manifest.json", "evidence.json"}
    try:
        exact_physical_closure(root, expected_files, label=label)
        verify_descriptor_contents(root, descriptors, label=label)
        verify_evidence_sha256(root, manifest["evidenceSha256"], label=label)
    except SystemExit as exc:
        _fail(f"{label}: {exc}")
    return manifest


def main() -> None:
    if len(sys.argv) != 3:
        _fail("usage: solana_runtime_bind_output.py <output-dir> <program-name>")
    root = Path(sys.argv[1])
    program_name = sys.argv[2]
    bind_output(root, program_name)
    print(f"solana-runtime-bind: {program_name}: ok")


if __name__ == "__main__":
    main()

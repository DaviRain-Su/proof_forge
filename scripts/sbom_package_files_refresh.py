#!/usr/bin/env python3
"""Regenerate supply-chain/lean-package-files.v1.json from the working tree.

The historical schema name is retained, but the package file set includes Lean
and package-owned native C/header sources. The committed pin is consumed by
TST-SBOM-002 (TASK-D0-08): any ProofForgeV2 source add/remove/rename/content
change must be followed by a
deliberate refresh committed alongside the source change, exactly like the
canonical golden re-pins.  Run with:

    /usr/bin/python3 -I -S scripts/sbom_package_files_refresh.py
    /usr/bin/python3 -I -S scripts/sbom_package_files_refresh.py --check
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "supply-chain" / "lean-package-files.v1.json"
SCHEMA = "proof-forge.lean-package-files.v1"


PACKAGE_SOURCE_SUFFIXES = {".lean", ".c", ".h"}


def collect_package_file_records() -> list[dict]:
    """Discover package sources and compute path/bytes/sha256 records.

    Discovery order, sort key, and hash inputs must stay identical between
    refresh and --check so a fresh pin always passes the freshness gate.
    """
    paths = [REPO_ROOT / "ProofForgeV2.lean"]
    paths.extend(
        sorted(
            path
            for path in (REPO_ROOT / "ProofForgeV2").rglob("*")
            if path.suffix in PACKAGE_SOURCE_SUFFIXES
        )
    )
    records = []
    for path in paths:
        data = path.read_bytes()
        records.append(
            {
                "path": str(path.relative_to(REPO_ROOT)),
                "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            }
        )
    records.sort(key=lambda record: record["path"])
    return records


def build_document(records: list[dict]) -> dict:
    return {"schema": SCHEMA, "files": records}


def write_manifest(document: dict) -> None:
    MANIFEST_PATH.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def load_committed_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def _record_index(files: list) -> dict[str, dict]:
    index: dict[str, dict] = {}
    for entry in files:
        if not isinstance(entry, dict):
            continue
        path = entry.get("path")
        if isinstance(path, str):
            index[path] = entry
    return index


def emit_freshness_diff(expected: dict, actual: dict) -> None:
    """Print a stable, path-ordered freshness diff on stderr.

    expected = computed from the working tree
    actual   = committed pin contents
    """
    lines: list[str] = []
    expected_schema = expected.get("schema")
    actual_schema = actual.get("schema")
    if expected_schema != actual_schema:
        lines.append(
            f"schema mismatch: committed={actual_schema!r} expected={expected_schema!r}"
        )

    expected_files = expected.get("files")
    actual_files = actual.get("files")
    if not isinstance(expected_files, list):
        expected_files = []
    if not isinstance(actual_files, list):
        actual_files = []
        if "files" in actual and not isinstance(actual.get("files"), list):
            lines.append("committed files field is not an array")

    expected_by_path = _record_index(expected_files)
    actual_by_path = _record_index(actual_files)

    all_paths = sorted(set(expected_by_path) | set(actual_by_path))
    for path in all_paths:
        exp = expected_by_path.get(path)
        act = actual_by_path.get(path)
        if exp is None:
            lines.append(f"extra: {path} (bytes={act.get('bytes')!r} sha256={act.get('sha256')!r})")
            continue
        if act is None:
            lines.append(
                f"missing: {path} (bytes={exp.get('bytes')!r} sha256={exp.get('sha256')!r})"
            )
            continue
        exp_bytes = exp.get("bytes")
        act_bytes = act.get("bytes")
        exp_sha = exp.get("sha256")
        act_sha = act.get("sha256")
        if exp_bytes != act_bytes or exp_sha != act_sha:
            lines.append(
                f"changed: {path} "
                f"bytes {act_bytes!r}->{exp_bytes!r} "
                f"sha256 {act_sha!r}->{exp_sha!r}"
            )

    # Order-only drift: same multiset of records but different sequence.
    if not lines and expected_files != actual_files:
        lines.append(
            "files order mismatch: committed files list order differs from "
            "canonical path order"
        )

    if not lines:
        lines.append("committed pin differs from working tree (unclassified)")

    sys.stderr.write(
        "lean-package-files pin is stale; run `just sbom-package-files-refresh`\n"
    )
    for line in lines:
        sys.stderr.write(f"  {line}\n")


def check_manifest() -> int:
    """Compute the live record set and compare to the committed pin.

    Never writes. Exit 0 iff schema + files list are exactly identical
    (including order); exit 1 with a path-ordered stderr diff otherwise.
    """
    computed = build_document(collect_package_file_records())
    try:
        committed = load_committed_manifest()
    except FileNotFoundError:
        sys.stderr.write(
            f"lean-package-files pin missing: {MANIFEST_PATH.relative_to(REPO_ROOT)}\n"
        )
        return 1
    except json.JSONDecodeError as exc:
        sys.stderr.write(
            f"lean-package-files pin is not valid JSON: {exc}\n"
        )
        return 1

    if committed == computed:
        print(f"lean-package-files pin is fresh: {len(computed['files'])} files")
        return 0

    emit_freshness_diff(expected=computed, actual=committed)
    return 1


def refresh_manifest() -> int:
    records = collect_package_file_records()
    document = build_document(records)
    write_manifest(document)
    print(f"lean-package-files manifest refreshed: {len(records)} files")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args == ["--check"]:
        return check_manifest()
    if args:
        sys.stderr.write(
            "usage: sbom_package_files_refresh.py [--check]\n"
        )
        return 2
    return refresh_manifest()


if __name__ == "__main__":
    raise SystemExit(main())

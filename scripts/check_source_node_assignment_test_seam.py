#!/usr/bin/env python3
"""Verify the NodeId candidate seam exists only in the Tests build surface."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile

FORBIDDEN = b"assignNodeIdsV1ForTestWithCandidate"
TEST_MODULE = "Tests/Language/SourceNodeAssignmentCollisionV1.lean"
MANIFEST = "supply-chain/lean-package-files.v1.json"


def fail(detail):
    raise RuntimeError(detail)


def require(condition, detail):
    if not condition:
        fail(detail)


def load_manifest(root):
    document = json.loads((root / MANIFEST).read_text(encoding="utf-8"))
    paths = [entry.get("path") for entry in document.get("files", [])]
    require(len(paths) == 70, f"expected 70 production files, found {len(paths)}")
    require(len(paths) == len(set(paths)), "production manifest contains duplicate paths")
    return paths


def check_sources(root, paths):
    require(TEST_MODULE not in paths, "test seam module entered the production manifest")
    for relative in paths:
        require(isinstance(relative, str), "production manifest path is not a string")
        payload = (root / relative).read_bytes()
        require(FORBIDDEN not in payload,
                f"test seam symbol leaked into production source {relative}")
    umbrella = (root / "ProofForgeV2.lean").read_bytes()
    require(b"Tests." not in umbrella, "production umbrella imports Tests")
    test_source = (root / TEST_MODULE).read_text(encoding="utf-8")
    require(test_source.count("def assignNodeIdsV1ForTestWithCandidate") == 1,
            "test seam definition is missing or duplicated")


def check_release_probe(root):
    source = (
        "import ProofForgeV2\n"
        "#check Tests.Language.SourceNodeAssignmentCollisionV1."
        "assignNodeIdsV1ForTestWithCandidate\n"
    )
    probe_path = None
    try:
        with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", suffix=".lean",
                prefix=".pa124-release-probe-", dir=root, delete=False) as probe:
            probe.write(source)
            probe_path = Path(probe.name)
        result = subprocess.run(
            ["lake", "env", "lean", probe_path.name], cwd=root,
            capture_output=True, text=True, timeout=120,
        )
        diagnostic = (result.stdout + result.stderr).lower()
        require(result.returncode != 0, "release API probe resolved the test seam")
        require("unknown identifier" in diagnostic or "unknown constant" in diagnostic,
                f"release API probe failed for the wrong reason: {diagnostic.strip()}")
    finally:
        if probe_path is not None:
            probe_path.unlink(missing_ok=True)


def check_release_artifacts(root):
    paths = [
        root / ".lake/build/bin/proof-forge-next",
        root / ".lake/build/lib/lean/ProofForgeV2.olean",
    ]
    for path in paths:
        require(path.is_file(), f"release artifact is missing: {path.relative_to(root)}")
        require(FORBIDDEN not in path.read_bytes(),
                f"test seam symbol leaked into release artifact {path.relative_to(root)}")


def self_check(root):
    paths = load_manifest(root)
    check_sources(root, paths)
    check_release_probe(root)
    check_release_artifacts(root)


def main(argv):
    if argv != ["--self-check"]:
        print("usage: check_source_node_assignment_test_seam.py --self-check", file=sys.stderr)
        return 2
    root = Path(__file__).resolve().parents[1]
    try:
        self_check(root)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"source-node-assignment-test-seam: FAIL: {error}", file=sys.stderr)
        return 1
    print("source-node-assignment-test-seam: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

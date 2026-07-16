#!/usr/bin/env python3
"""Pre-acceptance fail-closed contract for development evidence finalization."""

from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
GATE_EVIDENCE = ROOT / "scripts" / "gate_evidence.py"


def load_gate_evidence() -> object:
    spec = importlib.util.spec_from_file_location(
        "_proof_forge_gate_evidence_finalization_fixture", GATE_EVIDENCE
    )
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load scripts/gate_evidence.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_secure(path: Path, body: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_bytes(body)
    path.chmod(0o400)


def write_formal_bundle(module: object, root: Path) -> None:
    document = module._sample_document(formal=True)
    document["command"]["startedUtc"] = "2026-07-15T00:00:00Z"
    document["command"]["endedUtc"] = "2026-07-15T00:00:00Z"
    document["command"]["durationMs"] = 7
    files = {
        "candidate.tar": b"synthetic candidate archive\n",
        "build/evm/Counter.bin": b"synthetic counter bytecode\n",
        "build/logs/gate.stderr": b"",
        "build/logs/gate.stdout": b"synthetic gate output\n",
    }
    for relative, body in files.items():
        write_secure(root / relative, body)

    claims = document["inputs"] + document["artifacts"] + document["logs"]
    for claim in claims:
        body = files[claim["path"]]
        claim["size"] = len(body)
        claim["sha256"] = hashlib.sha256(body).hexdigest()
    archive = document["repository"]["archive"]
    archive["size"] = len(files["candidate.tar"])
    archive["sha256"] = hashlib.sha256(files["candidate.tar"]).hexdigest()
    document["artifactSetSha256"] = module.artifact_set_sha256(document["artifacts"])
    module.validate_evidence(document)
    write_secure(root / "formal-evidence.json", module.canonical_bytes(document))


def invoke(arguments: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [sys.executable, "-I", "-S", os.fspath(GATE_EVIDENCE), *arguments],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def main() -> int:
    if not sys.flags.isolated or not sys.flags.no_site:
        raise AssertionError("invoke this test with isolated Python using -I -S")
    module = load_gate_evidence()
    with tempfile.TemporaryDirectory(prefix="proof-forge-evfinal-") as temporary:
        temporary_root = Path(temporary)
        bundle_root = temporary_root / "formal-bundle"
        bundle_root.mkdir(mode=0o700)
        write_formal_bundle(module, bundle_root)

        catalog_must_not_be_read = temporary_root / "catalog-must-not-be-read.json"
        output_root_must_not_be_touched = temporary_root / "output-must-not-be-touched"
        output = (
            output_root_must_not_be_touched
            / "finalized-development"
            / "development-alpha"
            / "v2-clean-room-alpha"
            / "EVF-20260715-0001.json"
        )
        result = invoke(
            [
                "finalize-development",
                "--catalog",
                os.fspath(catalog_must_not_be_read),
                "--catalog-sha256",
                "0" * 64,
                "--catalog-digest",
                "0" * 64,
                "--run-binding-sha256",
                "0" * 64,
                "--evidence",
                "formal-evidence.json",
                "--bundle-root",
                os.fspath(bundle_root),
                "--output",
                os.fspath(output),
            ]
        )
        if result.returncode != 2:
            raise AssertionError("formal input did not fail with the stable CLI status")
        if result.stdout:
            raise AssertionError("formal input produced stdout")
        if b"PF-EVIDENCE-FORMAL-UNVERIFIED" not in result.stderr:
            raise AssertionError(
                "formal input was not rejected before catalog/member/output I/O:\n"
                + result.stderr.decode("utf-8", errors="replace")
            )
        if catalog_must_not_be_read.exists():
            raise AssertionError("formal rejection created or replaced the catalog path")
        if output_root_must_not_be_touched.exists():
            raise AssertionError("formal rejection touched its output namespace")
    print("gate evidence formal zero-output self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

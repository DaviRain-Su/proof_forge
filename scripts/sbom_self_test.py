#!/usr/bin/env python3
"""Mutation tests for TASK-D0-05 / TST-SBOM-001 SBOM generation."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "sbom_generate.py"


def run(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-I", "-S", str(GENERATOR), *args],
        cwd=cwd,
        check=False,
        text=True,
        capture_output=True,
    )


def copy_corpus(destination: Path) -> None:
    # Minimal tree required by generator.
    for rel in (
        "docs/supply-chain/license-policy.v1.json",
        "docs/supply-chain/license-inventory.v1.json",
        "LICENSE",
        "licenses/Apache-2.0.txt",
        "licenses/MIT.txt",
        "licenses/GPL-3.0-NOTICE.txt",
        "lean-toolchain",
        "lakefile.lean",
        "lake-manifest.json",
    ):
        source = ROOT / rel
        target = destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def expect_ok(label: str, result: subprocess.CompletedProcess[str]) -> None:
    if result.returncode != 0:
        raise AssertionError(
            f"{label}: expected success, got {result.returncode}\n"
            f"stdout={result.stdout}\nstderr={result.stderr}"
        )


def expect_fail(label: str, result: subprocess.CompletedProcess[str], code: str) -> None:
    if result.returncode == 0:
        raise AssertionError(f"{label}: expected failure")
    if code not in result.stderr:
        raise AssertionError(
            f"{label}: expected {code} in stderr, got:\n{result.stderr}"
        )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="pf-sbom-") as temporary:
        base = Path(temporary) / "repo"
        base.mkdir()
        copy_corpus(base)
        out = base / "build" / "sbom"
        first = run(["--root", str(base), "generate", "--output-dir", str(out)], base)
        expect_ok("generate", first)
        second = run(
            ["--root", str(base), "generate", "--output-dir", str(out / "again")], base)
        expect_ok("regenerate", second)
        bom1 = (out / "bom.cdx.json").read_bytes()
        bom2 = (out / "again" / "bom.cdx.json").read_bytes()
        if bom1 != bom2:
            raise AssertionError("bom is not deterministic across regenerations")
        digests1 = json.loads((out / "sbom-digests.v1.json").read_text(encoding="utf-8"))
        digests2 = json.loads((out / "again" / "sbom-digests.v1.json").read_text(encoding="utf-8"))
        if digests1 != digests2:
            raise AssertionError("digest map is not deterministic")
        verify = run(["--root", str(base), "verify", "--output-dir", str(out)], base)
        expect_ok("verify", verify)

        bom = json.loads(bom1.decode("utf-8"))
        if bom.get("specVersion") != "1.6" or bom.get("bomFormat") != "CycloneDX":
            raise AssertionError("bom is not CycloneDX 1.6")
        if bom.get("version") != 1:
            raise AssertionError("bom version must be 1")
        if "serialNumber" in bom or "timestamp" in bom.get("metadata", {}):
            raise AssertionError("bom must not include timestamp/serialNumber")
        refs = [c["bom-ref"] for c in bom["components"]]
        if refs != sorted(refs):
            raise AssertionError("component bom-ref order must be sorted")

        # Mutation: redistributable GPL denied.
        inventory_path = base / "docs/supply-chain/license-inventory.v1.json"
        inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
        for component in inventory["components"]:
            if component["id"] == "solc-0.8.34":
                component["redistributable"] = True
        inventory_path.write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
        denied = run(
            ["--root", str(base), "generate", "--output-dir", str(out / "deny")], base)
        expect_fail("gpl redistributable", denied, "PF-SBOM-POLICY")

        # Restore solc and mutate license to unknown.
        copy_corpus(base)
        inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
        for component in inventory["components"]:
            if component["id"] == "proof-forge-next":
                component["licenseSpdx"] = "NOASSERTION"
        inventory_path.write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
        unknown = run(
            ["--root", str(base), "generate", "--output-dir", str(out / "unknown")], base)
        expect_fail("noassertion", unknown, "PF-SBOM-LICENSE")

        # Missing license file.
        copy_corpus(base)
        (base / "LICENSE").unlink()
        missing = run(
            ["--root", str(base), "generate", "--output-dir", str(out / "missing")], base)
        expect_fail("missing license file", missing, "PF-SBOM-LICENSE")

        # Tampered license hash.
        copy_corpus(base)
        inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
        for component in inventory["components"]:
            if component["id"] == "proof-forge-next":
                component["licenseFileSha256"] = "0" * 64
        inventory_path.write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
        badhash = run(
            ["--root", str(base), "generate", "--output-dir", str(out / "badhash")], base)
        expect_fail("license hash mismatch", badhash, "PF-SBOM-LICENSE")

    print("sbom-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

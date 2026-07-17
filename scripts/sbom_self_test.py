#!/usr/bin/env python3
"""Mutation tests for TASK-D0-05 / TST-SBOM-001 SBOM generation."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Optional


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "sbom_generate.py"


def run(
    args: list[str],
    cwd: Path,
    timeout_seconds: Optional[float] = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-I", "-S", str(GENERATOR), *args],
        cwd=cwd,
        check=False,
        text=True,
        capture_output=True,
        timeout=timeout_seconds,
    )


def copy_corpus(destination: Path) -> None:
    # Minimal tree required by generator.
    for rel in (
        "docs/supply-chain/license-policy.v1.json",
        "docs/supply-chain/license-inventory.v1.json",
        "LICENSE",
        "licenses/Apache-2.0.txt",
        "licenses/MIT.txt",
        "licenses/GPL-3.0.txt",
        "toolchains.lock.json",
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


def expect_fail_before_hash(
    label: str,
    result: subprocess.CompletedProcess[str],
    code: str,
) -> None:
    expect_fail(label, result, code)
    if "hash mismatch" in result.stderr:
        raise AssertionError(
            f"{label}: licenseFile node/containment must be rejected before hashing, "
            f"got:\n{result.stderr}"
        )


def collect_assertion(
    failures: list[str],
    assertion: Callable[[], None],
) -> None:
    try:
        assertion()
    except AssertionError as error:
        failures.append(str(error))


def duplicate_exact_line(path: Path, line: str) -> None:
    text = path.read_text(encoding="utf-8")
    needle = line + "\n"
    if text.count(needle) != 1:
        raise AssertionError(
            f"duplicate-key fixture anchor must occur exactly once in {path}: {line!r}"
        )
    if line.endswith(","):
        replacement = line + "\n" + line + "\n"
    else:
        replacement = line + ",\n" + line + "\n"
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def duplicate_root_scalar_key(path: Path, key: str) -> None:
    raw = json.loads(path.read_text(encoding="utf-8"))
    value = raw[key]
    encoded = json.dumps(key) + ":" + json.dumps(value, separators=(",", ":"))
    text = path.read_text(encoding="utf-8")
    if text.count(encoded) != 1:
        raise AssertionError(
            f"duplicate-key scalar anchor must occur exactly once in {path}: {key!r}"
        )
    path.write_text(text.replace(encoded, encoded + "," + encoded, 1), encoding="utf-8")


def set_root_license_reference(path: Path, license_file: str, digest: str) -> None:
    inventory = json.loads(path.read_text(encoding="utf-8"))
    roots = [
        component for component in inventory["components"]
        if component["id"] == "proof-forge-next"
    ]
    if len(roots) != 1:
        raise AssertionError("expected exactly one proof-forge-next inventory component")
    roots[0]["licenseFile"] = license_file
    roots[0]["licenseFileSha256"] = digest
    path.write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")


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
        root_ref = "urn:proofforge:component:id:proof-forge-next"
        root_entries = [c for c in bom["components"] if c["bom-ref"] == root_ref]
        if len(root_entries) != 1 or "hashes" in root_entries[0]:
            raise AssertionError("root component must use id bom-ref without hashes")
        if bom["metadata"]["component"]["bom-ref"] != root_ref:
            raise AssertionError("metadata component must reference the root bom-ref")

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

        # Lock closure: locked asset missing from inventory.
        copy_corpus(base)
        inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
        inventory["components"] = [
            c for c in inventory["components"] if c["id"] != "wabt-1.0.41"
        ]
        inventory_path.write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
        missing_asset = run(
            ["--root", str(base), "generate", "--output-dir", str(out / "closure-missing")],
            base)
        expect_fail("lock asset missing from inventory", missing_asset, "PF-SBOM-CLOSURE")

        # Lock closure: asset sha256 drifted from inventory (generate and verify).
        copy_corpus(base)
        lock_path = base / "toolchains.lock.json"
        lock = json.loads(lock_path.read_text(encoding="utf-8"))
        for asset in lock["assets"]:
            if asset["id"] == "wabt-1.0.41-macos-arm64":
                asset["sha256"] = "0" * 64
        lock_path.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
        drifted = run(
            ["--root", str(base), "generate", "--output-dir", str(out / "closure-sha")], base)
        expect_fail("lock asset sha256 mismatch", drifted, "PF-SBOM-CLOSURE")
        drifted_verify = run(
            ["--root", str(base), "verify", "--output-dir", str(out)], base)
        expect_fail("lock asset sha256 mismatch on verify", drifted_verify, "PF-SBOM-CLOSURE")

        # Lock closure: tool license drifted from inventory.
        copy_corpus(base)
        lock = json.loads(lock_path.read_text(encoding="utf-8"))
        for tool in lock["tools"]:
            if tool["id"] == "solc":
                tool["licenseSpdx"] = "GPL-3.0-only"
        lock_path.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
        license_drift = run(
            ["--root", str(base), "generate", "--output-dir", str(out / "closure-license")],
            base)
        expect_fail("lock tool license mismatch", license_drift, "PF-SBOM-CLOSURE")

        # P1 RED: every JSON document consumed by the generator must reject
        # duplicate object keys before schema-specific validation. Duplicate
        # values are identical so a last-wins parser would otherwise accept
        # each mutation without changing its decoded value.
        duplicate_failures: list[str] = []
        duplicate_cases = (
            (
                "policy duplicate root key",
                "docs/supply-chain/license-policy.v1.json",
                '  "schema": "proof-forge.license-policy.v1",',
            ),
            (
                "policy duplicate nested key",
                "docs/supply-chain/license-policy.v1.json",
                '    "notes": "External CLI tools may be inventory-only when '
                'redistributable=false and never copied into product archives."',
            ),
            (
                "inventory duplicate root key",
                "docs/supply-chain/license-inventory.v1.json",
                '  "schema": "proof-forge.license-inventory.v1",',
            ),
            (
                "inventory duplicate component key",
                "docs/supply-chain/license-inventory.v1.json",
                '      "id": "proof-forge-next",',
            ),
            (
                "toolchains lock duplicate root key",
                "toolchains.lock.json",
                '  "schema": "proof-forge.toolchains.v2",',
            ),
            (
                "toolchains lock duplicate asset key",
                "toolchains.lock.json",
                '      "id": "foundry-v0.3.0-darwin-arm64",',
            ),
            (
                "toolchains lock duplicate tool key",
                "toolchains.lock.json",
                '      "id": "anvil",',
            ),
        )
        for index, (label, relative_path, line) in enumerate(duplicate_cases):
            copy_corpus(base)
            duplicate_exact_line(base / relative_path, line)
            duplicate_result = run(
                [
                    "--root", str(base), "generate", "--output-dir",
                    str(out / f"duplicate-{index}"),
                ],
                base,
            )
            collect_assertion(
                duplicate_failures,
                lambda label=label, result=duplicate_result: expect_fail(
                    label, result, "PF-SBOM-JSON"
                ),
            )

        # verify additionally consumes the generated digest map as JSON.
        copy_corpus(base)
        duplicate_digest_out = out / "duplicate-digest-map"
        duplicate_digest_baseline = run(
            [
                "--root", str(base), "generate", "--output-dir",
                str(duplicate_digest_out),
            ],
            base,
        )
        expect_ok("duplicate digest map baseline", duplicate_digest_baseline)
        duplicate_root_scalar_key(
            duplicate_digest_out / "sbom-digests.v1.json", "bomSha256"
        )
        duplicate_digest_result = run(
            [
                "--root", str(base), "verify", "--output-dir",
                str(duplicate_digest_out),
            ],
            base,
        )
        collect_assertion(
            duplicate_failures,
            lambda: expect_fail(
                "digest map duplicate root key",
                duplicate_digest_result,
                "PF-SBOM-JSON",
            ),
        )

        # P1 RED: licenseFile must be a regular, non-symlink file contained by
        # the repository. A deliberately wrong digest makes the ordering
        # observable: both path/node attacks must fail before file hashing.
        direct_base = Path(temporary) / "direct-symlink-repo"
        direct_base.mkdir()
        copy_corpus(direct_base)
        direct_inventory = direct_base / "docs/supply-chain/license-inventory.v1.json"
        direct_target = direct_base / "LICENSE.direct-target"
        shutil.copy2(direct_base / "LICENSE", direct_target)
        (direct_base / "LICENSE").unlink()
        (direct_base / "LICENSE").symlink_to(direct_target.name)
        set_root_license_reference(direct_inventory, "LICENSE", "0" * 64)
        direct_result = run(
            [
                "--root", str(direct_base), "generate", "--output-dir",
                str(direct_base / "build/sbom"),
            ],
            direct_base,
        )
        collect_assertion(
            duplicate_failures,
            lambda: expect_fail_before_hash(
                "direct licenseFile symlink", direct_result, "PF-SBOM-LICENSE"
            ),
        )

        intermediate_base = Path(temporary) / "intermediate-symlink-repo"
        intermediate_base.mkdir()
        copy_corpus(intermediate_base)
        outside = Path(temporary) / "outside-license-files"
        outside.mkdir()
        shutil.copy2(intermediate_base / "LICENSE", outside / "LICENSE")
        (intermediate_base / "license-hop").symlink_to(
            outside, target_is_directory=True
        )
        intermediate_inventory = (
            intermediate_base / "docs/supply-chain/license-inventory.v1.json"
        )
        set_root_license_reference(
            intermediate_inventory, "license-hop/LICENSE", "0" * 64
        )
        intermediate_result = run(
            [
                "--root", str(intermediate_base), "generate", "--output-dir",
                str(intermediate_base / "build/sbom"),
            ],
            intermediate_base,
        )
        collect_assertion(
            duplicate_failures,
            lambda: expect_fail_before_hash(
                "intermediate licenseFile symlink escapes repository",
                intermediate_result,
                "PF-SBOM-LICENSE",
            ),
        )

        # A final special file must not block before the regular-file check.
        fifo_base = Path(temporary) / "fifo-repo"
        fifo_base.mkdir()
        copy_corpus(fifo_base)
        fifo_inventory = fifo_base / "docs/supply-chain/license-inventory.v1.json"
        os.mkfifo(fifo_base / "LICENSE.fifo")
        set_root_license_reference(fifo_inventory, "LICENSE.fifo", "0" * 64)
        try:
            fifo_result = run(
                [
                    "--root", str(fifo_base), "generate", "--output-dir",
                    str(fifo_base / "build/sbom"),
                ],
                fifo_base,
                timeout_seconds=1.0,
            )
        except subprocess.TimeoutExpired:
            duplicate_failures.append(
                "FIFO licenseFile: generator blocked before rejecting special file"
            )
        else:
            collect_assertion(
                duplicate_failures,
                lambda: expect_fail_before_hash(
                    "FIFO licenseFile", fifo_result, "PF-SBOM-LICENSE"
                ),
            )

        # Embedded NUL must be normalized to a stable PF-SBOM diagnostic, not
        # leak an implementation traceback from os.open.
        nul_base = Path(temporary) / "nul-repo"
        nul_base.mkdir()
        copy_corpus(nul_base)
        nul_inventory = nul_base / "docs/supply-chain/license-inventory.v1.json"
        set_root_license_reference(nul_inventory, "LICENSE\x00escape", "0" * 64)
        nul_result = run(
            [
                "--root", str(nul_base), "generate", "--output-dir",
                str(nul_base / "build/sbom"),
            ],
            nul_base,
        )
        collect_assertion(
            duplicate_failures,
            lambda: expect_fail_before_hash(
                "NUL licenseFile", nul_result, "PF-SBOM-LICENSE"
            ),
        )

        # A regular file with multiple hard links does not prove repository
        # containment. It must be rejected before hashing, just like symlinks.
        hardlink_base = Path(temporary) / "hardlink-repo"
        hardlink_base.mkdir()
        copy_corpus(hardlink_base)
        hardlink_outside = Path(temporary) / "outside-hardlink-license"
        shutil.copy2(hardlink_base / "LICENSE", hardlink_outside)
        os.link(hardlink_outside, hardlink_base / "LICENSE.hardlink")
        hardlink_inventory = (
            hardlink_base / "docs/supply-chain/license-inventory.v1.json"
        )
        set_root_license_reference(
            hardlink_inventory, "LICENSE.hardlink", "0" * 64
        )
        hardlink_result = run(
            [
                "--root", str(hardlink_base), "generate", "--output-dir",
                str(hardlink_base / "build/sbom"),
            ],
            hardlink_base,
        )
        collect_assertion(
            duplicate_failures,
            lambda: expect_fail_before_hash(
                "hardlink licenseFile", hardlink_result, "PF-SBOM-LICENSE"
            ),
        )

        if duplicate_failures:
            raise AssertionError(
                "SBOM P1 RED acceptance failures:\n- "
                + "\n- ".join(duplicate_failures)
            )

    print("sbom-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""No-tool tamper tests for Solana runtime artifact binding."""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from solana_runtime_bind_output import bind_output  # noqa: E402

_ZERO = "0" * 64


def _artifact_bytes(name: str) -> dict[str, bytes]:
    return {
        f"{name}.cpi-plan.json": f'{{"programName":"{name}"}}\n'.encode(),
        f"{name}.cpi-ir.json": f'{{"schema":"proof-forge.solana.full-body-hybrid-ir.v1"}}\n'.encode(),
        f"{name}.idl.json": f'{{"name":"{name}"}}\n'.encode(),
        f"{name}.s": f"; asm {name}\n".encode(),
        f"{name}.cpi-bindings.json": f'{{"programName":"{name}"}}\n'.encode(),
        f"{name}.so": b"\x7fELF" + name.encode() + b"\x00",
    }


def _write_fixture(root: Path, name: str) -> None:
    root.mkdir(parents=True, exist_ok=True)
    artifacts = _artifact_bytes(name)
    evidence = f'{{"program":"{name}"}}\n'.encode()
    for path, contents in artifacts.items():
        (root / path).write_bytes(contents)
    (root / "evidence.json").write_bytes(evidence)
    descriptors = []
    for path in sorted(p for p in artifacts if not p.endswith(".so")):
        contents = artifacts[path]
        descriptors.append(
            {
                "role": "materialized-base",
                "path": path,
                "size": len(contents),
                "contentSha256": hashlib.sha256(contents).hexdigest(),
            }
        )
    so_path = f"{name}.so"
    so = artifacts[so_path]
    descriptors.append(
        {
            "role": "finalized-extra",
            "path": so_path,
            "size": len(so),
            "contentSha256": hashlib.sha256(so).hexdigest(),
        }
    )
    manifest = {
        "schemaVersion": "proof-forge.output.v1",
        "target": "solana",
        "codegenProfile": "solana-sbpf-cpi-elf-v1",
        "artifactProgramName": name,
        "sourceHash": _ZERO,
        "semanticHash": "1" * 64,
        "buildIdentityDigest": "2" * 64,
        "planDigest": "3" * 64,
        "supportClaimDigest": "4" * 64,
        "engineeringRegistryRootDigest": "5" * 64,
        "outputSetDigest": "6" * 64,
        "evidenceSha256": hashlib.sha256(evidence).hexdigest(),
        "deployable": True,
        "files": descriptors,
    }
    (root / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def _expect_failure(label: str, needle: str, action) -> None:
    try:
        action()
    except SystemExit as exc:
        message = str(exc)
        if needle not in message:
            raise AssertionError(
                f"{label}: expected {needle!r}, got {message!r}"
            ) from exc
    else:
        raise AssertionError(f"{label}: expected failure")


def _reset(root: Path, name: str) -> None:
    if root.exists():
        shutil.rmtree(root)
    _write_fixture(root, name)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="proof-forge-solana-bind-") as tmp:
        base = Path(tmp)
        demo = base / "demo"
        other = base / "other"
        _write_fixture(demo, "Demo")
        _write_fixture(other, "Other")
        bind_output(demo, "Demo")

        # A valid ELF from another fixture is still the wrong content identity.
        (demo / "Demo.so").write_bytes((other / "Other.so").read_bytes())
        _expect_failure(
            "cross-fixture ELF",
            "mismatch",
            lambda: bind_output(demo, "Demo"),
        )

        _reset(demo, "Demo")
        (demo / "Demo.cpi-plan.json").write_bytes(
            (other / "Other.cpi-plan.json").read_bytes()
        )
        _expect_failure(
            "cross-fixture plan",
            "mismatch",
            lambda: bind_output(demo, "Demo"),
        )

        _reset(demo, "Demo")
        plan = demo / "Demo.cpi-plan.json"
        original = plan.read_bytes()
        plan.write_bytes(b"x" * len(original))
        _expect_failure(
            "same-size plan tamper",
            "contentSha256 mismatch",
            lambda: bind_output(demo, "Demo"),
        )

        _reset(demo, "Demo")
        manifest_path = demo / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        so_descriptor = next(
            item for item in manifest["files"] if item["path"] == "Demo.so"
        )
        so_descriptor["role"] = "materialized-base"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        _expect_failure(
            "wrong ELF role",
            "role mismatch",
            lambda: bind_output(demo, "Demo"),
        )

        _reset(demo, "Demo")
        (demo / "rogue.so").write_bytes(b"rogue")
        _expect_failure(
            "unexpected post-publish leaf",
            "unexpected",
            lambda: bind_output(demo, "Demo"),
        )

        _reset(demo, "Demo")
        _expect_failure(
            "cross-fixture program name",
            "artifactProgramName mismatch",
            lambda: bind_output(demo, "Other"),
        )

    print("solana_runtime_bind_output_self_test: ok")


if __name__ == "__main__":
    main()

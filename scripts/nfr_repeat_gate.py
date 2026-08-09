#!/usr/bin/env python3
"""Engineering same-host repeatability gate for two zero-tool target profiles.

Scope is deliberately narrow: the same built proof-forge-next binary performs
exactly two consecutive product builds of Examples.StateCell for the default
Solana plan profile and the default Noir source profile. Each output is checked
with the independent engineering artifact validator, then manifest.json and
evidence.json must be byte-identical across the two runs.

This is an engineering subset of PRD NFR-001 only. It is not a hermetic,
clean-room, multi-host, full-target, formal TST-*, release, or formal
OutputSetV1 claim.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, TypeVar

_SCRIPT_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _SCRIPT_DIR.parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from validate_artifacts import (  # noqa: E402
    artifact_paths_from_manifest,
    exact_physical_closure,
    validate_engineering_output_manifest,
    verify_descriptor_contents,
    verify_evidence_sha256,
)


_MANIFEST_FIELDS = (
    "schemaVersion",
    "target",
    "codegenProfile",
    "artifactProgramName",
    "sourceHash",
    "semanticHash",
    "buildIdentityDigest",
    "planDigest",
    "supportClaimDigest",
    "engineeringRegistryRootDigest",
    "outputSetDigest",
    "evidenceSha256",
    "deployable",
    "files",
)

_TARGETS = (
    # ADR-0032 U1 P4: sole rail default is cpi-elf (body-only StateCell path).
    ("solana", "solana-sbpf-cpi-elf-v1"),
    ("noir", "noir-source-u64-relations-v1"),
)

_T = TypeVar("_T")


@dataclass(frozen=True)
class OutputObservation:
    manifest: dict
    manifest_bytes: bytes
    evidence_bytes: bytes


def _fail(message: str) -> None:
    raise SystemExit(f"nfr-repeat: {message}")


def _run_validation(
    *, target: str, run_label: str, action: Callable[[], _T]
) -> _T:
    try:
        return action()
    except SystemExit as exc:
        _fail(f"target={target} run={run_label}: {exc}")


def _read_regular_single_link(path: Path, *, target: str, run_label: str) -> bytes:
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        _fail(f"target={target} run={run_label}: missing {path.name}")
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
        _fail(f"target={target} run={run_label}: {path.name} is not a regular file")
    if st.st_nlink != 1:
        _fail(
            f"target={target} run={run_label}: "
            f"{path.name} is not a single-link regular file"
        )
    try:
        return path.read_bytes()
    except OSError as exc:
        _fail(f"target={target} run={run_label}: cannot read {path.name}: {exc}")


def _observe_output(
    root: Path,
    *,
    target: str,
    expected_profile: str,
    run_label: str,
) -> OutputObservation:
    manifest_bytes = _read_regular_single_link(
        root / "manifest.json", target=target, run_label=run_label
    )
    try:
        manifest_text = manifest_bytes.decode("utf-8")
        manifest = json.loads(manifest_text)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        _fail(f"target={target} run={run_label}: invalid manifest.json: {exc}")

    descriptors = _run_validation(
        target=target,
        run_label=run_label,
        action=lambda: validate_engineering_output_manifest(
            manifest, label=f"nfr-repeat-{target}-{run_label}"
        ),
    )
    if manifest["target"] != target:
        _fail(
            f"target={target} run={run_label}: "
            f"manifest target={manifest['target']!r}"
        )
    if manifest["codegenProfile"] != expected_profile:
        _fail(
            f"target={target} run={run_label}: "
            f"profile={manifest['codegenProfile']!r} expected={expected_profile!r}"
        )
    if manifest["artifactProgramName"] != "StateCell":
        _fail(
            f"target={target} run={run_label}: "
            f"artifactProgramName={manifest['artifactProgramName']!r}"
        )

    artifact_paths = _run_validation(
        target=target,
        run_label=run_label,
        action=lambda: artifact_paths_from_manifest(manifest),
    )
    expected_files = set(artifact_paths) | {"manifest.json", "evidence.json"}
    _run_validation(
        target=target,
        run_label=run_label,
        action=lambda: exact_physical_closure(
            root,
            expected_files,
            label=f"nfr-repeat-{target}-{run_label}",
        ),
    )
    _run_validation(
        target=target,
        run_label=run_label,
        action=lambda: verify_descriptor_contents(
            root,
            descriptors,
            label=f"nfr-repeat-{target}-{run_label}",
        ),
    )
    _run_validation(
        target=target,
        run_label=run_label,
        action=lambda: verify_evidence_sha256(
            root,
            manifest["evidenceSha256"],
            label=f"nfr-repeat-{target}-{run_label}",
        ),
    )
    evidence_bytes = _read_regular_single_link(
        root / "evidence.json", target=target, run_label=run_label
    )
    return OutputObservation(
        manifest=manifest,
        manifest_bytes=manifest_bytes,
        evidence_bytes=evidence_bytes,
    )


def compare_repeat_outputs(
    *,
    target: str,
    expected_profile: str,
    run_a: Path,
    run_b: Path,
) -> None:
    """Validate both trees, then require byte-identical engineering sidecars."""
    observed_a = _observe_output(
        run_a,
        target=target,
        expected_profile=expected_profile,
        run_label="a",
    )
    observed_b = _observe_output(
        run_b,
        target=target,
        expected_profile=expected_profile,
        run_label="b",
    )

    if observed_a.manifest_bytes != observed_b.manifest_bytes:
        for field in _MANIFEST_FIELDS:
            if observed_a.manifest.get(field) != observed_b.manifest.get(field):
                _fail(
                    f"target={target} profile={expected_profile} "
                    f"field={field} differs between run-a and run-b"
                )
        _fail(
            f"target={target} profile={expected_profile} "
            "sidecar=manifest.json bytes differ between run-a and run-b"
        )

    if observed_a.evidence_bytes != observed_b.evidence_bytes:
        _fail(
            f"target={target} profile={expected_profile} "
            "sidecar=evidence.json bytes differ between run-a and run-b"
        )


def _build_once(*, target: str, output_dir: Path, run_label: str) -> None:
    output_arg = output_dir.relative_to(_REPO_ROOT).as_posix()
    command = [
        "lake",
        "env",
        ".lake/build/bin/proof-forge-next",
        "build",
        "Examples/StateCell.lean",
        "--module",
        "Examples.StateCell",
        "--target",
        target,
        "-o",
        output_arg,
    ]
    completed = subprocess.run(
        command,
        cwd=_REPO_ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if completed.returncode != 0:
        if completed.stdout:
            sys.stderr.write(completed.stdout)
        if completed.stderr:
            sys.stderr.write(completed.stderr)
        _fail(
            f"target={target} run={run_label}: "
            f"product build exited {completed.returncode}"
        )


def run_gate() -> None:
    cli = _REPO_ROOT / ".lake/build/bin/proof-forge-next"
    if not cli.is_file() or cli.is_symlink():
        _fail("missing built .lake/build/bin/proof-forge-next")

    output_root = _REPO_ROOT / "build/v2/nfr-repeat"
    if output_root.exists() or output_root.is_symlink():
        if output_root.is_symlink() or not output_root.is_dir():
            _fail("build/v2/nfr-repeat exists but is not a real directory")
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True, exist_ok=False)

    for target, expected_profile in _TARGETS:
        run_a = output_root / f"{target}-a"
        run_b = output_root / f"{target}-b"
        _build_once(target=target, output_dir=run_a, run_label="a")
        _build_once(target=target, output_dir=run_b, run_label="b")
        compare_repeat_outputs(
            target=target,
            expected_profile=expected_profile,
            run_a=run_a,
            run_b=run_b,
        )

    print("nfr-repeat: ok (solana×2, noir×2)")


def main() -> None:
    if len(sys.argv) != 1:
        _fail("usage: nfr_repeat_gate.py")
    run_gate()


if __name__ == "__main__":
    main()

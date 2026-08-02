#!/usr/bin/env python3
"""No-tool self-test for the engineering NFR repeat gate."""

from __future__ import annotations

import hashlib
import json
import sys
import tempfile
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from nfr_repeat_gate import compare_repeat_outputs  # noqa: E402


_ZERO = "0" * 64


def _write_fixture(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    artifact = b"deterministic artifact\n"
    artifact_path = "Counter.sbpf-plan"
    evidence = b'{"note":"deterministic"}\n'
    (root / artifact_path).write_bytes(artifact)
    (root / "evidence.json").write_bytes(evidence)
    manifest = {
        "schemaVersion": "proof-forge.output.v1",
        "target": "solana",
        "codegenProfile": "solana-sbpf-plan-v1",
        "artifactProgramName": "Counter",
        "sourceHash": _ZERO,
        "semanticHash": "1" * 64,
        "buildIdentityDigest": "2" * 64,
        "planDigest": "3" * 64,
        "supportClaimDigest": "4" * 64,
        "engineeringRegistryRootDigest": "5" * 64,
        "outputSetDigest": "6" * 64,
        "evidenceSha256": hashlib.sha256(evidence).hexdigest(),
        "deployable": False,
        "files": [
            {
                "role": "materialized-base",
                "path": artifact_path,
                "size": len(artifact),
                "contentSha256": hashlib.sha256(artifact).hexdigest(),
            }
        ],
    }
    rendered = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    (root / "manifest.json").write_text(rendered, encoding="utf-8")


def _expect_failure(label: str, needle: str, action) -> None:
    try:
        action()
    except SystemExit as exc:
        message = str(exc)
        if needle not in message:
            raise AssertionError(
                f"{label}: expected {needle!r} in failure, got {message!r}"
            ) from exc
    else:
        raise AssertionError(f"{label}: expected failure")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="proof-forge-nfr-repeat-") as tmp:
        base = Path(tmp)
        run_a = base / "a"
        run_b = base / "b"
        _write_fixture(run_a)
        _write_fixture(run_b)

        compare_repeat_outputs(
            target="solana",
            expected_profile="solana-sbpf-plan-v1",
            run_a=run_a,
            run_b=run_b,
        )

        (run_b / "Counter.sbpf-plan").write_bytes(b"tampered\n")
        _expect_failure(
            "artifact tamper",
            "size mismatch",
            lambda: compare_repeat_outputs(
                target="solana",
                expected_profile="solana-sbpf-plan-v1",
                run_a=run_a,
                run_b=run_b,
            ),
        )

        _write_fixture(run_b)
        artifact_path = run_b / "Counter.sbpf-plan"
        artifact_path.write_bytes(b"x" * len(artifact_path.read_bytes()))
        _expect_failure(
            "same-size artifact tamper",
            "contentSha256 mismatch",
            lambda: compare_repeat_outputs(
                target="solana",
                expected_profile="solana-sbpf-plan-v1",
                run_a=run_a,
                run_b=run_b,
            ),
        )

        _write_fixture(run_b)
        manifest_path = run_b / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["semanticHash"] = "f" * 64
        manifest_path.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        _expect_failure(
            "manifest field tamper",
            "field=semanticHash",
            lambda: compare_repeat_outputs(
                target="solana",
                expected_profile="solana-sbpf-plan-v1",
                run_a=run_a,
                run_b=run_b,
            ),
        )

        _write_fixture(run_b)
        (run_b / "evidence.json").write_bytes(b'{"note":"changed"}\n')
        _expect_failure(
            "evidence tamper",
            "evidence content digest",
            lambda: compare_repeat_outputs(
                target="solana",
                expected_profile="solana-sbpf-plan-v1",
                run_a=run_a,
                run_b=run_b,
            ),
        )

        _write_fixture(run_b)
        manifest_path = run_b / "manifest.json"
        manifest_path.write_bytes(manifest_path.read_bytes() + b"\n")
        _expect_failure(
            "manifest formatting drift",
            "sidecar=manifest.json",
            lambda: compare_repeat_outputs(
                target="solana",
                expected_profile="solana-sbpf-plan-v1",
                run_a=run_a,
                run_b=run_b,
            ),
        )

    print("nfr_repeat_gate_self_test: ok")


if __name__ == "__main__":
    main()

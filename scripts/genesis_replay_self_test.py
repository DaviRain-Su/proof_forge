#!/usr/bin/env python3
"""Unit tests for the genesis trust-upgrade replay runner (TASK-D0-07 slice S8).

Fast, manifest/report/aggregation level; the full multi-minute real replay
runs through the justfile `genesis-replay` recipe, not in docs-check.  One
real smoke leg (docs_check) proves the runner end to end.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tempfile
from pathlib import Path
from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "genesis_replay.py"
MANIFEST_PATH = REPO_ROOT / "docs" / "governance" / "genesis-replay.v1.json"
CHECKS = 0


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "genesis-replay self-test requires -I"
    assert sys.flags.no_site, "genesis-replay self-test requires -S"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def checked(label: str) -> None:
    global CHECKS
    CHECKS += 1
    print(f"ok: {label}")


def expect_error(module: ModuleType, code: str, label: str, operation) -> None:
    try:
        result = operation()
    except module.GenesisReplayError as error:
        if error.code != code:
            raise AssertionError(f"{label} raised {error.code}: {error.detail}")
        checked(label)
        return
    raise AssertionError(f"{label} must fail with {code}; got {result!r}")


def base_manifest() -> dict:
    return {
        "schema": "proof-forge.genesis-replay-manifest.v1",
        "version": "1.0.0",
        "governance": {"trustUpgrade": "GOV-GENESIS-001 §5", "preCutover": "GOV-PRECUTOVER-001 §4.1"},
        "environment": {"umask": "0022", "tmpdirMode": "0700", "note": "x"},
        "legs": [
            {
                "tstId": "TST-DOC-001",
                "taskId": "TASK-D0-01",
                "closingGate": "synthetic",
                "commands": [["/usr/bin/python3", "-I", "-S", "-c", "pass"]],
                "mappingNotes": [],
            }
        ],
    }


def write_manifest(path: Path, manifest: dict) -> None:
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    module = load_module(MODULE_PATH, "proof_forge_genesis_replay_under_test")

    for name in (
        "run_replay",
        "load_manifest",
        "validate_manifest",
        "build_report",
        "GenesisReplayError",
        "REPORT_SCHEMA",
        "FROZEN_TST_IDS",
        "TASK_OF_TST",
        "main",
    ):
        assert getattr(module, name, None) is not None, f"missing {name}"
    checked("public API surface")

    # The committed manifest validates and covers exactly the frozen set.
    committed = module.load_manifest(MANIFEST_PATH)
    legs = committed["legs"]
    assert tuple(leg["tstId"] for leg in legs) == module.FROZEN_TST_IDS
    host_leg = next(leg for leg in legs if leg["tstId"] == "TST-HOST-001")
    assert host_leg["mappingNotes"], "TST-HOST-001 must carry the darwin-leg mapping note"
    assert any("darwin" in note for note in host_leg["mappingNotes"])
    checked("committed manifest validates with TST-HOST-001 mapping note")

    with tempfile.TemporaryDirectory(prefix="genesis-replay-test-") as temporary:
        root = Path(temporary)

        # Negative: unknown schema.
        bad = base_manifest()
        bad["schema"] = "proof-forge.genesis-replay-manifest.v2"
        expect_error(
            module, "PF-GENESIS-REPLAY-MANIFEST", "unknown manifest schema rejected",
            lambda: module.validate_manifest(bad),
        )
        # Negative: unknown TST id.
        bad = base_manifest()
        bad["legs"][0]["tstId"] = "TST-BOGUS-999"
        expect_error(
            module, "PF-GENESIS-REPLAY-MANIFEST", "unknown TST id rejected",
            lambda: module.validate_manifest(bad),
        )
        # Negative: duplicate leg.
        bad = base_manifest()
        bad["legs"].append(dict(bad["legs"][0]))
        expect_error(
            module, "PF-GENESIS-REPLAY-MANIFEST", "duplicate leg rejected",
            lambda: module.validate_manifest(bad),
        )
        # Negative: empty command list.
        bad = base_manifest()
        bad["legs"][0]["commands"] = []
        expect_error(
            module, "PF-GENESIS-REPLAY-MANIFEST", "leg without commands rejected",
            lambda: module.validate_manifest(bad),
        )
        # Negative: task/TST mismatch.
        bad = base_manifest()
        bad["legs"][0]["taskId"] = "TASK-D0-09"
        expect_error(
            module, "PF-GENESIS-REPLAY-MANIFEST", "taskId/TST ownership mismatch rejected",
            lambda: module.validate_manifest(bad),
        )

        # Report shape + failure aggregation.
        report = module.build_report(
            run_utc="2026-07-19T00:00:00Z",
            host_profile_id="linux-x86_64-mint223-eligible",
            legs=[
                {"tstId": "TST-DOC-001", "taskId": "TASK-D0-01",
                 "commands": [
                     {"command": ["/usr/bin/true"], "exitCode": 0,
                      "logSha256": "ab" * 32, "durationMs": 3, "status": "passed"},
                 ]},
                {"tstId": "TST-ISO-001", "taskId": "TASK-D0-02",
                 "commands": [
                     {"command": ["/usr/bin/false"], "exitCode": 1,
                      "logSha256": "cd" * 32, "durationMs": 5, "status": "failed"},
                 ]},
            ],
        )
        assert report["schema"] == module.REPORT_SCHEMA
        assert report["overallStatus"] == "failed"
        checked("report schema + failure aggregation")

        report_ok = module.build_report(
            run_utc="2026-07-19T00:00:00Z",
            host_profile_id="linux-x86_64-mint223-eligible",
            legs=[
                {"tstId": "TST-DOC-001", "taskId": "TASK-D0-01",
                 "commands": [
                     {"command": ["/usr/bin/true"], "exitCode": 0,
                      "logSha256": "ab" * 32, "durationMs": 3, "status": "passed"},
                 ]},
            ],
        )
        assert report_ok["overallStatus"] == "passed"
        checked("report all-green aggregation")

        # One real smoke leg through the full runner path.
        manifest = base_manifest()
        manifest["legs"][0]["commands"] = [
            ["/usr/bin/python3", "-I", "-S", "scripts/docs_check.py", "--root", "."]
        ]
        manifest_path = root / "manifest.json"
        write_manifest(manifest_path, manifest)
        output_dir = root / "replay-out"
        report = module.run_replay(
            manifest_path=str(manifest_path),
            output_dir=str(output_dir),
            repo_root=str(REPO_ROOT),
        )
        assert report["overallStatus"] == "passed"
        leg = report["legs"][0]
        assert leg["tstId"] == "TST-DOC-001"
        assert leg["commands"][0]["exitCode"] == 0
        assert leg["commands"][0]["status"] == "passed"
        reports = list(output_dir.glob("report-*.json"))
        assert len(reports) == 1
        persisted = json.loads(reports[0].read_bytes().decode("utf-8"))
        assert persisted["schema"] == module.REPORT_SCHEMA
        assert persisted["overallStatus"] == "passed"
        log_files = list((output_dir / "logs").glob("*.log"))
        assert len(log_files) == 1
        expected_log_sha = hashlib.sha256(log_files[0].read_bytes()).hexdigest()
        assert leg["commands"][0]["logSha256"] == expected_log_sha
        checked("real smoke leg (docs_check) through the full runner")

        # Negative: a failing leg flips overallStatus and exits nonzero.
        manifest["legs"][0]["commands"] = [["/usr/bin/python3", "-I", "-S", "-c", "import sys; sys.exit(3)"]]
        write_manifest(manifest_path, manifest)
        output_dir_2 = root / "replay-out-2"
        try:
            module.run_replay(
                manifest_path=str(manifest_path),
                output_dir=str(output_dir_2),
                repo_root=str(REPO_ROOT),
            )
            raise AssertionError("failing leg must fail the run")
        except module.GenesisReplayError as error:
            if error.code != "PF-GENESIS-REPLAY-FAILED":
                raise AssertionError(f"unexpected code {error.code}")
        checked("failing leg flips overallStatus failed + nonzero")

    print(f"genesis-replay-self-test: ok ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

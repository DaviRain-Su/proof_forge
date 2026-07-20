#!/usr/bin/env python3
"""Acceptance tests for the TST-ISO-002 fixture clean-room harness (slice S7).

Drives ``scripts/formal_clean_room.py`` end to end: authoritative Stage-0,
candidate anchor, deny-all bwrap stages, loopback-only Anvil differential,
session containment receipt, and the fixture formal EV + catalog binding.
Checks marked [real] run real bwrap/Anvil (slow, minutes); [pure] checks
are fast gate-function or injected-fault checks.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path
from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "formal_clean_room.py"
SEEDS_BY_KEY_ID = {
    "key-architecture": bytes.fromhex(
        "9d61b19deffd5a60ba844af492ec2cc4"
        "4449c5697b326919703bac031cae7f60"
    ),
    "key-quality": bytes.fromhex(
        "4ccd089b28ff96da9db6c346ec114e0f"
        "5b8a319f35aba624da8cf6ed4fb8a6fb"
    ),
    "key-release": bytes.fromhex(
        "c5aa8df43f9f837bedb7442f31dcb7b1"
        "66d38535076f094b85ce3a2e0b4458f7"
    ),
    "key-security": bytes.fromhex(
        "f5e5767cf153319517630f226876b86c"
        "8160cc583bc013744c6bf255f5cc0ee5"
    ),
    "key-verifier-receipt": bytes.fromhex(
        "833fe62409237b9d62ec77587520911e"
        "9a759cec1d19755b7da901b96dca3d42"
    ),
}
CHECKS = 0


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "formal-clean-room self-test requires -I"
    assert sys.flags.no_site, "formal-clean-room self-test requires -S"
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
    except module.CleanRoomError as error:
        if error.code != code:
            raise AssertionError(f"{label} raised {error.code}: {error.detail}")
        checked(label)
        return
    raise AssertionError(f"{label} must fail with {code}; got {result!r}")


def main() -> int:
    module = load_module(MODULE_PATH, "proof_forge_formal_clean_room_under_test")

    for name in (
        "run_formal_clean_room",
        "CleanRoomReport",
        "CleanRoomError",
        "format_report_lines",
        "main",
    ):
        assert getattr(module, name, None) is not None, f"missing {name}"
    checked("public API surface [pure]")

    with tempfile.TemporaryDirectory(prefix="formal-clean-room-test-") as temporary:
        workspace = Path(temporary).resolve()

        # [pure] Stage-0 gate rejects an ineligible observation.
        expect_error(
            module, "PF-CLEAN-ROOM-STAGE0",
            "ineligible observation rejected [pure]",
            lambda: module.require_eligible_observation(
                json.dumps({"eligibleForHermetic": False}).encode()
            ),
        )
        expect_error(
            module, "PF-CLEAN-ROOM-STAGE0",
            "malformed observation rejected [pure]",
            lambda: module.require_eligible_observation(b"not json"),
        )

        # [real] Full clean-room run into a fresh workspace.
        started = time.monotonic()
        report = module.run_formal_clean_room(
            repo_root=str(REPO_ROOT),
            work_root=str(workspace / "run-a"),
            seeds_by_key_id=SEEDS_BY_KEY_ID,
            run_id="s7-clean-room-run-a",
            nonce="a1" * 32,
        )
        elapsed = time.monotonic() - started
        assert report.eligibleForHermetic is True
        assert report.candidateCommit == module.git_commit(str(REPO_ROOT))
        evidence_path = Path(report.evidencePath)
        assert evidence_path.is_file()
        assert evidence_path.stat().st_mode & 0o777 == 0o400
        assert evidence_path.stat().st_nlink == 1
        containment_path = Path(report.containmentPath)
        assert containment_path.is_file()
        checked(f"full clean-room run produces evidence+containment [real {elapsed:.0f}s]")

        # [real] The fixture EV validates through the evidence core.
        ev_core = module.evidence_core()
        ev_bytes = evidence_path.read_bytes()
        document = ev_core.validate_evidence(ev_core.decode_json(ev_bytes))
        assert document["result"] == "passed"
        assert document["gate"]["qualification"] == "formal"
        assert document["repository"]["commit"] == report.candidateCommit
        assert document["repository"]["archive"]["sha256"] == report.archiveSha256
        policies = document["sandboxPolicies"]
        assert len(policies) == 3
        assert any(policy["network"] == "deny-all" for policy in policies)
        assert any(policy["network"] == "loopback-only" for policy in policies)
        checked("fixture formal EV validates (formal/passed/3 policies) [real]")

        # [real] Containment receipt parses through the formal consumer.
        formal = module.formal_consumer()
        receipt_bytes = containment_path.read_bytes()
        policy_bytes = Path(report.policyPath).read_bytes()
        policy = formal._CONSUMER.parse_bootstrap_authority_policy(policy_bytes)[0]
        containment = formal.parse_session_containment_receipt(
            receipt_bytes, policy
        )
        assert containment.result == "contained"
        assert containment.candidate.commit == report.candidateCommit
        assert len(containment.descendants) >= 1
        checked("session containment receipt parses (contained) [real]")

        # [real] Catalog + approval + required set verify through the consumer.
        consumer = formal._CONSUMER
        consumer.parse_formal_gate_catalog_approval(
            Path(report.catalogApprovalPath).read_bytes(),
            Path(report.catalogPath).read_bytes(),
            Path(report.requiredSetPath).read_bytes(),
            policy_bytes,
        )
        catalog = consumer.decode_canonical_pf_jcs(
            Path(report.catalogPath).read_bytes()
        )
        assert tuple(gate["id"] for gate in catalog["gates"]) == (
            "gate-materialize", "gate-core", "gate-evm-runtime"
        )
        checked("fixture catalog binding verifies (3 gates) [real]")

        # [real] Stage receipts on disk: engine.id, policy path, runtimePort.
        policies_dir = workspace / "run-a" / "policies"
        receipts = sorted(policies_dir.glob("sandbox-*.receipt.json"))
        assert len(receipts) == 3, receipts
        by_stage = {}
        for path in receipts:
            wire = json.loads(path.read_bytes().decode("utf-8"))
            assert wire["engine"]["id"] == "bwrap"
            assert wire["engine"]["observedSha256"] == hashlib.sha256(
                Path("/usr/bin/bwrap").read_bytes()
            ).hexdigest()
            assert wire["policy"]["path"].endswith(".bwrap.json")
            by_stage[wire["stage"]] = wire
            assert path.stat().st_mode & 0o777 == 0o400
        assert by_stage["materialize"]["runtimePort"] is None
        assert by_stage["core"]["runtimePort"] is None
        assert isinstance(by_stage["evm-runtime"]["runtimePort"], int)
        checked("three stage receipts with bwrap engine identity [real]")

        # [real] Report lines carry the exact refs.
        lines = module.format_report_lines(report)
        assert any(line.startswith("stage0: ok ") for line in lines)
        assert any(line.startswith("anchor: ok commit=") for line in lines)
        assert any("evidence:" in line and Path(report.evidencePath).stem in line for line in lines)
        assert lines[-1] == "clean-room: ok"
        checked("typed report lines [real]")

        # [real] State independence: run B completes; run A artifacts unchanged.
        report_b = module.run_formal_clean_room(
            repo_root=str(REPO_ROOT),
            work_root=str(workspace / "run-b"),
            seeds_by_key_id=SEEDS_BY_KEY_ID,
            run_id="s7-clean-room-run-b",
            nonce="b2" * 32,
        )
        assert report_b.candidateCommit == report.candidateCommit
        assert evidence_path.read_bytes() == ev_bytes
        checked("state independence: run B completes, run A intact [real]")

        # [pure] Stale anchor commit is rejected by the anchor gate directly.
        expect_error(
            module, "PF-CLEAN-ROOM-ANCHOR",
            "stale anchor commit mismatch [pure]",
            lambda: module._candidate_anchor(
                str(REPO_ROOT), workspace / "pure-stale", "0" * 40, None
            ),
        )

        # [pure] Archive digest expectation mismatch is rejected by the gate.
        expect_error(
            module, "PF-CLEAN-ROOM-ANCHOR",
            "archive digest expectation mismatch [pure]",
            lambda: module._candidate_anchor(
                str(REPO_ROOT), workspace / "pure-digest", None, "0" * 64
            ),
        )

        # [real] Candidate status drift mid-run is detected and rejected.
        marker = REPO_ROOT / "clean-room-drift-marker.tmp"

        def drift_hook() -> None:
            marker.write_text("drift\n")

        try:
            expect_error(
                module, "PF-CLEAN-ROOM-ANCHOR",
                "candidate status drift mid-run detected [real]",
                lambda: module.run_formal_clean_room(
                    repo_root=str(REPO_ROOT),
                    work_root=str(workspace / "drift"),
                    seeds_by_key_id=SEEDS_BY_KEY_ID,
                    run_id="s7-clean-room-drift",
                    nonce="e5" * 32,
                    mid_run_hook=drift_hook,
                ),
            )
        finally:
            marker.unlink(missing_ok=True)
        assert not marker.exists()

        # [real] Missing external tool fails the gate, never skips to green.
        expect_error(
            module, "PF-CLEAN-ROOM-STAGE",
            "missing external tool fails the gate [real]",
            lambda: module.run_formal_clean_room(
                repo_root=str(REPO_ROOT),
                work_root=str(workspace / "missing-tool"),
                seeds_by_key_id=SEEDS_BY_KEY_ID,
                run_id="s7-clean-room-missing",
                nonce="f6" * 32,
                skip_tools=("anvil",),
            ),
        )

        # [pure] Network denial mapping: refused is not a denial.
        assert module.network_denied_errno(101) is True
        assert module.network_denied_errno(99) is True
        assert module.network_denied_errno(13) is True
        assert module.network_denied_errno(1) is True
        assert module.network_denied_errno(111) is False
        assert module.network_denied_errno(110) is False
        checked("network probe mapping (denial vs refusal) [pure]")

        # [pure] Containment escape observation must not be signable.
        expect_error(
            module, "PF-CLEAN-ROOM-CONTAINMENT",
            "escape probe observation cannot produce a receipt [pure]",
            lambda: module.sign_containment_receipt(
                report=report,
                descendants=report.containmentDescendants,
                escape_probes=({"id": "escape-x", "result": "escaped"},),
                started_at="2026-07-19T00:00:00Z",
                finished_at="2026-07-19T00:01:00Z",
                seeds_by_key_id=SEEDS_BY_KEY_ID,
                output=workspace / "escape-receipt.json",
            ),
        )

    print(f"formal-clean-room-self-test: ok ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

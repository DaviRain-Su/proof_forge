#!/usr/bin/env python3
"""Acceptance tests for the TST-EVIDENCE-002 fixture rehearsal (slice S5).

Drives ``scripts/formal_evidence_acceptance.py``: the positive full-chain
rehearsal (fixture store, catalog authority, signed inputs, formal record +
support binding, typed report), the state-independence proof (two disjoint
runs), and the acceptance-level negative matrix.  All seeds are public RFC
8032 test vectors (fixture namespace, ADR-0018); fixture trees live only in
temp directories.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path
from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parent
ACCEPTANCE_PATH = REPO_ROOT / "bootstrap_acceptance.py"
MODULE_PATH = REPO_ROOT / "formal_evidence_acceptance.py"
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
RUN_A_ID = "s5-acceptance-run-a"
RUN_A_NONCE = "a1" * 32
RUN_B_ID = "s5-acceptance-run-b"
RUN_B_NONCE = "b2" * 32
EV_ALPHA = "EV-20260718-0001"
EV_BETA = "EV-20260718-0002"
RECORD_ID = "EVF-20260719-0001"
FINALIZED_AT = "2026-07-19T00:30:00Z"
OBSERVED_AT = "2026-07-19T00:00:00Z"

CHECKS = 0


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "formal-evidence-acceptance self-test requires -I"
    assert sys.flags.no_site, "formal-evidence-acceptance self-test requires -S"
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


def digest_text(raw: bytes) -> str:
    return "sha256:" + raw.hex()


def run_rehearsal(module: ModuleType, fixture: dict, workspace: Path,
                  name: str, **overrides: object) -> object:
    workdir = workspace / f"{name}-work"
    trusted = workspace / f"{name}-trusted"
    workdir.mkdir()
    trusted.mkdir()
    kwargs = {
        "workdir": str(workdir),
        "trusted_root": str(trusted),
        "run_id": RUN_A_ID,
        "nonce": RUN_A_NONCE,
        "seeds_by_key_id": SEEDS_BY_KEY_ID,
        "record_id": RECORD_ID,
        "finalized_at": FINALIZED_AT,
        "observed_at": OBSERVED_AT,
    }
    kwargs.update(overrides)
    report = module.run_formal_evidence_rehearsal(fixture, **kwargs)
    return report, trusted


def expect_error(operation, code: str, label: str,
                 error_types: tuple, trusted: Path | None = None) -> None:
    try:
        result = operation()
    except error_types as error:
        if getattr(error, "code", None) != code:
            raise AssertionError(f"{label} raised {error.code}: {error}")
        if trusted is not None:
            leftovers = [p for p in trusted.rglob("*") if p.is_file()]
            if leftovers:
                raise AssertionError(f"{label} left outputs: {leftovers}")
        checked(label)
        return
    raise AssertionError(f"{label} must fail with {code}; got {result!r}")


def main() -> int:
    acceptance = load_module(
        ACCEPTANCE_PATH, "proof_forge_bootstrap_acceptance_for_s5_test"
    )
    module = load_module(
        MODULE_PATH, "proof_forge_formal_evidence_acceptance_under_test"
    )
    store = module._ACCEPTANCE._STORE

    for name in (
        "run_formal_evidence_rehearsal",
        "build_rehearsal_fixture",
        "start_fixture_store",
        "FormalEvidenceRehearsalReport",
        "FormalEvidenceAcceptanceError",
        "PRODUCTION_POLICY_ID",
        "PRODUCTION_NAMESPACE_ID",
        "main",
    ):
        assert getattr(module, name, None) is not None, f"missing {name}"
    checked("public API surface")

    with tempfile.TemporaryDirectory(prefix="pf-feat-", dir="/tmp") as temporary:
        workspace = Path(temporary)
        fixture = module.build_rehearsal_fixture(
            workspace / "fixture",
            seeds_by_key_id=SEEDS_BY_KEY_ID,
            run_id=RUN_A_ID,
            nonce=RUN_A_NONCE,
        )
        base = fixture["base"]

        # Positive: full rehearsal with typed report and exact store head.
        report, trusted = run_rehearsal(module, fixture, workspace, "positive")
        assert report.recordId == RECORD_ID
        assert report.storeHeadSequence == 2
        assert report.publishedObjects == 2
        assert report.evidenceCount == 2
        record_path = Path(report.recordPath)
        assert record_path.is_file()
        assert record_path.read_bytes() != b""
        assert Path(report.bindingPath).is_file()
        checked("positive rehearsal: record+binding published, store head 2")

        # Positive: report digests recompute from the published bytes.
        record_bytes = record_path.read_bytes()
        assert report.recordDigestHex == hashlib.sha256(
            b"pf.formal-evidence-finalization.v1\x00" + record_bytes
        ).hexdigest()
        binding_bytes = Path(report.bindingPath).read_bytes()
        assert report.bindingDigestHex == hashlib.sha256(
            b"pf.support-evidence-binding.v1\x00" + binding_bytes
        ).hexdigest()
        checked("positive: report digests recompute from published bytes")

        # Positive: the printed report lines carry the exact refs.
        lines = module.format_report_lines(report)
        assert any(line.startswith("record: EVF-20260719-0001 sha256:") for line in lines)
        assert any(line.startswith("binding: EV-20260718-0001 sha256:") for line in lines)
        assert lines[-1] == "rehearsal: ok"
        checked("positive: typed report lines")

        # Positive: main() returns 0 and prints the report.
        rc = module.main([])
        assert rc == 0
        checked("module main() returns 0")

        # State independence: run B completes with run A's artifacts intact.
        report_b, trusted_b = run_rehearsal(
            module, fixture, workspace, "run-b",
            run_id=RUN_B_ID, nonce=RUN_B_NONCE,
        )
        assert report_b.storeHeadSequence == 2
        assert record_path.read_bytes() == record_bytes
        assert Path(report.bindingPath).read_bytes() == binding_bytes
        checked("state independence: run B completes, run A artifacts intact")

        # Negative: store publish conflict on a duplicate required-set key.
        server, handle = module.start_fixture_store(
            fixture, RUN_A_ID, RUN_A_NONCE,
            str(workspace / "conflict.sock"),
        )
        client = store.AuthorityStoreClient(
            base.descriptorRef, RUN_A_ID, RUN_A_NONCE, io_timeout_seconds=30.0
        )
        client.connect(str(workspace / "conflict.sock"))
        try:
            client.publish_with_readback(
                store.REQUIRED_TEST_SET_SCHEMA, base.requiredBytes
            )
            expect_error(
                lambda: client.publish_with_readback(
                    store.REQUIRED_TEST_SET_SCHEMA, base.requiredBytes
                ),
                "PF-AUTH-STORE-CONFLICT",
                "duplicate required-set publish conflicts",
                (store.AuthorityStoreError,),
            )
        finally:
            client.close()
            handle.stop()

        # Negative: missing catalog approval lookup reports not-found.
        server, handle = module.start_fixture_store(
            fixture, RUN_A_ID, RUN_A_NONCE,
            str(workspace / "missing-approval.sock"),
        )
        client = store.AuthorityStoreClient(
            base.descriptorRef, RUN_A_ID, RUN_A_NONCE, io_timeout_seconds=30.0
        )
        client.connect(str(workspace / "missing-approval.sock"))
        try:
            key = store.derive_lookup_key(
                store.FORMAL_CATALOG_APPROVAL_SCHEMA,
                fixture["catalogApprovalBytes"],
            )
            response = client.lookup(
                store.FORMAL_CATALOG_APPROVAL_SCHEMA, key
            )
            if response.result != "not-found":
                raise AssertionError(
                    f"missing catalog approval must be not-found, got {response.result}"
                )
            checked("missing catalog approval in store is not-found")
        finally:
            client.close()
            handle.stop()

        # Negative: wrong runId on the client hello is rejected.
        server, handle = module.start_fixture_store(
            fixture, RUN_A_ID, RUN_A_NONCE,
            str(workspace / "wrong-run.sock"),
        )
        expect_error(
            lambda: store.AuthorityStoreClient(
                base.descriptorRef, RUN_B_ID, RUN_A_NONCE,
                io_timeout_seconds=2.0,
            ).connect(str(workspace / "wrong-run.sock")),
            "PF-AUTH-STORE-AUTHORITY",
            "wrong runId hello rejected",
            (store.AuthorityStoreError,),
        )
        handle.stop()

        # Negative: catalog approval signed under the wrong rule.
        consumer = module._ACCEPTANCE._CONSUMER
        approval_wire = consumer.decode_canonical_pf_jcs(
            fixture["catalogApprovalBytes"]
        )
        statement = {
            key: approval_wire[key] for key in approval_wire if key != "signatures"
        }
        statement_digest = hashlib.sha256(
            b"pf.formal-gate-catalog-approval-statement.v1\x00"
            + consumer.canonical_pf_jcs(statement)
        ).digest()
        producer = module._ACCEPTANCE._PRODUCER
        wrong_approval_wire = dict(statement)
        wrong_approval_wire["signatures"] = [
            {
                "keyId": key_id,
                "algorithm": "ed25519",
                "signature": producer.sign_ed25519(
                    SEEDS_BY_KEY_ID[key_id],
                    b"pf.formal-gate-catalog-approval-signature.v1\x00"
                    + statement_digest,
                ).hex(),
            }
            for key_id in ("key-quality", "key-release")
        ]
        wrong_fixture = dict(fixture)
        wrong_fixture["catalogApprovalBytes"] = consumer.canonical_pf_jcs(
            wrong_approval_wire
        )
        expect_error(
            lambda: run_rehearsal(
                module, wrong_fixture, workspace, "wrong-rule"
            ),
            "PF-EVIDENCE-FORMAL-UNVERIFIED",
            "catalog approval wrong rule signer rejected",
            (module.FormalEvidenceAcceptanceError,),
        )

        # Negative: catalog whose requiredTestSet ref does not match the set.
        mutated_catalog = consumer.decode_canonical_pf_jcs(
            fixture["catalogBytes"]
        )
        mutated_catalog["requiredTestSet"]["id"] = "other-required-set"
        mutated_catalog_bytes = consumer.canonical_pf_jcs(mutated_catalog)
        mutated_ref = consumer.GateCatalogRefV1(
            "proof-forge.gate-catalog.v1",
            mutated_catalog["id"],
            mutated_catalog["version"],
            hashlib.sha256(mutated_catalog_bytes).hexdigest(),
            hashlib.sha256(
                b"pf.gate-catalog.v1\x00" + mutated_catalog_bytes
            ).hexdigest(),
        )
        mutated_approval = module._ACCEPTANCE._PRODUCER.produce_formal_gate_catalog_approval(
            id="s5-acceptance-catalog-approval",
            version="1.0.0",
            authorityPolicy=base.policyRef,
            requiredTestSet=base.requiredRef,
            catalog=mutated_ref,
            signers=(
                ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
                ("key-security", SEEDS_BY_KEY_ID["key-security"]),
            ),
            authority_policy_bytes=base.policyBytes,
        )
        mutated_fixture = dict(fixture)
        mutated_fixture["catalogBytes"] = mutated_catalog_bytes
        mutated_fixture["catalogApprovalBytes"] = mutated_approval
        tree_mutated = workspace / "tree-catalog-mismatch"
        shutil.copytree(fixture["tree"], tree_mutated)
        (tree_mutated / "catalog.json").write_bytes(mutated_catalog_bytes)
        (tree_mutated / "catalog-approval.json").write_bytes(mutated_approval)
        mutated_fixture["tree"] = tree_mutated
        expect_error(
            lambda: run_rehearsal(
                module, mutated_fixture, workspace, "catalog-mismatch"
            ),
            "PF-EVIDENCE-FORMAL-UNVERIFIED",
            "catalog/required-set ref mismatch rejected",
            (module.FormalEvidenceAcceptanceError,),
        )

        # Negative: production namespace leakage via the policy id.
        policy_wire = consumer.decode_canonical_pf_jcs(base.policyBytes)
        policy_wire["id"] = module.PRODUCTION_POLICY_ID
        leaked_policy = consumer.canonical_pf_jcs(policy_wire)
        expect_error(
            lambda: run_rehearsal(
                module, fixture, workspace, "leak",
                policy_bytes=leaked_policy,
            ),
            "PF-FORMAL-EVIDENCE-ACCEPTANCE",
            "production policy id in fixture namespace rejected",
            (module.FormalEvidenceAcceptanceError,),
        )

        # Negative: replay into a no-clobber destination (originals intact).
        expect_error(
            lambda: module.run_formal_evidence_rehearsal(
                fixture,
                workdir=str(workspace / "replay-work"),
                trusted_root=str(trusted),
                run_id=RUN_A_ID,
                nonce=RUN_A_NONCE,
                seeds_by_key_id=SEEDS_BY_KEY_ID,
                record_id=RECORD_ID,
                finalized_at=FINALIZED_AT,
                observed_at=OBSERVED_AT,
            ),
            "PF-EVIDENCE-FORMAL-UNVERIFIED",
            "replay into no-clobber destination rejected",
            (module.FormalEvidenceAcceptanceError,),
        )
        assert record_path.read_bytes() == record_bytes
        checked("replay leaves the original record intact")

        # Negative: tampered published record is rejected by the consumer.
        tampered = bytearray(record_bytes)
        tampered[-40] ^= 0x01
        expect_error(
            lambda: module.verify_published_record(
                bytes(tampered), fixture
            ),
            "PF-EVIDENCE-FORMAL-UNVERIFIED",
            "tampered published record rejected by the consumer",
            (module.FormalEvidenceAcceptanceError,),
        )

        # Negative: mutation-driven harness failures (each with zero output).
        def tree_case(name: str, mutate, label: str) -> None:
            case_dir = workspace / f"case-{name}"
            shutil.copytree(fixture["tree"], case_dir)
            mutate(case_dir)
            case_fixture = dict(fixture)
            case_fixture["tree"] = case_dir
            trusted = workspace / f"trusted-{name}"
            trusted.mkdir()
            expect_error(
                lambda: module.run_formal_evidence_rehearsal(
                    case_fixture,
                    workdir=str(workspace / f"work-{name}"),
                    trusted_root=str(trusted),
                    run_id=RUN_A_ID,
                    nonce=RUN_A_NONCE,
                    seeds_by_key_id=SEEDS_BY_KEY_ID,
                    record_id=RECORD_ID,
                    finalized_at=FINALIZED_AT,
                    observed_at=OBSERVED_AT,
                ),
                "PF-EVIDENCE-FORMAL-UNVERIFIED",
                label,
                (module.FormalEvidenceAcceptanceError,),
                trusted,
            )

        tree_case(
            "revoked-gate-ev",
            lambda tree: (tree / "revocation" / "RVK-20260718-0001.json").write_bytes(
                fixture["makeRevocationRecord"](EV_ALPHA)
            ),
            "revoked EV in gates rejected at harness level",
        )
        tree_case(
            "non-formal-ev",
            lambda tree: (tree / "evidence" / f"{EV_ALPHA}.json").write_bytes(
                fixture["makeEvidence"](
                    ev_id=EV_ALPHA, qualification="development"
                )
            ),
            "non-formal EV rejected",
        )
        tree_case(
            "member-drift",
            lambda tree: (tree / "members" / "out" / "alpha.acir").write_bytes(
                b"drifted"
            ),
            "member bytes drift rejected",
        )
        tree_case(
            "missing-catalog-approval",
            lambda tree: (tree / "catalog-approval.json").unlink(),
            "missing catalog-approval rejected",
        )
        tree_case(
            "required-set-tamper",
            lambda tree: (tree / "required-test-set.json").write_bytes(
                bytes([tree.joinpath("required-test-set.json").read_bytes()[0] ^ 0x01])
                + tree.joinpath("required-test-set.json").read_bytes()[1:]
            ),
            "tampered required set rejected",
        )

        # Negative: freshness window reversal at the rehearsal level.
        trusted = workspace / "trusted-stale"
        trusted.mkdir()
        expect_error(
            lambda: module.run_formal_evidence_rehearsal(
                fixture,
                workdir=str(workspace / "work-stale"),
                trusted_root=str(trusted),
                run_id=RUN_A_ID,
                nonce=RUN_A_NONCE,
                seeds_by_key_id=SEEDS_BY_KEY_ID,
                record_id=RECORD_ID,
                finalized_at="2026-07-19T01:00:00Z",
                observed_at=OBSERVED_AT,
            ),
            "PF-EVIDENCE-FORMAL-UNVERIFIED",
            "freshness stale (finalizedAt >= expiresAt) rejected",
            (module.FormalEvidenceAcceptanceError,),
            trusted,
        )

        # Negative: declared ref digest does not match the EV bytes.
        wrong_inputs = {
            gate: dict(value) for gate, value in fixture["gateInputs"].items()
        }
        wrong_inputs["gate-alpha"]["evidenceRefs"] = [
            {"id": EV_ALPHA, "digest": digest_text(bytes(32))}
        ]
        trusted = workspace / "trusted-digest"
        trusted.mkdir()
        expect_error(
            lambda: module.run_formal_evidence_rehearsal(
                fixture,
                workdir=str(workspace / "work-digest"),
                trusted_root=str(trusted),
                run_id=RUN_A_ID,
                nonce=RUN_A_NONCE,
                seeds_by_key_id=SEEDS_BY_KEY_ID,
                record_id=RECORD_ID,
                finalized_at=FINALIZED_AT,
                observed_at=OBSERVED_AT,
                gate_inputs=wrong_inputs,
            ),
            "PF-EVIDENCE-FORMAL-UNVERIFIED",
            "EV digest mismatch vs declared refs rejected",
            (module.FormalEvidenceAcceptanceError,),
            trusted,
        )

    print(f"formal-evidence-acceptance-self-test: ok ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

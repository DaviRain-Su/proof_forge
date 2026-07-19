#!/usr/bin/env python3
"""Acceptance tests for the formal finalization/support-binding producers.

Reuses the previous slice's complete signed fixture chain (loaded from the
exact sibling self-test file) to exercise record production, consumer
round-trip, spec-frozen publication, and support-binding production with
its negative matrix.  All seeds are public RFC 8032 test vectors; all
publication targets live under temporary trusted roots.
"""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import os
import shutil
import sys
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Callable


REPO_ROOT = Path(__file__).resolve().parent
ACCEPTANCE_PATH = REPO_ROOT / "bootstrap_acceptance.py"
CONSUMER_TEST_PATH = REPO_ROOT / "formal_evidence_self_test.py"
PRODUCER_PATH = REPO_ROOT / "formal_evidence_producer.py"
ACCEPTANCE_MODULE_NAME = "proof_forge_acceptance_for_producer_test"
CONSUMER_TEST_MODULE_NAME = "proof_forge_formal_consumer_test_fixtures"
PRODUCER_MODULE_NAME = "proof_forge_formal_evidence_producer_under_test"
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
D0_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "producer self-test requires -I"
    assert sys.flags.no_site, "producer self-test requires -S"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def digest_text(raw: bytes) -> str:
    return "sha256:" + raw.hex()


def record_inputs(producer: ModuleType, fixture: dict) -> object:
    base = fixture["base"]
    run = fixture["run"]
    snapshot = base.phase5Snapshot
    return producer.FormalRecordInputsV1(
        record_bytes=fixture["recordBytes"],
        authority_policy_bytes=base.policyBytes,
        required_test_set_bytes=base.requiredBytes,
        phase5_snapshot=producer._CONSUMER.BootstrapDocumentSnapshotV1(
            id=snapshot.id, path=snapshot.path, bytes=snapshot.bytes
        ),
        catalog_bytes=fixture["catalogBytes"],
        catalog_approval_bytes=fixture["catalogApprovalBytes"],
        session_containment_bytes=fixture["containmentBytes"],
        freshness_authority_bytes=fixture["freshnessBytes"],
        private_scan_bytes=fixture["scanBytes"],
        revocation_ledger_bytes=fixture["revocationBytes"],
        revocation_record_bytes=fixture["revocationRecordBytes"],
        finalizer_identity_bytes=fixture["finalizerBytes"],
        approval_set_bytes=run.setBytes,
        task_receipt_bytes=tuple(
            run.receiptBytes[task_id] for task_id in D0_TASK_IDS
        ),
        verifier_receipt_bytes=run.activationBytes,
        stage0_handoff_bytes=fixture["handoff"].handoffBytes,
    )


def typed_ref(producer: ModuleType, ref_wire: dict) -> object:
    consumer = producer._CONSUMER
    return consumer.ContentRef(
        ref_wire["schema"],
        ref_wire["id"],
        ref_wire["version"],
        consumer.parse_digest(ref_wire["digest"]),
    )


def typed_gates(producer: ModuleType, gates_wire: list) -> tuple:
    formal = producer._FORMAL
    consumer = producer._CONSUMER
    gates = []
    for gate in gates_wire:
        build = gate["build"]
        gates.append(formal.FormalGateV1(
            gate["id"],
            tuple(gate["testIds"]),
            None if build is None else formal.BuildIdentityV1(
                build["targetId"],
                build["targetSemanticsVersion"],
                consumer.parse_digest(build["targetSemanticsDigest"]),
                build["codegenProfileId"],
                consumer.parse_digest(build["codegenProfileDigest"]),
            ),
            tuple(
                (ref["id"], consumer.parse_digest(ref["digest"]))
                for ref in gate["evidenceRefs"]
            ),
        ))
    return tuple(gates)


def expect_error(
    producer: ModuleType,
    operation: Callable[[], object],
    codes: tuple,
    label: str,
) -> None:
    try:
        result = operation()
    except producer.FormalEvidenceProducerError as error:
        if error.code not in codes:
            raise AssertionError(f"{label} raised {error.code}, expected {codes}")
        return
    raise AssertionError(f"{label} must fail with one of {codes}; got {result!r}")


def assert_public_api(producer: ModuleType) -> None:
    import dataclasses
    import inspect
    for name in (
        "produce_formal_evidence_finalization",
        "publish_finalization",
        "produce_support_binding",
        "publish_support_binding",
    ):
        assert callable(getattr(producer, name, None)), f"missing callable {name}"
    for name in (
        "FormalRecordInputsV1",
        "GateVectorV1",
        "RequirementKeyV1",
        "SupportEvidenceBindingV1",
        "SupportBindingRefV1",
        "FormalEvidenceProducerError",
    ):
        assert isinstance(getattr(producer, name, None), type), f"missing {name}"
    binding_fields = tuple(
        field.name
        for field in dataclasses.fields(producer.SupportEvidenceBindingV1)
    )
    assert binding_fields == (
        "schema",
        "evidence",
        "finalization",
        "candidate",
        "build",
        "requirement",
        "claimDigest",
        "achieved",
        "finalizedAt",
        "expiresAt",
        "revocationLedgerDigest",
    ), "binding dataclass must match the frozen wire"
    ref_fields = tuple(
        field.name for field in dataclasses.fields(producer.SupportBindingRefV1)
    )
    assert ref_fields == (
        "evidence",
        "finalization",
        "requirement",
        "claimDigest",
        "digest",
    ), "binding ref dataclass must match the frozen wire"
    publish_parameters = tuple(
        inspect.signature(producer.publish_finalization).parameters.values()
    )
    assert tuple(parameter.name for parameter in publish_parameters) == (
        "record_bytes",
        "ref",
        "trusted_root",
        "required_test_set_bytes",
        "authority_policy_bytes",
    ), "publish_finalization must take exactly five inputs"


def make_typed_record_args(producer: ModuleType, fixture: dict) -> dict:
    consumer = producer._CONSUMER
    wire = fixture["recordWire"]
    return {
        "identifier": wire["id"],
        "candidate": consumer.parse_candidate_identity(wire["candidate"]),
        "hostProfile": typed_ref(producer, wire["hostProfile"]),
        "stage0Handoff": typed_ref(producer, wire["stage0Handoff"]),
        "sessionContainment": typed_ref(producer, wire["sessionContainment"]),
        "requiredTestSet": typed_ref(producer, wire["requiredTestSet"]),
        "catalog": consumer.GateCatalogRefV1(
            wire["catalog"]["schema"],
            wire["catalog"]["id"],
            wire["catalog"]["version"],
            wire["catalog"]["contentSha256"],
            wire["catalog"]["catalogDigest"],
        ),
        "catalogApproval": typed_ref(producer, wire["catalogApproval"]),
        "gates": typed_gates(producer, wire["gates"]),
        "freshnessAuthority": typed_ref(producer, wire["freshnessAuthority"]),
        "finalizedAt": wire["finalizedAt"],
        "expiresAt": wire["expiresAt"],
        "privateScan": typed_ref(producer, wire["privateScan"]),
        "revocationLedger": typed_ref(producer, wire["revocationLedger"]),
        "finalizer": typed_ref(producer, wire["finalizer"]),
        "bootstrapApproval": producer._FORMAL.BootstrapApprovalBindingV1(
            typed_ref(producer, wire["bootstrapApproval"]["set"]),
            producer._CONSUMER.BootstrapApprovalVerifierReceiptRefV1(
                wire["bootstrapApproval"]["verifierReceipt"]["id"],
                consumer.parse_digest(
                    wire["bootstrapApproval"]["verifierReceipt"]["digest"]
                ),
            ),
        ),
    }


def make_claim() -> dict:
    return {
        "requirement": {
            "id": "noir.acir",
            "version": "1.0.0",
            "digest": digest_text(bytes.fromhex("b1" * 32)),
        },
        "predicates": [
            {
                "variant": "uint-at-least",
                "name": "witness-bounds",
                "value": 4,
            },
        ],
    }


def make_gate_vectors(producer: ModuleType, fixture: dict) -> tuple:
    consumer = producer._CONSUMER
    vectors = []
    for gate in fixture["recordWire"]["gates"]:
        ref = gate["evidenceRefs"][0]
        vectors.append(producer.GateVectorV1(
            gate["id"],
            (ref["id"], consumer.parse_digest(ref["digest"])),
            "local_runtime",
        ))
    return tuple(vectors)


def target_build(producer: ModuleType, target_id: str = "noir") -> object:
    consumer = producer._CONSUMER
    return producer._FORMAL.BuildIdentityV1(
        target_id,
        "1.0.0",
        consumer.Digest("sha256", bytes.fromhex("94" * 32)),
        f"{target_id}-acir" if target_id != "evm" else "evm-yul",
        consumer.Digest("sha256", bytes.fromhex("95" * 32)),
    )


def test_produce_and_publish_record(producer: ModuleType, fixture: dict, tmpdir: Path) -> None:
    inputs = record_inputs(producer, fixture)
    record_bytes, ref = producer.produce_formal_evidence_finalization(
        **make_typed_record_args(producer, fixture),
        inputs=inputs,
    )
    if record_bytes != fixture["recordBytes"]:
        raise AssertionError("produced record must equal the reference bytes")
    expected_digest = hashlib.sha256(
        b"pf.formal-evidence-finalization.v1\x00" + fixture["recordBytes"]
    ).digest()
    if ref.id != "EVF-20260718-0001" or ref.digest.bytes != expected_digest:
        raise AssertionError("FinalizationRef must recompute exactly")
    if ref.schema != "proof-forge.formal-evidence-finalization.v1":
        raise AssertionError("FinalizationRef schema drift")

    consumer = producer._FORMAL
    record, ref2 = consumer.parse_formal_evidence_finalization(
        record_bytes,
        inputs.authority_policy_bytes,
        inputs.required_test_set_bytes,
        inputs.phase5_snapshot,
        inputs.catalog_bytes,
        inputs.catalog_approval_bytes,
        inputs.session_containment_bytes,
        inputs.freshness_authority_bytes,
        inputs.private_scan_bytes,
        inputs.revocation_ledger_bytes,
        inputs.revocation_record_bytes,
        inputs.finalizer_identity_bytes,
        inputs.approval_set_bytes,
        inputs.task_receipt_bytes,
        inputs.verifier_receipt_bytes,
        inputs.stage0_handoff_bytes,
    )
    if ref2 != ref:
        raise AssertionError("consumer round-trip ref must equal producer ref")

    trusted_root = tmpdir / "trusted-root"
    trusted_root.mkdir()
    base = fixture["base"]
    final_path = producer.publish_finalization(
        record_bytes,
        ref,
        str(trusted_root),
        base.requiredBytes,
        base.policyBytes,
    )
    expected_path = trusted_root / (
        "finalized-formal/formal-evidence-catalog/"
        "bootstrap-acceptance-required-tests/EVF-20260718-0001.json"
    )
    if Path(final_path) != expected_path:
        raise AssertionError(f"publish path drift: {final_path}")
    if Path(final_path).read_bytes() != fixture["recordBytes"]:
        raise AssertionError("published record bytes drift")
    if os.stat(final_path).st_mode & 0o777 != 0o444:
        raise AssertionError("published record must be 0444")
    receipt_path = expected_path.with_name("EVF-20260718-0001.receipt.json")
    if not receipt_path.is_file():
        raise AssertionError("receipt-last marker missing")
    receipt_wire = producer._CONSUMER.decode_canonical_pf_jcs(
        receipt_path.read_bytes()
    )
    if receipt_wire != {
        "schema": "proof-forge.formal-evidence-finalization.v1",
        "id": "EVF-20260718-0001",
        "digest": "sha256:" + expected_digest.hex(),
    }:
        raise AssertionError("receipt marker must carry the exact FinalizationRef")
    expect_error(
        producer,
        lambda: producer.publish_finalization(
            record_bytes,
            ref,
            str(trusted_root),
            base.requiredBytes,
            base.policyBytes,
        ),
        ("PF-EVIDENCE-ATOMICITY",),
        "finalization publish no-clobber rerun",
    )
    if Path(final_path).read_bytes() != fixture["recordBytes"]:
        raise AssertionError("no-clobber rerun must not modify the record")

    expect_error(
        producer,
        lambda: producer.publish_finalization(
            record_bytes,
            ref,
            str(tmpdir / "no-such-root"),
            base.requiredBytes,
            base.policyBytes,
        ),
        ("PF-EVIDENCE-IO",),
        "publish into a missing trusted root",
    )


def produce_binding_for(
    producer: ModuleType,
    fixture: dict,
    evidence_ref: tuple,
    build: object,
    claim: dict,
) -> tuple:
    ev_id, _ = evidence_ref
    return producer.produce_support_binding(
        evidence_bytes=fixture["evPayloads"][ev_id],
        evidence_id=ev_id,
        record_inputs=record_inputs(producer, fixture),
        build=build,
        support_claim=claim,
        gate_vectors=make_gate_vectors(producer, fixture),
    )


def test_support_binding(producer: ModuleType, fixture: dict, tmpdir: Path) -> None:
    consumer = producer._CONSUMER
    evidence_ref = fixture["recordWire"]["gates"][0]["evidenceRefs"][0]
    ev_typed = (
        evidence_ref["id"], consumer.parse_digest(evidence_ref["digest"])
    )
    build = target_build(producer, "noir")
    claim = make_claim()
    binding_bytes, ref = produce_binding_for(
        producer, fixture, ev_typed, build, claim
    )
    binding_wire = consumer.decode_canonical_pf_jcs(binding_bytes)
    if binding_wire["schema"] != "proof-forge.support-evidence-binding.v1":
        raise AssertionError("binding schema drift")
    if binding_wire["evidence"] != evidence_ref:
        raise AssertionError("binding evidence ref drift")
    if binding_wire["finalization"] != {
        "schema": "proof-forge.formal-evidence-finalization.v1",
        "id": "EVF-20260718-0001",
        "digest": digest_text(hashlib.sha256(
            b"pf.formal-evidence-finalization.v1\x00" + fixture["recordBytes"]
        ).digest()),
    }:
        raise AssertionError("binding finalization ref drift")
    if binding_wire["candidate"] != fixture["candidateWire"]:
        raise AssertionError("binding candidate must equal the record candidate")
    expected_claim_digest = hashlib.sha256(
        b"pf.support-claim.v1\x00"
        + consumer.canonical_pf_jcs(claim)
    ).hexdigest()
    if binding_wire["claimDigest"] != f"sha256:{expected_claim_digest}":
        raise AssertionError("claimDigest must recompute from the full claim")
    if binding_wire["achieved"] != "local_runtime":
        raise AssertionError("achieved must be the minimum vector grade")
    if binding_wire["finalizedAt"] != "2026-07-18T10:07:00Z":
        raise AssertionError("binding finalizedAt must equal the record's")
    if binding_wire["expiresAt"] != "2026-07-18T12:00:00Z":
        raise AssertionError("binding expiresAt must equal the record's")
    expected_ledger_digest = hashlib.sha256(
        b"pf.revocation-ledger-snapshot.v1\x00" + fixture["revocationBytes"]
    ).hexdigest()
    if binding_wire["revocationLedgerDigest"] != (
        f"sha256:{expected_ledger_digest}"
    ):
        raise AssertionError("revocationLedgerDigest must equal the record's")
    expected_binding_digest = hashlib.sha256(
        b"pf.support-evidence-binding.v1\x00" + binding_bytes
    ).digest()
    if ref.digest.bytes != expected_binding_digest:
        raise AssertionError("SupportBindingRef digest must recompute exactly")

    alt_build = target_build(producer, "evm")
    alt_binding_bytes, alt_ref = produce_binding_for(
        producer, fixture, ev_typed, alt_build, claim
    )
    if alt_binding_bytes == binding_bytes or alt_ref.digest == ref.digest:
        raise AssertionError("a different build must produce a different binding")
    alt_claim = make_claim()
    alt_claim["requirement"] = dict(
        alt_claim["requirement"], version="2.0.0"
    )
    alt_requirement_bytes, alt_requirement_ref = produce_binding_for(
        producer, fixture, ev_typed, build, alt_claim
    )
    if alt_requirement_bytes == binding_bytes:
        raise AssertionError(
            "a different requirement must produce a different binding"
        )
    if alt_requirement_ref.requirement.version != "2.0.0":
        raise AssertionError("requirement version drift")

    trusted_root = tmpdir / "binding-root"
    trusted_root.mkdir()
    final_path = producer.publish_support_binding(
        binding_bytes, ref, str(trusted_root)
    )
    expected_path = trusted_root / (
        "support-bindings/noir.acir/EV-20260718-0001-noir.json"
    )
    if Path(final_path) != expected_path:
        raise AssertionError(f"binding publish path drift: {final_path}")
    if Path(final_path).read_bytes() != binding_bytes:
        raise AssertionError("published binding bytes drift")
    if os.stat(final_path).st_mode & 0o777 != 0o444:
        raise AssertionError("published binding must be 0444")
    receipt_path = expected_path.with_name("EV-20260718-0001-noir.receipt.json")
    if not receipt_path.is_file():
        raise AssertionError("binding receipt-last marker missing")
    receipt_wire = consumer.decode_canonical_pf_jcs(receipt_path.read_bytes())
    if receipt_wire["digest"] != "sha256:" + expected_binding_digest.hex():
        raise AssertionError("binding receipt digest drift")
    if receipt_wire["evidence"] != evidence_ref:
        raise AssertionError("binding receipt evidence drift")
    expect_error(
        producer,
        lambda: producer.publish_support_binding(
            binding_bytes, ref, str(trusted_root)
        ),
        ("PF-EVIDENCE-ATOMICITY",),
        "same EV same build re-publication must be no-clobber",
    )


def test_support_binding_negatives(
    producer: ModuleType, fixture: dict, tmpdir: Path
) -> None:
    consumer = producer._CONSUMER
    formal = producer._FORMAL
    base = fixture["base"]
    evidence_ref = fixture["recordWire"]["gates"][0]["evidenceRefs"][0]
    ev_typed = (
        evidence_ref["id"], consumer.parse_digest(evidence_ref["digest"])
    )
    build = target_build(producer, "noir")
    claim = make_claim()

    # development finalization record.
    dev_record = copy.deepcopy(fixture["recordWire"])
    dev_record["qualification"] = "development"
    dev_inputs = producer.FormalRecordInputsV1(
        **{
            **vars(record_inputs(producer, fixture)),
            "record_bytes": consumer.canonical_pf_jcs(dev_record),
        }
    )
    expect_error(
        producer,
        lambda: producer.produce_support_binding(
            evidence_bytes=b"ev\n",
            evidence_id=ev_typed[0],
            record_inputs=dev_inputs,
            build=build,
            support_claim=claim,
            gate_vectors=make_gate_vectors(producer, fixture),
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "development finalization input",
    )

    # revoked evidence.
    revoked_record = consumer.decode_canonical_pf_jcs(
        fixture["revocationRecordBytes"][0]
    )
    revoked_record["revokedEvidenceId"] = evidence_ref["id"]
    tampered_revocation_bytes = (
        consumer.canonical_pf_jcs(revoked_record),
        fixture["revocationRecordBytes"][1],
    )
    tampered_inputs = producer.FormalRecordInputsV1(
        **{
            **vars(record_inputs(producer, fixture)),
            "revocation_record_bytes": tampered_revocation_bytes,
        }
    )
    expect_error(
        producer,
        lambda: producer.produce_support_binding(
            evidence_bytes=b"ev\n",
            evidence_id=ev_typed[0],
            record_inputs=tampered_inputs,
            build=build,
            support_claim=claim,
            gate_vectors=make_gate_vectors(producer, fixture),
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "revoked evidence must not bind",
    )

    # inverted record window (stale).
    inverted = copy.deepcopy(fixture["recordWire"])
    inverted["expiresAt"] = "2026-07-18T10:00:00Z"
    inverted_inputs = producer.FormalRecordInputsV1(
        **{
            **vars(record_inputs(producer, fixture)),
            "record_bytes": consumer.canonical_pf_jcs(inverted),
        }
    )
    expect_error(
        producer,
        lambda: producer.produce_support_binding(
            evidence_bytes=b"ev\n",
            evidence_id=ev_typed[0],
            record_inputs=inverted_inputs,
            build=build,
            support_claim=claim,
            gate_vectors=make_gate_vectors(producer, fixture),
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "finalizedAt not before expiresAt",
    )

    # evidence not covered by the record.
    expect_error(
        producer,
        lambda: producer.produce_support_binding(
            evidence_bytes=b"ev\n",
            evidence_id="EV-20260719-0001",
            record_inputs=record_inputs(producer, fixture),
            build=build,
            support_claim=claim,
            gate_vectors=make_gate_vectors(producer, fixture),
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "evidence outside the finalization record",
    )

    # partial gate set.
    partial_vectors = make_gate_vectors(producer, fixture)[:-1]
    expect_error(
        producer,
        lambda: producer.produce_support_binding(
            evidence_bytes=b"ev\n",
            evidence_id=ev_typed[0],
            record_inputs=record_inputs(producer, fixture),
            build=build,
            support_claim=claim,
            gate_vectors=partial_vectors,
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "partial gate vector set",
    )
    unknown_gate_vector = make_gate_vectors(producer, fixture) + (
        producer.GateVectorV1("gate-unknown", ev_typed, "specified"),
    )
    expect_error(
        producer,
        lambda: producer.produce_support_binding(
            evidence_bytes=b"ev\n",
            evidence_id=ev_typed[0],
            record_inputs=record_inputs(producer, fixture),
            build=build,
            support_claim=claim,
            gate_vectors=unknown_gate_vector,
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "gate vector for an unknown gate",
    )
    bad_grade = producer.GateVectorV1(
        "gate-alpha", ev_typed, "production"
    )
    expect_error(
        producer,
        lambda: producer.produce_support_binding(
            evidence_bytes=b"ev\n",
            evidence_id=ev_typed[0],
            record_inputs=record_inputs(producer, fixture),
            build=build,
            support_claim=claim,
            gate_vectors=(bad_grade,) + make_gate_vectors(producer, fixture)[1:],
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "gate vector with an invalid grade",
    )

    # wrong claimDigest at publication: tampered binding body + original ref.
    trusted_root = tmpdir / "neg-binding-root"
    trusted_root.mkdir()
    binding_bytes, ref = produce_binding_for(
        producer, fixture, ev_typed, build, claim
    )
    tampered = consumer.decode_canonical_pf_jcs(binding_bytes)
    tampered["claimDigest"] = digest_text(bytes.fromhex("b9" * 32))
    expect_error(
        producer,
        lambda: producer.publish_support_binding(
            consumer.canonical_pf_jcs(tampered), ref, str(trusted_root)
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "tampered claimDigest must not publish",
    )
    residue = list(trusted_root.rglob("*.json"))
    if residue:
        raise AssertionError(f"failed binding must leave no staging residue: {residue}")

    # wrong claim shape negatives at production.
    bad_claim = make_claim()
    bad_claim["requirement"]["id"] = "noir"
    expect_error(
        producer,
        lambda: producer.produce_support_binding(
            evidence_bytes=b"ev\n",
            evidence_id=ev_typed[0],
            record_inputs=record_inputs(producer, fixture),
            build=build,
            support_claim=bad_claim,
            gate_vectors=make_gate_vectors(producer, fixture),
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "requirement id without two segments",
    )
    bad_predicates = make_claim()
    bad_predicates["predicates"] = [{"variant": "maybe", "name": "x", "value": 1}]
    expect_error(
        producer,
        lambda: producer.produce_support_binding(
            evidence_bytes=b"ev\n",
            evidence_id=ev_typed[0],
            record_inputs=record_inputs(producer, fixture),
            build=build,
            support_claim=bad_predicates,
            gate_vectors=make_gate_vectors(producer, fixture),
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "unknown predicate variant",
    )


def test_publish_record_negatives(producer: ModuleType, fixture: dict, tmpdir: Path) -> None:
    consumer = producer._CONSUMER
    base = fixture["base"]
    trusted_root = tmpdir / "neg-record-root"
    trusted_root.mkdir()
    record_bytes = fixture["recordBytes"]
    expected_digest = hashlib.sha256(
        b"pf.formal-evidence-finalization.v1\x00" + record_bytes
    ).digest()
    ref = producer._FORMAL.FinalizationRefV1(
        "proof-forge.formal-evidence-finalization.v1",
        "EVF-20260718-0001",
        producer._CONSUMER.Digest("sha256", expected_digest),
    )
    record_dir = trusted_root / (
        "finalized-formal/formal-evidence-catalog/"
        "bootstrap-acceptance-required-tests"
    )
    record_dir.mkdir(parents=True)
    (record_dir / "EVF-20260718-0001.json").write_bytes(b"existing")
    expect_error(
        producer,
        lambda: producer.publish_finalization(
            record_bytes,
            ref,
            str(trusted_root),
            base.requiredBytes,
            base.policyBytes,
        ),
        ("PF-EVIDENCE-ATOMICITY",),
        "pre-existing finalization publication",
    )
    if (record_dir / "EVF-20260718-0001.json").read_bytes() != b"existing":
        raise AssertionError("pre-existing publication must stay untouched")

    wrong_schema_root = tmpdir / "wrong-schema-root"
    wrong_schema_root.mkdir()
    expect_error(
        producer,
        lambda: producer.publish_finalization(
            consumer.canonical_pf_jcs({"schema": "proof-forge.other.v1"}),
            ref,
            str(wrong_schema_root),
            base.requiredBytes,
            base.policyBytes,
        ),
        ("PF-EVIDENCE-FORMAL-UNVERIFIED",),
        "publication of a non-record payload",
    )


def main() -> int:
    tmpdir = Path(tempfile.mkdtemp(prefix="formal-evidence-producer-test-"))
    try:
        acceptance = load_module(ACCEPTANCE_PATH, ACCEPTANCE_MODULE_NAME)
        consumer_test = load_module(CONSUMER_TEST_PATH, CONSUMER_TEST_MODULE_NAME)
        producer = load_module(PRODUCER_PATH, PRODUCER_MODULE_NAME)
        assert_public_api(producer)
        fixture = consumer_test.build_fixture(acceptance, tmpdir)
        try:
            test_produce_and_publish_record(producer, fixture, tmpdir)
            test_support_binding(producer, fixture, tmpdir)
            test_support_binding_negatives(producer, fixture, tmpdir)
            test_publish_record_negatives(producer, fixture, tmpdir)
        finally:
            consumer_test.close_fixture(fixture)
    except (AssertionError, AttributeError, OSError, ImportError, SyntaxError) as error:
        print(
            f"formal-evidence-producer-self-test: FAIL: {error}",
            file=sys.stderr,
        )
        return 1
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    print("formal-evidence-producer-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

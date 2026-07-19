#!/usr/bin/env python3
"""Acceptance tests for the formal input producer family (TASK-D0-07 slice S3).

Exercises ``scripts/formal_input_producers.py`` (SessionContainmentReceiptV1
and FreshnessAuthoritySnapshotV1 producers/signers, freshness window
predicate, unsigned FormalFinalizerIdentityV1 constructor) against the real
consumer round-trips in ``scripts/formal_evidence.py``.  All seeds are public
RFC 8032 test vectors (fixture namespace, ADR-0018); no filesystem use.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parent
ACCEPTANCE_PATH = REPO_ROOT / "bootstrap_acceptance.py"
FORMAL_PATH = REPO_ROOT / "formal_evidence.py"
PRODUCER_PATH = REPO_ROOT / "formal_input_producers.py"
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
SERVICE_SEED = bytes.fromhex("10" * 32)
CONTAINMENT_SIGNERS = ("key-quality", "key-security")
FRESHNESS_SIGNERS = ("key-quality", "key-release")
OBSERVED_AT = "2026-07-18T10:06:00Z"
MAX_AGE = 3600
EXPECTED_EXPIRY = "2026-07-18T11:06:00Z"
CLOCK_DECLARATION = (
    b"fixture local clock declaration\nsource: monotonic+utc drift<=1s\n"
)

CHECKS = 0


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "formal-input-producers self-test requires -I"
    assert sys.flags.no_site, "formal-input-producers self-test requires -S"
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


def build_policy(acceptance: ModuleType) -> object:
    return acceptance.build_rehearsal_base(
        namespace_id="formal-input-fixture-namespace",
        descriptor_id="authority-store",
        descriptor_version="1.0.0",
        service_seed=SERVICE_SEED,
        executable_digest_bytes=bytes.fromhex("42" * 32),
        observation_bytes=json.dumps(
            {
                "attestationScope": "local-observation-only",
                "eligibleForHermetic": True,
                "hostProfileId": "linux-x86_64-formal-input-fixture",
                "platform": {"secureBoot": "enabled"},
                "remoteAttestation": False,
                "trustRoot": "synthetic fixture",
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        profile_bytes=json.dumps(
            {"id": "linux-x86_64-formal-input-fixture"},
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )


def candidate_wire(base: object) -> dict:
    return {
        "commit": base.candidateCommit,
        "treeObjectId": base.candidateTreeObjectId,
        "archiveDigest": digest_text(base.candidateArchiveDigestBytes),
        "digest": digest_text(base.candidateDigestBytes),
    }


def handoff_ref_wire() -> dict:
    return {
        "schema": "proof-forge.eligible-stage0-handoff.v1",
        "id": "formal-input-fixture-handoff",
        "version": "1.0.0",
        "digest": digest_text(hashlib.sha256(b"fixture handoff").digest()),
    }


def descendants() -> tuple:
    return (
        {
            "pid": 102,
            "parentPid": 1,
            "startToken": 12,
            "sessionId": 501,
            "executableDigest": digest_text(bytes.fromhex("83" * 32)),
            "termination": "killed",
        },
        {
            "pid": 101,
            "parentPid": 1,
            "startToken": 11,
            "sessionId": 501,
            "executableDigest": digest_text(bytes.fromhex("82" * 32)),
            "termination": "exited",
        },
    )


def escape_probes() -> tuple:
    return ({"id": "escape-probe-01", "result": "contained"},)


def produce_containment(module: ModuleType, base: object,
                        signers: tuple = CONTAINMENT_SIGNERS,
                        **overrides: object) -> bytes:
    kwargs = {
        "id": "session-containment-fixture",
        "version": "1.0.0",
        "candidate": candidate_wire(base),
        "stage0_handoff": handoff_ref_wire(),
        "supervisor_digest": digest_text(bytes.fromhex("81" * 32)),
        "root_session_id": "root-session-01",
        "descendants": descendants(),
        "escape_probes": escape_probes(),
        "started_at": "2026-07-18T10:00:00Z",
        "finished_at": "2026-07-18T10:05:00Z",
        "result": "contained",
        "authority_policy_bytes": base.policyBytes,
        "signers": tuple((key_id, SEEDS_BY_KEY_ID[key_id]) for key_id in signers),
    }
    kwargs.update(overrides)
    return module.produce_session_containment_receipt(**kwargs)


def produce_freshness(module: ModuleType, base: object,
                      signers: tuple = FRESHNESS_SIGNERS,
                      **overrides: object) -> bytes:
    kwargs = {
        "id": "freshness-authority-fixture",
        "version": "1.0.0",
        "authority_policy_bytes": base.policyBytes,
        "observed_at": OBSERVED_AT,
        "maximum_age_seconds": MAX_AGE,
        "clock_source_bytes": CLOCK_DECLARATION,
        "signers": tuple((key_id, SEEDS_BY_KEY_ID[key_id]) for key_id in signers),
    }
    kwargs.update(overrides)
    return module.produce_freshness_authority_snapshot(**kwargs)


def formal_policy(formal: ModuleType, policy_bytes: bytes) -> object:
    return formal._CONSUMER.parse_bootstrap_authority_policy(policy_bytes)[0]


def expect_module_error(module: ModuleType, operation, code: str, label: str) -> None:
    try:
        result = operation()
    except module.FormalInputError as error:
        if error.code != code:
            raise AssertionError(f"{label} raised {error.code}: {error.detail}")
        checked(label)
        return
    raise AssertionError(f"{label} must fail with {code}; got {result!r}")


def expect_formal_rejected(formal: ModuleType, operation, label: str) -> None:
    try:
        result = operation()
    except formal.Rejected as rejected:
        if rejected.code != "PF-EVIDENCE-FORMAL-UNVERIFIED":
            raise AssertionError(f"{label} raised {rejected.code}")
        checked(label)
        return
    raise AssertionError(f"{label} must fail with formal Rejected; got {result!r}")


def resign_with_domain(acceptance: ModuleType, consumer, signed_bytes: bytes,
                       signers: tuple, statement_domain: bytes,
                       signature_domain: bytes) -> bytes:
    wire = consumer.decode_canonical_pf_jcs(signed_bytes)
    statement = {key: wire[key] for key in wire if key != "signatures"}
    statement_digest = hashlib.sha256(
        statement_domain + consumer.canonical_pf_jcs(statement)
    ).digest()
    producer = acceptance._PRODUCER
    wire = dict(statement)
    wire["signatures"] = [
        {
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": producer.sign_ed25519(
                SEEDS_BY_KEY_ID[key_id], signature_domain + statement_digest
            ).hex(),
        }
        for key_id in signers
    ]
    return consumer.canonical_pf_jcs(wire)


def main() -> int:
    acceptance = load_module(
        ACCEPTANCE_PATH, "proof_forge_bootstrap_acceptance_for_input_test"
    )
    formal = load_module(
        FORMAL_PATH, "proof_forge_formal_evidence_for_input_test"
    )
    module = load_module(
        PRODUCER_PATH, "proof_forge_formal_input_producers_under_test"
    )
    base = build_policy(acceptance)
    policy = formal_policy(formal, base.policyBytes)
    consumer = acceptance._CONSUMER

    for name in (
        "produce_session_containment_receipt",
        "produce_freshness_authority_snapshot",
        "produce_formal_finalizer_identity",
        "formal_finalizer_identity_digest",
        "freshness_expires_at",
        "require_freshness_window",
        "FormalInputError",
        "CONTAINMENT_SCHEMA",
        "FRESHNESS_SCHEMA",
        "FINALIZER_SCHEMA",
        "CONTAINMENT_STATEMENT_DOMAIN",
        "CONTAINMENT_SIGNATURE_DOMAIN",
        "FRESHNESS_STATEMENT_DOMAIN",
        "FRESHNESS_SIGNATURE_DOMAIN",
        "FINALIZER_DIGEST_DOMAIN",
    ):
        assert getattr(module, name, None) is not None, f"missing {name}"
    checked("public API surface")

    # Positive: containment receipt round-trip (2 descendants, 1 escape probe).
    containment_bytes = produce_containment(module, base)
    containment = formal.parse_session_containment_receipt(
        containment_bytes, policy
    )
    assert containment.schema == "proof-forge.session-containment-receipt.v1"
    assert containment.candidate.commit == base.candidateCommit
    assert containment.rootSessionId == "root-session-01"
    assert tuple(item.pid for item in containment.descendants) == (101, 102)
    assert tuple(item.termination for item in containment.descendants) == (
        "exited", "killed"
    )
    assert tuple(probe.id for probe in containment.escapeProbes) == (
        "escape-probe-01",
    )
    assert containment.result == "contained"
    assert containment.startedAt == "2026-07-18T10:00:00Z"
    assert containment.finishedAt == "2026-07-18T10:05:00Z"
    checked("containment receipt round-trip (sorted descendants/probes)")

    # Positive: freshness snapshot round-trip + expiresAt relation.
    freshness_bytes = produce_freshness(module, base)
    freshness = formal.parse_freshness_authority_snapshot(
        freshness_bytes, policy
    )
    assert freshness.schema == "proof-forge.freshness-authority-snapshot.v1"
    assert freshness.observedAt == OBSERVED_AT
    assert freshness.maximumAgeSeconds == MAX_AGE
    assert freshness.clockSourceDigest.bytes == hashlib.sha256(
        CLOCK_DECLARATION
    ).digest()
    base_policy_ref = formal._CONSUMER.parse_bootstrap_authority_policy(
        base.policyBytes
    )[1]
    assert freshness.authorityPolicy == base_policy_ref
    assert module.freshness_expires_at(OBSERVED_AT, MAX_AGE) == EXPECTED_EXPIRY
    checked("freshness snapshot round-trip (expiresAt relation)")

    # Positive: freshness window predicate accepts an in-window finalization.
    module.require_freshness_window(
        OBSERVED_AT, MAX_AGE, EXPECTED_EXPIRY, "2026-07-18T10:30:00Z"
    )
    checked("freshness window accepts in-window finalization")

    # Positive: finalizer identity construction + digest helper.
    identity_bytes = module.produce_formal_finalizer_identity(
        id="formal-finalizer-fixture",
        version="1.0.0",
        executable_digest=digest_text(bytes.fromhex("91" * 32)),
        closure_digest=digest_text(bytes.fromhex("92" * 32)),
        toolchain_lock_digest=digest_text(bytes.fromhex("93" * 32)),
    )
    identity = formal.parse_formal_finalizer_identity(identity_bytes)
    assert identity.schema == "proof-forge.formal-finalizer-identity.v1"
    assert identity.executableDigest.bytes == bytes.fromhex("91" * 32)
    assert module.formal_finalizer_identity_digest(identity_bytes) == (
        digest_text(
            hashlib.sha256(
                b"pf.formal-finalizer-identity.v1\x00" + identity_bytes
            ).digest()
        )
    )
    checked("finalizer identity construction + digest helper")

    # Negative: containment signing-rule violations.
    expect_module_error(
        module,
        lambda: produce_containment(
            module, base, signers=("key-quality", "key-release")
        ),
        "PF-FORMAL-INPUT-VERIFY",
        "containment wrong rule signer rejected (quality+release)",
    )
    expect_module_error(
        module,
        lambda: produce_containment(module, base, signers=("key-quality",)),
        "PF-FORMAL-INPUT-VERIFY",
        "containment below-quorum signature rejected",
    )

    # Negative: containment wire violations.
    bad_termination = [dict(descendants()[0], termination="vanished")]
    expect_module_error(
        module,
        lambda: produce_containment(module, base, descendants=bad_termination),
        "PF-FORMAL-INPUT-SCHEMA",
        "bad termination enum rejected",
    )
    negative_pid = [dict(descendants()[0], pid=-1)]
    expect_module_error(
        module,
        lambda: produce_containment(module, base, descendants=negative_pid),
        "PF-FORMAL-INPUT-SCHEMA",
        "negative pid rejected (UInt64)",
    )
    float_pid = [dict(descendants()[0], pid=101.5)]
    expect_module_error(
        module,
        lambda: produce_containment(module, base, descendants=float_pid),
        "PF-FORMAL-INPUT-SCHEMA",
        "non-integer pid rejected (UInt64)",
    )
    extra_field_descendant = [dict(descendants()[0], note="x")]
    expect_module_error(
        module,
        lambda: produce_containment(
            module, base, descendants=extra_field_descendant
        ),
        "PF-FORMAL-INPUT-SCHEMA",
        "descendant with unknown field rejected (closed object)",
    )
    expect_module_error(
        module,
        lambda: produce_containment(
            module, base, escape_probes=({"id": "escape-probe-02", "result": "escaped"},)
        ),
        "PF-FORMAL-INPUT-SCHEMA",
        "non-contained escape probe rejected",
    )
    expect_module_error(
        module,
        lambda: produce_containment(module, base, result="escaped"),
        "PF-FORMAL-INPUT-SCHEMA",
        "non-contained receipt result rejected",
    )

    # Negative: containment consumer-level tampering.
    wrong_domain = resign_with_domain(
        acceptance, consumer, containment_bytes, CONTAINMENT_SIGNERS,
        b"pf.session-containment-receipt-statement.v1\x00",
        b"pf.freshness-authority-snapshot-signature.v1\x00",
    )
    expect_formal_rejected(
        formal,
        lambda: formal.parse_session_containment_receipt(wrong_domain, policy),
        "containment wrong signature domain rejected",
    )
    stale = bytearray(containment_bytes)
    stale[-40] ^= 0x01
    expect_formal_rejected(
        formal,
        lambda: formal.parse_session_containment_receipt(bytes(stale), policy),
        "stale containment receipt (signed bytes mutated) rejected",
    )

    # Negative: freshness signing-rule violations.
    expect_module_error(
        module,
        lambda: produce_freshness(
            module, base, signers=("key-quality", "key-security")
        ),
        "PF-FORMAL-INPUT-VERIFY",
        "freshness wrong rule signer rejected (quality+security)",
    )
    expect_module_error(
        module,
        lambda: produce_freshness(module, base, signers=("key-release",)),
        "PF-FORMAL-INPUT-VERIFY",
        "freshness below-quorum signature rejected",
    )

    # Negative: freshness wire violations.
    expect_module_error(
        module,
        lambda: produce_freshness(module, base, maximum_age_seconds=0),
        "PF-FORMAL-INPUT-SCHEMA",
        "zero maximumAgeSeconds rejected (must be nonzero)",
    )
    expect_module_error(
        module,
        lambda: produce_freshness(module, base, maximum_age_seconds=-60),
        "PF-FORMAL-INPUT-SCHEMA",
        "negative maximumAgeSeconds rejected (UInt64)",
    )
    expect_module_error(
        module,
        lambda: produce_freshness(module, base, clock_source_bytes=b""),
        "PF-FORMAL-INPUT-SCHEMA",
        "missing clock source declaration rejected",
    )

    # Negative: freshness predicate violations.
    expect_module_error(
        module,
        lambda: module.require_freshness_window(
            OBSERVED_AT, MAX_AGE, "2026-07-18T12:06:00Z", "2026-07-18T10:30:00Z"
        ),
        "PF-FORMAL-INPUT-VERIFY",
        "expiresAt mismatch (not observedAt+maximumAgeSeconds) rejected",
    )
    expect_module_error(
        module,
        lambda: module.require_freshness_window(
            OBSERVED_AT, MAX_AGE, EXPECTED_EXPIRY, "2026-07-18T11:06:00Z"
        ),
        "PF-FORMAL-INPUT-VERIFY",
        "stale finalization (finalizedAt >= expiresAt) rejected",
    )

    # Negative: freshness consumer-level tampering.
    wrong_domain = resign_with_domain(
        acceptance, consumer, freshness_bytes, FRESHNESS_SIGNERS,
        b"pf.freshness-authority-snapshot-statement.v1\x00",
        b"pf.session-containment-receipt-signature.v1\x00",
    )
    expect_formal_rejected(
        formal,
        lambda: formal.parse_freshness_authority_snapshot(wrong_domain, policy),
        "freshness wrong signature domain rejected",
    )
    stale = bytearray(freshness_bytes)
    stale[-40] ^= 0x01
    expect_formal_rejected(
        formal,
        lambda: formal.parse_freshness_authority_snapshot(bytes(stale), policy),
        "stale freshness snapshot (signed bytes mutated) rejected",
    )

    # Negative: finalizer identity violations.
    expect_module_error(
        module,
        lambda: module.produce_formal_finalizer_identity(
            id="formal-finalizer-fixture",
            version="1.0.0",
            executable_digest="not-a-digest",
            closure_digest=digest_text(bytes.fromhex("92" * 32)),
            toolchain_lock_digest=digest_text(bytes.fromhex("93" * 32)),
        ),
        "PF-FORMAL-INPUT-SCHEMA",
        "finalizer identity bad digest grammar rejected",
    )
    extra_field_identity = consumer.decode_canonical_pf_jcs(identity_bytes)
    extra_field_identity["signatures"] = []
    expect_formal_rejected(
        formal,
        lambda: formal.parse_formal_finalizer_identity(
            consumer.canonical_pf_jcs(extra_field_identity)
        ),
        "finalizer identity is unsigned (signatures field rejected)",
    )

    print(f"formal-input-producers-self-test: ok ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

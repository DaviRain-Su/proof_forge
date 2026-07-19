#!/usr/bin/env python3
"""Acceptance tests for the revocation ledger family (TASK-D0-07 slice S1).

Exercises ``scripts/revocation_ledger.py`` (record producer/parser,
append-only store, signed RevocationLedgerSnapshotV1 producer) against the
real consumer round-trip in ``scripts/formal_evidence.py``.  All seeds are
public RFC 8032 test vectors (fixture namespace, ADR-0018); nothing touches
the filesystem.
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
REVOCATION_PATH = REPO_ROOT / "revocation_ledger.py"
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
GENESIS = "0" * 64
SNAPSHOT_SIGNERS = ("key-release", "key-security")
AUTHORITIES = ("revocation-authority-alpha", "revocation-authority-beta")

CHECKS = 0


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "revocation-ledger self-test requires -I"
    assert sys.flags.no_site, "revocation-ledger self-test requires -S"
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
        namespace_id="revocation-ledger-fixture-namespace",
        descriptor_id="authority-store",
        descriptor_version="1.0.0",
        service_seed=SERVICE_SEED,
        executable_digest_bytes=bytes.fromhex("42" * 32),
        observation_bytes=json.dumps(
            {
                "attestationScope": "local-observation-only",
                "eligibleForHermetic": True,
                "hostProfileId": "linux-x86_64-revocation-fixture",
                "platform": {"secureBoot": "enabled"},
                "remoteAttestation": False,
                "trustRoot": "synthetic fixture",
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        profile_bytes=json.dumps(
            {"id": "linux-x86_64-revocation-fixture"},
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )


def make_record(
    module: ModuleType,
    record_id: str,
    evidence_id: str,
    previous: str,
    *,
    authority: str = "revocation-authority-alpha",
    revoked_utc: str = "2026-07-18T09:00:00Z",
    replacement=None,
) -> bytes:
    return module.produce_revocation_record(
        id=record_id,
        evidence_id=evidence_id,
        evidence_sha256=hashlib.sha256(evidence_id.encode("ascii")).hexdigest(),
        revoked_utc=revoked_utc,
        reason_code="superseded",
        reason=f"fixture revocation of {evidence_id}",
        authority_ref=authority,
        replacement=replacement,
        previous_record_sha256=previous,
    )


def chain_records(module: ModuleType, count: int) -> tuple:
    records = []
    previous = GENESIS
    for index in range(1, count + 1):
        record_bytes = make_record(
            module,
            f"RVK-20260718-{index:04d}",
            f"EV-20260717-{index:04d}",
            previous,
        )
        records.append(record_bytes)
        previous = hashlib.sha256(record_bytes).hexdigest()
    return tuple(records)


def sign_snapshot(module: ModuleType, policy_bytes: bytes, records: tuple,
                  signers: tuple = SNAPSHOT_SIGNERS) -> bytes:
    return module.produce_revocation_ledger_snapshot(
        id="revocation-ledger-fixture",
        version="1.0.0",
        policy_bytes=policy_bytes,
        record_bytes=records,
        signers=tuple(
            (key_id, SEEDS_BY_KEY_ID[key_id]) for key_id in signers
        ),
    )


def formal_policy(formal: ModuleType, policy_bytes: bytes) -> object:
    return formal._CONSUMER.parse_bootstrap_authority_policy(policy_bytes)[0]


def expect_module_error(
    module: ModuleType,
    operation,
    code: str,
    label: str,
) -> None:
    try:
        result = operation()
    except module.RevocationError as error:
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


def main() -> int:
    acceptance = load_module(
        ACCEPTANCE_PATH, "proof_forge_bootstrap_acceptance_for_revocation_test"
    )
    formal = load_module(
        FORMAL_PATH, "proof_forge_formal_evidence_for_revocation_test"
    )
    module = load_module(
        REVOCATION_PATH, "proof_forge_revocation_ledger_under_test"
    )
    base = build_policy(acceptance)
    policy_bytes = base.policyBytes
    policy = formal_policy(formal, policy_bytes)
    consumer = acceptance._CONSUMER

    for name in (
        "produce_revocation_record",
        "parse_revocation_record",
        "produce_revocation_ledger_snapshot",
        "RevocationLedgerStore",
        "RevocationError",
        "GENESIS_PREVIOUS_RECORD_SHA256",
        "REVOCATION_RECORD_SCHEMA",
        "REVOCATION_SNAPSHOT_SCHEMA",
        "RECORD_DIGEST_DOMAIN",
        "RECORDS_DIGEST_DOMAIN",
        "STATEMENT_DOMAIN",
        "SIGNATURE_DOMAIN",
    ):
        assert getattr(module, name, None) is not None, f"missing {name}"
    assert module.GENESIS_PREVIOUS_RECORD_SHA256 == GENESIS
    checked("public API surface")

    # Positive: empty ledger snapshot round-trips with head=null.
    empty_snapshot = sign_snapshot(module, policy_bytes, ())
    parsed_empty = formal.parse_revocation_ledger_snapshot(
        empty_snapshot, policy, ()
    )
    assert parsed_empty.records == ()
    assert parsed_empty.head is None
    expected_empty_digest = hashlib.sha256(
        b"pf.revocation-ledger-records.v1\x00"
    ).digest()
    assert parsed_empty.recordsDigest.bytes == expected_empty_digest
    checked("empty-ledger snapshot parses with head=null")

    # Positive: two-record chain through the append-only store.
    records = chain_records(module, 2)
    store = module.RevocationLedgerStore(authorities=AUTHORITIES)
    for record_bytes in records:
        store.append(record_bytes)
    assert store.records == records
    assert len(store.refs) == 2
    snapshot = sign_snapshot(module, policy_bytes, store.records)
    parsed = formal.parse_revocation_ledger_snapshot(
        snapshot, policy, store.records
    )
    assert tuple(ref.id for ref in parsed.records) == (
        "RVK-20260718-0001", "RVK-20260718-0002"
    )
    assert parsed.head == parsed.records[-1]
    aggregate = b"".join(
        (32).to_bytes(4, "big") + ref.digest.bytes for ref in parsed.records
    )
    assert parsed.recordsDigest.bytes == hashlib.sha256(
        b"pf.revocation-ledger-records.v1\x00" + aggregate
    ).digest()
    checked("two-record chain snapshot round-trip")

    # Positive: record parser round-trip preserves the full payload.
    record = module.parse_revocation_record(records[0])
    assert record.schema == "proof-forge.evidence-revocation.v1"
    assert record.id == "RVK-20260718-0001"
    assert record.version == "1.0.0"
    assert record.evidenceId == "EV-20260717-0001"
    assert record.revokedUtc == "2026-07-18T09:00:00Z"
    assert record.reasonCode == "superseded"
    assert record.authorityRef == "revocation-authority-alpha"
    assert record.replacementId is None
    assert record.previousRecordSha256 == GENESIS
    ref = module.revocation_record_ref(records[0])
    assert ref["digest"] == digest_text(
        hashlib.sha256(b"pf.evidence-revocation.v1\x00" + records[0]).digest()
    )
    checked("record parser round-trip + ref digest")

    # Positive: replacement payload accepted when referencing another EV.
    replacement_record = module.produce_revocation_record(
        id="RVK-20260718-0003",
        evidence_id="EV-20260717-0001",
        evidence_sha256=hashlib.sha256(b"EV-20260717-0001").hexdigest(),
        revoked_utc="2026-07-18T10:00:00Z",
        reason_code="incorrect",
        reason="fixture replacement path",
        authority_ref="revocation-authority-beta",
        replacement=(
            "EV-20260717-0002",
            hashlib.sha256(b"EV-20260717-0002").hexdigest(),
        ),
        previous_record_sha256=GENESIS,
    )
    parsed_replacement = module.parse_revocation_record(replacement_record)
    assert parsed_replacement.replacementId == "EV-20260717-0002"
    checked("replacement payload accepted")

    # Negative: record wire violations.
    expect_module_error(
        module,
        lambda: module.produce_revocation_record(
            id="RVK-20260718-0001",
            evidence_id="EV-20260717-0001",
            evidence_sha256=hashlib.sha256(b"EV-20260717-0001").hexdigest(),
            revoked_utc="2026-07-19T09:00:00Z",
            reason_code="superseded",
            reason="date mismatch",
            authority_ref="revocation-authority-alpha",
            replacement=None,
            previous_record_sha256=GENESIS,
        ),
        "PF-REVOCATION-SCHEMA",
        "RVK id date must equal revokedUtc date",
    )
    expect_module_error(
        module,
        lambda: module.produce_revocation_record(
            id="RVK-20260718-0001",
            evidence_id="EV-20260717-0001",
            evidence_sha256=hashlib.sha256(b"EV-20260717-0001").hexdigest(),
            revoked_utc="2026-07-18T09:00:00Z",
            reason_code="bogus",
            reason="bad reason code",
            authority_ref="revocation-authority-alpha",
            replacement=None,
            previous_record_sha256=GENESIS,
        ),
        "PF-REVOCATION-SCHEMA",
        "unknown reasonCode rejected",
    )
    expect_module_error(
        module,
        lambda: module.produce_revocation_record(
            id="RVK-20260718-0001",
            evidence_id="EV-20260717-0001",
            evidence_sha256=hashlib.sha256(b"EV-20260717-0001").hexdigest(),
            revoked_utc="2026-07-18T09:00:00Z",
            reason_code="superseded",
            reason="self replacement",
            authority_ref="revocation-authority-alpha",
            replacement=(
                "EV-20260717-0001",
                hashlib.sha256(b"EV-20260717-0001").hexdigest(),
            ),
            previous_record_sha256=GENESIS,
        ),
        "PF-REVOCATION-SCHEMA",
        "replacement must not equal revoked evidence",
    )
    expect_module_error(
        module,
        lambda: module.produce_revocation_record(
            id="RVK-20260718-0001",
            evidence_id="EV-20260717-0001",
            evidence_sha256=hashlib.sha256(b"EV-20260717-0001").hexdigest(),
            revoked_utc="2026-07-18T09:00:00Z",
            reason_code="superseded",
            reason="null genesis",
            authority_ref="revocation-authority-alpha",
            replacement=None,
            previous_record_sha256=None,
        ),
        "PF-REVOCATION-SCHEMA",
        "null genesis previousRecordSha256 rejected (zero-hex convention)",
    )
    tampered_schema = consumer.decode_canonical_pf_jcs(records[0])
    tampered_schema["schema"] = "proof-forge.evidence-revocation.v2"
    expect_module_error(
        module,
        lambda: module.parse_revocation_record(
            consumer.canonical_pf_jcs(tampered_schema)
        ),
        "PF-REVOCATION-SCHEMA",
        "unknown record schema rejected",
    )
    extra_field = consumer.decode_canonical_pf_jcs(records[0])
    extra_field["revoked"] = True
    expect_module_error(
        module,
        lambda: module.parse_revocation_record(
            consumer.canonical_pf_jcs(extra_field)
        ),
        "PF-REVOCATION-SCHEMA",
        "record with unknown field rejected (closed object)",
    )

    # Negative: append-only store violations.
    fork_store = module.RevocationLedgerStore(authorities=AUTHORITIES)
    fork_store.append(records[0])
    fork_store.append(records[1])
    expect_module_error(
        module,
        lambda: fork_store.append(records[0]),
        "PF-REVOCATION-CHAIN",
        "duplicate record id rejected",
    )
    fork_record = make_record(
        module, "RVK-20260718-0003", "EV-20260717-0003",
        hashlib.sha256(records[0]).hexdigest(),
    )
    expect_module_error(
        module,
        lambda: fork_store.append(fork_record),
        "PF-REVOCATION-CHAIN",
        "hash chain fork rejected",
    )
    dangling_record = make_record(
        module, "RVK-20260718-0004", "EV-20260717-0004",
        hashlib.sha256(b"not-in-the-ledger").hexdigest(),
    )
    expect_module_error(
        module,
        lambda: fork_store.append(dangling_record),
        "PF-REVOCATION-CHAIN",
        "missing chain link rejected",
    )
    unknown_authority_record = make_record(
        module, "RVK-20260718-0005", "EV-20260717-0005",
        hashlib.sha256(records[1]).hexdigest(),
        authority="revocation-authority-gamma",
    )
    expect_module_error(
        module,
        lambda: fork_store.append(unknown_authority_record),
        "PF-REVOCATION-CHAIN",
        "unknown authority rejected",
    )

    # Negative: producer chain/order violations.
    expect_module_error(
        module,
        lambda: sign_snapshot(module, policy_bytes, (records[1], records[0])),
        "PF-REVOCATION-CHAIN",
        "producer rejects out-of-order record chain",
    )
    broken_link = make_record(
        module, "RVK-20260718-0002", "EV-20260717-0002", GENESIS,
    )
    expect_module_error(
        module,
        lambda: sign_snapshot(
            module, policy_bytes, (records[0], broken_link)
        ),
        "PF-REVOCATION-CHAIN",
        "producer rejects wrong previousRecordSha256",
    )

    # Negative: signature/rule violations caught by consumer re-verification.
    expect_module_error(
        module,
        lambda: sign_snapshot(
            module, policy_bytes, records, signers=("key-quality", "key-security")
        ),
        "PF-REVOCATION-VERIFY",
        "wrong rule signer rejected (quality+security instead of release+security)",
    )
    expect_module_error(
        module,
        lambda: sign_snapshot(
            module, policy_bytes, records, signers=("key-release",)
        ),
        "PF-REVOCATION-VERIFY",
        "below-quorum signature rejected",
    )

    # Negative: tampered snapshot bytes / digests at the consumer level.
    snapshot_wire = consumer.decode_canonical_pf_jcs(snapshot)
    tampered_digest = dict(snapshot_wire)
    tampered_digest["recordsDigest"] = digest_text(bytes(32))
    expect_formal_rejected(
        formal,
        lambda: formal.parse_revocation_ledger_snapshot(
            consumer.canonical_pf_jcs(tampered_digest), policy, records
        ),
        "tampered recordsDigest rejected",
    )
    wrong_head = consumer.decode_canonical_pf_jcs(snapshot)
    wrong_head["head"] = wrong_head["records"][0]
    expect_formal_rejected(
        formal,
        lambda: formal.parse_revocation_ledger_snapshot(
            consumer.canonical_pf_jcs(wrong_head), policy, records
        ),
        "head not the last record rejected",
    )
    stale = bytearray(snapshot)
    stale[-40] ^= 0x01
    expect_formal_rejected(
        formal,
        lambda: formal.parse_revocation_ledger_snapshot(
            bytes(stale), policy, records
        ),
        "stale snapshot (signed bytes mutated) rejected",
    )

    # Negative: wrong signature domain (hand-signed with the freshness domain).
    statement = {
        key: snapshot_wire[key] for key in snapshot_wire if key != "signatures"
    }
    statement_digest = hashlib.sha256(
        b"pf.revocation-ledger-snapshot-statement.v1\x00"
        + consumer.canonical_pf_jcs(statement)
    ).digest()
    wrong_domain_message = (
        b"pf.freshness-authority-snapshot-signature.v1\x00" + statement_digest
    )
    producer = acceptance._PRODUCER
    wrong_domain_wire = dict(statement)
    wrong_domain_wire["signatures"] = [
        {
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": producer.sign_ed25519(
                SEEDS_BY_KEY_ID[key_id], wrong_domain_message
            ).hex(),
        }
        for key_id in SNAPSHOT_SIGNERS
    ]
    expect_formal_rejected(
        formal,
        lambda: formal.parse_revocation_ledger_snapshot(
            consumer.canonical_pf_jcs(wrong_domain_wire), policy, records
        ),
        "wrong signature domain rejected",
    )

    print(f"revocation-ledger-self-test: ok ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

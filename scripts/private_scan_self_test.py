#!/usr/bin/env python3
"""Acceptance tests for the private scan family (TASK-D0-07 slice S2).

Exercises ``scripts/private_scan.py`` (policy validator, deny-marker scanner,
signed PrivateScanReceiptV1 producer) against the real consumer round-trip in
``scripts/formal_evidence.py``.  All seeds are public RFC 8032 test vectors
(fixture namespace, ADR-0018); member files live only in a temp directory.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tempfile
from pathlib import Path
from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parent
ACCEPTANCE_PATH = REPO_ROOT / "bootstrap_acceptance.py"
FORMAL_PATH = REPO_ROOT / "formal_evidence.py"
PRIVATE_SCAN_PATH = REPO_ROOT / "private_scan.py"
COMMITTED_POLICY_PATH = (
    REPO_ROOT.parent
    / "docs" / "governance" / "bootstrap-closure" / "private-scan-policy.json"
)
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
SCAN_SIGNERS = ("key-quality", "key-security")
EV1 = "EV-20260717-0001"
EV2 = "EV-20260717-0002"

CHECKS = 0


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "private-scan self-test requires -I"
    assert sys.flags.no_site, "private-scan self-test requires -S"
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
        namespace_id="private-scan-fixture-namespace",
        descriptor_id="authority-store",
        descriptor_version="1.0.0",
        service_seed=SERVICE_SEED,
        executable_digest_bytes=bytes.fromhex("42" * 32),
        observation_bytes=json.dumps(
            {
                "attestationScope": "local-observation-only",
                "eligibleForHermetic": True,
                "hostProfileId": "linux-x86_64-private-scan-fixture",
                "platform": {"secureBoot": "enabled"},
                "remoteAttestation": False,
                "trustRoot": "synthetic fixture",
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        profile_bytes=json.dumps(
            {"id": "linux-x86_64-private-scan-fixture"},
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


def scan_policy_bytes() -> bytes:
    return (
        json.dumps(
            {
                "schema": "proof-forge.private-scan-policy.v1",
                "id": "private-scan-fixture-policy",
                "version": "1.0.0",
                "denyContentMarkers": [
                    "BEGIN OPENSSH PRIVATE KEY",
                    "BEGIN PGP PRIVATE KEY BLOCK",
                    "BEGIN PRIVATE KEY",
                    "aws_secret_access_key",
                    "xoxb-",
                ],
                "denyPathMarkers": [
                    ".env",
                    ".key",
                    ".p12",
                    ".pem",
                    "id_ed25519",
                    "id_rsa",
                ],
                "maximumFindings": 0,
            },
            sort_keys=True,
            indent=2,
        ).encode("utf-8")
        + b"\n"
    )


def ev_ref(evidence_id: str) -> dict:
    return {
        "id": evidence_id,
        "digest": digest_text(
            hashlib.sha256(b"fixture-evidence:" + evidence_id.encode()).digest()
        ),
    }


def write_member(root: Path, relative: str, payload: bytes) -> str:
    path = root / "members" / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return str(path)


def build_bundle(root: Path) -> tuple:
    """Two-EV synthetic bundle; returns (manifest, member_specs)."""
    manifest = {
        "src/input.json": write_member(
            root, "src/input.json", b'{"fixture": "input"}\n'
        ),
        "out/artifact.bin": write_member(
            root, "out/artifact.bin", b"\x00\x01\x02artifact"
        ),
        "logs/run.log": write_member(
            root, "logs/run.log", b"fixture run log\n"
        ),
        "src/spec.txt": write_member(root, "src/spec.txt", b"fixture spec\n"),
        "out/result.bin": write_member(root, "out/result.bin", b"result"),
    }
    member_specs = (
        {"evidence": ev_ref(EV1), "role": "input", "path": "src/input.json"},
        {"evidence": ev_ref(EV1), "role": "artifact", "path": "out/artifact.bin"},
        {"evidence": ev_ref(EV1), "role": "log", "path": "logs/run.log"},
        {"evidence": ev_ref(EV2), "role": "input", "path": "src/spec.txt"},
        {"evidence": ev_ref(EV2), "role": "artifact", "path": "out/result.bin"},
    )
    return manifest, member_specs


def produce(module: ModuleType, base: object, manifest, member_specs,
            signers: tuple = SCAN_SIGNERS) -> bytes:
    return module.produce_private_scan_receipt(
        id="private-scan-fixture",
        version="1.0.0",
        candidate=candidate_wire(base),
        evidence_core_digest=digest_text(hashlib.sha256(b"fixture core").digest()),
        scanner_executable_bytes=PRIVATE_SCAN_PATH.read_bytes(),
        authority_policy_bytes=base.policyBytes,
        scan_policy_bytes=scan_policy_bytes(),
        scanned_evidence_refs=(ev_ref(EV1), ev_ref(EV2)),
        member_specs=member_specs,
        manifest=manifest,
        signers=tuple((key_id, SEEDS_BY_KEY_ID[key_id]) for key_id in signers),
    )


def formal_policy(formal: ModuleType, policy_bytes: bytes) -> object:
    return formal._CONSUMER.parse_bootstrap_authority_policy(policy_bytes)[0]


def expect_module_error(module: ModuleType, operation, code: str, label: str) -> None:
    try:
        result = operation()
    except module.PrivateScanError as error:
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
        ACCEPTANCE_PATH, "proof_forge_bootstrap_acceptance_for_scan_test"
    )
    formal = load_module(
        FORMAL_PATH, "proof_forge_formal_evidence_for_scan_test"
    )
    module = load_module(
        PRIVATE_SCAN_PATH, "proof_forge_private_scan_under_test"
    )
    base = build_policy(acceptance)
    policy = formal_policy(formal, base.policyBytes)
    consumer = acceptance._CONSUMER

    for name in (
        "parse_private_scan_policy",
        "private_scan_policy_ref",
        "scan_bundle_members",
        "produce_private_scan_receipt",
        "PrivateScanError",
        "PRIVATE_SCAN_POLICY_SCHEMA",
        "PRIVATE_SCAN_RECEIPT_SCHEMA",
        "POLICY_DIGEST_DOMAIN",
        "STATEMENT_DOMAIN",
        "SIGNATURE_DOMAIN",
    ):
        assert getattr(module, name, None) is not None, f"missing {name}"
    checked("public API surface")

    # Positive: the committed real policy document parses and digests correctly.
    committed = module.parse_private_scan_policy(COMMITTED_POLICY_PATH.read_bytes())
    assert committed.id == "bootstrap-private-scan-policy"
    assert committed.maximumFindings == 0
    assert b"BEGIN PRIVATE KEY" in committed.denyContentMarkers
    assert ".env" in committed.denyPathMarkers
    committed_ref = module.private_scan_policy_ref(
        COMMITTED_POLICY_PATH.read_bytes()
    )
    committed_wire = json.loads(COMMITTED_POLICY_PATH.read_bytes().decode("utf-8"))
    assert committed_ref["digest"] == digest_text(
        hashlib.sha256(
            b"pf.private-scan-policy.v1\x00"
            + consumer.canonical_pf_jcs(committed_wire)
        ).digest()
    )
    checked("committed policy document parses + ref digest convention")

    # Negative: policy document violations.
    expect_module_error(
        module,
        lambda: module.parse_private_scan_policy(
            json.dumps({**json.loads(scan_policy_bytes()), "extra": True}).encode()
        ),
        "PF-PRIVATE-SCAN-SCHEMA",
        "policy with unknown field rejected (closed object)",
    )
    expect_module_error(
        module,
        lambda: module.parse_private_scan_policy(
            json.dumps({
                **json.loads(scan_policy_bytes()),
                "denyContentMarkers": ["dup", "dup"],
            }).encode()
        ),
        "PF-PRIVATE-SCAN-SCHEMA",
        "policy with duplicate markers rejected",
    )
    expect_module_error(
        module,
        lambda: module.parse_private_scan_policy(
            json.dumps({
                **json.loads(scan_policy_bytes()),
                "maximumFindings": "0",
            }).encode()
        ),
        "PF-PRIVATE-SCAN-SCHEMA",
        "policy with non-integer maximumFindings rejected",
    )

    with tempfile.TemporaryDirectory(prefix="private-scan-test-") as temporary:
        root = Path(temporary)
        manifest, member_specs = build_bundle(root)
        policy_doc = module.parse_private_scan_policy(scan_policy_bytes())

        # Positive: clean scan computes exact member facts.
        outcome = module.scan_bundle_members(manifest, policy_doc)
        assert outcome.findings == ()
        artifact = outcome.members["out/artifact.bin"]
        assert artifact.size == len(b"\x00\x01\x02artifact")
        assert artifact.digest == hashlib.sha256(b"\x00\x01\x02artifact").hexdigest()
        checked("clean scan computes exact size/sha256 per member")

        # Positive: signed receipt round-trips through the formal consumer.
        receipt_bytes = produce(module, base, manifest, member_specs)
        receipt = formal.parse_private_scan_receipt(receipt_bytes, policy)
        assert receipt.schema == "proof-forge.private-scan-receipt.v1"
        assert receipt.candidate.commit == base.candidateCommit
        assert receipt.scannerDigest.bytes == hashlib.sha256(
            PRIVATE_SCAN_PATH.read_bytes()
        ).digest()
        assert receipt.policy.id == "private-scan-fixture-policy"
        assert tuple(ref[0] for ref in receipt.scannedEvidenceRefs) == (EV1, EV2)
        member_keys = tuple(
            (member.evidence[0], member.path) for member in receipt.scannedMembers
        )
        assert member_keys == (
            (EV1, "logs/run.log"),
            (EV1, "out/artifact.bin"),
            (EV1, "src/input.json"),
            (EV2, "out/result.bin"),
            (EV2, "src/spec.txt"),
        )
        assert receipt.findings == ()
        assert receipt.result == "clean"
        for member in receipt.scannedMembers:
            payload = (root / "members" / member.path).read_bytes()
            assert member.size == len(payload)
            assert member.digest.bytes == hashlib.sha256(payload).digest()
        checked("clean receipt round-trip (candidate/policy/members/findings)")

        # Negative: content marker hit blocks any clean receipt.
        bad_manifest = dict(manifest)
        bad_manifest["out/artifact.bin"] = write_member(
            root, "out/poisoned.bin",
            b"-----BEGIN PRIVATE KEY-----\nfixture\n",
        )
        bad_outcome = module.scan_bundle_members(bad_manifest, policy_doc)
        assert len(bad_outcome.findings) == 1
        assert bad_outcome.findings[0]["kind"] == "content"
        expect_module_error(
            module,
            lambda: produce(module, base, bad_manifest, member_specs),
            "PF-PRIVATE-SCAN-VERIFY",
            "content marker hit makes a clean receipt impossible",
        )

        # Negative: path marker hit blocks any clean receipt.
        env_manifest = dict(manifest)
        env_manifest["config/.env"] = write_member(
            root, "config/.env", b"SECRET=fixture\n"
        )
        env_specs = member_specs + (
            {"evidence": ev_ref(EV2), "role": "input", "path": "config/.env"},
        )
        env_outcome = module.scan_bundle_members(env_manifest, policy_doc)
        assert any(f["kind"] == "path" for f in env_outcome.findings)
        expect_module_error(
            module,
            lambda: produce(module, base, env_manifest, env_specs),
            "PF-PRIVATE-SCAN-VERIFY",
            "path marker hit (.env) makes a clean receipt impossible",
        )

        # Negative: EV references a member not in the manifest.
        missing_specs = member_specs + (
            {"evidence": ev_ref(EV2), "role": "log", "path": "logs/missing.log"},
        )
        expect_module_error(
            module,
            lambda: produce(module, base, manifest, missing_specs),
            "PF-PRIVATE-SCAN-VERIFY",
            "missing member (referenced, not in manifest) rejected",
        )

        # Negative: manifest carries a member no EV references.
        extra_manifest = dict(manifest)
        extra_manifest["out/extra.bin"] = write_member(
            root, "out/extra.bin", b"extra"
        )
        expect_module_error(
            module,
            lambda: produce(module, base, extra_manifest, member_specs),
            "PF-PRIVATE-SCAN-VERIFY",
            "extra manifest member (not referenced by any EV) rejected",
        )

        # Negative: duplicate (evidence,path) tuple.
        duplicate_specs = member_specs + (
            {"evidence": ev_ref(EV1), "role": "input", "path": "src/input.json"},
        )
        expect_module_error(
            module,
            lambda: produce(module, base, manifest, duplicate_specs),
            "PF-PRIVATE-SCAN-SCHEMA",
            "duplicate (evidence,path) member rejected",
        )

        # Negative: member references an evidence outside scannedEvidenceRefs.
        alien_specs = member_specs + (
            {
                "evidence": ev_ref("EV-20260717-0003"),
                "role": "input",
                "path": "src/spec.txt",
            },
        )
        expect_module_error(
            module,
            lambda: produce(module, base, manifest, alien_specs),
            "PF-PRIVATE-SCAN-VERIFY",
            "member evidence outside scannedEvidenceRefs rejected",
        )

        # Negative: signing rule violations.
        expect_module_error(
            module,
            lambda: produce(
                module, base, manifest, member_specs,
                signers=("key-release", "key-security"),
            ),
            "PF-PRIVATE-SCAN-VERIFY",
            "wrong rule signer rejected (release+security instead of quality+security)",
        )
        expect_module_error(
            module,
            lambda: produce(
                module, base, manifest, member_specs, signers=("key-quality",)
            ),
            "PF-PRIVATE-SCAN-VERIFY",
            "below-quorum signature rejected",
        )

        # Negative: consumer-level tampering of the signed receipt.
        receipt_wire = consumer.decode_canonical_pf_jcs(receipt_bytes)
        tampered_member = consumer.decode_canonical_pf_jcs(receipt_bytes)
        tampered_member["scannedMembers"][0]["digest"] = digest_text(bytes(32))
        expect_formal_rejected(
            formal,
            lambda: formal.parse_private_scan_receipt(
                consumer.canonical_pf_jcs(tampered_member), policy
            ),
            "tampered member digest breaks the statement signature",
        )
        non_clean = consumer.decode_canonical_pf_jcs(receipt_bytes)
        non_clean["findings"] = [{"marker": "x"}]
        expect_formal_rejected(
            formal,
            lambda: formal.parse_private_scan_receipt(
                consumer.canonical_pf_jcs(non_clean), policy
            ),
            "non-empty findings rejected by the consumer",
        )
        stale = bytearray(receipt_bytes)
        stale[-40] ^= 0x01
        expect_formal_rejected(
            formal,
            lambda: formal.parse_private_scan_receipt(bytes(stale), policy),
            "stale receipt (signed bytes mutated) rejected",
        )

        # Negative: wrong signature domain (hand-signed with the revocation domain).
        statement = {
            key: receipt_wire[key] for key in receipt_wire if key != "signatures"
        }
        statement_digest = hashlib.sha256(
            b"pf.private-scan-receipt-statement.v1\x00"
            + consumer.canonical_pf_jcs(statement)
        ).digest()
        wrong_domain_message = (
            b"pf.revocation-ledger-snapshot-signature.v1\x00" + statement_digest
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
            for key_id in SCAN_SIGNERS
        ]
        expect_formal_rejected(
            formal,
            lambda: formal.parse_private_scan_receipt(
                consumer.canonical_pf_jcs(wrong_domain_wire), policy
            ),
            "wrong signature domain rejected",
        )

    print(f"private-scan-self-test: ok ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

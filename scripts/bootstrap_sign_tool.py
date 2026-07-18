#!/usr/bin/env python3
"""Offline signing-ceremony CLI for bootstrap authority objects.

A human ceremony operator holds the Ed25519 seeds offline; this tool reads a
seed only from the explicit ``--seed-file`` path (or a ``seedFile`` entry in
the spec's signer list), uses it in memory for the immediate signature, and
never echoes, persists, or prints key material.  Seed files are safe-opened
(``O_NOFOLLOW``, regular file, single link, mode bits not exceeding 0400,
1..66 bytes) and the read buffer is overwritten after parsing; scrubbing is
best-effort because Python bytes are immutable.

Every subcommand maps a closed JSON spec (``fields`` for the producer
parameters, ``inputs`` for the authority bytes used by full verification,
``signer``/``signers`` for the signing material) onto typed consumer values,
reuses the consumer validators for construction-time checking, produces the
signed object with the sibling producer module, immediately re-verifies it
with the corresponding full ``parse_*`` against the supplied authority
inputs, and only then writes the canonical PF-JCS bytes to ``--output``
atomically with no-clobber 0444 semantics (exclusive temp file, fsync,
``os.link``, directory fsync, temp unlink).  On success it prints the object
id and recomputed digest; on any failure it prints only a
``PF-SIGN-TOOL-{SCHEMA,IO,SIGN,VERIFY}`` code and a fixed detail and leaves
no output file behind.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import stat
import sys
from pathlib import Path
from types import ModuleType
from typing import NoReturn, Optional, Tuple


def _load_bootstrap_task_producers() -> ModuleType:
    """Load the exact sibling producer module without a sys.path authority seam."""
    tool_path = Path(__file__).resolve(strict=True)
    producer_path = tool_path.with_name("bootstrap_task_producers.py")
    spec = importlib.util.spec_from_file_location(
        "proof_forge_bootstrap_task_producers_for_sign_tool",
        producer_path,
    )
    if spec is None or spec.loader is None or spec.origin is None:
        raise ImportError("exact bootstrap task producer loader is unavailable")
    if Path(spec.origin).resolve(strict=True) != producer_path.resolve(strict=True):
        raise ImportError("exact bootstrap task producer origin changed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for name in ("sign_ed25519", "_CONSUMER") + tuple(
        f"produce_{suffix}" for suffix in (
            "bootstrap_authority_policy",
            "required_test_set",
            "task_approval",
            "bootstrap_task_verifier_receipt",
            "bootstrap_approval_set",
            "bootstrap_approval_verifier_receipt",
            "formal_gate_catalog_approval",
        )
    ):
        if getattr(module, name, None) is None:
            raise ImportError("exact bootstrap task producer ABI changed")
    return module


_PRODUCER = _load_bootstrap_task_producers()
_CONSUMER = _PRODUCER._CONSUMER

Digest = _CONSUMER.Digest
ContentRef = _CONSUMER.ContentRef

MAX_SPEC_BYTES = 4 * 1024 * 1024
MAX_SEED_FILE_BYTES = 66

_DIGEST_DOMAINS = {
    "sign-authority-policy": b"pf.bootstrap-authority-policy.v1\x00",
    "sign-required-test-set": b"pf.required-test-set.v1\x00",
    "sign-task-approval": b"pf.bootstrap-task-approval.v1\x00",
    "sign-task-receipt": b"pf.bootstrap-task-verifier-receipt.v1\x00",
    "sign-approval-set": b"pf.bootstrap-approval-set.v1\x00",
    "sign-activation-receipt": (
        b"pf.bootstrap-approval-verifier-receipt.v1\x00"
    ),
    "sign-catalog-approval": b"pf.formal-gate-catalog-approval.v1\x00",
}
SUBCOMMANDS = tuple(_DIGEST_DOMAINS)

_FIELDS_KEYS = {
    "sign-authority-policy": (
        "id",
        "version",
        "principals",
        "taskRules",
        "requiredTestSetRule",
        "formalCatalogRule",
        "bootstrapSetRule",
        "sessionContainmentRule",
        "freshnessAuthorityRule",
        "privateScanRule",
        "privateScanPolicy",
        "revocationSnapshotRule",
        "authorityStoreService",
        "verifier",
    ),
    "sign-required-test-set": (
        "id",
        "version",
        "phase5Document",
        "authorityPolicy",
        "requiredTestIds",
    ),
    "sign-task-approval": (
        "taskId",
        "candidate",
        "taskBreakdown",
        "requiredTestSet",
        "testIds",
        "evidence",
        "dependencyCompletions",
        "prerequisiteDocuments",
        "authorityPolicy",
        "stage0Handoff",
        "independentReviews",
    ),
    "sign-task-receipt": (
        "id",
        "taskId",
        "candidate",
        "authorityPolicy",
        "requiredTestSet",
        "taskApproval",
        "stage0Handoff",
        "dependencyCompletions",
        "verifierDigest",
    ),
    "sign-approval-set": (
        "id",
        "version",
        "candidate",
        "authorityPolicy",
        "taskBreakdown",
        "requiredTestSet",
        "stage0Handoff",
        "taskApprovalsHex",
        "taskReceipts",
    ),
    "sign-activation-receipt": (
        "id",
        "candidate",
        "authorityPolicy",
        "requiredTestSet",
        "approvalSet",
        "stage0Handoff",
        "verifierDigest",
        "taskApprovals",
        "taskReceipts",
    ),
    "sign-catalog-approval": (
        "id",
        "version",
        "authorityPolicy",
        "requiredTestSet",
        "catalog",
    ),
}
_INPUTS_KEYS = {
    "sign-authority-policy": (),
    "sign-required-test-set": ("authorityPolicyBytesHex",),
    "sign-task-approval": (
        "requiredTestSetBytesHex",
        "authorityPolicyBytesHex",
        "phase5Snapshot",
    ),
    "sign-task-receipt": (
        "taskApprovalBytesHex",
        "requiredTestSetBytesHex",
        "authorityPolicyBytesHex",
        "phase5Snapshot",
        "stage0HandoffBytesHex",
    ),
    "sign-approval-set": (
        "taskReceiptBytesHex",
        "requiredTestSetBytesHex",
        "authorityPolicyBytesHex",
        "phase5Snapshot",
        "stage0HandoffBytesHex",
    ),
    "sign-activation-receipt": (
        "approvalSetBytesHex",
        "taskReceiptBytesHex",
        "requiredTestSetBytesHex",
        "authorityPolicyBytesHex",
        "phase5Snapshot",
        "stage0HandoffBytesHex",
    ),
    "sign-catalog-approval": (
        "authorityPolicyBytesHex",
        "catalogBytesHex",
        "requiredTestSetBytesHex",
    ),
}
_SINGLE_SIGNER_SUBCOMMANDS = ("sign-task-receipt", "sign-activation-receipt")
_UNSIGNED_SUBCOMMANDS = ("sign-authority-policy",)


class SignToolError(Exception):
    """Stable ceremony failure; never carries key material."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise SignToolError(code, detail)


def _schema(detail: str) -> NoReturn:
    _fail("PF-SIGN-TOOL-SCHEMA", detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-SIGN-TOOL-IO", detail)


def _sign(detail: str) -> NoReturn:
    _fail("PF-SIGN-TOOL-SIGN", detail)


def _verify(detail: str) -> NoReturn:
    _fail("PF-SIGN-TOOL-VERIFY", detail)


def _consumer_checked(validation, code: str, detail: str):
    try:
        return validation()
    except _CONSUMER.Rejected:
        _fail(code, detail)
    except (TypeError, ValueError, AttributeError, IndexError, KeyError):
        _fail(code, detail)


def _require_closed(value: object, fields: Tuple[str, ...], where: str) -> dict:
    if type(value) is not dict:
        _schema(f"{where} must be a closed object")
    assert isinstance(value, dict)
    if set(value.keys()) != set(fields):
        _schema(f"{where} must contain exactly {fields}")
    return value


def _require_text(value: object, where: str) -> str:
    if type(value) is not str or not value:
        _schema(f"{where} must be non-empty text")
    assert isinstance(value, str)
    return value


def _require_text_list(value: object, where: str) -> Tuple[str, ...]:
    if type(value) is not list or any(type(item) is not str for item in value):
        _schema(f"{where} must be an array of text")
    assert isinstance(value, list)
    return tuple(value)


def _require_hex_bytes(value: object, where: str) -> bytes:
    if type(value) is not str or not value or len(value) % 2 != 0:
        _schema(f"{where} must be non-empty even-length hex")
    assert isinstance(value, str)
    if any(character not in "0123456789abcdef" for character in value):
        _schema(f"{where} must be lowercase hex")
    decoded = bytes.fromhex(value)
    if len(decoded) > MAX_SPEC_BYTES:
        _schema(f"{where} exceeds the input maximum")
    return decoded


def _map_digest(value: object, where: str) -> Digest:
    return _consumer_checked(
        lambda: _CONSUMER.parse_digest(value),
        "PF-SIGN-TOOL-SCHEMA",
        f"{where} must be the SPEC-COMMON Digest wire form",
    )


def _map_content_ref(value: object, schema: str, where: str) -> ContentRef:
    obj = _require_closed(value, ("id", "version", "digest"), where)
    return ContentRef(
        schema,
        _consumer_checked(
            lambda: _CONSUMER._require_ascii_text(
                obj["id"], _CONSUMER.PROFILE_ID_RE, f"{where}.id", 127
            ),
            "PF-SIGN-TOOL-SCHEMA",
            f"{where}.id must use the ContentRef id grammar",
        ),
        _consumer_checked(
            lambda: _CONSUMER._require_semver(obj["version"], f"{where}.version"),
            "PF-SIGN-TOOL-SCHEMA",
            f"{where}.version must be exact SemVer",
        ),
        _map_digest(obj["digest"], f"{where}.digest"),
    )


def _map_candidate(value: object, where: str) -> object:
    obj = _require_closed(
        value, ("commit", "treeObjectId", "archiveDigest"), where
    )
    wire = {
        "commit": obj["commit"],
        "treeObjectId": obj["treeObjectId"],
        "archiveDigest": obj["archiveDigest"],
    }
    digest = hashlib.sha256(
        b"pf.candidate-identity.v1\x00" + _CONSUMER.canonical_pf_jcs(wire)
    ).digest()
    return _consumer_checked(
        lambda: _CONSUMER.parse_candidate_identity(
            {**wire, "digest": "sha256:" + digest.hex()}
        ),
        "PF-SIGN-TOOL-SCHEMA",
        f"{where} is not a valid CandidateIdentity",
    )


def _map_normative_document(value: object, where: str) -> object:
    obj = _require_closed(
        value,
        (
            "id",
            "contentDigest",
            "status",
            "reviewCommit",
            "reviewLink",
            "approvedAt",
            "approvers",
        ),
        where,
    )
    return _CONSUMER.NormativeDocumentRefV1(
        _require_text(obj["id"], f"{where}.id"),
        _map_digest(obj["contentDigest"], f"{where}.contentDigest"),
        _require_text(obj["status"], f"{where}.status"),
        _require_text(obj["reviewCommit"], f"{where}.reviewCommit"),
        _require_text(obj["reviewLink"], f"{where}.reviewLink"),
        _require_text(obj["approvedAt"], f"{where}.approvedAt"),
        _require_text_list(obj["approvers"], f"{where}.approvers"),
    )


def _map_approval_rule(value: object, where: str) -> object:
    obj = _require_closed(
        value, ("requiredRoles", "minimumDistinctSigners"), where
    )
    minimum = obj["minimumDistinctSigners"]
    if type(minimum) is not int:
        _schema(f"{where}.minimumDistinctSigners must be an integer")
    return _CONSUMER.ApprovalRuleV1(
        _require_text_list(obj["requiredRoles"], f"{where}.requiredRoles"),
        minimum,
    )


def _map_principal(value: object, where: str) -> object:
    obj = _require_closed(
        value, ("principalId", "keyId", "publicKey", "roles"), where
    )
    public_key = _require_hex_bytes(obj["publicKey"], f"{where}.publicKey")
    if len(public_key) != 32:
        _schema(f"{where}.publicKey must be 32 bytes")
    return _CONSUMER.BootstrapAuthorityPrincipalV1(
        _require_text(obj["principalId"], f"{where}.principalId"),
        _require_text(obj["keyId"], f"{where}.keyId"),
        public_key,
        _require_text_list(obj["roles"], f"{where}.roles"),
    )


def _map_task_rule(value: object, where: str) -> object:
    obj = _require_closed(value, ("taskId", "rule"), where)
    return _CONSUMER.BootstrapAuthorityTaskRuleV1(
        _require_text(obj["taskId"], f"{where}.taskId"),
        _map_approval_rule(obj["rule"], f"{where}.rule"),
    )


def _map_verifier(value: object, where: str) -> object:
    obj = _require_closed(
        value,
        ("id", "executableDigest", "receiptKeyId", "receiptPublicKey"),
        where,
    )
    public_key = _require_hex_bytes(
        obj["receiptPublicKey"], f"{where}.receiptPublicKey"
    )
    if len(public_key) != 32:
        _schema(f"{where}.receiptPublicKey must be 32 bytes")
    return _CONSUMER.BootstrapAuthorityVerifierV1(
        _require_text(obj["id"], f"{where}.id"),
        _map_digest(obj["executableDigest"], f"{where}.executableDigest"),
        _require_text(obj["receiptKeyId"], f"{where}.receiptKeyId"),
        public_key,
    )


def _map_evidence_ref(value: object, where: str) -> object:
    obj = _require_closed(value, ("id", "digest"), where)
    return _CONSUMER.EvidenceRef(
        _require_text(obj["id"], f"{where}.id"),
        _map_digest(obj["digest"], f"{where}.digest"),
    )


def _map_task_approval_ref(value: object, where: str) -> object:
    obj = _require_closed(value, ("taskId", "digest"), where)
    return _CONSUMER.TaskApprovalRefV1(
        _require_text(obj["taskId"], f"{where}.taskId"),
        _map_digest(obj["digest"], f"{where}.digest"),
    )


def _map_receipt_ref(value: object, where: str) -> object:
    obj = _require_closed(value, ("taskId", "id", "digest"), where)
    return _CONSUMER.BootstrapTaskVerifierReceiptRefV1(
        _require_text(obj["taskId"], f"{where}.taskId"),
        _require_text(obj["id"], f"{where}.id"),
        _map_digest(obj["digest"], f"{where}.digest"),
    )


def _map_independent_review(value: object, where: str) -> object:
    obj = _require_closed(
        value,
        (
            "keyId",
            "role",
            "reviewCommit",
            "reviewLink",
            "reportDigest",
            "decision",
        ),
        where,
    )
    return _CONSUMER.IndependentReviewRefV1(
        _require_text(obj["keyId"], f"{where}.keyId"),
        _require_text(obj["role"], f"{where}.role"),
        _require_text(obj["reviewCommit"], f"{where}.reviewCommit"),
        _require_text(obj["reviewLink"], f"{where}.reviewLink"),
        _map_digest(obj["reportDigest"], f"{where}.reportDigest"),
        _require_text(obj["decision"], f"{where}.decision"),
    )


def _map_catalog_ref(value: object, where: str) -> object:
    obj = _require_closed(
        value, ("id", "version", "contentSha256", "catalogDigest"), where
    )
    content_sha256 = _require_hex_bytes(
        obj["contentSha256"], f"{where}.contentSha256"
    )
    catalog_digest = _require_hex_bytes(
        obj["catalogDigest"], f"{where}.catalogDigest"
    )
    if len(content_sha256) != 32 or len(catalog_digest) != 32:
        _schema(f"{where} hashes must be 32 bytes")
    return _CONSUMER.GateCatalogRefV1(
        "proof-forge.gate-catalog.v1",
        _require_text(obj["id"], f"{where}.id"),
        _require_text(obj["version"], f"{where}.version"),
        content_sha256.hex(),
        catalog_digest.hex(),
    )


def _map_snapshot(value: object, where: str) -> object:
    obj = _require_closed(value, ("id", "path", "bytesHex"), where)
    return _CONSUMER.BootstrapDocumentSnapshotV1(
        id=_require_text(obj["id"], f"{where}.id"),
        path=_require_text(obj["path"], f"{where}.path"),
        bytes=_require_hex_bytes(obj["bytesHex"], f"{where}.bytesHex"),
    )


def _map_ref_list(value: object, mapper, where: str) -> tuple:
    if type(value) is not list:
        _schema(f"{where} must be an array")
    assert isinstance(value, list)
    return tuple(
        mapper(item, f"{where}[{index}]") for index, item in enumerate(value)
    )


def _read_spec(path: str) -> dict:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        _io(f"cannot open the spec file: {error}")
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            _io("spec path is not a regular file")
        chunks = []
        offset = 0
        while True:
            chunk = os.pread(fd, 65536, offset)
            if not chunk:
                break
            chunks.append(chunk)
            offset += len(chunk)
            if offset > MAX_SPEC_BYTES:
                _io("spec file exceeds the input maximum")
        raw = b"".join(chunks)
    finally:
        os.close(fd)

    def reject_duplicates(pairs: list) -> dict:
        result = {}
        for key, item in pairs:
            if key in result:
                _schema("spec contains a duplicate JSON object key")
            result[key] = item
        return result

    try:
        parsed = json.loads(
            raw.decode("utf-8", errors="strict"),
            object_pairs_hook=reject_duplicates,
            parse_float=lambda text: _schema("spec must not contain floats"),
            parse_constant=lambda text: _schema("spec constant is forbidden"),
        )
    except UnicodeError:
        _schema("spec is not strict UTF-8")
    except json.JSONDecodeError:
        _schema("spec is not valid JSON")
    if type(parsed) is not dict:
        _schema("spec root must be a closed object")
    assert isinstance(parsed, dict)
    return parsed


def read_seed_file(path: str) -> bytes:
    """Safe-open and parse a ceremony seed file, scrubbing the read buffer."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        _io(f"cannot open the seed file: {error}")
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            _io("seed path is not a regular file")
        if metadata.st_nlink != 1:
            _io("seed file must have exactly one link")
        if stat.S_IMODE(metadata.st_mode) & 0o377 != 0:
            _io("seed file mode must not exceed 0400")
        if not 1 <= metadata.st_size <= MAX_SEED_FILE_BYTES:
            _io("seed file must contain a 32-byte seed or its 64-hex form")
        buffer = bytearray(os.pread(fd, metadata.st_size, 0))
    finally:
        os.close(fd)
    try:
        if len(buffer) == 32:
            return bytes(buffer)
        text = bytes(buffer)
        if text.endswith(b"\n"):
            text = text[:-1]
        if len(text) == 64 and all(
            character in b"0123456789abcdef" for character in text
        ):
            return bytes.fromhex(text.decode("ascii"))
        _schema("seed file must be 32 raw bytes or 64 lowercase hex")
    finally:
        for index in range(len(buffer)):
            buffer[index] = 0
    raise AssertionError("unreachable")


def _resolve_signers(
    subcommand: str,
    spec: dict,
    seed_file: Optional[str],
    key_id: Optional[str],
) -> Tuple[Tuple[str, bytes], ...]:
    if subcommand in _UNSIGNED_SUBCOMMANDS:
        if seed_file is not None or key_id is not None:
            _schema(f"{subcommand} does not accept signing material")
        return ()
    signer_entries = spec.get("signers")
    single_entry = spec.get("signer")
    if subcommand in _SINGLE_SIGNER_SUBCOMMANDS:
        if signer_entries is not None:
            _schema(f"{subcommand} uses the singular signer entry")
    elif single_entry is not None:
        _schema(f"{subcommand} uses the signers array")
    if seed_file is not None and (signer_entries or single_entry):
        _schema("signing material must come from exactly one source")
    if seed_file is not None:
        if key_id is None:
            _schema("--key-id is required with --seed-file")
        return ((key_id, read_seed_file(seed_file)),)
    entries = single_entry if single_entry is not None else signer_entries
    if entries is None:
        _schema("spec must carry signing material or use --seed-file")
    if type(entries) is dict:
        entries = [entries]
    if type(entries) is not list or not entries:
        _schema("signers must be a non-empty array")
    pairs = []
    for index, entry in enumerate(entries):
        obj = _require_closed(entry, ("keyId", "seedFile"), f"signers[{index}]")
        entry_key_id = _require_text(obj["keyId"], f"signers[{index}].keyId")
        if key_id is not None:
            entry_key_id = key_id
        seed_path = _require_text(obj["seedFile"], f"signers[{index}].seedFile")
        pairs.append((entry_key_id, read_seed_file(seed_path)))
    if key_id is not None and len(pairs) > 1:
        _schema("--key-id override applies to a single signer only")
    return tuple(pairs)


def _write_output(path: str, payload: bytes) -> None:
    directory = os.path.dirname(path) or "."
    final_name = os.path.basename(path)
    temp_name = f".{final_name}.tmp-{os.getpid()}"
    temp_path = os.path.join(directory, temp_name)
    try:
        fd = os.open(
            temp_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o444,
        )
    except OSError as error:
        _io(f"cannot create the output temp file: {error}")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.chmod(temp_path, 0o444)
            os.link(temp_path, path)
        except FileExistsError:
            _io("output path already exists (no-clobber)")
        except OSError as error:
            _io(f"cannot link the output into place: {error}")
        directory_fd = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        try:
            os.unlink(temp_path)
        except OSError:
            pass


def _signing_pairs_for_producer(
    subcommand: str,
    pairs: Tuple[Tuple[str, bytes], ...],
) -> object:
    if subcommand in _SINGLE_SIGNER_SUBCOMMANDS:
        if len(pairs) != 1:
            _sign(f"{subcommand} requires exactly one signer")
        return pairs[0]
    return pairs


def _object_identifier(subcommand: str, fields: dict) -> str:
    if subcommand == "sign-task-approval":
        return fields["taskId"]
    return fields["id"]


def run_subcommand(
    subcommand: str,
    spec: dict,
    seed_file: Optional[str],
    key_id: Optional[str],
) -> Tuple[bytes, str]:
    """Produce and fully re-verify one signed object; return (bytes, id)."""
    fields = _require_closed(
        spec.get("fields"), _FIELDS_KEYS[subcommand], "fields"
    )
    inputs = _require_closed(
        spec.get("inputs", {}), _INPUTS_KEYS[subcommand], "inputs"
    )
    pairs = _resolve_signers(subcommand, spec, seed_file, key_id)
    signer_argument = _signing_pairs_for_producer(subcommand, pairs)
    policy_bytes = (
        _require_hex_bytes(inputs["authorityPolicyBytesHex"], "inputs.authorityPolicyBytesHex")
        if "authorityPolicyBytesHex" in inputs
        else None
    )
    required_bytes = (
        _require_hex_bytes(inputs["requiredTestSetBytesHex"], "inputs.requiredTestSetBytesHex")
        if "requiredTestSetBytesHex" in inputs
        else None
    )
    snapshot = (
        _map_snapshot(inputs["phase5Snapshot"], "inputs.phase5Snapshot")
        if "phase5Snapshot" in inputs
        else None
    )
    handoff_bytes = (
        _require_hex_bytes(inputs["stage0HandoffBytesHex"], "inputs.stage0HandoffBytesHex")
        if "stage0HandoffBytesHex" in inputs
        else None
    )

    try:
        produced = _produce(subcommand, fields, inputs, pairs, signer_argument,
                            policy_bytes, required_bytes)
    except SignToolError:
        raise
    except _CONSUMER.Rejected:
        _sign(f"{subcommand} construction validation failed")
    except (TypeError, ValueError, AttributeError, IndexError, KeyError):
        _sign(f"{subcommand} construction input is invalid")

    _verify_produced(
        subcommand,
        produced,
        inputs,
        policy_bytes,
        required_bytes,
        snapshot,
        handoff_bytes,
    )
    return produced, _object_identifier(subcommand, fields)


def _produce(
    subcommand: str,
    fields: dict,
    inputs: dict,
    pairs: Tuple[Tuple[str, bytes], ...],
    signer_argument: object,
    policy_bytes: Optional[bytes],
    required_bytes: Optional[bytes],
) -> bytes:
    producer = _PRODUCER
    if subcommand == "sign-authority-policy":
        return producer.produce_bootstrap_authority_policy(
            id=fields["id"],
            version=fields["version"],
            principals=_map_ref_list(fields["principals"], _map_principal, "fields.principals"),
            taskRules=_map_ref_list(fields["taskRules"], _map_task_rule, "fields.taskRules"),
            requiredTestSetRule=_map_approval_rule(fields["requiredTestSetRule"], "fields.requiredTestSetRule"),
            formalCatalogRule=_map_approval_rule(fields["formalCatalogRule"], "fields.formalCatalogRule"),
            bootstrapSetRule=_map_approval_rule(fields["bootstrapSetRule"], "fields.bootstrapSetRule"),
            sessionContainmentRule=_map_approval_rule(fields["sessionContainmentRule"], "fields.sessionContainmentRule"),
            freshnessAuthorityRule=_map_approval_rule(fields["freshnessAuthorityRule"], "fields.freshnessAuthorityRule"),
            privateScanRule=_map_approval_rule(fields["privateScanRule"], "fields.privateScanRule"),
            privateScanPolicy=_map_content_ref(fields["privateScanPolicy"], "proof-forge.private-scan-policy.v1", "fields.privateScanPolicy"),
            revocationSnapshotRule=_map_approval_rule(fields["revocationSnapshotRule"], "fields.revocationSnapshotRule"),
            authorityStoreService=_map_content_ref(fields["authorityStoreService"], "proof-forge.authority-store-service.v1", "fields.authorityStoreService"),
            verifier=_map_verifier(fields["verifier"], "fields.verifier"),
        )
    if subcommand == "sign-required-test-set":
        return producer.produce_required_test_set(
            id=fields["id"],
            version=fields["version"],
            phase5Document=_map_normative_document(fields["phase5Document"], "fields.phase5Document"),
            authorityPolicy=_map_content_ref(fields["authorityPolicy"], "proof-forge.bootstrap-authority-policy.v1", "fields.authorityPolicy"),
            requiredTestIds=_require_text_list(fields["requiredTestIds"], "fields.requiredTestIds"),
            signers=pairs,
            authority_policy_bytes=policy_bytes,
        )
    if subcommand == "sign-task-approval":
        return producer.produce_task_approval(
            taskId=fields["taskId"],
            candidate=_map_candidate(fields["candidate"], "fields.candidate"),
            taskBreakdown=_map_normative_document(fields["taskBreakdown"], "fields.taskBreakdown"),
            requiredTestSet=_map_content_ref(fields["requiredTestSet"], "proof-forge.required-test-set.v1", "fields.requiredTestSet"),
            testIds=_require_text_list(fields["testIds"], "fields.testIds"),
            evidence=_map_ref_list(fields["evidence"], _map_evidence_ref, "fields.evidence"),
            dependencyCompletions=_map_ref_list(fields["dependencyCompletions"], _map_receipt_ref, "fields.dependencyCompletions"),
            prerequisiteDocuments=_map_ref_list(fields["prerequisiteDocuments"], _map_normative_document, "fields.prerequisiteDocuments"),
            authorityPolicy=_map_content_ref(fields["authorityPolicy"], "proof-forge.bootstrap-authority-policy.v1", "fields.authorityPolicy"),
            stage0Handoff=_map_content_ref(fields["stage0Handoff"], "proof-forge.eligible-stage0-handoff.v1", "fields.stage0Handoff"),
            independentReviews=_map_ref_list(fields["independentReviews"], _map_independent_review, "fields.independentReviews"),
            signers=pairs,
        )
    if subcommand == "sign-task-receipt":
        return producer.produce_bootstrap_task_verifier_receipt(
            id=fields["id"],
            taskId=fields["taskId"],
            candidate=_map_candidate(fields["candidate"], "fields.candidate"),
            authorityPolicy=_map_content_ref(fields["authorityPolicy"], "proof-forge.bootstrap-authority-policy.v1", "fields.authorityPolicy"),
            requiredTestSet=_map_content_ref(fields["requiredTestSet"], "proof-forge.required-test-set.v1", "fields.requiredTestSet"),
            taskApproval=_map_task_approval_ref(fields["taskApproval"], "fields.taskApproval"),
            stage0Handoff=_map_content_ref(fields["stage0Handoff"], "proof-forge.eligible-stage0-handoff.v1", "fields.stage0Handoff"),
            dependencyCompletions=_map_ref_list(fields["dependencyCompletions"], _map_receipt_ref, "fields.dependencyCompletions"),
            verifierDigest=_map_digest(fields["verifierDigest"], "fields.verifierDigest"),
            signer=signer_argument,
        )
    if subcommand == "sign-approval-set":
        approval_bytes_list = _map_ref_list(
            fields["taskApprovalsHex"], _require_hex_bytes, "fields.taskApprovalsHex"
        )
        approvals = tuple(
            _consumer_checked(
                lambda approval_bytes=approval_bytes: _CONSUMER.parse_task_approval(
                    approval_bytes,
                    required_bytes,
                    policy_bytes,
                    _map_snapshot(inputs["phase5Snapshot"], "inputs.phase5Snapshot"),
                )[0],
                "PF-SIGN-TOOL-SCHEMA",
                "fields.taskApprovalsHex entries must be valid signed approvals",
            )
            for approval_bytes in approval_bytes_list
        )
        return producer.produce_bootstrap_approval_set(
            id=fields["id"],
            version=fields["version"],
            candidate=_map_candidate(fields["candidate"], "fields.candidate"),
            authorityPolicy=_map_content_ref(fields["authorityPolicy"], "proof-forge.bootstrap-authority-policy.v1", "fields.authorityPolicy"),
            taskBreakdown=_map_normative_document(fields["taskBreakdown"], "fields.taskBreakdown"),
            requiredTestSet=_map_content_ref(fields["requiredTestSet"], "proof-forge.required-test-set.v1", "fields.requiredTestSet"),
            stage0Handoff=_map_content_ref(fields["stage0Handoff"], "proof-forge.eligible-stage0-handoff.v1", "fields.stage0Handoff"),
            taskApprovals=approvals,
            taskReceipts=_map_ref_list(fields["taskReceipts"], _map_receipt_ref, "fields.taskReceipts"),
            signers=pairs,
        )
    if subcommand == "sign-activation-receipt":
        return producer.produce_bootstrap_approval_verifier_receipt(
            id=fields["id"],
            candidate=_map_candidate(fields["candidate"], "fields.candidate"),
            authorityPolicy=_map_content_ref(fields["authorityPolicy"], "proof-forge.bootstrap-authority-policy.v1", "fields.authorityPolicy"),
            requiredTestSet=_map_content_ref(fields["requiredTestSet"], "proof-forge.required-test-set.v1", "fields.requiredTestSet"),
            approvalSet=_map_content_ref(fields["approvalSet"], "proof-forge.bootstrap-approval-set.v1", "fields.approvalSet"),
            stage0Handoff=_map_content_ref(fields["stage0Handoff"], "proof-forge.eligible-stage0-handoff.v1", "fields.stage0Handoff"),
            verifierDigest=_map_digest(fields["verifierDigest"], "fields.verifierDigest"),
            taskApprovals=_map_ref_list(fields["taskApprovals"], _map_task_approval_ref, "fields.taskApprovals"),
            taskReceipts=_map_ref_list(fields["taskReceipts"], _map_receipt_ref, "fields.taskReceipts"),
            signer=signer_argument,
        )
    if subcommand == "sign-catalog-approval":
        return producer.produce_formal_gate_catalog_approval(
            id=fields["id"],
            version=fields["version"],
            authorityPolicy=_map_content_ref(fields["authorityPolicy"], "proof-forge.bootstrap-authority-policy.v1", "fields.authorityPolicy"),
            requiredTestSet=_map_content_ref(fields["requiredTestSet"], "proof-forge.required-test-set.v1", "fields.requiredTestSet"),
            catalog=_map_catalog_ref(fields["catalog"], "fields.catalog"),
            signers=pairs,
            authority_policy_bytes=policy_bytes,
        )
    _schema(f"unknown subcommand {subcommand}")


def _verify_produced(
    subcommand: str,
    produced: bytes,
    inputs: dict,
    policy_bytes: Optional[bytes],
    required_bytes: Optional[bytes],
    snapshot: Optional[object],
    handoff_bytes: Optional[bytes],
) -> None:
    consumer = _CONSUMER

    def verified(validation):
        return _consumer_checked(
            validation,
            "PF-SIGN-TOOL-VERIFY",
            f"{subcommand} full re-verification failed",
        )

    if subcommand == "sign-authority-policy":
        verified(lambda: consumer.parse_bootstrap_authority_policy(produced))
    elif subcommand == "sign-required-test-set":
        verified(lambda: consumer.parse_required_test_set(produced, policy_bytes))
    elif subcommand == "sign-task-approval":
        verified(lambda: consumer.parse_task_approval(
            produced, required_bytes, policy_bytes, snapshot
        ))
    elif subcommand == "sign-task-receipt":
        verified(lambda: consumer.parse_bootstrap_task_verifier_receipt(
            produced,
            _require_hex_bytes(inputs["taskApprovalBytesHex"], "inputs.taskApprovalBytesHex"),
            required_bytes,
            policy_bytes,
            snapshot,
            handoff_bytes,
        ))
    elif subcommand == "sign-approval-set":
        verified(lambda: consumer.parse_bootstrap_approval_set(
            produced,
            tuple(
                _require_hex_bytes(item, "inputs.taskReceiptBytesHex")
                for item in inputs["taskReceiptBytesHex"]
            ),
            required_bytes,
            policy_bytes,
            snapshot,
            handoff_bytes,
        ))
    elif subcommand == "sign-activation-receipt":
        verified(lambda: consumer.parse_bootstrap_approval_verifier_receipt(
            produced,
            _require_hex_bytes(inputs["approvalSetBytesHex"], "inputs.approvalSetBytesHex"),
            tuple(
                _require_hex_bytes(item, "inputs.taskReceiptBytesHex")
                for item in inputs["taskReceiptBytesHex"]
            ),
            required_bytes,
            policy_bytes,
            snapshot,
            handoff_bytes,
        ))
    elif subcommand == "sign-catalog-approval":
        verified(lambda: consumer.parse_formal_gate_catalog_approval(
            produced,
            _require_hex_bytes(inputs["catalogBytesHex"], "inputs.catalogBytesHex"),
            required_bytes,
            policy_bytes,
        ))


_USAGE = (
    "usage: bootstrap_sign_tool.py <subcommand> --spec <spec.json> "
    "--output <path> [--seed-file <path> --key-id <safe-id>]\n"
    "subcommands: " + " ".join(SUBCOMMANDS)
)


def main(argv: Optional[Tuple[str, ...]] = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] not in SUBCOMMANDS:
        print(_USAGE, file=sys.stderr)
        return 2
    subcommand = args[0]
    options = {"--spec": None, "--output": None, "--seed-file": None, "--key-id": None}
    index = 1
    while index < len(args):
        flag = args[index]
        if flag not in options or index + 1 >= len(args):
            print(_USAGE, file=sys.stderr)
            return 2
        if options[flag] is not None:
            print(_USAGE, file=sys.stderr)
            return 2
        options[flag] = args[index + 1]
        index += 2
    if options["--spec"] is None or options["--output"] is None:
        print(_USAGE, file=sys.stderr)
        return 2
    if options["--seed-file"] is not None and options["--key-id"] is None:
        print(_USAGE, file=sys.stderr)
        return 2
    try:
        spec = _read_spec(options["--spec"])
        produced, identifier = run_subcommand(
            subcommand,
            spec,
            options["--seed-file"],
            options["--key-id"],
        )
        digest = hashlib.sha256(_DIGEST_DOMAINS[subcommand] + produced).hexdigest()
        _write_output(options["--output"], produced)
        print(f"signed: {identifier} sha256:{digest}")
        return 0
    except SignToolError as error:
        print(f"{error.code}: {error.detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

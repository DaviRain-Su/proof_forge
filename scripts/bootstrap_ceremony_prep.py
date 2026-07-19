#!/usr/bin/env python3
"""Bootstrap ceremony preparation (TASK-D0-04 closure path).

Generates the authority-policy signing spec, the authority-store service
descriptor, the private-scan policy document, and (after the policy is signed)
the required-test-set spec.  All derivable digests are recomputed from the
committed files; public keys are derived from caller-provided seed files with
the same custody discipline as `bootstrap_sign_tool.py` (seeds are only read
from explicit paths, never echoed, never persisted into outputs).

Run with: /usr/bin/python3 -I -S scripts/bootstrap_ceremony_prep.py <init|stage> ...

This tool does not sign anything and does not read, generate, or persist any
private key beyond deriving public keys in memory.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import secrets
import stat
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

PRODUCERS_PATH = REPO_ROOT / "scripts" / "bootstrap_task_producers.py"
CONSUMER_PATH = REPO_ROOT / "scripts" / "bootstrap_task_objects.py"

POLICY_SCHEMA = "proof-forge.bootstrap-authority-policy.v1"
DESCRIPTOR_SCHEMA = "proof-forge.authority-store-service.v1"
SCAN_POLICY_SCHEMA = "proof-forge.private-scan-policy.v1"
DESCRIPTOR_DOMAIN = b"pf.authority-store-service.v1\x00"
SCAN_POLICY_DOMAIN = b"pf.private-scan-policy.v1\x00"
POLICY_DOMAIN = b"pf.bootstrap-authority-policy.v1\x00"
REQUIRED_SET_SCHEMA = "proof-forge.required-test-set.v1"

SIGN_TOOL_PATH = REPO_ROOT / "scripts" / "bootstrap_sign_tool.py"

ROLES = ("architecture", "quality", "security", "release")
_APPROVAL_ROLE_INDEX = {role: index for index, role in enumerate(ROLES)}
PRINCIPAL_KEY_ORDER = ("architecture", "quality", "release", "security")
SEED_FILES = {
    "architecture": "architecture.seed",
    "quality": "quality.seed",
    "release": "release.seed",
    "security": "security.seed",
    "service": "service.seed",
    "verifier-receipt": "verifier-receipt.seed",
}

TASK_RULE_MINIMUMS = {
    "TASK-D0-01": (("architecture", "quality"), 2),
    "TASK-D0-02": (("architecture", "quality"), 2),
    "TASK-D0-03": (("quality", "security"), 2),
    "TASK-D0-04": (("quality", "security", "release"), 3),
    "TASK-D0-05": (("quality", "security"), 2),
    "TASK-D0-06": (("architecture", "quality"), 2),
}
GLOBAL_RULE_MINIMUM = 2
SET_RULE_MINIMUM = 3

GENESIS_REQUIRED_TEST_IDS = (
    "TST-BOOTSTRAP-001",
    "TST-COMMON-001",
    "TST-DOC-001",
    "TST-EVIDENCE-001",
    "TST-HOST-001",
    "TST-ISO-001",
    "TST-SBOM-001",
    "TST-SBOM-002",
    "TST-HOST-002",
)

STORE_SERVICE_SCRIPT = "scripts/stage0_store_service.py"
ACTIVATION_DRIVER_SCRIPT = "scripts/stage0_activate.py"
MAX_FRAME_BYTES = 4194304

_HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
_SAFE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:+-]{0,255}$")


class PrepError(Exception):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


def fail(code: str, detail: str) -> None:
    raise PrepError(code, detail)


def _load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


PRODUCERS = _load_module(PRODUCERS_PATH, "pf_ceremony_producers")
CONSUMER = _load_module(CONSUMER_PATH, "pf_ceremony_consumer")
SIGN_TOOL = _load_module(SIGN_TOOL_PATH, "pf_ceremony_sign_tool")


def read_seed(path: Path) -> bytes:
    """Read a caller-designated seed file with sign-tool custody discipline."""

    try:
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        fail("PF-CEREMONY-IO", f"cannot read seed file {path}: {error.strerror or error}")
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            fail("PF-CEREMONY-IO", f"seed file must be a regular single-link file: {path}")
        if metadata.st_mode & 0o077:
            fail(
                "PF-CEREMONY-IO",
                f"seed file mode must not exceed 0400: {path} (chmod 0400 first)",
            )
        with os.fdopen(fd, "rb", closefd=True) as handle:
            fd = -1
            raw = handle.read(66)
    finally:
        if fd >= 0:
            os.close(fd)
    buffer = bytearray(raw)
    try:
        text = bytes(buffer).decode("ascii", errors="strict").rstrip("\n")
        if _HEX64_RE.fullmatch(text):
            return bytes.fromhex(text)
        if len(buffer) == 32:
            return bytes(buffer)
        fail("PF-CEREMONY-SCHEMA", f"seed file must be 64 lowercase hex or 32 raw bytes: {path}")
    finally:
        for index in range(len(buffer)):
            buffer[index] = 0
    return b""


def public_from_seed(path: Path) -> str:
    return PRODUCERS.ed25519_public_key_from_seed(read_seed(path)).hex()


def canonical(value: object) -> bytes:
    return CONSUMER.canonical_pf_jcs(value)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def domain_digest_hex(domain: bytes, canonical_bytes: bytes) -> str:
    return hashlib.sha256(domain + canonical_bytes).hexdigest()


def content_ref(schema: str, identifier: str, version: str, digest_hex: str) -> dict:
    """Sign-tool spec wire: refs carry id/version/digest; schema is positional."""

    del schema
    return {
        "id": identifier,
        "version": version,
        "digest": "sha256:" + digest_hex,
    }


def repo_file_sha256(relative: str) -> str:
    path = REPO_ROOT / relative
    if not path.is_file():
        fail("PF-CEREMONY-IO", f"required repo file missing: {relative}")
    return sha256_hex(path.read_bytes())


def write_output(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        fail("PF-CEREMONY-IO", f"output already exists: {path}")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o444)
    try:
        with os.fdopen(fd, "wb", closefd=True) as handle:
            fd = -1
            handle.write(json.dumps(payload, indent=2, sort_keys=True).encode("utf-8") + b"\n")
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        if fd >= 0:
            os.close(fd)
    print(f"wrote {path}")


def approval_rule(roles: tuple[str, ...], minimum: int) -> dict:
    return {
        "requiredRoles": sorted(roles, key=_APPROVAL_ROLE_INDEX.__getitem__),
        "minimumDistinctSigners": minimum,
    }


def cmd_init(args: argparse.Namespace) -> int:
    seeds_dir = Path(args.seeds_dir)
    workdir = Path(args.workdir)
    if not seeds_dir.is_dir():
        fail("PF-CEREMONY-IO", f"seeds directory missing: {seeds_dir}")

    public_keys: dict[str, str] = {}
    for name, filename in SEED_FILES.items():
        public_keys[name] = public_from_seed(seeds_dir / filename)

    service_exe_digest = repo_file_sha256(STORE_SERVICE_SCRIPT)
    verifier_exe_digest = repo_file_sha256(ACTIVATION_DRIVER_SCRIPT)

    descriptor = {
        "schema": DESCRIPTOR_SCHEMA,
        "id": args.namespace_id,
        "version": "1.0.0",
        "protocol": "pf.authority-store.rpc.v1",
        "serviceExecutableDigest": "sha256:" + service_exe_digest,
        "servicePublicKey": public_keys["service"],
        "namespaceId": args.namespace_id,
        "maximumFrameBytes": MAX_FRAME_BYTES,
    }
    descriptor_digest = domain_digest_hex(DESCRIPTOR_DOMAIN, canonical(descriptor))

    scan_policy = {
        "schema": SCAN_POLICY_SCHEMA,
        "id": args.scan_policy_id,
        "version": "1.0.0",
        "denyContentMarkers": [
            "BEGIN PRIVATE KEY",
            "BEGIN OPENSSH PRIVATE KEY",
            "BEGIN PGP PRIVATE KEY BLOCK",
            "aws_secret_access_key",
            "xoxb-",
        ],
        "denyPathMarkers": [".env", "id_rsa", "id_ed25519", ".pem", ".p12", ".key"],
        "maximumFindings": 0,
    }
    scan_policy_digest = domain_digest_hex(SCAN_POLICY_DOMAIN, canonical(scan_policy))

    principals = [
        {
            "principalId": f"principal-{role}",
            "keyId": f"key-{role}",
            "publicKey": public_keys[role],
            "roles": [role],
        }
        for role in PRINCIPAL_KEY_ORDER
    ]
    task_rules = [
        {
            "taskId": task_id,
            "rule": approval_rule(roles, minimum),
        }
        for task_id, (roles, minimum) in TASK_RULE_MINIMUMS.items()
    ]
    policy_fields = {
        "id": args.policy_id,
        "version": "1.0.0",
        "principals": principals,
        "taskRules": task_rules,
        "requiredTestSetRule": approval_rule(("quality", "security"), GLOBAL_RULE_MINIMUM),
        "formalCatalogRule": approval_rule(("quality", "security"), GLOBAL_RULE_MINIMUM),
        "bootstrapSetRule": approval_rule(("quality", "release", "security"), SET_RULE_MINIMUM),
        "sessionContainmentRule": approval_rule(("quality", "security"), GLOBAL_RULE_MINIMUM),
        "freshnessAuthorityRule": approval_rule(("quality", "release"), GLOBAL_RULE_MINIMUM),
        "privateScanRule": approval_rule(("quality", "security"), GLOBAL_RULE_MINIMUM),
        "privateScanPolicy": content_ref(
            SCAN_POLICY_SCHEMA, args.scan_policy_id, "1.0.0", scan_policy_digest
        ),
        "revocationSnapshotRule": approval_rule(("release", "security"), GLOBAL_RULE_MINIMUM),
        "authorityStoreService": content_ref(
            DESCRIPTOR_SCHEMA, args.namespace_id, "1.0.0", descriptor_digest
        ),
        "verifier": {
            "id": args.verifier_id,
            "executableDigest": "sha256:" + verifier_exe_digest,
            "receiptKeyId": "key-verifier-receipt",
            "receiptPublicKey": public_keys["verifier-receipt"],
        },
    }
    spec = {"fields": policy_fields, "inputs": {}}

    # validate the policy fields end-to-end through the sign tool's own
    # produce + full re-verification path before writing anything
    produced, _ = SIGN_TOOL.run_subcommand("sign-authority-policy", spec, None, None)
    CONSUMER.parse_bootstrap_authority_policy(produced)

    write_output(workdir / "authority-policy.spec.json", spec)
    write_output(workdir / "private-scan-policy.json", scan_policy)
    write_output(workdir / "service-descriptor.json", descriptor)

    print()
    print("next steps:")
    print(f"  1. produce the (unsigned) genesis authority policy:")
    print(f"     /usr/bin/python3 -I -S scripts/bootstrap_sign_tool.py sign-authority-policy \\")
    print(f"       --spec {workdir / 'authority-policy.spec.json'} \\")
    print(f"       --output {workdir / 'authority-policy.json'}")
    print(f"  2. then run:")
    print(f"     /usr/bin/python3 -I -S scripts/bootstrap_ceremony_prep.py stage \\")
    print(f"       --policy {workdir / 'authority-policy.json'} --workdir {workdir}")
    return 0


def cmd_stage(args: argparse.Namespace) -> int:
    workdir = Path(args.workdir)
    policy_bytes = Path(args.policy).read_bytes()
    _, policy_ref = CONSUMER.parse_bootstrap_authority_policy(policy_bytes)
    policy_digest_hex = policy_ref.digest.bytes.hex()

    required_ids = sorted(GENESIS_REQUIRED_TEST_IDS)
    fields = {
        "id": args.required_set_id,
        "version": "1.0.0",
        "phase5Document": _phase5_document_ref(),
        "authorityPolicy": content_ref(POLICY_SCHEMA, policy_ref.id, policy_ref.version, policy_digest_hex),
        "requiredTestIds": required_ids,
    }
    spec = {
        "fields": fields,
        "inputs": {"authorityPolicyBytesHex": policy_bytes.hex()},
        "signers": [
            {"keyId": "key-quality", "seedFile": "<seeds-dir>/quality.seed"},
            {"keyId": "key-security", "seedFile": "<seeds-dir>/security.seed"},
        ],
    }
    write_output(workdir / "required-test-set.spec.json", spec)
    print()
    print("sign the required test set (two signer seeds, quality+security):")
    print(f"  /usr/bin/python3 -I -S scripts/bootstrap_sign_tool.py sign-required-test-set \\")
    print(f"    --spec {workdir / 'required-test-set.spec.json'} \\")
    print(f"    --output {workdir / 'required-test-set.json'}")
    print("then produce the candidate, the handoff (stage0_activate phase 1),")
    print("sign catalog approval + 6 task approvals + 6 receipts + set + activation receipt,")
    print("and finally run stage0_activate phase 2 with --approvals-dir.")
    return 0


def _phase5_document_ref() -> dict:
    """NormativeDocumentRefV1 for docs/05-test-spec.md (must be accepted)."""

    path = REPO_ROOT / "docs" / "05-test-spec.md"
    text = path.read_text(encoding="utf-8")
    frontmatter = {}
    if text.startswith("---\n"):
        for line in text[4:].split("---", 1)[0].strip().splitlines():
            key, _, value = line.partition(":")
            frontmatter[key.strip()] = value.strip()
    if frontmatter.get("status") != "accepted":
        fail(
            "PF-CEREMONY-PREREQ",
            "docs/05-test-spec.md must be accepted before the real activation "
            "(governance prerequisite: PHASE-5 acceptance)",
        )
    return {
        "id": frontmatter.get("id", "PHASE-5"),
        "contentDigest": "sha256:" + sha256_hex(path.read_bytes()),
        "status": "accepted",
        "reviewCommit": frontmatter["reviewCommit"],
        "reviewLink": frontmatter["reviewLink"],
        "approvedAt": frontmatter["approvedAt"],
        "approvers": sorted(
            item.strip() for item in frontmatter["approvers"].split(",")
        ),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="bootstrap_ceremony_prep.py")
    sub = parser.add_subparsers(dest="command", required=True)

    init = sub.add_parser("init")
    init.add_argument("--seeds-dir", required=True)
    init.add_argument("--workdir", required=True)
    init.add_argument("--policy-id", default="bootstrap-authority-root")
    init.add_argument("--namespace-id", default="bootstrap-authority-store")
    init.add_argument("--scan-policy-id", default="bootstrap-private-scan-policy")
    init.add_argument("--verifier-id", default="bootstrap-task-verifier")
    init.add_argument("--genesis-key-id", default="genesis-root-2026-01")
    init.add_argument("--signer-seed-name", default="architecture",
                      help="seed file key in SEED_FILES used for the self-check throwaway signature")

    stage = sub.add_parser("stage")
    stage.add_argument("--policy", required=True)
    stage.add_argument("--workdir", required=True)
    stage.add_argument("--required-set-id", default="bootstrap-required-test-set")

    args = parser.parse_args(argv)
    try:
        if args.command == "init":
            return cmd_init(args)
        return cmd_stage(args)
    except PrepError as error:
        print(f"{error.code}: {error.detail}", file=sys.stderr)
        return 1
    except CONSUMER.Rejected as error:
        print(f"PF-CEREMONY-VERIFY: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

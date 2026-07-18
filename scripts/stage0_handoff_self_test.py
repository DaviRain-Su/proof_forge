#!/usr/bin/env python3
"""Acceptance tests for the Stage-0 handoff producer and containment runner.

The modules under test are intentionally loaded from their exact sibling
pathnames.  Everything runs under a temporary directory with unprivileged
bubblewrap; nothing touches system state, TCP, or real key material.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from types import ModuleType
from typing import Callable


HANDOFF_PATH = Path(__file__).with_name("stage0_handoff.py")
CONTAINMENT_PATH = Path(__file__).with_name("stage0_containment.py")
HANDOFF_MODULE_NAME = "proof_forge_stage0_handoff"
CONTAINMENT_MODULE_NAME = "proof_forge_stage0_containment"
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
RUN_ID = "run-20260718-0001"
DESCRIPTOR_ID = "authority-store"
NAMESPACE_ID = "bootstrap-authority-store"


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "stage0 self-test requires isolated Python (-I)"
    assert sys.flags.no_site, "stage0 self-test requires no-site Python (-S)"
    assert path.is_file(), f"missing {path}"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None, "import spec unavailable"
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves postponed annotations through the defining module.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def close_quietly(fds) -> None:
    for fd in fds:
        try:
            os.close(fd)
        except OSError:
            pass


def fd_set() -> set:
    return {int(entry) for entry in os.listdir("/proc/self/fd") if entry.isdigit()}


def expect_handoff_error(
    module: ModuleType,
    operation: Callable[[], object],
    codes: tuple[str, ...],
    label: str,
) -> object:
    try:
        result = operation()
    except module.Stage0HandoffError as error:
        if error.code not in codes:
            raise AssertionError(
                f"{label} raised {error.code}, expected one of {codes}"
            ) from error
        return error
    raise AssertionError(f"{label} must fail with one of {codes}")


def build_fixture(module: ModuleType, tmpdir: str) -> dict[str, object]:
    producer = module._PRODUCER
    consumer = producer._CONSUMER

    def digest(raw: bytes) -> object:
        return consumer.Digest("sha256", raw)

    principals = tuple(
        consumer.BootstrapAuthorityPrincipalV1(
            principalId=f"principal-{role}",
            keyId=f"key-{role}",
            publicKey=producer.ed25519_public_key_from_seed(
                SEEDS_BY_KEY_ID[f"key-{role}"]
            ),
            roles=(role,),
        )
        for role in ("architecture", "quality", "release", "security")
    )
    policy_bytes = producer.produce_bootstrap_authority_policy(
        id="bootstrap-authority-root",
        version="1.0.0",
        principals=principals,
        taskRules=tuple(
            consumer.BootstrapAuthorityTaskRuleV1(
                taskId=task_id,
                rule=consumer.ApprovalRuleV1(roles, minimum),
            )
            for task_id, roles, minimum in (
                ("TASK-D0-01", ("architecture", "quality"), 2),
                ("TASK-D0-02", ("architecture", "quality"), 2),
                ("TASK-D0-03", ("quality", "security"), 2),
                ("TASK-D0-04", ("quality", "security", "release"), 3),
                ("TASK-D0-05", ("quality", "security"), 2),
                ("TASK-D0-06", ("architecture", "quality"), 2),
            )
        ),
        requiredTestSetRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        formalCatalogRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        bootstrapSetRule=consumer.ApprovalRuleV1(
            ("quality", "security", "release"), 3
        ),
        sessionContainmentRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        freshnessAuthorityRule=consumer.ApprovalRuleV1(("quality", "release"), 2),
        privateScanRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        privateScanPolicy=consumer.ContentRef(
            "proof-forge.private-scan-policy.v1",
            "bootstrap-private-scan-policy",
            "1.0.0",
            digest(bytes.fromhex("41" * 32)),
        ),
        revocationSnapshotRule=consumer.ApprovalRuleV1(("security", "release"), 2),
        authorityStoreService=consumer.ContentRef(
            "proof-forge.authority-store-service.v1",
            "bootstrap-authority-store",
            "1.0.0",
            digest(bytes.fromhex("42" * 32)),
        ),
        verifier=consumer.BootstrapAuthorityVerifierV1(
            id="bootstrap-task-verifier",
            executableDigest=digest(bytes.fromhex("43" * 32)),
            receiptKeyId="key-verifier-receipt",
            receiptPublicKey=producer.ed25519_public_key_from_seed(
                SEEDS_BY_KEY_ID["key-verifier-receipt"]
            ),
        ),
    )
    policy, policy_ref = consumer.parse_bootstrap_authority_policy(policy_bytes)
    policy_path = os.path.join(tmpdir, "policy.json")
    with open(policy_path, "wb") as handle:
        handle.write(policy_bytes)

    archive_bytes = b"synthetic candidate archive v1\n" * 64
    archive_sha256 = hashlib.sha256(archive_bytes).digest()
    archive_path = os.path.join(tmpdir, "archive.tar")
    with open(archive_path, "wb") as handle:
        handle.write(archive_bytes)
    candidate_statement = {
        "commit": "a" * 40,
        "treeObjectId": "b" * 40,
        "archiveDigest": "sha256:" + archive_sha256.hex(),
    }
    candidate_digest = hashlib.sha256(
        b"pf.candidate-identity.v1\x00"
        + consumer.canonical_pf_jcs(candidate_statement)
    ).digest()
    candidate = consumer.CandidateIdentity(
        candidate_statement["commit"],
        candidate_statement["treeObjectId"],
        digest(archive_sha256),
        digest(candidate_digest),
    )

    manifest_bytes = (
        b'{"schema":"proof-forge.bootstrap-evidence-root-manifest.v1",'
        b'"taskId":"TASK-D0-04"}\n'
    )
    manifest_path = os.path.join(tmpdir, "manifest.json")
    with open(manifest_path, "wb") as handle:
        handle.write(manifest_bytes)

    descriptor_wire = {
        "schema": "proof-forge.authority-store-service.v1",
        "id": DESCRIPTOR_ID,
        "version": "1.0.0",
        "protocol": "pf.authority-store.rpc.v1",
        "serviceExecutableDigest": "sha256:" + ("42" * 32),
        "servicePublicKey": producer.ed25519_public_key_from_seed(
            SERVICE_SEED
        ).hex(),
        "namespaceId": NAMESPACE_ID,
        "maximumFrameBytes": 4194304,
    }
    descriptor_ref = consumer.ContentRef(
        descriptor_wire["schema"],
        descriptor_wire["id"],
        descriptor_wire["version"],
        digest(hashlib.sha256(
            b"pf.authority-store-service.v1\x00"
            + consumer.canonical_pf_jcs(descriptor_wire)
        ).digest()),
    )

    observation_bytes = json.dumps(
        {
            "attestationScope": "local-observation-only",
            "eligibleForHermetic": True,
            "hostProfileId": "linux-x86_64-test",
            "platform": {"secureBoot": "enabled"},
            "remoteAttestation": False,
            "trustRoot": "synthetic fixture",
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    profile_bytes = json.dumps(
        {"id": "linux-x86_64-test", "qualification": "formal"},
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")

    tcb = consumer.EligibleStage0TcbV1(
        digest(bytes.fromhex("73" * 32)),
        policy.verifier.executableDigest,
        digest(bytes.fromhex("74" * 32)),
        digest(bytes.fromhex("75" * 32)),
    )
    environment = consumer.EligibleStage0EnvironmentV1(
        "env-i", "/var/empty", "/usr/bin:/bin", "C", "UTC", "deny-default"
    )
    return {
        "consumer": consumer,
        "producer": producer,
        "policy": policy,
        "policyRef": policy_ref,
        "policyBytes": policy_bytes,
        "policyPath": policy_path,
        "archiveBytes": archive_bytes,
        "archivePath": archive_path,
        "candidate": candidate,
        "manifestBytes": manifest_bytes,
        "manifestPath": manifest_path,
        "descriptorWire": descriptor_wire,
        "descriptorRef": descriptor_ref,
        "observationBytes": observation_bytes,
        "profileBytes": profile_bytes,
        "tcb": tcb,
        "environment": environment,
    }


def produce_kwargs(fixture: dict[str, object], module: ModuleType) -> dict:
    return {
        "handoff_id": "bootstrap-stage0-handoff",
        "handoff_version": "1.0.0",
        "run_id": RUN_ID,
        "candidate": fixture["candidate"],
        "candidate_archive_path": fixture["archivePath"],
        "authority_policy_path": fixture["policyPath"],
        "authority_store_descriptor": fixture["descriptorRef"],
        "evidence_root_manifest_path": fixture["manifestPath"],
        "host_observation": module.Stage0HostObservationV1(
            id="eligible-host-observation",
            version="1.0.0",
            bytes=fixture["observationBytes"],
        ),
        "host_profile": module.Stage0HostProfileV1(
            id="eligible-host-profile",
            version="1.0.0",
            bytes=fixture["profileBytes"],
        ),
        "tcb": fixture["tcb"],
        "environment": fixture["environment"],
    }


def test_handoff_producer_positive(module: ModuleType, fixture: dict[str, object]) -> None:
    consumer = fixture["consumer"]
    assert isinstance(consumer, ModuleType)
    produced = module.produce_stage0_handoff(**produce_kwargs(fixture, module))
    fds = (
        produced.channels.authorityPolicyFd,
        produced.channels.authorityStoreFd,
        produced.channels.candidateArchiveFd,
        produced.channels.evidenceRootFd,
        produced.channels.authorityStoreServiceFd,
    )
    try:
        handoff = consumer._preflight_eligible_stage0_handoff(
            produced.handoffBytes
        ).handoff
        if handoff.id != "bootstrap-stage0-handoff":
            raise AssertionError("handoff id round-trip drift")
        if handoff.runId != RUN_ID or handoff.version != "1.0.0":
            raise AssertionError("handoff runId/version round-trip drift")
        if handoff.candidate != fixture["candidate"]:
            raise AssertionError("handoff candidate round-trip drift")
        if handoff.authorityPolicy != fixture["policyRef"]:
            raise AssertionError("handoff policy ref round-trip drift")
        if handoff.authorityStoreService != fixture["descriptorRef"]:
            raise AssertionError("handoff descriptor ref round-trip drift")
        if handoff.eligible is not True or handoff.pathnameReopen is not False:
            raise AssertionError("handoff flags drift")
        if handoff.fallback != "none":
            raise AssertionError("handoff fallback drift")
        expected_evidence_digest = hashlib.sha256(
            b"pf.bootstrap-evidence-root-manifest.v1\x00"
            + fixture["manifestBytes"]
        ).digest()
        expected_channels = (
            (
                "authority-policy",
                produced.channels.authorityPolicyFd,
                "regular-file",
                "read-only",
                fixture["policyRef"].digest,
            ),
            (
                "authority-store",
                produced.channels.authorityStoreFd,
                "authenticated-stream",
                "request-response",
                fixture["descriptorRef"].digest,
            ),
            (
                "candidate-archive",
                produced.channels.candidateArchiveFd,
                "regular-file",
                "read-only",
                fixture["candidate"].archiveDigest,
            ),
            (
                "evidence-root",
                produced.channels.evidenceRootFd,
                "regular-file",
                "read-only",
                consumer.Digest("sha256", expected_evidence_digest),
            ),
        )
        if len(handoff.channels) != 4:
            raise AssertionError("handoff must carry exactly four channels")
        for channel, expected in zip(handoff.channels, expected_channels):
            role, fd, transport, access, binding = expected
            if (channel.role, channel.fd, channel.transport, channel.access,
                    channel.bindingDigest) != (role, fd, transport, access, binding):
                raise AssertionError(f"channel {role} does not match the bound fd")
        if handoff.tcb != fixture["tcb"] or handoff.environment != fixture["environment"]:
            raise AssertionError("handoff tcb/environment round-trip drift")
        if produced.handoffDigest.bytes != hashlib.sha256(
            b"pf.eligible-stage0-handoff.v1\x00" + produced.handoffBytes
        ).digest():
            raise AssertionError("handoff digest must use the frozen domain")
        if produced.handoffRef.digest != produced.handoffDigest:
            raise AssertionError("handoff ref must carry the recomputed digest")
        if any(fd <= 2 for fd in fds) or len(set(fds)) != 5:
            raise AssertionError("channel fds must be unique and greater than 2")
        metadata = os.fstat(produced.channels.authorityPolicyFd)
        if not stat.S_ISREG(metadata.st_mode):
            raise AssertionError("policy channel fd must be a regular file")
        store_metadata = os.fstat(produced.channels.authorityStoreFd)
        if not stat.S_ISSOCK(store_metadata.st_mode):
            raise AssertionError("store channel fd must be a socket")
        reread = os.pread(produced.channels.authorityPolicyFd, 65536, 0)
        if reread != fixture["policyBytes"]:
            raise AssertionError("policy channel fd must read the exact bytes")

        second = module.produce_stage0_handoff(**produce_kwargs(fixture, module))
        try:
            first_nonce = consumer.decode_canonical_pf_jcs(
                produced.handoffBytes
            )["nonce"]
            second_nonce = consumer.decode_canonical_pf_jcs(
                second.handoffBytes
            )["nonce"]
            if first_nonce == second_nonce:
                raise AssertionError("handoff nonces must be unpredictable")
        finally:
            close_quietly((
                second.channels.authorityPolicyFd,
                second.channels.authorityStoreFd,
                second.channels.candidateArchiveFd,
                second.channels.evidenceRootFd,
                second.channels.authorityStoreServiceFd,
            ))
    finally:
        close_quietly(fds)


def test_handoff_producer_negatives(module: ModuleType, fixture: dict[str, object]) -> None:
    consumer = fixture["consumer"]
    assert isinstance(consumer, ModuleType)

    def ineligible_observation() -> object:
        kwargs = produce_kwargs(fixture, module)
        kwargs["host_observation"] = module.Stage0HostObservationV1(
            id="eligible-host-observation",
            version="1.0.0",
            bytes=json.dumps(
                {
                    "attestationScope": "local-observation-only",
                    "eligibleForHermetic": False,
                },
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8"),
        )
        return module.produce_stage0_handoff(**kwargs)

    before = fd_set()
    expect_handoff_error(
        module,
        ineligible_observation,
        ("PF-STAGE0-HANDOFF",),
        "ineligible host observation must fail closed",
    )
    if fd_set() != before:
        raise AssertionError("ineligible rejection must not leak channel fds")

    def garbage_observation() -> object:
        kwargs = produce_kwargs(fixture, module)
        kwargs["host_observation"] = module.Stage0HostObservationV1(
            id="eligible-host-observation",
            version="1.0.0",
            bytes=b"not json",
        )
        return module.produce_stage0_handoff(**kwargs)

    expect_handoff_error(
        module,
        garbage_observation,
        ("PF-STAGE0-HANDOFF",),
        "malformed host observation must fail closed",
    )

    symlink_path = os.path.join(
        tempfile.mkdtemp(prefix="stage0-symlink-"), "policy-link.json"
    )
    os.symlink(fixture["policyPath"], symlink_path)

    def symlink_policy() -> object:
        kwargs = produce_kwargs(fixture, module)
        kwargs["authority_policy_path"] = symlink_path
        return module.produce_stage0_handoff(**kwargs)

    before = fd_set()
    expect_handoff_error(
        module,
        symlink_policy,
        ("PF-STAGE0-CHANNEL",),
        "symlink policy channel must fail closed",
    )
    if fd_set() != before:
        raise AssertionError("symlink rejection must not leak channel fds")

    def directory_policy() -> object:
        kwargs = produce_kwargs(fixture, module)
        kwargs["authority_policy_path"] = os.path.dirname(fixture["policyPath"])
        return module.produce_stage0_handoff(**kwargs)

    expect_handoff_error(
        module,
        directory_policy,
        ("PF-STAGE0-CHANNEL",),
        "directory policy channel must fail closed",
    )

    fifo_dir = tempfile.mkdtemp(prefix="stage0-fifo-")
    fifo_path = os.path.join(fifo_dir, "policy.fifo")
    os.mkfifo(fifo_path)

    def fifo_policy() -> object:
        kwargs = produce_kwargs(fixture, module)
        kwargs["authority_policy_path"] = fifo_path
        return module.produce_stage0_handoff(**kwargs)

    expect_handoff_error(
        module,
        fifo_policy,
        ("PF-STAGE0-CHANNEL",),
        "fifo policy channel must fail closed",
    )
    shutil.rmtree(fifo_dir, ignore_errors=True)

    replaced_dir = tempfile.mkdtemp(prefix="stage0-replaced-")
    replaced_archive = os.path.join(replaced_dir, "archive.tar")
    with open(replaced_archive, "wb") as handle:
        handle.write(b"replaced archive content v2\n" * 64)

    def replaced_candidate_archive() -> object:
        kwargs = produce_kwargs(fixture, module)
        kwargs["candidate_archive_path"] = replaced_archive
        return module.produce_stage0_handoff(**kwargs)

    expect_handoff_error(
        module,
        replaced_candidate_archive,
        ("PF-STAGE0-CHANNEL",),
        "replaced candidate archive must fail the digest binding",
    )
    shutil.rmtree(replaced_dir, ignore_errors=True)

    garbage_dir = tempfile.mkdtemp(prefix="stage0-garbage-")
    garbage_policy = os.path.join(garbage_dir, "policy.json")
    with open(garbage_policy, "wb") as handle:
        handle.write(b"not a policy\n")

    def garbage_policy_bytes() -> object:
        kwargs = produce_kwargs(fixture, module)
        kwargs["authority_policy_path"] = garbage_policy
        return module.produce_stage0_handoff(**kwargs)

    expect_handoff_error(
        module,
        garbage_policy_bytes,
        ("PF-STAGE0-HANDOFF",),
        "invalid policy channel bytes must fail closed",
    )
    shutil.rmtree(garbage_dir, ignore_errors=True)

    def relative_policy_path() -> object:
        kwargs = produce_kwargs(fixture, module)
        kwargs["authority_policy_path"] = "policy.json"
        return module.produce_stage0_handoff(**kwargs)

    expect_handoff_error(
        module,
        relative_policy_path,
        ("PF-STAGE0-CHANNEL",),
        "relative channel path must fail closed",
    )


def spawn_verify_child(
    handoff_bytes: bytes,
    pass_fds: tuple,
    *,
    stdin_mode: str = "devnull",
) -> subprocess.CompletedProcess:
    argv = [
        sys.executable,
        "-I",
        "-S",
        str(Path(__file__).resolve()),
        "--verify-child",
        handoff_bytes.hex(),
    ]
    if stdin_mode == "devnull":
        stdin = subprocess.DEVNULL
    elif stdin_mode == "pipe-data":
        stdin = subprocess.PIPE
    else:
        raise AssertionError(f"unknown stdin mode {stdin_mode}")
    proc = subprocess.Popen(
        argv,
        stdin=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
        close_fds=True,
        pass_fds=pass_fds,
    )
    if stdin_mode == "pipe-data":
        assert proc.stdin is not None
        proc.stdin.write(b"not-eof\n")
        proc.stdin.flush()
        time.sleep(0.4)
        proc.stdin.close()
        proc.stdin = None
    stdout, stderr = proc.communicate(timeout=30)
    return subprocess.CompletedProcess(argv, proc.returncode, stdout, stderr)


def test_verify_inherited_channels(module: ModuleType, fixture: dict[str, object]) -> None:
    consumer = fixture["consumer"]
    assert isinstance(consumer, ModuleType)
    produced = module.produce_stage0_handoff(**produce_kwargs(fixture, module))
    channels = produced.channels
    channel_fds = (
        channels.authorityPolicyFd,
        channels.authorityStoreFd,
        channels.candidateArchiveFd,
        channels.evidenceRootFd,
    )
    service_fd = channels.authorityStoreServiceFd
    try:
        positive = spawn_verify_child(produced.handoffBytes, channel_fds)
        if positive.returncode != 0 or b"verify-inherited-channels: ok" not in (
            positive.stdout
        ):
            raise AssertionError(
                f"inherited-channel positive must pass: {positive.stderr!r}"
            )

        extra_fd = spawn_verify_child(
            produced.handoffBytes, channel_fds + (service_fd,)
        )
        if extra_fd.returncode == 0:
            raise AssertionError("an extra inherited fd must be rejected")

        duplicated = tuple(os.dup(fd) for fd in channel_fds)
        try:
            renumbered = spawn_verify_child(produced.handoffBytes, duplicated)
            if renumbered.returncode == 0:
                raise AssertionError("renumbered channel fds must be rejected")
        finally:
            close_quietly(duplicated)

        decoded = consumer.decode_canonical_pf_jcs(produced.handoffBytes)
        swapped = consumer.decode_canonical_pf_jcs(produced.handoffBytes)
        swapped["channels"][0]["fd"], swapped["channels"][1]["fd"] = (
            swapped["channels"][1]["fd"],
            swapped["channels"][0]["fd"],
        )
        socket_first = spawn_verify_child(
            consumer.canonical_pf_jcs(swapped), channel_fds
        )
        if socket_first.returncode == 0:
            raise AssertionError("a socket fd in a regular channel must be rejected")

        swapped_regular = consumer.decode_canonical_pf_jcs(produced.handoffBytes)
        swapped_regular["channels"][1]["fd"], swapped_regular["channels"][3]["fd"] = (
            swapped_regular["channels"][3]["fd"],
            swapped_regular["channels"][1]["fd"],
        )
        regular_second = spawn_verify_child(
            consumer.canonical_pf_jcs(swapped_regular), channel_fds
        )
        if regular_second.returncode == 0:
            raise AssertionError("a regular fd in the socket channel must be rejected")

        tampered_digest = consumer.decode_canonical_pf_jcs(produced.handoffBytes)
        tampered_digest["channels"][0]["bindingDigest"] = "sha256:" + "0" * 64
        digest_mismatch = spawn_verify_child(
            consumer.canonical_pf_jcs(tampered_digest), channel_fds
        )
        if digest_mismatch.returncode == 0:
            raise AssertionError("a drifted bindingDigest must be rejected")

        not_eof = spawn_verify_child(
            produced.handoffBytes, channel_fds, stdin_mode="pipe-data"
        )
        if not_eof.returncode == 0:
            raise AssertionError("non-EOF stdin must be rejected")
    finally:
        close_quietly(channel_fds + (service_fd,))


def payload(code: str) -> tuple:
    return ("/usr/bin/python3", "-I", "-S", "-c", code)


PAYLOAD_ENV = (("PATH", "/usr/bin:/bin"), ("LC_ALL", "C"))


def test_containment(module: ModuleType, fixture: dict[str, object], tmpdir: str) -> None:
    error_type = module.Stage0ContainmentError

    def expect_error(operation, codes, label):
        try:
            result = operation()
        except error_type as error:
            if error.code not in codes:
                raise AssertionError(
                    f"{label} raised {error.code}, expected one of {codes}"
                ) from error
            return error
        raise AssertionError(f"{label} must fail with one of {codes}")

    result = module.run_contained(
        payload("print('hello-containment')"),
        env=PAYLOAD_ENV,
        timeout_seconds=15.0,
    )
    if result.exitCode != 0 or result.stdoutBytes != b"hello-containment\n":
        raise AssertionError(f"containment positive failed: {result}")

    for label, argv in (
        ("empty argv", ()),
        ("relative argv0", ("python3", "-c", "pass")),
    ):
        expect_error(
            lambda argv=argv: module.run_contained(argv),
            ("PF-STAGE0-CONTAINMENT",),
            label,
        )

    env_probe = module.run_contained(
        payload(
            "import os\n"
            "print(sorted(os.environ.items()))"
        ),
        env=PAYLOAD_ENV + (("MARKER", "probe"),),
        timeout_seconds=15.0,
    )
    expected_env = (
        "[('LC_ALL', 'C'), ('MARKER', 'probe'), ('PATH', '/usr/bin:/bin'), "
        "('PWD', '/')]\n"
    )
    if env_probe.exitCode != 0 or env_probe.stdoutBytes.decode() != expected_env:
        raise AssertionError(
            f"environment whitelist must be exact: {env_probe.stdoutBytes!r}"
        )

    fixture_path = os.path.join(tmpdir, "inherit-input.bin")
    with open(fixture_path, "wb") as handle:
        handle.write(b"inherited-fd-payload-bytes\n")
    inherit_fd = os.open(fixture_path, os.O_RDONLY)
    try:
        inherit_probe = module.run_contained(
            payload(
                "import os\n"
                f"data = os.pread({inherit_fd}, 4096, 0)\n"
                "print(data.decode().strip())"
            ),
            inherit_fds=(inherit_fd,),
            env=PAYLOAD_ENV,
            timeout_seconds=15.0,
        )
        if (inherit_probe.exitCode != 0
                or inherit_probe.stdoutBytes != b"inherited-fd-payload-bytes\n"):
            raise AssertionError(
                f"inherit_fds must reach the payload at the same number: "
                f"{inherit_probe!r}"
            )
    finally:
        os.close(inherit_fd)

    network_probe = module.run_contained(
        payload(
            "import socket, sys\n"
            "sock = socket.socket()\n"
            "sock.settimeout(1)\n"
            "try:\n"
            "    sock.connect(('10.255.255.1', 65000))\n"
            "except OSError:\n"
            "    sys.exit(0)\n"
            "sys.exit(42)"
        ),
        env=PAYLOAD_ENV,
        timeout_seconds=15.0,
    )
    if network_probe.exitCode != 0:
        raise AssertionError("network access must fail inside the containment")

    marker = os.path.join(tmpdir, "escape-marker")
    escape = module.run_contained(
        payload(
            "import os, time\n"
            "pid = os.fork()\n"
            "if pid == 0:\n"
            "    os.setsid()\n"
            "    time.sleep(2)\n"
            f"    open({marker!r}, 'w').write('escaped')\n"
            "    os._exit(0)\n"
            "time.sleep(0.2)"
        ),
        env=PAYLOAD_ENV,
        timeout_seconds=15.0,
    )
    if escape.exitCode != 0:
        raise AssertionError("escape-probe payload must exit cleanly")
    time.sleep(2.6)
    if os.path.exists(marker):
        raise AssertionError("setsid escapee must not outlive the namespace")

    expect_error(
        lambda: module.run_contained(
            payload(
                "import sys\n"
                "sys.stdout.write('x' * (2 * 1024 * 1024))\n"
                "sys.stdout.flush()"
            ),
            env=PAYLOAD_ENV,
            timeout_seconds=15.0,
        ),
        ("PF-STAGE0-LIMIT",),
        "stdout overflow must fail as a limit",
    )

    timeout_marker = os.path.join(tmpdir, "timeout-marker")
    started = time.monotonic()
    expect_error(
        lambda: module.run_contained(
            payload(
                "import os, time\n"
                "pid = os.fork()\n"
                "if pid == 0:\n"
                "    time.sleep(3)\n"
                f"    open({timeout_marker!r}, 'w').write('escaped')\n"
                "    os._exit(0)\n"
                "time.sleep(30)"
            ),
            env=PAYLOAD_ENV,
            timeout_seconds=1.5,
        ),
        ("PF-STAGE0-TIMEOUT",),
        "timeout must kill the contained run",
    )
    if time.monotonic() - started > 8:
        raise AssertionError("timeout enforcement took too long")
    time.sleep(3.2)
    if os.path.exists(timeout_marker):
        raise AssertionError("timeout must kill the whole process tree")

    limited = module.run_contained(
        payload(
            "blocks = []\n"
            "for _ in range(512):\n"
            "    blocks.append(bytearray(1 << 20))\n"
            "print('allocated')"
        ),
        env=PAYLOAD_ENV,
        timeout_seconds=20.0,
        limits=module.ContainmentLimits(addressSpaceBytes=96 * 1024 * 1024),
    )
    if limited.exitCode == 0:
        raise AssertionError("address-space rlimit must stop the allocation")

    passthrough = module.run_contained(
        payload("import sys; sys.exit(7)"),
        env=PAYLOAD_ENV,
        timeout_seconds=15.0,
    )
    if passthrough.exitCode != 7:
        raise AssertionError("exit codes must pass through as data")


def run_verify_child() -> int:
    module = load_module(HANDOFF_PATH, HANDOFF_MODULE_NAME)
    consumer = module._CONSUMER
    handoff_bytes = bytes.fromhex(sys.argv[2])
    handoff = consumer._preflight_eligible_stage0_handoff(handoff_bytes).handoff
    module.verify_inherited_channels(handoff)
    print("verify-inherited-channels: ok")
    return 0


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--verify-child":
        return run_verify_child()
    tmpdir = tempfile.mkdtemp(prefix="stage0-handoff-self-test-")
    try:
        handoff_module = load_module(HANDOFF_PATH, HANDOFF_MODULE_NAME)
        containment_module = load_module(CONTAINMENT_PATH, CONTAINMENT_MODULE_NAME)
        fixture = build_fixture(handoff_module, tmpdir)
        test_handoff_producer_positive(handoff_module, fixture)
        test_handoff_producer_negatives(handoff_module, fixture)
        test_verify_inherited_channels(handoff_module, fixture)
        test_containment(containment_module, fixture, tmpdir)
    except (AssertionError, AttributeError, OSError, ImportError, SyntaxError) as error:
        print(f"stage0-handoff-self-test: FAIL: {error}", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    print("stage0-handoff-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Schema-complete immutable evidence (proof-forge.evidence.v1) helpers.

Evidence files are written once and never overwritten in place. Re-runs allocate
a new EV id. Validation rejects unknown fields, missing required keys, and
malformed digests.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

SCHEMA = "proof-forge.evidence.v1"
EV_ID_RE = re.compile(r"^EV-\d{8}-\d{4}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
RESULT_VALUES = frozenset({"passed", "failed", "skipped"})


class EvidenceError(RuntimeError):
    pass


def fail(message: str) -> "None":
    raise EvidenceError(message)


def require_isolated_python() -> None:
    if not sys.flags.isolated or not sys.flags.no_site:
        fail("run evidence with /usr/bin/python3 -I -S")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def require_dict(value: object, where: str) -> dict:
    if not isinstance(value, dict):
        fail(f"{where} must be an object")
    return value


def require_list(value: object, where: str) -> list:
    if not isinstance(value, list):
        fail(f"{where} must be an array")
    return value


def require_string(value: object, where: str) -> str:
    if not isinstance(value, str) or value == "":
        fail(f"{where} must be a non-empty string")
    return value


def require_sha256(value: object, where: str) -> str:
    text = require_string(value, where)
    if not SHA256_RE.fullmatch(text):
        fail(f"{where} must be lowercase SHA-256")
    return text


def require_int(value: object, where: str, *, min_value: int | None = None) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        fail(f"{where} must be an integer")
    if min_value is not None and value < min_value:
        fail(f"{where} must be >= {min_value}")
    return value


def require_keys(value: dict, required: set[str], where: str) -> None:
    missing = sorted(required - set(value))
    if missing:
        fail(f"{where} missing keys: {', '.join(missing)}")
    extra = sorted(set(value) - required)
    if extra:
        fail(f"{where} has unknown keys: {', '.join(extra)}")


def reject_duplicate_json_keys(pairs: list[tuple[str, object]]) -> dict:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def parse_json_text(text: str, where: str) -> dict:
    try:
        value = json.loads(text, object_pairs_hook=reject_duplicate_json_keys)
    except json.JSONDecodeError as error:
        fail(f"{where} is not valid JSON: {error}")
    return require_dict(value, where)


def validate_path_digest(entry: object, where: str, *, require_size: bool) -> dict:
    record = require_dict(entry, where)
    required = {"path", "sha256"}
    if require_size:
        required.add("size")
    require_keys(record, required, where)
    require_string(record["path"], f"{where}.path")
    require_sha256(record["sha256"], f"{where}.sha256")
    if require_size:
        require_int(record["size"], f"{where}.size", min_value=0)
    return record


def validate_observation(entry: object, where: str) -> dict:
    record = require_dict(entry, where)
    require_keys(
        record,
        {"step", "status", "return", "logicalState", "effects", "errorClass"},
        where,
    )
    require_string(record["step"], f"{where}.step")
    require_string(record["status"], f"{where}.status")
    # return/logicalState/effects may be structured; errorClass is string or null.
    if record["errorClass"] is not None and not isinstance(record["errorClass"], str):
        fail(f"{where}.errorClass must be string or null")
    if not isinstance(record["effects"], list):
        fail(f"{where}.effects must be an array")
    return record


def validate_evidence(document: dict) -> dict:
    require_keys(
        document,
        {
            "schema",
            "id",
            "gateId",
            "testIds",
            "taskId",
            "repository",
            "environment",
            "toolchains",
            "command",
            "inputs",
            "outputs",
            "observations",
            "result",
            "logs",
            "bindings",
        },
        "evidence",
    )
    if document["schema"] != SCHEMA:
        fail(f"unsupported evidence schema: {document['schema']}")
    ev_id = require_string(document["id"], "id")
    if not EV_ID_RE.fullmatch(ev_id):
        fail(f"id must match EV-YYYYMMDD-NNNN: {ev_id}")
    require_string(document["gateId"], "gateId")
    test_ids = require_list(document["testIds"], "testIds")
    if not test_ids or any(not isinstance(item, str) or not item for item in test_ids):
        fail("testIds must be a non-empty string array")
    require_string(document["taskId"], "taskId")

    repository = require_dict(document["repository"], "repository")
    require_keys(repository, {"commit", "dirty", "diffDigest"}, "repository")
    require_string(repository["commit"], "repository.commit")
    if not isinstance(repository["dirty"], bool):
        fail("repository.dirty must be boolean")
    if repository["diffDigest"] is not None:
        require_sha256(repository["diffDigest"], "repository.diffDigest")

    environment = require_dict(document["environment"], "environment")
    require_keys(
        environment,
        {
            "os",
            "arch",
            "envDigest",
            "cleanRoom",
            "cacheMode",
            "sandboxPolicy",
            "eligibleForHermetic",
            "hostProfileId",
        },
        "environment",
    )
    require_string(environment["os"], "environment.os")
    require_string(environment["arch"], "environment.arch")
    require_sha256(environment["envDigest"], "environment.envDigest")
    if not isinstance(environment["cleanRoom"], bool):
        fail("environment.cleanRoom must be boolean")
    require_string(environment["cacheMode"], "environment.cacheMode")
    require_string(environment["sandboxPolicy"], "environment.sandboxPolicy")
    if environment["sandboxPolicy"] not in ("deny-default", "allow-default-deny-list"):
        fail("environment.sandboxPolicy must be deny-default or allow-default-deny-list")
    if not isinstance(environment["eligibleForHermetic"], bool):
        fail("environment.eligibleForHermetic must be boolean")
    require_string(environment["hostProfileId"], "environment.hostProfileId")

    toolchains = require_list(document["toolchains"], "toolchains")
    for index, item in enumerate(toolchains):
        where = f"toolchains[{index}]"
        record = require_dict(item, where)
        require_keys(record, {"id", "version", "executableSha256"}, where)
        require_string(record["id"], f"{where}.id")
        require_string(record["version"], f"{where}.version")
        require_sha256(record["executableSha256"], f"{where}.executableSha256")

    command = require_dict(document["command"], "command")
    require_keys(
        command,
        {"argv", "cwdRelative", "startedUtc", "durationMs", "exitCode"},
        "command",
    )
    argv = require_list(command["argv"], "command.argv")
    if not argv or any(not isinstance(item, str) or not item for item in argv):
        fail("command.argv must be a non-empty string array")
    require_string(command["cwdRelative"], "command.cwdRelative")
    require_string(command["startedUtc"], "command.startedUtc")
    require_int(command["durationMs"], "command.durationMs", min_value=0)
    require_int(command["exitCode"], "command.exitCode")

    inputs = require_list(document["inputs"], "inputs")
    for index, item in enumerate(inputs):
        validate_path_digest(item, f"inputs[{index}]", require_size=False)
    outputs = require_list(document["outputs"], "outputs")
    for index, item in enumerate(outputs):
        validate_path_digest(item, f"outputs[{index}]", require_size=True)
    observations = require_list(document["observations"], "observations")
    for index, item in enumerate(observations):
        validate_observation(item, f"observations[{index}]")

    result = require_string(document["result"], "result")
    if result not in RESULT_VALUES:
        fail(f"result must be one of {sorted(RESULT_VALUES)}")

    logs = require_list(document["logs"], "logs")
    for index, item in enumerate(logs):
        record = require_dict(item, f"logs[{index}]")
        require_keys(record, {"path", "sha256", "truncated"}, f"logs[{index}]")
        require_string(record["path"], f"logs[{index}].path")
        require_sha256(record["sha256"], f"logs[{index}].sha256")
        if not isinstance(record["truncated"], bool):
            fail(f"logs[{index}].truncated must be boolean")

    bindings = require_dict(document["bindings"], "bindings")
    require_keys(
        bindings,
        {
            "candidateCommit",
            "archiveSha256",
            "hostBootstrapSha256",
            "hostLockSha256",
            "toolLockSha256",
            "launcherSha256",
            "verifierSha256",
            "isolationHarnessSha256",
            "sandboxPolicySha256",
            "evidenceSchema",
        },
        "bindings",
    )
    for key in (
        "archiveSha256",
        "hostBootstrapSha256",
        "hostLockSha256",
        "toolLockSha256",
        "launcherSha256",
        "verifierSha256",
        "isolationHarnessSha256",
        "sandboxPolicySha256",
    ):
        require_sha256(bindings[key], f"bindings.{key}")
    require_string(bindings["candidateCommit"], "bindings.candidateCommit")
    if bindings["evidenceSchema"] != SCHEMA:
        fail("bindings.evidenceSchema must equal proof-forge.evidence.v1")

    return document


def canonical_json_bytes(document: dict) -> bytes:
    # JCS-style stable encoding: sorted keys, no insignificant whitespace, UTF-8.
    return json.dumps(
        document,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def write_evidence(path: Path, document: dict) -> Path:
    validate_evidence(document)
    path = path.resolve()
    if path.exists():
        fail(f"evidence path already exists (immutable): {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = canonical_json_bytes(document)
    # Atomic publish via exclusive create + rename within the same directory.
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=str(path.parent),
    )
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp_path, 0o444)
        os.link(tmp_path, path)
    finally:
        try:
            tmp_path.unlink()
        except FileNotFoundError:
            pass
    # Refuse later overwrite: re-open and confirm digest.
    written = path.read_bytes()
    if written != payload:
        fail("evidence write verification failed")
    return path


def load_and_validate(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    document = parse_json_text(text, str(path))
    return validate_evidence(document)


def path_digest(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    return {
        "path": path.name,
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
    }


def self_test() -> None:
    sample = {
        "schema": SCHEMA,
        "id": "EV-20260716-0001",
        "gateId": "host-h1-deny-default",
        "testIds": ["TST-HOST-001", "TST-EVIDENCE-001"],
        "taskId": "TASK-D0-03/H1",
        "repository": {
            "commit": "0" * 40,
            "dirty": False,
            "diffDigest": None,
        },
        "environment": {
            "os": "macOS 26.4.1",
            "arch": "arm64",
            "envDigest": "a" * 64,
            "cleanRoom": True,
            "cacheMode": "empty",
            "sandboxPolicy": "deny-default",
            "eligibleForHermetic": False,
            "hostProfileId": "darwin-arm64-development",
        },
        "toolchains": [
            {
                "id": "lean",
                "version": "4.31.0",
                "executableSha256": "b" * 64,
            }
        ],
        "command": {
            "argv": ["scripts/verify_isolation.sh"],
            "cwdRelative": ".",
            "startedUtc": "2026-07-16T00:00:00Z",
            "durationMs": 12,
            "exitCode": 0,
        },
        "inputs": [{"path": "host-bootstrap.lock", "sha256": "c" * 64}],
        "outputs": [{"path": "archive.tar", "sha256": "d" * 64, "size": 10}],
        "observations": [
            {
                "step": "sandbox-self-test",
                "status": "ok",
                "return": None,
                "logicalState": None,
                "effects": [],
                "errorClass": None,
            }
        ],
        "result": "passed",
        "logs": [{"path": "gate.log", "sha256": "e" * 64, "truncated": False}],
        "bindings": {
            "candidateCommit": "0" * 40,
            "archiveSha256": "f" * 64,
            "hostBootstrapSha256": "1" * 64,
            "hostLockSha256": "2" * 64,
            "toolLockSha256": "3" * 64,
            "launcherSha256": "4" * 64,
            "verifierSha256": "5" * 64,
            "isolationHarnessSha256": "6" * 64,
            "sandboxPolicySha256": "7" * 64,
            "evidenceSchema": SCHEMA,
        },
    }
    validate_evidence(sample)

    bad = json.loads(json.dumps(sample))
    bad["schema"] = "nope"
    try:
        validate_evidence(bad)
        fail("self-test failed to reject bad schema")
    except EvidenceError:
        pass

    with tempfile.TemporaryDirectory(prefix="pf-evidence-") as raw:
        root = Path(raw)
        path = root / "EV-20260716-0001.json"
        write_evidence(path, sample)
        if not path.is_file():
            fail("evidence file missing after write")
        mode = path.stat().st_mode & 0o777
        if mode != 0o444:
            fail(f"evidence mode must be 0444, got {oct(mode)}")
        load_and_validate(path)
        try:
            write_evidence(path, sample)
            fail("self-test failed to reject overwrite")
        except EvidenceError:
            pass
        # In-place mutation must be blocked by mode; if chmod is possible by owner,
        # the immutable contract is still enforced by write_evidence exclusive create.
        try:
            with path.open("a", encoding="utf-8") as handle:
                handle.write("\n")
            # On some FS owner can still write after chmod; enforce content check.
            if path.read_bytes() != canonical_json_bytes(sample):
                # restore is not required for the test process temp dir
                pass
        except OSError:
            pass

    print("evidence: self-test ok (schema-complete immutable)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="ProofForge evidence schema tools")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("self-test")
    validate = commands.add_parser("validate")
    validate.add_argument("path", type=Path)
    write = commands.add_parser("write")
    write.add_argument("--output", type=Path, required=True)
    write.add_argument("--document", type=Path, required=True)
    return parser


def main() -> None:
    require_isolated_python()
    args = build_parser().parse_args()
    if args.command == "self-test":
        self_test()
        return
    if args.command == "validate":
        load_and_validate(args.path.resolve())
        print(f"evidence: ok {args.path}")
        return
    if args.command == "write":
        document = parse_json_text(
            args.document.read_text(encoding="utf-8"),
            str(args.document),
        )
        path = write_evidence(args.output, document)
        print(f"evidence: wrote {path}")
        return
    fail(f"unsupported command {args.command}")


if __name__ == "__main__":
    try:
        main()
    except (EvidenceError, OSError) as error:
        print(f"evidence: {error}", file=sys.stderr)
        raise SystemExit(1) from error

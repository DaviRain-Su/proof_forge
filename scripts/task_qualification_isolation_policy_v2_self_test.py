#!/usr/bin/env python3
"""Development matrix for the ADR-0021 isolation-policy C owner.

The matrix supplies candidate-external-shaped canonical policy bytes, an exact
FD-role manifest, descriptor/handoff joins, Unicode 17 NFC paths, and all three
signed seccomp tables.  It remains development evidence: fixtures are not
A+Q+S signed and this test does not launch the production supervisor.
"""

from __future__ import annotations

import argparse
import copy
import errno
import hashlib
import json
import os
import platform
import stat
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
_MAX_U64 = (1 << 64) - 1
_DOMAIN = b"pf.taskqual.store-isolation-policy.v2"
_PROC_ROOT_FD = 40
_DURABLE_ROOT_FD = 41
_SERVICE_EXECUTABLE_FD = 42

_SYSCALL = {
    "capset": 126,
    "prctl": 157,
    "exit_group": 231,
    "seccomp": 317,
    "execveat": 322,
}
_PR_CAPBSET_READ = 23
_PR_CAPBSET_DROP = 24
_PR_GET_NO_NEW_PRIVS = 39
_PR_CAP_AMBIENT = 47
_PR_CAP_AMBIENT_IS_SET = 1
_PR_CAP_AMBIENT_CLEAR_ALL = 4
_SECCOMP_SET_MODE_FILTER = 1
_AT_EMPTY_PATH = 0x1000


@dataclass(frozen=True)
class Vector:
    name: str
    payload: bytes
    accepted: bool
    digest_override: str | None = None


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def _canonical(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def _digest(payload: bytes) -> str:
    return hashlib.sha256(_DOMAIN + b"\x00" + payload).hexdigest()


def _hex(value: int) -> str:
    return f"{value & _MAX_U64:016x}"


def _argument(
    index: int,
    value: int,
    *,
    operation: str = "eq",
    mask: int = _MAX_U64,
) -> dict[str, Any]:
    return {
        "index": index,
        "mask": _hex(mask),
        "operation": operation,
        "value": _hex(value),
    }


def _rule(syscall: str, *arguments: dict[str, Any]) -> dict[str, Any]:
    return {"action": "allow", "arguments": list(arguments), "syscall": syscall}


def _sort_rules(rules: list[dict[str, Any]]) -> None:
    rules.sort(key=lambda item: (_SYSCALL[item["syscall"]], _canonical(item["arguments"])))


def _seccomp(stage: str, rules: list[dict[str, Any]]) -> dict[str, Any]:
    copied = copy.deepcopy(rules)
    _sort_rules(copied)
    return {
        "auditArch": "AUDIT_ARCH_X86_64",
        "defaultAction": "kill-process",
        "noNewPrivs": True,
        "rules": copied,
        "stage": stage,
    }


def _prctl(option: int, argument1: int, argument2: int = 0) -> dict[str, Any]:
    return _rule(
        "prctl",
        _argument(0, option),
        _argument(1, argument1),
        _argument(2, argument2),
        _argument(3, 0),
        _argument(4, 0),
    )


def _seccomp_policies() -> list[dict[str, Any]]:
    adapter = _seccomp("adapter", [_rule("exit_group")])
    custody = _seccomp("custody-pre-exec", [
        _rule("capset"),
        _prctl(_PR_CAPBSET_READ, 0),
        _prctl(_PR_CAPBSET_DROP, 19),
        _prctl(_PR_CAPBSET_DROP, 8),
        _prctl(_PR_GET_NO_NEW_PRIVS, 0),
        _prctl(_PR_CAP_AMBIENT, _PR_CAP_AMBIENT_IS_SET, 0),
        _prctl(_PR_CAP_AMBIENT, _PR_CAP_AMBIENT_CLEAR_ALL),
        _rule("seccomp", _argument(0, _SECCOMP_SET_MODE_FILTER), _argument(1, 0)),
        _rule(
            "execveat",
            _argument(0, _SERVICE_EXECUTABLE_FD),
            _argument(4, _AT_EMPTY_PATH),
        ),
    ])
    service = _seccomp("service-final", [
        _rule("capset"),
        _prctl(_PR_GET_NO_NEW_PRIVS, 0),
        _rule("exit_group"),
    ])
    return [adapter, custody, service]


def _namespace(device: int, inode: int) -> dict[str, int]:
    return {"device": device, "inode": inode}


def _mount(target: str, device: int, inode: int) -> dict[str, Any]:
    return {
        "noDev": True,
        "noExec": True,
        "noSuid": True,
        "readOnly": True,
        "source": _namespace(device, inode),
        "target": target,
    }


def _fd_roles() -> list[dict[str, Any]]:
    rows = [
        ("adapter", "steady", "authority-store", 30, False),
        ("service", "post-exec", "durable-root", 41, False),
        ("service", "post-exec", "proc-root", 40, False),
        ("service", "pre-exec", "durable-root", 41, False),
        ("service", "pre-exec", "proc-root", 40, False),
        ("service", "pre-exec", "service-executable", 42, True),
        ("service", "steady", "durable-root", 41, False),
        ("service", "steady", "proc-root", 40, False),
    ]
    return [
        {
            "closeOnExec": close,
            "fd": fd,
            "process": process,
            "role": role,
            "stage": stage,
        }
        for process, stage, role, fd, close in rows
    ]


def _baseline() -> dict[str, Any]:
    return {
        "schema": "proof-forge.task-qualification-store-isolation-policy.v2",
        "id": "task-qualification-store-isolation-run-policy-v2",
        "version": "2.0.0",
        "namespace": "task-qualification-production-v1",
        "taskId": "TASK-D1-01",
        "operation": "task-qualification",
        "runId": "run-policy-v2",
        "nonce": "nonce-policy-v2",
        "userNamespace": _namespace(10, 11),
        "parentPidNamespace": _namespace(10, 12),
        "adapterPidNamespace": _namespace(10, 13),
        "serviceMountNamespace": _namespace(10, 14),
        "adapterMountNamespace": _namespace(10, 15),
        "uidMap": [
            {"insideId": 1001, "length": 1, "outsideId": 200001},
            {"insideId": 1002, "length": 1, "outsideId": 200002},
        ],
        "gidMap": [
            {"insideId": 1003, "length": 1, "outsideId": 200003},
            {"insideId": 1004, "length": 1, "outsideId": 200004},
        ],
        "adapterUid": 1001,
        "adapterGid": 1003,
        "serviceUid": 1002,
        "serviceGid": 1004,
        "serviceProcRoot": _namespace(20, 21),
        "durableStateRoot": _namespace(20, 22),
        "seedRoot": _namespace(20, 23),
        "serviceMounts": [_mount("/runtime/é", 30, 31)],
        "adapterMounts": [_mount("/input/가", 30, 32)],
        "fdRoles": _fd_roles(),
        "socketDomain": "AF_UNIX",
        "socketType": "SOCK_SEQPACKET",
        "socketCreation": "socketpair",
        "socketSendFlags": "MSG_NOSIGNAL",
        "passCredentials": True,
        "requestedSocketBufferBytes": 4194304,
        "minimumEffectiveSocketBufferBytes": 8388608,
        "preSeedCapabilities": [6, 7, 8, 19, 21],
        "custodyCapabilities": [8, 19],
        "adapterCapabilities": [],
        "finalServiceCapabilities": [],
        "serviceExecutableFd": _SERVICE_EXECUTABLE_FD,
        "serviceArgv": ["proof-forge-taskqualification-store-v2"],
        "serviceEnvironment": [],
        "execOperation": "execveat-at-empty-path",
        "staticElfRequired": True,
        "seccompPolicies": _seccomp_policies(),
        "maximumFrameBytes": 4194304,
        "maximumTerminalAcceptances": 1,
    }


def _mutated(
    baseline: dict[str, Any], mutate: Callable[[dict[str, Any]], None]
) -> dict[str, Any]:
    result = copy.deepcopy(baseline)
    mutate(result)
    return result


def _vector(
    name: str,
    value: dict[str, Any] | bytes,
    accepted: bool,
    digest_override: str | None = None,
) -> Vector:
    return Vector(
        name,
        value if isinstance(value, bytes) else _canonical(value),
        accepted,
        digest_override,
    )


def _build_vectors() -> list[Vector]:
    base = _baseline()
    vectors = [_vector("baseline", base, True)]

    special = _mutated(base, lambda item: item["serviceMounts"][0].__setitem__(
        "target", '/runtime/"\\é'))
    vectors.extend([
        _vector("canonical-escaped-quote-backslash", special, True),
        _vector("root-mount-target", _mutated(
            base, lambda item: item["serviceMounts"][0].__setitem__("target", "/")), True),
        _vector("nfc-combining-positive", _mutated(
            base, lambda item: item["serviceMounts"][0].__setitem__(
                "target", "/runtime/à\u0315")), True),
    ])

    canonical = _canonical(base)
    vectors.extend([
        _vector("canonical-whitespace", canonical.replace(b'{"adapterCapabilities"',
            b'{ "adapterCapabilities"', 1), False),
        _vector("canonical-unicode-escape", canonical.replace(
            "é".encode(), b"\\u00e9", 1), False),
        _vector("invalid-utf8", canonical.replace("é".encode(), b"\xc0\xaf", 1), False),
        _vector("root-not-object", b"[]", False),
        _vector("unknown-root-field", _mutated(
            base, lambda item: item.__setitem__("unknown", 1)), False),
        _vector("missing-root-field", _mutated(
            base, lambda item: item.pop("socketDomain")), False),
        _vector("digest-mismatch", base, False, "00" * 32),
    ])

    scalar_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("schema", lambda item: item.__setitem__("schema", "wrong")),
        ("derived-id", lambda item: item.__setitem__("id", item["id"] + "-x")),
        ("version", lambda item: item.__setitem__("version", "2.0.1")),
        ("namespace", lambda item: item.__setitem__("namespace", "fixture")),
        ("task-tuple", lambda item: item.__setitem__("taskId", "TASK-D1-02")),
        ("operation-tuple", lambda item: item.__setitem__("operation", "task-completion")),
        ("run-tuple", lambda item: item.__setitem__("runId", "run-other")),
        ("nonce-tuple", lambda item: item.__setitem__("nonce", "nonce-other")),
        ("user-namespace-descriptor-join", lambda item: item["userNamespace"].__setitem__("inode", 99)),
        ("seed-root-descriptor-join", lambda item: item["seedRoot"].__setitem__("inode", 99)),
        ("parent-adapter-pid-alias", lambda item: item.__setitem__(
            "adapterPidNamespace", copy.deepcopy(item["parentPidNamespace"]))),
        ("service-adapter-mount-alias", lambda item: item.__setitem__(
            "adapterMountNamespace", copy.deepcopy(item["serviceMountNamespace"]))),
        ("identity-extra-field", lambda item: item["userNamespace"].__setitem__("kind", "user")),
        ("identity-bool", lambda item: item["userNamespace"].__setitem__("device", True)),
        ("identity-unsafe", lambda item: item["userNamespace"].__setitem__("device", 2**53)),
        ("adapter-uid-zero", lambda item: item.__setitem__("adapterUid", 0)),
        ("adapter-uid-overflow-id", lambda item: item.__setitem__("adapterUid", 65534)),
        ("adapter-service-uid-equal", lambda item: item.__setitem__("serviceUid", 1001)),
        ("adapter-service-gid-equal", lambda item: item.__setitem__("serviceGid", 1003)),
        ("descriptor-uid-join", lambda item: item.__setitem__("adapterUid", 1011)),
        ("proc-durable-alias", lambda item: item.__setitem__(
            "durableStateRoot", copy.deepcopy(item["serviceProcRoot"]))),
        ("socket-domain", lambda item: item.__setitem__("socketDomain", "AF_INET")),
        ("socket-type", lambda item: item.__setitem__("socketType", "SOCK_STREAM")),
        ("socket-creation", lambda item: item.__setitem__("socketCreation", "connect")),
        ("socket-flags", lambda item: item.__setitem__("socketSendFlags", "0")),
        ("pass-credentials", lambda item: item.__setitem__("passCredentials", False)),
        ("requested-buffer", lambda item: item.__setitem__("requestedSocketBufferBytes", 1)),
        ("effective-buffer", lambda item: item.__setitem__("minimumEffectiveSocketBufferBytes", 4194304)),
        ("maximum-frame", lambda item: item.__setitem__("maximumFrameBytes", 4194303)),
        ("terminal-count", lambda item: item.__setitem__("maximumTerminalAcceptances", 2)),
        ("exec-operation", lambda item: item.__setitem__("execOperation", "execve")),
        ("static-required", lambda item: item.__setitem__("staticElfRequired", False)),
        ("service-executable-fd", lambda item: item.__setitem__("serviceExecutableFd", 43)),
        ("argv", lambda item: item.__setitem__("serviceArgv", ["wrong"])),
        ("argv-extra", lambda item: item["serviceArgv"].append("extra")),
        ("environment", lambda item: item["serviceEnvironment"].append("A=B")),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in scalar_mutations)

    map_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("uid-map-count", lambda item: item["uidMap"].pop()),
        ("gid-map-count", lambda item: item["gidMap"].append(copy.deepcopy(item["gidMap"][1]))),
        ("map-field", lambda item: item["uidMap"][0].__setitem__("extra", 0)),
        ("map-length", lambda item: item["uidMap"][0].__setitem__("length", 2)),
        ("map-inside-order", lambda item: item["uidMap"].reverse()),
        ("map-inside-not-identity", lambda item: item["uidMap"][0].__setitem__("insideId", 999)),
        ("map-outside-reuse", lambda item: item["gidMap"][1].__setitem__(
            "outsideId", item["uidMap"][0]["outsideId"])),
        ("map-outside-overflow-id", lambda item: item["gidMap"][0].__setitem__("outsideId", 65534)),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in map_mutations)

    mount_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("mount-not-array", lambda item: item.__setitem__("serviceMounts", {})),
        ("mount-not-object", lambda item: item["serviceMounts"].__setitem__(0, 1)),
        ("mount-field", lambda item: item["serviceMounts"][0].__setitem__("extra", True)),
        ("mount-flag-type", lambda item: item["serviceMounts"][0].__setitem__("readOnly", 1)),
        ("mount-relative", lambda item: item["serviceMounts"][0].__setitem__("target", "runtime")),
        ("mount-empty-component", lambda item: item["serviceMounts"][0].__setitem__("target", "/a//b")),
        ("mount-dot", lambda item: item["serviceMounts"][0].__setitem__("target", "/a/./b")),
        ("mount-dotdot", lambda item: item["serviceMounts"][0].__setitem__("target", "/a/../b")),
        ("mount-trailing-slash", lambda item: item["serviceMounts"][0].__setitem__("target", "/a/")),
        ("mount-component-256", lambda item: item["serviceMounts"][0].__setitem__("target", "/" + "a" * 256)),
        ("mount-path-4097", lambda item: item["serviceMounts"][0].__setitem__(
            "target", "/" + "/".join("a" * 255 for _ in range(16)) + "/a" * 8)),
        ("mount-nfd", lambda item: item["serviceMounts"][0].__setitem__("target", "/runtime/e\u0301")),
        ("mount-combining-order", lambda item: item["serviceMounts"][0].__setitem__("target", "/runtime/a\u0315\u0300")),
        ("mount-hangul-nfd", lambda item: item["adapterMounts"][0].__setitem__("target", "/input/가")),
        ("adapter-seed-source", lambda item: item["adapterMounts"][0].__setitem__(
            "source", copy.deepcopy(item["seedRoot"]))),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in mount_mutations)

    two_mounts = _mutated(base, lambda item: item["serviceMounts"].append(
        _mount("/aaa", 30, 33)))
    vectors.extend([
        _vector("mount-order", two_mounts, False),
        _vector("mount-duplicate", _mutated(base, lambda item: item["serviceMounts"].append(
            copy.deepcopy(item["serviceMounts"][0]))), False),
    ])

    role_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("fd-role-count", lambda item: item["fdRoles"].pop()),
        ("fd-role-order", lambda item: item["fdRoles"].reverse()),
        ("fd-role-field", lambda item: item["fdRoles"][0].__setitem__("extra", 0)),
        ("fd-role-process", lambda item: item["fdRoles"][0].__setitem__("process", "candidate")),
        ("fd-role-stage", lambda item: item["fdRoles"][0].__setitem__("stage", "setup")),
        ("fd-role-name", lambda item: item["fdRoles"][0].__setitem__("role", "other")),
        ("fd-role-nonascii", lambda item: item["fdRoles"][0].__setitem__("role", "rôle")),
        ("fd-role-close", lambda item: item["fdRoles"][5].__setitem__("closeOnExec", False)),
        ("fd-role-unsafe", lambda item: item["fdRoles"][5].__setitem__("fd", 2**53)),
        ("fd-role-int-overflow", lambda item: item["fdRoles"][5].__setitem__("fd", 2**31)),
        ("fd-role-duplicate-number", lambda item: item["fdRoles"][4].__setitem__("fd", 41)),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in role_mutations)

    capability_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("preseed-missing", lambda item: item["preSeedCapabilities"].pop()),
        ("preseed-order", lambda item: item["preSeedCapabilities"].reverse()),
        ("preseed-extra", lambda item: item["preSeedCapabilities"].append(22)),
        ("custody-old", lambda item: item.__setitem__("custodyCapabilities", [19])),
        ("adapter-capability", lambda item: item["adapterCapabilities"].append(1)),
        ("final-capability", lambda item: item["finalServiceCapabilities"].append(19)),
        ("capability-bool", lambda item: item["custodyCapabilities"].__setitem__(0, True)),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in capability_mutations)

    seccomp_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("seccomp-count", lambda item: item["seccompPolicies"].pop()),
        ("seccomp-order", lambda item: item["seccompPolicies"].reverse()),
        ("seccomp-stage", lambda item: item["seccompPolicies"][0].__setitem__("stage", "service-final")),
        ("seccomp-hard-constraint", lambda item: item["seccompPolicies"][0]["rules"][0].__setitem__("syscall", "capset")),
        ("seccomp-executable-fd", lambda item: next(
            rule for rule in item["seccompPolicies"][1]["rules"]
            if rule["syscall"] == "execveat")["arguments"][0].__setitem__("value", _hex(43))),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in seccomp_mutations)
    return vectors


def _compile(binary: Path, *, sanitizer: bool) -> None:
    flags = (
        ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        if sanitizer else ["-O2", "-static", "-no-pie"]
    )
    sources = [
        _HERE / "task_qualification_isolation_policy_v2_driver.c",
        _HERE / "task_qualification_isolation_policy_v2.c",
        _HERE / "task_qualification_unicode_v2.c",
        _HERE / "task_qualification_seccomp_v2.c",
        _HERE / "task_qualification_pf_jcs_v2.c",
    ]
    completed = subprocess.run(
        [
            "/usr/bin/cc", *flags, "-std=c11", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-I", str(_HERE), "-o", str(binary),
            *(str(source) for source in sources), "-lcrypto", "-ldl", "-pthread",
        ],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout:
        raise AssertionError(
            f"policy {'sanitizer' if sanitizer else 'static'} compile failed: "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def _inspect_static(binary: Path) -> None:
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
            metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("policy driver is not an ordinary single-link ELF")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(f"security.capability absence errno={exc.errno}") from exc
    else:
        raise AssertionError("policy driver unexpectedly has security.capability")
    completed = subprocess.run(
        ["/usr/bin/readelf", "-W", "-l", "-d", str(binary)],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0 or completed.stderr:
        raise AssertionError(f"ELF inspection failed: {completed.stderr!r}")
    if any("INTERP" in line or "(NEEDED)" in line
           for line in completed.stdout.splitlines()):
        raise AssertionError("policy driver contains PT_INTERP or DT_NEEDED")


def _analyze_sources() -> None:
    sources = [
        _HERE / "task_qualification_isolation_policy_v2_driver.c",
        _HERE / "task_qualification_isolation_policy_v2.c",
        _HERE / "task_qualification_unicode_v2.c",
        _HERE / "task_qualification_seccomp_v2.c",
        _HERE / "task_qualification_pf_jcs_v2.c",
    ]
    completed = subprocess.run(
        [
            "/usr/bin/cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-fanalyzer", "-fsyntax-only", "-I", str(_HERE),
            *(str(source) for source in sources),
        ],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout or completed.stderr:
        raise AssertionError(
            f"policy static analysis failed: stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )


def _invoke(
    binary: Path,
    vector: Vector,
    payload: Path,
    *,
    sanitizer: bool,
) -> subprocess.CompletedProcess[str]:
    payload.write_bytes(vector.payload)
    digest = vector.digest_override or _digest(vector.payload)
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": "detect_leaks=1:symbolize=0:halt_on_error=1:abort_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    return subprocess.run(
        [str(binary), "--validate" if vector.accepted else "--reject",
         str(payload), digest],
        cwd=binary.parent,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )


def _run_matrix(binary: Path, base: Path, vectors: list[Vector], *, sanitizer: bool) -> list[Result]:
    results: list[Result] = []
    payload = base / ("policy-asan.json" if sanitizer else "policy.json")
    for vector in vectors:
        completed = _invoke(binary, vector, payload, sanitizer=sanitizer)
        passed = completed.returncode == 0 and not completed.stdout and not completed.stderr
        detail = "" if passed else (
            f"exit={completed.returncode} stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )
        results.append(Result(("asan-" if sanitizer else "") + vector.name, passed, detail))
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        print("task-qualification isolation-policy self-test: requires Linux x86_64")
        return 1
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-isolation-policy-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        binary = base / "pf-taskqualification-isolation-policy-v2-test"
        sanitizer_binary = base / "pf-taskqualification-isolation-policy-v2-asan"
        try:
            subprocess.run(
                ["/usr/bin/python3", "-I", "-S",
                 str(_HERE / "generate_task_qualification_unicode_v2.py"), "--check"],
                cwd=_ROOT,
                env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
                check=True,
            )
            vectors = _build_vectors()
            _compile(binary, sanitizer=False)
            _inspect_static(binary)
            _compile(sanitizer_binary, sanitizer=True)
            _analyze_sources()
            results = _run_matrix(binary, base, vectors, sanitizer=False)
            results.extend(_run_matrix(
                sanitizer_binary, base, vectors, sanitizer=True))
            invalid = subprocess.run(
                [str(binary), "--invalid-input"],
                cwd=base,
                env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
                check=False,
            )
            results.append(Result(
                "invalid-api-input",
                invalid.returncode == 0 and not invalid.stdout and not invalid.stderr,
                "" if invalid.returncode == 0 else
                f"exit={invalid.returncode} stdout={invalid.stdout!r} stderr={invalid.stderr!r}",
            ))
        except (AssertionError, OSError, subprocess.SubprocessError) as exc:
            print(f"task-qualification isolation-policy self-test: PRECHECK-FAIL: {exc}")
            return 1
    for result in results:
        print(result)
    passed = sum(result.passed for result in results)
    print(f"task-qualification isolation-policy self-test: {passed}/{len(results)} passed")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())

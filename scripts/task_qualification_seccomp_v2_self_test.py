#!/usr/bin/env python3
"""Development matrix for the ADR-0021 signed seccomp v2 loader.

The matrix compiles the production parser/compiler/installer into a static ELF,
checks closed canonical policies and irreversible-transition hard constraints,
and installs real deny-default filters in disposable children. These fixtures
are not candidate-external signed policies and do not constitute formal task
qualification or hermetic evidence.
"""

from __future__ import annotations

import argparse
import copy
import errno
import json
import os
import platform
import stat
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
_MAX_U64 = (1 << 64) - 1

# The production component is deliberately pinned to AUDIT_ARCH_X86_64.
_SYSCALL = {
    "open": 2,
    "getpid": 39,
    "sendmsg": 46,
    "clone": 56,
    "fork": 57,
    "vfork": 58,
    "execve": 59,
    "fcntl": 72,
    "creat": 85,
    "ptrace": 101,
    "setuid": 105,
    "setgid": 106,
    "setreuid": 113,
    "setregid": 114,
    "getgroups": 115,
    "setgroups": 116,
    "setresuid": 117,
    "setresgid": 119,
    "setfsuid": 122,
    "setfsgid": 123,
    "capset": 126,
    "pivot_root": 155,
    "prctl": 157,
    "chroot": 161,
    "mount": 165,
    "umount2": 166,
    "exit_group": 231,
    "openat": 257,
    "unshare": 272,
    "dup3": 292,
    "sendmmsg": 307,
    "setns": 308,
    "process_vm_writev": 311,
    "seccomp": 317,
    "execveat": 322,
    "clone3": 435,
    "openat2": 437,
    "pidfd_getfd": 438,
    "dup": 32,
    "dup2": 33,
}

_PR_CAPBSET_READ = 23
_PR_CAPBSET_DROP = 24
_PR_GET_NO_NEW_PRIVS = 39
_PR_CAP_AMBIENT = 47
_PR_CAP_AMBIENT_IS_SET = 1
_PR_CAP_AMBIENT_CLEAR_ALL = 4
_SECCOMP_SET_MODE_FILTER = 1
_AT_EMPTY_PATH = 0x1000
_PROC_ROOT_FD = 90
_DURABLE_ROOT_FD = 91
_SERVICE_EXECUTABLE_FD = 92
_RUNTIME_FD = 3


@dataclass(frozen=True)
class Vector:
    name: str
    stage: str
    payload: bytes
    accepted: bool


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
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True,
    ).encode("ascii")


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
    return {
        "action": "allow",
        "arguments": list(arguments),
        "syscall": syscall,
    }


def _sort_rules(rules: list[dict[str, Any]]) -> None:
    rules.sort(key=lambda item: (
        _SYSCALL[item["syscall"]], _canonical(item["arguments"]),
    ))


def _policy(stage: str, rules: list[dict[str, Any]]) -> dict[str, Any]:
    copied = copy.deepcopy(rules)
    _sort_rules(copied)
    return {
        "auditArch": "AUDIT_ARCH_X86_64",
        "defaultAction": "kill-process",
        "noNewPrivs": True,
        "rules": copied,
        "stage": stage,
    }


def _normalize(policy: dict[str, Any]) -> dict[str, Any]:
    _sort_rules(policy["rules"])
    return policy


def _runtime_adapter_policy() -> dict[str, Any]:
    return _policy("adapter", [
        _rule(
            "fcntl",
            _argument(0, _RUNTIME_FD),
            _argument(1, 1),  # F_GETFD
            _argument(2, 0),
        ),
        _rule(
            "exit_group",
            _argument(0, 0, operation="masked-eq", mask=0xFF),
        ),
    ])


def _prctl(option: int, argument1: int, argument2: int = 0) -> dict[str, Any]:
    return _rule(
        "prctl",
        _argument(0, option),
        _argument(1, argument1),
        _argument(2, argument2),
        _argument(3, 0),
        _argument(4, 0),
    )


def _custody_policy() -> dict[str, Any]:
    return _policy("custody-pre-exec", [
        _rule("capset"),
        _prctl(_PR_CAPBSET_READ, 0),
        _prctl(_PR_CAPBSET_DROP, 19),
        _prctl(_PR_CAPBSET_DROP, 8),
        _prctl(_PR_GET_NO_NEW_PRIVS, 0),
        _prctl(_PR_CAP_AMBIENT, _PR_CAP_AMBIENT_IS_SET, 0),
        _prctl(_PR_CAP_AMBIENT, _PR_CAP_AMBIENT_CLEAR_ALL),
        _rule(
            "seccomp",
            _argument(0, _SECCOMP_SET_MODE_FILTER),
            _argument(1, 0),
        ),
        _rule(
            "execveat",
            _argument(0, _SERVICE_EXECUTABLE_FD),
            _argument(4, _AT_EMPTY_PATH),
        ),
    ])


def _service_policy() -> dict[str, Any]:
    return _policy("service-final", [
        _rule("capset"),
        _prctl(_PR_GET_NO_NEW_PRIVS, 0),
        _rule("exit_group"),
    ])


def _arg_value(rule: dict[str, Any], index: int) -> int | None:
    for argument in rule["arguments"]:
        if argument["index"] == index:
            return int(argument["value"], 16)
    return None


def _remove_rule(
    policy: dict[str, Any], predicate,
) -> dict[str, Any]:
    policy["rules"] = [
        rule for rule in policy["rules"] if not predicate(rule)
    ]
    return _normalize(policy)


def _mutated(policy: dict[str, Any], mutate, *, normalize: bool = True) -> dict[str, Any]:
    result = copy.deepcopy(policy)
    mutate(result)
    return _normalize(result) if normalize else result


def _vector(
    name: str,
    policy: dict[str, Any] | bytes,
    stage: str,
    accepted: bool,
) -> Vector:
    return Vector(
        name,
        stage,
        policy if isinstance(policy, bytes) else _canonical(policy),
        accepted,
    )


def _build_vectors() -> list[Vector]:
    adapter = _runtime_adapter_policy()
    custody = _custody_policy()
    service = _service_policy()
    vectors = [
        _vector("adapter-baseline", adapter, "adapter", True),
        _vector("custody-baseline", custody, "custody-pre-exec", True),
        _vector("service-final-baseline", service, "service-final", True),
    ]

    vectors.extend([
        _vector("canonical-whitespace", _canonical(adapter).replace(
            b'{"auditArch"', b'{ "auditArch"', 1), "adapter", False),
        _vector("canonical-escaped-string", _canonical(adapter).replace(
            b'"stage":"adapter"', b'"stage":"adapt\\u0065r"', 1),
            "adapter", False),
        _vector("root-not-object", b"[]", "adapter", False),
        _vector("unknown-policy-field", _mutated(
            adapter, lambda item: item.__setitem__("extra", 1)), "adapter", False),
        _vector("missing-policy-field", _mutated(
            adapter, lambda item: item.pop("defaultAction")), "adapter", False),
        _vector("wrong-audit-arch", _mutated(
            adapter, lambda item: item.__setitem__("auditArch", "AUDIT_ARCH_AARCH64")),
            "adapter", False),
        _vector("wrong-default-action", _mutated(
            adapter, lambda item: item.__setitem__("defaultAction", "allow")),
            "adapter", False),
        _vector("no-new-privs-false", _mutated(
            adapter, lambda item: item.__setitem__("noNewPrivs", False)),
            "adapter", False),
        _vector("stage-context-mismatch", adapter, "service-final", False),
        _vector("empty-rules", _policy("adapter", []), "adapter", False),
    ])

    def unknown_syscall(item: dict[str, Any]) -> None:
        item["rules"][0]["syscall"] = "not_a_linux_syscall"

    def missing_rule_field(item: dict[str, Any]) -> None:
        item["rules"][0].pop("action")

    def extra_rule_field(item: dict[str, Any]) -> None:
        item["rules"][0]["errno"] = 1

    def wrong_action(item: dict[str, Any]) -> None:
        item["rules"][0]["action"] = "errno"

    vectors.extend([
        _vector("unknown-syscall", _mutated(
            adapter, unknown_syscall, normalize=False), "adapter", False),
        _vector("missing-rule-field", _mutated(
            adapter, missing_rule_field), "adapter", False),
        _vector("extra-rule-field", _mutated(
            adapter, extra_rule_field), "adapter", False),
        _vector("non-allow-action", _mutated(
            adapter, wrong_action), "adapter", False),
        _vector("rule-order", _mutated(
            adapter, lambda item: item["rules"].reverse(), normalize=False),
            "adapter", False),
    ])

    duplicate = copy.deepcopy(adapter)
    duplicate["rules"].append(copy.deepcopy(duplicate["rules"][0]))
    _sort_rules(duplicate["rules"])
    vectors.append(_vector("duplicate-rule", duplicate, "adapter", False))

    distinct_fcntl = copy.deepcopy(adapter)
    distinct_fcntl["rules"].append(_rule(
        "fcntl", _argument(0, _RUNTIME_FD), _argument(1, 3), _argument(2, 0),
    ))
    vectors.append(_vector(
        "same-syscall-distinct-arguments", _normalize(distinct_fcntl),
        "adapter", True,
    ))

    def mutate_first_argument(item: dict[str, Any], mutate) -> None:
        mutate(item["rules"][0]["arguments"])

    vectors.extend([
        _vector("argument-index-out-of-range", _mutated(
            adapter,
            lambda item: mutate_first_argument(
                item, lambda arguments: arguments[-1].__setitem__("index", 6),
            )), "adapter", False),
        _vector("argument-order", _mutated(
            adapter,
            lambda item: mutate_first_argument(item, lambda arguments: arguments.reverse()),
            normalize=False), "adapter", False),
        _vector("duplicate-argument-index", _mutated(
            adapter,
            lambda item: mutate_first_argument(
                item, lambda arguments: arguments.append(copy.deepcopy(arguments[-1])),
            )), "adapter", False),
        _vector("argument-not-object", _mutated(
            adapter,
            lambda item: item["rules"][0]["arguments"].__setitem__(0, 0),
        ), "adapter", False),
        _vector("argument-extra-field", _mutated(
            adapter,
            lambda item: item["rules"][0]["arguments"][0].__setitem__("width", 64),
        ), "adapter", False),
        _vector("argument-operation", _mutated(
            adapter,
            lambda item: item["rules"][0]["arguments"][0].__setitem__("operation", "lt"),
        ), "adapter", False),
        _vector("eq-mask-not-full", _mutated(
            adapter,
            lambda item: item["rules"][0]["arguments"][0].__setitem__(
                "mask", "00000000000000ff",
            ),
        ), "adapter", False),
        _vector("masked-eq-zero-mask", _mutated(
            adapter,
            lambda item: item["rules"][0]["arguments"][0].update({
                "operation": "masked-eq", "mask": "0000000000000000",
            }),
        ), "adapter", False),
        _vector("masked-eq-value-outside-mask", _mutated(
            adapter,
            lambda item: item["rules"][0]["arguments"][0].update({
                "operation": "masked-eq",
                "mask": "0000000000000001",
                "value": "0000000000000002",
            }),
        ), "adapter", False),
        _vector("uppercase-hex", _mutated(
            adapter,
            lambda item: item["rules"][0]["arguments"][0].__setitem__(
                "value", "000000000000000A",
            ),
        ), "adapter", False),
        _vector("short-hex", _mutated(
            adapter,
            lambda item: item["rules"][0]["arguments"][0].__setitem__(
                "value", "000000000000003",
            ),
        ), "adapter", False),
    ])

    six_arguments = _policy("adapter", [
        _rule("exit_group", *(_argument(index, 0) for index in range(6))),
    ])
    seven_arguments = copy.deepcopy(six_arguments)
    seven_arguments["rules"][0]["arguments"].append(_argument(6, 0))
    vectors.extend([
        _vector("six-arguments-bound", six_arguments, "adapter", True),
        _vector("seven-arguments-rejected", seven_arguments, "adapter", False),
    ])

    max_rules = _policy("adapter", [
        _rule("exit_group", _argument(0, value)) for value in range(256)
    ])
    over_rules = _policy("adapter", [
        _rule("exit_group", _argument(0, value)) for value in range(257)
    ])
    instruction_overflow = _policy("adapter", [
        _rule(
            "exit_group",
            *(
                _argument(
                    index,
                    value if index == 0 else 0,
                    operation="masked-eq",
                    mask=_MAX_U64,
                )
                for index in range(6)
            ),
        )
        for value in range(256)
    ])
    vectors.extend([
        _vector("rule-count-bound", max_rules, "adapter", True),
        _vector("rule-count-overflow", over_rules, "adapter", False),
        _vector("bpf-instruction-bound", instruction_overflow, "adapter", False),
    ])

    forbidden_groups = {
        "process-creation": ("fork", "vfork", "clone", "clone3"),
        "fd-dup-transfer": ("dup", "dup2", "dup3", "pidfd_getfd", "sendmsg", "sendmmsg"),
        "exec-path": ("execve", "execveat"),
        "process-namespace": (
            "ptrace", "process_vm_writev", "mount", "umount2", "pivot_root",
            "chroot", "setns", "unshare",
        ),
        "pathname-open": ("open", "openat2", "creat"),
        "credential-mutation": (
            "setuid", "setgid", "setreuid", "setregid", "setresuid", "setresgid",
            "setfsuid", "setfsgid", "setgroups",
        ),
    }
    for group, names in forbidden_groups.items():
        for name in names:
            vectors.append(_vector(
                f"forbidden-{group}-{name}",
                _policy("adapter", [_rule(name), _rule("exit_group")]),
                "adapter", False,
            ))

    proc_open = _rule(
        "openat",
        _argument(0, _PROC_ROOT_FD),
        _argument(2, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW),
    )
    durable_open = _rule(
        "openat",
        _argument(0, _DURABLE_ROOT_FD),
        _argument(2, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                  os.O_CLOEXEC | os.O_NOFOLLOW),
        _argument(3, 0o600),
    )
    vectors.extend([
        _vector("openat-proc-fixed", _policy(
            "adapter", [proc_open, _rule("exit_group")]), "adapter", True),
        _vector("openat-durable-fixed", _policy(
            "adapter", [durable_open, _rule("exit_group")]), "adapter", True),
        _vector("openat-at-fdcwd", _policy("adapter", [
            _rule("openat", _argument(0, -100), _argument(
                2, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)),
        ]), "adapter", False),
        _vector("openat-unknown-dirfd", _policy("adapter", [
            _rule("openat", _argument(0, 89), _argument(
                2, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)),
        ]), "adapter", False),
        _vector("openat-pointer-constraint", _policy("adapter", [
            _rule("openat", _argument(0, _PROC_ROOT_FD), _argument(1, 0),
                  _argument(2, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)),
        ]), "adapter", False),
        _vector("openat-flags", _policy("adapter", [
            _rule("openat", _argument(0, _PROC_ROOT_FD), _argument(2, os.O_RDONLY)),
        ]), "adapter", False),
        _vector("openat-create-mode-missing", _policy("adapter", [
            _rule("openat", _argument(0, _DURABLE_ROOT_FD),
                  _argument(2, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW)),
        ]), "adapter", False),
        _vector("openat-create-mode-wrong", _policy("adapter", [
            _rule("openat", _argument(0, _DURABLE_ROOT_FD),
                  _argument(2, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW),
                  _argument(3, 0o644)),
        ]), "adapter", False),
    ])

    vectors.extend([
        _vector("fcntl-setfd", _policy("adapter", [
            _rule("fcntl", _argument(0, 3), _argument(1, 2), _argument(2, 0)),
        ]), "adapter", True),
        _vector("fcntl-command-missing", _policy("adapter", [
            _rule("fcntl", _argument(0, 3)),
        ]), "adapter", False),
        _vector("fcntl-dupfd", _policy("adapter", [
            _rule("fcntl", _argument(0, 3), _argument(1, 0)),
        ]), "adapter", False),
        _vector("fcntl-unknown-command", _policy("adapter", [
            _rule("fcntl", _argument(0, 3), _argument(1, 999)),
        ]), "adapter", False),
    ])

    adapter_get_nnp = _policy("adapter", [
        _prctl(_PR_GET_NO_NEW_PRIVS, 0), _rule("exit_group"),
    ])
    adapter_bounding_read = _policy("adapter", [
        _prctl(_PR_CAPBSET_READ, 0), _rule("exit_group"),
    ])
    vectors.extend([
        _vector("adapter-read-only-nnp", adapter_get_nnp, "adapter", True),
        _vector("adapter-bounding-read", adapter_bounding_read, "adapter", False),
        _vector("adapter-capset", _policy(
            "adapter", [_rule("capset")]), "adapter", False),
    ])

    def is_drop(rule: dict[str, Any], capability: int) -> bool:
        return (rule["syscall"] == "prctl" and
                _arg_value(rule, 0) == _PR_CAPBSET_DROP and
                _arg_value(rule, 1) == capability)

    def is_ambient_clear(rule: dict[str, Any]) -> bool:
        return (rule["syscall"] == "prctl" and
                _arg_value(rule, 0) == _PR_CAP_AMBIENT and
                _arg_value(rule, 1) == _PR_CAP_AMBIENT_CLEAR_ALL)

    for name, predicate in (
        ("custody-missing-drop-ptrace", lambda rule: is_drop(rule, 19)),
        ("custody-missing-drop-setpcap", lambda rule: is_drop(rule, 8)),
        ("custody-missing-ambient-clear", is_ambient_clear),
        ("custody-missing-capset", lambda rule: rule["syscall"] == "capset"),
        ("custody-missing-overlay", lambda rule: rule["syscall"] == "seccomp"),
        ("custody-missing-exec", lambda rule: rule["syscall"] == "execveat"),
    ):
        vectors.append(_vector(
            name, _remove_rule(copy.deepcopy(custody), predicate),
            "custody-pre-exec", False,
        ))

    extra_drop = copy.deepcopy(custody)
    extra_drop["rules"].append(_prctl(_PR_CAPBSET_DROP, 7))
    vectors.append(_vector(
        "custody-extra-bounding-drop", _normalize(extra_drop),
        "custody-pre-exec", False,
    ))

    relaxed_drop = copy.deepcopy(custody)
    for rule in relaxed_drop["rules"]:
        if is_drop(rule, 19):
            rule["arguments"].pop()
            break
    vectors.append(_vector(
        "custody-relaxed-bounding-drop", _normalize(relaxed_drop),
        "custody-pre-exec", False,
    ))

    capset_argument = copy.deepcopy(custody)
    for rule in capset_argument["rules"]:
        if rule["syscall"] == "capset":
            rule["arguments"] = [_argument(0, 0)]
            break
    vectors.append(_vector(
        "custody-capset-pointer-constraint", _normalize(capset_argument),
        "custody-pre-exec", False,
    ))

    overlay_flags = copy.deepcopy(custody)
    for rule in overlay_flags["rules"]:
        if rule["syscall"] == "seccomp":
            rule["arguments"][1]["value"] = _hex(1)
            break
    vectors.append(_vector(
        "custody-overlay-flags", _normalize(overlay_flags),
        "custody-pre-exec", False,
    ))

    relaxed_overlay = copy.deepcopy(custody)
    for rule in relaxed_overlay["rules"]:
        if rule["syscall"] == "seccomp":
            rule["arguments"].pop()
            break
    vectors.append(_vector(
        "custody-relaxed-overlay", _normalize(relaxed_overlay),
        "custody-pre-exec", False,
    ))

    wrong_exec_fd = copy.deepcopy(custody)
    wrong_exec_flags = copy.deepcopy(custody)
    for policy, index, value in (
        (wrong_exec_fd, 0, _DURABLE_ROOT_FD),
        (wrong_exec_flags, 4, 0),
    ):
        for rule in policy["rules"]:
            if rule["syscall"] == "execveat":
                for argument in rule["arguments"]:
                    if argument["index"] == index:
                        argument["value"] = _hex(value)
                break
    vectors.extend([
        _vector("custody-exec-fd", _normalize(wrong_exec_fd),
                "custody-pre-exec", False),
        _vector("custody-exec-flags", _normalize(wrong_exec_flags),
                "custody-pre-exec", False),
    ])

    query_capability = copy.deepcopy(custody)
    ambient_capability = copy.deepcopy(custody)
    for rule in query_capability["rules"]:
        if _arg_value(rule, 0) == _PR_CAPBSET_READ:
            rule["arguments"][1]["value"] = _hex(64)
            break
    for rule in ambient_capability["rules"]:
        if (_arg_value(rule, 0) == _PR_CAP_AMBIENT and
                _arg_value(rule, 1) == _PR_CAP_AMBIENT_IS_SET):
            rule["arguments"][2]["value"] = _hex(64)
            break
    vectors.extend([
        _vector("custody-bounding-query-range", _normalize(query_capability),
                "custody-pre-exec", False),
        _vector("custody-ambient-query-range", _normalize(ambient_capability),
                "custody-pre-exec", False),
    ])

    vectors.extend([
        _vector("service-final-missing-capset", _remove_rule(
            copy.deepcopy(service), lambda rule: rule["syscall"] == "capset"),
            "service-final", False),
        _vector("service-final-bounding-read", _policy("service-final", [
            _rule("capset"), _prctl(_PR_CAPBSET_READ, 0),
        ]), "service-final", False),
        _vector("service-final-bounding-drop", _policy("service-final", [
            _rule("capset"), _prctl(_PR_CAPBSET_DROP, 19),
        ]), "service-final", False),
        _vector("service-final-ambient-query", _policy("service-final", [
            _rule("capset"),
            _prctl(_PR_CAP_AMBIENT, _PR_CAP_AMBIENT_IS_SET, 0),
        ]), "service-final", False),
        _vector("service-final-overlay", _policy("service-final", [
            _rule("capset"),
            _rule("seccomp", _argument(0, 1), _argument(1, 0)),
        ]), "service-final", False),
    ])
    return vectors


def _compile(binary: Path, *, sanitizer: bool) -> None:
    flags = ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"] \
        if sanitizer else ["-static", "-no-pie", "-O2"]
    command = [
        "/usr/bin/cc", *flags, "-std=c11", "-Wall", "-Wextra", "-Werror",
        "-Wpedantic", "-I", str(_HERE), "-o", str(binary),
        str(_HERE / "task_qualification_seccomp_v2_driver.c"),
        str(_HERE / "task_qualification_seccomp_v2.c"),
        str(_HERE / "task_qualification_pf_jcs_v2.c"),
    ]
    completed = subprocess.run(
        command,
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout:
        raise AssertionError(
            f"seccomp {'sanitizer' if sanitizer else 'static'} compile failed: "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def _inspect_static(binary: Path) -> None:
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
            metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("seccomp driver is not an ordinary single-link executable")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(
                f"security.capability absence returned errno {exc.errno}"
            ) from exc
    else:
        raise AssertionError("seccomp driver unexpectedly has security.capability")
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
        raise AssertionError(f"static ELF inspection failed: {completed.stderr!r}")
    if any("INTERP" in line or "(NEEDED)" in line
           for line in completed.stdout.splitlines()):
        raise AssertionError("seccomp driver contains PT_INTERP or DT_NEEDED")


def _analyze_sources() -> None:
    completed = subprocess.run(
        [
            "/usr/bin/cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-fanalyzer", "-fsyntax-only", "-I", str(_HERE),
            str(_HERE / "task_qualification_seccomp_v2_driver.c"),
            str(_HERE / "task_qualification_seccomp_v2.c"),
            str(_HERE / "task_qualification_pf_jcs_v2.c"),
        ],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout or completed.stderr:
        raise AssertionError(
            f"seccomp static analysis failed: stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )


def _invoke(
    binary: Path,
    arguments: list[str],
    *,
    sanitizer: bool = False,
) -> subprocess.CompletedProcess[bytes]:
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": "detect_leaks=1:halt_on_error=1:abort_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1",
        })
    return subprocess.run(
        [str(binary), *arguments],
        cwd=binary.parent,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )


def _require_clean(completed: subprocess.CompletedProcess[bytes]) -> None:
    if completed.returncode != 0 or completed.stdout or completed.stderr:
        raise AssertionError(
            f"rc={completed.returncode} stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )


def _invoke_clean(
    binary: Path,
    arguments: list[str],
    *,
    sanitizer: bool = False,
) -> None:
    _require_clean(_invoke(binary, arguments, sanitizer=sanitizer))


def _run_vector(
    binary: Path,
    directory: Path,
    vector: Vector,
    *,
    sanitizer: bool = False,
) -> None:
    path = directory / f"{vector.name}.json"
    path.write_bytes(vector.payload)
    mode = "--validate" if vector.accepted else "--reject"
    _invoke_clean(
        binary, [mode, vector.stage, str(path)], sanitizer=sanitizer,
    )


def _source_contract() -> None:
    source = (_HERE / "task_qualification_seccomp_v2.c").read_text(encoding="utf-8")
    required = (
        "AUDIT_ARCH_X86_64",
        "SECCOMP_RET_KILL_PROCESS",
        "SECCOMP_RET_ALLOW",
        "pf_tq_seccomp_syscall_table_validate",
        "PR_CAPBSET_DROP",
        "PR_CAP_AMBIENT_CLEAR_ALL",
        "SECCOMP_SET_MODE_FILTER, 0U, &descriptor",
        "block_end - (comparison + 1U)",
    )
    if any(token not in source for token in required):
        raise AssertionError("deny-default compiler/install source contract drift")
    forbidden = (
        "SECCOMP_RET_ERRNO", "SECCOMP_RET_LOG", "SECCOMP_RET_TRACE",
        "SECCOMP_FILTER_FLAG_TSYNC", "prctl(PR_SET_SECCOMP",
    )
    if any(token in source for token in forbidden):
        raise AssertionError("seccomp source contains fallback or non-exact install mode")
    install_start = source.index("int pf_tq_seccomp_install_v2(")
    install = source[install_start:]
    ordered = (
        "pf_tq_seccomp_prepare(",
        "prctl(PR_GET_NO_NEW_PRIVS",
        "syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, 0U, &descriptor)",
    )
    offsets = [install.index(token) for token in ordered]
    if offsets != sorted(offsets) or any(install.count(token) != 1 for token in ordered):
        raise AssertionError("validate/NNP/install ordering drift")


def _case(name: str, operation) -> Result:
    try:
        operation()
    except Exception as exc:
        return Result(name, False, f"{type(exc).__name__}: {exc}")
    return Result(name, True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        print("task-qualification seccomp-v2 self-test: HOST-PRECHECK-FAIL: "
              "requires Linux x86_64")
        return 1
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-seccomp-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        directory = Path(temporary)
        binary = directory / "pf-taskqualification-seccomp-v2-test"
        sanitizer_binary = directory / "pf-taskqualification-seccomp-v2-sanitizer"
        try:
            vectors = _build_vectors()
            _compile(binary, sanitizer=False)
            _inspect_static(binary)
            _compile(sanitizer_binary, sanitizer=True)
            _analyze_sources()
        except Exception as exc:
            print(f"task-qualification seccomp-v2 self-test: PRECHECK-FAIL: {exc}")
            return 1

        results = [
            _case(vector.name, lambda vector=vector: _run_vector(
                binary, directory, vector,
            ))
            for vector in vectors
        ]
        adapter_path = directory / "runtime-adapter.json"
        adapter_path.write_bytes(_canonical(_runtime_adapter_policy()))
        for mode in (
            "--runtime-allowed",
            "--runtime-wrong-argument",
            "--runtime-high-bits",
            "--runtime-forbidden",
            "--runtime-mask-reject",
        ):
            results.append(_case(
                mode.removeprefix("--"),
                lambda mode=mode: _invoke_clean(
                    binary, [mode, str(adapter_path)],
                ),
            ))

        results.extend([
            _case(
                "invalid-policy-input",
                lambda: _invoke_clean(binary, ["--null-policy"]),
            ),
            _case(
                "invalid-stage-context",
                lambda: _invoke_clean(
                    binary, ["--invalid-context", str(adapter_path)],
                ),
            ),
            _case(
                "invalid-fixed-fd-context",
                lambda: _invoke_clean(
                    binary, ["--invalid-fd-context", str(adapter_path)],
                ),
            ),
            _case("source-contract", _source_contract),
        ])

        def sanitizer_matrix() -> None:
            for vector in vectors:
                _run_vector(
                    sanitizer_binary, directory, vector, sanitizer=True,
                )

        results.append(_case("asan-ubsan-validation-matrix", sanitizer_matrix))

    passed = sum(result.passed for result in results)
    print(f"task-qualification seccomp-v2 self-test: {passed}/{len(results)} passed")
    for result in results:
        print(result)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())

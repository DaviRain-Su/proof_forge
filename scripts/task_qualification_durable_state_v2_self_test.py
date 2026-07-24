#!/usr/bin/env python3
"""Focused durable nonce/head transaction tests for ADR-0021 §6.

This test compiles the candidate-external state-machine implementation as a
static ELF and exercises only its internal durable transaction boundary. It
does not sign an acceptance, hold role keys, or claim formal qualification.

The state files are append-only canonical events. Each transition uses an
O_EXCL temporary file, file fsync, renameat2(RENAME_NOREPLACE), and directory
fsync; stale ``active|signing`` records are recovered exactly once to
``rejected`` before a new ceremony may open seed files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

_HERE = Path(__file__).resolve().parent
_SOURCE = _HERE / "task_qualification_durable_state_v2.c"
_DRIVER = _HERE / "task_qualification_durable_state_v2_driver.c"
_HEADER = _HERE / "task_qualification_durable_state_v2.h"
_DOMAIN = b"pf.taskqual.durable-key.v2"
_TIMESTAMP = "2026-07-24T12:00:00Z"
_ACCEPTANCE = "sha256:" + "aa" * 32
_RESPONSE = "sha256:" + "bb" * 32


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def _canonical(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, allow_nan=False,
        sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")


def _tuple() -> tuple[str, str, str, str]:
    return ("TASK-D1-01", "task-qualification", "run-one", "nonce-one")


def _key(values: tuple[str, str, str, str]) -> str:
    task, operation, run_id, nonce = values
    return hashlib.sha256(
        _DOMAIN + b"\x00" + task.encode("ascii") + b"\x00"
        + operation.encode("ascii") + b"\x00" + run_id.encode("ascii")
        + b"\x00" + nonce.encode("ascii")
    ).hexdigest()


def _run(
    binary: Path,
    root: Path,
    command: str,
    *arguments: str,
    expected: int = 0,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [str(binary), str(root), command, *arguments],
        cwd=_HERE.parent,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=False,
    )
    if result.returncode != expected:
        raise AssertionError(
            f"{command} exit={result.returncode}, expected={expected}; "
            f"stdout={result.stdout!r}; stderr={result.stderr!r}"
        )
    return result


def _new_root(base: Path, name: str, mode: int = 0o700) -> Path:
    root = base / name
    root.mkdir(mode=mode)
    os.chmod(root, mode)
    return root


def _compile(binary: Path) -> None:
    result = subprocess.run(
        [
            "/usr/bin/cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-static", "-no-pie", "-o", str(binary),
            str(_SOURCE), str(_DRIVER), "-lcrypto", "-ldl", "-pthread",
        ],
        cwd=_HERE.parent,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"compile failed: {result.stderr}")
    if result.stdout:
        raise AssertionError("compiler wrote unexpected stdout")


def _validate_static_elf(binary: Path) -> None:
    metadata = binary.stat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        raise AssertionError("driver is not a single-link regular file")
    raw = binary.read_bytes()
    if len(raw) < 64 or raw[:6] != b"\x7fELF\x02\x01":
        raise AssertionError("driver is not ELF64 little-endian")
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", raw, 0)
    if header[2] != 62 or header[8] != 64 or header[9] != 56:
        raise AssertionError("ELF machine/header mismatch")
    offset, count = header[5], header[10]
    if count == 0 or offset + count * 56 > len(raw):
        raise AssertionError("ELF program headers invalid")
    for index in range(count):
        fields = struct.unpack_from("<IIQQQQQQ", raw, offset + index * 56)
        segment_type, segment_offset, segment_size = fields[0], fields[2], fields[5]
        if segment_offset + segment_size > len(raw):
            raise AssertionError("ELF segment exceeds file")
        if segment_type == 3:
            raise AssertionError("static driver contains PT_INTERP")
        if segment_type == 2:
            for cursor in range(segment_offset, segment_offset + segment_size, 16):
                tag, _value = struct.unpack_from("<QQ", raw, cursor)
                if tag == 0:
                    break
                if tag == 1:
                    raise AssertionError("static driver contains DT_NEEDED")


def _event_files(root: Path, key: str | None = None) -> list[Path]:
    return sorted(
        (
            path for path in root.iterdir()
            if path.name != ".lock"
            and (key is None or path.name.startswith(key + "."))
        ),
        key=lambda path: path.name.encode("ascii"),
    )


def _assert_event_chain(
    root: Path,
    values: tuple[str, str, str, str],
    statuses: list[str],
) -> list[dict]:
    key = _key(values)
    files = _event_files(root, key)
    if len(files) != len(statuses):
        raise AssertionError(f"event count {len(files)} != {len(statuses)}")
    records: list[dict] = []
    previous_digest: str | None = None
    for sequence, (path, status_name) in enumerate(zip(files, statuses)):
        expected_name = f"{key}.{sequence:03d}.{status_name}.json"
        if path.name != expected_name:
            raise AssertionError(f"event filename {path.name!r} != {expected_name!r}")
        metadata = path.stat()
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1
                or stat.S_IMODE(metadata.st_mode) != 0o600):
            raise AssertionError("event metadata is not regular/0600/single-link")
        raw = path.read_bytes()
        if not raw or raw.endswith(b"\n") or b"seed" in raw.lower():
            raise AssertionError("event bytes are empty/newline/private-material-shaped")
        record = json.loads(raw)
        if _canonical(record) != raw:
            raise AssertionError("event bytes are not canonical PF-JCS")
        if record["eventSequence"] != sequence or record["status"] != status_name:
            raise AssertionError("event sequence/status mismatch")
        if record["key"] != key:
            raise AssertionError("event key mismatch")
        if (
            record["taskId"], record["operation"],
            record["runId"], record["nonce"],
        ) != values:
            raise AssertionError("event tuple mismatch")
        if record["previousDigest"] != previous_digest:
            raise AssertionError("event previousDigest mismatch")
        previous_digest = "sha256:" + hashlib.sha256(raw).hexdigest()
        records.append(record)
    return records


def _case(name: str, invoke: Callable[[], None]) -> Result:
    try:
        invoke()
    except Exception as exc:
        return Result(name, False, f"{type(exc).__name__}: {exc}")
    return Result(name, True)


def run_cases(binary: Path, base: Path) -> list[Result]:
    values = _tuple()

    def static_elf() -> None:
        _validate_static_elf(binary)

    def accepted_chain() -> None:
        root = _new_root(base, "accepted")
        _run(binary, root, "inspect", *values)
        _run(binary, root, "reserve", *values)
        _run(binary, root, "signing", *values)
        _run(binary, root, "accept", *values, _ACCEPTANCE, _RESPONSE, _TIMESTAMP)
        _run(binary, root, "undelivered", *values)
        output = _run(binary, root, "inspect", *values).stdout
        if "state=accepted" not in output or "undelivered=1" not in output:
            raise AssertionError("accepted snapshot output mismatch")
        records = _assert_event_chain(
            root, values,
            ["active", "signing", "accepted", "accepted-response-undelivered"],
        )
        if records[2]["acceptanceDigest"] != _ACCEPTANCE:
            raise AssertionError("accepted digest not persisted")
        if records[3]["acceptanceDigest"] != records[2]["acceptanceDigest"]:
            raise AssertionError("undelivered audit changed acceptance")

    def replay_rejected() -> None:
        root = _new_root(base, "replay")
        _run(binary, root, "reserve", *values)
        result = _run(binary, root, "reserve", *values, expected=1)
        if "replay rejected" not in result.stderr:
            raise AssertionError("second reservation did not report replay")
        _assert_event_chain(root, values, ["active"])

    def explicit_rejections() -> None:
        root_active = _new_root(base, "reject-active")
        active_values = (values[0], values[1], "run-active", "nonce-active")
        _run(binary, root_active, "reserve", *active_values)
        _run(binary, root_active, "reject", *active_values, "setup-failure", _TIMESTAMP)
        _assert_event_chain(root_active, active_values, ["active", "rejected"])
        root_signing = _new_root(base, "reject-signing")
        signing_values = (values[0], values[1], "run-signing", "nonce-signing")
        _run(binary, root_signing, "reserve", *signing_values)
        _run(binary, root_signing, "signing", *signing_values)
        _run(binary, root_signing, "reject", *signing_values, "head-drift", _TIMESTAMP)
        _assert_event_chain(root_signing, signing_values, ["active", "signing", "rejected"])

    def recovery() -> None:
        root = _new_root(base, "recovery")
        active = (values[0], values[1], "run-stale-active", "nonce-stale-active")
        signing = (values[0], values[1], "run-stale-signing", "nonce-stale-signing")
        _run(binary, root, "reserve", *active)
        _run(binary, root, "reserve", *signing)
        _run(binary, root, "signing", *signing)
        stale = root / ".tmp-stale"
        stale.write_bytes(b"incomplete")
        os.chmod(stale, 0o600)
        result = _run(binary, root, "recover", _TIMESTAMP)
        if result.stdout != "recovered=2\n" or stale.exists():
            raise AssertionError("recovery count/temp cleanup mismatch")
        active_records = _assert_event_chain(root, active, ["active", "rejected"])
        signing_records = _assert_event_chain(
            root, signing, ["active", "signing", "rejected"]
        )
        if active_records[-1]["reason"] != "recovered-stale-active":
            raise AssertionError("active recovery reason mismatch")
        if signing_records[-1]["reason"] != "recovered-stale-signing":
            raise AssertionError("signing recovery reason mismatch")
        if _run(binary, root, "recover", _TIMESTAMP).stdout != "recovered=0\n":
            raise AssertionError("terminal recovery was not idempotent")

    def accepted_survives_recovery() -> None:
        root = _new_root(base, "accepted-recovery")
        local = (values[0], values[1], "run-accepted", "nonce-accepted")
        _run(binary, root, "reserve", *local)
        _run(binary, root, "signing", *local)
        _run(binary, root, "accept", *local, _ACCEPTANCE, _RESPONSE, _TIMESTAMP)
        before = {path.name: path.read_bytes() for path in _event_files(root)}
        if _run(binary, root, "recover", _TIMESTAMP).stdout != "recovered=0\n":
            raise AssertionError("accepted state was recovered as stale")
        after = {path.name: path.read_bytes() for path in _event_files(root)}
        if before != after:
            raise AssertionError("recovery modified accepted state")

    def concurrent_reservation() -> None:
        root = _new_root(base, "concurrent")
        local = (values[0], values[1], "run-concurrent", "nonce-concurrent")
        processes = [
            subprocess.Popen(
                [str(binary), str(root), "reserve", *local],
                cwd=_HERE.parent,
                env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for _ in range(8)
        ]
        results = [process.communicate(timeout=15) + (process.returncode,) for process in processes]
        if [result[2] for result in results].count(0) != 1:
            raise AssertionError(f"concurrent success count != 1: {results}")
        if [result[2] for result in results].count(1) != 7:
            raise AssertionError("concurrent loser count != 7")
        _assert_event_chain(root, local, ["active"])

    def tamper_rejected() -> None:
        root = _new_root(base, "tamper")
        local = (values[0], values[1], "run-tamper", "nonce-tamper")
        _run(binary, root, "reserve", *local)
        event = _event_files(root)[0]
        raw = bytearray(event.read_bytes())
        position = raw.index(b"run-tamper")
        raw[position] = ord("x")
        event.write_bytes(raw)
        os.chmod(event, 0o600)
        result = _run(binary, root, "inspect", *local, expected=1)
        if "mismatch" not in result.stderr and "noncanonical" not in result.stderr:
            raise AssertionError("tampered event failed for an unrelated reason")

    def unsafe_nodes_rejected() -> None:
        mode_root = _new_root(base, "mode-root", 0o755)
        result = _run(binary, mode_root, "inspect", *values, expected=1)
        if "mode-0700" not in result.stderr:
            raise AssertionError("unsafe root mode not rejected")
        hard_root = _new_root(base, "hardlink")
        local = (values[0], values[1], "run-hardlink", "nonce-hardlink")
        _run(binary, hard_root, "reserve", *local)
        os.link(_event_files(hard_root)[0], hard_root / "extra-link")
        result = _run(binary, hard_root, "inspect", *local, expected=1)
        if "metadata rejected" not in result.stderr:
            raise AssertionError("hard-linked event not rejected")
        unknown_root = _new_root(base, "unknown")
        (unknown_root / "unknown").write_bytes(b"x")
        os.chmod(unknown_root / "unknown", 0o600)
        result = _run(binary, unknown_root, "recover", _TIMESTAMP, expected=1)
        if "unknown entry" not in result.stderr:
            raise AssertionError("unknown durable-root entry not rejected")
        symlink_root = _new_root(base, "temp-symlink")
        os.symlink("missing", symlink_root / ".tmp-hostile")
        result = _run(binary, symlink_root, "recover", _TIMESTAMP, expected=1)
        if "temp metadata rejected" not in result.stderr:
            raise AssertionError("stale temp symlink not rejected")

    def malformed_inputs_rejected() -> None:
        root = _new_root(base, "malformed")
        mutations = [
            ("reserve", ("TASK-d1-01", values[1], values[2], values[3])),
            ("reserve", (values[0], "unknown", values[2], values[3])),
            ("reserve", (values[0], values[1], "Run", values[3])),
        ]
        for command, arguments in mutations:
            _run(binary, root, command, *arguments, expected=2)
        _run(binary, root, "reserve", *values)
        _run(binary, root, "signing", *values)
        _run(
            binary, root, "accept", *values,
            "sha256:" + "A" * 64, _RESPONSE, _TIMESTAMP,
            expected=1,
        )
        _run(
            binary, root, "accept", *values,
            _ACCEPTANCE, _RESPONSE, "2026-02-30T12:00:00Z",
            expected=1,
        )
        output = _run(binary, root, "inspect", *values).stdout
        if "state=signing" not in output:
            raise AssertionError("invalid terminal arguments mutated durable state")

    def no_replace_source_contract() -> None:
        source = _SOURCE.read_text(encoding="utf-8")
        required = (
            "O_EXCL", "fsync(descriptor)", "SYS_renameat2",
            "RENAME_NOREPLACE", "fsync(root_fd)", "flock",
        )
        forbidden = ("renameat(", "rename(")
        if any(token not in source for token in required):
            raise AssertionError("atomic transaction primitive missing")
        if any(token in source for token in forbidden):
            raise AssertionError("replace-capable rename fallback present")

    cases: tuple[tuple[str, Callable[[], None]], ...] = (
        ("static-elf", static_elf),
        ("accepted-chain", accepted_chain),
        ("replay-rejected", replay_rejected),
        ("explicit-rejections", explicit_rejections),
        ("crash-recovery", recovery),
        ("accepted-survives-recovery", accepted_survives_recovery),
        ("concurrent-reservation", concurrent_reservation),
        ("tamper-rejected", tamper_rejected),
        ("unsafe-nodes-rejected", unsafe_nodes_rejected),
        ("malformed-inputs-rejected", malformed_inputs_rejected),
        ("no-replace-source-contract", no_replace_source_contract),
    )
    return [_case(name, invoke) for name, invoke in cases]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    scratch_parent = arguments.scratch_root
    if scratch_parent is not None:
        scratch_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-durable-v2-",
        dir=None if scratch_parent is None else str(scratch_parent),
    ) as temporary:
        base = Path(temporary)
        binary = base / "pf-taskqualification-durable-v2"
        try:
            _compile(binary)
            results = run_cases(binary, base)
        except Exception as exc:
            print(f"task-qualification durable-state-v2 self-test: PRECHECK-FAIL: {exc}")
            return 1
    passed = sum(result.passed for result in results)
    print(
        "task-qualification durable-state-v2 self-test: "
        f"{passed}/{len(results)} passed"
    )
    for result in results:
        print(result)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())

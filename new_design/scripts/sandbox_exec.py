#!/usr/bin/env python3
"""Launch one sandbox stage with a closed descriptor table and fixed logs."""

from __future__ import annotations

import argparse
import os
import re
import secrets
import selectors
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import NoReturn, Sequence


STAGES = ("materialize", "core", "evm-runtime")
INVOCATION_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,47}\Z")
MAX_STREAM_BYTES = 4 * 1024 * 1024
MAX_TOTAL_BYTES = 8 * 1024 * 1024
MAX_POLICY_BYTES = 128 * 1024
STAGE_TIMEOUT_SECONDS = {"materialize": 3600, "core": 3600, "evm-runtime": 900}
SYSCTL_RULE = '(allow sysctl-read (sysctl-name "hw.ncpu" "hw.pagesize_compat"))'
ALLOW_DEFAULT_RE = re.compile(r"\(\s*allow\s+default\b")
PROCESS_EXEC_RE = re.compile(r"\(\s*allow\s+process-exec\b")
BARE_PROCESS_EXEC_RE = re.compile(r"\(\s*allow\s+process-exec\s*\)")
PROCESS_WILDCARD_RE = re.compile(r"\bprocess(?:-exec|-info)?\s*\*")
NETWORK_WILDCARD_RE = re.compile(r"\bnetwork\s*\*")


class LaunchError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def fail(code: str, message: str) -> NoReturn:
    raise LaunchError(code, message)


def reject_symlink_components(path: Path, label: str) -> None:
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current /= component
        try:
            metadata = os.lstat(current)
        except OSError as error:
            fail("PF-SANDBOX-LAUNCH-PATH", f"cannot inspect {label}: {error.strerror}")
        if stat.S_ISLNK(metadata.st_mode):
            fail("PF-SANDBOX-LAUNCH-PATH", f"{label} contains a symbolic link")


def canonical_existing(path_text: str, label: str, *, kind: str) -> Path:
    if not path_text or "\x00" in path_text:
        fail("PF-SANDBOX-LAUNCH-PATH", f"{label} is empty or contains NUL")
    path = Path(path_text)
    if not path.is_absolute() or os.path.normpath(path_text) != path_text:
        fail("PF-SANDBOX-LAUNCH-PATH", f"{label} must be absolute and normalized")
    reject_symlink_components(path, label)
    if Path(os.path.realpath(path)) != path:
        fail("PF-SANDBOX-LAUNCH-PATH", f"{label} must already be canonical")
    metadata = os.stat(path, follow_symlinks=False)
    if kind == "dir" and not stat.S_ISDIR(metadata.st_mode):
        fail("PF-SANDBOX-LAUNCH-PATH", f"{label} must be a directory")
    if kind == "file" and not stat.S_ISREG(metadata.st_mode):
        fail("PF-SANDBOX-LAUNCH-PATH", f"{label} must be a regular file")
    return path


def require_direct_xcode_python() -> None:
    if not sys.flags.isolated or not sys.flags.no_site:
        fail("PF-SANDBOX-LAUNCH-PYTHON", "launcher requires direct Xcode Python -I -S")
    executable = canonical_existing(sys.executable, "Python executable", kind="file")
    app_roots = [parent for parent in executable.parents if parent.name.endswith(".app")]
    if len(app_roots) != 1 or any(parent.name == "Python.app" for parent in executable.parents):
        fail("PF-SANDBOX-LAUNCH-PYTHON", "launcher requires the direct Xcode Python")
    developer = app_roots[0] / "Contents" / "Developer"
    version = f"{sys.version_info.major}.{sys.version_info.minor}"
    expected = (
        developer
        / "Library"
        / "Frameworks"
        / "Python3.framework"
        / "Versions"
        / version
        / "bin"
        / f"python{version}"
    )
    if executable != expected or not os.access(executable, os.X_OK):
        fail("PF-SANDBOX-LAUNCH-PYTHON", "unexpected Xcode Python executable path")


def require_private_directory(path: Path, label: str) -> None:
    metadata = os.stat(path, follow_symlinks=False)
    if metadata.st_uid != os.geteuid() or stat.S_IMODE(metadata.st_mode) != 0o700:
        fail("PF-SANDBOX-LAUNCH-LAYOUT", f"{label} must be current-user 0700")


def validate_layout(stage: str, temp_text: str) -> tuple[Path, Path, Path, bytes]:
    temp_root = canonical_existing(temp_text, "TEMP_ROOT", kind="dir")
    require_private_directory(temp_root, "TEMP_ROOT")
    work = canonical_existing(str(temp_root / "work"), "work root", kind="dir")
    policies = canonical_existing(str(temp_root / "policies"), "policies root", kind="dir")
    require_private_directory(work, "work root")
    require_private_directory(policies, "policies root")
    policy = canonical_existing(
        str(policies / f"{stage}.sb"), f"{stage} policy", kind="file"
    )
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(policy, flags)
    try:
        before = os.fstat(descriptor)
        if (
            before.st_uid != os.geteuid()
            or before.st_nlink != 1
            or stat.S_IMODE(before.st_mode) != 0o400
            or before.st_size > MAX_POLICY_BYTES
        ):
            fail(
                "PF-SANDBOX-LAUNCH-POLICY",
                "policy must be current-user-owned, single-link, 0400, and bounded",
            )
        chunks: list[bytes] = []
        remaining = MAX_POLICY_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, min(remaining, 64 * 1024))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        policy_bytes = b"".join(chunks)
        after = os.fstat(descriptor)
        stable = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
        if len(policy_bytes) != before.st_size or any(
            getattr(before, field) != getattr(after, field) for field in stable
        ):
            fail("PF-SANDBOX-LAUNCH-POLICY", "policy changed while being read")
    finally:
        os.close(descriptor)
    return temp_root, work, policies, policy_bytes


def validate_invocation(value: str) -> str:
    if INVOCATION_RE.fullmatch(value) is None:
        fail("PF-SANDBOX-LAUNCH-ID", "invocation must match [a-z0-9][a-z0-9-]{0,47}")
    return value


def validate_policy_snapshot(policy_bytes: bytes, stage: str, port: int | None) -> None:
    try:
        policy = policy_bytes.decode("utf-8")
    except UnicodeDecodeError:
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy must be UTF-8")
    if "\x00" in policy:
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy contains NUL")
    if policy.count("(version 1)") != 1 or policy.count("(deny default)") != 1:
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy must be version 1 deny-default")
    if (
        ALLOW_DEFAULT_RE.search(policy)
        or len(PROCESS_EXEC_RE.findall(policy)) != 1
        or BARE_PROCESS_EXEC_RE.search(policy)
    ):
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy has unsafe default/process execution")
    if PROCESS_WILDCARD_RE.search(policy) or NETWORK_WILDCARD_RE.search(policy):
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy contains a wildcard operation")
    if policy.count("sysctl-read") != 1 or policy.count(SYSCTL_RULE) != 1:
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy has an unlocked sysctl allowance")
    for forbidden in (
        "mach-lookup",
        "ipc-posix",
        "dynamic-code-generation",
        '(subpath "/")',
        "/dev/fd",
    ):
        if forbidden in policy:
            fail("PF-SANDBOX-LAUNCH-POLICY", f"policy contains forbidden {forbidden}")
    if stage != "evm-runtime":
        if "network-" in policy:
            fail("PF-SANDBOX-LAUNCH-POLICY", f"{stage} must deny all network access")
        return
    if type(port) is not int:
        fail("PF-SANDBOX-LAUNCH-PORT", "evm-runtime requires an exact local port")
    inbound = f'(allow network-inbound (local ip "localhost:{port}"))'
    outbound = f'(allow network-outbound (remote ip "localhost:{port}"))'
    if (
        policy.count(inbound) != 1
        or policy.count(outbound) != 1
        or policy.count("network-") != 2
    ):
        fail("PF-SANDBOX-LAUNCH-PORT", "runtime policy local-port rules mismatch")


def xcode_tool_paths() -> tuple[Path, Path]:
    python = Path(sys.executable)
    app_root = next(parent for parent in python.parents if parent.name.endswith(".app"))
    developer = app_root / "Contents" / "Developer"
    git = canonical_existing(str(developer / "usr" / "bin" / "git"), "Xcode Git", kind="file")
    return python, git


def derive_environment(
    stage: str,
    temp_root: Path,
    asset_cache: str | None,
    runtime_port: int | None,
) -> dict[str, str]:
    common = {
        "HOME": str(temp_root / "home"),
        "LC_ALL": "C",
        "PYTHONDONTWRITEBYTECODE": "1",
        "TMPDIR": str(temp_root / "work"),
        "TZ": "UTC",
    }
    xcode_python, xcode_git = xcode_tool_paths()
    if stage == "materialize":
        if asset_cache is None:
            fail("PF-SANDBOX-LAUNCH-ENV", "materialize requires --asset-cache")
        cache = canonical_existing(asset_cache, "ASSET_CACHE", kind="dir")
        if cache == temp_root or cache in temp_root.parents or temp_root in cache.parents:
            fail("PF-SANDBOX-LAUNCH-ENV", "ASSET_CACHE must be disjoint from TEMP_ROOT")
        cache_metadata = os.stat(cache, follow_symlinks=False)
        if cache_metadata.st_uid != os.geteuid() or stat.S_IMODE(cache_metadata.st_mode) & 0o022:
            fail("PF-SANDBOX-LAUNCH-ENV", "ASSET_CACHE must be owned and not writable by peers")
        cache_index = canonical_existing(
            str(cache / "sha256"), "ASSET_CACHE/sha256", kind="dir"
        )
        index_metadata = os.stat(cache_index, follow_symlinks=False)
        if index_metadata.st_uid != os.geteuid() or stat.S_IMODE(index_metadata.st_mode) & 0o022:
            fail(
                "PF-SANDBOX-LAUNCH-ENV",
                "ASSET_CACHE/sha256 must be owned and not writable by peers",
            )
        return common | {
            "PATH": "/usr/bin:/bin",
            "PF_XCODE_PYTHON": str(xcode_python),
            "PROOF_FORGE_ASSET_CACHE": str(cache),
        }
    if asset_cache is not None:
        fail("PF-SANDBOX-LAUNCH-ENV", f"{stage} forbids --asset-cache")
    build = common | {
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "LAKE_CACHE_DIR": str(temp_root / "cache" / "lake-packages"),
        "LAKE_HOME": str(temp_root / "cache" / "lake"),
        "LAKE_NO_CACHE": "1",
        "PATH": f"{temp_root / 'tools' / 'lean' / 'bin'}:{temp_root / 'tools' / 'external'}",
        "PF_CLEAN_OUTPUT": str(temp_root / "output"),
        "PF_CLEAN_SOURCE": str(temp_root / "source"),
        "PF_CLEAN_WORK": str(temp_root / "work"),
        "PF_LEAN_ROOT": str(temp_root / "tools" / "lean"),
        "PF_XCODE_GIT": str(xcode_git),
        "PF_XCODE_PYTHON": str(xcode_python),
        "PROOF_FORGE_TOOL_ROOT": str(temp_root / "tools" / "external"),
        "SOURCE_DATE_EPOCH": "0",
        "XDG_CACHE_HOME": str(temp_root / "cache" / "xdg"),
    }
    if stage == "evm-runtime":
        if runtime_port is None:
            fail("PF-SANDBOX-LAUNCH-PORT", "evm-runtime requires --runtime-port")
        return common | {
            "PATH": str(temp_root / "tools" / "external"),
            "PF_CLEAN_OUTPUT": str(temp_root / "output"),
            "PF_CLEAN_WORK": str(temp_root / "work"),
            "PF_EVM_PORT": str(runtime_port),
            "PF_XCODE_PYTHON": str(xcode_python),
            "PROOF_FORGE_TOOL_ROOT": str(temp_root / "tools" / "external"),
            "XDG_CACHE_HOME": str(temp_root / "cache" / "xdg"),
        }
    return build


def validate_runtime_port(
    stage: str, runtime_port: int | None, environment: dict[str, str], policy_bytes: bytes
) -> None:
    if stage != "evm-runtime":
        if runtime_port is not None:
            fail("PF-SANDBOX-LAUNCH-PORT", f"{stage} forbids --runtime-port")
        return
    if type(runtime_port) is not int or not 1 <= runtime_port <= 65535:
        fail("PF-SANDBOX-LAUNCH-PORT", "evm-runtime requires --runtime-port in [1,65535]")
    if environment.get("PF_EVM_PORT") != str(runtime_port):
        fail("PF-SANDBOX-LAUNCH-PORT", "PF_EVM_PORT must equal --runtime-port")
    try:
        text = policy_bytes.decode("utf-8")
    except UnicodeDecodeError:
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy must be UTF-8")
    inbound = f'(allow network-inbound (local ip "localhost:{runtime_port}"))'
    outbound = f'(allow network-outbound (remote ip "localhost:{runtime_port}"))'
    if text.count(inbound) != 1 or text.count(outbound) != 1:
        fail("PF-SANDBOX-LAUNCH-PORT", "policy does not bind both local-port rules")


def validate_command(command: Sequence[str]) -> list[str]:
    result = list(command)
    if result and result[0] == "--":
        result = result[1:]
    if not result:
        fail("PF-SANDBOX-LAUNCH-COMMAND", "sandbox command must be non-empty")
    executable = canonical_existing(result[0], "command executable", kind="file")
    metadata = os.stat(executable, follow_symlinks=False)
    if metadata.st_nlink != 1 or not os.access(executable, os.X_OK):
        fail("PF-SANDBOX-LAUNCH-COMMAND", "command executable must be single-link executable")
    result[0] = str(executable)
    return result


def same_inode(left: os.stat_result, right: os.stat_result) -> bool:
    return left.st_dev == right.st_dev and left.st_ino == right.st_ino


def atomic_receipt(directory_fd: int, name: str, data: bytes) -> None:
    temporary = f".{name}.tmp-{os.getpid()}-{secrets.token_hex(8)}"
    flags = (
        os.O_RDWR
        | os.O_CREAT
        | os.O_EXCL
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    descriptor: int | None = None
    temporary_present = False
    linked = False
    completed = False
    try:
        descriptor = os.open(temporary, flags, 0o600, dir_fd=directory_fd)
        temporary_present = True
        offset = 0
        while offset < len(data):
            written = os.write(descriptor, data[offset:])
            if written <= 0:
                fail("PF-SANDBOX-LAUNCH-LOG", "short receipt write")
            offset += written
        os.fsync(descriptor)
        os.fchmod(descriptor, 0o400)
        os.fsync(descriptor)
        staged = os.fstat(descriptor)
        if staged.st_size != len(data) or staged.st_nlink != 1:
            fail("PF-SANDBOX-LAUNCH-LOG", "receipt staging invariant failed")
        try:
            os.link(
                temporary,
                name,
                src_dir_fd=directory_fd,
                dst_dir_fd=directory_fd,
                follow_symlinks=False,
            )
            linked = True
        except FileExistsError:
            fail("PF-SANDBOX-LAUNCH-LOG", f"receipt already exists: {name}")
        published = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if not same_inode(staged, published) or published.st_nlink != 2:
            fail("PF-SANDBOX-LAUNCH-LOG", "receipt pathname changed during publication")
        os.fsync(directory_fd)
        os.unlink(temporary, dir_fd=directory_fd)
        temporary_present = False
        os.fsync(directory_fd)
        final = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if (
            not same_inode(staged, final)
            or final.st_nlink != 1
            or final.st_uid != os.geteuid()
            or stat.S_IMODE(final.st_mode) != 0o400
        ):
            fail("PF-SANDBOX-LAUNCH-LOG", "final receipt invariant failed")
        completed = True
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if temporary_present:
            try:
                os.unlink(temporary, dir_fd=directory_fd)
            except FileNotFoundError:
                pass
        if linked and not completed:
            try:
                os.unlink(name, dir_fd=directory_fd)
            except FileNotFoundError:
                pass


def kill_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    process.wait()


def collect_bounded_output(
    process: subprocess.Popen[bytes], timeout_seconds: int
) -> tuple[int, bytes, bytes]:
    if process.stdout is None or process.stderr is None:
        fail("PF-SANDBOX-LAUNCH", "launcher pipes are missing")
    output = {"stdout": bytearray(), "stderr": bytearray()}
    selector = selectors.DefaultSelector()
    streams = {
        process.stdout.fileno(): ("stdout", process.stdout),
        process.stderr.fileno(): ("stderr", process.stderr),
    }
    for descriptor, (name, stream) in streams.items():
        os.set_blocking(descriptor, False)
        selector.register(descriptor, selectors.EVENT_READ, (name, stream))
    deadline = time.monotonic() + timeout_seconds
    try:
        while selector.get_map():
            if time.monotonic() >= deadline:
                kill_process_group(process)
                fail("PF-SANDBOX-LAUNCH-TIMEOUT", "sandbox stage exceeded fixed timeout")
            for key, _ in selector.select(timeout=0.25):
                name, stream = key.data
                try:
                    chunk = os.read(key.fd, 64 * 1024)
                except BlockingIOError:
                    continue
                if not chunk:
                    selector.unregister(key.fd)
                    stream.close()
                    continue
                output[name].extend(chunk)
                if (
                    len(output[name]) > MAX_STREAM_BYTES
                    or len(output["stdout"]) + len(output["stderr"]) > MAX_TOTAL_BYTES
                ):
                    kill_process_group(process)
                    fail("PF-SANDBOX-LAUNCH-OUTPUT", "sandbox output exceeded byte cap")
        return_code = process.wait()
    finally:
        selector.close()
        for _, stream in streams.values():
            if not stream.closed:
                stream.close()
    return return_code, bytes(output["stdout"]), bytes(output["stderr"])


def launch(
    stage: str,
    invocation: str,
    temp_root: Path,
    policies: Path,
    policy_bytes: bytes,
    environment: dict[str, str],
    command: Sequence[str],
) -> int:
    validate_invocation(invocation)
    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    policies_fd = os.open(policies, directory_flags)
    stdout_name = f"sandbox-{stage}-{invocation}.stdout.log"
    stderr_name = f"sandbox-{stage}-{invocation}.stderr.log"
    process: subprocess.Popen[bytes] | None = None
    try:
        for name in (stdout_name, stderr_name):
            try:
                os.stat(name, dir_fd=policies_fd, follow_symlinks=False)
            except FileNotFoundError:
                continue
            fail("PF-SANDBOX-LAUNCH-LOG", f"receipt already exists: {name}")
        try:
            policy_text = policy_bytes.decode("utf-8")
        except UnicodeDecodeError:
            fail("PF-SANDBOX-LAUNCH-POLICY", "policy must be UTF-8")
        if "\x00" in policy_text:
            fail("PF-SANDBOX-LAUNCH-POLICY", "policy contains NUL")
        process = subprocess.Popen(
            ["/usr/bin/sandbox-exec", "-p", policy_text, *command],
            shell=False,
            cwd=str(temp_root),
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            close_fds=True,
            start_new_session=True,
        )
        return_code, stdout_data, stderr_data = collect_bounded_output(
            process, STAGE_TIMEOUT_SECONDS[stage]
        )
        published: list[str] = []
        try:
            atomic_receipt(policies_fd, stdout_name, stdout_data)
            published.append(stdout_name)
            atomic_receipt(policies_fd, stderr_name, stderr_data)
            published.append(stderr_name)
        except BaseException:
            for name in published:
                try:
                    os.unlink(name, dir_fd=policies_fd)
                except FileNotFoundError:
                    pass
            os.fsync(policies_fd)
            raise
        return return_code if return_code >= 0 else 128 - return_code
    finally:
        if process is not None and process.poll() is None:
            kill_process_group(process)
        os.close(policies_fd)


def expect_error(code: str, operation) -> None:  # type: ignore[no-untyped-def]
    try:
        operation()
    except LaunchError as error:
        if error.code != code:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", f"expected {code}, got {error.code}")
        return
    fail("PF-SANDBOX-LAUNCH-SELFTEST", f"expected rejection {code}")


def self_test() -> None:
    global MAX_STREAM_BYTES
    with tempfile.TemporaryDirectory(prefix="proof-forge-sandbox-launch-") as raw:
        outer = Path(raw).resolve(strict=True)
        temp_root = outer / "private"
        asset_cache = outer / "assets"
        work = temp_root / "work"
        policies = temp_root / "policies"
        source = temp_root / "source"
        for directory in (
            temp_root,
            work,
            policies,
            source,
            temp_root / "home",
            temp_root / "cache",
            temp_root / "output",
            temp_root / "tools",
            temp_root / "tools" / "lean",
            temp_root / "tools" / "external",
            asset_cache,
            asset_cache / "sha256",
        ):
            directory.mkdir(parents=True, exist_ok=True)
        for directory in (
            temp_root,
            work,
            policies,
            temp_root / "home",
            temp_root / "cache",
            temp_root / "output",
            temp_root / "tools",
        ):
            os.chmod(directory, 0o700)
        runner = temp_root / "clean-room-runner.sh"
        runner.write_bytes(b"#!/bin/bash\n")
        os.chmod(runner, 0o500)
        policy = policies / "core.sb"
        renderer = Path(__file__).with_name("sandbox_policy.py")
        subprocess.run(
            [
                sys.executable,
                "-I",
                "-S",
                str(renderer),
                "render",
                "core",
                "--temp-root",
                str(temp_root),
                "--asset-cache",
                str(asset_cache),
                "--xcode-python",
                sys.executable,
                "--lean-root",
                str(temp_root / "tools" / "lean"),
                "--external-root",
                str(temp_root / "tools" / "external"),
                "--source-root",
                str(source),
                "-o",
                str(policy),
            ],
            check=True,
            close_fds=True,
        )
        environment = derive_environment("core", temp_root, None, None)
        _, _, validated_policies, policy_bytes = validate_layout("core", str(temp_root))
        validate_policy_snapshot(policy_bytes, "core", None)
        expect_error(
            "PF-SANDBOX-LAUNCH-POLICY",
            lambda: validate_policy_snapshot(b"(version 1)\n(allow default)\n", "core", None),
        )
        secret = source / "body"
        secret.write_bytes(b"candidate-body")
        descriptor = os.open(secret, os.O_WRONLY)
        try:
            os.dup2(descriptor, 9, inheritable=True)
            code = (
                "import errno,os,sys; "
                "assert os.read(0,1)==b''; "
                "\ntry: os.write(9,b'changed')\n"
                "except OSError as e: assert e.errno==errno.EBADF\n"
                "else: raise AssertionError('fd9 inherited')\n"
                "print('stdout-ok'); print('stderr-ok',file=sys.stderr)"
            )
            result = launch(
                "core",
                "fd-close",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", code],
            )
        finally:
            os.close(9)
            if descriptor != 9:
                os.close(descriptor)
        if result != 0 or secret.read_bytes() != b"candidate-body":
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "inherited fd modified candidate body")
        stdout_receipt = policies / "sandbox-core-fd-close.stdout.log"
        stderr_receipt = policies / "sandbox-core-fd-close.stderr.log"
        if stdout_receipt.read_text() != "stdout-ok\n":
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "stdout log mismatch")
        if stderr_receipt.read_text() != "stderr-ok\n":
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "stderr log mismatch")
        if stat.S_IMODE(stdout_receipt.stat().st_mode) != 0o400:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "receipt mode mismatch")
        original_stream_cap = MAX_STREAM_BYTES
        MAX_STREAM_BYTES = 32
        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-OUTPUT",
                lambda: launch(
                    "core",
                    "output-cap",
                    temp_root,
                    validated_policies,
                    policy_bytes,
                    environment,
                    [sys.executable, "-I", "-S", "-c", "print('x'*1024)"],
                ),
            )
        finally:
            MAX_STREAM_BYTES = original_stream_cap
        if any(policies.glob("sandbox-core-output-cap.*.log")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "output-cap failure published receipts")
        expect_error("PF-SANDBOX-LAUNCH-ID", lambda: validate_invocation("Invalid_ID"))
        expect_error("PF-SANDBOX-LAUNCH-ID", lambda: validate_invocation("x" * 49))
        expect_error(
            "PF-SANDBOX-LAUNCH-LOG",
            lambda: launch(
                "core",
                "fd-close",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "pass"],
            ),
        )
    print("sandbox-exec-launcher: self-test ok")


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(prog="sandbox-exec-launcher", allow_abbrev=False)
    subcommands = command.add_subparsers(dest="action", required=True)
    run = subcommands.add_parser("run", allow_abbrev=False)
    run.add_argument("stage", choices=STAGES)
    run.add_argument("--invocation", required=True)
    run.add_argument("--temp-root", required=True)
    run.add_argument("--asset-cache")
    run.add_argument("--runtime-port", type=int)
    test = subcommands.add_parser("self-test", allow_abbrev=False)
    test.set_defaults(handler=lambda _args: self_test())
    return command


def run_command(args: argparse.Namespace) -> int:
    invocation = validate_invocation(args.invocation)
    temp_root, _, policies, policy_bytes = validate_layout(args.stage, args.temp_root)
    environment = derive_environment(
        args.stage, temp_root, args.asset_cache, args.runtime_port
    )
    validate_policy_snapshot(policy_bytes, args.stage, args.runtime_port)
    validate_runtime_port(args.stage, args.runtime_port, environment, policy_bytes)
    command = validate_command(args.command)
    return launch(
        args.stage,
        invocation,
        temp_root,
        policies,
        policy_bytes,
        environment,
        command,
    )


def main(argv: Sequence[str] | None = None) -> int:
    try:
        require_direct_xcode_python()
        raw = list(sys.argv[1:] if argv is None else argv)
        sandbox_command: list[str] = []
        # Split explicitly so launcher options may follow STAGE; REMAINDER would
        # otherwise swallow them into the sandboxed command.
        if raw and raw[0] == "run" and "--" in raw:
            delimiter = raw.index("--")
            sandbox_command = raw[delimiter + 1 :]
            raw = raw[:delimiter]
        args = parser().parse_args(raw)
        if args.action == "run":
            args.command = sandbox_command
            return run_command(args)
        args.handler(args)
        return 0
    except (LaunchError, OSError, UnicodeError, subprocess.SubprocessError) as error:
        code = error.code if isinstance(error, LaunchError) else "PF-SANDBOX-LAUNCH"
        print(f"sandbox-exec-launcher: {code}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

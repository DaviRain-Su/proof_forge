#!/usr/bin/env python3
"""Deny-default macOS sandbox policy generator for ProofForge V2 clean-room.

Policy is fail-closed: default deny, then explicit allows for system TCB roots
and the exact work trees of one clean-room run. Network is denied unless the
localhost runtime profile is selected.
"""
from __future__ import annotations

import argparse
import os
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

SYSTEM_READ_ROOTS = (
    "/usr",
    "/System",
    "/bin",
    "/sbin",
    "/private/var/db",
    "/private/etc",
    "/private/var/folders",
    "/Library",
    "/Applications",
    "/dev",
)


class PolicyError(RuntimeError):
    pass


def fail(message: str) -> "None":
    raise PolicyError(message)


def require_isolated_python() -> None:
    if not sys.flags.isolated or not sys.flags.no_site:
        fail("run sandbox_policy with /usr/bin/python3 -I -S")


def realpath(path: Path | str) -> Path:
    return Path(os.path.realpath(str(path)))


def escape_sbpl(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def require_absolute_root(path: Path, where: str) -> Path:
    resolved = realpath(path)
    if not resolved.is_absolute():
        fail(f"{where} must be absolute")
    if resolved.is_symlink():
        fail(f"{where} must not be a symlink: {resolved}")
    text = str(resolved)
    if text == "/" or text == "":
        fail(f"{where} must not be the filesystem root")
    return resolved


def subpath_filters(paths: list[Path]) -> str:
    parts: list[str] = []
    seen: set[str] = set()
    for path in paths:
        text = str(path)
        if text in seen:
            continue
        seen.add(text)
        parts.append(f'(subpath "{escape_sbpl(text)}")')
    return "\n  ".join(parts)


def build_deny_default_profile(
    *,
    read_roots: list[Path],
    write_roots: list[Path],
    network: str,
) -> str:
    if network not in ("none", "localhost"):
        fail(f"unsupported network mode: {network}")
    if not read_roots:
        fail("read_roots must be non-empty")
    if not write_roots:
        fail("write_roots must be non-empty")

    system_reads = [Path(root) for root in SYSTEM_READ_ROOTS]
    all_reads = system_reads + [require_absolute_root(p, "read_root") for p in read_roots]
    all_writes = [require_absolute_root(p, "write_root") for p in write_roots]

    profile = f"""(version 1)
(deny default)
(import "system.sb")
(allow process*)
(allow signal)
(allow sysctl*)
(allow mach*)
(allow iokit-open)
(allow file-read-metadata)
(allow file-read*
  {subpath_filters(all_reads)}
)
(allow file-write*
  {subpath_filters(all_writes)}
  (subpath "/dev")
)
(allow file-write-data (literal "/dev/null"))
(allow file-ioctl (literal "/dev/null"))
"""
    if network == "localhost":
        profile += """(allow network-inbound (local ip "localhost:*"))
(allow network-outbound (remote ip "localhost:*"))
"""
    return profile


def materialize_profile(
    *,
    work_root: Path,
    asset_cache: Path | None = None,
) -> str:
    work = require_absolute_root(work_root, "work_root")
    reads = [work]
    writes = [work]
    if asset_cache is not None:
        cache = require_absolute_root(asset_cache, "asset_cache")
        reads.append(cache)
    return build_deny_default_profile(
        read_roots=reads,
        write_roots=writes,
        network="none",
    )


def core_profile(
    *,
    work_root: Path,
    source_root: Path,
    home_root: Path,
    cache_root: Path,
    tool_root: Path,
    output_root: Path,
) -> str:
    roots = [
        require_absolute_root(work_root, "work_root"),
        require_absolute_root(source_root, "source_root"),
        require_absolute_root(home_root, "home_root"),
        require_absolute_root(cache_root, "cache_root"),
        require_absolute_root(tool_root, "tool_root"),
        require_absolute_root(output_root, "output_root"),
    ]
    return build_deny_default_profile(
        read_roots=roots,
        write_roots=roots,
        network="none",
    )


def localhost_profile(
    *,
    work_root: Path,
    source_root: Path,
    home_root: Path,
    cache_root: Path,
    tool_root: Path,
    output_root: Path,
) -> str:
    roots = [
        require_absolute_root(work_root, "work_root"),
        require_absolute_root(source_root, "source_root"),
        require_absolute_root(home_root, "home_root"),
        require_absolute_root(cache_root, "cache_root"),
        require_absolute_root(tool_root, "tool_root"),
        require_absolute_root(output_root, "output_root"),
    ]
    return build_deny_default_profile(
        read_roots=roots,
        write_roots=roots,
        network="localhost",
    )


def _run_sandbox(profile: str, argv: list[str], *, timeout: float = 5.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["/usr/bin/sandbox-exec", "-p", profile, *argv],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def self_test() -> None:
    if not Path("/usr/bin/sandbox-exec").is_file():
        fail("macOS sandbox-exec is unavailable")

    with tempfile.TemporaryDirectory(prefix="pf-sandbox-policy-") as raw:
        root = realpath(raw)
        allowed = root / "allowed"
        denied = root / "denied"
        allowed.mkdir()
        denied.mkdir()
        (allowed / "ok.txt").write_text("ok\n", encoding="ascii")
        (denied / "secret.txt").write_text("secret\n", encoding="ascii")
        home_probe = Path.home() / f".pf-sandbox-policy-probe-{os.getpid()}"
        home_probe.write_text("home-secret\n", encoding="ascii")
        try:
            core = build_deny_default_profile(
                read_roots=[allowed],
                write_roots=[allowed],
                network="none",
            )
            if "(allow default)" in core:
                fail("policy must not contain allow default")
            if "(deny default)" not in core:
                fail("policy must deny by default")
            if "network*" in core and "localhost" not in core:
                fail("core policy must not allow network")

            ok = _run_sandbox(core, ["/bin/cat", str(allowed / "ok.txt")])
            if ok.returncode != 0 or ok.stdout != "ok\n":
                fail(f"allowed read failed: rc={ok.returncode} out={ok.stdout!r} err={ok.stderr!r}")

            secret = _run_sandbox(core, ["/bin/cat", str(denied / "secret.txt")])
            if secret.returncode == 0:
                fail("deny-default unexpectedly allowed sibling path read")

            home = _run_sandbox(core, ["/bin/cat", str(home_probe)])
            if home.returncode == 0:
                fail("deny-default unexpectedly allowed HOME path read")

            brew = _run_sandbox(core, ["/bin/ls", "/opt/homebrew"])
            if brew.returncode == 0:
                fail("deny-default unexpectedly allowed /opt/homebrew")

            net = _run_sandbox(
                core,
                [
                    "/usr/bin/python3",
                    "-I",
                    "-S",
                    "-c",
                    "import socket; socket.create_connection(('127.0.0.1',1),1)",
                ],
            )
            if net.returncode == 0:
                fail("core deny-default unexpectedly allowed network")

            listener = socket.socket()
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            port = listener.getsockname()[1]
            local = build_deny_default_profile(
                read_roots=[allowed],
                write_roots=[allowed],
                network="localhost",
            )
            allowed_local = _run_sandbox(
                local,
                [
                    "/usr/bin/python3",
                    "-I",
                    "-S",
                    "-c",
                    f"import socket; socket.create_connection(('127.0.0.1',{port}),1); print('ok')",
                ],
            )
            conn, _ = listener.accept()
            conn.close()
            listener.close()
            if allowed_local.returncode != 0 or "ok" not in allowed_local.stdout:
                fail(f"localhost profile failed: {allowed_local.stderr!r}")

            remote = _run_sandbox(
                local,
                [
                    "/usr/bin/python3",
                    "-I",
                    "-S",
                    "-c",
                    "import socket; socket.create_connection(('192.0.2.1',9),1)",
                ],
            )
            if remote.returncode == 0:
                fail("localhost profile unexpectedly allowed non-local network")
            err = remote.stderr + remote.stdout
            if "PermissionError" not in err and "Operation not permitted" not in err and "timed out" not in err.lower() and "Errno" not in err:
                fail(f"localhost non-local denial missing sandbox signal: {err!r}")
        finally:
            try:
                home_probe.unlink()
            except FileNotFoundError:
                pass

    print("sandbox-policy: self-test ok (deny-default)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="ProofForge deny-default sandbox policy")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("self-test")
    emit = commands.add_parser("emit")
    emit.add_argument("--mode", choices=("core", "localhost", "materialize"), required=True)
    emit.add_argument("--work-root", type=Path, required=True)
    emit.add_argument("--source-root", type=Path)
    emit.add_argument("--home-root", type=Path)
    emit.add_argument("--cache-root", type=Path)
    emit.add_argument("--tool-root", type=Path)
    emit.add_argument("--output-root", type=Path)
    emit.add_argument("--asset-cache", type=Path)
    return parser


def main() -> None:
    require_isolated_python()
    args = build_parser().parse_args()
    if args.command == "self-test":
        self_test()
        return
    if args.command == "emit":
        if args.mode == "materialize":
            print(materialize_profile(work_root=args.work_root, asset_cache=args.asset_cache), end="")
            return
        required = {
            "source_root": args.source_root,
            "home_root": args.home_root,
            "cache_root": args.cache_root,
            "tool_root": args.tool_root,
            "output_root": args.output_root,
        }
        missing = [name for name, value in required.items() if value is None]
        if missing:
            fail(f"missing roots for {args.mode}: {', '.join(missing)}")
        if args.mode == "core":
            print(
                core_profile(
                    work_root=args.work_root,
                    source_root=args.source_root,
                    home_root=args.home_root,
                    cache_root=args.cache_root,
                    tool_root=args.tool_root,
                    output_root=args.output_root,
                ),
                end="",
            )
            return
        print(
            localhost_profile(
                work_root=args.work_root,
                source_root=args.source_root,
                home_root=args.home_root,
                cache_root=args.cache_root,
                tool_root=args.tool_root,
                output_root=args.output_root,
            ),
            end="",
        )
        return
    fail(f"unsupported command {args.command}")


if __name__ == "__main__":
    try:
        main()
    except (PolicyError, OSError, subprocess.SubprocessError) as error:
        print(f"sandbox-policy: {error}", file=sys.stderr)
        raise SystemExit(1) from error

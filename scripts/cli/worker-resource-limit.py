#!/usr/bin/env python3
"""PF-P3-03: portable worker resource-limit runner.

Enforces wall-clock, CPU, and (when the platform allows) memory limits around a
child command. Intended for hosted-compilation isolation smokes:

* wall-clock: always (process-session timeout)
* CPU: RLIMIT_CPU when available (Linux + macOS)
* memory:
  - Linux cgroup v2 when a writable controller is available
  - else RLIMIT_AS / RLIMIT_DATA when the kernel accepts a lowered limit
  - else report `mem_backend=none` (caller may require cgroup via env)

Exit codes:
  0   child success
  124 wall-clock timeout
  137 memory-kill convention (or child signalled)
  other: child exit code or 1 on setup failure

Usage:
  worker-resource-limit.py --wall-sec 30 --cpu-sec 2 --mem-bytes 67108864 -- cmd...
"""
from __future__ import annotations

import argparse
import os
import resource
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional


def _try_set_rlimit(which: int, soft: int, hard: Optional[int] = None) -> bool:
    if hard is None:
        hard = soft
    try:
        resource.setrlimit(which, (soft, hard))
        return True
    except (ValueError, resource.error, OSError):
        return False


def _apply_cpu_rlimit(cpu_sec: Optional[int]) -> str:
    if cpu_sec is None or cpu_sec <= 0:
        return "none"
    if not hasattr(resource, "RLIMIT_CPU"):
        return "unavailable"
    # Soft+hard so the process cannot raise the limit.
    if _try_set_rlimit(resource.RLIMIT_CPU, cpu_sec, cpu_sec):
        return "rlimit_cpu"
    return "failed"


def _apply_mem_rlimit(mem_bytes: Optional[int]) -> str:
    if mem_bytes is None or mem_bytes <= 0:
        return "none"
    for name in ("RLIMIT_AS", "RLIMIT_DATA"):
        which = getattr(resource, name, None)
        if which is None:
            continue
        if _try_set_rlimit(which, mem_bytes, mem_bytes):
            return name.lower()
    return "failed"


def _cgroup_v2_available() -> bool:
    base = Path("/sys/fs/cgroup")
    if not base.is_dir():
        return False
    # cgroup v2 unified hierarchy exposes cgroup.controllers
    return (base / "cgroup.controllers").is_file()


def _create_cgroup_v2(mem_bytes: Optional[int], cpu_sec: Optional[int]) -> Optional[Path]:
    """Create and configure a leaf cgroup without moving the wrapper into it."""
    if not _cgroup_v2_available():
        return None
    base = Path("/sys/fs/cgroup")
    # Prefer a delegated subtree when present; else try creating under root
    # (requires privilege — failure returns None).
    parent = base
    for candidate in (
        base / "user.slice",
        base / f"user.slice/user-{os.getuid()}.slice",
        base,
    ):
        if candidate.is_dir() and os.access(candidate, os.W_OK):
            parent = candidate
            break
    name = f"proof-forge-worker-{os.getpid()}-{int(time.time())}"
    cg = parent / name
    try:
        cg.mkdir(exist_ok=False)
    except OSError:
        return None
    try:
        if mem_bytes is not None and mem_bytes > 0:
            memory_max = cg / "memory.max"
            if not memory_max.is_file():
                raise OSError("memory controller is not delegated to the leaf cgroup")
            memory_max.write_text(str(mem_bytes), encoding="ascii")
        if cpu_sec is not None and cpu_sec > 0 and (cg / "cpu.max").exists():
            # cpu.max: $MAX $PERIOD (µs). A lifetime `cpu_sec` budget is handled
            # by RLIMIT_CPU; use 10% of one core as an additional cgroup throttle.
            (cg / "cpu.max").write_text("10000 100000", encoding="ascii")
        return cg
    except OSError:
        try:
            cg.rmdir()
        except OSError:
            pass
        return None


def _preexec(
    cpu_sec: Optional[int],
    mem_bytes: Optional[int],
    cgroup_path: Optional[Path],
) -> None:
    if cgroup_path is not None:
        # Move only the child into the leaf. Descendants inherit membership while
        # the wrapper stays outside and can always tear the leaf down.
        (cgroup_path / "cgroup.procs").write_text(str(os.getpid()), encoding="ascii")

    cpu_backend = _apply_cpu_rlimit(cpu_sec)
    if cpu_sec is not None and cpu_sec > 0 and cpu_backend != "rlimit_cpu":
        raise RuntimeError(f"CPU limit setup failed: {cpu_backend}")

    if cgroup_path is None and mem_bytes is not None and mem_bytes > 0:
        mem_backend = _apply_mem_rlimit(mem_bytes)
        if mem_backend not in ("rlimit_as", "rlimit_data"):
            raise RuntimeError(f"memory limit setup failed: {mem_backend}")


def _process_group_exists(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _terminate_process_group(proc: subprocess.Popen[bytes], grace_sec: float = 1.0) -> None:
    """Terminate the command session, escalating to SIGKILL for descendants."""
    pgid = proc.pid
    try:
        os.killpg(pgid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass

    deadline = time.monotonic() + grace_sec
    while time.monotonic() < deadline:
        # poll() reaps the direct child. On macOS an unreaped zombie can keep
        # killpg(pgid, 0) true and make a later SIGKILL fail with EPERM.
        proc.poll()
        if not _process_group_exists(pgid):
            break
        time.sleep(0.02)

    if _process_group_exists(pgid):
        try:
            os.killpg(pgid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass

    if proc.poll() is None:
        try:
            proc.wait(timeout=grace_sec)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def _cleanup_cgroup(cg_path: Path, timeout_sec: float = 2.0) -> bool:
    """Kill any escaped members and remove the leaf cgroup."""
    kill_file = cg_path / "cgroup.kill"
    if kill_file.is_file():
        try:
            kill_file.write_text("1", encoding="ascii")
        except OSError:
            pass

    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        try:
            pids = [int(pid) for pid in (cg_path / "cgroup.procs").read_text().split()]
        except (OSError, ValueError):
            pids = []
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        if not pids:
            try:
                cg_path.rmdir()
                return True
            except FileNotFoundError:
                return True
            except OSError:
                pass
        time.sleep(0.02)

    try:
        cg_path.rmdir()
        return True
    except FileNotFoundError:
        return True
    except OSError as exc:
        print(f"worker-resource-limit: cgroup cleanup failed for {cg_path}: {exc}", file=sys.stderr)
        return False


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="PF-P3-03 worker resource limits")
    parser.add_argument("--wall-sec", type=float, default=None, help="wall-clock timeout seconds")
    parser.add_argument("--cpu-sec", type=int, default=None, help="RLIMIT_CPU seconds")
    parser.add_argument("--mem-bytes", type=int, default=None, help="memory limit in bytes")
    parser.add_argument(
        "--require-mem",
        action="store_true",
        help="fail if no memory backend could be applied",
    )
    parser.add_argument("cmd", nargs=argparse.REMAINDER, help="command after --")
    args = parser.parse_args(argv)

    cmd = args.cmd
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        print("worker-resource-limit: missing command after --", file=sys.stderr)
        return 2

    mem_backend = "none"
    cg_path: Optional[Path] = None
    if args.mem_bytes is not None and args.mem_bytes > 0:
        cg_path = _create_cgroup_v2(args.mem_bytes, args.cpu_sec)
        if cg_path is not None:
            mem_backend = f"cgroup_v2:{cg_path}"
        else:
            # Probe whether rlimit can be applied in a throwaway child.
            probe = subprocess.run(
                [
                    sys.executable,
                    "-c",
                    "import resource,sys;\n"
                    f"b={args.mem_bytes};\n"
                    "ok=False\n"
                    "for n in ('RLIMIT_AS','RLIMIT_DATA'):\n"
                    "  w=getattr(resource,n,None)\n"
                    "  if w is None: continue\n"
                    "  try:\n"
                    "    resource.setrlimit(w,(b,b)); ok=True; print(n); break\n"
                    "  except Exception:\n"
                    "    pass\n"
                    "sys.exit(0 if ok else 1)\n",
                ],
                capture_output=True,
                text=True,
            )
            if probe.returncode == 0 and probe.stdout.strip():
                mem_backend = f"rlimit_probe:{probe.stdout.strip()}"
            else:
                mem_backend = "none"

    if args.require_mem and mem_backend == "none":
        print(
            "worker-resource-limit: memory backend unavailable "
            "(need cgroup v2 write access or working RLIMIT_AS/DATA)",
            file=sys.stderr,
        )
        return 1

    print(
        f"worker-resource-limit: wall={args.wall_sec} cpu_sec={args.cpu_sec} "
        f"mem_bytes={args.mem_bytes} mem_backend={mem_backend}",
        flush=True,
    )

    proc: Optional[subprocess.Popen[bytes]] = None
    cleanup_ok = True
    try:
        proc = subprocess.Popen(
            cmd,
            start_new_session=True,
            preexec_fn=lambda: _preexec(args.cpu_sec, args.mem_bytes, cg_path),
        )
        try:
            code = proc.wait(timeout=args.wall_sec)
        except subprocess.TimeoutExpired:
            print("worker-resource-limit: wall-clock timeout", file=sys.stderr)
            _terminate_process_group(proc)
            code = 124
    except Exception as exc:  # noqa: BLE001 — surface setup/run failures
        print(f"worker-resource-limit: run failed: {exc}", file=sys.stderr)
        code = 1
    finally:
        if proc is not None and (proc.poll() is None or _process_group_exists(proc.pid)):
            _terminate_process_group(proc)
        if cg_path is not None:
            cleanup_ok = _cleanup_cgroup(cg_path)

    if not cleanup_ok:
        return 1

    # Normalize signal deaths used by rlimit/cgroup kills.
    if code is not None and code < 0:
        sig = -code
        if sig in (signal.SIGXCPU, signal.SIGKILL, signal.SIGSEGV):
            # 137 is common OOM-kill convention (128+9).
            if sig == signal.SIGKILL:
                return 137
            return 128 + sig
    return int(code if code is not None else 1)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

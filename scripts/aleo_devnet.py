#!/usr/bin/env python3
"""Ownership-safe Aleo local DevNet lifecycle manager.

Each `start` allocates a fresh ledger directory, binds all REST listeners to
127.0.0.1, starts each validator in its own process group, and records exactly
those PIDs in an atomic active.json file. `stop` verifies each recorded command
before signalling it and never uses global pgrep/kill-by-name discovery.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, NamedTuple, Sequence

ACTIVE_SCHEMA = "proof-forge.aleo-devnet-active.engineering.v1"
SNARKOS_VERSION = "4.9.0"
VALIDATOR_COUNT = 4
DEFAULT_PORT_BASE = 3030
CONSENSUS_VERSION_HEIGHTS = "0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17"


class DevnetError(RuntimeError):
    exit_code = 1


class DevnetUsageError(DevnetError):
    exit_code = 2


class DevnetToolError(DevnetError):
    exit_code = 2


class ActiveDevnet(NamedTuple):
    run_dir: Path
    snarkos: Path
    port_base: int
    pids: tuple[int, ...]


def build_validator_command(
    *,
    snarkos: Path,
    run_dir: Path,
    index: int,
    port: int,
    dev_transactions: bool,
) -> list[str]:
    if index < 0 or index >= VALIDATOR_COUNT:
        raise DevnetUsageError(f"validator index must be in 0..{VALIDATOR_COUNT - 1}")
    command = [
        str(snarkos),
        "start",
        "--nodisplay",
        "--network",
        "1",
        "--dev",
        str(index),
        "--dev-num-validators",
        str(VALIDATOR_COUNT),
        "--rest",
        f"127.0.0.1:{port}",
        "--validator",
    ]
    if not dev_transactions:
        command.append("--no-dev-txs")
    command.extend(
        [
            "--ledger-storage",
            str(run_dir / f"node-{index}"),
            "--node-data-storage",
            str(run_dir / f"node-data-{index}"),
            "--logfile",
            str(run_dir / f"validator-{index}.log"),
            "--verbosity",
            "1",
        ]
    )
    return command


def _value_after(command: Sequence[str], flag: str) -> str | None:
    try:
        index = command.index(flag)
    except ValueError:
        return None
    if index + 1 >= len(command):
        return None
    return command[index + 1]


def command_is_owned(
    command: Sequence[str],
    *,
    snarkos: Path,
    run_dir: Path,
    index: int,
) -> bool:
    if not command:
        return False
    try:
        executable = Path(command[0]).resolve(strict=False)
    except OSError:
        return False
    if executable != snarkos.resolve(strict=False):
        return False
    return (
        len(command) > 1
        and command[1] == "start"
        and _value_after(command, "--dev") == str(index)
        and _value_after(command, "--ledger-storage") == str(run_dir / f"node-{index}")
        and _value_after(command, "--node-data-storage") == str(run_dir / f"node-data-{index}")
    )


def _active_json(active: ActiveDevnet) -> dict[str, Any]:
    return {
        "schema": ACTIVE_SCHEMA,
        "runDir": str(active.run_dir),
        "snarkos": str(active.snarkos),
        "portBase": active.port_base,
        "pids": list(active.pids),
    }


def write_active_atomic(path: Path, active: ActiveDevnet) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    rendered = (json.dumps(_active_json(active), sort_keys=True, indent=2) + "\n").encode("utf-8")
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    tmp = Path(tmp_name)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb", closefd=False) as handle:
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        os.close(fd)
        fd = -1
        os.replace(tmp, path)
    finally:
        if fd >= 0:
            os.close(fd)
        if tmp.exists():
            tmp.unlink()


def read_active(path: Path) -> ActiveDevnet:
    try:
        info = path.lstat()
    except OSError as error:
        raise DevnetError(f"cannot stat active metadata: {error}") from error
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise DevnetError("active metadata must be a regular single-link non-symlink file")
    if info.st_size <= 0 or info.st_size > 64 * 1024:
        raise DevnetError("active metadata size is invalid")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise DevnetError(f"active metadata is invalid: {error}") from error
    if not isinstance(payload, dict) or set(payload) != {
        "schema",
        "runDir",
        "snarkos",
        "portBase",
        "pids",
    }:
        raise DevnetError("active metadata has an invalid field set")
    if payload["schema"] != ACTIVE_SCHEMA:
        raise DevnetError("active metadata schema mismatch")
    if not isinstance(payload["runDir"], str) or not Path(payload["runDir"]).is_absolute():
        raise DevnetError("active runDir must be absolute")
    if not isinstance(payload["snarkos"], str) or not Path(payload["snarkos"]).is_absolute():
        raise DevnetError("active snarkos path must be absolute")
    port_base = payload["portBase"]
    if not isinstance(port_base, int) or isinstance(port_base, bool) or not (1024 <= port_base <= 65532):
        raise DevnetError("active portBase is invalid")
    pids = payload["pids"]
    if (
        not isinstance(pids, list)
        or len(pids) != VALIDATOR_COUNT
        or any(not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1 for pid in pids)
        or len(set(pids)) != VALIDATOR_COUNT
    ):
        raise DevnetError("active PID inventory is invalid")
    return ActiveDevnet(
        run_dir=Path(payload["runDir"]),
        snarkos=Path(payload["snarkos"]),
        port_base=port_base,
        pids=tuple(pids),
    )


def _process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _process_command(pid: int) -> list[str] | None:
    proc_path = Path("/proc") / str(pid) / "cmdline"
    if proc_path.is_file():
        try:
            raw = proc_path.read_bytes()
        except OSError:
            return None
        return [part.decode("utf-8", errors="replace") for part in raw.split(b"\x00") if part]
    try:
        completed = subprocess.run(
            ["/bin/ps", "-p", str(pid), "-o", "command="],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
            env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"},
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if completed.returncode != 0 or not completed.stdout.strip():
        return None
    # Package/tool paths are required to be whitespace-free by this manager.
    return completed.stdout.strip().split()


def _owned_live_pids(active: ActiveDevnet) -> tuple[list[int], list[int]]:
    owned: list[int] = []
    mismatched: list[int] = []
    for index, pid in enumerate(active.pids):
        if not _process_alive(pid):
            continue
        command = _process_command(pid)
        if command is not None and command_is_owned(
            command,
            snarkos=active.snarkos,
            run_dir=active.run_dir,
            index=index,
        ):
            owned.append(pid)
        else:
            mismatched.append(pid)
    return owned, mismatched


def _resolve_snarkos() -> tuple[Path, str]:
    raw = os.environ.get("PROOF_FORGE_ALEO_SNARKOS")
    if not raw:
        raw = str(
            Path.home()
            / ".cache"
            / "proof-forge-v2"
            / "aleo-devnet"
            / "cargo-install"
            / "bin"
            / "snarkos"
        )
    path = Path(raw)
    if not path.is_absolute():
        raise DevnetToolError("PF-TOOLCHAIN-MISSING: snarkos path must be absolute")
    try:
        info = path.lstat()
    except OSError as error:
        raise DevnetToolError(f"PF-TOOLCHAIN-MISSING: snarkos not found: {error}") from error
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise DevnetToolError("PF-TOOLCHAIN-MISSING: snarkos must be a regular non-symlink file")
    # The documented cargo-install binary may be hard-linked to Cargo's build
    # output. DevNet uses only a funded local dev-key, so it does not expose a
    # private-key file to this out-of-Tool-Lock executable.
    if not os.access(path, os.X_OK):
        raise DevnetToolError("PF-TOOLCHAIN-MISSING: snarkos must be executable")
    try:
        completed = subprocess.run(
            [str(path), "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
            env={
                "HOME": str(Path.home()),
                "PATH": "/usr/bin:/bin",
                "LANG": "C",
                "LC_ALL": "C",
            },
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise DevnetToolError(f"PF-TOOLCHAIN-MISSING: snarkos version probe failed: {error}") from error
    text = (completed.stdout or "") + (completed.stderr or "")
    line = text.strip().splitlines()[0] if text.strip() else ""
    if completed.returncode != 0 or re.search(rf"\bsnarkos\s+{SNARKOS_VERSION}\b", text) is None:
        raise DevnetToolError(f"PF-TOOLCHAIN-MISMATCH: expected snarkos {SNARKOS_VERSION}; got '{line}'")
    if "test_network" not in text:
        raise DevnetToolError("PF-TOOLCHAIN-MISMATCH: snarkos must report features=[...,test_network,...]")
    return path.resolve(strict=True), line


def _runtime_env(home: Path) -> dict[str, str]:
    return {
        "HOME": str(home),
        "PATH": "/usr/bin:/bin",
        "LANG": "C",
        "LC_ALL": "C",
        "RUST_BACKTRACE": "0",
        "CONSENSUS_VERSION_HEIGHTS": os.environ.get(
            "PROOF_FORGE_ALEO_CONSENSUS_HEIGHTS", CONSENSUS_VERSION_HEIGHTS
        ),
    }


def _base_dir(root: Path) -> Path:
    raw = os.environ.get("PROOF_FORGE_ALEO_DEVNET_DIR")
    path = Path(raw) if raw else root / "build" / "aleo-devnet"
    return path if path.is_absolute() else (Path.cwd() / path).resolve(strict=False)


def _port_base() -> int:
    raw = os.environ.get("PROOF_FORGE_ALEO_DEVNET_PORT_BASE", str(DEFAULT_PORT_BASE))
    try:
        value = int(raw)
    except ValueError as error:
        raise DevnetUsageError("PROOF_FORGE_ALEO_DEVNET_PORT_BASE must be decimal") from error
    if value < 1024 or value + VALIDATOR_COUNT - 1 > 65535:
        raise DevnetUsageError("DevNet port base must leave four ports in 1024..65535")
    return value


def _active_path(base: Path) -> Path:
    return base / "active.json"


def _read_height(port_base: int) -> str:
    url = f"http://127.0.0.1:{port_base}/testnet/block/height/latest"
    request = urllib.request.Request(url, headers={"User-Agent": "proof-forge-aleo-devnet-v1"})
    with urllib.request.urlopen(request, timeout=2) as response:
        return response.read(128).decode("utf-8").strip()


def _spawned_process_running(process: subprocess.Popen[Any]) -> bool:
    return process.poll() is None


def _signal_spawned_process_group(
    process: subprocess.Popen[Any],
    sig: signal.Signals,
    *,
    getpgid=os.getpgid,
    killpg=os.killpg,
) -> None:
    try:
        pgid = getpgid(process.pid)
        killpg(pgid, sig)
    except (ProcessLookupError, PermissionError):
        pass


def _wait_spawned_processes(
    processes: Sequence[subprocess.Popen[Any]],
    *,
    deadline: float,
    monotonic=time.monotonic,
) -> None:
    for process in processes:
        while _spawned_process_running(process):
            remaining = deadline - monotonic()
            if remaining <= 0:
                break
            try:
                process.wait(timeout=min(0.2, remaining))
            except subprocess.TimeoutExpired:
                pass


def terminate_spawned_devnet_process_groups(
    processes: Sequence[subprocess.Popen[Any]],
    *,
    deadline_seconds: float = 10.0,
    getpgid=os.getpgid,
    killpg=os.killpg,
    monotonic=time.monotonic,
) -> None:
    """Terminate retained startup children by process group and reap them.

    This is intentionally limited to Popen objects created by this start attempt;
    it never discovers processes globally by name or command.
    """

    retained = list(processes)
    for process in retained:
        if _spawned_process_running(process):
            _signal_spawned_process_group(process, signal.SIGTERM, getpgid=getpgid, killpg=killpg)
    deadline = monotonic() + deadline_seconds
    _wait_spawned_processes(retained, deadline=deadline, monotonic=monotonic)
    for process in retained:
        if _spawned_process_running(process):
            _signal_spawned_process_group(process, signal.SIGKILL, getpgid=getpgid, killpg=killpg)
    kill_deadline = monotonic() + deadline_seconds
    _wait_spawned_processes(retained, deadline=kill_deadline, monotonic=monotonic)
    survivors = [process.pid for process in retained if _spawned_process_running(process)]
    if survivors:
        raise DevnetError(f"one or more startup validator processes survived SIGKILL: {survivors}")
    for process in retained:
        try:
            process.wait(timeout=0)
        except subprocess.TimeoutExpired:
            raise DevnetError(f"startup validator process was not reaped: {process.pid}")


def start_devnet(
    root: Path,
    *,
    popen_factory=subprocess.Popen,
    startup_sleep=time.sleep,
    cleanup_process_groups=terminate_spawned_devnet_process_groups,
) -> None:
    base = _base_dir(root)
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    if base.is_symlink() or not base.is_dir():
        raise DevnetError("DevNet base must be a real directory")
    base.chmod(0o700)
    active_path = _active_path(base)
    if active_path.exists() or active_path.is_symlink():
        active = read_active(active_path)
        owned, mismatched = _owned_live_pids(active)
        if owned or mismatched:
            raise DevnetError(
                "DevNet is already active or its PID inventory is ambiguous; run stop/status before start"
            )
        active_path.unlink()
    snarkos, version_line = _resolve_snarkos()
    port_base = _port_base()
    run_dir = Path(tempfile.mkdtemp(prefix="run.", dir=base)).resolve(strict=True)
    run_dir.chmod(0o700)
    isolated_home = run_dir / "home"
    isolated_home.mkdir(mode=0o700)
    dev_transactions = os.environ.get("PROOF_FORGE_ALEO_DEVNET_DEV_TXS", "0") == "1"
    pids: list[int] = []
    processes: list[subprocess.Popen[Any]] = []
    handles = []
    try:
        for index in range(VALIDATOR_COUNT):
            stdout_path = run_dir / f"validator-{index}.stdout.log"
            handle = stdout_path.open("ab", buffering=0)
            handles.append(handle)
            command = build_validator_command(
                snarkos=snarkos,
                run_dir=run_dir,
                index=index,
                port=port_base + index,
                dev_transactions=dev_transactions,
            )
            process = popen_factory(
                command,
                stdin=subprocess.DEVNULL,
                stdout=handle,
                stderr=subprocess.STDOUT,
                env=_runtime_env(isolated_home),
                start_new_session=True,
                close_fds=True,
            )
            processes.append(process)
            pids.append(process.pid)
        active = ActiveDevnet(
            run_dir=run_dir,
            snarkos=snarkos,
            port_base=port_base,
            pids=tuple(pids),
        )
        write_active_atomic(active_path, active)
        startup_sleep(1)
        exited = [process.pid for process in processes if process.poll() is not None]
        if exited:
            raise DevnetError(f"validator process exited during startup: {exited}")
        print(f"aleo-devnet: started snarkos={version_line}")
        print(f"aleo-devnet: run_dir={run_dir}")
        print(f"aleo-devnet: endpoint=http://127.0.0.1:{port_base}")
        print(f"aleo-devnet: pids={','.join(str(pid) for pid in pids)}")
    except BaseException:
        try:
            cleanup_process_groups(processes)
        finally:
            if active_path.exists():
                active_path.unlink()
        raise
    finally:
        for handle in handles:
            handle.close()


def stop_devnet(root: Path) -> None:
    base = _base_dir(root)
    active_path = _active_path(base)
    if not active_path.exists() and not active_path.is_symlink():
        print("aleo-devnet: stopped (no active owned DevNet)")
        return
    active = read_active(active_path)
    owned, mismatched = _owned_live_pids(active)
    if mismatched:
        raise DevnetError(
            f"refusing to signal PID(s) whose commands do not match active metadata: {mismatched}"
        )
    for pid in owned:
        try:
            if os.getpgid(pid) == pid:
                os.killpg(pid, signal.SIGTERM)
            else:
                os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and any(_process_alive(pid) for pid in owned):
        time.sleep(0.2)
    for pid in owned:
        if _process_alive(pid):
            try:
                if os.getpgid(pid) == pid:
                    os.killpg(pid, signal.SIGKILL)
                else:
                    os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    if any(_process_alive(pid) for pid in owned):
        raise DevnetError("one or more owned validator processes survived SIGKILL")
    active_path.unlink()
    print(f"aleo-devnet: stopped owned_pids={','.join(str(pid) for pid in owned) or 'none'}")
    print(f"aleo-devnet: retained logs/ledger at {active.run_dir}")


def status_devnet(root: Path) -> int:
    base = _base_dir(root)
    active_path = _active_path(base)
    if not active_path.exists() and not active_path.is_symlink():
        print("aleo-devnet: DOWN (no active metadata)")
        return 1
    active = read_active(active_path)
    owned, mismatched = _owned_live_pids(active)
    height = "down"
    try:
        height = _read_height(active.port_base)
    except (OSError, urllib.error.URLError, UnicodeError):
        pass
    print(
        f"aleo-devnet: owned={len(owned)}/{VALIDATOR_COUNT} mismatched={len(mismatched)} "
        f"rest_height={height} endpoint=http://127.0.0.1:{active.port_base} run_dir={active.run_dir}"
    )
    if len(owned) == VALIDATOR_COUNT and not mismatched and height != "down":
        print("aleo-devnet: UP")
        return 0
    print("aleo-devnet: DOWN")
    return 1


def wait_devnet(root: Path, timeout_seconds: int) -> None:
    base = _base_dir(root)
    active_path = _active_path(base)
    if not active_path.exists():
        raise DevnetError("no active DevNet; run start first")
    active = read_active(active_path)
    deadline = time.monotonic() + timeout_seconds
    last = "down"
    while time.monotonic() < deadline:
        owned, mismatched = _owned_live_pids(active)
        if mismatched:
            raise DevnetError(f"active PID ownership mismatch: {mismatched}")
        if len(owned) != VALIDATOR_COUNT:
            raise DevnetError("one or more owned validators exited before REST became ready")
        try:
            last = _read_height(active.port_base)
            print(f"aleo-devnet: REST ready height={last} endpoint=http://127.0.0.1:{active.port_base}")
            return
        except (OSError, urllib.error.URLError, UnicodeError):
            time.sleep(2)
    raise DevnetError(f"REST did not become ready within {timeout_seconds}s (last={last})")


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Aleo local DevNet lifecycle")
    parser.add_argument("command", choices=("start", "stop", "status", "wait"))
    parser.add_argument("--timeout-seconds", type=int, default=180)
    args = parser.parse_args(argv)
    if args.timeout_seconds < 1 or args.timeout_seconds > 1800:
        raise DevnetUsageError("--timeout-seconds must be in 1..1800")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = _parse_args(sys.argv[1:] if argv is None else argv)
        root = Path(__file__).resolve().parent.parent
        if args.command == "start":
            start_devnet(root)
            return 0
        if args.command == "stop":
            stop_devnet(root)
            return 0
        if args.command == "status":
            return status_devnet(root)
        wait_devnet(root, args.timeout_seconds)
        return 0
    except DevnetError as error:
        print(f"aleo-devnet: {error}", file=sys.stderr)
        return error.exit_code
    except KeyboardInterrupt:
        print("aleo-devnet: interrupted", file=sys.stderr)
        return 130
    except Exception as error:
        print(f"aleo-devnet: PF-INTERNAL: {error}", file=sys.stderr)
        return 70


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Focused no-process tests for the Aleo DevNet lifecycle manager."""

from __future__ import annotations

import importlib.util
import json
import signal
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = ROOT / "scripts" / "aleo_devnet.py"
NETWORK_MODULE_PATH = ROOT / "scripts" / "aleo_network_receipt.py"
INTEGRATION_PATH = ROOT / "scripts" / "aleo_devnet_integration.sh"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeProcess:
    def __init__(self, pid: int, *, exited: bool = False, ignore_term: bool = False):
        self.pid = pid
        self.returncode = 1 if exited else None
        self.ignore_term = ignore_term
        self.signals: list[int] = []
        self.wait_calls = 0

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        self.wait_calls += 1
        if self.returncode is not None:
            return self.returncode
        if signal.SIGKILL in self.signals:
            self.returncode = -int(signal.SIGKILL)
            return self.returncode
        if signal.SIGTERM in self.signals and not self.ignore_term:
            self.returncode = -int(signal.SIGTERM)
            return self.returncode
        raise subprocess.TimeoutExpired(cmd=f"fake-{self.pid}", timeout=timeout)


def advancing_clock(step: float = 0.01):
    now = [0.0]

    def monotonic() -> float:
        now[0] += step
        return now[0]

    return monotonic


def run() -> None:
    m = load_module(MODULE_PATH, "proof_forge_aleo_devnet")
    network = load_module(NETWORK_MODULE_PATH, "proof_forge_aleo_network_receipt")
    assert m.CONSENSUS_VERSION_HEIGHTS == network.DEFAULT_DEVNET_CONSENSUS_HEIGHTS
    with tempfile.TemporaryDirectory(prefix="pf-aleo-devnet-self-test.") as td:
        root = Path(td)
        snarkos = root / "snarkos"
        snarkos.write_bytes(b"fake")
        snarkos.chmod(0o700)
        run_dir = root / "run.one"
        run_dir.mkdir()
        command = m.build_validator_command(
            snarkos=snarkos,
            run_dir=run_dir,
            index=2,
            port=4032,
            dev_transactions=False,
        )
        joined = " ".join(command)
        assert "--rest 127.0.0.1:4032" in joined
        assert "--ledger-storage" in command
        assert str(run_dir / "node-2") in command
        assert "--no-dev-txs" in command
        assert m.command_is_owned(command, snarkos=snarkos, run_dir=run_dir, index=2)
        assert not m.command_is_owned(command, snarkos=snarkos, run_dir=root / "other", index=2)
        assert not m.command_is_owned(command, snarkos=snarkos, run_dir=run_dir, index=1)

        active_path = root / "active.json"
        payload = m.ActiveDevnet(
            run_dir=run_dir.resolve(),
            snarkos=snarkos.resolve(),
            port_base=4030,
            pids=(101, 102, 103, 104),
        )
        m.write_active_atomic(active_path, payload)
        loaded = m.read_active(active_path)
        assert loaded == payload
        raw = json.loads(active_path.read_text())
        assert raw["schema"] == "proof-forge.aleo-devnet-active.engineering.v1"
        assert raw["pids"] == [101, 102, 103, 104]

        term_proc = FakeProcess(201)
        kill_proc = FakeProcess(202, ignore_term=True)
        by_pid = {201: term_proc, 202: kill_proc}
        m.terminate_spawned_devnet_process_groups(
            [term_proc, kill_proc],
            deadline_seconds=1.0,
            getpgid=lambda pid: pid,
            killpg=lambda pgid, sig: by_pid[pgid].signals.append(sig),
            monotonic=advancing_clock(0.01),
        )
        assert term_proc.signals == [signal.SIGTERM]
        assert kill_proc.signals == [signal.SIGTERM, signal.SIGKILL]
        assert term_proc.poll() == -int(signal.SIGTERM)
        assert kill_proc.poll() == -int(signal.SIGKILL)
        assert term_proc.wait_calls > 0 and kill_proc.wait_calls > 0
        assert term_proc.wait(timeout=0) == -int(signal.SIGTERM)
        assert kill_proc.wait(timeout=0) == -int(signal.SIGKILL)

        start_base = root / "devnet-base"
        fake_snarkos = root / "snarkos-owned"
        fake_snarkos.write_bytes(b"fake")
        fake_snarkos.chmod(0o700)
        old_base_dir = m._base_dir
        old_resolve = m._resolve_snarkos
        spawned = [
            FakeProcess(301, exited=True),
            FakeProcess(302),
            FakeProcess(303, ignore_term=True),
            FakeProcess(304),
        ]
        cleaned: list[int] = []

        popen_index = [0]

        def indexed_fake_popen(*args, **kwargs):
            proc = spawned[popen_index[0]]
            popen_index[0] += 1
            return proc

        def fake_cleanup(processes):
            assert (start_base / "active.json").exists()
            cleaned.extend(process.pid for process in processes)
            local_by_pid = {process.pid: process for process in processes}
            m.terminate_spawned_devnet_process_groups(
                processes,
                deadline_seconds=1.0,
                getpgid=lambda pid: pid,
                killpg=lambda pgid, sig: local_by_pid[pgid].signals.append(sig),
                monotonic=advancing_clock(0.01),
            )

        try:
            m._base_dir = lambda _root: start_base
            m._resolve_snarkos = lambda: (fake_snarkos.resolve(), "snarkos 4.9.0 features=[test_network]")
            try:
                m.start_devnet(
                    root,
                    popen_factory=indexed_fake_popen,
                    startup_sleep=lambda _seconds: None,
                    cleanup_process_groups=fake_cleanup,
                )
            except m.DevnetError as error:
                assert "validator process exited during startup" in str(error)
            else:
                raise AssertionError("start_devnet should fail closed on partial startup exit")
        finally:
            m._base_dir = old_base_dir
            m._resolve_snarkos = old_resolve
        assert cleaned == [301, 302, 303, 304]
        assert not (start_base / "active.json").exists()
        assert spawned[1].signals == [signal.SIGTERM]
        assert spawned[2].signals == [signal.SIGTERM, signal.SIGKILL]
        assert spawned[3].signals == [signal.SIGTERM, signal.SIGKILL]
        assert all(process.wait_calls > 0 for process in spawned)

        spawned_keyboard = [FakeProcess(501), FakeProcess(502, ignore_term=True), FakeProcess(503), FakeProcess(504)]
        cleaned_keyboard: list[int] = []
        keyboard_index = [0]

        def keyboard_fake_popen(*args, **kwargs):
            proc = spawned_keyboard[keyboard_index[0]]
            keyboard_index[0] += 1
            return proc

        def fake_cleanup_keyboard(processes):
            assert (start_base / "active.json").exists()
            cleaned_keyboard.extend(process.pid for process in processes)
            local_by_pid = {process.pid: process for process in processes}
            m.terminate_spawned_devnet_process_groups(
                processes,
                deadline_seconds=1.0,
                getpgid=lambda pid: pid,
                killpg=lambda pgid, sig: local_by_pid[pgid].signals.append(sig),
                monotonic=advancing_clock(0.01),
            )

        try:
            m._base_dir = lambda _root: start_base
            m._resolve_snarkos = lambda: (fake_snarkos.resolve(), "snarkos 4.9.0 features=[test_network]")
            try:
                m.start_devnet(
                    root,
                    popen_factory=keyboard_fake_popen,
                    startup_sleep=lambda _seconds: (_ for _ in ()).throw(KeyboardInterrupt()),
                    cleanup_process_groups=fake_cleanup_keyboard,
                )
            except KeyboardInterrupt:
                pass
            else:
                raise AssertionError("start_devnet should propagate KeyboardInterrupt after cleanup")
        finally:
            m._base_dir = old_base_dir
            m._resolve_snarkos = old_resolve
        assert cleaned_keyboard == [501, 502, 503, 504]
        assert spawned_keyboard[0].signals == [signal.SIGTERM]
        assert spawned_keyboard[1].signals == [signal.SIGTERM, signal.SIGKILL]
        assert spawned_keyboard[2].signals == [signal.SIGTERM, signal.SIGKILL]
        assert spawned_keyboard[3].signals == [signal.SIGTERM, signal.SIGKILL]
        assert all(process.wait_calls > 0 for process in spawned_keyboard)
        assert not (start_base / "active.json").exists()

        spawned_before_popen_failure = [FakeProcess(401), FakeProcess(402, ignore_term=True)]
        cleaned_before_metadata: list[int] = []
        popen_failure_index = [0]

        def failing_fake_popen(*args, **kwargs):
            if popen_failure_index[0] >= len(spawned_before_popen_failure):
                raise OSError("synthetic validator spawn failure")
            proc = spawned_before_popen_failure[popen_failure_index[0]]
            popen_failure_index[0] += 1
            return proc

        def fake_cleanup_before_metadata(processes):
            assert not (start_base / "active.json").exists()
            cleaned_before_metadata.extend(process.pid for process in processes)
            local_by_pid = {process.pid: process for process in processes}
            m.terminate_spawned_devnet_process_groups(
                processes,
                deadline_seconds=1.0,
                getpgid=lambda pid: pid,
                killpg=lambda pgid, sig: local_by_pid[pgid].signals.append(sig),
                monotonic=advancing_clock(0.01),
            )

        try:
            m._base_dir = lambda _root: start_base
            m._resolve_snarkos = lambda: (fake_snarkos.resolve(), "snarkos 4.9.0 features=[test_network]")
            try:
                m.start_devnet(
                    root,
                    popen_factory=failing_fake_popen,
                    startup_sleep=lambda _seconds: None,
                    cleanup_process_groups=fake_cleanup_before_metadata,
                )
            except OSError as error:
                assert "synthetic validator spawn failure" in str(error)
            else:
                raise AssertionError("start_devnet should propagate validator spawn failure")
        finally:
            m._base_dir = old_base_dir
            m._resolve_snarkos = old_resolve
        assert cleaned_before_metadata == [401, 402]
        assert spawned_before_popen_failure[0].signals == [signal.SIGTERM]
        assert spawned_before_popen_failure[1].signals == [signal.SIGTERM, signal.SIGKILL]
        assert all(process.wait_calls > 0 for process in spawned_before_popen_failure)
        assert not (start_base / "active.json").exists()

        integration = INTEGRATION_PATH.read_text(encoding="utf-8")
        assert "trap cleanup EXIT" in integration
        assert "trap on_int INT" in integration
        assert "trap on_term TERM" in integration
        assert "exit 130" in integration
        assert "exit 143" in integration
        assert integration.rfind("echo \"integration(aleo-devnet): PASS\"") > integration.rfind("trap on_term TERM")

    print("aleo-devnet-self-test: ok")


if __name__ == "__main__":
    run()

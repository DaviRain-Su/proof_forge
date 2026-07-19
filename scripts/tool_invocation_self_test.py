#!/usr/bin/env python3
"""Tool invocation timeout-discipline acceptance tests (D0-03 deferred P2 leg).

TST-TOOL-001's frozen surface includes "exact tool version/checksum、
missing/shadow、timeout".  This suite pins the timeout discipline of
``toolchain_assets.bounded_host_command`` on this linux host with real
subprocesses: a hanging command is killed at the deadline with the exact
message, its process group has no survivors, an output-cap breach fails
with the exact message, a fast command passes, and non-positive limit
values are rejected.  ``scripts/toolchain_assets.py`` is digest-pinned by
the host bootstrap locks and is loaded unmodified as a module.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import time
from pathlib import Path
from types import ModuleType


MODULE_PATH = Path(__file__).with_name("toolchain_assets.py")
MODULE_NAME = "proof_forge_toolchain_assets_for_invocation_test"
CHECKS = 0


def load_producer() -> ModuleType:
    assert sys.flags.isolated, "tool-invocation self-test requires isolated Python (-I)"
    assert sys.flags.no_site, "tool-invocation self-test requires no-site Python (-S)"
    assert MODULE_PATH.is_file(), "missing scripts/toolchain_assets.py"
    spec = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
    assert spec is not None and spec.loader is not None, "producer import spec unavailable"
    module = importlib.util.module_from_spec(spec)
    sys.modules[MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


def checked(label: str) -> None:
    global CHECKS
    CHECKS += 1
    print(f"ok: {label}")


def rejection_text(module: ModuleType, thunk) -> str:
    try:
        thunk()
    except module.AssetError as error:
        return str(error)
    raise AssertionError("expected an AssetError rejection")


def process_group_survivors(pgid: int) -> list:
    survivors = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat", "rb") as handle:
                fields = handle.read().split()
            if len(fields) > 4 and int(fields[4]) == pgid:
                survivors.append(int(entry))
        except (OSError, ValueError, IndexError):
            continue
    return survivors


def main() -> int:
    module = load_producer()
    assert callable(getattr(module, "bounded_host_command", None)), (
        "bounded_host_command is unavailable"
    )
    checked("module loads unmodified with bounded_host_command")

    # (a) A hanging command is killed at the deadline with the exact message.
    started = time.monotonic()
    text = rejection_text(
        module,
        lambda: module.bounded_host_command(
            ["/usr/bin/sleep", "30"], timeout=1
        ),
    )
    elapsed = time.monotonic() - started
    assert "host command timed out after 1s" in text, text
    assert elapsed < 15, f"timeout kill took too long: {elapsed:.1f}s"
    checked(f"hanging command killed at deadline ({elapsed:.1f}s, exact message)")

    # (b) The killed process group has no survivors.
    with tempfile.TemporaryDirectory(prefix="tool-invocation-") as temporary:
        marker = Path(temporary) / "pgid"
        started = time.monotonic()
        text = rejection_text(
            module,
            lambda: module.bounded_host_command(
                ["/bin/bash", "-c", f"echo $$ > {marker}; exec /usr/bin/sleep 30"],
                timeout=1,
            ),
        )
        assert "host command timed out after 1s" in text, text
        pgid = int(marker.read_text().strip())
        survivors = process_group_survivors(pgid)
        assert not survivors, f"survivors in process group {pgid}: {survivors}"
        checked("killed process group has no survivors")

    # (c) A command exceeding the output cap fails with the exact message.
    text = rejection_text(
        module,
        lambda: module.bounded_host_command(
            ["/usr/bin/python3", "-I", "-S", "-c", "print('x' * 1048576)"],
            max_output=1024,
        ),
    )
    assert "host command output exceeded 1024 bytes" in text, text
    checked("output cap breach fails with the exact message")

    # (d) A fast command passes normally.
    completed = module.bounded_host_command(["/usr/bin/echo", "invocation-ok"], timeout=5)
    assert completed.returncode == 0
    assert completed.stdout == "invocation-ok\n"
    checked("fast command passes normally")

    # (e) Non-integer/zero/negative limits are rejected before any spawn.
    for label, kwargs in (
        ("zero timeout", {"timeout": 0}),
        ("negative timeout", {"timeout": -3}),
        ("non-integer timeout", {"timeout": "1"}),
        ("zero output cap", {"max_output": 0}),
        ("negative output cap", {"max_output": -1}),
    ):
        text = rejection_text(
            module,
            lambda kwargs=kwargs: module.bounded_host_command(
                ["/usr/bin/true"], **kwargs
            ),
        )
        assert "host command limits must be positive integers" in text, (
            f"{label}: {text}"
        )
    checked("non-positive limit values rejected")

    print(f"tool-invocation-self-test: ok ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

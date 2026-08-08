#!/usr/bin/env python3
"""Aleo snarkos runtime honesty helpers (I3 product surface).

snarkos is **not** a Tool Lock asset. Local DevNet (`leo devnet` / aleo_devnet.sh)
requires a cargo-built binary with crate feature `test_network`.

GitHub prebuilt snarkos zips usually lack `test_network` and must never be marked
ok for this product path.

Authority:
  - docs/product/01-toolchain-install-surface.md §10
  - docs/targets/09c-aleo-network.md §7
  - scripts/aleo_devnet.sh (PROOF_FORGE_ALEO_SNARKOS)

Does not search PATH. Does not write Tool Root. Does not set deployable.
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path
from typing import Any

# Pinned cargo install recipe (host-heavy; not ordinary ci; not Tool Lock).
SNARKOS_CRATE_VERSION = "4.9.0"
SNARKOS_FEATURE = "test_network"
ENV_SNARKOS = "PROOF_FORGE_ALEO_SNARKOS"

# Documented install root (matches aleo_devnet.sh default).
_CACHE_REL = Path(".cache") / "proof-forge-v2" / "aleo-devnet" / "cargo-install"


def default_snarkos_install_root() -> Path:
    return Path.home() / _CACHE_REL


def default_snarkos_path() -> Path:
    return default_snarkos_install_root() / "bin" / "snarkos"


def default_snarkos_install_root_display() -> str:
    """Portable display path using ~/ (not expanded home)."""
    return f"~/{_CACHE_REL.as_posix()}"


def default_snarkos_path_display() -> str:
    return f"{default_snarkos_install_root_display()}/bin/snarkos"


def cargo_install_command() -> str:
    """Exact cargo install recipe for test_network snarkos (semi-auto handoff)."""
    root = default_snarkos_install_root_display()
    return (
        f"cargo install snarkos --version {SNARKOS_CRATE_VERSION} "
        f"--features {SNARKOS_FEATURE} --locked --root {root}"
    )


def resolve_snarkos_path() -> Path:
    """Resolve snarkos binary path: PROOF_FORGE_ALEO_SNARKOS or documented default.

    Relative PROOF_FORGE_ALEO_SNARKOS is accepted as-is (caller may still report
    missing); product scripts prefer absolute paths.
    """
    env = os.environ.get(ENV_SNARKOS)
    if env is not None and env != "":
        return Path(env)
    return default_snarkos_path()


_FEATURES_RE = re.compile(r"features=\[([^\]]*)\]")


def parse_version_has_test_network(version_text: str) -> bool:
    """True iff `snarkos --version` reports features=[...,test_network,...]."""
    match = _FEATURES_RE.search(version_text)
    if match is None:
        return False
    features = [part.strip() for part in match.group(1).split(",") if part.strip()]
    return SNARKOS_FEATURE in features


def probe_snarkos_version(path: Path, *, timeout_sec: float = 20.0) -> tuple[str | None, str | None]:
    """Run `path --version`. Returns (stdout_text, error_hint)."""
    try:
        completed = subprocess.run(
            [str(path), "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            env={
                # Minimal env: avoid ambient PATH tool influence; binary is absolute.
                "PATH": "/usr/bin:/bin",
                "HOME": os.environ.get("HOME", "/var/empty"),
                "LANG": "C",
                "LC_ALL": "C",
            },
        )
    except FileNotFoundError:
        return None, "executable not found at resolve path"
    except PermissionError as error:
        return None, f"permission denied: {error}"
    except subprocess.TimeoutExpired:
        return None, f"--version timed out after {timeout_sec}s"
    except OSError as error:
        return None, f"exec failed: {error}"

    text = (completed.stdout or "") + (completed.stderr or "")
    if completed.returncode != 0 and not text.strip():
        return None, f"--version exit {completed.returncode}"
    return text, None


def inspect_snarkos() -> dict[str, Any]:
    """Doctor-facing snarkos record (runtime honesty; not Tool Lock).

    Status:
      - missing: path absent
      - mismatch: present but --version lacks features=[…,test_network,…]
        (typical of prebuilt GitHub zip / wrong build)
      - partial: present but version probe failed (cannot attest feature)
      - ok: present and --version lists test_network
    """
    path = resolve_snarkos_path()
    install_cmd = cargo_install_command()
    record: dict[str, Any] = {
        "name": "snarkos",
        "path": str(path),
        "tier": "runtime",
        "envVar": ENV_SNARKOS,
        "defaultPath": default_snarkos_path_display(),
        "installCommand": install_cmd,
    }

    try:
        st = path.lstat()
    except FileNotFoundError:
        record["status"] = "missing"
        record["hint"] = (
            f"features={SNARKOS_FEATURE} required; not in Tool Lock; "
            f"prebuilt GitHub snarkos usually lacks {SNARKOS_FEATURE}; "
            f"install: {install_cmd}; "
            f"or set {ENV_SNARKOS} (see docs/product/01-toolchain-install-surface.md §10)"
        )
        return record
    except OSError as error:
        record["status"] = "missing"
        record["hint"] = f"stat failed: {error}; install: {install_cmd}"
        return record

    import stat as stat_mod

    if not stat_mod.S_ISREG(st.st_mode):
        record["status"] = "partial"
        record["hint"] = (
            f"path exists but is not a regular file; cannot attest {SNARKOS_FEATURE}; "
            f"install: {install_cmd}"
        )
        return record

    if not os.access(path, os.X_OK):
        record["status"] = "partial"
        record["hint"] = (
            f"not executable; cannot attest {SNARKOS_FEATURE}; install: {install_cmd}"
        )
        return record

    version_text, probe_err = probe_snarkos_version(path)
    if version_text is None:
        record["status"] = "partial"
        record["hint"] = (
            f"present but --version probe failed ({probe_err}); "
            f"cannot attest {SNARKOS_FEATURE}; not in Tool Lock; "
            f"prebuilt GitHub zip is not sufficient for leo devnet"
        )
        return record

    record["versionText"] = version_text.strip().splitlines()[0] if version_text.strip() else ""
    # Extract short version token if present (e.g. "4.9.0").
    ver_m = re.search(r"\bsnarkos\s+(\S+)", version_text)
    if ver_m:
        record["version"] = ver_m.group(1)

    if parse_version_has_test_network(version_text):
        record["status"] = "ok"
        record["hint"] = (
            f"features={SNARKOS_FEATURE} verified via --version; not in Tool Lock; "
            f"default path {default_snarkos_path_display()} / env {ENV_SNARKOS}"
        )
        return record

    # Present binary without test_network — typical prebuilt release.
    record["status"] = "mismatch"
    record["hint"] = (
        f"binary present but --version lacks features=[…,{SNARKOS_FEATURE},…]; "
        f"prebuilt GitHub snarkos usually lacks {SNARKOS_FEATURE} and is not ok for "
        f"leo devnet; rebuild: {install_cmd}"
    )
    return record


def snarkos_install_record(*, dry_run: bool = False) -> dict[str, Any]:
    """Install-facing record: never materializes snarkos into Tool Root.

    Always documents the cargo recipe. If a verified binary already exists at the
    resolved path, status is `present` (idempotent observation only).
    """
    probe = inspect_snarkos()
    status = "present" if probe["status"] == "ok" else "documented"
    if dry_run and status == "present":
        # Plan-only: still honest that install would skip cargo (already present).
        status = "present"
    record: dict[str, Any] = {
        "name": "snarkos",
        "status": status,
        "tier": "runtime",
        "path": probe["path"],
        "envVar": ENV_SNARKOS,
        "defaultPath": default_snarkos_path_display(),
        "installCommand": cargo_install_command(),
        "hint": (
            "not in Tool Lock; host-heavy cargo build (not run by product install); "
            f"requires features={SNARKOS_FEATURE}; "
            f"prebuilt GitHub zip is not sufficient for leo devnet; "
            f"wire {ENV_SNARKOS} or use default path; "
            "see docs/product/01-toolchain-install-surface.md §10"
        ),
    }
    if probe.get("version"):
        record["version"] = probe["version"]
    if probe["status"] == "ok":
        record["probeStatus"] = "ok"
    else:
        record["probeStatus"] = probe["status"]
        # Surface the exact command for operators/agents.
        record["hint"] = (
            f"{record['hint']}; run: {cargo_install_command()}"
        )
    return record

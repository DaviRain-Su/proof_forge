#!/usr/bin/env python3
"""Product doctor surface for ProofForge V2 (proof-forge.doctor.v1).

Inspects PROOF_FORGE_TOOL_ROOT (or the platform default cache path) and reports
Tool Lock member presence for each TargetRegistry implemented target.

Authority:
  - docs/product/01-toolchain-install-surface.md §4.4 / §5
  - toolchains*.lock.json (proof-forge.toolchains.v4)
  - scripts/toolchain_assets.py (platform + lock load only)

Does not search PATH or invent tools outside the lock. Aleo/Psy are explicit
zero-tool targets. Does not set deployable.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DOCTOR_SCHEMA = "proof-forge.doctor.v1"


# Implemented targets (TargetRegistryV1 materializers) → core Tool Lock ids.
# Planning table from docs/product/01-toolchain-install-surface.md §4.4.
CORE_TOOLS_BY_TARGET: dict[str, list[str]] = {
    "evm": ["solc"],
    "solana": ["sbpf"],
    "near": ["wat2wasm"],
    "noir": ["nargo"],
    "aleo": [],
    "psy": [],
    "quint": ["jv"],
    "cosmwasm": ["wat2wasm", "cosmwasm-check"],
    "ton": ["tolk"],
}

# Optional runtime-tier lock members (reported with --with-runtime).
RUNTIME_TOOLS_BY_TARGET: dict[str, list[str]] = {
    "evm": ["anvil", "cast"],
    "near": ["near-sandbox"],
}

# Design-only registry ids (unsupported for install/doctor install-path).
DESIGN_ONLY_TARGETS: tuple[str, ...] = ("soroban", "icp", "openvm")

IMPLEMENTED_TARGETS: tuple[str, ...] = tuple(CORE_TOOLS_BY_TARGET.keys())

TOOL_STATUS = ("ok", "missing", "mismatch", "partial")
TARGET_STATUS = ("ok", "partial", "missing", "mismatch", "unsupported")


def _load_toolchain_assets() -> Any:
    path = ROOT / "scripts" / "toolchain_assets.py"
    spec = importlib.util.spec_from_file_location("toolchain_assets", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load toolchain_assets from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def die(code: str, message: str, exit_code: int = 3) -> "None":
    """Fail closed with stable CODE: message on stderr."""
    print(f"{code}: {message}", file=sys.stderr)
    raise SystemExit(exit_code)


def usage(message: str) -> "None":
    """Usage/config failure: plain stderr + exit 2 (matches product CLI failUsage)."""
    print(message, file=sys.stderr)
    raise SystemExit(2)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def default_tool_root(platform: str) -> Path:
    return Path.home() / ".cache" / "proof-forge-v2" / "tool-root" / platform


def resolve_tool_root(platform: str) -> Path:
    env = os.environ.get("PROOF_FORGE_TOOL_ROOT")
    if env is None or env == "":
        return default_tool_root(platform)
    path = Path(env)
    if not path.is_absolute():
        die(
            "PF-TOOLCHAIN-MISMATCH",
            "PROOF_FORGE_TOOL_ROOT must be an absolute path",
            exit_code=3,
        )
    return path


def load_host_lock_and_tools(ta: Any) -> tuple[str, dict[str, dict], Path]:
    """Return (platform, tools_by_id, lock_path)."""
    try:
        platform = ta.host_platform_id()
    except ta.AssetError as error:
        die("PF-TOOLCHAIN-MISMATCH", str(error), exit_code=1)

    lock_name = ta.PLATFORM_LOCK_FILES.get(platform)
    if lock_name is None:
        die(
            "PF-TOOLCHAIN-MISMATCH",
            f"no Tool Lock for host platform {platform}",
            exit_code=1,
        )
    lock_path = ROOT / lock_name
    if not lock_path.is_file():
        die(
            "PF-TOOLCHAIN-MISSING",
            f"Tool Lock file absent for platform {platform}: {lock_path}",
            exit_code=1,
        )
    lock = ta.load_json(lock_path)
    if lock.get("schema") != ta.TOOL_LOCK_SCHEMA_V4:
        die(
            "PF-TOOLCHAIN-MISMATCH",
            f"unsupported tool lock schema {lock.get('schema')!r}",
            exit_code=1,
        )
    if lock.get("platform") != platform:
        die(
            "PF-TOOLCHAIN-MISMATCH",
            f"tool lock platform {lock.get('platform')} does not match host {platform}",
            exit_code=1,
        )
    tools: dict[str, dict] = {}
    for tool in lock.get("tools", []):
        tool_id = tool.get("id")
        if not isinstance(tool_id, str) or not tool_id:
            die("PF-TOOLCHAIN-MISMATCH", "tool lock entry missing id", exit_code=1)
        if tool_id in tools:
            die(
                "PF-TOOLCHAIN-MISMATCH",
                f"duplicate tool id in lock: {tool_id}",
                exit_code=1,
            )
        tools[tool_id] = tool
    return platform, tools, lock_path


def inspect_lock_tool(tool: dict, tool_root: Path) -> dict[str, Any]:
    """Inspect one Tool Lock member under tool_root (no PATH search)."""
    name = tool["id"]
    executable = tool.get("executable") or name
    path = tool_root / executable
    version = tool.get("version")
    expected = tool.get("executableSha256")
    source_build = tool.get("sourceBuild") is not None

    record: dict[str, Any] = {
        "name": name,
        "path": str(path),
        "version": version,
        "tier": "core",
    }

    try:
        st = path.lstat()
    except FileNotFoundError:
        record["status"] = "missing"
        return record
    except OSError as error:
        record["status"] = "mismatch"
        record["hint"] = f"stat failed: {error}"
        return record

    if not stat_is_reg(st):
        record["status"] = "mismatch"
        record["hint"] = "not a regular file"
        return record

    try:
        actual = sha256_file(path)
    except OSError as error:
        record["status"] = "mismatch"
        record["hint"] = f"read failed: {error}"
        return record

    record["sha"] = actual
    if source_build:
        # cargo-git: no content pin; presence of a regular file is ok for doctor.
        record["status"] = "ok"
        record["hint"] = "sourceBuild: hash not pinned (version probe is product resolve)"
        return record

    if not isinstance(expected, str) or len(expected) != 64:
        record["status"] = "mismatch"
        record["hint"] = "lock missing executableSha256 pin"
        return record

    if actual != expected:
        record["status"] = "mismatch"
        record["expectedSha"] = expected
        return record

    record["status"] = "ok"
    return record


def stat_is_reg(st: os.stat_result) -> bool:
    import stat as stat_mod

    return stat_mod.S_ISREG(st.st_mode)




def aggregate_target_status(tool_records: list[dict[str, Any]]) -> str:
    if not tool_records:
        return "ok"
    statuses = [r["status"] for r in tool_records]
    if all(s == "ok" for s in statuses):
        return "ok"
    if all(s == "missing" for s in statuses):
        return "missing"
    if any(s == "mismatch" for s in statuses) and all(
        s in ("ok", "mismatch") for s in statuses
    ):
        return "mismatch"
    return "partial"


def build_target_report(
    target_id: str,
    tools_by_id: dict[str, dict],
    tool_root: Path,
    *,
    with_runtime: bool,
) -> dict[str, Any]:
    if target_id in DESIGN_ONLY_TARGETS:
        return {
            "id": target_id,
            "status": "unsupported",
            "tools": [],
        }

    if target_id not in CORE_TOOLS_BY_TARGET:
        usage(f"unknown target '{target_id}'")

    tool_records: list[dict[str, Any]] = []
    for tool_id in CORE_TOOLS_BY_TARGET[target_id]:
        tool = tools_by_id.get(tool_id)
        if tool is None:
            tool_records.append(
                {
                    "name": tool_id,
                    "status": "missing",
                    "tier": "core",
                    "hint": f"not present in Tool Lock for this platform",
                }
            )
            continue
        rec = inspect_lock_tool(tool, tool_root)
        rec["tier"] = "core"
        tool_records.append(rec)

    if with_runtime:
        for tool_id in RUNTIME_TOOLS_BY_TARGET.get(target_id, []):
            tool = tools_by_id.get(tool_id)
            if tool is None:
                tool_records.append(
                    {
                        "name": tool_id,
                        "status": "missing",
                        "tier": "runtime",
                        "hint": "not present in Tool Lock for this platform",
                    }
                )
                continue
            rec = inspect_lock_tool(tool, tool_root)
            rec["tier"] = "runtime"
            tool_records.append(rec)


    return {
        "id": target_id,
        "status": aggregate_target_status(tool_records),
        "tools": tool_records,
    }


def render_human(report: dict[str, Any]) -> str:
    lines: list[str] = [
        f"platform={report['platform']}",
        f"tool_root={report['toolRoot']}",
    ]
    for target in report["targets"]:
        lines.append(f"target={target['id']} status={target['status']}")
        for tool in target.get("tools", []):
            name = tool["name"]
            status = tool["status"]
            parts = [f"  {name}: {status}"]
            if tool.get("sha"):
                parts.append(f"sha={tool['sha'][:16]}…")
            if tool.get("version") and status == "ok":
                parts.append(f"version={tool['version']}")
            if tool.get("expectedSha") and status == "mismatch":
                parts.append(f"expected={tool['expectedSha'][:16]}…")
            if tool.get("installCommand") and status in (
                "missing",
                "mismatch",
                "partial",
            ):
                parts.append(f"installCommand={tool['installCommand']}")
            if tool.get("hint"):
                parts.append(f"({tool['hint']})")
            lines.append(" ".join(parts))
    return "\n".join(lines) + "\n"


def compact_json_tool(tool: dict[str, Any]) -> dict[str, Any]:
    """JSON tool object: name/status required; optional hint/version/sha."""
    out: dict[str, Any] = {
        "name": tool["name"],
        "status": tool["status"],
    }
    if tool.get("hint"):
        out["hint"] = tool["hint"]
    if tool.get("version") is not None:
        out["version"] = tool["version"]
    if tool.get("sha"):
        out["sha"] = tool["sha"]
    if tool.get("path"):
        out["path"] = tool["path"]
    if tool.get("tier"):
        out["tier"] = tool["tier"]
    if tool.get("expectedSha"):
        out["expectedSha"] = tool["expectedSha"]
    return out


def render_json(report: dict[str, Any]) -> str:
    payload = {
        "schema": DOCTOR_SCHEMA,
        "platform": report["platform"],
        "toolRoot": report["toolRoot"],
        "targets": [
            {
                "id": t["id"],
                "status": t["status"],
                "tools": [compact_json_tool(tool) for tool in t.get("tools", [])],
            }
            for t in report["targets"]
        ],
    }
    return json.dumps(payload, indent=2, sort_keys=False) + "\n"


def exit_code_for(report: dict[str, Any]) -> int:
    """0 only when every reported non-unsupported target is ok."""
    statuses = [t["status"] for t in report["targets"] if t["status"] != "unsupported"]
    if not statuses:
        return 0
    if all(s == "ok" for s in statuses):
        return 0
    return 3


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="proof_forge_doctor",
        description="ProofForge product doctor (proof-forge.doctor.v1)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit proof-forge.doctor.v1 JSON on stdout",
    )
    parser.add_argument(
        "--target",
        action="append",
        default=[],
        help="limit to one target id (repeatable); design-only → unsupported",
    )
    parser.add_argument(
        "--with-runtime",
        action="store_true",
        help="include runtime-tier Tool Lock members (anvil/cast, near-sandbox)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="also list design-only targets as unsupported",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    ta = _load_toolchain_assets()
    platform, tools_by_id, _lock_path = load_host_lock_and_tools(ta)
    tool_root = resolve_tool_root(platform)

    if not tool_root.exists():
        die(
            "PF-TOOLCHAIN-MISSING",
            f"tool root does not exist: {tool_root}",
            exit_code=3,
        )
    if not tool_root.is_dir():
        die(
            "PF-TOOLCHAIN-MISMATCH",
            f"tool root is not a directory: {tool_root}",
            exit_code=3,
        )

    if args.target:
        selected: list[str] = []
        for raw in args.target:
            tid = raw.strip()
            if not tid:
                usage("--target requires a nonempty target id")
            if tid in selected:
                usage(f"duplicate --target '{tid}'")
            if (
                tid not in CORE_TOOLS_BY_TARGET
                and tid not in DESIGN_ONLY_TARGETS
            ):
                usage(f"unknown target '{tid}'")
            selected.append(tid)
        target_ids = selected
    else:
        target_ids = list(IMPLEMENTED_TARGETS)
        if args.all:
            target_ids = target_ids + list(DESIGN_ONLY_TARGETS)

    targets = [
        build_target_report(
            tid, tools_by_id, tool_root, with_runtime=args.with_runtime
        )
        for tid in target_ids
    ]
    report = {
        "platform": platform,
        "toolRoot": str(tool_root),
        "targets": targets,
    }

    if args.json:
        sys.stdout.write(render_json(report))
    else:
        sys.stdout.write(render_human(report))
    return exit_code_for(report)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(0)

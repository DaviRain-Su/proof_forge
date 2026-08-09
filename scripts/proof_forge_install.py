#!/usr/bin/env python3
"""Product install surface for ProofForge V2 (proof-forge.install.v1).

Non-interactive installer: materializes Tool Lock members for selected
implemented targets into PROOF_FORGE_TOOL_ROOT (or the platform default).

Authority:
  - docs/product/01-toolchain-install-surface.md §4.4 / §6
  - toolchains*.lock.json (proof-forge.toolchains.v4)
  - scripts/toolchain_assets.py (sole provision / materialize engine)

Does not search PATH or invent tools outside the lock. Does not set deployable.
Optional --with-runtime installs only lock-listed runtime tools. Aleo/Psy are
explicit zero-tool targets.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import secrets
import shutil
import stat as stat_mod
import sys
from pathlib import Path
from typing import Any, Iterator


ROOT = Path(__file__).resolve().parents[1]
INSTALL_SCHEMA = "proof-forge.install.v1"


# Implemented targets → core Tool Lock ids (same table as doctor).
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

RUNTIME_TOOLS_BY_TARGET: dict[str, list[str]] = {
    "evm": ["anvil", "cast"],
    "near": ["near-sandbox"],
}

DESIGN_ONLY_TARGETS: tuple[str, ...] = ("soroban", "icp", "openvm")
IMPLEMENTED_TARGETS: tuple[str, ...] = tuple(CORE_TOOLS_BY_TARGET.keys())

# Tool action statuses for install report.
TOOL_ACTION = (
    "skipped",
    "installed",
    "would-install",
    "would-skip",
    "failed",
    "missing-lock",
)


def _load_toolchain_assets() -> Any:
    path = ROOT / "scripts" / "toolchain_assets.py"
    spec = importlib.util.spec_from_file_location("toolchain_assets", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load toolchain_assets from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def die(code: str, message: str, exit_code: int = 3) -> "None":
    print(f"{code}: {message}", file=sys.stderr)
    raise SystemExit(exit_code)


@contextlib.contextmanager
def _quiet_stdout() -> Iterator[None]:
    """Suppress toolchain_assets progress prints so product JSON stays pure."""
    sink = io.StringIO()
    with contextlib.redirect_stdout(sink):
        yield


def usage(message: str) -> "None":
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


def load_host_lock(ta: Any) -> tuple[str, dict, dict, Path]:
    """Return (platform, lock, host_lock, lock_path). Full validate via load_locks."""
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
    host_lock_path = ROOT / "host-profiles.lock.json"
    if not host_lock_path.is_file():
        die(
            "PF-TOOLCHAIN-MISSING",
            f"host profiles lock absent: {host_lock_path}",
            exit_code=1,
        )
    try:
        lock, host_lock = ta.load_locks(lock_path.resolve(), host_lock_path.resolve())
    except ta.AssetError as error:
        die("PF-TOOLCHAIN-MISMATCH", str(error), exit_code=1)
    if lock.get("platform") != platform:
        die(
            "PF-TOOLCHAIN-MISMATCH",
            f"tool lock platform {lock.get('platform')} does not match host {platform}",
            exit_code=1,
        )
    return platform, lock, host_lock, lock_path


def ensure_tool_root(tool_root: Path, *, dry_run: bool) -> Path:
    """Create or validate product tool root (absolute, no symlink, not world-writable)."""
    if not tool_root.is_absolute():
        die(
            "PF-TOOLCHAIN-MISMATCH",
            f"tool root must be absolute: {tool_root}",
            exit_code=3,
        )
    if tool_root.exists() or tool_root.is_symlink():
        try:
            st = tool_root.lstat()
        except OSError as error:
            die("PF-TOOLCHAIN-MISMATCH", f"cannot stat tool root: {error}", exit_code=3)
        if stat_mod.S_ISLNK(st.st_mode):
            die(
                "PF-TOOLCHAIN-MISMATCH",
                f"tool root cannot be a symbolic link: {tool_root}",
                exit_code=3,
            )
        if not stat_mod.S_ISDIR(st.st_mode):
            die(
                "PF-TOOLCHAIN-MISMATCH",
                f"tool root is not a directory: {tool_root}",
                exit_code=3,
            )
        if st.st_uid != os.getuid():
            die(
                "PF-TOOLCHAIN-MISMATCH",
                f"tool root is not owned by the current user: {tool_root}",
                exit_code=3,
            )
        if stat_mod.S_IMODE(st.st_mode) & 0o022:
            die(
                "PF-TOOLCHAIN-MISMATCH",
                f"tool root is group/world writable: {tool_root}",
                exit_code=3,
            )
        return tool_root.resolve(strict=True)

    if dry_run:
        return tool_root
    tool_root.parent.mkdir(parents=True, exist_ok=True)
    tool_root.mkdir(mode=0o755)
    os.chmod(tool_root, 0o755)
    return tool_root.resolve(strict=True)


def tools_by_id(lock: dict) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for tool in lock.get("tools", []):
        tid = tool.get("id")
        if not isinstance(tid, str) or not tid:
            die("PF-TOOLCHAIN-MISMATCH", "tool lock entry missing id", exit_code=1)
        if tid in out:
            die(
                "PF-TOOLCHAIN-MISMATCH",
                f"duplicate tool id in lock: {tid}",
                exit_code=1,
            )
        out[tid] = tool
    return out


def bundle_records_for_asset(lock: dict, asset_id: str) -> list[dict]:
    return [r for r in lock.get("bundleFiles", []) if r.get("assetId") == asset_id]


def member_matches(root: Path, record: dict) -> bool:
    path = root / record["path"]
    try:
        st = path.lstat()
    except FileNotFoundError:
        return False
    except OSError:
        return False
    if not stat_mod.S_ISREG(st.st_mode) or stat_mod.S_ISLNK(st.st_mode):
        return False
    if st.st_size != record["size"]:
        return False
    if stat_mod.S_IMODE(st.st_mode) != int(record["mode"], 8):
        return False
    try:
        actual = sha256_file(path)
    except OSError:
        return False
    return actual == record["sha256"]


def all_members_match(root: Path, records: list[dict]) -> bool:
    if not records:
        return False
    return all(member_matches(root, r) for r in records)


def source_build_present(root: Path, tool: dict) -> bool:
    path = root / tool["executable"]
    try:
        st = path.lstat()
    except FileNotFoundError:
        return False
    except OSError:
        return False
    if not stat_mod.S_ISREG(st.st_mode) or stat_mod.S_ISLNK(st.st_mode):
        return False
    # cargo-git: no content pin; regular executable file is install-ok (matches doctor).
    return bool(st.st_mode & (stat_mod.S_IXUSR | stat_mod.S_IXGRP | stat_mod.S_IXOTH))


def atomic_write_member(
    ta: Any, asset: dict, record: dict, dest: Path
) -> None:
    """Write one bundle member to dest via exclusive temp + replace (no PATH)."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.parent != dest.parent.resolve(strict=False):
        # Keep parents under tool root; mkdir is enough for relative members.
        pass
    token = secrets.token_hex(6)
    partial = dest.parent / f".{dest.name}.partial-{os.getpid()}-{token}"
    try:
        if partial.exists() or partial.is_symlink():
            partial.unlink()
        with ta.member_stream(asset, record.get("member")) as handle:
            # copy_exact opens with "xb" and checks size/hash.
            ta.copy_exact(handle, partial, record["size"], record["sha256"])
        os.chmod(partial, int(record["mode"], 8))
        os.replace(partial, dest)
    finally:
        try:
            partial.unlink()
        except FileNotFoundError:
            pass


def materialize_asset_members(
    ta: Any,
    lock: dict,
    asset: dict,
    records: list[dict],
    tool_root: Path,
    *,
    dry_run: bool,
) -> str:
    """Provision (if needed) and materialize all bundle members for one asset.

    Returns: skipped | installed | would-install | would-skip
    """
    if all_members_match(tool_root, records):
        return "would-skip" if dry_run else "skipped"

    if dry_run:
        return "would-install"

    # Provision into content-addressed cache (network only if cache miss).
    with _quiet_stdout():
        ta.provision_asset(asset)

    for record in records:
        dest = tool_root / record["path"]
        if member_matches(tool_root, record):
            continue
        if dest.exists() or dest.is_symlink():
            # Replace mismatched / unexpected leaf atomically via temp then replace.
            dest.unlink()
        with _quiet_stdout():
            atomic_write_member(ta, asset, record, dest)

    # Subset verifier: exact size/hash/mode for this asset's members only.
    with _quiet_stdout():
        ta.verify_asset_members(lock, tool_root, asset["id"])
    return "installed"


def materialize_source_build(
    ta: Any,
    tool: dict,
    asset: dict,
    tool_root: Path,
    *,
    dry_run: bool,
) -> str:
    if source_build_present(tool_root, tool):
        return "would-skip" if dry_run else "skipped"
    if dry_run:
        return "would-install"

    with _quiet_stdout():
        ta.provision_asset(asset)
    binary = ta.cargo_git_binary_path(asset)
    try:
        st = binary.lstat()
    except FileNotFoundError as error:
        raise ta.AssetError(
            f"cache miss for cargo-git {asset['id']} after provision"
        ) from error
    if not stat_mod.S_ISREG(st.st_mode) or stat_mod.S_ISLNK(st.st_mode):
        raise ta.AssetError(f"cargo-git product for {asset['id']} is not a regular file")

    dest = tool_root / tool["executable"]
    dest.parent.mkdir(parents=True, exist_ok=True)
    token = secrets.token_hex(6)
    partial = dest.parent / f".{dest.name}.partial-{os.getpid()}-{token}"
    try:
        if partial.exists() or partial.is_symlink():
            partial.unlink()
        with binary.open("rb") as handle, partial.open("xb") as out:
            shutil.copyfileobj(handle, out)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(partial, 0o555)
        if dest.exists() or dest.is_symlink():
            dest.unlink()
        os.replace(partial, dest)
    finally:
        try:
            partial.unlink()
        except FileNotFoundError:
            pass
    return "installed"


def collect_tool_ids(
    target_ids: list[str], *, with_runtime: bool
) -> tuple[list[str], list[str]]:
    """Return (ordered unique tool ids, notes)."""
    tools: list[str] = []
    notes: list[str] = []
    seen: set[str] = set()
    for tid in target_ids:
        if tid in DESIGN_ONLY_TARGETS:
            usage(
                f"target '{tid}' is design-only (unsupported); not installable"
            )
        if tid not in CORE_TOOLS_BY_TARGET:
            usage(f"unknown target '{tid}'")
        for tool_id in CORE_TOOLS_BY_TARGET[tid]:
            if tool_id not in seen:
                seen.add(tool_id)
                tools.append(tool_id)
        if with_runtime:
            for tool_id in RUNTIME_TOOLS_BY_TARGET.get(tid, []):
                if tool_id not in seen:
                    seen.add(tool_id)
                    tools.append(tool_id)
    return tools, notes


def install_one_tool(
    ta: Any,
    lock: dict,
    tools_map: dict[str, dict],
    assets: dict[str, dict],
    tool_id: str,
    tool_root: Path,
    *,
    dry_run: bool,
    tier: str,
) -> dict[str, Any]:
    tool = tools_map.get(tool_id)
    if tool is None:
        return {
            "name": tool_id,
            "status": "missing-lock",
            "tier": tier,
            "hint": "not present in Tool Lock for this platform",
        }

    asset_id = tool.get("assetId")
    if not isinstance(asset_id, str) or not asset_id:
        return {
            "name": tool_id,
            "status": "failed",
            "tier": tier,
            "hint": "tool lock entry missing assetId",
        }
    asset = assets.get(asset_id)
    if asset is None:
        return {
            "name": tool_id,
            "status": "failed",
            "tier": tier,
            "assetId": asset_id,
            "hint": f"asset {asset_id} absent from lock",
        }

    record: dict[str, Any] = {
        "name": tool_id,
        "tier": tier,
        "assetId": asset_id,
        "path": str(tool_root / tool["executable"]),
        "version": tool.get("version"),
    }

    try:
        if tool.get("sourceBuild") is not None:
            status = materialize_source_build(
                ta, tool, asset, tool_root, dry_run=dry_run
            )
        else:
            records = bundle_records_for_asset(lock, asset_id)
            if not records:
                record["status"] = "failed"
                record["hint"] = f"asset {asset_id} has no bundleFiles members"
                return record
            status = materialize_asset_members(
                ta, lock, asset, records, tool_root, dry_run=dry_run
            )
        record["status"] = status
        # Post-state hash for pin tools when present.
        exe = tool_root / tool["executable"]
        if not dry_run and exe.is_file():
            try:
                record["sha"] = sha256_file(exe)
            except OSError:
                pass
            expected = tool.get("executableSha256")
            if isinstance(expected, str) and len(expected) == 64:
                if record.get("sha") and record["sha"] != expected:
                    record["status"] = "failed"
                    record["hint"] = "post-install executableSha256 mismatch"
                    record["expectedSha"] = expected
        return record
    except ta.AssetError as error:
        record["status"] = "failed"
        record["hint"] = str(error)
        return record
    except (OSError, RuntimeError) as error:
        record["status"] = "failed"
        record["hint"] = str(error)
        return record


def tool_tier(tool_id: str, target_ids: list[str], with_runtime: bool) -> str:
    for tid in target_ids:
        if tool_id in CORE_TOOLS_BY_TARGET.get(tid, []):
            return "core"
        if with_runtime and tool_id in RUNTIME_TOOLS_BY_TARGET.get(tid, []):
            return "runtime"
    return "core"


def render_human(report: dict[str, Any]) -> str:
    lines = [
        f"platform={report['platform']}",
        f"tool_root={report['toolRoot']}",
        f"dry_run={str(report['dryRun']).lower()}",
        f"targets={','.join(report['targets'])}",
    ]
    for tool in report["tools"]:
        parts = [f"  {tool['name']}: {tool['status']}"]
        if tool.get("assetId"):
            parts.append(f"asset={tool['assetId']}")
        if tool.get("sha"):
            parts.append(f"sha={tool['sha'][:16]}…")
        if tool.get("version") and tool["status"] in (
            "installed",
            "skipped",
            "would-skip",
        ):
            parts.append(f"version={tool['version']}")
        if tool.get("hint"):
            parts.append(f"({tool['hint']})")
        lines.append(" ".join(parts))
    for note in report.get("notes", []):
        lines.append(f"note: {note}")
    return "\n".join(lines) + "\n"


def render_json(report: dict[str, Any]) -> str:
    payload = {
        "schema": INSTALL_SCHEMA,
        "platform": report["platform"],
        "toolRoot": report["toolRoot"],
        "dryRun": report["dryRun"],
        "withRuntime": report["withRuntime"],
        "targets": report["targets"],
        "tools": report["tools"],
        "notes": report.get("notes", []),
    }
    return json.dumps(payload, indent=2, sort_keys=False) + "\n"


def exit_code_for(report: dict[str, Any]) -> int:
    """0 when every tool is skipped/installed/would-*/documented/present; 3 on fail."""
    bad = {"failed", "missing-lock"}
    for tool in report["tools"]:
        if tool["status"] in bad:
            return 3
    return 0


def parse_targets_csv(raw: str) -> list[str]:
    parts = [p.strip() for p in raw.split(",")]
    out: list[str] = []
    for p in parts:
        if not p:
            usage("--targets entries must be nonempty")
        if p in out:
            usage(f"duplicate target '{p}'")
        out.append(p)
    if not out:
        usage("--targets requires at least one target id")
    return out


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="proof_forge_install",
        description="ProofForge product install (proof-forge.install.v1)",
    )
    parser.add_argument(
        "--targets",
        action="append",
        default=[],
        help="comma-separated target ids (repeatable); design-only rejected",
    )
    parser.add_argument(
        "--all-core",
        action="store_true",
        help="install core/compile tools for every implemented target",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="required confirmation for non-dry-run install (non-interactive)",
    )
    parser.add_argument(
        "--with-runtime",
        action="store_true",
        help="also install runtime-tier lock tools (anvil/cast, near-sandbox)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="plan only: report would-install/would-skip without writing or network",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit proof-forge.install.v1 JSON on stdout",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.all_core and args.targets:
        usage("--all-core and --targets are mutually exclusive")
    if not args.all_core and not args.targets:
        usage("install requires --targets <id,id> or --all-core")
    if not args.dry_run and not args.yes:
        usage("install requires --yes (non-interactive); use --dry-run to plan only")

    ta = _load_toolchain_assets()
    platform, lock, _host_lock, _lock_path = load_host_lock(ta)
    tool_root = resolve_tool_root(platform)
    assets = {a["id"]: a for a in lock.get("assets", [])}
    tmap = tools_by_id(lock)

    if args.all_core:
        target_ids = list(IMPLEMENTED_TARGETS)
    else:
        target_ids = []
        for raw in args.targets:
            for tid in parse_targets_csv(raw):
                if tid in target_ids:
                    usage(f"duplicate target '{tid}'")
                target_ids.append(tid)

    tool_ids, notes = collect_tool_ids(target_ids, with_runtime=args.with_runtime)

    # Dry-run may report against a non-existent root without creating it.
    if not args.dry_run:
        tool_root = ensure_tool_root(tool_root, dry_run=False)
    elif tool_root.exists():
        tool_root = ensure_tool_root(tool_root, dry_run=True)

    # Group by asset so multi-tool assets (foundry → anvil+cast) materialize once.
    tool_records: list[dict[str, Any]] = []
    processed_assets: dict[str, str] = {}  # assetId → status for bundle assets

    for tool_id in tool_ids:
        tier = tool_tier(tool_id, target_ids, args.with_runtime)
        tool = tmap.get(tool_id)
        if tool is not None and tool.get("sourceBuild") is None:
            asset_id = tool.get("assetId")
            if isinstance(asset_id, str) and asset_id in processed_assets:
                # Sibling tool of an already-handled asset: mirror status.
                status = processed_assets[asset_id]
                rec: dict[str, Any] = {
                    "name": tool_id,
                    "status": status,
                    "tier": tier,
                    "assetId": asset_id,
                    "path": str(tool_root / tool["executable"]),
                    "version": tool.get("version"),
                }
                exe = tool_root / tool["executable"]
                if not args.dry_run and exe.is_file():
                    try:
                        rec["sha"] = sha256_file(exe)
                    except OSError:
                        pass
                tool_records.append(rec)
                continue

        rec = install_one_tool(
            ta,
            lock,
            tmap,
            assets,
            tool_id,
            tool_root,
            dry_run=args.dry_run,
            tier=tier,
        )
        tool_records.append(rec)
        if (
            tool is not None
            and tool.get("sourceBuild") is None
            and isinstance(tool.get("assetId"), str)
            and rec["status"]
            in ("skipped", "installed", "would-install", "would-skip")
        ):
            processed_assets[tool["assetId"]] = rec["status"]


    report = {
        "platform": platform,
        "toolRoot": str(tool_root),
        "dryRun": bool(args.dry_run),
        "withRuntime": bool(args.with_runtime),
        "targets": target_ids,
        "tools": tool_records,
        "notes": notes,
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

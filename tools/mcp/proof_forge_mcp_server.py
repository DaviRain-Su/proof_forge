#!/usr/bin/env python3
# ProofForge MCP-V0 — minimal stdio MCP server over product CLI JSON.
# Authority: docs/product/01-toolchain-install-surface.md §8.
#
# - Tools only spawn proof-forge-next (or package doctor/install engines under
#   the same contracts). Never reimplements solc/leo/nargo/etc.
# - Never invents PATH fallback toolchain tools into PROOF_FORGE_TOOL_ROOT.
# - No default network broadcast tool (network requires explicit CLI --broadcast).
# - deployable maturity is not rewritten here.
#
# Transport: newline-delimited JSON-RPC 2.0 on stdin/stdout (MCP stdio).
# Logs: stderr only.

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import traceback
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "proof-forge-mcp"
SERVER_VERSION = "0.1.0"
SCHEMA_WRAP = "proof-forge.mcp.tool-result.v1"

# ---------------------------------------------------------------------------
# Repo / CLI resolution
# ---------------------------------------------------------------------------


def _script_dir() -> Path:
    return Path(__file__).resolve().parent


def find_repo_root() -> Path:
    """Resolve package root (contains scripts/proof_forge_doctor.py + lakefile)."""
    env = os.environ.get("PROOF_FORGE_ROOT", "").strip()
    if env:
        p = Path(env).expanduser().resolve()
        if not (p / "scripts" / "proof_forge_doctor.py").is_file():
            raise RuntimeError(
                f"PROOF_FORGE_ROOT={p} does not contain scripts/proof_forge_doctor.py"
            )
        return p

    # tools/mcp/ → repo root
    candidate = _script_dir().parent.parent
    if (candidate / "scripts" / "proof_forge_doctor.py").is_file():
        return candidate.resolve()

    cwd = Path.cwd().resolve()
    if (cwd / "scripts" / "proof_forge_doctor.py").is_file():
        return cwd

    raise RuntimeError(
        "cannot locate ProofForge repo root; set PROOF_FORGE_ROOT or run from package root"
    )


def find_cli(repo_root: Path) -> Path:
    """Locate product CLI binary. Not a Tool Lock toolchain (solc etc.)."""
    env = os.environ.get("PROOF_FORGE_CLI", "").strip()
    if env:
        p = Path(env).expanduser().resolve()
        if not p.is_file():
            raise RuntimeError(f"PROOF_FORGE_CLI is not a file: {p}")
        return p

    built = repo_root / ".lake" / "build" / "bin" / "proof-forge-next"
    if built.is_file() and os.access(built, os.X_OK):
        return built.resolve()

    which = shutil.which("proof-forge-next")
    if which:
        return Path(which).resolve()

    raise RuntimeError(
        "proof-forge-next not found; build with `lake build` or set PROOF_FORGE_CLI "
        f"(expected {built})"
    )


# ---------------------------------------------------------------------------
# Subprocess helpers
# ---------------------------------------------------------------------------


def run_cli(
    repo_root: Path,
    cli: Path,
    args: Sequence[str],
    *,
    timeout: Optional[float] = None,
    extra_env: Optional[Dict[str, str]] = None,
) -> Dict[str, Any]:
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    cmd = [str(cli), *args]
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(repo_root),
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        return {
            "schema": SCHEMA_WRAP,
            "ok": False,
            "exitCode": None,
            "command": cmd,
            "stdout": (e.stdout or "") if isinstance(e.stdout, str) else "",
            "stderr": (e.stderr or "") if isinstance(e.stderr, str) else "timeout",
            "error": "timeout",
            "parsed": None,
        }

    stdout = proc.stdout or ""
    stderr = proc.stderr or ""
    parsed = _try_parse_json(stdout)
    return {
        "schema": SCHEMA_WRAP,
        "ok": proc.returncode == 0,
        "exitCode": proc.returncode,
        "command": cmd,
        "stdout": stdout,
        "stderr": stderr,
        "parsed": parsed,
        "error": None if proc.returncode == 0 else _classify_error(stderr, proc.returncode),
    }


def run_python_engine(
    repo_root: Path,
    script_name: str,
    args: Sequence[str],
    *,
    timeout: Optional[float] = None,
) -> Dict[str, Any]:
    """Direct engine path (same scripts CLI wraps). Prefer when CLI binary missing optional."""
    script = repo_root / "scripts" / script_name
    if not script.is_file():
        return {
            "schema": SCHEMA_WRAP,
            "ok": False,
            "exitCode": 2,
            "command": [],
            "stdout": "",
            "stderr": f"missing engine script: {script}",
            "parsed": None,
            "error": "usage",
        }
    cmd = ["/usr/bin/python3", "-I", "-S", str(script), *args]
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(repo_root),
            env=os.environ.copy(),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        return {
            "schema": SCHEMA_WRAP,
            "ok": False,
            "exitCode": None,
            "command": cmd,
            "stdout": (e.stdout or "") if isinstance(e.stdout, str) else "",
            "stderr": (e.stderr or "") if isinstance(e.stderr, str) else "timeout",
            "parsed": None,
            "error": "timeout",
        }
    stdout = proc.stdout or ""
    stderr = proc.stderr or ""
    return {
        "schema": SCHEMA_WRAP,
        "ok": proc.returncode == 0,
        "exitCode": proc.returncode,
        "command": cmd,
        "stdout": stdout,
        "stderr": stderr,
        "parsed": _try_parse_json(stdout),
        "error": None if proc.returncode == 0 else _classify_error(stderr, proc.returncode),
    }


def _try_parse_json(text: str) -> Any:
    s = text.strip()
    if not s:
        return None
    # Prefer whole stdout as JSON; if multi-line noise, try last {...} block.
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        pass
    start = s.find("{")
    end = s.rfind("}")
    if start >= 0 and end > start:
        try:
            return json.loads(s[start : end + 1])
        except json.JSONDecodeError:
            return None
    return None


def _classify_error(stderr: str, code: int) -> str:
    if "PF-TOOLCHAIN-MISSING" in stderr:
        return "toolchain-missing"
    if "PF-TOOLCHAIN-MISMATCH" in stderr:
        return "toolchain-mismatch"
    if "PF-SRC-INVALID" in stderr:
        return "src-invalid"
    if "PF-OUTPUT-MANIFEST" in stderr:
        return "output-manifest"
    if code == 2:
        return "usage"
    if code == 3:
        return "product-error"
    return "failed"


def _as_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(x) for x in value]
    if isinstance(value, str):
        parts = [p.strip() for p in value.replace(";", ",").split(",")]
        return [p for p in parts if p]
    return [str(value)]


def _tool_result_text(payload: Dict[str, Any], *, is_error: bool = False) -> Dict[str, Any]:
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    return {
        "content": [{"type": "text", "text": text}],
        "isError": bool(is_error or not payload.get("ok", True)),
    }


# ---------------------------------------------------------------------------
# Tool handlers
# ---------------------------------------------------------------------------


def tool_pf_list_targets(repo_root: Path, cli: Path, args: Dict[str, Any]) -> Dict[str, Any]:
    argv = ["list-targets", "--json"]
    if args.get("includeAll") or args.get("all") or args.get("include_all"):
        argv.append("--all")
    result = run_cli(repo_root, cli, argv)
    return _tool_result_text(result, is_error=not result["ok"])


def tool_pf_doctor(repo_root: Path, cli: Path, args: Dict[str, Any]) -> Dict[str, Any]:
    argv = ["doctor", "--json"]
    targets = _as_list(args.get("targets") or args.get("target"))
    for t in targets:
        argv.extend(["--target", t])
    if args.get("withRuntime") or args.get("with_runtime"):
        argv.append("--with-runtime")
    if args.get("includeAll") or args.get("all"):
        argv.append("--all")
    # Prefer product CLI when available; falls back to engine if CLI fails to start.
    try:
        result = run_cli(repo_root, cli, argv)
    except Exception as e:
        eng = ["--json"]
        for t in targets:
            eng.extend(["--target", t])
        if args.get("withRuntime") or args.get("with_runtime"):
            eng.append("--with-runtime")
        if args.get("includeAll") or args.get("all"):
            eng.append("--all")
        result = run_python_engine(repo_root, "proof_forge_doctor.py", eng)
        result["fallback"] = f"cli-error:{e}"
    # Doctor exit 3 for missing/partial is informational for agents: still return body.
    if result.get("parsed") is not None and result.get("exitCode") in (0, 3):
        result["ok"] = True
        result["productOk"] = result.get("exitCode") == 0
    return _tool_result_text(result, is_error=result.get("exitCode") not in (0, 3) and not result.get("ok"))


def tool_pf_install(repo_root: Path, cli: Path, args: Dict[str, Any]) -> Dict[str, Any]:
    argv = ["install", "--json"]
    dry_run = bool(args.get("dryRun") or args.get("dry_run"))
    all_core = bool(args.get("allCore") or args.get("all_core"))
    targets = _as_list(args.get("targets") or args.get("target"))
    if all_core:
        argv.append("--all-core")
    elif targets:
        argv.extend(["--targets", ",".join(targets)])
    else:
        return _tool_result_text(
            {
                "schema": SCHEMA_WRAP,
                "ok": False,
                "exitCode": 2,
                "command": [],
                "stdout": "",
                "stderr": "pf_install requires targets=[...] or allCore=true",
                "parsed": None,
                "error": "usage",
            },
            is_error=True,
        )
    if dry_run:
        argv.append("--dry-run")
    else:
        # Non-interactive product install requires --yes.
        argv.append("--yes")
    if args.get("withRuntime") or args.get("with_runtime"):
        argv.append("--with-runtime")
    result = run_cli(repo_root, cli, argv)
    return _tool_result_text(result, is_error=not result["ok"])


def tool_pf_build(repo_root: Path, cli: Path, args: Dict[str, Any]) -> Dict[str, Any]:
    source = args.get("source") or args.get("sourcePath") or args.get("source_path")
    module = args.get("module")
    target = args.get("target")
    if not source or not module or not target:
        return _tool_result_text(
            {
                "schema": SCHEMA_WRAP,
                "ok": False,
                "exitCode": 2,
                "command": [],
                "stdout": "",
                "stderr": "pf_build requires source, module, and target",
                "parsed": None,
                "error": "usage",
            },
            is_error=True,
        )
    argv = ["build", str(source), "--module", str(module), "--target", str(target), "--json"]
    out = args.get("output") or args.get("outputDir") or args.get("output_dir") or args.get("o")
    if out:
        argv.extend(["-o", str(out)])
    program = args.get("program")
    if program:
        argv.extend(["--program", str(program)])
    profile = args.get("profile")
    if profile:
        argv.extend(["--profile", str(profile)])
    root = args.get("root")
    if root:
        argv.extend(["--root", str(root)])
    # Hard reject network broadcast via this tool surface.
    if args.get("broadcast") or args.get("network"):
        return _tool_result_text(
            {
                "schema": SCHEMA_WRAP,
                "ok": False,
                "exitCode": 2,
                "command": [],
                "stdout": "",
                "stderr": "pf_build does not support network/broadcast; use product CLI network --broadcast explicitly",
                "parsed": None,
                "error": "usage",
            },
            is_error=True,
        )
    timeout = args.get("timeoutSeconds") or args.get("timeout_seconds")
    to = float(timeout) if timeout is not None else None
    result = run_cli(repo_root, cli, argv, timeout=to)
    return _tool_result_text(result, is_error=not result["ok"])


def tool_pf_artifacts(repo_root: Path, cli: Path, args: Dict[str, Any]) -> Dict[str, Any]:
    """inspect output-dir (artifact closure) or inspect <target> descriptor."""
    output_dir = (
        args.get("outputDir")
        or args.get("output_dir")
        or args.get("dir")
        or args.get("path")
    )
    target = args.get("target")
    argv: List[str]
    if output_dir:
        # Force path form so target-id collision cannot hijack inspect.
        argv = ["inspect", "--output-dir", str(output_dir), "--json"]
    elif target:
        argv = ["inspect", str(target), "--json"]
    else:
        return _tool_result_text(
            {
                "schema": SCHEMA_WRAP,
                "ok": False,
                "exitCode": 2,
                "command": [],
                "stdout": "",
                "stderr": "pf_artifacts requires outputDir (build output) or target (registry inspect)",
                "parsed": None,
                "error": "usage",
            },
            is_error=True,
        )
    result = run_cli(repo_root, cli, argv)
    return _tool_result_text(result, is_error=not result["ok"])


def tool_pf_local(repo_root: Path, cli: Path, args: Dict[str, Any]) -> Dict[str, Any]:
    """Product local host-heavy scripts (Aleo generic sandbox, etc.).

    Never accepts network broadcast or raw private keys. Aleo sandbox requires
    source + module (no default program).
    """
    target = args.get("target")
    if not target:
        return _tool_result_text(
            {
                "schema": SCHEMA_WRAP,
                "ok": False,
                "exitCode": 2,
                "command": [],
                "stdout": "",
                "stderr": "pf_local requires target",
                "parsed": None,
                "error": "usage",
            },
            is_error=True,
        )
    # Hard reject network / secrets on this surface.
    for bad in (
        "broadcast",
        "network",
        "privateKey",
        "private_key",
        "privateKeyFile",
        "private_key_file",
        "feeRecord",
        "fee_record",
    ):
        if args.get(bad):
            return _tool_result_text(
                {
                    "schema": SCHEMA_WRAP,
                    "ok": False,
                    "exitCode": 2,
                    "command": [],
                    "stdout": "",
                    "stderr": (
                        "pf_local does not support network/broadcast or signer secrets; "
                        "use product CLI network --broadcast outside MCP"
                    ),
                    "parsed": None,
                    "error": "usage",
                },
                is_error=True,
            )

    mode = args.get("mode")
    source = args.get("source") or args.get("sourcePath") or args.get("source_path")
    module = args.get("module")
    if str(target) == "aleo" and (mode is None or str(mode) in ("", "sandbox")):
        if not source or not module:
            return _tool_result_text(
                {
                    "schema": SCHEMA_WRAP,
                    "ok": False,
                    "exitCode": 2,
                    "command": [],
                    "stdout": "",
                    "stderr": (
                        "pf_local aleo sandbox requires source and module "
                        "(generic path; no default program)"
                    ),
                    "parsed": None,
                    "error": "usage",
                },
                is_error=True,
            )

    argv: List[str] = ["local", "--target", str(target), "--json"]
    if mode:
        argv.extend(["--mode", str(mode)])
    tail: List[str] = []
    if source:
        tail.extend(["--source", str(source)])
    if module:
        tail.extend(["--module", str(module)])
    root_arg = args.get("root") or args.get("projectRoot") or args.get("project_root")
    if root_arg:
        tail.extend(["--root", str(root_arg)])
    program = args.get("program")
    if program:
        tail.extend(["--program", str(program)])
    profile = args.get("profile")
    if profile:
        tail.extend(["--profile", str(profile)])
    golden = args.get("golden")
    if golden:
        tail.extend(["--golden", str(golden)])
    out = args.get("outputDir") or args.get("output_dir") or args.get("output")
    if out:
        tail.extend(["--output-dir", str(out)])
    if args.get("skipRun") or args.get("skip_run"):
        tail.append("--skip-run")
    runs = args.get("runs") or args.get("run") or []
    if isinstance(runs, str):
        runs = [runs]
    for r in runs:
        tail.extend(["--run", str(r)])
    extra = args.get("scriptArgs") or args.get("script_args") or []
    if isinstance(extra, str):
        extra = [extra]
    for a in extra:
        s = str(a)
        if s in (
            "--broadcast",
            "--private-key",
            "--priv-key",
            "--fee-record",
            "--private-key-file",
        ) or s.startswith((
            "--broadcast=",
            "--private-key=",
            "--priv-key=",
            "--fee-record=",
            "--private-key-file=",
        )):
            return _tool_result_text(
                {
                    "schema": SCHEMA_WRAP,
                    "ok": False,
                    "exitCode": 2,
                    "command": [],
                    "stdout": "",
                    "stderr": "pf_local rejects signer/broadcast scriptArgs",
                    "parsed": None,
                    "error": "usage",
                },
                is_error=True,
            )
        tail.append(s)
    if tail:
        argv.append("--")
        argv.extend(tail)

    timeout = args.get("timeoutSeconds") or args.get("timeout_seconds")
    to = float(timeout) if timeout is not None else None
    result = run_cli(repo_root, cli, argv, timeout=to)
    return _tool_result_text(result, is_error=not result["ok"])


def tool_pf_chain_catalog(repo_root: Path, cli: Path, args: Dict[str, Any]) -> Dict[str, Any]:
    """Static chain client/frontend catalog (metadata only; no CLI spawn)."""
    del cli  # catalog is package JSON, not product CLI
    path = repo_root / "docs" / "product" / "chain-client-catalog.v1.json"
    if not path.is_file():
        return _tool_result_text(
            {
                "schema": SCHEMA_WRAP,
                "ok": False,
                "exitCode": 2,
                "command": [],
                "stdout": "",
                "stderr": f"missing catalog {path}",
                "parsed": None,
                "error": "usage",
            },
            is_error=True,
        )
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        return _tool_result_text(
            {
                "schema": SCHEMA_WRAP,
                "ok": False,
                "exitCode": 1,
                "command": [str(path)],
                "stdout": "",
                "stderr": str(e),
                "parsed": None,
                "error": "failed",
            },
            is_error=True,
        )
    if not isinstance(data, dict) or data.get("schema") != "proof-forge.chain-client-catalog.v1":
        return _tool_result_text(
            {
                "schema": SCHEMA_WRAP,
                "ok": False,
                "exitCode": 1,
                "command": [str(path)],
                "stdout": "",
                "stderr": "invalid catalog schema",
                "parsed": None,
                "error": "failed",
            },
            is_error=True,
        )
    target = args.get("target")
    include_design = bool(args.get("includeDesignOnly") or args.get("include_design_only"))
    rows = data.get("targets") or []
    filtered = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        tid = str(row.get("id") or "")
        implemented = bool(row.get("implemented"))
        if target is not None and tid != str(target):
            continue
        if target is None and not include_design and not implemented:
            continue
        filtered.append(row)
    if target is not None and not filtered:
        return _tool_result_text(
            {
                "schema": SCHEMA_WRAP,
                "ok": False,
                "exitCode": 2,
                "command": [str(path)],
                "stdout": "",
                "stderr": f"unknown catalog target id: {target}",
                "parsed": None,
                "error": "usage",
            },
            is_error=True,
        )
    out = dict(data)
    out["targets"] = filtered
    out["filter"] = {"target": target, "includeDesignOnly": include_design}
    return _tool_result_text(
        {
            "schema": SCHEMA_WRAP,
            "ok": True,
            "exitCode": 0,
            "command": [str(path)],
            "stdout": json.dumps(out, ensure_ascii=False, separators=(",", ":")),
            "stderr": "",
            "parsed": out,
            "error": None,
        },
        is_error=False,
    )


TOOL_HANDLERS = {
    "pf_list_targets": tool_pf_list_targets,
    "pf_doctor": tool_pf_doctor,
    "pf_install": tool_pf_install,
    "pf_build": tool_pf_build,
    "pf_artifacts": tool_pf_artifacts,
    "pf_local": tool_pf_local,
    "pf_chain_catalog": tool_pf_chain_catalog,
}


def tool_definitions() -> List[Dict[str, Any]]:
    return [
        {
            "name": "pf_list_targets",
            "description": (
                "List ProofForge TargetRegistryV1 targets (implemented by default). "
                "Set includeAll=true to also list design-only (unsupported) targets. "
                "Maps to: proof-forge-next list-targets [--all] --json"
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "includeAll": {
                        "type": "boolean",
                        "description": "Include design-only targets (soroban/icp/openvm).",
                    }
                },
                "additionalProperties": False,
            },
        },
        {
            "name": "pf_doctor",
            "description": (
                "Diagnose Tool Lock tools under PROOF_FORGE_TOOL_ROOT for implemented targets. "
                "Never uses PATH fallback tools. Maps to: proof-forge-next doctor --json"
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "targets": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Optional target ids (e.g. [\"aleo\",\"solana\"]).",
                    },
                    "target": {
                        "type": "string",
                        "description": "Single target id (alias of targets).",
                    },
                    "withRuntime": {
                        "type": "boolean",
                        "description": "Also report runtime-tier tools (anvil, near-sandbox, snarkos honesty).",
                    },
                    "includeAll": {
                        "type": "boolean",
                        "description": "Include design-only as unsupported rows.",
                    },
                },
                "additionalProperties": False,
            },
        },
        {
            "name": "pf_install",
            "description": (
                "Non-interactive install of Tool Lock assets for selected targets into "
                "PROOF_FORGE_TOOL_ROOT. Always passes --yes (or --dry-run). No PATH fallback. "
                "Maps to: proof-forge-next install --targets … --yes --json"
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "targets": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Implemented target ids to install core tools for.",
                    },
                    "allCore": {
                        "type": "boolean",
                        "description": "Install core tools for all implemented targets.",
                    },
                    "withRuntime": {
                        "type": "boolean",
                        "description": "Also install lock runtime tools; Aleo snarkos is documented only.",
                    },
                    "dryRun": {
                        "type": "boolean",
                        "description": "Plan only; do not materialize.",
                    },
                },
                "additionalProperties": False,
            },
        },
        {
            "name": "pf_build",
            "description": (
                "Build a ProofForge program for one target. Spawns product CLI only; "
                "does not reimplement compilers. No network broadcast. "
                "Maps to: proof-forge-next build <source> --module … --target … [--profile] -o … --json"
            ),
            "inputSchema": {
                "type": "object",
                "required": ["source", "module", "target"],
                "properties": {
                    "source": {
                        "type": "string",
                        "description": "Path to source .lean program file (repo-relative or absolute).",
                    },
                    "module": {
                        "type": "string",
                        "description": "Lean module name, e.g. Examples.Counter",
                    },
                    "target": {
                        "type": "string",
                        "description": "Implemented TargetId (evm, solana, near, noir, aleo, psy, quint, cosmwasm, ton).",
                    },
                    "output": {
                        "type": "string",
                        "description": "Output directory (-o). Default CLI: build/v2",
                    },
                    "profile": {
                        "type": "string",
                        "description": "Optional codegen profile id.",
                    },
                    "program": {
                        "type": "string",
                        "description": "Optional program name selector.",
                    },
                    "root": {
                        "type": "string",
                        "description": "Optional --root for module path resolution.",
                    },
                    "timeoutSeconds": {
                        "type": "number",
                        "description": "Optional subprocess timeout.",
                    },
                },
                "additionalProperties": False,
            },
        },
        {
            "name": "pf_artifacts",
            "description": (
                "Inspect a published output directory (proof-forge.output.v1 exact disk closure) "
                "or a target registry descriptor. "
                "Maps to: proof-forge-next inspect --output-dir <dir> --json | inspect <target> --json"
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "outputDir": {
                        "type": "string",
                        "description": "Build output directory to revalidate and list artifacts.",
                    },
                    "target": {
                        "type": "string",
                        "description": "Registered target id to inspect (descriptor, not artifacts).",
                    },
                },
                "additionalProperties": False,
            },
        },
        {
            "name": "pf_local",
            "description": (
                "Run product local host-heavy scripts (e.g. Aleo offline sandbox). "
                "Generic: for Aleo sandbox pass source + module + optional runs "
                "(no default program). Does NOT broadcast network or accept private keys. "
                "Maps to: proof-forge-next local --target … [--mode sandbox] -- --source … --module …"
            ),
            "inputSchema": {
                "type": "object",
                "required": ["target"],
                "properties": {
                    "target": {
                        "type": "string",
                        "description": "Implemented target id (aleo, solana, evm, …).",
                    },
                    "mode": {
                        "type": "string",
                        "description": "Local mode (aleo: sandbox|devnet; default sandbox).",
                    },
                    "source": {
                        "type": "string",
                        "description": "ProgramV1 .lean path (required for aleo sandbox).",
                    },
                    "module": {
                        "type": "string",
                        "description": "Lean module name (required for aleo sandbox).",
                    },
                    "root": {
                        "type": "string",
                        "description": "External project root for product --root (source is relative to it).",
                    },
                    "projectRoot": {
                        "type": "string",
                        "description": "Alias for root; passed through as product --root.",
                    },
                    "project_root": {
                        "type": "string",
                        "description": "Alias for root; passed through as product --root.",
                    },
                    "program": {
                        "type": "string",
                        "description": "Optional --program selector.",
                    },
                    "profile": {
                        "type": "string",
                        "description": "Optional codegen profile id.",
                    },
                    "golden": {
                        "type": "string",
                        "description": "Optional Instructions golden path for byte pin.",
                    },
                    "runs": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": (
                            "Optional leo run lines, e.g. [\"initialize 1u64\", \"increment 2u64\"]."
                        ),
                    },
                    "skipRun": {
                        "type": "boolean",
                        "description": "Skip offline run steps (build pins only).",
                    },
                    "outputDir": {
                        "type": "string",
                        "description": "Optional keep product OutputSet directory.",
                    },
                    "timeoutSeconds": {
                        "type": "number",
                        "description": "Optional subprocess timeout (host-heavy).",
                    },
                },
                "additionalProperties": False,
            },
        },
        {
            "name": "pf_chain_catalog",
            "description": (
                "Static multi-chain client/frontend catalog for authors and Code Agents. "
                "Metadata only (ecosystem SDKs are not shipped by ProofForge). "
                "Use before building a dApp UI to learn backend PF surface vs frontend clients. "
                "Does not broadcast network or install npm packages."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "target": {
                        "type": "string",
                        "description": "Optional TargetId filter (e.g. aleo).",
                    },
                    "includeDesignOnly": {
                        "type": "boolean",
                        "description": "Include design-only targets when target is omitted.",
                    },
                },
                "additionalProperties": False,
            },
        },
    ]


# ---------------------------------------------------------------------------
# JSON-RPC / MCP lifecycle
# ---------------------------------------------------------------------------


class McpServer:
    def __init__(self) -> None:
        self.repo_root = find_repo_root()
        self.cli = find_cli(self.repo_root)
        self.initialized = False

    def handle(self, msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        if "method" not in msg:
            # Response from client — ignore.
            return None
        method = msg["method"]
        msg_id = msg.get("id")
        params = msg.get("params") or {}

        # Notifications (no id) — no response.
        is_notification = "id" not in msg

        try:
            if method == "initialize":
                result = self._initialize(params)
            elif method == "notifications/initialized":
                self.initialized = True
                return None
            elif method == "ping":
                result = {}
            elif method == "tools/list":
                result = {"tools": tool_definitions()}
            elif method == "tools/call":
                result = self._tools_call(params)
            elif method == "resources/list":
                result = {"resources": []}
            elif method == "prompts/list":
                result = {"prompts": []}
            else:
                if is_notification:
                    return None
                return self._error(msg_id, -32601, f"Method not found: {method}")
        except Exception as e:
            traceback.print_exc(file=sys.stderr)
            if is_notification:
                return None
            return self._error(msg_id, -32000, str(e))

        if is_notification:
            return None
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    def _initialize(self, params: Dict[str, Any]) -> Dict[str, Any]:
        # Accept any client protocol version we know; echo preferred.
        client_version = params.get("protocolVersion") or PROTOCOL_VERSION
        # Negotiate: prefer 2024-11-05 / 2025-03-26 style if offered.
        supported = {"2024-11-05", "2025-03-26", "2025-06-18"}
        version = client_version if client_version in supported else PROTOCOL_VERSION
        self.initialized = True
        return {
            "protocolVersion": version,
            "capabilities": {
                "tools": {"listChanged": False},
            },
            "serverInfo": {
                "name": SERVER_NAME,
                "version": SERVER_VERSION,
            },
            "instructions": (
                "ProofForge product surface MCP. Tools shell to proof-forge-next only. "
                f"repoRoot={self.repo_root} cli={self.cli}. "
                "Use PROOF_FORGE_TOOL_ROOT for Tool Lock tools. "
                "No network broadcast tool; no PATH toolchain fallback; "
                "do not treat success as formal/hermetic/mainnet evidence."
            ),
        }

    def _tools_call(self, params: Dict[str, Any]) -> Dict[str, Any]:
        name = params.get("name")
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict):
            arguments = {}
        handler = TOOL_HANDLERS.get(name or "")
        if handler is None:
            return {
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps(
                            {
                                "schema": SCHEMA_WRAP,
                                "ok": False,
                                "error": "unknown-tool",
                                "name": name,
                            }
                        ),
                    }
                ],
                "isError": True,
            }
        return handler(self.repo_root, self.cli, arguments)

    @staticmethod
    def _error(msg_id: Any, code: int, message: str) -> Dict[str, Any]:
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "error": {"code": code, "message": message},
        }


def _read_message() -> Optional[Dict[str, Any]]:
    """Read one newline-delimited JSON-RPC message from stdin."""
    line = sys.stdin.buffer.readline()
    if not line:
        return None
    line = line.strip()
    if not line:
        # Skip empty lines.
        return _read_message()
    # Optional Content-Length framing (LSP-style) compatibility:
    if line.lower().startswith(b"content-length:"):
        try:
            length = int(line.split(b":", 1)[1].strip())
        except ValueError:
            return None
        # Consume headers until blank line.
        while True:
            hdr = sys.stdin.buffer.readline()
            if not hdr or hdr in (b"\r\n", b"\n"):
                break
        body = sys.stdin.buffer.read(length)
        return json.loads(body.decode("utf-8"))
    return json.loads(line.decode("utf-8"))


def _write_message(msg: Dict[str, Any]) -> None:
    data = json.dumps(msg, ensure_ascii=False, separators=(",", ":"))
    # Newline-delimited (MCP stdio 2025-03-26). No embedded newlines.
    sys.stdout.write(data + "\n")
    sys.stdout.flush()


def main(argv: Optional[Sequence[str]] = None) -> int:
    argv = list(argv if argv is not None else sys.argv[1:])
    if "--help" in argv or "-h" in argv:
        sys.stderr.write(
            "proof_forge_mcp_server.py — stdio MCP for ProofForge product CLI\n"
            "Env:\n"
            "  PROOF_FORGE_ROOT   package root (optional if launched from tools/mcp)\n"
            "  PROOF_FORGE_CLI    path to proof-forge-next binary (optional)\n"
            "  PROOF_FORGE_TOOL_ROOT  Tool Lock root (consumed by doctor/install/build)\n"
            "Tools: pf_list_targets pf_doctor pf_install pf_build pf_artifacts pf_local pf_chain_catalog\n"
        )
        return 0
    if "--self-check" in argv:
        try:
            root = find_repo_root()
            cli = find_cli(root)
            print(
                json.dumps(
                    {
                        "ok": True,
                        "repoRoot": str(root),
                        "cli": str(cli),
                        "tools": sorted(TOOL_HANDLERS.keys()),
                    },
                    indent=2,
                )
            )
            return 0
        except Exception as e:
            print(json.dumps({"ok": False, "error": str(e)}), file=sys.stderr)
            return 1

    try:
        server = McpServer()
    except Exception as e:
        sys.stderr.write(f"PF-MCP-INIT: {e}\n")
        return 1

    sys.stderr.write(
        f"{SERVER_NAME} {SERVER_VERSION} ready repo={server.repo_root} cli={server.cli}\n"
    )
    while True:
        try:
            msg = _read_message()
        except json.JSONDecodeError as e:
            _write_message(
                {
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {"code": -32700, "message": f"Parse error: {e}"},
                }
            )
            continue
        if msg is None:
            break
        # Support JSON-RPC batches (array).
        if isinstance(msg, list):
            responses = []
            for item in msg:
                if not isinstance(item, dict):
                    continue
                resp = server.handle(item)
                if resp is not None:
                    responses.append(resp)
            if responses:
                # Spec allows batch; emit one line per response for simplicity.
                for resp in responses:
                    _write_message(resp)
            continue
        if not isinstance(msg, dict):
            continue
        resp = server.handle(msg)
        if resp is not None:
            _write_message(resp)
    return 0


if __name__ == "__main__":
    sys.exit(main())

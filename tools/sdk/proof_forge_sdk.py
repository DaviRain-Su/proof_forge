#!/usr/bin/env python3
"""ProofForge SDK-V0 — thin Python client over product CLI JSON.

Authority: docs/product/01-toolchain-install-surface.md §9.

- Spawns ``proof-forge-next`` (or package doctor/install engines under the same
  contracts). Never reimplements solc/leo/nargo/sbpf/etc.
- Never invents PATH fallback toolchain tools into ``PROOF_FORGE_TOOL_ROOT``.
- Never rewrites ``deployable`` maturity.
- No default network broadcast API (use product CLI ``network --broadcast``).
- Success is not formal / hermetic / mainnet / Stage-0 evidence.

Schemas consumed (parse-only; product CLI remains authority):
  - proof-forge.cli.list-targets.v1
  - proof-forge.doctor.v1
  - proof-forge.install.v1
  - proof-forge.output.v1 (on-disk engineering manifest ``schemaVersion``)
  - build / check / inspect product JSON (schema may vary by command)

Usage::

    from proof_forge_sdk import ProofForgeClient
    client = ProofForgeClient()  # PROOF_FORGE_ROOT / CWD
    print(client.list_targets().parsed)
    print(client.doctor(targets=["quint"]).parsed)
    manifest = client.load_output_manifest("/path/to/output")
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Union

SCHEMA_RESULT = "proof-forge.sdk.result.v1"
SCHEMA_LIST_TARGETS = "proof-forge.cli.list-targets.v1"
SCHEMA_DOCTOR = "proof-forge.doctor.v1"
SCHEMA_INSTALL = "proof-forge.install.v1"
SCHEMA_OUTPUT = "proof-forge.output.v1"
SCHEMA_CHAIN_CATALOG = "proof-forge.chain-client-catalog.v1"
SCHEMA_NETWORK_CATALOG = "proof-forge.network-catalog.v1"
CATALOG_REL = Path("docs/product/chain-client-catalog.v1.json")
NETWORKS_REL = Path("docs/product/networks.v1.json")

IMPLEMENTED_TARGETS = (
    "evm",
    "solana",
    "near",
    "noir",
    "aleo",
    "psy",
    "quint",
    "cosmwasm",
    "ton",
)
DESIGN_ONLY_TARGETS = ("soroban", "icp", "openvm")

PathLike = Union[str, Path]


# ---------------------------------------------------------------------------
# Result carrier
# ---------------------------------------------------------------------------


@dataclass
class CliResult:
    """Structured result of one product CLI / engine invocation."""

    schema: str = SCHEMA_RESULT
    ok: bool = False
    exit_code: Optional[int] = None
    command: List[str] = field(default_factory=list)
    stdout: str = ""
    stderr: str = ""
    parsed: Any = None
    error: Optional[str] = None
    # Doctor exit 3 with body: product status may be non-zero while payload is usable.
    product_ok: Optional[bool] = None

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        # camelCase aliases for Agent/JSON consumers (keep snake for Python).
        d["exitCode"] = d.pop("exit_code")
        d["productOk"] = d.pop("product_ok")
        return d


# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------


def _script_dir() -> Path:
    return Path(__file__).resolve().parent


def find_repo_root(explicit: Optional[PathLike] = None) -> Path:
    """Resolve package root (must contain scripts/proof_forge_doctor.py)."""
    if explicit is not None:
        p = Path(explicit).expanduser().resolve()
        if not (p / "scripts" / "proof_forge_doctor.py").is_file():
            raise FileNotFoundError(
                f"repo root {p} missing scripts/proof_forge_doctor.py"
            )
        return p

    env = os.environ.get("PROOF_FORGE_ROOT", "").strip()
    if env:
        p = Path(env).expanduser().resolve()
        if not (p / "scripts" / "proof_forge_doctor.py").is_file():
            raise FileNotFoundError(
                f"PROOF_FORGE_ROOT={p} missing scripts/proof_forge_doctor.py"
            )
        return p

    # tools/sdk/ → repo root
    candidate = _script_dir().parent.parent
    if (candidate / "scripts" / "proof_forge_doctor.py").is_file():
        return candidate.resolve()

    cwd = Path.cwd().resolve()
    if (cwd / "scripts" / "proof_forge_doctor.py").is_file():
        return cwd

    raise FileNotFoundError(
        "cannot locate ProofForge package root; set PROOF_FORGE_ROOT or pass root="
    )


def find_cli(repo_root: Path, explicit: Optional[PathLike] = None) -> Path:
    """Locate product CLI binary. Not a Tool Lock toolchain (solc etc.)."""
    if explicit is not None:
        p = Path(explicit).expanduser().resolve()
        if not p.is_file():
            raise FileNotFoundError(f"cli path is not a file: {p}")
        return p

    env = os.environ.get("PROOF_FORGE_CLI", "").strip()
    if env:
        p = Path(env).expanduser().resolve()
        if not p.is_file():
            raise FileNotFoundError(f"PROOF_FORGE_CLI is not a file: {p}")
        return p

    built = repo_root / ".lake" / "build" / "bin" / "proof-forge-next"
    if built.is_file() and os.access(built, os.X_OK):
        return built.resolve()

    which = shutil.which("proof-forge-next")
    if which:
        return Path(which).resolve()

    raise FileNotFoundError(
        "proof-forge-next not found; build with `lake build` or set PROOF_FORGE_CLI "
        f"(expected {built})"
    )


# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------


def try_parse_json(text: str) -> Any:
    s = text.strip()
    if not s:
        return None
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


def classify_error(stderr: str, code: Optional[int]) -> str:
    if code is None:
        return "timeout"
    if "PF-TOOLCHAIN-MISSING" in stderr:
        return "toolchain-missing"
    if "PF-TOOLCHAIN-MISMATCH" in stderr:
        return "toolchain-mismatch"
    if "PF-SRC-INVALID" in stderr:
        return "src-invalid"
    if "PF-OUTPUT-MANIFEST" in stderr or "PF-ARTIFACT" in stderr:
        return "output-manifest"
    if code == 2:
        return "usage"
    if code == 3:
        return "product-error"
    return "failed"


def _as_str_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [str(x) for x in value]
    if isinstance(value, str):
        parts = [p.strip() for p in value.replace(";", ",").split(",")]
        return [p for p in parts if p]
    return [str(value)]


def output_manifest_schema(obj: Mapping[str, Any]) -> Optional[str]:
    """Return output schema id if object looks like engineering proof-forge.output.v1."""
    if not isinstance(obj, Mapping):
        return None
    # Engineering on-disk uses schemaVersion; formal-ish wire may use schema.
    for key in ("schemaVersion", "schema"):
        v = obj.get(key)
        if v == SCHEMA_OUTPUT:
            return SCHEMA_OUTPUT
    return None


def load_output_manifest(output_dir: PathLike) -> Dict[str, Any]:
    """Load and lightly validate on-disk engineering ``proof-forge.output.v1``.

    Reads ``manifest.json`` under *output_dir* (product publisher layout).
    Does **not** re-walk exact disk closure (use ``client.inspect_artifacts`` for
    product revalidation). Does **not** claim formal OutputSetV1.
    """
    root = Path(output_dir).expanduser().resolve()
    path = root / "manifest.json"
    if not path.is_file():
        # Some trees may use proof-forge-output.json; accept either basename.
        alt = root / "proof-forge-output.json"
        if alt.is_file():
            path = alt
        else:
            raise FileNotFoundError(f"no manifest.json under {root}")
    raw = path.read_text(encoding="utf-8")
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: root is not a JSON object")
    if output_manifest_schema(data) != SCHEMA_OUTPUT:
        raise ValueError(
            f"{path}: expected schema/schemaVersion {SCHEMA_OUTPUT!r}, got "
            f"{data.get('schemaVersion') or data.get('schema')!r}"
        )
    # Surface key fields for callers without inventing deployable maturity.
    files = data.get("files")
    if files is not None and not isinstance(files, list):
        raise ValueError(f"{path}: files must be an array when present")
    return data


def file_sha256(path: PathLike) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_chain_client_catalog(
    repo_root: PathLike,
    *,
    target: Optional[str] = None,
    include_design_only: bool = False,
) -> Dict[str, Any]:
    """Load static chain-client catalog JSON (metadata only; not a compiler)."""
    root = Path(repo_root).expanduser().resolve()
    path = root / CATALOG_REL
    if not path.is_file():
        raise FileNotFoundError(f"missing chain client catalog: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path}: root must be object")
    if data.get("schema") != SCHEMA_CHAIN_CATALOG:
        raise ValueError(
            f"{path}: expected schema {SCHEMA_CHAIN_CATALOG!r}, got {data.get('schema')!r}"
        )
    targets = data.get("targets")
    if not isinstance(targets, list):
        raise ValueError(f"{path}: targets must be an array")
    filtered: List[Any] = []
    for row in targets:
        if not isinstance(row, dict):
            continue
        tid = str(row.get("id") or "")
        implemented = bool(row.get("implemented"))
        if target is not None and tid != str(target):
            continue
        if target is None and not include_design_only and not implemented:
            continue
        filtered.append(row)
    if target is not None and not filtered:
        raise KeyError(f"unknown catalog target id: {target}")
    out = dict(data)
    out["targets"] = filtered
    out["filter"] = {
        "target": target,
        "includeDesignOnly": include_design_only,
    }
    return out


def load_network_catalog(
    repo_root: PathLike,
    *,
    network_id: Optional[str] = None,
    target_family: Optional[str] = None,
    env: Optional[str] = None,
    chain_id: Optional[int] = None,
) -> Dict[str, Any]:
    """Load static EVM/network catalog (metadata only; not a deploy authority)."""
    root = Path(repo_root).expanduser().resolve()
    path = root / NETWORKS_REL
    if not path.is_file():
        raise FileNotFoundError(f"missing network catalog: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path}: root must be object")
    if data.get("schema") != SCHEMA_NETWORK_CATALOG:
        raise ValueError(
            f"{path}: expected schema {SCHEMA_NETWORK_CATALOG!r}, got {data.get('schema')!r}"
        )
    rows = data.get("networks")
    if not isinstance(rows, list):
        raise ValueError(f"{path}: networks must be an array")
    filtered: List[Any] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        rid = str(row.get("id") or "")
        if network_id is not None and rid != str(network_id):
            continue
        if target_family is not None and str(row.get("targetFamily") or "") != str(
            target_family
        ):
            continue
        if env is not None and str(row.get("env") or "") != str(env):
            continue
        if chain_id is not None:
            try:
                if int(row.get("chainId")) != int(chain_id):
                    continue
            except (TypeError, ValueError):
                continue
        filtered.append(row)
    if network_id is not None and not filtered:
        raise KeyError(f"unknown network id: {network_id}")
    out = dict(data)
    out["networks"] = filtered
    out["filter"] = {
        "id": network_id,
        "targetFamily": target_family,
        "env": env,
        "chainId": chain_id,
    }
    return out


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------


class ProofForgeClient:
    """Thin product-CLI client for Code Agents and local scripts.

    Environment (optional):
      - ``PROOF_FORGE_ROOT`` — package root
      - ``PROOF_FORGE_CLI`` — path to ``proof-forge-next``
      - ``PROOF_FORGE_TOOL_ROOT`` — Tool Lock materialize root (absolute)
    """

    def __init__(
        self,
        *,
        root: Optional[PathLike] = None,
        cli: Optional[PathLike] = None,
        tool_root: Optional[PathLike] = None,
        default_timeout: Optional[float] = None,
    ) -> None:
        self.root = find_repo_root(root)
        self.cli = find_cli(self.root, cli)
        self.tool_root: Optional[Path] = None
        if tool_root is not None:
            self.tool_root = Path(tool_root).expanduser().resolve()
        elif os.environ.get("PROOF_FORGE_TOOL_ROOT", "").strip():
            self.tool_root = Path(
                os.environ["PROOF_FORGE_TOOL_ROOT"]
            ).expanduser().resolve()
        self.default_timeout = default_timeout

    def _env(self, extra: Optional[Mapping[str, str]] = None) -> Dict[str, str]:
        env = os.environ.copy()
        env["PROOF_FORGE_ROOT"] = str(self.root)
        if self.tool_root is not None:
            env["PROOF_FORGE_TOOL_ROOT"] = str(self.tool_root)
        if extra:
            env.update({str(k): str(v) for k, v in extra.items()})
        return env

    def run(
        self,
        args: Sequence[str],
        *,
        timeout: Optional[float] = None,
        extra_env: Optional[Mapping[str, str]] = None,
    ) -> CliResult:
        """Spawn product CLI with *args* (without the binary name)."""
        cmd = [str(self.cli), *args]
        to = self.default_timeout if timeout is None else timeout
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(self.root),
                env=self._env(extra_env),
                capture_output=True,
                text=True,
                timeout=to,
                check=False,
            )
        except subprocess.TimeoutExpired as e:
            stdout = e.stdout if isinstance(e.stdout, str) else ""
            stderr = e.stderr if isinstance(e.stderr, str) else "timeout"
            return CliResult(
                ok=False,
                exit_code=None,
                command=cmd,
                stdout=stdout or "",
                stderr=stderr or "timeout",
                parsed=None,
                error="timeout",
            )
        stdout = proc.stdout or ""
        stderr = proc.stderr or ""
        parsed = try_parse_json(stdout)
        ok = proc.returncode == 0
        return CliResult(
            ok=ok,
            exit_code=proc.returncode,
            command=cmd,
            stdout=stdout,
            stderr=stderr,
            parsed=parsed,
            error=None if ok else classify_error(stderr, proc.returncode),
            product_ok=ok,
        )

    def run_engine(
        self,
        script_name: str,
        args: Sequence[str],
        *,
        timeout: Optional[float] = None,
    ) -> CliResult:
        """Direct package engine (same scripts CLI wraps). Prefer CLI when present."""
        script = self.root / "scripts" / script_name
        if not script.is_file():
            return CliResult(
                ok=False,
                exit_code=2,
                command=[],
                stderr=f"missing engine script: {script}",
                error="usage",
            )
        cmd = ["/usr/bin/python3", "-I", "-S", str(script), *args]
        to = self.default_timeout if timeout is None else timeout
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(self.root),
                env=self._env(),
                capture_output=True,
                text=True,
                timeout=to,
                check=False,
            )
        except subprocess.TimeoutExpired as e:
            stdout = e.stdout if isinstance(e.stdout, str) else ""
            stderr = e.stderr if isinstance(e.stderr, str) else "timeout"
            return CliResult(
                ok=False,
                exit_code=None,
                command=cmd,
                stdout=stdout or "",
                stderr=stderr or "timeout",
                error="timeout",
            )
        stdout = proc.stdout or ""
        stderr = proc.stderr or ""
        ok = proc.returncode == 0
        return CliResult(
            ok=ok,
            exit_code=proc.returncode,
            command=cmd,
            stdout=stdout,
            stderr=stderr,
            parsed=try_parse_json(stdout),
            error=None if ok else classify_error(stderr, proc.returncode),
            product_ok=ok,
        )

    # ----- product methods -----

    def list_targets(self, *, include_all: bool = False) -> CliResult:
        argv = ["list-targets", "--json"]
        if include_all:
            argv.append("--all")
        return self.run(argv)

    def doctor(
        self,
        *,
        targets: Optional[Sequence[str]] = None,
        with_runtime: bool = False,
        include_all: bool = False,
    ) -> CliResult:
        argv = ["doctor", "--json"]
        for t in _as_str_list(targets):
            argv.extend(["--target", t])
        if with_runtime:
            argv.append("--with-runtime")
        if include_all:
            argv.append("--all")
        try:
            result = self.run(argv)
        except Exception as e:  # noqa: BLE001 — fall back to engine
            eng = ["--json"]
            for t in _as_str_list(targets):
                eng.extend(["--target", t])
            if with_runtime:
                eng.append("--with-runtime")
            if include_all:
                eng.append("--all")
            result = self.run_engine("proof_forge_doctor.py", eng)
            result.error = f"cli-error:{e}" if result.error is None else result.error
        # Exit 3 with parseable body is usable for agents (missing/partial tools).
        if result.parsed is not None and result.exit_code in (0, 3):
            result.product_ok = result.exit_code == 0
            result.ok = True
            if result.exit_code == 3 and result.error is None:
                result.error = None
        return result

    def install(
        self,
        *,
        targets: Optional[Sequence[str]] = None,
        all_core: bool = False,
        with_runtime: bool = False,
        dry_run: bool = False,
        yes: bool = True,
    ) -> CliResult:
        """Non-interactive Tool Lock install. Requires yes=True unless dry_run."""
        argv = ["install", "--json"]
        if all_core:
            argv.append("--all-core")
        else:
            ts = _as_str_list(targets)
            if not ts:
                return CliResult(
                    ok=False,
                    exit_code=2,
                    command=[],
                    stderr="install requires targets=[...] or all_core=True",
                    error="usage",
                )
            argv.extend(["--targets", ",".join(ts)])
        if dry_run:
            argv.append("--dry-run")
        elif yes:
            argv.append("--yes")
        else:
            return CliResult(
                ok=False,
                exit_code=2,
                command=[],
                stderr="install is non-interactive: pass yes=True or dry_run=True",
                error="usage",
            )
        if with_runtime:
            argv.append("--with-runtime")
        return self.run(argv)

    def build(
        self,
        source: PathLike,
        *,
        module: str,
        target: str,
        output: Optional[PathLike] = None,
        program: Optional[str] = None,
        profile: Optional[str] = None,
        root: Optional[PathLike] = None,
        timeout: Optional[float] = None,
    ) -> CliResult:
        """Product build. Rejects network/broadcast (use CLI network --broadcast)."""
        if target in DESIGN_ONLY_TARGETS:
            return CliResult(
                ok=False,
                exit_code=2,
                command=[],
                stderr=(
                    f"target '{target}' is design-only (unsupported; not installable/buildable "
                    "via product surface)"
                ),
                error="usage",
            )
        argv = [
            "build",
            str(source),
            "--module",
            str(module),
            "--target",
            str(target),
            "--json",
        ]
        if output is not None:
            argv.extend(["-o", str(output)])
        if program is not None:
            argv.extend(["--program", str(program)])
        if profile is not None:
            argv.extend(["--profile", str(profile)])
        if root is not None:
            argv.extend(["--root", str(root)])
        return self.run(argv, timeout=timeout)

    def check(
        self,
        source: PathLike,
        *,
        module: str,
        program: Optional[str] = None,
        root: Optional[PathLike] = None,
    ) -> CliResult:
        argv = ["check", str(source), "--module", str(module), "--json"]
        if program is not None:
            argv.extend(["--program", str(program)])
        if root is not None:
            argv.extend(["--root", str(root)])
        return self.run(argv)

    def inspect_artifacts(self, output_dir: PathLike) -> CliResult:
        """Revalidate on-disk output via product ``inspect --output-dir``."""
        return self.run(
            ["inspect", "--output-dir", str(output_dir), "--json"]
        )

    def inspect_target(self, target: str) -> CliResult:
        return self.run(["inspect", str(target), "--json"])

    def local(
        self,
        *,
        target: str,
        mode: Optional[str] = None,
        script_args: Optional[Sequence[str]] = None,
        source: Optional[PathLike] = None,
        module: Optional[str] = None,
        root: Optional[PathLike] = None,
        runs: Optional[Sequence[str]] = None,
        golden: Optional[PathLike] = None,
        skip_run: bool = False,
        profile: Optional[str] = None,
        program: Optional[str] = None,
        output_dir: Optional[PathLike] = None,
        timeout: Optional[float] = None,
    ) -> CliResult:
        """Product ``local`` wrapper (host-heavy package scripts).

        For Aleo sandbox, pass ``source`` + ``module`` (generic; no default
        program). Optional ``runs`` become ``--run`` lines; ``skip_run`` skips
        leo run. Never accepts network broadcast or raw private keys.
        """
        if target in DESIGN_ONLY_TARGETS:
            return CliResult(
                ok=False,
                exit_code=2,
                command=[],
                stderr=f"target '{target}' is design-only (unsupported for local)",
                error="usage",
            )
        forbidden = []
        for a in script_args or []:
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
                forbidden.append(s)
        if forbidden:
            return CliResult(
                ok=False,
                exit_code=2,
                command=[],
                stderr=(
                    "local SDK rejects signer/broadcast args; use product CLI "
                    "network --broadcast explicitly outside the SDK"
                ),
                error="usage",
            )
        argv: List[str] = ["local", "--target", str(target), "--json"]
        if mode:
            argv.extend(["--mode", str(mode)])
        tail: List[str] = []
        if script_args:
            tail.extend(str(x) for x in script_args)
        if source is not None:
            tail.extend(["--source", str(source)])
        if module is not None:
            tail.extend(["--module", str(module)])
        if root is not None:
            tail.extend(["--root", str(root)])
        if program is not None:
            tail.extend(["--program", str(program)])
        if profile is not None:
            tail.extend(["--profile", str(profile)])
        if golden is not None:
            tail.extend(["--golden", str(golden)])
        if output_dir is not None:
            tail.extend(["--output-dir", str(output_dir)])
        if skip_run:
            tail.append("--skip-run")
        for r in runs or []:
            tail.extend(["--run", str(r)])
        if tail:
            argv.append("--")
            argv.extend(tail)
        return self.run(argv, timeout=timeout)

    def load_output_manifest(self, output_dir: PathLike) -> Dict[str, Any]:
        """Parse engineering ``proof-forge.output.v1`` without re-running inspect."""
        return load_output_manifest(output_dir)

    def chain_catalog(
        self,
        *,
        target: Optional[str] = None,
        include_design_only: bool = False,
    ) -> CliResult:
        """Static multi-chain client/frontend metadata (not product CLI spawn)."""
        try:
            data = load_chain_client_catalog(
                self.root,
                target=target,
                include_design_only=include_design_only,
            )
        except (OSError, ValueError, KeyError, json.JSONDecodeError) as e:
            return CliResult(
                ok=False,
                exit_code=2,
                command=["chain-catalog"],
                stderr=str(e),
                error="usage",
            )
        return CliResult(
            ok=True,
            exit_code=0,
            command=["chain-catalog"],
            stdout=json.dumps(data, ensure_ascii=False, separators=(",", ":")),
            parsed=data,
            product_ok=True,
        )

    def network_catalog(
        self,
        *,
        network_id: Optional[str] = None,
        target_family: Optional[str] = None,
        env: Optional[str] = None,
        chain_id: Optional[int] = None,
    ) -> CliResult:
        """Static network catalog (X Layer, Anvil, …). Metadata only."""
        try:
            data = load_network_catalog(
                self.root,
                network_id=network_id,
                target_family=target_family,
                env=env,
                chain_id=chain_id,
            )
        except (OSError, ValueError, KeyError, json.JSONDecodeError) as e:
            return CliResult(
                ok=False,
                exit_code=2,
                command=["network-catalog"],
                stderr=str(e),
                error="usage",
            )
        return CliResult(
            ok=True,
            exit_code=0,
            command=["network-catalog"],
            stdout=json.dumps(data, ensure_ascii=False, separators=(",", ":")),
            parsed=data,
            product_ok=True,
        )


# ---------------------------------------------------------------------------
# Self-check / CLI entry
# ---------------------------------------------------------------------------


def self_check(*, root: Optional[PathLike] = None) -> Dict[str, Any]:
    """Lightweight identity + import self-check (no host-heavy tools)."""
    repo = find_repo_root(root)
    report: Dict[str, Any] = {
        "ok": True,
        "schema": "proof-forge.sdk.self-check.v1",
        "root": str(repo),
        "module": str(Path(__file__).resolve()),
        "implementedTargets": list(IMPLEMENTED_TARGETS),
        "designOnlyTargets": list(DESIGN_ONLY_TARGETS),
        "methods": [
            "list_targets",
            "doctor",
            "install",
            "build",
            "check",
            "inspect_artifacts",
            "inspect_target",
            "local",
            "load_output_manifest",
            "chain_catalog",
            "network_catalog",
        ],
        "notes": [
            "SDK only spawns product CLI / package engines",
            "no PATH fallback into PROOF_FORGE_TOOL_ROOT",
            "not formal/hermetic/mainnet/deployable rewrite",
            "local is generic (Aleo: --source/--module/--run; no default program)",
            "no default network broadcast helper",
            "chain_catalog is static metadata (frontend/client names; not shipped SDKs)",
            "network_catalog is static metadata (X Layer/Anvil; not deploy authority)",
        ],
    }
    try:
        cli = find_cli(repo)
        report["cli"] = str(cli)
        report["cliPresent"] = True
    except FileNotFoundError as e:
        report["cli"] = None
        report["cliPresent"] = False
        report["cliError"] = str(e)
        # Self-check of the library can pass without built binary; smoke scripts require it.
        report["ok"] = True
        report["soft"] = "cli-missing"
    # Doctor engine must exist for product surface.
    if not (repo / "scripts" / "proof_forge_doctor.py").is_file():
        report["ok"] = False
        report["error"] = "missing proof_forge_doctor.py"
    return report


def _main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="ProofForge SDK-V0 thin client (spawn product CLI JSON)"
    )
    parser.add_argument(
        "--self-check",
        action="store_true",
        help="emit proof-forge.sdk.self-check.v1 JSON and exit",
    )
    parser.add_argument(
        "--root",
        dest="package_root",
        default=None,
        help="package root (default: PROOF_FORGE_ROOT or discovery)",
    )
    sub = parser.add_subparsers(dest="cmd")

    p_list = sub.add_parser("list-targets", help="list-targets --json")
    p_list.add_argument("--all", action="store_true")

    p_doc = sub.add_parser("doctor", help="doctor --json")
    p_doc.add_argument("--target", action="append", default=[])
    p_doc.add_argument("--with-runtime", action="store_true")
    p_doc.add_argument("--all", action="store_true")

    p_ins = sub.add_parser("install", help="install --json")
    p_ins.add_argument("--targets", default=None)
    p_ins.add_argument("--all-core", action="store_true")
    p_ins.add_argument("--with-runtime", action="store_true")
    p_ins.add_argument("--dry-run", action="store_true")

    p_man = sub.add_parser(
        "load-manifest", help="parse on-disk proof-forge.output.v1 manifest.json"
    )
    p_man.add_argument("output_dir")

    p_loc = sub.add_parser(
        "local",
        help="product local (Aleo sandbox: --source/--module; no broadcast)",
    )
    p_loc.add_argument("--target", required=True)
    p_loc.add_argument("--mode", default=None)
    p_loc.add_argument("--source", default=None)
    p_loc.add_argument("--module", default=None)
    p_loc.add_argument(
        "--root",
        dest="local_root",
        default=None,
        help="external project root to pass through to product local --root",
    )
    p_loc.add_argument("--program", default=None)
    p_loc.add_argument("--profile", default=None)
    p_loc.add_argument("--golden", default=None)
    p_loc.add_argument("--run", action="append", default=[], dest="runs")
    p_loc.add_argument("--skip-run", action="store_true")
    p_loc.add_argument("--output-dir", default=None)

    p_cat = sub.add_parser(
        "chain-catalog",
        help="static chain client/frontend catalog JSON (metadata only)",
    )
    p_cat.add_argument("--target", default=None)
    p_cat.add_argument("--all", action="store_true", help="include design-only rows")

    p_net = sub.add_parser(
        "network-catalog",
        help="static network catalog JSON (X Layer / Anvil; metadata only)",
    )
    p_net.add_argument("--id", dest="network_id", default=None)
    p_net.add_argument("--target-family", default=None)
    p_net.add_argument("--env", default=None)
    p_net.add_argument("--chain-id", type=int, default=None)

    args = parser.parse_args(list(argv) if argv is not None else None)

    if args.self_check or args.cmd is None:
        report = self_check(root=args.package_root)
        print(json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False))
        return 0 if report.get("ok") else 1

    client = ProofForgeClient(root=args.package_root)
    if args.cmd == "list-targets":
        r = client.list_targets(include_all=bool(args.all))
    elif args.cmd == "doctor":
        r = client.doctor(
            targets=args.target or None,
            with_runtime=bool(args.with_runtime),
            include_all=bool(args.all),
        )
    elif args.cmd == "install":
        r = client.install(
            targets=_as_str_list(args.targets) or None,
            all_core=bool(args.all_core),
            with_runtime=bool(args.with_runtime),
            dry_run=bool(args.dry_run),
        )
    elif args.cmd == "local":
        r = client.local(
            target=str(args.target),
            mode=args.mode,
            source=args.source,
            module=args.module,
            root=args.local_root,
            program=args.program,
            profile=args.profile,
            golden=args.golden,
            runs=args.runs or None,
            skip_run=bool(args.skip_run),
            output_dir=args.output_dir,
        )
    elif args.cmd == "chain-catalog":
        r = client.chain_catalog(
            target=args.target,
            include_design_only=bool(args.all),
        )
    elif args.cmd == "network-catalog":
        r = client.network_catalog(
            network_id=args.network_id,
            target_family=args.target_family,
            env=args.env,
            chain_id=args.chain_id,
        )
    elif args.cmd == "load-manifest":
        try:
            data = client.load_output_manifest(args.output_dir)
        except (OSError, ValueError, json.JSONDecodeError) as e:
            print(json.dumps({"ok": False, "error": str(e)}, indent=2), file=sys.stderr)
            return 1
        print(json.dumps(data, indent=2, ensure_ascii=False))
        return 0
    else:
        parser.error(f"unknown command {args.cmd!r}")
        return 2

    print(json.dumps(r.to_dict(), indent=2, ensure_ascii=False, sort_keys=True))
    # doctor with body: exit 0 for agent usability when parsed
    if r.parsed is not None and r.exit_code in (0, 3) and args.cmd == "doctor":
        return 0
    return 0 if r.ok else (r.exit_code if isinstance(r.exit_code, int) else 1)


if __name__ == "__main__":
    raise SystemExit(_main())

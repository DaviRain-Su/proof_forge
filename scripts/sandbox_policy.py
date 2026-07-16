#!/usr/bin/env python3
"""Render fail-closed macOS sandbox-exec policies for the V2 clean room.

The renderer is deliberately standard-library only.  Invoke it with the
host-profile-pinned direct Xcode Python using ``-I -S``.  It accepts only
canonical, absolute, symlink-free paths and publishes a complete policy with
an atomic, no-clobber link in the caller's private temporary root.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import secrets
import stat
import sys
import tempfile
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn, Sequence


MAX_PATH_BYTES = 4096
MAX_POLICY_BYTES = 128 * 1024
STAGES = ("materialize", "core", "evm-runtime")
SYSCTL_RULE = '(allow sysctl-read (sysctl-name "hw.ncpu" "hw.pagesize_compat"))'
TEMPLATE_SHA256 = {
    "materialize": "9da5844481b09ebc6b1127ba2ed6ca56f398caf579866ce62950377f7536aec9",
    "core": "31b3aef326cf6bbe6438a49cdafc96cc6c5ae65e466ee04d79787f255a06aa72",
    "evm-runtime": "a0c07d1792ed2d52220b78deebef17447d8d21ec3f583be0c4aafa1af06b7333",
}

SYSTEM_READ_DIRS = (
    "/System",
    "/usr/bin",
    "/usr/lib",
    "/usr/libexec",
    "/bin",
    "/sbin",
    "/Library/Apple",
    "/private/var/db/timezone",
)
DEVICE_FILES = (
    "/dev/null",
    "/dev/random",
    "/dev/urandom",
    "/dev/zero",
    "/dev/stdin",
    "/dev/stdout",
    "/dev/stderr",
)
DEVICE_DIRS: tuple[str, ...] = ()

PLACEHOLDER_RE = re.compile(r"@@[A-Z][A-Z0-9_]*@@")
ALLOW_DEFAULT_RE = re.compile(r"\(\s*allow\s+default\b")
BARE_PROCESS_EXEC_RE = re.compile(r"\(\s*allow\s+process-exec\s*\)")
PROCESS_EXEC_ALLOW_RE = re.compile(r"\(\s*allow\s+process-exec\b")
PROCESS_STAR_RE = re.compile(r"\(\s*allow\s+process(?:-exec)?\s*\*")
PROCESS_INFO_STAR_RE = re.compile(r"\bprocess-info\s*\*")
NETWORK_STAR_RE = re.compile(r"\bnetwork\s*\*")


class PolicyError(RuntimeError):
    """Stable fail-closed policy-rendering rejection."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def fail(code: str, message: str) -> NoReturn:
    raise PolicyError(code, message)


def require_isolated_python() -> None:
    if not sys.flags.isolated or not sys.flags.no_site:
        fail(
            "PF-SANDBOX-PYTHON",
            "run sandbox-policy with the pinned direct Xcode Python using -I -S",
        )


def diagnostic(value: str, limit: int = 120) -> str:
    rendered = ascii(value)
    return rendered if len(rendered) <= limit else rendered[: limit - 3] + "..."


def require_safe_path_text(raw: str, label: str) -> None:
    if not raw or len(raw.encode("utf-8")) > MAX_PATH_BYTES:
        fail("PF-SANDBOX-PATH", f"{label} must be 1..{MAX_PATH_BYTES} UTF-8 bytes")
    if unicodedata.normalize("NFC", raw) != raw:
        fail("PF-SANDBOX-PATH", f"{label} must use Unicode NFC")
    if any(ord(char) < 0x20 or ord(char) == 0x7F for char in raw):
        fail("PF-SANDBOX-PATH", f"{label} contains an ASCII control character")
    if any(char in raw for char in ('"', "\\", "(", ")", ";")):
        fail(
            "PF-SANDBOX-PATH",
            f"{label} contains an SBPL metacharacter: {diagnostic(raw)}",
        )


def iter_path_prefixes(path: Path) -> list[Path]:
    prefixes: list[Path] = []
    current = path
    while True:
        prefixes.append(current)
        if current.parent == current:
            break
        current = current.parent
    prefixes.reverse()
    return prefixes


def reject_symlink_components(path: Path, label: str, *, allow_missing_leaf: bool) -> None:
    prefixes = iter_path_prefixes(path)
    missing_seen = False
    for index, prefix in enumerate(prefixes):
        try:
            metadata = os.lstat(prefix)
        except FileNotFoundError:
            missing_seen = True
            if not allow_missing_leaf or index != len(prefixes) - 1:
                fail("PF-SANDBOX-PATH", f"{label} does not exist: {diagnostic(str(prefix))}")
            continue
        except OSError as error:
            fail(
                "PF-SANDBOX-PATH",
                f"cannot inspect {label} component {diagnostic(str(prefix))}: {error.strerror}",
            )
        if missing_seen:
            fail("PF-SANDBOX-PATH", f"{label} has a missing non-leaf component")
        if stat.S_ISLNK(metadata.st_mode):
            fail(
                "PF-SANDBOX-SYMLINK",
                f"{label} contains a symbolic-link component: {diagnostic(str(prefix))}",
            )


def canonical_path(
    raw: str,
    label: str,
    *,
    kind: str,
    allow_missing_leaf: bool = False,
) -> Path:
    require_safe_path_text(raw, label)
    path = Path(raw)
    if not path.is_absolute() or os.path.normpath(raw) != raw:
        fail("PF-SANDBOX-PATH", f"{label} must be an absolute normalized path")
    reject_symlink_components(path, label, allow_missing_leaf=allow_missing_leaf)
    resolved = Path(os.path.realpath(raw))
    if resolved != path:
        fail(
            "PF-SANDBOX-PATH",
            f"{label} must already be canonical: {diagnostic(raw)} -> {diagnostic(str(resolved))}",
        )
    if allow_missing_leaf and not path.exists():
        parent = path.parent
        if not parent.is_dir():
            fail("PF-SANDBOX-PATH", f"{label} parent must be an existing directory")
        return path
    try:
        metadata = os.stat(path, follow_symlinks=False)
    except OSError as error:
        fail("PF-SANDBOX-PATH", f"cannot stat {label}: {error.strerror}")
    if kind == "dir" and not stat.S_ISDIR(metadata.st_mode):
        fail("PF-SANDBOX-PATH", f"{label} must be a directory")
    if kind == "file" and not stat.S_ISREG(metadata.st_mode):
        fail("PF-SANDBOX-PATH", f"{label} must be a regular file")
    if kind == "file" and metadata.st_nlink != 1:
        fail("PF-SANDBOX-PATH", f"{label} must have exactly one hard link")
    return path


def require_private_temp_root(path: Path) -> None:
    metadata = os.stat(path, follow_symlinks=False)
    if metadata.st_uid != os.getuid():
        fail("PF-SANDBOX-TEMP", "TEMP_ROOT must be owned by the current user")
    if stat.S_IMODE(metadata.st_mode) != 0o700:
        fail("PF-SANDBOX-TEMP", "TEMP_ROOT must have mode 0700")


def require_owned_directory(path: Path, label: str, *, private: bool = False) -> None:
    metadata = os.stat(path, follow_symlinks=False)
    if metadata.st_uid != os.getuid():
        fail("PF-SANDBOX-LAYOUT", f"{label} must be owned by the current user")
    mode = stat.S_IMODE(metadata.st_mode)
    if mode & 0o022:
        fail("PF-SANDBOX-LAYOUT", f"{label} must not be group/other writable")
    if private and mode != 0o700:
        fail("PF-SANDBOX-LAYOUT", f"{label} must have mode 0700")


def require_fixed_path(path: Path, expected: Path, label: str) -> None:
    if path != expected:
        fail(
            "PF-SANDBOX-LAYOUT",
            f"{label} must use the fixed clean-room path {diagnostic(str(expected))}",
        )


def derive_xcode_roots(python: Path) -> tuple[Path, Path, Path, Path, Path, Path]:
    app_candidates = [parent for parent in python.parents if parent.name.endswith(".app")]
    if len(app_candidates) != 1:
        fail("PF-SANDBOX-XCODE", "XCODE_PYTHON must be inside exactly one .app bundle")
    app_root = app_candidates[0]
    developer_root = app_root / "Contents" / "Developer"
    try:
        python.relative_to(developer_root)
    except ValueError:
        fail("PF-SANDBOX-XCODE", "XCODE_PYTHON must be below <Xcode>.app/Contents/Developer")
    if not developer_root.is_dir():
        fail("PF-SANDBOX-XCODE", "derived Xcode Developer root is missing")
    git = canonical_path(
        str(developer_root / "usr" / "bin" / "git"),
        "direct Xcode Git",
        kind="file",
    )
    otool = canonical_path(
        str(
            developer_root
            / "Toolchains"
            / "XcodeDefault.xctoolchain"
            / "usr"
            / "bin"
            / "llvm-otool"
        ),
        "direct Xcode otool",
        kind="file",
    )
    otool_classic = canonical_path(
        str(otool.parent / "otool-classic"),
        "direct Xcode otool-classic",
        kind="file",
    )
    if not all(os.access(path, os.X_OK) for path in (git, otool, otool_classic)):
        fail("PF-SANDBOX-XCODE", "derived direct Xcode tools must be executable")
    python_runtime = python.parent.parent / "Resources" / "Python.app"
    runtime_executable = python_runtime / "Contents" / "MacOS" / "Python"
    canonical_path(str(runtime_executable), "XCODE_PYTHON runtime", kind="file")
    return app_root, developer_root, git, otool, otool_classic, python_runtime


def sbpl_string(value: Path | str) -> str:
    text = str(value)
    require_safe_path_text(text, "SBPL string")
    return text.replace("\\", "\\\\").replace('"', '\\"')


def path_filters(
    directories: Sequence[Path | str], files: Sequence[Path | str] = ()
) -> str:
    filters: set[tuple[str, str]] = set()
    for raw in directories:
        path = Path(raw)
        filters.add(("literal", str(path)))
        filters.add(("subpath", str(path)))
    for raw in files:
        filters.add(("literal", str(Path(raw))))
    ordered = sorted(filters, key=lambda item: (item[1], 0 if item[0] == "literal" else 1))
    return "\n".join(f'  ({kind} "{sbpl_string(path)}")' for kind, path in ordered)


def metadata_filters(
    directories: Sequence[Path | str], files: Sequence[Path | str]
) -> str:
    filters: set[tuple[str, str]] = set()
    for raw in directories:
        path = Path(raw)
        for prefix in iter_path_prefixes(path):
            filters.add(("literal", str(prefix)))
        filters.add(("subpath", str(path)))
    for raw in files:
        path = Path(raw)
        for prefix in iter_path_prefixes(path):
            filters.add(("literal", str(prefix)))
    ordered = sorted(filters, key=lambda item: (item[1], 0 if item[0] == "literal" else 1))
    return "\n".join(f'  ({kind} "{sbpl_string(path)}")' for kind, path in ordered)


@dataclass(frozen=True)
class RenderInputs:
    stage: str
    temp_root: Path
    asset_cache: Path
    asset_index: Path
    xcode_python: Path
    xcode_app: Path
    xcode_developer: Path
    xcode_git: Path
    xcode_otool: Path
    xcode_otool_classic: Path
    xcode_python_runtime: Path
    tool_root: Path
    lean_root: Path
    external_root: Path
    source_root: Path
    source_lake_root: Path
    home_root: Path
    cache_root: Path
    artifact_output_root: Path
    work_root: Path
    policies_root: Path
    runner: Path
    port: int | None
    output: Path


def validate_inputs(args: argparse.Namespace) -> RenderInputs:
    stage = args.stage
    temp_root = canonical_path(args.temp_root, "TEMP_ROOT", kind="dir")
    require_private_temp_root(temp_root)
    asset_cache = canonical_path(args.asset_cache, "ASSET_CACHE", kind="dir")
    if (
        asset_cache == temp_root
        or asset_cache in temp_root.parents
        or temp_root in asset_cache.parents
    ):
        fail("PF-SANDBOX-LAYOUT", "ASSET_CACHE must be disjoint from TEMP_ROOT")
    require_owned_directory(asset_cache, "ASSET_CACHE")
    asset_index = canonical_path(
        str(asset_cache / "sha256"),
        "ASSET_CACHE/sha256",
        kind="dir",
    )
    require_owned_directory(asset_index, "ASSET_CACHE/sha256")
    xcode_python = canonical_path(args.xcode_python, "XCODE_PYTHON", kind="file")
    if not os.access(xcode_python, os.X_OK):
        fail("PF-SANDBOX-XCODE", "XCODE_PYTHON must be executable")
    (
        xcode_app,
        xcode_developer,
        xcode_git,
        xcode_otool,
        xcode_otool_classic,
        xcode_python_runtime,
    ) = derive_xcode_roots(xcode_python)

    tool_root = canonical_path(str(temp_root / "tools"), "tool root", kind="dir")
    require_owned_directory(tool_root, "tool root", private=True)
    allow_missing_tools = stage == "materialize"
    lean_root = canonical_path(
        args.lean_root,
        "LEAN_ROOT",
        kind="dir",
        allow_missing_leaf=allow_missing_tools,
    )
    require_fixed_path(lean_root, tool_root / "lean", "LEAN_ROOT")
    external_root = canonical_path(
        args.external_root,
        "EXTERNAL_ROOT",
        kind="dir",
        allow_missing_leaf=allow_missing_tools,
    )
    require_fixed_path(external_root, tool_root / "external", "EXTERNAL_ROOT")
    source_root = canonical_path(args.source_root, "SOURCE_ROOT", kind="dir")
    require_fixed_path(source_root, temp_root / "source", "SOURCE_ROOT")
    require_owned_directory(source_root, "SOURCE_ROOT")
    source_lake_root = canonical_path(
        str(source_root / ".lake"),
        "SOURCE_ROOT/.lake",
        kind="dir",
        allow_missing_leaf=True,
    )

    fixed_directories = {
        "HOME root": temp_root / "home",
        "cache root": temp_root / "cache",
        "artifact output root": temp_root / "output",
        "work root": temp_root / "work",
        "policies root": temp_root / "policies",
    }
    validated_directories: dict[str, Path] = {}
    for label, expected in fixed_directories.items():
        path = canonical_path(str(expected), label, kind="dir")
        require_owned_directory(path, label, private=True)
        validated_directories[label] = path
    home_root = validated_directories["HOME root"]
    cache_root = validated_directories["cache root"]
    artifact_output_root = validated_directories["artifact output root"]
    work_root = validated_directories["work root"]
    policies_root = validated_directories["policies root"]

    runner = canonical_path(
        str(temp_root / "clean-room-runner.sh"),
        "clean-room runner",
        kind="file",
    )
    runner_metadata = os.stat(runner, follow_symlinks=False)
    if runner_metadata.st_uid != os.getuid() or stat.S_IMODE(runner_metadata.st_mode) != 0o500:
        fail(
            "PF-SANDBOX-LAYOUT",
            "clean-room runner must be current-user-owned with mode 0500",
        )

    output = canonical_path(args.output, "output", kind="file", allow_missing_leaf=True)
    expected_output = policies_root / f"{stage}.sb"
    if output != expected_output:
        fail(
            "PF-SANDBOX-LAYOUT",
            f"policy output must be {diagnostic(str(expected_output))}",
        )
    if output.exists() or output.is_symlink():
        fail("PF-SANDBOX-NOCLOBBER", f"output already exists: {diagnostic(str(output))}")

    port = args.port
    if stage == "evm-runtime":
        if type(port) is not int or not 1 <= port <= 65535:
            fail("PF-SANDBOX-PORT", "evm-runtime requires a local port in [1, 65535]")
    elif port is not None:
        fail("PF-SANDBOX-PORT", f"{stage} must not receive a network port")

    return RenderInputs(
        stage=stage,
        temp_root=temp_root,
        asset_cache=asset_cache,
        asset_index=asset_index,
        xcode_python=xcode_python,
        xcode_app=xcode_app,
        xcode_developer=xcode_developer,
        xcode_git=xcode_git,
        xcode_otool=xcode_otool,
        xcode_otool_classic=xcode_otool_classic,
        xcode_python_runtime=xcode_python_runtime,
        tool_root=tool_root,
        lean_root=lean_root,
        external_root=external_root,
        source_root=source_root,
        source_lake_root=source_lake_root,
        home_root=home_root,
        cache_root=cache_root,
        artifact_output_root=artifact_output_root,
        work_root=work_root,
        policies_root=policies_root,
        runner=runner,
        port=port,
        output=output,
    )


def executable_filters(inputs: RenderInputs) -> str:
    if inputs.stage == "materialize":
        directories: tuple[Path | str, ...] = (
            # Materializers execute verified tools from randomized staging
            # directories immediately below the fixed tools root.
            inputs.tool_root,
            inputs.xcode_python_runtime,
        )
        files: tuple[Path | str, ...] = (
            "/usr/bin/env",
            inputs.xcode_python,
            inputs.xcode_otool,
            inputs.xcode_otool_classic,
        )
    elif inputs.stage == "core":
        directories = (
            inputs.lean_root,
            inputs.external_root,
            inputs.source_root / ".lake" / "build" / "bin",
            inputs.xcode_python_runtime,
        )
        files = (
            "/usr/bin/env",
            "/usr/bin/stat",
            "/bin/bash",
            "/bin/mkdir",
            "/bin/sleep",
            "/usr/bin/tr",
            inputs.xcode_python,
            inputs.xcode_git,
        )
    else:
        directories = (inputs.external_root, inputs.xcode_python_runtime)
        files = (
            "/usr/bin/env",
            "/bin/bash",
            "/bin/sleep",
            "/usr/bin/tr",
            inputs.xcode_python,
        )
    return path_filters(directories, files)


def stage_read_paths(
    inputs: RenderInputs,
) -> tuple[tuple[Path | str, ...], tuple[Path | str, ...]]:
    common = tuple(Path(path) for path in SYSTEM_READ_DIRS) + (inputs.xcode_app,)
    common_files = (
        Path("/"),
        inputs.temp_root,
        inputs.tool_root,
    ) + tuple(Path(path) for path in DEVICE_FILES)
    if inputs.stage == "materialize":
        directories = common + (
            inputs.asset_index,
            inputs.source_root,
            inputs.tool_root,
            inputs.home_root,
            inputs.work_root,
        )
        files = common_files + (inputs.asset_cache,)
    elif inputs.stage == "core":
        directories = common + (
            inputs.source_root,
            inputs.lean_root,
            inputs.external_root,
            inputs.home_root,
            inputs.cache_root,
            inputs.artifact_output_root,
            inputs.work_root,
        )
        files = common_files + (inputs.runner,)
    else:
        directories = common + (
            inputs.external_root,
            inputs.home_root,
            inputs.cache_root,
            inputs.artifact_output_root,
            inputs.work_root,
        )
        files = common_files + (inputs.runner,)
    # sandbox-exec on current macOS needs read-data permission for the root
    # directory entry before resolving otherwise allowlisted executable roots.
    # Keep root/TEMP_ROOT/tool-root as literal filters; a root subpath would
    # defeat deny-default and a TEMP_ROOT subpath would expose the candidate.
    return directories, files


def stage_write_paths(inputs: RenderInputs) -> tuple[Path | str, ...]:
    if inputs.stage == "materialize":
        return (inputs.tool_root, inputs.home_root, inputs.work_root)
    common: tuple[Path | str, ...] = (
        inputs.home_root,
        inputs.cache_root,
        inputs.work_root,
    )
    if inputs.stage == "core":
        return (
            inputs.source_lake_root,
            inputs.artifact_output_root,
        ) + common
    return common


def map_executable_paths(inputs: RenderInputs) -> tuple[Path | str, ...]:
    common: tuple[Path | str, ...] = (
        "/System",
        "/usr/bin",
        "/usr/lib",
        "/usr/libexec",
        "/bin",
        "/sbin",
        "/Library/Apple",
        inputs.xcode_app,
    )
    if inputs.stage == "materialize":
        return common + (inputs.tool_root,)
    if inputs.stage == "core":
        return common + (
            inputs.lean_root,
            inputs.external_root,
            inputs.source_root / ".lake" / "build" / "bin",
        )
    return common + (inputs.external_root,)


def validate_template_bytes(stage: str, data: bytes) -> None:
    expected = TEMPLATE_SHA256.get(stage)
    if expected is None or hashlib.sha256(data).hexdigest() != expected:
        fail("PF-SANDBOX-TEMPLATE", f"{stage} template does not match its locked SHA-256")
    if len(data) > MAX_POLICY_BYTES:
        fail("PF-SANDBOX-TEMPLATE", f"{stage} template exceeds {MAX_POLICY_BYTES} bytes")


def load_template(stage: str) -> str:
    repository_root = Path(__file__).resolve().parent.parent
    template_path = repository_root / "sandbox" / f"{stage}.sb.in"
    reject_symlink_components(template_path, "sandbox template", allow_missing_leaf=False)
    try:
        data = template_path.read_bytes()
    except OSError as error:
        fail("PF-SANDBOX-TEMPLATE", f"cannot read {stage} template: {error.strerror}")
    validate_template_bytes(stage, data)
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        fail("PF-SANDBOX-TEMPLATE", f"{stage} template must be UTF-8")


def replace_placeholders(template: str, replacements: dict[str, str]) -> str:
    expected = set(PLACEHOLDER_RE.findall(template))
    actual = set(replacements)
    missing = expected - actual
    unused = actual - expected
    if missing or unused:
        fail(
            "PF-SANDBOX-TEMPLATE",
            f"template placeholder mismatch missing={sorted(missing)} unused={sorted(unused)}",
        )
    rendered = template
    for placeholder in sorted(replacements):
        expected_count = 2 if placeholder == "@@PORT@@" else 1
        if rendered.count(placeholder) != expected_count:
            fail(
                "PF-SANDBOX-TEMPLATE",
                f"placeholder {placeholder} must occur exactly {expected_count} time(s)",
            )
        rendered = rendered.replace(placeholder, replacements[placeholder])
    if PLACEHOLDER_RE.search(rendered):
        fail("PF-SANDBOX-TEMPLATE", "rendered policy contains an unresolved placeholder")
    return rendered


def validate_policy(policy: str, stage: str, port: int | None) -> None:
    if policy.count("(version 1)") != 1 or policy.count("(deny default)") != 1:
        fail("PF-SANDBOX-POLICY", "policy must contain one version 1 and one deny default")
    if ALLOW_DEFAULT_RE.search(policy) or "(deny network" in policy:
        fail("PF-SANDBOX-POLICY", "policy may not use allow-default or deny-overrides")
    if len(PROCESS_EXEC_ALLOW_RE.findall(policy)) != 1:
        fail("PF-SANDBOX-POLICY", "policy must contain exactly one process-exec allowance")
    if (
        PROCESS_STAR_RE.search(policy)
        or PROCESS_INFO_STAR_RE.search(policy)
        or BARE_PROCESS_EXEC_RE.search(policy)
    ):
        fail("PF-SANDBOX-POLICY", "process execution must use an explicit stage allowlist")
    if NETWORK_STAR_RE.search(policy):
        fail("PF-SANDBOX-NETWORK", "network wildcard operations are forbidden")
    for forbidden in ("mach-lookup", "ipc-posix", "dynamic-code-generation"):
        if forbidden in policy:
            fail("PF-SANDBOX-POLICY", f"policy contains forbidden operation {forbidden}")
    if policy.count("sysctl-read") != 1 or policy.count(SYSCTL_RULE) != 1:
        fail("PF-SANDBOX-POLICY", "policy must use only the locked sysctl allowlist")
    if PLACEHOLDER_RE.search(policy):
        fail("PF-SANDBOX-POLICY", "policy contains an unresolved placeholder")
    if len(policy.encode("utf-8")) > MAX_POLICY_BYTES:
        fail("PF-SANDBOX-POLICY", f"policy exceeds {MAX_POLICY_BYTES} bytes")

    if stage in {"materialize", "core"}:
        if "network-" in policy or "network*" in policy:
            fail("PF-SANDBOX-NETWORK", f"{stage} may not contain any network allowance")
    else:
        if type(port) is not int:
            fail("PF-SANDBOX-PORT", "runtime policy requires an exact local port")
        inbound = f'(allow network-inbound (local ip "localhost:{port}"))'
        outbound = f'(allow network-outbound (remote ip "localhost:{port}"))'
        if policy.count(inbound) != 1 or policy.count(outbound) != 1:
            fail("PF-SANDBOX-NETWORK", "runtime policy must bind both rules to the local port")
        if policy.count("network-") != 2 or "localhost:*" in policy:
            fail("PF-SANDBOX-NETWORK", "runtime policy contains a non-exact network allowance")


def render_policy(inputs: RenderInputs) -> bytes:
    read_directories, read_files = stage_read_paths(inputs)
    write_directories = stage_write_paths(inputs)
    metadata_directories = (
        read_directories
        + write_directories
        + tuple(Path(path) for path in DEVICE_DIRS)
    )
    metadata_files = read_files + tuple(Path(path) for path in DEVICE_FILES)
    template = load_template(inputs.stage)
    replacements = {
        "@@PROCESS_EXEC_FILTERS@@": executable_filters(inputs),
        "@@METADATA_FILTERS@@": metadata_filters(metadata_directories, metadata_files),
        "@@READ_FILTERS@@": path_filters(read_directories, read_files),
        "@@MAP_EXEC_FILTERS@@": path_filters(map_executable_paths(inputs)),
        "@@WRITE_FILTERS@@": path_filters(
            write_directories + tuple(Path(path) for path in DEVICE_DIRS),
            tuple(Path(path) for path in DEVICE_FILES),
        ),
    }
    if inputs.stage == "evm-runtime":
        replacements["@@PORT@@"] = str(inputs.port)
    rendered = replace_placeholders(template, replacements)
    if not rendered.endswith("\n"):
        rendered += "\n"
    validate_policy(rendered, inputs.stage, inputs.port)
    return rendered.encode("utf-8")


def same_inode(left: os.stat_result, right: os.stat_result) -> bool:
    return left.st_dev == right.st_dev and left.st_ino == right.st_ino


def read_open_file(descriptor: int, maximum: int) -> bytes:
    chunks: list[bytes] = []
    remaining = maximum + 1
    while remaining:
        chunk = os.read(descriptor, min(remaining, 128 * 1024))
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def cleanup_link(directory_fd: int, name: str) -> None:
    try:
        os.unlink(name, dir_fd=directory_fd)
    except FileNotFoundError:
        return
    except OSError:
        return
    try:
        os.fsync(directory_fd)
    except OSError:
        pass


def atomic_publish_no_clobber(output: Path, data: bytes) -> None:
    """Publish a policy without clobbering or trusting its staging pathname."""
    parent = output.parent
    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    try:
        directory_fd = os.open(parent, directory_flags)
    except OSError as error:
        fail("PF-SANDBOX-OUTPUT", f"cannot open output parent: {error.strerror}")
    staging_name = f".{output.name}.sandbox-policy-{os.getpid()}-{secrets.token_hex(8)}"
    file_flags = (
        os.O_RDWR
        | os.O_CREAT
        | os.O_EXCL
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    staging_fd: int | None = None
    final_fd: int | None = None
    staging_name_present = False
    linked = False
    published = False
    try:
        try:
            opened_parent = os.fstat(directory_fd)
            path_parent = os.stat(parent, follow_symlinks=False)
            if not stat.S_ISDIR(opened_parent.st_mode) or not same_inode(
                opened_parent, path_parent
            ):
                fail("PF-SANDBOX-OUTPUT", "output parent changed before publication")

            staging_fd = os.open(staging_name, file_flags, 0o600, dir_fd=directory_fd)
            staging_name_present = True
            offset = 0
            while offset < len(data):
                written = os.write(staging_fd, data[offset:])
                if written <= 0:
                    fail("PF-SANDBOX-OUTPUT", "short write while staging policy")
                offset += written
            os.fsync(staging_fd)
            os.fchmod(staging_fd, 0o400)
            os.fsync(staging_fd)
            staged = os.fstat(staging_fd)
            if (
                not stat.S_ISREG(staged.st_mode)
                or staged.st_uid != os.geteuid()
                or staged.st_size != len(data)
                or staged.st_nlink != 1
                or stat.S_IMODE(staged.st_mode) != 0o400
            ):
                fail("PF-SANDBOX-OUTPUT", "staging inode failed its pre-link invariant")

            try:
                os.link(
                    staging_name,
                    output.name,
                    src_dir_fd=directory_fd,
                    dst_dir_fd=directory_fd,
                    follow_symlinks=False,
                )
                linked = True
            except FileExistsError:
                fail(
                    "PF-SANDBOX-NOCLOBBER",
                    f"output already exists: {diagnostic(str(output))}",
                )

            final_fd = os.open(
                output.name,
                os.O_RDONLY
                | getattr(os, "O_CLOEXEC", 0)
                | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=directory_fd,
            )
            staged_linked = os.fstat(staging_fd)
            final_before = os.fstat(final_fd)
            path_before = os.stat(output.name, dir_fd=directory_fd, follow_symlinks=False)
            if (
                not same_inode(staged_linked, final_before)
                or not same_inode(final_before, path_before)
                or not stat.S_ISREG(final_before.st_mode)
                or staged_linked.st_nlink != 2
                or final_before.st_nlink != 2
                or final_before.st_uid != os.geteuid()
                or final_before.st_size != len(data)
                or stat.S_IMODE(final_before.st_mode) != 0o400
            ):
                fail(
                    "PF-SANDBOX-OUTPUT",
                    "published pathname does not identify the open staging inode",
                )

            readback = read_open_file(final_fd, len(data))
            final_after = os.fstat(final_fd)
            path_after = os.stat(output.name, dir_fd=directory_fd, follow_symlinks=False)
            stable = (
                "st_dev",
                "st_ino",
                "st_size",
                "st_nlink",
                "st_mode",
                "st_uid",
                "st_mtime_ns",
                "st_ctime_ns",
            )
            if (
                readback != data
                or any(
                    getattr(final_before, field) != getattr(final_after, field)
                    for field in stable
                )
                or not same_inode(staged_linked, path_after)
                or path_after.st_nlink != 2
            ):
                fail("PF-SANDBOX-OUTPUT", "published policy failed inode/readback checks")
            os.fsync(final_fd)
            os.fsync(directory_fd)

            os.unlink(staging_name, dir_fd=directory_fd)
            staging_name_present = False
            os.fsync(directory_fd)
            staged_final = os.fstat(staging_fd)
            path_final = os.stat(output.name, dir_fd=directory_fd, follow_symlinks=False)
            if (
                not same_inode(staged_final, path_final)
                or staged_final.st_nlink != 1
                or path_final.st_nlink != 1
                or path_final.st_size != len(data)
                or stat.S_IMODE(path_final.st_mode) != 0o400
            ):
                fail("PF-SANDBOX-OUTPUT", "final policy inode changed during publication")
            published = True
        except PolicyError:
            raise
        except OSError as error:
            fail("PF-SANDBOX-OUTPUT", f"atomic policy publication failed: {error.strerror}")
    finally:
        if not published and linked:
            cleanup_link(directory_fd, output.name)
        if final_fd is not None:
            os.close(final_fd)
        if staging_fd is not None:
            os.close(staging_fd)
        if staging_name_present:
            cleanup_link(directory_fd, staging_name)
        os.close(directory_fd)


def render_command(args: argparse.Namespace) -> None:
    inputs = validate_inputs(args)
    policy = render_policy(inputs)
    atomic_publish_no_clobber(inputs.output, policy)
    print(f"sandbox-policy: rendered stage={inputs.stage} output={inputs.output}")


def expect_error(code: str, operation) -> None:  # type: ignore[no-untyped-def]
    try:
        operation()
    except PolicyError as error:
        if error.code != code:
            fail(
                "PF-SANDBOX-SELFTEST",
                f"expected {code}, observed {error.code}: {error}",
            )
        return
    fail("PF-SANDBOX-SELFTEST", f"operation unexpectedly succeeded; expected {code}")


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="proof-forge-sandbox-policy-") as raw_outer:
        outer = Path(raw_outer).resolve(strict=True)
        temp_root = outer / "private"
        asset_cache = outer / "asset-cache"
        source_root = temp_root / "source"
        tool_parent = temp_root / "tools"
        lean_root = tool_parent / "lean"
        external_root = tool_parent / "external"
        home_root = temp_root / "home"
        cache_root = temp_root / "cache"
        artifact_output_root = temp_root / "output"
        work_root = temp_root / "work"
        policy_root = temp_root / "policies"
        runner = temp_root / "clean-room-runner.sh"
        xcode_python = (
            outer
            / "Xcode.app"
            / "Contents"
            / "Developer"
            / "Library"
            / "Frameworks"
            / "Python3.framework"
            / "Versions"
            / "3.9"
            / "bin"
            / "python3.9"
        )
        xcode_git = outer / "Xcode.app" / "Contents" / "Developer" / "usr" / "bin" / "git"
        xcode_otool = (
            outer
            / "Xcode.app"
            / "Contents"
            / "Developer"
            / "Toolchains"
            / "XcodeDefault.xctoolchain"
            / "usr"
            / "bin"
            / "llvm-otool"
        )
        xcode_otool_classic = xcode_otool.parent / "otool-classic"
        xcode_runtime = (
            xcode_python.parent.parent
            / "Resources"
            / "Python.app"
            / "Contents"
            / "MacOS"
            / "Python"
        )
        for directory in (
            temp_root,
            asset_cache,
            asset_cache / "sha256",
            source_root,
            tool_parent,
            lean_root,
            external_root,
            home_root,
            cache_root,
            artifact_output_root,
            work_root,
            policy_root,
            xcode_python.parent,
            xcode_git.parent,
            xcode_otool.parent,
            xcode_runtime.parent,
        ):
            directory.mkdir(parents=True, exist_ok=True)
        for directory in (
            temp_root,
            tool_parent,
            home_root,
            cache_root,
            artifact_output_root,
            work_root,
            policy_root,
        ):
            os.chmod(directory, 0o700)
        runner.write_bytes(b"#!/bin/bash\n")
        os.chmod(runner, 0o500)
        xcode_python.write_bytes(b"python")
        xcode_git.write_bytes(b"git")
        xcode_otool.write_bytes(b"otool")
        xcode_otool_classic.write_bytes(b"otool-classic")
        xcode_runtime.write_bytes(b"python-runtime")
        os.chmod(xcode_python, 0o500)
        os.chmod(xcode_git, 0o500)
        os.chmod(xcode_otool, 0o500)
        os.chmod(xcode_otool_classic, 0o500)
        os.chmod(xcode_runtime, 0o500)

        def namespace(stage: str, output: Path, port: int | None = None) -> argparse.Namespace:
            return argparse.Namespace(
                stage=stage,
                temp_root=str(temp_root),
                asset_cache=str(asset_cache),
                xcode_python=str(xcode_python),
                lean_root=str(lean_root),
                external_root=str(external_root),
                source_root=str(source_root),
                port=port,
                output=str(output),
            )

        rendered: dict[str, bytes] = {}
        for stage, port in (("materialize", None), ("core", None), ("evm-runtime", 43123)):
            policy_output = policy_root / f"{stage}.sb"
            first = validate_inputs(namespace(stage, policy_output, port))
            second = validate_inputs(namespace(stage, policy_output, port))
            expected_write_roots = {
                "materialize": (tool_parent, home_root, work_root),
                "core": (
                    source_root / ".lake",
                    artifact_output_root,
                    home_root,
                    cache_root,
                    work_root,
                ),
                "evm-runtime": (home_root, cache_root, work_root),
            }
            if stage_write_paths(first) != expected_write_roots[stage]:
                fail("PF-SANDBOX-SELFTEST", f"{stage} write roots changed")
            first_bytes = render_policy(first)
            second_bytes = render_policy(second)
            if first_bytes != second_bytes:
                fail("PF-SANDBOX-SELFTEST", f"{stage} rendering is not deterministic")
            policy_text = first_bytes.decode("utf-8")
            if f'(subpath "{temp_root}")' in policy_text or '(subpath "/")' in policy_text:
                fail("PF-SANDBOX-SELFTEST", f"{stage} rendered an overbroad root filter")
            if "/dev/fd" in policy_text or "process-info" in policy_text:
                fail("PF-SANDBOX-SELFTEST", f"{stage} rendered a forbidden wildcard surface")
            if stage == "materialize":
                if f'(subpath "{asset_cache}")' in policy_text:
                    fail(
                        "PF-SANDBOX-SELFTEST",
                        "materialize rendered an overbroad asset-cache filter",
                    )
                if f'(subpath "{asset_cache / "sha256"}")' not in policy_text:
                    fail(
                        "PF-SANDBOX-SELFTEST",
                        "materialize omitted the locked asset-cache index",
                    )
            rendered[stage] = first_bytes
            atomic_publish_no_clobber(first.output, first_bytes)
            before = first.output.read_bytes()
            expect_error(
                "PF-SANDBOX-NOCLOBBER",
                lambda first=first, data=first_bytes: atomic_publish_no_clobber(first.output, data),
            )
            if first.output.read_bytes() != before:
                fail("PF-SANDBOX-SELFTEST", "no-clobber failure modified the existing policy")

        attack_root = temp_root / "publish-attack"
        attack_root.mkdir()
        attack_output = attack_root / "policy.sb"
        real_link = os.link

        def replace_staging_link(
            source: str,
            destination: str,
            *,
            src_dir_fd: int | None = None,
            dst_dir_fd: int | None = None,
            follow_symlinks: bool = True,
        ) -> None:
            if src_dir_fd is None or dst_dir_fd is None:
                raise RuntimeError("TOCTOU self-test requires dir_fd link semantics")
            os.unlink(source, dir_fd=src_dir_fd)
            attacker = os.open(
                source,
                os.O_WRONLY
                | os.O_CREAT
                | os.O_EXCL
                | getattr(os, "O_CLOEXEC", 0)
                | getattr(os, "O_NOFOLLOW", 0),
                0o600,
                dir_fd=src_dir_fd,
            )
            try:
                os.write(attacker, b"attacker-controlled policy")
                os.fsync(attacker)
            finally:
                os.close(attacker)
            real_link(
                source,
                destination,
                src_dir_fd=src_dir_fd,
                dst_dir_fd=dst_dir_fd,
                follow_symlinks=follow_symlinks,
            )

        os.link = replace_staging_link
        try:
            expect_error(
                "PF-SANDBOX-OUTPUT",
                lambda: atomic_publish_no_clobber(
                    attack_output, rendered["core"]
                ),
            )
        finally:
            os.link = real_link
        if attack_output.exists() or any(attack_root.iterdir()):
            fail(
                "PF-SANDBOX-SELFTEST",
                "staging pathname replacement left a final or staging file",
            )

        relative = namespace("core", policy_root / "relative.sb")
        relative.temp_root = "relative/root"
        expect_error("PF-SANDBOX-PATH", lambda: validate_inputs(relative))

        real_cache = outer / "real-cache"
        real_cache.mkdir()
        linked_cache = outer / "linked-cache"
        linked_cache.symlink_to(real_cache, target_is_directory=True)
        symlinked = namespace("materialize", policy_root / "symlink.sb")
        symlinked.asset_cache = str(linked_cache)
        expect_error("PF-SANDBOX-SYMLINK", lambda: validate_inputs(symlinked))

        escaped = namespace("core", outer / "escaped.sb")
        expect_error("PF-SANDBOX-LAYOUT", lambda: validate_inputs(escaped))

        wrong_policy_name = namespace("core", policy_root / "renamed.sb")
        expect_error("PF-SANDBOX-LAYOUT", lambda: validate_inputs(wrong_policy_name))

        wrong_tools = namespace("materialize", policy_root / "wrong-tools.sb")
        wrong_tools.lean_root = str(tool_parent / "not-lean")
        expect_error("PF-SANDBOX-LAYOUT", lambda: validate_inputs(wrong_tools))

        broad_cache = namespace("core", policy_root / "core.sb")
        broad_cache.asset_cache = "/"
        expect_error("PF-SANDBOX-LAYOUT", lambda: validate_inputs(broad_cache))

        injected = namespace("core", policy_root / "injected.sb")
        injected.source_root = str(source_root) + '\\"; (allow default)'
        expect_error("PF-SANDBOX-PATH", lambda: validate_inputs(injected))

        expect_error(
            "PF-SANDBOX-TEMPLATE",
            lambda: validate_template_bytes("core", b"tampered template"),
        )
        whitespace_allow_default = rendered["core"].decode("utf-8").replace(
            "(deny default)", "(deny default)\n(allow \n default)"
        )
        expect_error(
            "PF-SANDBOX-POLICY",
            lambda: validate_policy(whitespace_allow_default, "core", None),
        )
        expect_error(
            "PF-SANDBOX-POLICY",
            lambda: validate_policy(
                f"(version 1)\n(deny default)\n{SYSCTL_RULE}\n(allow process-exec)\n",
                "core",
                None,
            ),
        )
        duplicate_process_exec = (
            rendered["core"].decode("utf-8")
            + '(allow process-exec (literal "/usr/bin/env"))\n'
        )
        expect_error(
            "PF-SANDBOX-POLICY",
            lambda: validate_policy(duplicate_process_exec, "core", None),
        )
        process_star = rendered["core"].decode("utf-8") + "(allow process *)\n"
        expect_error(
            "PF-SANDBOX-POLICY",
            lambda: validate_policy(process_star, "core", None),
        )
        process_info_star = (
            rendered["core"].decode("utf-8")
            + "(allow process-info* (target self))\n"
        )
        expect_error(
            "PF-SANDBOX-POLICY",
            lambda: validate_policy(process_info_star, "core", None),
        )
        network_star = rendered["evm-runtime"].decode("utf-8") + "(allow network *)\n"
        expect_error(
            "PF-SANDBOX-NETWORK",
            lambda: validate_policy(network_star, "evm-runtime", 43123),
        )
        wildcard_runtime = rendered["evm-runtime"].decode("utf-8").replace(
            "localhost:43123", "localhost:*"
        )
        expect_error(
            "PF-SANDBOX-NETWORK",
            lambda: validate_policy(wildcard_runtime, "evm-runtime", 43123),
        )
        wrong_port = rendered["evm-runtime"].decode("utf-8").replace(
            "localhost:43123", "localhost:43124"
        )
        expect_error(
            "PF-SANDBOX-NETWORK",
            lambda: validate_policy(wrong_port, "evm-runtime", 43123),
        )

    print("sandbox-policy: self-test ok")


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(
        prog="sandbox-policy",
        description="Render fail-closed ProofForge V2 macOS sandbox policies.",
        allow_abbrev=False,
    )
    subcommands = command.add_subparsers(dest="command", required=True)
    render = subcommands.add_parser("render", allow_abbrev=False)
    render.add_argument("stage", choices=STAGES)
    render.add_argument("--temp-root", required=True)
    render.add_argument("--asset-cache", required=True)
    render.add_argument("--xcode-python", required=True)
    render.add_argument("--lean-root", required=True)
    render.add_argument("--external-root", required=True)
    render.add_argument("--source-root", required=True)
    render.add_argument("--port", type=int)
    render.add_argument("-o", "--output", required=True)
    render.set_defaults(handler=render_command)
    test = subcommands.add_parser("self-test", allow_abbrev=False)
    test.set_defaults(handler=lambda _args: self_test())
    return command


def main(argv: Sequence[str] | None = None) -> int:
    try:
        require_isolated_python()
        args = parser().parse_args(argv)
        args.handler(args)
        return 0
    except PolicyError as error:
        print(f"sandbox-policy: {error.code}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

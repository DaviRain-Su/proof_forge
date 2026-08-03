#!/usr/bin/env python3
"""Validate, provision, and safely materialize ProofForge V2 tool assets.

Provisioning is the only networked phase. Materialization consumes the
content-addressed cache and never downloads or searches PATH.
"""

from __future__ import annotations

import argparse
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
import plistlib
import posixpath
import re
import selectors
import secrets
import signal
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.error
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath
from types import ModuleType
from typing import BinaryIO, Iterator


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HOST_LOCK = ROOT / "host-profiles.lock.json"
PLATFORM_LOCK_FILES = {
    "darwin-arm64": "toolchains.lock.json",
    "linux-x86_64": "toolchains-linux-x86_64.lock.json",
    "linux-aarch64": "toolchains-linux-aarch64.lock.json",
}


def host_platform_id() -> str:
    uname = os.uname()
    platform_id = f"{uname.sysname.lower()}-{uname.machine.lower()}"
    if platform_id not in PLATFORM_LOCK_FILES:
        fail(f"unsupported host platform: {platform_id}")
    return platform_id


def default_lock_path() -> Path:
    return ROOT / PLATFORM_LOCK_FILES[host_platform_id()]
SHA256_RE = re.compile(r"[0-9a-f]{64}")
SOURCE_COMMIT_RE = re.compile(r"[0-9a-f]{40}")
SEMVER_RE = re.compile(
    r"(?P<major>0|[1-9][0-9]*)\."
    r"(?P<minor>0|[1-9][0-9]*)\."
    r"(?P<patch>0|[1-9][0-9]*)"
    r"(?:-(?:"
    r"(?:0|[1-9][0-9]*)|"
    r"(?:[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
    r")(?:\.(?:"
    r"(?:0|[1-9][0-9]*)|"
    r"(?:[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
    r"))*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)
SAFE_ASSET_ID_RE = re.compile(r"[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?")
SAFE_IDENTIFIER_RE = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9._-]{0,254}[A-Za-z0-9])?")
FORMATS = {"file", "tar.gz", "zip", "cargo-git"}
DOWNLOAD_FORMATS = {"file", "tar.gz", "zip"}
TOOL_LOCK_SCHEMA_V4 = "proof-forge.toolchains.v4"
CARGO_GIT_BUILD_POLICY_SCHEMA = "proof-forge.cargo-git-build-policy.v1"
CARGO_GIT_BUILD_POLICY_MARKER = ".proof-forge-cargo-git-build-policy"
# Engineering compatibility policy outside Tool Lock v4 identity. The exact
# pinned CosmWasm source uses Wasmer 5.0.6, which references Rust's former
# __rust_probestack symbol and cannot link with Rust 1.89 or newer. Keep this
# exact asset/commit override fail-closed until an honest Tool Lock v5 carries
# per-asset source-build toolchain identity.
CARGO_GIT_RUST_TOOLCHAIN_OVERRIDES = {
    (
        "cosmwasm-check-3.0.9-git-fe5b55d283f5",
        "fe5b55d283f5987c7fa0f95d5ad923be7a3d9283",
    ): "1.88.0",
}
LEGACY_TOOL_LOCK_SCHEMAS = {
    "proof-forge.toolchains.v2",
    "proof-forge.toolchains.v3",
}
MAX_ARCHIVE_MEMBERS = 100_000
MAX_COMPILER_UNPACKED_BYTES = 8 * 1024 * 1024 * 1024
MAX_ZIP_ENTRY_NAME_BYTES = 4096
MAX_ZIP_ENTRY_METADATA_BYTES = 1024 * 1024
MAX_ZIP_TOTAL_METADATA_BYTES = 64 * 1024 * 1024
MAX_OCI_TOKEN_BYTES = 64 * 1024
MAX_HTTPS_REDIRECTS = 5
MAX_HOST_COMMAND_OUTPUT_BYTES = 1024 * 1024
DEFAULT_HOST_COMMAND_TIMEOUT_SECONDS = 15
XCODE_VERIFY_TIMEOUT_SECONDS = 180
FILE_MODE_RE = re.compile(r"0[0-7]{3}")
MACHO_MAGICS = {
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",  # universal 32-bit
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",  # universal 64-bit
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",  # Mach-O 32-bit
    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",  # Mach-O 64-bit
}
RUNTIME_IMAGE_MAGICS = MACHO_MAGICS | {b"\x7fELF"}


class AssetError(RuntimeError):
    """A stable, user-facing asset validation failure."""


class ToolLockClosureError(AssetError):
    """A typed Tool Lock cross-reference or leaf-closure failure."""


def fail_sbom_observation(code: str, message: str) -> "None":
    """Raise the sole coded failure channel for runtime SBOM observation."""

    error = AssetError(f"{code}: {message}")
    error.code = code  # type: ignore[attr-defined]
    raise error from None


def fail(message: str) -> "None":
    raise AssetError(message)


def fail_tool_lock_closure(message: str) -> "None":
    raise ToolLockClosureError(message)


def require_dict(value: object, where: str) -> dict:
    if not isinstance(value, dict):
        fail(f"{where} must be an object")
    return value


def require_list(value: object, where: str) -> list:
    if not isinstance(value, list):
        fail(f"{where} must be an array")
    return value


def require_string(value: object, where: str) -> str:
    if not isinstance(value, str) or not value:
        fail(f"{where} must be a non-empty string")
    return value


def require_semver(value: object, where: str) -> str:
    text = require_string(value, where)
    match = SEMVER_RE.fullmatch(text) if text.isascii() else None
    if match is None:
        fail(f"{where} must be a canonical SemVer 2.0.0 string")
    maximum_u64 = "18446744073709551615"
    for component in ("major", "minor", "patch"):
        digits = match.group(component)
        if (
            len(digits) > len(maximum_u64)
            or (len(digits) == len(maximum_u64) and digits > maximum_u64)
        ):
            fail(f"{where} {component} component exceeds UInt64")
    return text


def require_sha256(value: object, where: str) -> str:
    text = require_string(value, where)
    if SHA256_RE.fullmatch(text) is None:
        fail(f"{where} must be a lowercase SHA-256")
    return text


def require_nullable_string(value: object, where: str) -> str | None:
    if value is None:
        return None
    return require_string(value, where)


def require_keys(value: dict, required: set[str], where: str,
                 optional: set[str] | None = None) -> None:
    optional = optional or set()
    actual = set(value)
    missing = sorted(required - actual)
    unknown = sorted(actual - required - optional)
    if missing:
        fail(f"{where} is missing required fields: {', '.join(missing)}")
    if unknown:
        fail(f"{where} contains unknown fields: {', '.join(unknown)}")


def require_safe_asset_id(value: object, where: str) -> str:
    text = require_string(value, where)
    if SAFE_ASSET_ID_RE.fullmatch(text) is None:
        fail(f"{where} must be a safe lowercase identifier")
    return text


def require_safe_identifier(value: object, where: str) -> str:
    text = require_string(value, where)
    if SAFE_IDENTIFIER_RE.fullmatch(text) is None:
        fail(f"{where} must be a safe identifier")
    return text


def require_string_array(value: object, where: str, *, nonempty: bool = False) -> list[str]:
    records = require_list(value, where)
    if nonempty and not records:
        fail(f"{where} must be non-empty")
    if not all(isinstance(item, str) and item for item in records):
        fail(f"{where} must contain non-empty strings")
    if len(records) != len(set(records)):
        fail(f"{where} contains duplicates")
    if records != sorted(records):
        fail(f"{where} must be sorted")
    return records


def require_https_url(value: object, where: str) -> str:
    text = require_string(value, where)
    parsed = urllib.parse.urlsplit(text)
    if (parsed.scheme.lower() != "https" or not parsed.hostname or
            parsed.username is not None or parsed.password is not None):
        fail(f"{where} must be an HTTPS URL without user information")
    try:
        parsed.port
    except ValueError:
        fail(f"{where} contains an invalid port")
    return text


def require_absolute_file_path(value: object, where: str) -> str:
    text = require_string(value, where)
    if "\x00" in text or "\\" in text or not text.startswith("/"):
        fail(f"{where} must be an absolute POSIX file path")
    if text == "/" or text.endswith("/") or posixpath.normpath(text) != text:
        fail(f"{where} must be a normalized absolute file path")
    return text


def require_absolute_directory_prefix(value: object, where: str) -> str:
    text = require_string(value, where)
    if ("\x00" in text or "\\" in text or not text.startswith("/") or
            not text.endswith("/") or text == "/"):
        fail(f"{where} must be an absolute POSIX directory prefix")
    if posixpath.normpath(text) + "/" != text:
        fail(f"{where} must be a normalized absolute directory prefix")
    return text


def require_normalized_absolute_path(path: Path, where: str) -> Path:
    text = str(path)
    if not path.is_absolute() or "\x00" in text or posixpath.normpath(text) != text:
        fail(f"{where} must be a normalized absolute path")
    return path


def safe_relative(value: object, where: str) -> str:
    text = require_string(value, where)
    if "\x00" in text or "\\" in text:
        fail(f"{where} contains a forbidden character")
    path = PurePosixPath(text)
    if (path.is_absolute() or path.as_posix() != text or
            any(part in {"", ".", ".."} for part in path.parts)):
        fail(f"{where} must be a normalized relative path")
    return text


def unique_sorted(records: list, key: str, where: str) -> None:
    values = [require_string(require_dict(record, f"{where}[]").get(key), f"{where}[].{key}")
              for record in records]
    if len(values) != len(set(values)):
        fail(f"{where} contains duplicate {key}")
    if values != sorted(values):
        fail(f"{where} must be sorted by {key}")


def validate_macho_policy(lock: dict, bundle_by_path: dict[str, dict]) -> None:
    macho_policy = require_dict(lock.get("machoPolicy"), "machoPolicy")
    require_keys(macho_policy, {"allowedSystemLoadRoots", "files"}, "machoPolicy")
    system_roots = require_list(macho_policy.get("allowedSystemLoadRoots"),
                                "machoPolicy.allowedSystemLoadRoots")
    if (system_roots != sorted(system_roots) or
            len(system_roots) != len(set(system_roots)) or not system_roots):
        fail("machoPolicy.allowedSystemLoadRoots must be a non-empty sorted array")
    for index, root in enumerate(system_roots):
        require_absolute_directory_prefix(root, f"machoPolicy.allowedSystemLoadRoots[{index}]")
    macho_files = require_list(macho_policy.get("files"), "machoPolicy.files")
    unique_sorted(macho_files, "path", "machoPolicy.files")
    macho_paths: set[str] = set()
    macho_by_path: dict[str, dict] = {}
    for index, raw in enumerate(macho_files):
        record = require_dict(raw, f"machoPolicy.files[{index}]")
        require_keys(record, {"path", "installId", "externalLoads"},
                     f"machoPolicy.files[{index}]")
        path = safe_relative(record.get("path"), f"machoPolicy.files[{index}].path")
        if path not in bundle_by_path:
            fail_tool_lock_closure(
                f"Mach-O policy references unknown bundle path {path}"
            )
        install_id = record.get("installId")
        if install_id is not None:
            require_string(install_id, f"Mach-O install ID for {path}")
        external = require_list(record.get("externalLoads"),
                                f"machoPolicy.files[{index}].externalLoads")
        unique_sorted(external, "installName", f"machoPolicy.files[{index}].externalLoads")
        bundle_targets: set[str] = set()
        for edge in external:
            edge = require_dict(edge, f"Mach-O external load for {path}")
            require_keys(edge, {"installName", "bundlePath"},
                         f"Mach-O external load for {path}")
            install_name = require_string(edge.get("installName"),
                                          f"Mach-O external load for {path}.installName")
            if not install_name.startswith("/"):
                fail(f"Mach-O external install name for {path} must be absolute")
            bundle_path = safe_relative(edge.get("bundlePath"),
                                        f"Mach-O external load for {path}.bundlePath")
            if bundle_path not in bundle_by_path:
                fail_tool_lock_closure(
                    f"Mach-O external load for {path} targets an unknown bundle path"
                )
            if bundle_path in bundle_targets:
                fail_tool_lock_closure(
                    f"Mach-O external loads for {path} repeat bundle path {bundle_path}"
                )
            bundle_targets.add(bundle_path)
        macho_paths.add(path)
        macho_by_path[path] = record
    if macho_paths != set(bundle_by_path):
        fail_tool_lock_closure(
            "every bundle file must have an explicit Mach-O closure policy"
        )
    return {
        path: [edge["bundlePath"] for edge in record["externalLoads"]]
        for path, record in macho_by_path.items()
    }


def validate_elf_policy(lock: dict, bundle_by_path: dict[str, dict]) -> dict[str, list[str]]:
    elf_policy = require_dict(lock.get("elfPolicy"), "elfPolicy")
    require_keys(elf_policy, {"allowedSystemLoadRoots", "files"}, "elfPolicy")
    system_roots = require_list(elf_policy.get("allowedSystemLoadRoots"),
                                "elfPolicy.allowedSystemLoadRoots")
    if (system_roots != sorted(system_roots) or
            len(system_roots) != len(set(system_roots)) or not system_roots):
        fail("elfPolicy.allowedSystemLoadRoots must be a non-empty sorted array")
    for index, root in enumerate(system_roots):
        require_absolute_directory_prefix(root, f"elfPolicy.allowedSystemLoadRoots[{index}]")
    elf_files = require_list(elf_policy.get("files"), "elfPolicy.files")
    unique_sorted(elf_files, "path", "elfPolicy.files")
    elf_paths: set[str] = set()
    adjacency: dict[str, list[str]] = {}
    for index, raw in enumerate(elf_files):
        record = require_dict(raw, f"elfPolicy.files[{index}]")
        require_keys(record, {"path", "needed", "runpath"},
                     f"elfPolicy.files[{index}]")
        path = safe_relative(record.get("path"), f"elfPolicy.files[{index}].path")
        if path not in bundle_by_path:
            fail_tool_lock_closure(
                f"ELF policy references unknown bundle path {path}"
            )
        needed = require_list(record.get("needed"),
                              f"elfPolicy.files[{index}].needed")
        unique_sorted(needed, "soname", f"elfPolicy.files[{index}].needed")
        bundle_targets: set[str] = set()
        internal: list[str] = []
        for edge in needed:
            edge = require_dict(edge, f"ELF needed entry for {path}")
            require_keys(edge, {"soname", "bundlePath"}, f"ELF needed entry for {path}")
            soname = require_string(edge.get("soname"), f"ELF needed soname for {path}")
            if not soname or "/" in soname or "\x00" in soname:
                fail(f"ELF needed soname for {path} must be a plain soname")
            bundle_path = edge.get("bundlePath")
            if bundle_path is not None:
                bundle_path = safe_relative(
                    bundle_path, f"ELF needed bundlePath for {path}")
                if bundle_path not in bundle_by_path:
                    fail_tool_lock_closure(
                        f"ELF needed for {path} targets an unknown bundle path"
                    )
                if bundle_path in bundle_targets:
                    fail_tool_lock_closure(
                        f"ELF needed for {path} repeats bundle path {bundle_path}"
                    )
                bundle_targets.add(bundle_path)
                internal.append(bundle_path)
        runpath = record.get("runpath")
        if runpath is not None:
            runpath = require_string(runpath, f"elfPolicy.files[{index}].runpath")
            if not runpath or "\x00" in runpath:
                fail(f"elfPolicy runpath for {path} must be non-empty")
        elf_paths.add(path)
        adjacency[path] = internal
    if elf_paths != set(bundle_by_path):
        fail_tool_lock_closure(
            "every bundle file must have an explicit ELF closure policy"
        )
    return adjacency


def tool_lock_policy_key(lock: dict) -> str:
    """Return the platform-bound policy key for a validated or candidate v4 lock."""

    platform = lock.get("platform")
    if platform == "darwin-arm64":
        return "machoPolicy"
    if platform == "linux-x86_64":
        return "elfPolicy"
    fail(f"unsupported toolchain lock platform: {platform}")


def is_darwin_tool_lock(lock: dict) -> bool:
    return lock.get("platform") == "darwin-arm64"


def is_source_build_tool(tool: dict) -> bool:
    return tool.get("sourceBuild") is not None


def validate_tool_lock(lock: dict) -> dict:
    schema = lock.get("schema")
    if schema in LEGACY_TOOL_LOCK_SCHEMAS:
        fail(f"toolchain lock schema {schema} is retired; migrate to {TOOL_LOCK_SCHEMA_V4}")
    if schema != TOOL_LOCK_SCHEMA_V4:
        fail("unsupported toolchain lock schema")
    platform = lock.get("platform")
    if platform == "darwin-arm64":
        policy_key = "machoPolicy"
        forbidden_policy = "elfPolicy"
    elif platform == "linux-x86_64":
        policy_key = "elfPolicy"
        forbidden_policy = "machoPolicy"
    else:
        fail("toolchain lock platform must be darwin-arm64 or linux-x86_64")
    require_keys(lock, {
        "schema", "platform", "assets", "compilerToolchain", "bundleFiles",
        policy_key, "tools", "unresolved",
    }, "toolchain lock")
    if forbidden_policy in lock:
        fail(f"toolchain lock for {platform} must not declare {forbidden_policy}")

    assets = require_list(lock.get("assets"), "assets")
    unique_sorted(assets, "id", "assets")
    asset_by_id: dict[str, dict] = {}
    for index, raw in enumerate(assets):
        asset = require_dict(raw, f"assets[{index}]")
        format_value = asset.get("format")
        if format_value == "cargo-git":
            require_keys(asset, {
                "id", "url", "commit", "format", "package", "bin", "version",
            }, f"assets[{index}]")
            asset_id = require_safe_asset_id(asset.get("id"), f"assets[{index}].id")
            require_https_url(asset.get("url"), f"asset {asset_id}.url")
            commit = require_string(asset.get("commit"), f"asset {asset_id}.commit")
            if SOURCE_COMMIT_RE.fullmatch(commit) is None:
                fail(f"asset {asset_id}.commit must be a lowercase 40-hex commit")
            require_safe_identifier(asset.get("package"), f"asset {asset_id}.package")
            require_safe_identifier(asset.get("bin"), f"asset {asset_id}.bin")
            require_semver(asset.get("version"), f"asset {asset_id}.version")
        elif format_value in DOWNLOAD_FORMATS:
            require_keys(asset, {"id", "url", "size", "sha256", "format"},
                         f"assets[{index}]", {"auth"})
            asset_id = require_safe_asset_id(asset.get("id"), f"assets[{index}].id")
            require_https_url(asset.get("url"), f"asset {asset_id}.url")
            size = asset.get("size")
            if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
                fail(f"asset {asset_id} size must be a positive integer")
            require_sha256(asset.get("sha256"), f"asset {asset_id}.sha256")
            auth = asset.get("auth")
            if auth is not None:
                auth = require_dict(auth, f"asset {asset_id}.auth")
                require_keys(auth, {"type", "realm", "service", "scope"},
                             f"asset {asset_id}.auth")
                if auth.get("type") != "oci-bearer":
                    fail(f"asset {asset_id} has unsupported auth type")
                require_https_url(auth.get("realm"), f"asset {asset_id}.auth.realm")
                require_string(auth.get("service"), f"asset {asset_id}.auth.service")
                require_string(auth.get("scope"), f"asset {asset_id}.auth.scope")
        else:
            fail(f"asset at assets[{index}] has unsupported format")
            asset_id = f"assets[{index}]"  # pragma: no cover - fail() never returns
        asset_by_id[asset_id] = asset

    compiler = require_dict(lock.get("compilerToolchain"), "compilerToolchain")
    require_keys(compiler, {
        "id", "version", "sourceCommit", "platform", "assetId", "archiveRoot",
        "stripComponents", "entryCount", "unpackedSize", "executables",
        "versionProbes",
    }, "compilerToolchain")
    require_safe_asset_id(compiler.get("id"), "compilerToolchain.id")
    require_semver(compiler.get("version"), "compilerToolchain.version")
    source_commit = require_string(compiler.get("sourceCommit"),
                                   "compilerToolchain.sourceCommit")
    if SOURCE_COMMIT_RE.fullmatch(source_commit) is None:
        fail("compilerToolchain.sourceCommit must be a lowercase 40-hex commit")
    if compiler.get("platform") != lock["platform"]:
        fail_tool_lock_closure("compilerToolchain.platform does not match the lock")
    compiler_asset = require_string(compiler.get("assetId"), "compilerToolchain.assetId")
    if compiler_asset not in asset_by_id:
        fail_tool_lock_closure("compilerToolchain references an unknown asset")
    if asset_by_id[compiler_asset]["format"] != "zip":
        fail_tool_lock_closure("compilerToolchain asset must be a ZIP archive")
    archive_root = safe_relative(compiler.get("archiveRoot"), "compilerToolchain.archiveRoot")
    if len(PurePosixPath(archive_root).parts) != 1:
        fail("compilerToolchain.archiveRoot must be one path component")
    strip_components = compiler.get("stripComponents")
    if (
        not isinstance(strip_components, int)
        or isinstance(strip_components, bool)
        or strip_components != 1
    ):
        fail("compilerToolchain.stripComponents must be 1")
    entry_count = compiler.get("entryCount")
    if (not isinstance(entry_count, int) or isinstance(entry_count, bool) or
            entry_count <= 1 or entry_count > MAX_ARCHIVE_MEMBERS):
        fail(f"compilerToolchain.entryCount must be in [2, {MAX_ARCHIVE_MEMBERS}]")
    unpacked_size = compiler.get("unpackedSize")
    if (not isinstance(unpacked_size, int) or isinstance(unpacked_size, bool) or
            unpacked_size <= 0 or unpacked_size > MAX_COMPILER_UNPACKED_BYTES):
        fail("compilerToolchain.unpackedSize must be in (0, 8 GiB]")
    compiler_executables = require_list(compiler.get("executables"), "compilerToolchain.executables")
    if not compiler_executables:
        fail("compilerToolchain.executables must be non-empty")
    unique_sorted(compiler_executables, "path", "compilerToolchain.executables")
    for index, raw in enumerate(compiler_executables):
        executable = require_dict(raw, f"compilerToolchain.executables[{index}]")
        require_keys(executable, {"path", "sha256"},
                     f"compilerToolchain.executables[{index}]")
        safe_relative(executable.get("path"), f"compilerToolchain.executables[{index}].path")
        require_sha256(executable.get("sha256"), f"compilerToolchain.executables[{index}].sha256")
    executable_paths = {record["path"] for record in compiler_executables}
    version_probes = require_list(compiler.get("versionProbes"),
                                  "compilerToolchain.versionProbes")
    if not version_probes:
        fail("compilerToolchain.versionProbes must be non-empty")
    unique_sorted(version_probes, "path", "compilerToolchain.versionProbes")
    probe_paths: set[str] = set()
    for index, raw in enumerate(version_probes):
        probe = require_dict(raw, f"compilerToolchain.versionProbes[{index}]")
        require_keys(probe, {"path", "args", "expected"},
                     f"compilerToolchain.versionProbes[{index}]")
        path = safe_relative(probe.get("path"),
                             f"compilerToolchain.versionProbes[{index}].path")
        if path not in executable_paths:
            fail_tool_lock_closure(
                f"compiler version probe references undeclared executable {path}"
            )
        args = require_list(probe.get("args"),
                            f"compilerToolchain.versionProbes[{index}].args")
        if not args or not all(isinstance(arg, str) and arg for arg in args):
            fail("compiler version probe args must contain non-empty strings")
        require_string(probe.get("expected"),
                       f"compilerToolchain.versionProbes[{index}].expected")
        probe_paths.add(path)
    if probe_paths != executable_paths:
        fail_tool_lock_closure(
            "every compiler executable must have exactly one version probe"
        )

    bundle_files = require_list(lock.get("bundleFiles"), "bundleFiles")
    if not bundle_files:
        fail("bundleFiles must be non-empty")
    unique_sorted(bundle_files, "path", "bundleFiles")
    bundle_by_path: dict[str, dict] = {}
    for index, raw in enumerate(bundle_files):
        record = require_dict(raw, f"bundleFiles[{index}]")
        require_keys(record, {"path", "assetId", "member", "size", "sha256", "mode"},
                     f"bundleFiles[{index}]")
        path = safe_relative(record.get("path"), f"bundleFiles[{index}].path")
        asset_id = require_string(record.get("assetId"), f"bundleFiles[{index}].assetId")
        if asset_id not in asset_by_id:
            fail_tool_lock_closure(
                f"bundle file {path} references an unknown asset"
            )
        member = record.get("member")
        asset_format = asset_by_id[asset_id]["format"]
        if asset_format == "cargo-git":
            fail_tool_lock_closure(
                f"bundle file {path} cannot reference cargo-git asset {asset_id}"
            )
        if asset_format == "file":
            if member is not None:
                fail_tool_lock_closure(
                    f"raw file asset {asset_id} must use a null member"
                )
        else:
            safe_relative(member, f"bundleFiles[{index}].member")
        size = record.get("size")
        if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
            fail(f"bundle file {path} size must be a positive integer")
        require_sha256(record.get("sha256"), f"bundleFiles[{index}].sha256")
        mode = record.get("mode")
        if mode not in {"0444", "0555"}:
            fail(f"bundle file {path} mode must be 0444 or 0555")
        bundle_by_path[path] = record

    if policy_key == "machoPolicy":
        bundle_adjacency = validate_macho_policy(lock, bundle_by_path)
    else:
        bundle_adjacency = validate_elf_policy(lock, bundle_by_path)

    tools = require_list(lock.get("tools"), "tools")
    if not tools:
        fail("tools must be non-empty")
    unique_sorted(tools, "id", "tools")
    source_build_executables: set[str] = set()
    for index, raw in enumerate(tools):
        tool = require_dict(raw, f"tools[{index}]")
        require_keys(tool, {
            "id", "version", "sourceUrl", "platform", "assetId", "executable",
            "defaultPath", "executableSha256", "runtimeLibrarySubdir",
            "runtimeFiles", "versionArgs", "expectedVersion", "licenseSpdx",
            "requiredByProfiles", "sourceBuild",
        }, f"tools[{index}]")
        tool_id = require_safe_asset_id(tool.get("id"), f"tools[{index}].id")
        require_semver(tool.get("version"), f"tool {tool_id}.version")
        require_https_url(tool.get("sourceUrl"), f"tool {tool_id}.sourceUrl")
        if tool.get("platform") != lock["platform"]:
            fail_tool_lock_closure(
                f"tool {tool_id} platform does not match the lock"
            )
        tool_asset = require_string(tool.get("assetId"), f"tool {tool_id}.assetId")
        if tool_asset not in asset_by_id:
            fail_tool_lock_closure(
                f"tool {tool_id} references an unknown asset"
            )
        executable = safe_relative(tool.get("executable"), f"tool {tool_id}.executable")
        default_path = require_string(tool.get("defaultPath"), f"tool {tool_id}.defaultPath")
        if (not default_path.startswith("~/") or "\\" in default_path or
                posixpath.normpath(default_path[2:]) != default_path[2:] or
                PurePosixPath(default_path[2:]).name != PurePosixPath(executable).name):
            fail(f"tool {tool_id} defaultPath must be a normalized home-relative executable path")
        source_build = tool.get("sourceBuild")
        runtime_subdir = tool.get("runtimeLibrarySubdir")
        runtime_files = require_list(tool.get("runtimeFiles"), f"tool {tool_id}.runtimeFiles")
        if source_build is not None:
            source_build = require_dict(source_build, f"tool {tool_id}.sourceBuild")
            require_keys(source_build, {"assetId"}, f"tool {tool_id}.sourceBuild")
            source_asset = require_string(
                source_build.get("assetId"), f"tool {tool_id}.sourceBuild.assetId")
            if source_asset != tool_asset:
                fail_tool_lock_closure(
                    f"tool {tool_id} sourceBuild.assetId must equal tools[].assetId"
                )
            if asset_by_id[tool_asset]["format"] != "cargo-git":
                fail_tool_lock_closure(
                    f"tool {tool_id} sourceBuild requires a cargo-git asset"
                )
            if tool.get("executableSha256") is not None:
                fail(f"tool {tool_id} sourceBuild requires executableSha256 null")
            if runtime_subdir is not None:
                fail_tool_lock_closure(
                    f"tool {tool_id} sourceBuild must not declare runtimeLibrarySubdir"
                )
            if runtime_files:
                fail_tool_lock_closure(
                    f"tool {tool_id} sourceBuild must declare empty runtimeFiles"
                )
            if executable in bundle_by_path:
                fail_tool_lock_closure(
                    f"tool {tool_id} sourceBuild executable must not appear in bundleFiles"
                )
            if executable in source_build_executables:
                fail_tool_lock_closure(
                    f"tool {tool_id} sourceBuild executable path is duplicated"
                )
            source_build_executables.add(executable)
            # cargo-git package/bin should match tool executable leaf for this product slice
            cargo_bin = asset_by_id[tool_asset]["bin"]
            if PurePosixPath(executable).name != cargo_bin:
                fail_tool_lock_closure(
                    f"tool {tool_id} executable leaf must equal cargo-git bin '{cargo_bin}'"
                )
            if asset_by_id[tool_asset]["version"] != tool["version"]:
                fail_tool_lock_closure(
                    f"tool {tool_id} version must match cargo-git asset version"
                )
        else:
            if asset_by_id[tool_asset]["format"] == "cargo-git":
                fail_tool_lock_closure(
                    f"tool {tool_id} cargo-git asset requires sourceBuild"
                )
            if executable not in bundle_by_path:
                fail_tool_lock_closure(
                    f"tool {tool_id} executable is absent from bundleFiles"
                )
            if bundle_by_path[executable]["assetId"] != tool_asset:
                fail_tool_lock_closure(
                    f"tool {tool_id} asset disagrees with its executable bundle asset"
                )
            executable_hash = require_sha256(tool.get("executableSha256"),
                                               f"tool {tool_id}.executableSha256")
            if executable_hash != bundle_by_path[executable]["sha256"]:
                fail_tool_lock_closure(
                    f"tool {tool_id} executable hash disagrees with bundleFiles"
                )
            if runtime_subdir is not None:
                runtime_subdir = safe_relative(
                    runtime_subdir, f"tool {tool_id}.runtimeLibrarySubdir")
            unique_sorted(runtime_files, "path", f"tool {tool_id}.runtimeFiles")
            declared_runtime: set[str] = set()
            for runtime in runtime_files:
                runtime = require_dict(runtime, f"tool {tool_id}.runtimeFiles[]")
                require_keys(runtime, {"path", "sha256"}, f"tool {tool_id}.runtimeFiles[]")
                runtime_path = safe_relative(
                    runtime.get("path"), f"tool {tool_id} runtime file path")
                if runtime_path not in bundle_by_path:
                    fail_tool_lock_closure(
                        f"tool {tool_id} runtime file is absent from bundleFiles"
                    )
                runtime_hash = require_sha256(runtime.get("sha256"),
                                                 f"tool {tool_id} runtime file sha256")
                if runtime_hash != bundle_by_path[runtime_path]["sha256"]:
                    fail_tool_lock_closure(
                        f"tool {tool_id} runtime file hash disagrees with bundleFiles"
                    )
                declared_runtime.add(runtime_path)

            pending = list(bundle_adjacency[executable])
            closure: set[str] = set()
            while pending:
                dependency = pending.pop()
                if dependency in closure:
                    continue
                if dependency == executable:
                    fail_tool_lock_closure(
                        f"tool {tool_id} bundle closure cycles to its executable"
                    )
                closure.add(dependency)
                pending.extend(bundle_adjacency[dependency])
            if declared_runtime != closure:
                fail_tool_lock_closure(
                    f"tool {tool_id} runtimeFiles do not equal its bundle closure"
                )
            if closure and runtime_subdir is None:
                fail_tool_lock_closure(
                    f"tool {tool_id} with runtime files must declare runtimeLibrarySubdir"
                )
            if not closure and runtime_subdir is not None:
                fail_tool_lock_closure(
                    f"tool {tool_id} without runtime files must not declare runtimeLibrarySubdir"
                )
            if runtime_subdir is not None and any(
                    not path.startswith(runtime_subdir + "/") for path in closure):
                fail_tool_lock_closure(
                    f"tool {tool_id} runtime file is outside runtimeLibrarySubdir"
                )
        args = require_list(tool.get("versionArgs"), f"tool {tool_id}.versionArgs")
        if not args or not all(isinstance(arg, str) and arg for arg in args):
            fail(f"tool {tool_id} versionArgs must be non-empty strings")
        require_string(tool.get("expectedVersion"), f"tool {tool_id}.expectedVersion")
        require_string(tool.get("licenseSpdx"), f"tool {tool_id}.licenseSpdx")
        profiles = require_string_array(tool.get("requiredByProfiles"),
                                        f"tool {tool_id}.requiredByProfiles", nonempty=True)
        for profile in profiles:
            require_safe_asset_id(profile, f"tool {tool_id}.requiredByProfiles[]")

    unresolved = require_dict(lock.get("unresolved"), "unresolved")
    require_keys(unresolved, {"nearSandbox", "solanaAssembler", "nargo", "barretenberg"},
                 "unresolved")
    for field, value in unresolved.items():
        if value is not None:
            require_semver(value, f"unresolved.{field}")

    return lock


DARWIN_PLATFORM_KEYS = frozenset({
    "productVersion", "buildVersion", "kernelRelease", "arch", "procTranslated",
    "sip", "authenticatedRoot", "systemVolumeSeal",
})
LINUX_PLATFORM_KEYS = frozenset({
    "osReleaseId", "osReleaseVersionId", "kernelRelease", "arch", "secureBoot",
})


def host_profile_kind(profile: dict) -> str:
    platform = profile.get("platform")
    keys = set(platform.keys()) if isinstance(platform, dict) else set()
    if keys == DARWIN_PLATFORM_KEYS:
        return "darwin"
    if keys == LINUX_PLATFORM_KEYS:
        return "linux"
    fail("host profile platform has an unrecognized field set")


def validate_host_lock(lock: dict) -> dict:
    require_keys(lock, {"schema", "profiles"}, "host profile lock")
    schema = lock.get("schema")
    if schema == "proof-forge.host-profiles.v1":
        fail("host profile lock v1 is retired; migrate to "
             "proof-forge.host-profiles.v2 (ADR-0016)")
    if schema != "proof-forge.host-profiles.v2":
        fail("unsupported host profile lock schema")
    profiles = require_list(lock.get("profiles"), "profiles")
    if not profiles:
        fail("host profile lock must contain at least one profile")
    unique_sorted(profiles, "id", "profiles")
    seen_kinds: set[str] = set()
    for index, raw in enumerate(profiles):
        profile = require_dict(raw, f"profiles[{index}]")
        profile_id = require_safe_identifier(profile.get("id"), f"profiles[{index}].id")
        kind = host_profile_kind(profile)
        if kind in seen_kinds:
            fail(f"host profile lock must contain at most one {kind} profile")
        seen_kinds.add(kind)
        require_keys(profile, {
            "id", "platform", "eligibleForHermetic", "ineligibilityReason",
            "digestBootstrap", "systemRuntime", "systemTools",
        } | ({"developerTools"} if kind == "darwin" else {"distroTools"}),
                     f"profiles[{index}]")
        platform = require_dict(profile.get("platform"), f"profile {profile_id}.platform")
        if not isinstance(profile.get("eligibleForHermetic"), bool):
            fail(f"profile {profile_id}.eligibleForHermetic must be boolean")
        if profile["eligibleForHermetic"]:
            if profile.get("ineligibilityReason") is not None:
                fail(f"profile {profile_id}.ineligibilityReason must be null when eligible")
        else:
            require_string(profile.get("ineligibilityReason"),
                           f"profile {profile_id}.ineligibilityReason")
        bootstrap = require_dict(profile.get("digestBootstrap"),
                                 f"profile {profile_id}.digestBootstrap")
        require_keys(bootstrap, {"path", "sha256", "knownAnswerInput", "knownAnswerSha256"},
                     f"profile {profile_id}.digestBootstrap")
        require_absolute_file_path(bootstrap.get("path"),
                                   f"profile {profile_id}.digestBootstrap.path")
        require_sha256(bootstrap.get("sha256"), f"profile {profile_id}.digestBootstrap.sha256")
        require_string(bootstrap.get("knownAnswerInput"),
                       f"profile {profile_id}.digestBootstrap.knownAnswerInput")
        require_sha256(bootstrap.get("knownAnswerSha256"),
                       f"profile {profile_id}.digestBootstrap.knownAnswerSha256")

        runtime = require_dict(profile.get("systemRuntime"),
                               f"profile {profile_id}.systemRuntime")
        require_keys(runtime, {"allowedLoadRoots"}, f"profile {profile_id}.systemRuntime")
        roots = require_list(runtime.get("allowedLoadRoots"),
                             f"profile {profile_id}.systemRuntime.allowedLoadRoots")
        if not roots or roots != sorted(roots) or len(roots) != len(set(roots)):
            fail(f"profile {profile_id} system runtime roots must be non-empty, unique, and sorted")
        for root_index, root in enumerate(roots):
            require_absolute_directory_prefix(
                root, f"profile {profile_id}.systemRuntime.allowedLoadRoots[{root_index}]")

        tools = require_list(profile.get("systemTools"), f"profile {profile_id}.systemTools")
        if not tools:
            fail(f"profile {profile_id}.systemTools must be non-empty")
        unique_sorted(tools, "id", f"profile {profile_id}.systemTools")
        for tool in tools:
            tool = require_dict(tool, f"profile {profile_id}.systemTools[]")
            require_keys(tool, {
                "id", "path", "sha256", "nodeKind", "linkTarget", "resolvedPath",
                "resolvedNlink", "mode",
            },
                         f"profile {profile_id}.systemTools[]")
            require_safe_asset_id(tool.get("id"), f"profile {profile_id} system tool id")
            path = require_absolute_file_path(tool.get("path"),
                                              f"profile {profile_id} system tool path")
            require_sha256(tool.get("sha256"), f"profile {profile_id} system tool sha256")
            node_kind = tool.get("nodeKind")
            if node_kind not in {"regular", "symlink"}:
                fail(f"profile {profile_id} system tool nodeKind must be regular or symlink")
            link_target = require_nullable_string(
                tool.get("linkTarget"), f"profile {profile_id} system tool linkTarget")
            if node_kind == "regular" and link_target is not None:
                fail(f"profile {profile_id} regular system tool must have null linkTarget")
            if node_kind == "symlink":
                if link_target is None:
                    fail(f"profile {profile_id} symlink system tool must lock linkTarget")
                if "\x00" in link_target or "\\" in link_target:
                    fail(f"profile {profile_id} system tool linkTarget is invalid")
                if posixpath.normpath(link_target) != link_target:
                    fail(f"profile {profile_id} system tool linkTarget must be normalized")
            resolved_path = require_absolute_file_path(
                tool.get("resolvedPath"), f"profile {profile_id} system tool resolvedPath")
            if node_kind == "regular" and resolved_path != path:
                fail(f"profile {profile_id} regular system tool must resolve to itself")
            resolved_nlink = tool.get("resolvedNlink")
            if (not isinstance(resolved_nlink, int) or isinstance(resolved_nlink, bool) or
                    resolved_nlink < 1):
                fail(f"profile {profile_id} system tool resolvedNlink must be positive")
            mode = require_string(tool.get("mode"),
                                  f"profile {profile_id} system tool mode")
            if FILE_MODE_RE.fullmatch(mode) is None:
                fail(f"profile {profile_id} system tool mode must be a four-digit octal mode")
        if kind == "darwin":
            eligible_state = validate_darwin_developer(profile, platform)
        else:
            eligible_state = validate_linux_distro(profile, platform)
        if profile["eligibleForHermetic"] and not eligible_state:
            fail(f"profile {profile_id} is marked eligible but does not satisfy the host policy")

        bootstrap = profile["digestBootstrap"]
        matching_bootstrap = [
            tool for tool in tools if tool["path"] == bootstrap["path"]
        ]
        if (len(matching_bootstrap) != 1 or
                matching_bootstrap[0]["sha256"] != bootstrap["sha256"]):
            fail(f"profile {profile_id} digest bootstrap must match one locked system tool")
    return lock


def validate_darwin_developer(profile: dict, platform: dict) -> bool:
    profile_id = profile["id"]
    for field in ("productVersion", "buildVersion", "kernelRelease", "arch",
                  "sip", "authenticatedRoot", "systemVolumeSeal"):
        require_string(platform.get(field), f"profile {profile_id}.platform.{field}")
    if not isinstance(platform.get("procTranslated"), bool):
        fail(f"profile {profile_id}.platform.procTranslated must be boolean")
    if platform["sip"] not in {"disabled", "enabled"}:
        fail(f"profile {profile_id}.platform.sip has an unsupported value")
    if platform["authenticatedRoot"] not in {"disabled", "enabled"}:
        fail(f"profile {profile_id}.platform.authenticatedRoot has an unsupported value")
    if platform["systemVolumeSeal"] not in {"broken", "sealed", "unsealed"}:
        fail(f"profile {profile_id}.platform.systemVolumeSeal has an unsupported value")
    developer = require_dict(profile.get("developerTools"), f"profile {profile_id}.developerTools")
    require_keys(developer, {
        "developerDir", "xcodeAppPath", "xcodeVersion", "xcodeBuildVersion",
        "xcodeIdentifier", "xcodeTeamIdentifier", "xcodeDesignatedRequirement",
        "xcodeCdHash", "xcodeMutableByCurrentUser", "allowedRuntimeRoots",
        "gitPath", "gitSha256", "gitVersion", "otoolPath", "otoolSha256",
        "otoolVersion", "pythonDispatchPath", "pythonPath", "pythonSha256",
        "pythonVersion",
    }, f"profile {profile_id}.developerTools")
    developer_dir = require_absolute_file_path(
        developer.get("developerDir"), f"profile {profile_id}.developerTools.developerDir")
    xcode_app = require_absolute_file_path(
        developer.get("xcodeAppPath"), f"profile {profile_id}.developerTools.xcodeAppPath")
    if not developer_dir.startswith(xcode_app + "/"):
        fail(f"profile {profile_id} developerDir must be inside xcodeAppPath")
    for field in (
            "xcodeVersion", "xcodeBuildVersion", "xcodeIdentifier",
            "xcodeTeamIdentifier", "xcodeDesignatedRequirement", "gitVersion",
            "otoolVersion", "pythonVersion"):
        require_string(developer.get(field), f"profile {profile_id}.developerTools.{field}")
    if re.fullmatch(r"[0-9a-f]{40}", str(developer.get("xcodeCdHash"))) is None:
        fail(f"profile {profile_id}.developerTools.xcodeCdHash must be lowercase 40-hex")
    if not isinstance(developer.get("xcodeMutableByCurrentUser"), bool):
        fail(f"profile {profile_id}.developerTools.xcodeMutableByCurrentUser must be boolean")
    developer_roots = require_list(
        developer.get("allowedRuntimeRoots"),
        f"profile {profile_id}.developerTools.allowedRuntimeRoots")
    if (not developer_roots or developer_roots != sorted(developer_roots) or
            len(developer_roots) != len(set(developer_roots))):
        fail(f"profile {profile_id} developer runtime roots must be non-empty, unique, and sorted")
    for root_index, root in enumerate(developer_roots):
        require_absolute_directory_prefix(
            root, f"profile {profile_id}.developerTools.allowedRuntimeRoots[{root_index}]")
    if xcode_app + "/" not in developer_roots:
        fail(f"profile {profile_id} developer runtime roots must include xcodeAppPath")
    for field in ("gitSha256", "pythonSha256", "otoolSha256"):
        require_sha256(developer.get(field), f"profile {profile_id}.developerTools.{field}")
    for field in ("gitPath", "pythonDispatchPath", "pythonPath", "otoolPath"):
        path = require_absolute_file_path(developer.get(field),
                                          f"profile {profile_id}.developerTools.{field}")
        if not path.startswith(developer_dir + "/"):
            fail(f"profile {profile_id}.developerTools.{field} must be inside developerDir")
    return (
        platform["arch"] == "arm64" and
        not platform["procTranslated"] and
        platform["sip"] == "enabled" and
        platform["authenticatedRoot"] == "enabled" and
        platform["systemVolumeSeal"] == "sealed" and
        not developer["xcodeMutableByCurrentUser"]
    )


def validate_linux_distro(profile: dict, platform: dict) -> bool:
    profile_id = profile["id"]
    for field in ("osReleaseId", "osReleaseVersionId", "kernelRelease", "arch"):
        require_string(platform.get(field), f"profile {profile_id}.platform.{field}")
    if platform["secureBoot"] not in {"enabled", "disabled", "unavailable"}:
        fail(f"profile {profile_id}.platform.secureBoot has an unsupported value")
    distro = require_dict(profile.get("distroTools"), f"profile {profile_id}.distroTools")
    require_keys(distro, {
        "gitPath", "gitSha256", "gitVersion",
        "pythonPath", "pythonSha256", "pythonVersion",
        "readelfPath", "readelfSha256", "readelfVersion",
        "toolsMutableByCurrentUser",
    }, f"profile {profile_id}.distroTools")
    for field in ("gitPath", "pythonPath", "readelfPath"):
        require_absolute_file_path(distro.get(field),
                                   f"profile {profile_id}.distroTools.{field}")
    for field in ("gitSha256", "pythonSha256", "readelfSha256"):
        require_sha256(distro.get(field), f"profile {profile_id}.distroTools.{field}")
    for field in ("gitVersion", "pythonVersion", "readelfVersion"):
        require_string(distro.get(field), f"profile {profile_id}.distroTools.{field}")
    if not isinstance(distro.get("toolsMutableByCurrentUser"), bool):
        fail(f"profile {profile_id}.distroTools.toolsMutableByCurrentUser must be boolean")
    return (
        platform["arch"] in {"x86_64", "aarch64"} and
        platform["secureBoot"] == "enabled" and
        not distro["toolsMutableByCurrentUser"]
    )


def validate_lock_pair(tool_lock: dict, host_lock: dict) -> None:
    if is_darwin_tool_lock(tool_lock):
        policy_key = "machoPolicy"
        kind = "darwin"
    else:
        policy_key = "elfPolicy"
        kind = "linux"
    expected = tool_lock[policy_key]["allowedSystemLoadRoots"]
    matching = [
        profile for profile in host_lock["profiles"]
        if host_profile_kind(profile) == kind
    ]
    if len(matching) != 1:
        fail(f"host profile lock must contain exactly one {kind} profile for this tool lock")
    observed = matching[0]["systemRuntime"]["allowedLoadRoots"]
    if observed != expected:
        fail(f"profile {matching[0]['id']} system runtime roots disagree with the load policy")


def validate_host_profile_file(path: Path) -> None:
    profile = load_json(path)
    synthetic_lock = {"schema": "proof-forge.host-profiles.v2", "profiles": [profile]}
    validate_host_lock(synthetic_lock)
    kind = host_profile_kind(profile)
    for name in dict.fromkeys(PLATFORM_LOCK_FILES.values()):
        lock_path = ROOT / name
        if not lock_path.is_file():
            continue
        tool_lock = validate_tool_lock(load_json(lock_path))
        lock_kind = "darwin" if is_darwin_tool_lock(tool_lock) else "linux"
        if lock_kind != kind:
            continue
        validate_lock_pair(tool_lock, synthetic_lock)
    summary = {
        "eligibleForHermetic": profile["eligibleForHermetic"],
        "hostProfileId": profile["id"],
        "ineligibilityReason": profile["ineligibilityReason"],
        "profileKind": kind,
    }
    print(json.dumps(summary, sort_keys=True, separators=(",", ":")))


def reject_duplicate_json_keys(pairs: list[tuple[str, object]]) -> dict:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def parse_json_text(text: str, where: str) -> dict:
    try:
        value = json.loads(text, object_pairs_hook=reject_duplicate_json_keys)
    except (AssetError, json.JSONDecodeError) as error:
        fail(f"cannot parse {where}: {error}")
    return require_dict(value, where)


def load_json(path: Path) -> dict:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        fail(f"cannot read {path}: {error}")
    return parse_json_text(text, str(path))


def load_locks(tool_path: Path, host_path: Path) -> tuple[dict, dict]:
    tool_lock = validate_tool_lock(load_json(tool_path))
    host_lock = validate_host_lock(load_json(host_path))
    validate_lock_pair(tool_lock, host_lock)
    return tool_lock, host_lock


def sha256_file(path: Path) -> str:
    with path.open("rb") as handle:
        return sha256_handle(handle)


def sha256_handle(handle: BinaryIO) -> str:
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def cache_root() -> Path:
    explicit = os.environ.get("PROOF_FORGE_ASSET_CACHE")
    if explicit:
        root = Path(explicit)
    else:
        base = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
        root = base / "proof-forge-v2" / "assets"
    require_normalized_absolute_path(root, "asset cache root")
    if root.resolve(strict=False) != root:
        fail("asset cache root must not traverse symlinked path components")
    return root


def cached_asset_path(asset: dict) -> Path:
    asset_id = require_safe_asset_id(asset.get("id"), "asset cache id")
    if asset.get("format") == "cargo-git":
        fail(f"cargo-git asset {asset_id} uses cargo_git_cache_root, not sha256 cache")
    digest = require_sha256(asset.get("sha256"), f"asset {asset_id}.sha256")
    root = cache_root()
    path = root / "sha256" / digest / asset_id
    if path.parent.parent.parent != root:
        fail(f"cached asset {asset_id} escaped the cache root")
    return path


def cargo_git_cache_root(asset: dict) -> Path:
    """Content-addressed (by commit) workspace root for a cargo-git asset."""

    asset_id = require_safe_asset_id(asset.get("id"), "cargo-git asset id")
    if asset.get("format") != "cargo-git":
        fail(f"asset {asset_id} is not cargo-git")
    commit = require_string(asset.get("commit"), f"asset {asset_id}.commit")
    if SOURCE_COMMIT_RE.fullmatch(commit) is None:
        fail(f"asset {asset_id}.commit must be a lowercase 40-hex commit")
    root = cache_root()
    path = root / "cargo-git" / commit / asset_id
    if path.parent.parent.parent != root:
        fail(f"cargo-git asset {asset_id} escaped the cache root")
    return path


def cargo_git_binary_path(asset: dict) -> Path:
    return cargo_git_cache_root(asset) / "target" / "release" / asset["bin"]


def cargo_git_compatibility_rust_toolchain(asset: dict) -> str | None:
    """Return an exact engineering-only Rust compatibility override, if any."""

    return CARGO_GIT_RUST_TOOLCHAIN_OVERRIDES.get(
        (asset.get("id"), asset.get("commit"))
    )


def cargo_git_build_environment(staging: Path, rustup_home: Path,
                                rust_toolchain: str | None,
                                host_path: str) -> dict[str, str]:
    """Build without user Cargo config or inherited Rust/linker flags."""

    environment = {
        "LC_ALL": "C",
        "TZ": "UTC",
        "HOME": str(staging / ".proof-forge-home"),
        "PATH": host_path,
        "CARGO_HOME": str(staging / ".proof-forge-cargo-home"),
        "RUSTUP_HOME": str(rustup_home),
    }
    if rust_toolchain is not None:
        environment["RUSTUP_TOOLCHAIN"] = rust_toolchain
    return environment


def cargo_git_build_policy_bytes(asset: dict) -> bytes | None:
    rust_toolchain = cargo_git_compatibility_rust_toolchain(asset)
    if rust_toolchain is None:
        return None
    return (
        f"{CARGO_GIT_BUILD_POLICY_SCHEMA}\n"
        f"rust-toolchain={rust_toolchain}\n"
    ).encode("ascii")


def cargo_git_cached_policy_matches(asset: dict, cache_dir: Path) -> bool:
    expected = cargo_git_build_policy_bytes(asset)
    if expected is None:
        return True
    marker = cache_dir / CARGO_GIT_BUILD_POLICY_MARKER
    try:
        metadata = marker.lstat()
    except FileNotFoundError:
        return False
    if (
        not stat.S_ISREG(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or metadata.st_nlink != 1
        or stat.S_IMODE(metadata.st_mode) != 0o444
        or metadata.st_size != len(expected)
    ):
        return False
    try:
        return marker.read_bytes() == expected
    except OSError:
        return False


def write_cargo_git_build_policy(asset: dict, staging: Path) -> None:
    content = cargo_git_build_policy_bytes(asset)
    if content is None:
        return
    marker = staging / CARGO_GIT_BUILD_POLICY_MARKER
    with marker.open("xb") as handle:
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(marker, 0o444)


def validate_owned_directory(path: Path, where: str) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        fail(f"{where} is missing: {path}")
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail(f"{where} is not a regular directory: {path}")
    if metadata.st_uid != os.getuid():
        fail(f"{where} is not owned by the current user: {path}")
    if stat.S_IMODE(metadata.st_mode) & 0o022:
        fail(f"{where} is group/world writable: {path}")


def cache_asset_parent(asset: dict, *, create: bool) -> Path:
    destination = cached_asset_path(asset)
    directories = [cache_root(), cache_root() / "sha256", destination.parent]
    if create:
        for directory in directories:
            try:
                directory.mkdir(mode=0o700, parents=directory == directories[0])
            except FileExistsError:
                pass
    for index, directory in enumerate(directories):
        validate_owned_directory(directory, f"asset cache directory {index}")
    return destination.parent


@contextlib.contextmanager
def cached_asset_snapshot(asset: dict) -> Iterator[BinaryIO]:
    path = cached_asset_path(asset)
    cache_asset_parent(asset, create=False)
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except FileNotFoundError:
        fail(f"cache miss for {asset['id']}; run toolchain-assets provision")
    except OSError as error:
        fail(f"cannot open cached asset {asset['id']}: {error}")
    with os.fdopen(descriptor, "rb", closefd=True) as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode):
            fail(f"cached asset {asset['id']} is not a regular file")
        if before.st_nlink != 1:
            fail(f"cached asset {asset['id']} must have exactly one hard link")
        if before.st_uid != os.getuid():
            fail(f"cached asset {asset['id']} is not owned by the current user")
        if stat.S_IMODE(before.st_mode) != 0o444:
            fail(f"cached asset {asset['id']} mode must be 0444")
        if before.st_size != asset["size"]:
            fail(f"cached asset {asset['id']} size mismatch")
        digest = hashlib.sha256()
        with tempfile.TemporaryFile(mode="w+b") as snapshot:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
                snapshot.write(chunk)
            after = os.fstat(source.fileno())
            stable_fields = ("st_dev", "st_ino", "st_mode", "st_nlink", "st_uid", "st_size")
            if any(getattr(before, field) != getattr(after, field) for field in stable_fields):
                fail(f"cached asset {asset['id']} changed while being validated")
            actual = digest.hexdigest()
            if actual != asset["sha256"]:
                fail(f"cached asset {asset['id']} hash mismatch: {actual}")
            snapshot.seek(0)
            yield snapshot


def validate_cached_asset(asset: dict) -> Path:
    path = cached_asset_path(asset)
    with cached_asset_snapshot(asset):
        pass
    return path


def https_origin(url: str) -> tuple[str, str, int]:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme.lower() != "https" or not parsed.hostname:
        fail(f"redirect URL must use HTTPS: {url}")
    try:
        port = parsed.port or 443
    except ValueError:
        fail(f"redirect URL has an invalid port: {url}")
    return "https", parsed.hostname.lower(), port


class StrictHTTPSRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Keep every redirect on HTTPS and never forward bearer auth cross-origin."""

    max_redirections = MAX_HTTPS_REDIRECTS
    max_repeats = 2

    def redirect_request(self, request, file_pointer, code, message, headers, new_url):
        absolute_url = urllib.parse.urljoin(request.full_url, new_url)
        new_origin = https_origin(absolute_url)
        old_origin = https_origin(request.full_url)
        redirected = super().redirect_request(
            request, file_pointer, code, message, headers, absolute_url,
        )
        if redirected is not None and new_origin != old_origin:
            for mapping in (redirected.headers, redirected.unredirected_hdrs):
                for name in list(mapping):
                    if name.lower() == "authorization":
                        mapping.pop(name, None)
        return redirected


TRANSIENT_HTTP_STATUSES = {429, 500, 502, 503, 504}
SAFE_HTTPS_OPEN_ATTEMPTS = 4
SAFE_HTTPS_OPEN_BACKOFF_SECONDS = (2, 5, 10)


def safe_https_open(request: urllib.request.Request, timeout: int):
    https_origin(request.full_url)
    # Transient CDN/gateway errors (429/5xx, connection resets, timeouts) are
    # retried with a small fixed backoff; 4xx and all other failures fail fast.
    for attempt in range(SAFE_HTTPS_OPEN_ATTEMPTS):
        try:
            opener = urllib.request.build_opener(StrictHTTPSRedirectHandler())
            response = opener.open(request, timeout=timeout)  # noqa: S310 - HTTPS enforced above
            break
        except urllib.error.HTTPError as error:
            if error.code in TRANSIENT_HTTP_STATUSES and attempt + 1 < SAFE_HTTPS_OPEN_ATTEMPTS:
                delay = SAFE_HTTPS_OPEN_BACKOFF_SECONDS[attempt]
                print(
                    f"toolchain-assets: HTTP {error.code}; retrying in {delay}s "
                    f"(attempt {attempt + 2}/{SAFE_HTTPS_OPEN_ATTEMPTS})",
                    file=sys.stderr,
                )
                time.sleep(delay)
                continue
            raise
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            if attempt + 1 < SAFE_HTTPS_OPEN_ATTEMPTS:
                delay = SAFE_HTTPS_OPEN_BACKOFF_SECONDS[attempt]
                print(
                    f"toolchain-assets: {type(error).__name__}; retrying in {delay}s "
                    f"(attempt {attempt + 2}/{SAFE_HTTPS_OPEN_ATTEMPTS})",
                    file=sys.stderr,
                )
                time.sleep(delay)
                continue
            raise
    try:
        https_origin(response.geturl())
    except Exception:
        response.close()
        raise
    return response


def request_headers(asset: dict) -> dict[str, str]:
    headers = {"User-Agent": "ProofForge-V2-toolchain-provision/1"}
    auth = asset.get("auth")
    if auth is None:
        return headers
    query = urllib.parse.urlencode({"service": auth["service"], "scope": auth["scope"]})
    separator = "&" if urllib.parse.urlsplit(auth["realm"]).query else "?"
    request = urllib.request.Request(auth["realm"] + separator + query, headers=headers)
    with safe_https_open(request, timeout=30) as response:
        declared_length = response.headers.get("Content-Length")
        if declared_length is not None:
            try:
                if int(declared_length) > MAX_OCI_TOKEN_BYTES:
                    fail(f"asset {asset['id']} auth response exceeded 64 KiB")
            except ValueError:
                fail(f"asset {asset['id']} auth returned an invalid Content-Length")
        token_bytes = response.read(MAX_OCI_TOKEN_BYTES + 1)
        if len(token_bytes) > MAX_OCI_TOKEN_BYTES:
            fail(f"asset {asset['id']} auth response exceeded 64 KiB")
    try:
        token_doc = require_dict(json.loads(token_bytes), f"asset {asset['id']} auth response")
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"asset {asset['id']} auth returned invalid JSON: {error}")
    token = token_doc.get("token") or token_doc.get("access_token")
    if not isinstance(token, str) or not token or "\r" in token or "\n" in token:
        fail(f"asset {asset['id']} auth returned no bearer token")
    headers["Authorization"] = "Bearer " + token
    return headers


def provision_cargo_git_asset(asset: dict) -> Path:
    """Clone pinned commit and cargo build --release; cache under cargo-git/<commit>/<id>."""

    asset_id = asset["id"]
    commit = asset["commit"]
    package = asset["package"]
    binary_name = asset["bin"]
    rust_toolchain = cargo_git_compatibility_rust_toolchain(asset)
    cache_dir = cargo_git_cache_root(asset)
    binary = cargo_git_binary_path(asset)
    # Ensure cache parents exist with owned-directory checks.
    directories = [cache_root(), cache_root() / "cargo-git", cache_dir.parent]
    for directory in directories:
        try:
            directory.mkdir(mode=0o700, parents=directory == directories[0])
        except FileExistsError:
            pass
        validate_owned_directory(directory, f"cargo-git cache parent for {asset_id}")

    def binary_usable() -> bool:
        try:
            metadata = binary.lstat()
        except FileNotFoundError:
            return False
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            return False
        if metadata.st_uid != os.getuid():
            return False
        if not os.access(binary, os.X_OK):
            return False
        return cargo_git_cached_policy_matches(asset, cache_dir)

    if cache_dir.is_dir() and binary_usable():
        policy = f" rust={rust_toolchain}" if rust_toolchain is not None else ""
        print(f"toolchain-assets: cached cargo-git {asset_id} commit={commit}{policy}")
        return binary

    staging = cache_dir.parent / (
        f".{asset_id}.staging-{os.getpid()}-{secrets.token_hex(6)}"
    )
    if staging.exists() or staging.is_symlink():
        fail(f"cargo-git staging path already exists: {staging}")
    try:
        clone = subprocess.run(
            [
                "git", "clone", "--filter=blob:none", "--no-checkout",
                asset["url"], str(staging),
            ],
            check=False,
            capture_output=True,
            text=True,
            env={
                "LC_ALL": "C",
                "TZ": "UTC",
                "HOME": os.environ.get("HOME", "/var/empty"),
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "GIT_TERMINAL_PROMPT": "0",
            },
            timeout=600,
        )
        if clone.returncode != 0:
            fail(
                f"cargo-git clone failed for {asset_id}: "
                f"{clone.stderr.strip() or clone.stdout.strip()}"
            )
        fetch = subprocess.run(
            ["git", "-C", str(staging), "fetch", "--depth", "1", "origin", commit],
            check=False,
            capture_output=True,
            text=True,
            env={
                "LC_ALL": "C",
                "TZ": "UTC",
                "HOME": os.environ.get("HOME", "/var/empty"),
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "GIT_TERMINAL_PROMPT": "0",
            },
            timeout=600,
        )
        # shallow fetch of an arbitrary commit may fail on some remotes; fall back to full fetch
        if fetch.returncode != 0:
            fetch = subprocess.run(
                ["git", "-C", str(staging), "fetch", "origin", commit],
                check=False,
                capture_output=True,
                text=True,
                env={
                    "LC_ALL": "C",
                    "TZ": "UTC",
                    "HOME": os.environ.get("HOME", "/var/empty"),
                    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                    "GIT_TERMINAL_PROMPT": "0",
                },
                timeout=1200,
            )
        if fetch.returncode != 0:
            fail(
                f"cargo-git fetch failed for {asset_id}@{commit}: "
                f"{fetch.stderr.strip() or fetch.stdout.strip()}"
            )
        checkout = subprocess.run(
            ["git", "-C", str(staging), "checkout", "--force", commit],
            check=False,
            capture_output=True,
            text=True,
            env={
                "LC_ALL": "C",
                "TZ": "UTC",
                "HOME": os.environ.get("HOME", "/var/empty"),
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "GIT_TERMINAL_PROMPT": "0",
            },
            timeout=120,
        )
        if checkout.returncode != 0:
            fail(
                f"cargo-git checkout failed for {asset_id}@{commit}: "
                f"{checkout.stderr.strip() or checkout.stdout.strip()}"
            )
        head = subprocess.run(
            ["git", "-C", str(staging), "rev-parse", "HEAD"],
            check=False,
            capture_output=True,
            text=True,
            env={
                "LC_ALL": "C",
                "TZ": "UTC",
                "HOME": os.environ.get("HOME", "/var/empty"),
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "GIT_TERMINAL_PROMPT": "0",
            },
            timeout=30,
        )
        if head.returncode != 0 or head.stdout.strip() != commit:
            fail(
                f"cargo-git HEAD mismatch for {asset_id}: "
                f"expected {commit}, got {head.stdout.strip()!r}"
            )
        host_path = os.environ.get("PATH", "/usr/bin:/bin")
        if rust_toolchain is None:
            cargo = shutil.which("cargo")
            if cargo is None:
                fail(f"cargo is required to provision cargo-git asset {asset_id}")
            rustup_home = Path(os.environ.get(
                "RUSTUP_HOME", str(Path.home() / ".rustup")))
            build_command = [cargo, "build", "--release", "-p", package]
        else:
            rustup = shutil.which("rustup")
            if rustup is None:
                fail(
                    f"rustup is required to provision cargo-git asset {asset_id} "
                    f"with Rust {rust_toolchain}"
                )
            rustup_home = cache_root() / "rustup"
            try:
                rustup_home.mkdir(mode=0o700)
            except FileExistsError:
                pass
            validate_owned_directory(
                rustup_home, f"cargo-git rustup root for {asset_id}")
            build_command = [
                rustup, "run", rust_toolchain, "cargo",
                "build", "--release", "-p", package,
            ]

        build_env = cargo_git_build_environment(
            staging, rustup_home, rust_toolchain, host_path
        )
        for name in ("HOME", "CARGO_HOME"):
            directory = Path(build_env[name])
            directory.mkdir(mode=0o700)
            validate_owned_directory(
                directory, f"cargo-git isolated {name} for {asset_id}")

        if rust_toolchain is not None:
            install = subprocess.run(
                [
                    rustup, "toolchain", "install", rust_toolchain,
                    "--profile", "minimal", "--no-self-update",
                ],
                check=False,
                capture_output=True,
                text=True,
                env=build_env,
                timeout=900,
            )
            if install.returncode != 0:
                fail(
                    f"rustup toolchain install {rust_toolchain} failed for "
                    f"{asset_id}: {install.stderr.strip() or install.stdout.strip()}"
                )
            version = subprocess.run(
                [rustup, "run", rust_toolchain, "rustc", "--version"],
                check=False,
                capture_output=True,
                text=True,
                env=build_env,
                timeout=30,
            )
            expected_version = f"rustc {rust_toolchain} "
            if version.returncode != 0 or not version.stdout.startswith(expected_version):
                observed = version.stdout.strip() or version.stderr.strip()
                fail(
                    f"Rust toolchain mismatch for {asset_id}: expected "
                    f"{rust_toolchain}, got {observed!r}"
                )

        build = subprocess.run(
            build_command,
            check=False,
            capture_output=True,
            text=True,
            cwd=str(staging),
            env=build_env,
            timeout=1800,
        )
        if build.returncode != 0:
            policy = (
                f" with Rust {rust_toolchain}" if rust_toolchain is not None else ""
            )
            fail(
                f"cargo build --release -p {package}{policy} failed for {asset_id}: "
                f"{build.stderr.strip() or build.stdout.strip()}"
            )
        built = staging / "target" / "release" / binary_name
        try:
            built_meta = built.lstat()
        except FileNotFoundError:
            fail(
                f"cargo-git build for {asset_id} did not produce "
                f"target/release/{binary_name}"
            )
        if not stat.S_ISREG(built_meta.st_mode):
            fail(f"cargo-git product for {asset_id} is not a regular file")
        os.chmod(built, 0o755)
        write_cargo_git_build_policy(asset, staging)
        # Atomic publish: replace any incomplete previous cache tree.
        if cache_dir.exists() or cache_dir.is_symlink():
            if cache_dir.is_dir() and not cache_dir.is_symlink():
                shutil.rmtree(cache_dir)
            else:
                cache_dir.unlink()
        os.replace(staging, cache_dir)
        directory_fd = os.open(cache_dir.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
    if not binary_usable():
        fail(f"cargo-git provision for {asset_id} did not leave a usable binary")
    policy = f" rust={rust_toolchain}" if rust_toolchain is not None else ""
    print(
        f"toolchain-assets: provisioned cargo-git {asset_id} "
        f"commit={commit}{policy}"
    )
    return binary


def provision_asset(asset: dict) -> Path:
    if asset.get("format") == "cargo-git":
        return provision_cargo_git_asset(asset)
    destination = cached_asset_path(asset)
    cache_asset_parent(asset, create=True)
    try:
        destination.lstat()
        destination_present = True
    except FileNotFoundError:
        destination_present = False
    if destination_present:
        path = validate_cached_asset(asset)
        print(f"toolchain-assets: cached {asset['id']} sha256={asset['sha256']}")
        return path
    partial = destination.parent / f".{asset['id']}.partial-{os.getpid()}-{secrets.token_hex(6)}"
    digest = hashlib.sha256()
    total = 0
    try:
        request = urllib.request.Request(asset["url"], headers=request_headers(asset))
        with safe_https_open(request, timeout=60) as response, partial.open("xb") as output:
            os.chmod(partial, 0o600)
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > asset["size"]:
                    fail(f"asset {asset['id']} exceeded locked size")
                digest.update(chunk)
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        if total != asset["size"]:
            fail(f"asset {asset['id']} size mismatch: expected {asset['size']}, got {total}")
        actual = digest.hexdigest()
        if actual != asset["sha256"]:
            fail(f"asset {asset['id']} hash mismatch: expected {asset['sha256']}, got {actual}")
        os.chmod(partial, 0o444)
        os.replace(partial, destination)
        directory_fd = os.open(destination.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        validate_cached_asset(asset)
    finally:
        try:
            partial.unlink()
        except FileNotFoundError:
            pass
    print(f"toolchain-assets: provisioned {asset['id']} sha256={asset['sha256']}")
    return destination


def asset_map(lock: dict) -> dict[str, dict]:
    return {asset["id"]: asset for asset in lock["assets"]}


def selected_assets(lock: dict, group: str, requested: list[str]) -> list[dict]:
    assets = asset_map(lock)
    if requested:
        unknown = sorted(set(requested) - set(assets))
        if unknown:
            fail(f"unknown assets: {', '.join(unknown)}")
        ids = set(requested)
    elif group == "lean":
        ids = {lock["compilerToolchain"]["assetId"]}
    elif group == "external":
        ids = {record["assetId"] for record in lock["bundleFiles"]}
        for tool in lock["tools"]:
            if tool.get("sourceBuild") is not None:
                ids.add(tool["assetId"])
    else:
        ids = set(assets)
    return [asset for asset in lock["assets"] if asset["id"] in ids]


def copy_exact(handle: BinaryIO, destination: Path, expected_size: int, expected_hash: str) -> None:
    digest = hashlib.sha256()
    total = 0
    with destination.open("xb") as output:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > expected_size:
                fail(f"materialized file {destination.name} exceeded locked size")
            digest.update(chunk)
            output.write(chunk)
        output.flush()
        os.fsync(output.fileno())
    if total != expected_size:
        fail(f"materialized file {destination.name} size mismatch: expected {expected_size}, got {total}")
    actual = digest.hexdigest()
    if actual != expected_hash:
        fail(f"materialized file {destination.name} hash mismatch: {actual}")


@contextlib.contextmanager
def member_stream(asset: dict, member: str | None) -> Iterator[BinaryIO]:
    with cached_asset_snapshot(asset) as snapshot:
        if asset["format"] == "file":
            if member is not None:
                fail(f"raw asset {asset['id']} cannot select a member")
            yield snapshot
            return
        if member is None:
            fail(f"archive asset {asset['id']} requires a member")
        if asset["format"] == "tar.gz":
            with tarfile.open(fileobj=snapshot, mode="r:gz") as archive:
                matches: list[tarfile.TarInfo] = []
                count = 0
                for item in archive:
                    count += 1
                    if count > MAX_ARCHIVE_MEMBERS:
                        fail(f"asset {asset['id']} exceeds the archive member limit")
                    if item.name == member:
                        matches.append(item)
                if len(matches) != 1 or not matches[0].isfile():
                    fail(f"asset {asset['id']} does not contain one regular member {member}")
                handle = archive.extractfile(matches[0])
                if handle is None:
                    fail(f"cannot read {member} from asset {asset['id']}")
                with handle:
                    yield handle
            return
        if asset["format"] == "zip":
            with zipfile.ZipFile(snapshot) as archive:
                members = archive.infolist()
                if len(members) > MAX_ARCHIVE_MEMBERS:
                    fail(f"asset {asset['id']} exceeds the archive member limit")
                matches = [item for item in members if item.filename == member]
                if len(matches) != 1 or matches[0].is_dir():
                    fail(f"asset {asset['id']} does not contain one regular member {member}")
                mode = matches[0].external_attr >> 16
                if stat.S_ISLNK(mode):
                    fail(f"asset {asset['id']} member {member} is a symlink")
                with archive.open(matches[0], "r") as handle:
                    yield handle
            return
    fail(f"cannot materialize format {asset['format']}")


def prepare_destination(destination: Path) -> Path:
    if not destination.is_absolute():
        fail("materialization destination must be absolute")
    if destination.exists() or destination.is_symlink():
        fail(f"materialization destination already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = destination.parent / f".{destination.name}.staging-{os.getpid()}-{secrets.token_hex(6)}"
    staging.mkdir(mode=0o700)
    return staging


def parse_otool_lines(output: str) -> list[str]:
    result: list[str] = []
    for line in output.splitlines():
        if not line.startswith("\t"):
            continue
        value = line.strip().split(" (", 1)[0]
        if value:
            result.append(value)
    return result


def sha256_regular_snapshot(path: Path, expected_metadata: os.stat_result,
                            where: str) -> str:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        fail(f"cannot safely open {where}: {error}")
    with os.fdopen(descriptor, "rb", closefd=True) as handle:
        before = os.fstat(handle.fileno())
        if ((before.st_dev, before.st_ino) !=
                (expected_metadata.st_dev, expected_metadata.st_ino)):
            fail(f"{where} changed before it could be opened")
        digest = sha256_handle(handle)
        after = os.fstat(handle.fileno())
        stable_fields = ("st_dev", "st_ino", "st_mode", "st_nlink", "st_uid", "st_size")
        if any(getattr(before, field) != getattr(after, field) for field in stable_fields):
            fail(f"{where} changed while being hashed")
        return digest


def bounded_host_command(argv: list[str], *, input_bytes: bytes | None = None,
                         timeout: int = DEFAULT_HOST_COMMAND_TIMEOUT_SECONDS,
                         max_output: int = MAX_HOST_COMMAND_OUTPUT_BYTES,
                         extra_env: dict[str, str] | None = None,
                         check: bool = True) -> subprocess.CompletedProcess[str]:
    if (not argv or any(not isinstance(arg, str) or "\x00" in arg for arg in argv) or
            not argv[0].startswith("/")):
        fail("host command must use an absolute executable and valid string arguments")
    if (not isinstance(timeout, int) or timeout < 1 or
            not isinstance(max_output, int) or max_output < 1):
        fail("host command limits must be positive integers")
    if input_bytes is not None and len(input_bytes) > max_output:
        fail("host command input exceeds the byte limit")
    environment = {
        "HOME": "/var/empty",
        "LC_ALL": "C",
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TZ": "UTC",
    }
    if extra_env is not None:
        allowed = {"DYLD_PRINT_LIBRARIES"}
        if set(extra_env) - allowed:
            fail("host command requested a forbidden environment variable")
        environment.update(extra_env)
    process = subprocess.Popen(
        argv,
        stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        close_fds=True,
        start_new_session=True,
    )

    def kill_process_group() -> None:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()

    if process.stdout is None or process.stderr is None:
        kill_process_group()
        fail("host command pipes were not created")
    if input_bytes is not None:
        if process.stdin is None:
            kill_process_group()
            fail("host command input pipe was not created")
        try:
            process.stdin.write(input_bytes)
            process.stdin.close()
        except BrokenPipeError:
            pass
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    chunks: dict[str, list[bytes]] = {"stdout": [], "stderr": []}
    total = 0
    deadline = time.monotonic() + timeout
    try:
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                kill_process_group()
                fail(f"host command timed out after {timeout}s: {argv[0]}")
            events = selector.select(remaining)
            if not events:
                kill_process_group()
                fail(f"host command timed out after {timeout}s: {argv[0]}")
            for key, _ in events:
                data = os.read(key.fileobj.fileno(), min(64 * 1024, max_output + 1 - total))
                if not data:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                chunks[key.data].append(data)
                total += len(data)
                if total > max_output:
                    kill_process_group()
                    fail(f"host command output exceeded {max_output} bytes: {argv[0]}")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            kill_process_group()
            fail(f"host command timed out after {timeout}s: {argv[0]}")
        returncode = process.wait(timeout=remaining)
    finally:
        selector.close()
        if process.poll() is None:
            kill_process_group()
    try:
        stdout = b"".join(chunks["stdout"]).decode("utf-8", errors="strict")
        stderr = b"".join(chunks["stderr"]).decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        fail(f"host command emitted non-UTF-8 output: {argv[0]}")
    result = subprocess.CompletedProcess(argv, returncode, stdout, stderr)
    if check and returncode != 0:
        detail = (stderr or stdout).strip().replace("\n", " ")[:512]
        fail(f"host command failed ({returncode}): {argv[0]}: {detail}")
    return result


def extract_kat_digest(output: str, where: str) -> str:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if len(lines) != 1:
        fail(f"{where} known-answer probe must emit exactly one line")
    token = lines[0].rsplit(" ", 1)[-1].rsplit("=", 1)[-1]
    if SHA256_RE.fullmatch(token) is None:
        fail(f"{where} known-answer probe did not emit a SHA-256 digest")
    return token


def require_host_tool(tools: dict[str, dict], tool_id: str) -> dict:
    record = tools.get(tool_id)
    if record is None:
        fail(f"host profile is missing required system tool {tool_id}")
    return record


def verify_locked_regular(path: Path, expected_hash: str, where: str,
                          *, require_root_owner: bool = True) -> os.stat_result:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        fail(f"{where} is missing: {path}")
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail(f"{where} must be a regular non-symlink file: {path}")
    if require_root_owner and metadata.st_uid != 0:
        fail(f"{where} must be owned by root: {path}")
    if sha256_regular_snapshot(path, metadata, where) != expected_hash:
        fail(f"{where} hash mismatch: {path}")
    return metadata


def verify_system_tool_nodes(profile: dict) -> dict[str, dict]:
    tools = {record["id"]: record for record in profile["systemTools"]}
    for tool_id in sorted(tools):
        record = tools[tool_id]
        path = Path(record["path"])
        try:
            node = path.lstat()
        except FileNotFoundError:
            fail(f"system tool {tool_id} is missing: {path}")
        if node.st_uid != 0:
            fail(f"system tool {tool_id} pathname is not root-owned")
        if record["nodeKind"] == "regular":
            if not stat.S_ISREG(node.st_mode) or stat.S_ISLNK(node.st_mode):
                fail(f"system tool {tool_id} node kind mismatch")
        elif not stat.S_ISLNK(node.st_mode):
            fail(f"system tool {tool_id} node kind mismatch")
        if stat.S_ISLNK(node.st_mode):
            if os.readlink(path) != record["linkTarget"]:
                fail(f"system tool {tool_id} symlink target mismatch")
        try:
            resolved = path.resolve(strict=True)
        except (FileNotFoundError, RuntimeError) as error:
            fail(f"system tool {tool_id} cannot be resolved: {error}")
        if str(resolved) != record["resolvedPath"]:
            fail(f"system tool {tool_id} resolved path mismatch: {resolved}")
        resolved_metadata = verify_locked_regular(
            resolved, record["sha256"], f"system tool {tool_id}")
        if resolved_metadata.st_nlink != record["resolvedNlink"]:
            fail(f"system tool {tool_id} resolved link count mismatch")
        if stat.S_IMODE(resolved_metadata.st_mode) != int(record["mode"], 8):
            fail(f"system tool {tool_id} resolved mode mismatch")
        after = path.lstat()
        if any(getattr(node, field) != getattr(after, field)
               for field in ("st_dev", "st_ino", "st_mode", "st_nlink", "st_uid", "st_size")):
            fail(f"system tool {tool_id} pathname changed during verification")
        if stat.S_ISLNK(after.st_mode) and os.readlink(path) != record["linkTarget"]:
            fail(f"system tool {tool_id} symlink changed during verification")
    return tools


def verify_code_signatures(tools: dict[str, dict], paths: list[Path]) -> None:
    codesign = Path(require_host_tool(tools, "codesign")["resolvedPath"])
    for path in paths:
        bounded_host_command([str(codesign), "--verify", "--strict", str(path)])


def parse_single_prefixed_line(output: str, prefix: str, where: str) -> str:
    matches = [line[len(prefix):] for line in output.splitlines() if line.startswith(prefix)]
    if len(matches) != 1 or not matches[0]:
        fail(f"cannot parse {where}")
    return matches[0]


def normalized_csrutil_state(output: str, prefix: str, where: str) -> str:
    match = re.fullmatch(re.escape(prefix) + r" (enabled|disabled)\.?\n?", output)
    if match is None:
        fail(f"cannot parse {where}")
    return match.group(1)


def normalized_volume_seal(output: bytes) -> str:
    try:
        record = plistlib.loads(output)
    except (plistlib.InvalidFileException, ValueError) as error:
        fail(f"cannot parse diskutil seal evidence: {error}")
    if not isinstance(record, dict) or "Sealed" not in record:
        fail("diskutil seal evidence is missing Sealed")
    observed = record["Sealed"]
    if observed is True or observed in {"Yes", "Sealed"}:
        return "sealed"
    if observed is False or observed in {"No", "Unsealed"}:
        return "unsealed"
    if observed == "Broken":
        return "broken"
    fail(f"diskutil returned an unsupported seal state: {observed!r}")


def path_mutable_by_current_user(path: Path, label: str) -> bool:
    candidate = path
    while True:
        try:
            metadata = candidate.lstat()
        except FileNotFoundError:
            fail(f"{label} pathname ancestor is missing: {candidate}")
        if stat.S_ISLNK(metadata.st_mode):
            fail(f"{label} pathname ancestor must not be a symlink: {candidate}")
        if candidate == path:
            if not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
                fail(f"{label} pathname must be a directory or regular file: {candidate}")
        elif not stat.S_ISDIR(metadata.st_mode):
            fail(f"{label} pathname ancestor must be a directory: {candidate}")
        if metadata.st_uid != 0:
            return True
        if os.access(candidate, os.W_OK | os.X_OK, effective_ids=True):
            return True
        parent = candidate.parent
        if parent == candidate:
            return False
        candidate = parent


def xcode_path_mutable_by_current_user(xcode_app: Path) -> bool:
    return path_mutable_by_current_user(xcode_app, "Xcode")


def verify_runtime_probe(path: Path, args: list[str], expected_line: str,
                         allowed_roots: tuple[str, ...], where: str) -> None:
    probe = bounded_host_command(
        [str(path), *args], extra_env={"DYLD_PRINT_LIBRARIES": "1"},
    )
    output = probe.stdout + probe.stderr
    non_dyld_lines = [
        line for line in output.splitlines()
        if line and not line.startswith("dyld[")
    ]
    if expected_line not in non_dyld_lines:
        fail(f"{where} version mismatch")
    loaded: list[str] = []
    for line in probe.stderr.splitlines():
        match = re.fullmatch(r"dyld\[\d+\]: <[^>]+> (/.+)", line)
        if match is not None:
            loaded.append(match.group(1))
    if not loaded:
        fail(f"{where} runtime load observation was empty")
    for loaded_path in loaded:
        if not loaded_path.startswith("/") or posixpath.normpath(loaded_path) != loaded_path:
            fail(f"{where} runtime emitted a non-canonical load path: {loaded_path}")
        if not loaded_path.startswith(allowed_roots):
            fail(f"{where} runtime escaped allowed roots: {loaded_path}")


def host_platform_kind() -> str:
    kind = os.uname().sysname.lower()
    if kind not in {"darwin", "linux"}:
        fail(f"unsupported host platform kind: {kind}")
    return kind


def verify_host(profile: dict, *, require_eligible: bool) -> None:
    kind = host_profile_kind(profile)
    host_kind = host_platform_kind()
    if kind != host_kind:
        fail(f"host profile {profile['id']} is a {kind} profile; this host is {host_kind}")
    if kind == "darwin":
        verify_host_darwin(profile, require_eligible=require_eligible)
    else:
        verify_host_linux(profile, require_eligible=require_eligible)


def verify_host_darwin(profile: dict, *, require_eligible: bool) -> None:
    tools = verify_system_tool_nodes(profile)
    required_ids = {
        "codesign", "csrutil", "diskutil", "openssl", "sw_vers", "sysctl",
        "uname", "xcode-select", "xcodebuild", "xcrun",
    }
    for tool_id in sorted(required_ids):
        require_host_tool(tools, tool_id)
    verify_code_signatures(
        tools, [Path(record["resolvedPath"]) for record in profile["systemTools"]],
    )

    bootstrap = profile["digestBootstrap"]
    digest_probe = bounded_host_command(
        [bootstrap["path"], "dgst", "-sha256"],
        input_bytes=bootstrap["knownAnswerInput"].encode("utf-8"),
    )
    if extract_kat_digest(digest_probe.stdout, "digest bootstrap") != \
            bootstrap["knownAnswerSha256"]:
        fail("digest bootstrap known-answer test failed")

    platform = profile["platform"]
    sw_vers = require_host_tool(tools, "sw_vers")["resolvedPath"]
    uname = require_host_tool(tools, "uname")["resolvedPath"]
    sysctl = require_host_tool(tools, "sysctl")["resolvedPath"]
    csrutil = require_host_tool(tools, "csrutil")["resolvedPath"]
    diskutil = require_host_tool(tools, "diskutil")["resolvedPath"]
    observed_platform = {
        "productVersion": bounded_host_command([sw_vers, "-productVersion"]).stdout.strip(),
        "buildVersion": bounded_host_command([sw_vers, "-buildVersion"]).stdout.strip(),
        "kernelRelease": bounded_host_command([uname, "-r"]).stdout.strip(),
        "arch": bounded_host_command([uname, "-m"]).stdout.strip(),
    }
    translated_text = bounded_host_command(
        [sysctl, "-in", "sysctl.proc_translated"]
    ).stdout.strip()
    if translated_text not in {"0", "1"}:
        fail("sysctl.proc_translated must be 0 or 1")
    observed_platform["procTranslated"] = translated_text == "1"
    observed_platform["sip"] = normalized_csrutil_state(
        bounded_host_command([csrutil, "status"]).stdout,
        "System Integrity Protection status:", "SIP status",
    )
    observed_platform["authenticatedRoot"] = normalized_csrutil_state(
        bounded_host_command([csrutil, "authenticated-root", "status"]).stdout,
        "Authenticated Root status:", "authenticated-root status",
    )
    seal_probe = bounded_host_command([diskutil, "info", "-plist", "/"])
    observed_platform["systemVolumeSeal"] = normalized_volume_seal(
        seal_probe.stdout.encode("utf-8"))
    if observed_platform != platform:
        fail(f"host platform observation mismatch: expected={platform}, observed={observed_platform}")

    developer = profile["developerTools"]
    xcode_app = Path(developer["xcodeAppPath"])
    developer_dir = Path(developer["developerDir"])
    for path, label in ((xcode_app, "Xcode app"), (developer_dir, "developer directory")):
        metadata = path.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            fail(f"{label} must be a non-symlink directory")
        if metadata.st_uid != 0:
            fail(f"{label} must be root-owned")
        if path.resolve(strict=True) != path:
            fail(f"{label} pathname must be canonical")
    mutable = xcode_path_mutable_by_current_user(xcode_app)
    if mutable != developer["xcodeMutableByCurrentUser"]:
        fail("Xcode current-user mutability observation mismatch")

    codesign = Path(require_host_tool(tools, "codesign")["resolvedPath"])
    bounded_host_command(
        [str(codesign), "--verify", "--deep", "--strict", str(xcode_app)],
        timeout=XCODE_VERIFY_TIMEOUT_SECONDS,
    )
    signature = bounded_host_command(
        [str(codesign), "-d", "--verbose=4", str(xcode_app)],
    ).stderr
    signature_observed = {
        "xcodeIdentifier": parse_single_prefixed_line(signature, "Identifier=", "Xcode identifier"),
        "xcodeTeamIdentifier": parse_single_prefixed_line(
            signature, "TeamIdentifier=", "Xcode team identifier"),
        "xcodeCdHash": parse_single_prefixed_line(signature, "CDHash=", "Xcode CDHash"),
    }
    requirement_probe = bounded_host_command(
        [str(codesign), "-d", "-r-", str(xcode_app)],
    )
    requirement_output = requirement_probe.stdout + requirement_probe.stderr
    signature_observed["xcodeDesignatedRequirement"] = parse_single_prefixed_line(
        requirement_output, "designated => ", "Xcode designated requirement")
    for field, observed in signature_observed.items():
        if observed != developer[field]:
            fail(f"{field} mismatch")

    xcode_select = require_host_tool(tools, "xcode-select")["resolvedPath"]
    xcodebuild = require_host_tool(tools, "xcodebuild")["resolvedPath"]
    xcrun = require_host_tool(tools, "xcrun")["resolvedPath"]
    if bounded_host_command([xcode_select, "-p"]).stdout.strip() != str(developer_dir):
        fail("xcode-select developer directory mismatch")
    xcode_lines = [
        line for line in bounded_host_command([xcodebuild, "-version"]).stdout.splitlines()
        if line
    ]
    if xcode_lines != [
            f"Xcode {developer['xcodeVersion']}",
            f"Build version {developer['xcodeBuildVersion']}"]:
        fail("xcodebuild version mismatch")
    xcrun_probes = {
        "git": developer["gitPath"],
        "llvm-otool": developer["otoolPath"],
        "python3": developer["pythonDispatchPath"],
    }
    for name, expected in xcrun_probes.items():
        observed = bounded_host_command([xcrun, "--find", name]).stdout.strip()
        if observed != expected:
            fail(f"xcrun resolved path mismatch for {name}: {observed}")

    python_dispatch = Path(developer["pythonDispatchPath"])
    try:
        dispatch_resolved = python_dispatch.resolve(strict=True)
    except (FileNotFoundError, RuntimeError) as error:
        fail(f"Python dispatch path cannot be resolved: {error}")
    if str(dispatch_resolved) != developer["pythonPath"]:
        fail("Python dispatch path does not resolve to locked Python")
    if python_dispatch.lstat().st_uid != 0:
        fail("Python dispatch pathname must be root-owned")

    developer_paths = [
        (Path(developer["gitPath"]), developer["gitSha256"], "Xcode Git"),
        (Path(developer["otoolPath"]), developer["otoolSha256"], "Xcode otool"),
        (Path(developer["pythonPath"]), developer["pythonSha256"], "Xcode Python"),
    ]
    for path, expected_hash, label in developer_paths:
        verify_locked_regular(path, expected_hash, label)
    verify_code_signatures(tools, [path for path, _, _ in developer_paths])
    runtime_roots = tuple(
        developer["allowedRuntimeRoots"] + profile["systemRuntime"]["allowedLoadRoots"])
    verify_runtime_probe(
        Path(developer["gitPath"]), ["--version"], developer["gitVersion"],
        runtime_roots, "Xcode Git",
    )
    verify_runtime_probe(
        Path(developer["otoolPath"]), ["--version"], developer["otoolVersion"],
        runtime_roots, "Xcode otool",
    )
    verify_runtime_probe(
        Path(developer["pythonPath"]), ["--version"], developer["pythonVersion"],
        runtime_roots, "Xcode Python",
    )

    summary = {
        "attestationScope": "local-observation-only",
        "eligibleForHermetic": profile["eligibleForHermetic"],
        "hostProfileId": profile["id"],
        "platform": observed_platform,
        "remoteAttestation": False,
        "xcode": {
            "buildVersion": developer["xcodeBuildVersion"],
            "cdHash": developer["xcodeCdHash"],
            "identifier": developer["xcodeIdentifier"],
            "mutableByCurrentUser": mutable,
            "version": developer["xcodeVersion"],
        },
    }
    if require_eligible and not profile["eligibleForHermetic"]:
        fail(f"PF-HOST-INELIGIBLE: {profile['id']}: {profile['ineligibilityReason']}")
    print(json.dumps(summary, sort_keys=True, separators=(",", ":")))


SECURE_BOOT_EFIVAR = Path(
    "/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c")


def parse_os_release_text(text: str) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        data[key] = value
    return data


def read_os_release() -> dict[str, str]:
    for candidate in (Path("/etc/os-release"), Path("/usr/lib/os-release")):
        try:
            return parse_os_release_text(candidate.read_text(encoding="utf-8"))
        except FileNotFoundError:
            continue
    fail("no os-release file found")


def observe_secure_boot() -> str:
    try:
        data = SECURE_BOOT_EFIVAR.read_bytes()
    except (FileNotFoundError, PermissionError):
        return "unavailable"
    if len(data) < 5:
        fail("secure boot efivar is truncated")
    return "enabled" if data[-1] == 0x01 else "disabled"


def verify_host_linux(profile: dict, *, require_eligible: bool) -> None:
    tools = verify_system_tool_nodes(profile)
    required_ids = {"git", "openssl", "python3", "readelf", "uname"}
    for tool_id in sorted(required_ids):
        require_host_tool(tools, tool_id)

    bootstrap = profile["digestBootstrap"]
    digest_probe = bounded_host_command(
        [bootstrap["path"], "dgst", "-sha256"],
        input_bytes=bootstrap["knownAnswerInput"].encode("utf-8"),
    )
    if extract_kat_digest(digest_probe.stdout, "digest bootstrap") != \
            bootstrap["knownAnswerSha256"]:
        fail("digest bootstrap known-answer test failed")

    platform = profile["platform"]
    uname = require_host_tool(tools, "uname")["resolvedPath"]
    os_release = read_os_release()
    observed_platform = {
        "osReleaseId": os_release.get("ID", ""),
        "osReleaseVersionId": os_release.get("VERSION_ID", ""),
        "kernelRelease": bounded_host_command([uname, "-r"]).stdout.strip(),
        "arch": bounded_host_command([uname, "-m"]).stdout.strip(),
        "secureBoot": observe_secure_boot(),
    }
    if observed_platform != platform:
        fail(f"host platform observation mismatch: expected={platform}, observed={observed_platform}")

    distro = profile["distroTools"]
    distro_paths = [
        (Path(distro["gitPath"]), distro["gitSha256"], "distro Git"),
        (Path(distro["pythonPath"]), distro["pythonSha256"], "distro Python"),
        (Path(distro["readelfPath"]), distro["readelfSha256"], "distro readelf"),
    ]
    for path, expected_hash, label in distro_paths:
        verify_locked_regular(path, expected_hash, label)
    version_probes = [
        (Path(distro["gitPath"]), ["--version"], distro["gitVersion"], "distro Git"),
        (Path(distro["pythonPath"]), ["--version"], distro["pythonVersion"], "distro Python"),
        (Path(distro["readelfPath"]), ["--version"], distro["readelfVersion"],
         "distro readelf"),
    ]
    for path, args, expected_line, label in version_probes:
        output = bounded_host_command([str(path), *args]).stdout
        lines = [line for line in output.splitlines() if line]
        if expected_line not in lines:
            fail(f"{label} version mismatch")
    mutable = any(
        path_mutable_by_current_user(path, label)
        for path, _, label in distro_paths
    )
    if mutable != distro["toolsMutableByCurrentUser"]:
        fail("distro tools current-user mutability observation mismatch")
    if profile["eligibleForHermetic"]:
        eligible_paths = [
            (Path(record["resolvedPath"]), f"system tool {record['id']}")
            for record in profile["systemTools"]
        ]
        eligible_paths.append((Path(bootstrap["path"]), "digest bootstrap"))
        for path, label in eligible_paths:
            if path_mutable_by_current_user(path, label):
                fail(f"{label} pathname is replaceable by the current user: {path}")

    summary = {
        "attestationScope": "local-observation-only",
        "eligibleForHermetic": profile["eligibleForHermetic"],
        "hostProfileId": profile["id"],
        "platform": observed_platform,
        "remoteAttestation": False,
        "trustRoot": "secure-boot+distro-package-integrity+pinned-digests "
                     "(weaker than Apple SSV; no codesign equivalence on linux)",
    }
    if require_eligible and not profile["eligibleForHermetic"]:
        fail(f"PF-HOST-INELIGIBLE: {profile['id']}: {profile['ineligibilityReason']}")
    print(json.dumps(summary, sort_keys=True, separators=(",", ":")))


def source_build_executables(lock: dict) -> dict[str, dict]:
    """Map executable relative path → tool record for sourceBuild tools."""

    result: dict[str, dict] = {}
    for tool in lock["tools"]:
        if tool.get("sourceBuild") is None:
            continue
        path = tool["executable"]
        if path in result:
            fail(f"duplicate sourceBuild executable path: {path}")
        result[path] = tool
    return result


def verify_external_tree(root: Path, bundle: dict[str, dict],
                         source_tools: dict[str, dict] | None = None) -> Path:
    source_tools = source_tools or {}
    require_normalized_absolute_path(root, "external tool root")
    try:
        root_metadata = root.lstat()
    except FileNotFoundError:
        fail(f"external tool root is missing: {root}")
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        fail(f"external tool root is not a regular directory: {root}")
    if root_metadata.st_uid != os.getuid():
        fail(f"external tool root is not owned by the current user: {root}")
    if stat.S_IMODE(root_metadata.st_mode) & 0o022:
        fail(f"external tool root is group/world writable: {root}")
    canonical_root = root.resolve(strict=True)
    canonical_metadata = canonical_root.lstat()
    if ((canonical_metadata.st_dev, canonical_metadata.st_ino) !=
            (root_metadata.st_dev, root_metadata.st_ino)):
        fail(f"external tool root changed during canonicalization: {root}")
    root = canonical_root

    expected_files = set(bundle) | set(source_tools)
    expected_directories: set[str] = set()
    for relative in expected_files:
        parent = PurePosixPath(relative).parent
        while parent != PurePosixPath("."):
            expected_directories.add(parent.as_posix())
            parent = parent.parent

    actual_files: set[str] = set()
    actual_directories: set[str] = set()

    def walk(directory: Path, relative_directory: PurePosixPath) -> None:
        try:
            entries = list(os.scandir(directory))
        except OSError as error:
            fail(f"cannot scan external tool directory {directory}: {error}")
        for entry in entries:
            name = entry.name
            if name in {"", ".", ".."} or "/" in name or "\x00" in name:
                fail(f"external tool root contains an unsafe entry name: {name!r}")
            relative_path = (relative_directory / name
                             if relative_directory != PurePosixPath(".")
                             else PurePosixPath(name))
            relative = relative_path.as_posix()
            try:
                metadata = entry.stat(follow_symlinks=False)
            except OSError as error:
                fail(f"cannot inspect external bundle path {relative}: {error}")
            if stat.S_ISLNK(metadata.st_mode):
                fail(f"external bundle symlink is forbidden: {relative}")
            if stat.S_ISDIR(metadata.st_mode):
                if relative not in expected_directories:
                    fail(f"external tool root contains unexpected directory: {relative}")
                if metadata.st_uid != os.getuid():
                    fail(f"external bundle directory owner mismatch: {relative}")
                if stat.S_IMODE(metadata.st_mode) & 0o022:
                    fail(f"external bundle directory is group/world writable: {relative}")
                actual_directories.add(relative)
                walk(Path(entry.path), relative_path)
                continue
            if not stat.S_ISREG(metadata.st_mode):
                fail(f"external bundle special node is forbidden: {relative}")
            if relative not in expected_files:
                fail(f"external tool root contains unexpected file: {relative}")
            if metadata.st_nlink != 1:
                fail(f"external bundle file must have exactly one hard link: {relative}")
            if metadata.st_uid != os.getuid():
                fail(f"external bundle file owner mismatch: {relative}")
            if relative in source_tools:
                # sourceBuild: mode must be executable 0555; size/hash not locked
                mode = stat.S_IMODE(metadata.st_mode)
                if mode != 0o555:
                    fail(f"sourceBuild tool mode mismatch: {relative} mode={mode:04o}")
                if not os.access(Path(entry.path), os.X_OK):
                    fail(f"sourceBuild tool is not executable: {relative}")
            else:
                record = bundle[relative]
                if metadata.st_size != record["size"]:
                    fail(f"external bundle size mismatch: {relative}")
                if sha256_regular_snapshot(Path(entry.path), metadata,
                                           f"external bundle path {relative}") != record["sha256"]:
                    fail(f"external bundle hash mismatch: {relative}")
                if stat.S_IMODE(metadata.st_mode) != int(record["mode"], 8):
                    fail(f"external bundle mode mismatch: {relative}")
            actual_files.add(relative)

    walk(root, PurePosixPath("."))
    if actual_files != expected_files:
        fail("external tool root has missing files")
    if actual_directories != expected_directories:
        fail("external tool root has missing directories")
    return root


def verify_external_macho_closure(lock: dict, host_lock: dict, root: Path) -> None:
    profile = host_lock["profiles"][0]
    developer = profile["developerTools"]
    otool = Path(developer["otoolPath"])
    if not otool.is_file() or otool.is_symlink() or sha256_file(otool) != developer["otoolSha256"]:
        fail("effective Xcode otool does not match the host profile")
    system_roots = tuple(lock["machoPolicy"]["allowedSystemLoadRoots"])
    for record in lock["machoPolicy"]["files"]:
        path = root / record["path"]
        loads = subprocess.run(
            [str(otool), "-L", str(path)], check=True, capture_output=True, text=True,
            env={"LC_ALL": "C"}, timeout=10,
        )
        observed = parse_otool_lines(loads.stdout)
        install_id = record["installId"]
        if install_id is not None:
            ids = subprocess.run(
                [str(otool), "-D", str(path)], check=True, capture_output=True, text=True,
                env={"LC_ALL": "C"}, timeout=10,
            )
            id_lines = [line.strip() for line in ids.stdout.splitlines()[1:] if line.strip()]
            if id_lines != [install_id]:
                fail(f"Mach-O install ID mismatch for {record['path']}")
            observed = [load for load in observed if load != install_id]
        expected_external = {edge["installName"] for edge in record["externalLoads"]}
        observed_external = {load for load in observed if not load.startswith(system_roots)}
        if observed_external != expected_external:
            fail(f"Mach-O external loads mismatch for {record['path']}: {sorted(observed_external)}")


def verify_external_elf_closure(lock: dict, host_lock: dict, root: Path) -> None:
    readelf = locked_readelf(host_lock)
    for record in lock["elfPolicy"]["files"]:
        path = root / record["path"]
        observed_needed, observed_runpath = readelf_dynamic(readelf, path)
        expected_needed = {edge["soname"] for edge in record["needed"]}
        if observed_needed != expected_needed:
            fail(f"ELF needed mismatch for {record['path']}: {sorted(observed_needed)}")
        if record["runpath"] != observed_runpath:
            fail(f"ELF runpath mismatch for {record['path']}")


def verify_external(lock: dict, host_lock: dict, root: Path) -> None:
    bundle = {record["path"]: record for record in lock["bundleFiles"]}
    source_tools = source_build_executables(lock)
    root = verify_external_tree(root, bundle, source_tools)
    darwin_probe = is_darwin_tool_lock(lock)
    if darwin_probe:
        verify_external_macho_closure(lock, host_lock, root)
        system_roots = tuple(lock["machoPolicy"]["allowedSystemLoadRoots"])
    else:
        verify_external_elf_closure(lock, host_lock, root)
        system_roots = tuple(lock["elfPolicy"]["allowedSystemLoadRoots"])

    tool_by_id = {tool["id"]: tool for tool in lock["tools"]}
    for tool_id in sorted(tool_by_id):
        tool = tool_by_id[tool_id]
        is_source = tool.get("sourceBuild") is not None
        if darwin_probe:
            environment = {
                "HOME": "/var/empty",
                "LC_ALL": "C",
                "PATH": "/usr/bin:/bin",
                "TZ": "UTC",
                "DYLD_LIBRARY_PATH": str(root / "lib"),
                "DYLD_PRINT_LIBRARIES": "1",
            }
        else:
            environment = {
                "HOME": "/var/empty",
                "LC_ALL": "C",
                "PATH": "/usr/bin:/bin",
                "TZ": "UTC",
                "LD_LIBRARY_PATH": str(root / "lib"),
            }
        probe = subprocess.run(
            [str(root / tool["executable"]), *tool["versionArgs"]],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
            timeout=30 if is_source else 10,
        )
        observed_version = probe.stdout + probe.stderr
        if probe.returncode != 0 or tool["expectedVersion"] not in observed_version:
            fail(f"external tool version probe failed for {tool_id}")
        if is_source:
            # sourceBuild tools: version probe is the authority; skip Mach-O/ELF
            # policy join (executable is outside bundleFiles).
            continue
        if darwin_probe:
            loaded: set[str] = set()
            for line in probe.stderr.splitlines():
                match = re.fullmatch(r"dyld\[\d+\]: <[^>]+> (/.+)", line)
                if match is not None:
                    loaded.add(match.group(1))
            if not loaded:
                fail(f"DYLD load observation was empty for {tool_id}")
            for text in loaded:
                if text == str(root / tool["executable"]):
                    continue
                if text.startswith(str(root) + "/") or text.startswith(system_roots):
                    continue
                fail(f"external tool {tool_id} loaded outside its closure: {text}")
            macho = next(item for item in lock["machoPolicy"]["files"]
                         if item["path"] == tool["executable"])
            for edge in macho["externalLoads"]:
                required = str((root / edge["bundlePath"]).resolve())
                if required not in {str(Path(text).resolve()) for text in loaded}:
                    fail(f"external tool {tool_id} did not load bundled {edge['bundlePath']}")
        else:
            trace_environment = dict(environment)
            trace_environment["LD_TRACE_LOADED_OBJECTS"] = "1"
            trace = subprocess.run(
                [str(root / tool["executable"])],
                check=False,
                capture_output=True,
                text=True,
                env=trace_environment,
                timeout=10,
            )
            loaded = parse_ld_trace(trace.stdout)
            elf_record = next(item for item in lock["elfPolicy"]["files"]
                              if item["path"] == tool["executable"])
            expected_system = {
                edge["soname"] for edge in elf_record["needed"]
                if edge["bundlePath"] is None
            }
            if expected_system and not loaded:
                fail(f"LD load observation was empty for {tool_id}")
            for text in loaded:
                if text.startswith(str(root) + "/") or text.startswith(system_roots):
                    continue
                fail(f"external tool {tool_id} loaded outside its closure: {text}")
            resolved_loaded = {str(Path(text).resolve()) for text in loaded}
            for edge in elf_record["needed"]:
                if edge["bundlePath"] is None:
                    continue
                required = str((root / edge["bundlePath"]).resolve())
                if required not in resolved_loaded:
                    fail(f"external tool {tool_id} did not load bundled {edge['bundlePath']}")
    if darwin_probe:
        print(f"toolchain-assets: verified Mach-O and runtime closure {root}")
    else:
        print(f"toolchain-assets: verified ELF and runtime closure {root}")


def materialize_source_build_tools(lock: dict, staging: Path) -> None:
    assets = asset_map(lock)
    for tool in lock["tools"]:
        if tool.get("sourceBuild") is None:
            continue
        asset = assets[tool["assetId"]]
        if asset["format"] != "cargo-git":
            fail(f"sourceBuild tool {tool['id']} asset is not cargo-git")
        binary = cargo_git_binary_path(asset)
        try:
            metadata = binary.lstat()
        except FileNotFoundError:
            fail(
                f"cache miss for cargo-git {asset['id']}; "
                "run toolchain-assets provision --group external"
            )
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            fail(f"cargo-git product for {asset['id']} is not a regular file")
        if not cargo_git_cached_policy_matches(asset, cargo_git_cache_root(asset)):
            fail(
                f"cargo-git build policy mismatch for {asset['id']}; "
                "run toolchain-assets provision --group external"
            )
        output = staging / tool["executable"]
        output.parent.mkdir(parents=True, exist_ok=True)
        # Copy without hash pin; size is whatever cargo produced.
        with binary.open("rb") as handle, output.open("xb") as dest:
            shutil.copyfileobj(handle, dest)
            dest.flush()
            os.fsync(dest.fileno())
        os.chmod(output, 0o555)


def materialize_external(lock: dict, host_lock: dict, destination: Path) -> None:
    assets = asset_map(lock)
    staging = prepare_destination(destination)
    try:
        for record in lock["bundleFiles"]:
            output = staging / record["path"]
            output.parent.mkdir(parents=True, exist_ok=True)
            with member_stream(assets[record["assetId"]], record["member"]) as handle:
                copy_exact(handle, output, record["size"], record["sha256"])
            os.chmod(output, int(record["mode"], 8))
        materialize_source_build_tools(lock, staging)
        verify_external(lock, host_lock, staging)
        os.replace(staging, destination)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print(f"toolchain-assets: materialized external tool root {destination}")


def safe_zip_name(name: str, root: str) -> PurePosixPath | None:
    if "\x00" in name or "\\" in name or name.startswith("/"):
        fail(f"unsafe Lean ZIP path: {name!r}")
    try:
        encoded = name.encode("ascii")
    except UnicodeEncodeError:
        fail(f"Lean ZIP paths must be ASCII: {name!r}")
    if len(encoded) > MAX_ZIP_ENTRY_NAME_BYTES:
        fail(f"Lean ZIP path exceeds {MAX_ZIP_ENTRY_NAME_BYTES} bytes: {name!r}")
    path = PurePosixPath(name)
    if (path.as_posix() != name or
            any(part in {"", ".", ".."} for part in path.parts)):
        fail(f"non-normal Lean ZIP path: {name!r}")
    if not path.parts or path.parts[0] != root:
        fail(f"Lean ZIP has an unexpected top-level path: {name!r}")
    if len(path.parts) == 1:
        return None
    return PurePosixPath(*path.parts[1:])


def validate_lean_zip(archive: zipfile.ZipFile, compiler: dict,
                      asset_id: str) -> list[tuple[zipfile.ZipInfo, str | None]]:
    """Validate the complete central directory before writing any output."""

    members = archive.infolist()
    if len(members) != compiler["entryCount"]:
        fail(f"asset {asset_id} ZIP entry count mismatch: expected "
             f"{compiler['entryCount']}, got {len(members)}")
    metadata_total = len(archive.comment)
    if metadata_total > MAX_ZIP_TOTAL_METADATA_BYTES:
        fail(f"asset {asset_id} ZIP metadata exceeds the limit")

    root_entry = compiler["archiveRoot"] + "/"
    root_count = 0
    unpacked_total = 0
    manifest: dict[str, str] = {}
    validated: list[tuple[zipfile.ZipInfo, str | None]] = []
    for info in members:
        name = info.filename
        is_directory = info.is_dir()
        if is_directory:
            if not name.endswith("/") or name.endswith("//"):
                fail(f"Lean ZIP has a malformed directory path: {name!r}")
            normalized_name = name[:-1]
        else:
            if name.endswith("/"):
                fail(f"Lean ZIP has a malformed file path: {name!r}")
            normalized_name = name

        relative = safe_zip_name(normalized_name, compiler["archiveRoot"])
        metadata_size = (46 + len(name.encode("ascii")) + len(info.extra) +
                         len(info.comment))
        if metadata_size > MAX_ZIP_ENTRY_METADATA_BYTES:
            fail(f"Lean ZIP entry metadata exceeds the limit: {name!r}")
        metadata_total += metadata_size
        if metadata_total > MAX_ZIP_TOTAL_METADATA_BYTES:
            fail(f"asset {asset_id} ZIP metadata exceeds the limit")
        if info.flag_bits & 0x1:
            fail(f"encrypted Lean ZIP entry is forbidden: {name!r}")
        if info.create_system != 3:
            fail(f"Lean ZIP entry lacks Unix metadata: {name!r}")
        mode = info.external_attr >> 16
        if mode & 0o7000:
            fail(f"Lean ZIP privilege mode bits are forbidden: {name!r}")
        file_type = stat.S_IFMT(mode)
        if is_directory:
            if file_type != stat.S_IFDIR or info.file_size != 0:
                fail(f"Lean ZIP directory metadata is invalid: {name!r}")
        elif file_type != stat.S_IFREG:
            fail(f"Lean ZIP entry is not a regular file: {name!r}")

        if relative is None:
            if name != root_entry or not is_directory:
                fail(f"Lean ZIP root entry is malformed: {name!r}")
            root_count += 1
            validated.append((info, None))
            continue
        normalized = relative.as_posix()
        if normalized in manifest:
            fail(f"duplicate Lean ZIP path: {normalized}")
        manifest[normalized] = "directory" if is_directory else "file"
        if not is_directory:
            unpacked_total += info.file_size
            if unpacked_total > compiler["unpackedSize"]:
                fail(f"asset {asset_id} exceeded locked unpacked size")
        validated.append((info, normalized))

    if root_count != 1:
        fail(f"asset {asset_id} must contain exactly one explicit archive root")
    if len(manifest) != compiler["entryCount"] - 1:
        fail(f"asset {asset_id} ZIP tree entry count mismatch")
    if unpacked_total != compiler["unpackedSize"]:
        fail(f"asset {asset_id} unpacked size mismatch: expected "
             f"{compiler['unpackedSize']}, got {unpacked_total}")
    for path, kind in manifest.items():
        parent = PurePosixPath(path).parent
        while parent != PurePosixPath("."):
            parent_text = parent.as_posix()
            if manifest.get(parent_text) != "directory":
                fail(f"Lean ZIP omits or conflicts with parent directory {parent_text}")
            parent = parent.parent
        if kind == "directory" and not any(
                candidate.startswith(path + "/") for candidate in manifest if candidate != path):
            # Empty directories are permitted; this branch documents that they remain part
            # of the exact final tree rather than being discarded.
            continue
    return validated


def extract_lean_zip(archive: zipfile.ZipFile,
                     validated: list[tuple[zipfile.ZipInfo, str | None]],
                     staging: Path, expected_total: int) -> dict[str, dict]:
    manifest: dict[str, dict] = {}
    for info, relative in validated:
        if relative is None:
            continue
        is_directory = info.is_dir()
        archive_mode = info.external_attr >> 16
        manifest[relative] = {
            "kind": "directory" if is_directory else "file",
            "size": 0 if is_directory else info.file_size,
            "mode": 0o555 if is_directory or archive_mode & 0o111 else 0o444,
        }

    directories = sorted(
        (path for path, record in manifest.items() if record["kind"] == "directory"),
        key=lambda path: (len(PurePosixPath(path).parts), path),
    )
    for relative in directories:
        (staging / relative).mkdir()

    total = 0
    for info, relative in validated:
        if relative is None or info.is_dir():
            continue
        output = staging / relative
        written = 0
        digest = hashlib.sha256()
        with archive.open(info, "r") as source, output.open("xb") as target:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                written += len(chunk)
                total += len(chunk)
                if written > info.file_size or total > expected_total:
                    fail(f"Lean ZIP output exceeded locked size at {relative}")
                digest.update(chunk)
                target.write(chunk)
        if written != info.file_size:
            fail(f"Lean ZIP output size mismatch at {relative}")
        manifest[relative]["sha256"] = digest.hexdigest()
        os.chmod(output, manifest[relative]["mode"])
    if total != expected_total:
        fail(f"Lean ZIP total output mismatch: expected {expected_total}, got {total}")
    for relative in reversed(directories):
        os.chmod(staging / relative, manifest[relative]["mode"])
    os.chmod(staging, 0o555)
    return manifest


def verify_extracted_file_witness(root: Path, relative: str, record: dict,
                                  where: str) -> str:
    """Bind one extracted file snapshot to its verified ZIP member bytes."""

    root_text = str(root)
    if (not root.is_absolute() or root_text in {"/", "//"} or
            root_text.startswith("//") or "\x00" in root_text or
            posixpath.normpath(root_text) != root_text):
        fail(f"{where} root must be a normalized absolute path")
    relative = safe_relative(relative, f"{where} path")
    if type(record) is not dict or set(record) != {"kind", "size", "mode", "sha256"}:
        fail(f"{where} witness fields are not exact")
    if record["kind"] != "file":
        fail(f"{where} witness must describe a file")
    expected_size = record["size"]
    expected_mode = record["mode"]
    expected_digest = record["sha256"]
    if type(expected_size) is not int or expected_size < 0:
        fail(f"{where} size witness is invalid")
    if type(expected_mode) is not int or expected_mode not in {0o444, 0o555}:
        fail(f"{where} mode witness is invalid")
    if type(expected_digest) is not str or SHA256_RE.fullmatch(expected_digest) is None:
        fail(f"{where} digest witness is invalid")

    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    file_flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NONBLOCK", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    stable_fields = (
        "st_dev", "st_ino", "st_mode", "st_nlink", "st_uid", "st_size",
        "st_mtime_ns", "st_ctime_ns",
    )
    directory_descriptors: list[int] = []
    directory_snapshots: list[tuple[int, os.stat_result]] = []
    file_descriptor: int | None = None

    def open_root_chain() -> tuple[int, os.stat_result]:
        """Open every absolute root component without following a symlink."""

        parts = PurePosixPath(root_text).parts
        if not parts or parts[0] != "/" or len(parts) == 1:
            fail(f"{where} root must be a normalized absolute path")
        current_descriptor = os.open("/", directory_flags)
        directory_descriptors.append(current_descriptor)
        opened = os.fstat(current_descriptor)
        for part in parts[1:]:
            before = os.stat(
                part,
                dir_fd=current_descriptor,
                follow_symlinks=False,
            )
            if not stat.S_ISDIR(before.st_mode) or stat.S_ISLNK(before.st_mode):
                fail(f"{where} root must not traverse symlinked ancestors")
            child_descriptor = os.open(
                part,
                directory_flags,
                dir_fd=current_descriptor,
            )
            directory_descriptors.append(child_descriptor)
            opened = os.fstat(child_descriptor)
            if any(getattr(before, field) != getattr(opened, field)
                   for field in stable_fields):
                fail(f"{where} root changed before it could be opened")
            current_descriptor = child_descriptor
        return current_descriptor, opened

    try:
        current_descriptor, root_open = open_root_chain()
        if (not stat.S_ISDIR(root_open.st_mode) or
                stat.S_ISLNK(root_open.st_mode) or
                root_open.st_uid != os.getuid()):
            fail(f"{where} root must be an owned non-symlink directory")
        directory_snapshots.append((current_descriptor, root_open))

        parts = PurePosixPath(relative).parts
        for part in parts[:-1]:
            before = os.stat(
                part,
                dir_fd=current_descriptor,
                follow_symlinks=False,
            )
            if (not stat.S_ISDIR(before.st_mode) or stat.S_ISLNK(before.st_mode) or
                    before.st_uid != os.getuid()):
                fail(f"{where} ancestor must be an owned non-symlink directory")
            child_descriptor = os.open(
                part,
                directory_flags,
                dir_fd=current_descriptor,
            )
            directory_descriptors.append(child_descriptor)
            opened = os.fstat(child_descriptor)
            if any(getattr(before, field) != getattr(opened, field)
                   for field in stable_fields):
                fail(f"{where} ancestor changed before it could be opened")
            if (not stat.S_ISDIR(opened.st_mode) or
                    stat.S_ISLNK(opened.st_mode) or
                    opened.st_uid != os.getuid()):
                fail(f"{where} ancestor must remain an owned directory after open")
            directory_snapshots.append((child_descriptor, opened))
            current_descriptor = child_descriptor

        filename = parts[-1]
        before = os.stat(
            filename,
            dir_fd=current_descriptor,
            follow_symlinks=False,
        )
        if not stat.S_ISREG(before.st_mode) or stat.S_ISLNK(before.st_mode):
            fail(f"{where} must be a regular non-symlink file")
        if before.st_nlink != 1:
            fail(f"{where} must have exactly one hard link")
        if before.st_uid != os.getuid():
            fail(f"{where} owner mismatch")
        if before.st_size != expected_size:
            fail(f"{where} size witness mismatch")
        if stat.S_IMODE(before.st_mode) != expected_mode:
            fail(f"{where} mode witness mismatch")

        file_descriptor = os.open(
            filename,
            file_flags,
            dir_fd=current_descriptor,
        )
        opened = os.fstat(file_descriptor)
        if any(getattr(before, field) != getattr(opened, field)
               for field in stable_fields):
            fail(f"{where} changed before it could be opened")
        if (not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1 or
                opened.st_uid != os.getuid() or opened.st_size != expected_size or
                stat.S_IMODE(opened.st_mode) != expected_mode):
            fail(f"{where} must remain a regular file after open")

        digest = hashlib.sha256()
        remaining = expected_size
        while remaining:
            chunk = os.read(file_descriptor, min(remaining, 1024 * 1024))
            if not chunk:
                fail(f"{where} ended before its size witness")
            digest.update(chunk)
            remaining -= len(chunk)
        if os.read(file_descriptor, 1):
            fail(f"{where} exceeded its size witness")
        after = os.fstat(file_descriptor)
        path_after = os.stat(
            filename,
            dir_fd=current_descriptor,
            follow_symlinks=False,
        )
        if (any(getattr(opened, field) != getattr(after, field)
                for field in stable_fields) or
                any(getattr(after, field) != getattr(path_after, field)
                    for field in stable_fields)):
            fail(f"{where} changed while being read")
        for descriptor, snapshot in directory_snapshots:
            current = os.fstat(descriptor)
            if any(getattr(snapshot, field) != getattr(current, field)
                   for field in stable_fields):
                fail(f"{where} ancestor changed while being read")
        _, root_path_after = open_root_chain()
        if any(getattr(root_open, field) != getattr(root_path_after, field)
               for field in stable_fields):
            fail(f"{where} root path changed while being read")
        actual_digest = digest.hexdigest()
        if actual_digest != expected_digest:
            fail(f"{where} digest witness mismatch")
        return actual_digest
    except OSError as error:
        fail(f"cannot safely read {where}: {error}")
    finally:
        active_error = sys.exc_info()[0] is not None
        close_error: OSError | None = None
        descriptors = list(reversed(directory_descriptors))
        if file_descriptor is not None:
            descriptors.insert(0, file_descriptor)
        for descriptor in descriptors:
            try:
                os.close(descriptor)
            except OSError as error:
                if close_error is None:
                    close_error = error
        if close_error is not None and not active_error:
            fail(f"cannot safely close {where}: {close_error}")


def verify_lean_tree(root: Path, manifest: dict[str, dict],
                     expected_total: int) -> tuple[Path, list[Path]]:
    root_metadata = root.lstat()
    if (not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode) or
            root_metadata.st_uid != os.getuid() or
            stat.S_IMODE(root_metadata.st_mode) != 0o555):
        fail("materialized Lean root metadata mismatch")
    actual_paths: set[str] = set()
    macho_paths: list[Path] = []
    total = 0

    def walk(directory: Path, relative_directory: PurePosixPath) -> None:
        nonlocal total
        for entry in os.scandir(directory):
            relative_path = (relative_directory / entry.name
                             if relative_directory != PurePosixPath(".")
                             else PurePosixPath(entry.name))
            relative = relative_path.as_posix()
            record = manifest.get(relative)
            if record is None:
                fail(f"materialized Lean tree contains unexpected path: {relative}")
            metadata = entry.stat(follow_symlinks=False)
            if stat.S_ISLNK(metadata.st_mode):
                fail(f"materialized Lean symlink is forbidden: {relative}")
            if metadata.st_uid != os.getuid():
                fail(f"materialized Lean owner mismatch: {relative}")
            if record["kind"] == "directory":
                if (not stat.S_ISDIR(metadata.st_mode) or
                        stat.S_IMODE(metadata.st_mode) != record["mode"]):
                    fail(f"materialized Lean directory metadata mismatch: {relative}")
                walk(Path(entry.path), relative_path)
            else:
                if not stat.S_ISREG(metadata.st_mode):
                    fail(f"materialized Lean entry is not regular: {relative}")
                if metadata.st_nlink != 1:
                    fail(f"materialized Lean file must have one hard link: {relative}")
                if (metadata.st_size != record["size"] or
                        stat.S_IMODE(metadata.st_mode) != record["mode"]):
                    fail(f"materialized Lean file metadata mismatch: {relative}")
                total += metadata.st_size
                flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
                descriptor = os.open(entry.path, flags)
                try:
                    before = os.fstat(descriptor)
                    if ((before.st_dev, before.st_ino) !=
                            (metadata.st_dev, metadata.st_ino)):
                        fail(f"materialized Lean file changed before inspection: {relative}")
                    magic = os.read(descriptor, 4)
                    after = os.fstat(descriptor)
                    if any(getattr(before, field) != getattr(after, field)
                           for field in ("st_dev", "st_ino", "st_mode", "st_nlink",
                                         "st_uid", "st_size")):
                        fail(f"materialized Lean file changed during inspection: {relative}")
                finally:
                    os.close(descriptor)
                if magic in RUNTIME_IMAGE_MAGICS:
                    macho_paths.append(Path(entry.path))
            actual_paths.add(relative)

    walk(root, PurePosixPath("."))
    if actual_paths != set(manifest):
        fail("materialized Lean tree has missing paths")
    if len(actual_paths) != len(manifest):
        fail("materialized Lean tree entry count mismatch")
    if total != expected_total:
        fail(f"materialized Lean tree byte count mismatch: expected {expected_total}, got {total}")
    return root, sorted(macho_paths)


def locked_otool(host_lock: dict) -> Path:
    developer = host_lock["profiles"][0]["developerTools"]
    otool = Path(developer["otoolPath"])
    try:
        metadata = otool.lstat()
    except FileNotFoundError:
        fail("effective Xcode otool is missing")
    if (not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode) or
            sha256_regular_snapshot(otool, metadata, "effective Xcode otool") !=
            developer["otoolSha256"]):
        fail("effective Xcode otool does not match the host profile")
    return otool


def locked_readelf(host_lock: dict) -> Path:
    matching = [
        profile for profile in host_lock["profiles"]
        if host_profile_kind(profile) == "linux"
    ]
    if len(matching) != 1:
        fail("host profile lock must contain exactly one linux profile")
    distro = matching[0]["distroTools"]
    readelf = Path(distro["readelfPath"])
    try:
        metadata = readelf.lstat()
    except FileNotFoundError:
        fail("locked distro readelf is missing")
    if (not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode) or
            sha256_regular_snapshot(readelf, metadata, "locked distro readelf") !=
            distro["readelfSha256"]):
        fail("locked distro readelf does not match the host profile")
    return readelf


def readelf_dynamic(readelf: Path, path: Path) -> tuple[set[str], str | None]:
    output = subprocess.run(
        [str(readelf), "-d", str(path)], check=True, capture_output=True, text=True,
        env={"LC_ALL": "C"}, timeout=10,
    ).stdout
    needed: set[str] = set()
    runpath: str | None = None
    for line in output.splitlines():
        match = re.search(r"\(NEEDED\).*\[(?P<soname>[^\]]+)\]", line)
        if match is not None:
            needed.add(match.group("soname"))
            continue
        match = re.search(r"\((?:RUNPATH|RPATH)\).*\[(?P<value>[^\]]+)\]", line)
        if match is not None:
            if runpath is not None and runpath != match.group("value"):
                fail(f"ELF has conflicting RPATH/RUNPATH entries: {path}")
            runpath = match.group("value")
    return needed, runpath


def parse_ld_trace(output: str) -> set[str]:
    loaded: set[str] = set()
    for raw_line in output.splitlines():
        line = raw_line.strip()
        match = re.fullmatch(r"\S+\s+=>\s+(/\S+)\s+\(0x[0-9a-f]+\)", line)
        if match is not None:
            loaded.add(match.group(1))
            continue
        match = re.fullmatch(r"(/\S+)\s+\(0x[0-9a-f]+\)", line)
        if match is not None:
            loaded.add(match.group(1))
    return loaded


def internal_load_path(root: Path, base: Path, suffix: str,
                       macho_set: set[Path]) -> Path | None:
    candidate = (base / suffix).resolve(strict=False)
    try:
        candidate.relative_to(root)
    except ValueError:
        return None
    return candidate if candidate in macho_set else None


def parse_otool_rpaths(output: str) -> list[str]:
    lines = output.splitlines()
    result: list[str] = []
    for index, line in enumerate(lines):
        if line.strip() != "cmd LC_RPATH":
            continue
        for detail in lines[index + 1:index + 5]:
            match = re.fullmatch(r"\s*path (.+) \(offset \d+\)", detail)
            if match is not None:
                result.append(match.group(1))
                break
        else:
            fail("otool emitted LC_RPATH without a path")
    return result


def _is_canonical_system_path(
    value: str,
    system_roots: tuple[str, ...],
    *,
    allow_trailing_slash: bool,
) -> bool:
    """Match a system path only after lexical canonicalization checks."""

    if not value.startswith("/"):
        return False
    if any(
        ord(char) < 0x20
        or ord(char) == 0x7f
        or 0x80 <= ord(char) <= 0x9f
        for char in value
    ):
        return False
    body = value[1:]
    if body.endswith("/"):
        if not allow_trailing_slash:
            return False
        body = body[:-1]
    if not body:
        return False
    if any(part in ("", ".", "..") for part in body.split("/")):
        return False
    return any(value.startswith(root) for root in system_roots)


def resolve_internal_rpath(root: Path, loader: Path, executable: Path, value: str,
                           system_roots: tuple[str, ...], *,
                           require_exists: bool = True) -> Path:
    if _is_canonical_system_path(
        value,
        system_roots,
        allow_trailing_slash=True,
    ):
        return Path(value)
    if value.startswith(str(root) + "/"):
        candidate = Path(value)
    elif value == "@loader_path":
        candidate = loader.parent
    elif value.startswith("@loader_path/"):
        candidate = loader.parent / value[len("@loader_path/"):]
    elif value == "@executable_path":
        candidate = executable.parent
    elif value.startswith("@executable_path/"):
        candidate = executable.parent / value[len("@executable_path/"):]
    else:
        fail(f"Mach-O RPATH escapes Lean toolchain closure: "
             f"{loader.relative_to(root)} -> {value}")
    candidate = candidate.resolve(strict=False)
    try:
        candidate.relative_to(root)
    except ValueError:
        fail(f"Mach-O RPATH escapes Lean toolchain root: "
             f"{loader.relative_to(root)} -> {value}")
    if require_exists and (not candidate.is_dir() or candidate.is_symlink()):
        fail(f"Mach-O RPATH does not resolve to a toolchain directory: "
             f"{loader.relative_to(root)} -> {value}")
    return candidate


def resolve_reachable_macho_load(root: Path, loader: Path, executable: Path,
                                 load: str, active_rpaths: list[Path],
                                 macho_set: set[Path],
                                 system_roots: tuple[str, ...]) -> Path | None:
    if _is_canonical_system_path(
        load,
        system_roots,
        allow_trailing_slash=False,
    ):
        return None
    if load.startswith(str(root) + "/"):
        candidate = Path(load).resolve(strict=False)
    elif load.startswith("@loader_path/"):
        candidate = (loader.parent / load[len("@loader_path/"):]).resolve(strict=False)
    elif load.startswith("@executable_path/"):
        candidate = (executable.parent /
                     load[len("@executable_path/"):]).resolve(strict=False)
    elif load.startswith("@rpath/"):
        suffix = safe_relative(load[len("@rpath/"):], "Mach-O @rpath suffix")
        for runpath in active_rpaths:
            candidate = (runpath / suffix).resolve(strict=False)
            candidate_text = str(candidate)
            if candidate_text.startswith(system_roots):
                if candidate.exists():
                    return None
                continue
            if candidate in macho_set:
                return candidate
        return None
    else:
        return None
    try:
        candidate.relative_to(root)
    except ValueError:
        return None
    return candidate if candidate in macho_set else None


_COMPILER_RUNTIME_GRAPH: ModuleType | None = None
_COMPILER_RUNTIME_GRAPH_API = (
    "CompilerRuntimeGraph",
    "MachOInspection",
    "RuntimeGraphError",
    "resolve_compiler_runtime_graph",
)


def _require_compiler_runtime_graph_api(module: ModuleType) -> ModuleType:
    for name in _COMPILER_RUNTIME_GRAPH_API:
        if not hasattr(module, name):
            fail(f"compiler_runtime_graph.py missing symbol: {name}")
    return module


def _load_compiler_runtime_graph() -> ModuleType:
    """Load exact sibling compiler_runtime_graph.py (script + importlib safe).

    Reuses any already-imported module object whose ``__file__`` resolves to the
    sibling path so importlib self-tests that loaded the graph under a synthetic
    name still share class identity with discover results.
    """

    global _COMPILER_RUNTIME_GRAPH
    if _COMPILER_RUNTIME_GRAPH is not None:
        return _require_compiler_runtime_graph_api(_COMPILER_RUNTIME_GRAPH)

    sibling = (Path(__file__).resolve().parent / "compiler_runtime_graph.py").resolve()
    for candidate in list(sys.modules.values()):
        origin = getattr(candidate, "__file__", None)
        if not origin:
            continue
        try:
            if Path(origin).resolve() != sibling:
                continue
        except (OSError, RuntimeError):
            continue
        if hasattr(candidate, "resolve_compiler_runtime_graph"):
            checked = _require_compiler_runtime_graph_api(candidate)
            _COMPILER_RUNTIME_GRAPH = checked
            return checked

    module: ModuleType | None = None
    # Prefer a direct import when the scripts directory is already importable
    # (CLI: python scripts/toolchain_assets.py).
    try:
        import compiler_runtime_graph as imported  # type: ignore[no-redef]
        imported_origin = getattr(imported, "__file__", None)
        if imported_origin is not None:
            try:
                if Path(imported_origin).resolve() == sibling:
                    module = imported
            except (OSError, RuntimeError):
                module = None
    except ImportError:
        module = None
    if module is None:
        if not sibling.is_file():
            fail("compiler_runtime_graph.py sibling is missing")
        # Stable public name so subsequent imports share the same module object.
        spec = importlib.util.spec_from_file_location(
            "compiler_runtime_graph",
            sibling,
        )
        if spec is None or spec.loader is None:
            fail("cannot load compiler_runtime_graph.py sibling")
        module = importlib.util.module_from_spec(spec)
        sys.modules["compiler_runtime_graph"] = module
        try:
            spec.loader.exec_module(module)
        except Exception:  # noqa: BLE001 - collapse loader failures to AssetError
            if sys.modules.get("compiler_runtime_graph") is module:
                del sys.modules["compiler_runtime_graph"]
            raise AssetError(
                "cannot load compiler_runtime_graph.py sibling"
            ) from None

    checked = _require_compiler_runtime_graph_api(module)
    _COMPILER_RUNTIME_GRAPH = checked
    return checked


_COMPILER_RUNTIME_MANIFEST: ModuleType | None = None
_COMPILER_RUNTIME_MANIFEST_API = (
    "CompilerRuntimeObservation",
    "RuntimeImageWitness",
)


def _require_compiler_runtime_manifest_api(module: ModuleType) -> ModuleType:
    for name in _COMPILER_RUNTIME_MANIFEST_API:
        if not hasattr(module, name):
            fail(f"compiler_runtime_manifest.py missing symbol: {name}")
    return module


def _load_compiler_runtime_manifest() -> ModuleType:
    """Load the exact sibling manifest module while preserving class identity."""

    global _COMPILER_RUNTIME_MANIFEST
    if _COMPILER_RUNTIME_MANIFEST is not None:
        return _require_compiler_runtime_manifest_api(
            _COMPILER_RUNTIME_MANIFEST
        )

    sibling = (
        Path(__file__).resolve().parent / "compiler_runtime_manifest.py"
    ).resolve()
    for candidate in list(sys.modules.values()):
        origin = getattr(candidate, "__file__", None)
        if not origin:
            continue
        try:
            if Path(origin).resolve() != sibling:
                continue
        except (OSError, RuntimeError):
            continue
        if hasattr(candidate, "CompilerRuntimeObservation"):
            checked = _require_compiler_runtime_manifest_api(candidate)
            _COMPILER_RUNTIME_MANIFEST = checked
            return checked

    module: ModuleType | None = None
    try:
        import compiler_runtime_manifest as imported  # type: ignore[no-redef]
        imported_origin = getattr(imported, "__file__", None)
        if imported_origin is not None:
            try:
                if Path(imported_origin).resolve() == sibling:
                    module = imported
            except (OSError, RuntimeError):
                module = None
    except ImportError:
        module = None
    if module is None:
        if not sibling.is_file():
            fail("compiler_runtime_manifest.py sibling is missing")
        spec = importlib.util.spec_from_file_location(
            "compiler_runtime_manifest",
            sibling,
        )
        if spec is None or spec.loader is None:
            fail("cannot load compiler_runtime_manifest.py sibling")
        module = importlib.util.module_from_spec(spec)
        sys.modules["compiler_runtime_manifest"] = module
        try:
            spec.loader.exec_module(module)
        except Exception:  # noqa: BLE001 - collapse loader failures
            if sys.modules.get("compiler_runtime_manifest") is module:
                del sys.modules["compiler_runtime_manifest"]
            raise AssetError(
                "cannot load compiler_runtime_manifest.py sibling"
            ) from None

    checked = _require_compiler_runtime_manifest_api(module)
    _COMPILER_RUNTIME_MANIFEST = checked
    return checked


_OBSERVATION_STABLE_FIELDS = (
    "st_dev",
    "st_ino",
    "st_mode",
    "st_nlink",
    "st_uid",
    "st_size",
    "st_mtime_ns",
    "st_ctime_ns",
)
_OBSERVATION_OPEN_IDENTITY_FIELDS = (
    "st_dev",
    "st_ino",
    "st_mode",
    "st_nlink",
    "st_uid",
)


def _observation_stat_tuple(metadata: os.stat_result) -> tuple[object, ...]:
    return tuple(
        getattr(metadata, field) for field in _OBSERVATION_STABLE_FIELDS
    )


def _observation_open_identity(
    metadata: os.stat_result,
) -> tuple[object, ...]:
    return tuple(
        getattr(metadata, field)
        for field in _OBSERVATION_OPEN_IDENTITY_FIELDS
    )


def _require_observation_file_record(
    tree_manifest: object,
    relative: str,
) -> dict:
    if type(tree_manifest) is not dict:
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            "tree_manifest must be an exact dict",
        )
    if relative not in tree_manifest:
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            f"tree_manifest is missing runtime image {relative}",
        )
    record = tree_manifest[relative]
    if type(record) is not dict or set(record) != {
        "kind", "size", "mode", "sha256",
    }:
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            f"tree_manifest record is not exact for {relative}",
        )
    if record["kind"] != "file":
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            f"tree_manifest runtime image is not a file: {relative}",
        )
    if type(record["size"]) is not int or not 0 <= record["size"] <= 2 ** 53 - 1:
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            f"tree_manifest size witness is invalid for {relative}",
        )
    if type(record["mode"]) is not int or record["mode"] not in {0o444, 0o555}:
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            f"tree_manifest mode witness is invalid for {relative}",
        )
    if (type(record["sha256"]) is not str or
            SHA256_RE.fullmatch(record["sha256"]) is None):
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            f"tree_manifest digest witness is invalid for {relative}",
        )
    return record


def _runtime_observation_paths(
    root: Path,
    macho_paths: object,
) -> tuple[tuple[str, ...], tuple[Path, ...]]:
    root_text = str(root)
    if (not isinstance(root, Path) or not root.is_absolute() or
            root_text in {"/", "//"} or root_text.startswith("//") or
            "\x00" in root_text or posixpath.normpath(root_text) != root_text):
        fail_sbom_observation(
            "PF-SBOM-IO",
            "runtime root must be a normalized absolute path",
        )
    if type(macho_paths) is not list or not macho_paths:
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            "macho_paths must be a nonempty exact list",
        )

    relative_paths: list[str] = []
    absolute_paths: list[Path] = []
    for index, path in enumerate(macho_paths):
        if not isinstance(path, Path) or not path.is_absolute():
            fail_sbom_observation(
                "PF-SBOM-IO",
                f"macho_paths[{index}] must be an absolute Path",
            )
        try:
            lexical_relative = path.relative_to(root).as_posix()
            relative = safe_relative(
                lexical_relative,
                f"macho_paths[{index}]",
            )
        except (AssetError, ValueError):
            fail_sbom_observation(
                "PF-SBOM-IO",
                f"macho_paths[{index}] escapes the runtime root",
            )
        expected = root / PurePosixPath(relative)
        if path != expected:
            fail_sbom_observation(
                "PF-SBOM-IO",
                f"macho_paths[{index}] is not lexically normalized",
            )
        relative_paths.append(relative)
        absolute_paths.append(expected)

    if relative_paths != sorted(relative_paths):
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            "macho_paths must be sorted",
        )
    if len(relative_paths) != len(set(relative_paths)):
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            "macho_paths must be unique",
        )
    return tuple(relative_paths), tuple(absolute_paths)


def _open_observation_root_chain(
    root: Path,
    descriptors: list[int],
) -> tuple[int, os.stat_result]:
    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    current = os.open("/", directory_flags)
    descriptors.append(current)
    opened = os.fstat(current)
    for part in PurePosixPath(str(root)).parts[1:]:
        before = os.stat(part, dir_fd=current, follow_symlinks=False)
        if not stat.S_ISDIR(before.st_mode) or stat.S_ISLNK(before.st_mode):
            fail_sbom_observation(
                "PF-SBOM-IO",
                "runtime root traverses a symlink or non-directory",
            )
        child = os.open(part, directory_flags, dir_fd=current)
        descriptors.append(child)
        opened = os.fstat(child)
        if _observation_open_identity(before) != _observation_open_identity(opened):
            fail_sbom_observation(
                "PF-SBOM-IO",
                "runtime root changed while being opened",
            )
        current = child
    if (not stat.S_ISDIR(opened.st_mode) or stat.S_ISLNK(opened.st_mode) or
            opened.st_uid != os.getuid()):
        fail_sbom_observation(
            "PF-SBOM-IO",
            "runtime root must be an owned non-symlink directory",
        )
    return current, opened


def _read_observation_file(
    descriptor: int,
    expected_size: int,
) -> tuple[str, bytes]:
    os.lseek(descriptor, 0, os.SEEK_SET)
    digest = hashlib.sha256()
    prefix = b""
    remaining = expected_size
    while remaining:
        chunk = os.read(descriptor, min(remaining, 1024 * 1024))
        if not chunk:
            fail_sbom_observation(
                "PF-SBOM-IO",
                "runtime image ended while being observed",
            )
        if len(prefix) < 4:
            prefix = (prefix + chunk)[:4]
        digest.update(chunk)
        remaining -= len(chunk)
    if os.read(descriptor, 1):
        fail_sbom_observation(
            "PF-SBOM-IO",
            "runtime image grew while being observed",
        )
    return digest.hexdigest(), prefix


def _open_runtime_observation_window(
    root: Path,
    relative_paths: tuple[str, ...],
    tree_manifest: object,
) -> dict:
    descriptors: list[int] = []
    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    file_flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NONBLOCK", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    try:
        root_descriptor, root_snapshot = _open_observation_root_chain(
            root,
            descriptors,
        )
        directories: dict[str, tuple[int, os.stat_result, str, int]] = {
            "": (root_descriptor, root_snapshot, "", -1),
        }
        files: dict[str, dict] = {}
        for relative in relative_paths:
            record = dict(
                _require_observation_file_record(tree_manifest, relative)
            )
            parts = PurePosixPath(relative).parts
            parent_key = ""
            parent_descriptor = root_descriptor
            for part in parts[:-1]:
                key = f"{parent_key}/{part}" if parent_key else part
                cached = directories.get(key)
                if cached is not None:
                    parent_descriptor = cached[0]
                    parent_key = key
                    continue
                before = os.stat(
                    part,
                    dir_fd=parent_descriptor,
                    follow_symlinks=False,
                )
                if (not stat.S_ISDIR(before.st_mode) or
                        stat.S_ISLNK(before.st_mode) or
                        before.st_uid != os.getuid()):
                    fail_sbom_observation(
                        "PF-SBOM-IO",
                        f"runtime ancestor is unsafe: {key}",
                    )
                child = os.open(
                    part,
                    directory_flags,
                    dir_fd=parent_descriptor,
                )
                descriptors.append(child)
                opened = os.fstat(child)
                if (_observation_open_identity(before) !=
                        _observation_open_identity(opened)):
                    fail_sbom_observation(
                        "PF-SBOM-IO",
                        f"runtime ancestor changed while opening: {key}",
                    )
                directories[key] = (
                    child,
                    opened,
                    part,
                    parent_descriptor,
                )
                parent_descriptor = child
                parent_key = key

            filename = parts[-1]
            before = os.stat(
                filename,
                dir_fd=parent_descriptor,
                follow_symlinks=False,
            )
            if (not stat.S_ISREG(before.st_mode) or
                    stat.S_ISLNK(before.st_mode) or before.st_nlink != 1 or
                    before.st_uid != os.getuid()):
                fail_sbom_observation(
                    "PF-SBOM-IO",
                    f"runtime image is not an owned single-link file: {relative}",
                )
            if before.st_size != record["size"]:
                fail_sbom_observation(
                    "PF-SBOM-CLOSURE",
                    f"runtime size witness mismatch: {relative}",
                )
            if stat.S_IMODE(before.st_mode) != record["mode"]:
                fail_sbom_observation(
                    "PF-SBOM-CLOSURE",
                    f"runtime mode witness mismatch: {relative}",
                )
            descriptor = os.open(
                filename,
                file_flags,
                dir_fd=parent_descriptor,
            )
            descriptors.append(descriptor)
            opened = os.fstat(descriptor)
            if _observation_stat_tuple(before) != _observation_stat_tuple(opened):
                fail_sbom_observation(
                    "PF-SBOM-IO",
                    f"runtime image changed while opening: {relative}",
                )
            digest, magic = _read_observation_file(descriptor, record["size"])
            after_read = os.fstat(descriptor)
            if _observation_stat_tuple(opened) != _observation_stat_tuple(after_read):
                fail_sbom_observation(
                    "PF-SBOM-IO",
                    f"runtime image changed while reading: {relative}",
                )
            if digest != record["sha256"]:
                fail_sbom_observation(
                    "PF-SBOM-CLOSURE",
                    f"runtime digest witness mismatch: {relative}",
                )
            if magic not in RUNTIME_IMAGE_MAGICS:
                fail_sbom_observation(
                    "PF-SBOM-CLOSURE",
                    f"runtime image is not a Mach-O/ELF image: {relative}",
                )
            files[relative] = {
                "descriptor": descriptor,
                "snapshot": opened,
                "parent": parent_descriptor,
                "filename": filename,
                "record": record,
                "digest": digest,
            }
        return {
            "root": root,
            "rootSnapshot": root_snapshot,
            "descriptors": descriptors,
            "directories": directories,
            "files": files,
        }
    except Exception:
        for descriptor in reversed(descriptors):
            try:
                os.close(descriptor)
            except OSError:
                pass
        raise


def _verify_runtime_observation_window(window: dict) -> None:
    for relative, item in window["files"].items():
        descriptor = item["descriptor"]
        snapshot = item["snapshot"]
        current = os.fstat(descriptor)
        path_current = os.stat(
            item["filename"],
            dir_fd=item["parent"],
            follow_symlinks=False,
        )
        if (_observation_stat_tuple(snapshot) != _observation_stat_tuple(current) or
                _observation_stat_tuple(current) !=
                _observation_stat_tuple(path_current)):
            fail_sbom_observation(
                "PF-SBOM-IO",
                f"runtime image changed during observation: {relative}",
            )
        digest, magic = _read_observation_file(
            descriptor,
            item["record"]["size"],
        )
        after_read = os.fstat(descriptor)
        path_after_read = os.stat(
            item["filename"],
            dir_fd=item["parent"],
            follow_symlinks=False,
        )
        if (_observation_stat_tuple(snapshot) !=
                _observation_stat_tuple(after_read) or
                _observation_stat_tuple(after_read) !=
                _observation_stat_tuple(path_after_read)):
            fail_sbom_observation(
                "PF-SBOM-IO",
                f"runtime image changed during final read: {relative}",
            )
        if digest != item["digest"] or magic not in RUNTIME_IMAGE_MAGICS:
            fail_sbom_observation(
                "PF-SBOM-IO",
                f"runtime image bytes changed during observation: {relative}",
            )

    for relative, item in window["directories"].items():
        descriptor, snapshot, name, parent = item
        current = os.fstat(descriptor)
        if _observation_stat_tuple(snapshot) != _observation_stat_tuple(current):
            fail_sbom_observation(
                "PF-SBOM-IO",
                f"runtime directory changed during observation: {relative or '.'}",
            )
        if relative:
            path_current = os.stat(
                name,
                dir_fd=parent,
                follow_symlinks=False,
            )
            if _observation_stat_tuple(current) != _observation_stat_tuple(path_current):
                fail_sbom_observation(
                    "PF-SBOM-IO",
                    f"runtime directory path changed during observation: {relative}",
                )

    reopened: list[int] = []
    try:
        _, root_path_current = _open_observation_root_chain(
            window["root"],
            reopened,
        )
        if (_observation_stat_tuple(window["rootSnapshot"]) !=
                _observation_stat_tuple(root_path_current)):
            fail_sbom_observation(
                "PF-SBOM-IO",
                "runtime root path changed during observation",
            )
    finally:
        for descriptor in reversed(reopened):
            try:
                os.close(descriptor)
            except OSError:
                pass


def _close_runtime_observation_window(window: dict) -> None:
    close_error: OSError | None = None
    for descriptor in reversed(window["descriptors"]):
        try:
            os.close(descriptor)
        except OSError as error:
            if close_error is None:
                close_error = error
    if close_error is not None:
        fail_sbom_observation(
            "PF-SBOM-IO",
            f"cannot close runtime observation window: {close_error}",
        )


def _root_relative_posix(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        fail(f"Mach-O path escapes Lean toolchain root: {path}")
    raise AssertionError("unreachable")


def _normalize_load_for_graph(root: Path, load: str) -> str:
    """Map absolute-under-root install names to root-relative POSIX paths."""

    root_prefix = str(root.resolve()) + "/"
    if load.startswith(root_prefix):
        return _root_relative_posix(root, Path(load))
    return load


def discover_lean_macho_static(
    lock: dict,
    host_lock: dict,
    root: Path,
    macho_paths: list[Path],
):
    """Single-pass otool discovery -> typed CompilerRuntimeGraph.

    Each runtime image is inspected with otool -hv/-l/-L/-D at most once.
    Unreachable images still receive the existing static rpath/load admit
    checks.  Walk/resolution is delegated to compiler_runtime_graph.
    """

    graph_mod = _load_compiler_runtime_graph()
    if not macho_paths:
        fail("materialized Lean tree contains no Mach-O files")
    resolved_root = root.resolve()
    resolved_inputs = [path.resolve() for path in macho_paths]
    if len(resolved_inputs) != len(set(resolved_inputs)):
        fail("materialized Lean tree contains duplicate Mach-O paths")
    for path in resolved_inputs:
        _root_relative_posix(resolved_root, path)
    otool = locked_otool(host_lock)
    system_roots = tuple(lock["machoPolicy"]["allowedSystemLoadRoots"])
    runtime_macho_paths: list[Path] = []
    for path in resolved_inputs:
        headers = subprocess.run(
            [str(otool), "-hv", str(path)], check=True, capture_output=True, text=True,
            env={"LC_ALL": "C"}, timeout=10,
        )
        file_types = set(re.findall(
            r"\b(?:OBJECT|EXECUTE|DYLIB|DYLINKER|BUNDLE)\b", headers.stdout,
        ))
        if not file_types:
            fail(f"cannot classify Mach-O file type: {path.relative_to(resolved_root)}")
        if file_types <= {"OBJECT"}:
            # Static archives and relocatable objects are link inputs, not dyld
            # runtime nodes. Their headers are still parsed above, but they have
            # no process-time load closure to admit.
            continue
        if "OBJECT" in file_types:
            fail(f"Mach-O mixes runtime and object file types: "
                 f"{path.relative_to(resolved_root)}")
        runtime_macho_paths.append(path.resolve())
    if not runtime_macho_paths:
        fail("materialized Lean tree contains no runtime Mach-O files")

    macho_set = set(runtime_macho_paths)
    inspections_by_path: dict[str, object] = {}
    for path in runtime_macho_paths:
        relative = _root_relative_posix(resolved_root, path)
        commands = subprocess.run(
            [str(otool), "-l", str(path)], check=True, capture_output=True, text=True,
            env={"LC_ALL": "C"}, timeout=10,
        )
        rpaths = parse_otool_rpaths(commands.stdout)
        for raw_rpath in rpaths:
            # All standalone runtime images must be free of external runpaths,
            # including SDK dylibs that are not reachable from lean/lake.
            resolve_internal_rpath(
                resolved_root, path, resolved_root / "bin" / "lean", raw_rpath,
                system_roots, require_exists=False,
            )
        loads = subprocess.run(
            [str(otool), "-L", str(path)], check=True, capture_output=True, text=True,
            env={"LC_ALL": "C"}, timeout=10,
        )
        observed = parse_otool_lines(loads.stdout)
        ids = subprocess.run(
            [str(otool), "-D", str(path)], check=False, capture_output=True, text=True,
            env={"LC_ALL": "C"}, timeout=10,
        )
        if ids.returncode == 0:
            id_lines = [line.strip() for line in ids.stdout.splitlines()[1:]
                        if line.strip() and not line.rstrip().endswith(":")]
            unique_ids = set(id_lines)
            if len(unique_ids) > 1:
                fail(f"Mach-O has multiple install IDs: {relative}")
            if unique_ids:
                install_id = next(iter(unique_ids))
                observed = [load for load in observed if load != install_id]
        for load in observed:
            if _is_canonical_system_path(
                load,
                system_roots,
                allow_trailing_slash=False,
            ):
                continue
            if load.startswith(str(resolved_root) + "/"):
                target = Path(load)
                if target.resolve() not in macho_set:
                    fail(f"Mach-O load targets non-Mach-O toolchain path: {load}")
                continue
            if load.startswith("@loader_path/"):
                if internal_load_path(
                    resolved_root, path.parent, load[len("@loader_path/"):],
                    macho_set,
                ) is not None:
                    continue
            elif load.startswith("@executable_path/"):
                if internal_load_path(
                    resolved_root, resolved_root / "bin",
                    load[len("@executable_path/"):], macho_set,
                ) is not None:
                    continue
            elif load.startswith("@rpath/"):
                # An unreachable SDK dylib may intentionally leave an @rpath
                # dependency to the final link environment. Resolve these only
                # when walking a declared compiler entrypoint in the graph.
                safe_relative(load[len("@rpath/"):], "Mach-O @rpath suffix")
                continue
            fail(f"Mach-O load escapes Lean toolchain closure: {relative} -> {load}")

        graph_loads = tuple(
            _normalize_load_for_graph(resolved_root, load) for load in observed
        )
        inspections_by_path[relative] = graph_mod.MachOInspection(
            rpaths=tuple(rpaths),
            loads=graph_loads,
        )

    entrypoint_rels: list[str] = []
    for record in lock["compilerToolchain"]["executables"]:
        relative = safe_relative(record["path"], "compiler entrypoint")
        absolute = (resolved_root / relative).resolve()
        if absolute not in macho_set:
            fail(f"compiler entrypoint is not a runtime Mach-O: {relative}")
        entrypoint_rels.append(relative)
    if len(entrypoint_rels) != len(set(entrypoint_rels)):
        fail("compiler entrypoints are not unique")
    entrypoints = tuple(sorted(entrypoint_rels))

    inspections = tuple(
        (path, inspections_by_path[path])
        for path in sorted(inspections_by_path)
    )
    try:
        return graph_mod.resolve_compiler_runtime_graph(
            entrypoints=entrypoints,
            inspections=inspections,
            allowed_system_roots=tuple(sorted(system_roots)),
        )
    except graph_mod.RuntimeGraphError as error:
        # Typed fail-closed surface; suppress graph traceback as __context__.
        raise AssetError(
            f"compiler Mach-O runtime graph failed ({error.code}): {error.detail}"
        ) from None


def discover_lean_elf_static(
    lock: dict,
    host_lock: dict,
    root: Path,
    elf_paths: list[Path],
):
    """Single-pass readelf discovery -> typed CompilerRuntimeGraph (linux).

    DT_NEEDED sonames are pre-resolved during inspection: toolchain-internal
    libraries are mapped to their in-tree paths via RUNPATH $ORIGIN expansion,
    everything else is admitted as a synthetic `/usr/lib/<soname>` system load
    covered by elfPolicy.allowedSystemLoadRoots.
    """

    graph_mod = _load_compiler_runtime_graph()
    if not elf_paths:
        fail("materialized Lean tree contains no ELF files")
    resolved_root = root.resolve()
    resolved_inputs = [path.resolve() for path in elf_paths]
    if len(resolved_inputs) != len(set(resolved_inputs)):
        fail("materialized Lean tree contains duplicate ELF paths")
    for path in resolved_inputs:
        _root_relative_posix(resolved_root, path)
    readelf = locked_readelf(host_lock)
    system_roots = tuple(lock["elfPolicy"]["allowedSystemLoadRoots"])
    runtime_elf_paths: list[Path] = []
    for path in resolved_inputs:
        headers = subprocess.run(
            [str(readelf), "-h", str(path)], check=True, capture_output=True,
            text=True, env={"LC_ALL": "C"}, timeout=10,
        )
        type_match = re.search(r"Type:\s+(?P<elftype>\S+)", headers.stdout)
        if type_match is None:
            fail(f"cannot classify ELF file type: {path.relative_to(resolved_root)}")
        elf_type = type_match.group("elftype")
        if elf_type == "REL":
            # Relocatable objects are link inputs, not runtime nodes.
            continue
        if elf_type not in {"EXEC", "DYN"}:
            fail(f"ELF has an unsupported runtime file type {elf_type}: "
                 f"{path.relative_to(resolved_root)}")
        runtime_elf_paths.append(path.resolve())
    if not runtime_elf_paths:
        fail("materialized Lean tree contains no runtime ELF files")

    elf_set = set(runtime_elf_paths)
    inspections_by_path: dict[str, object] = {}
    for path in runtime_elf_paths:
        relative = _root_relative_posix(resolved_root, path)
        needed, runpath = readelf_dynamic(readelf, path)
        search_directories: list[Path] = []
        if runpath is not None:
            for entry in runpath.split(":"):
                if not entry:
                    continue
                expanded = entry.replace("$ORIGIN", str(path.parent))
                if "$" in expanded:
                    fail(f"ELF runpath contains an unsupported variable: {relative}")
                candidate = Path(expanded)
                if not candidate.is_absolute():
                    fail(f"ELF runpath entry is not absolute: {relative}: {entry}")
                resolved_entry = candidate.resolve(strict=False)
                inside_toolchain = False
                try:
                    resolved_entry.relative_to(resolved_root)
                    inside_toolchain = True
                except ValueError:
                    pass
                if inside_toolchain:
                    search_directories.append(resolved_entry)
                    continue
                if str(resolved_entry).startswith(system_roots):
                    # A system-root runpath is admitted; it cannot resolve to a
                    # toolchain image, so it is not a search directory here.
                    continue
                if not resolved_entry.exists():
                    # Upstream build residue (the official lean linux zip is
                    # nix-built and leaves /nix/store runpaths on unreachable
                    # images): the runtime loader skips non-existent
                    # directories, and every actual load is still fail-closed
                    # via the LD_TRACE runtime probe.
                    continue
                fail(f"ELF runpath escapes toolchain and system roots: "
                     f"{relative}: {entry}")
        graph_loads: list[str] = []
        for soname in sorted(needed):
            internal_target: Path | None = None
            for directory in search_directories:
                candidate = (directory / soname).resolve(strict=False)
                if candidate in elf_set:
                    internal_target = candidate
                    break
            if internal_target is not None:
                graph_loads.append(
                    _normalize_load_for_graph(resolved_root, str(internal_target)))
            else:
                graph_loads.append(f"/usr/lib/{soname}")
        inspections_by_path[relative] = graph_mod.MachOInspection(
            rpaths=(),
            loads=tuple(graph_loads),
        )

    entrypoint_rels: list[str] = []
    for record in lock["compilerToolchain"]["executables"]:
        relative = safe_relative(record["path"], "compiler entrypoint")
        absolute = (resolved_root / relative).resolve()
        if absolute not in elf_set:
            fail(f"compiler entrypoint is not a runtime ELF: {relative}")
        entrypoint_rels.append(relative)
    if len(entrypoint_rels) != len(set(entrypoint_rels)):
        fail("compiler entrypoints are not unique")
    entrypoints = tuple(sorted(entrypoint_rels))

    inspections = tuple(
        (path, inspections_by_path[path])
        for path in sorted(inspections_by_path)
    )
    try:
        return graph_mod.resolve_compiler_runtime_graph(
            entrypoints=entrypoints,
            inspections=inspections,
            allowed_system_roots=tuple(sorted(system_roots)),
        )
    except graph_mod.RuntimeGraphError as error:
        raise AssetError(
            f"compiler ELF runtime graph failed ({error.code}): {error.detail}"
        ) from None


def discover_lean_runtime_static(
    lock: dict,
    host_lock: dict,
    root: Path,
    image_paths: list[Path],
):
    if is_darwin_tool_lock(lock):
        return discover_lean_macho_static(lock, host_lock, root, image_paths)
    return discover_lean_elf_static(lock, host_lock, root, image_paths)


def observe_compiler_runtime(
    *,
    lock: dict,
    host_lock: dict,
    root: Path,
    macho_paths: list[Path],
    tree_manifest: object,
):
    """Observe one typed runtime graph inside a retained safe-read window."""

    window: dict | None = None
    active_error = False
    try:
        relative_paths, absolute_paths = _runtime_observation_paths(
            root,
            macho_paths,
        )
        window = _open_runtime_observation_window(
            root,
            relative_paths,
            tree_manifest,
        )
        try:
            graph = discover_lean_runtime_static(
                lock,
                host_lock,
                root,
                list(absolute_paths),
            )
        except AssetError as error:
            fail_sbom_observation(
                "PF-SBOM-CLOSURE",
                f"compiler runtime graph discovery failed: {error}",
            )
        except (OSError, subprocess.SubprocessError) as error:
            fail_sbom_observation(
                "PF-SBOM-IO",
                f"compiler runtime inspection failed: {error}",
            )
        except Exception as error:  # noqa: BLE001 - sole public channel
            fail_sbom_observation(
                "PF-SBOM-CLOSURE",
                f"compiler runtime inspection failed: {error}",
            )

        _verify_runtime_observation_window(window)
        manifest_mod = _load_compiler_runtime_manifest()
        graph_paths = tuple(sorted(
            [entry.path for entry in graph.entrypoints]
            + [file_node.path for file_node in graph.files]
        ))
        if len(graph_paths) != len(set(graph_paths)):
            fail_sbom_observation(
                "PF-SBOM-CLOSURE",
                "compiler runtime graph paths are not unique",
            )
        if any(path not in window["files"] for path in graph_paths):
            fail_sbom_observation(
                "PF-SBOM-CLOSURE",
                "compiler runtime graph escapes the observed image set",
            )
        images = tuple(
            manifest_mod.RuntimeImageWitness(
                path=path,
                size=window["files"][path]["record"]["size"],
                mode=window["files"][path]["record"]["mode"],
                sha256=window["files"][path]["digest"],
            )
            for path in graph_paths
        )
        return manifest_mod.CompilerRuntimeObservation(
            graph=graph,
            images=images,
        )
    except AssetError as error:
        active_error = True
        if getattr(error, "code", None) in {
            "PF-SBOM-IO",
            "PF-SBOM-CLOSURE",
        }:
            raise error from None
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            f"compiler runtime observation failed: {error}",
        )
    except (OSError, subprocess.SubprocessError) as error:
        active_error = True
        fail_sbom_observation(
            "PF-SBOM-IO",
            f"compiler runtime observation failed: {error}",
        )
    except Exception as error:  # noqa: BLE001 - sole public channel
        active_error = True
        fail_sbom_observation(
            "PF-SBOM-CLOSURE",
            f"compiler runtime observation failed: {error}",
        )
    finally:
        if window is not None:
            try:
                _close_runtime_observation_window(window)
            except AssetError:
                if not active_error:
                    raise


def verify_lean_macho_static(lock: dict, host_lock: dict, root: Path,
                             macho_paths: list[Path]) -> dict[Path, set[Path]]:
    """D0-03 legacy projection: absolute Path closures including entrypoint self."""

    graph = discover_lean_macho_static(lock, host_lock, root, macho_paths)
    resolved_root = root.resolve()
    closures: dict[Path, set[Path]] = {}
    legacy = graph.as_legacy_closures()
    for entry_rel, members in legacy.items():
        entry_abs = (resolved_root / entry_rel).resolve()
        member_set = {(resolved_root / member).resolve() for member in members}
        # D0-03 freeze: each closure set always contains the entrypoint itself.
        member_set.add(entry_abs)
        closures[entry_abs] = member_set
    return closures


def verify_lean_runtime_static(lock: dict, host_lock: dict, root: Path,
                               image_paths: list[Path]) -> dict[Path, set[Path]]:
    if is_darwin_tool_lock(lock):
        return verify_lean_macho_static(lock, host_lock, root, image_paths)
    graph = discover_lean_elf_static(lock, host_lock, root, image_paths)
    resolved_root = root.resolve()
    closures: dict[Path, set[Path]] = {}
    legacy = graph.as_legacy_closures()
    for entry_rel, members in legacy.items():
        entry_abs = (resolved_root / entry_rel).resolve()
        member_set = {(resolved_root / member).resolve() for member in members}
        member_set.add(entry_abs)
        closures[entry_abs] = member_set
    return closures


def probe_lean_versions_and_runtime(lock: dict, root: Path,
                                    closures: dict[Path, set[Path]]) -> None:
    compiler = lock["compilerToolchain"]
    darwin_probe = is_darwin_tool_lock(lock)
    if darwin_probe:
        system_roots = tuple(lock["machoPolicy"]["allowedSystemLoadRoots"])
    else:
        system_roots = tuple(lock["elfPolicy"]["allowedSystemLoadRoots"])
    image_set = set().union(*closures.values())
    for probe_record in compiler["versionProbes"]:
        executable = root / probe_record["path"]
        environment = {
            "HOME": "/var/empty",
            "LC_ALL": "C",
            "PATH": f"{root / 'bin'}:/usr/bin:/bin",
            "TZ": "UTC",
        }
        if darwin_probe:
            environment["DYLD_PRINT_LIBRARIES"] = "1"
        probe = subprocess.run(
            [str(executable), *probe_record["args"]], check=False,
            capture_output=True, text=True, env=environment, timeout=10,
        )
        observed = probe.stdout + probe.stderr
        if probe.returncode != 0 or probe_record["expected"] not in observed:
            fail(f"compiler version probe failed for {probe_record['path']}: "
                 f"{observed.strip()}")
        if darwin_probe:
            loaded: set[str] = set()
            for line in probe.stderr.splitlines():
                match = re.fullmatch(r"dyld\[\d+\]: <[^>]+> (/.+)", line)
                if match is not None:
                    loaded.add(match.group(1))
            if not loaded:
                fail(f"DYLD load observation was empty for {probe_record['path']}")
        else:
            trace_environment = dict(environment)
            trace_environment["LD_TRACE_LOADED_OBJECTS"] = "1"
            trace = subprocess.run(
                [str(executable)], check=False, capture_output=True, text=True,
                env=trace_environment, timeout=10,
            )
            loaded = parse_ld_trace(trace.stdout)
            if not loaded:
                fail(f"LD load observation was empty for {probe_record['path']}")
        internal_loaded: set[Path] = set()
        for text in loaded:
            if text.startswith(system_roots):
                continue
            candidate = Path(text)
            if text.startswith(str(root) + "/") and candidate.resolve() in image_set:
                internal_loaded.add(candidate.resolve())
                continue
            fail(f"compiler runtime escaped toolchain closure: "
                 f"{probe_record['path']} -> {text}")
        executable_path = executable.resolve()
        internal_loaded.discard(executable_path)
        expected_internal = closures[executable_path] - {executable_path}
        if internal_loaded != expected_internal:
            missing = sorted(str(path.relative_to(root))
                             for path in expected_internal - internal_loaded)
            unexpected = sorted(str(path.relative_to(root))
                                for path in internal_loaded - expected_internal)
            fail(f"compiler runtime/static closure mismatch for {probe_record['path']}: "
                 f"missing={missing}, unexpected={unexpected}")


def make_tree_removable(root: Path) -> None:
    for directory, child_directories, _ in os.walk(root, topdown=True):
        try:
            os.chmod(directory, 0o700)
        except FileNotFoundError:
            continue
        for child in child_directories:
            try:
                os.chmod(Path(directory) / child, 0o700)
            except FileNotFoundError:
                continue


def materialize_lean(lock: dict, host_lock: dict, destination: Path) -> None:
    compiler = lock["compilerToolchain"]
    asset = asset_map(lock)[compiler["assetId"]]
    staging = prepare_destination(destination)
    try:
        with cached_asset_snapshot(asset) as snapshot:
            with zipfile.ZipFile(snapshot) as archive:
                validated = validate_lean_zip(archive, compiler, asset["id"])
                manifest = extract_lean_zip(
                    archive, validated, staging, compiler["unpackedSize"],
                )
        root, macho_paths = verify_lean_tree(staging, manifest, compiler["unpackedSize"])
        for record in compiler["executables"]:
            path = root / record["path"]
            metadata = path.lstat()
            if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                fail(f"Lean executable is missing: {record['path']}")
            actual = sha256_regular_snapshot(path, metadata,
                                             f"Lean executable {record['path']}")
            if actual != record["sha256"]:
                fail(f"Lean executable hash mismatch for {record['path']}: {actual}")
        closures = verify_lean_runtime_static(lock, host_lock, root, macho_paths)
        probe_lean_versions_and_runtime(lock, root, closures)
        os.replace(staging, destination)
    finally:
        if staging.exists():
            make_tree_removable(staging)
            shutil.rmtree(staging)
    print(f"toolchain-assets: materialized Lean toolchain {destination}")


LINUX_SYSTEM_TOOL_IDS = (
    "bash", "env", "git", "openssl", "python3", "readelf", "rm", "sha256sum",
    "sleep", "stat", "uname",
)


def observe_linux_system_tool(tool_id: str) -> dict:
    path = Path(f"/usr/bin/{tool_id}")
    try:
        node = path.lstat()
    except FileNotFoundError:
        fail(f"required linux system tool is missing: {path}")
    if stat.S_ISLNK(node.st_mode):
        node_kind = "symlink"
        link_target = os.readlink(path)
    elif stat.S_ISREG(node.st_mode):
        node_kind = "regular"
        link_target = None
    else:
        fail(f"linux system tool {tool_id} has an unsupported node kind: {path}")
    try:
        resolved = path.resolve(strict=True)
    except (FileNotFoundError, RuntimeError) as error:
        fail(f"linux system tool {tool_id} cannot be resolved: {error}")
    resolved_metadata = resolved.lstat()
    if not stat.S_ISREG(resolved_metadata.st_mode):
        fail(f"linux system tool {tool_id} must resolve to a regular file: {resolved}")
    return {
        "id": tool_id,
        "path": str(path),
        "nodeKind": node_kind,
        "linkTarget": link_target,
        "resolvedPath": str(resolved),
        "resolvedNlink": resolved_metadata.st_nlink,
        "mode": format(stat.S_IMODE(resolved_metadata.st_mode), "04o"),
        "sha256": sha256_file(resolved),
    }


def observe_host_linux(profile_id: str) -> dict:
    if host_platform_kind() != "linux":
        fail("observe-host currently supports linux hosts only")
    require_safe_identifier(profile_id, "observe-host --profile-id")
    tools = [observe_linux_system_tool(tool_id) for tool_id in LINUX_SYSTEM_TOOL_IDS]
    tools.sort(key=lambda record: record["id"])
    by_id = {record["id"]: record for record in tools}

    os_release = read_os_release()
    uname_path = by_id["uname"]["resolvedPath"]
    platform = {
        "osReleaseId": os_release.get("ID", ""),
        "osReleaseVersionId": os_release.get("VERSION_ID", ""),
        "kernelRelease": bounded_host_command([uname_path, "-r"]).stdout.strip(),
        "arch": bounded_host_command([uname_path, "-m"]).stdout.strip(),
        "secureBoot": observe_secure_boot(),
    }
    if not platform["osReleaseId"]:
        fail("os-release observation is missing ID")

    git_record = by_id["git"]
    python_record = by_id["python3"]
    readelf_record = by_id["readelf"]
    distro_paths = [
        (Path(git_record["resolvedPath"]), "distro Git"),
        (Path(python_record["resolvedPath"]), "distro Python"),
        (Path(readelf_record["resolvedPath"]), "distro readelf"),
    ]
    distro_mutable = any(
        path_mutable_by_current_user(path, label) for path, label in distro_paths)
    distro = {
        "gitPath": git_record["resolvedPath"],
        "gitSha256": git_record["sha256"],
        "gitVersion": bounded_host_command(
            [git_record["resolvedPath"], "--version"]).stdout.strip(),
        "pythonPath": python_record["resolvedPath"],
        "pythonSha256": python_record["sha256"],
        "pythonVersion": bounded_host_command(
            [python_record["resolvedPath"], "--version"]).stdout.strip(),
        "readelfPath": readelf_record["resolvedPath"],
        "readelfSha256": readelf_record["sha256"],
        "readelfVersion": bounded_host_command(
            [readelf_record["resolvedPath"], "--version"]).stdout.splitlines()[0],
        "toolsMutableByCurrentUser": distro_mutable,
    }
    bootstrap_source = by_id["openssl"]
    kat = extract_kat_digest(
        bounded_host_command(
            [bootstrap_source["resolvedPath"], "dgst", "-sha256"],
            input_bytes=b"abc",
        ).stdout,
        "digest bootstrap",
    )
    bootstrap = {
        "path": bootstrap_source["path"],
        "sha256": bootstrap_source["sha256"],
        "knownAnswerInput": "abc",
        "knownAnswerSha256": kat,
    }
    load_roots = sorted(
        root for root in ("/lib/", "/lib64/", "/usr/lib/") if Path(root).is_dir())
    if not load_roots:
        fail("no system load roots observed")
    profile_paths = [
        (Path(record["resolvedPath"]), f"system tool {record['id']}")
        for record in tools
    ]
    profile_paths.append((Path(bootstrap["path"]), "digest bootstrap"))
    profile_paths.extend(distro_paths)
    mutable_paths = [
        f"{label} ({path})" for path, label in profile_paths
        if path_mutable_by_current_user(path, label)
    ]
    eligible = (
        platform["arch"] in {"x86_64", "aarch64"} and
        platform["secureBoot"] == "enabled" and
        not mutable_paths
    )
    reasons = []
    if platform["arch"] not in {"x86_64", "aarch64"}:
        reasons.append(f"unsupported arch {platform['arch']}")
    if platform["secureBoot"] != "enabled":
        reasons.append(f"secure boot is {platform['secureBoot']}")
    if mutable_paths:
        reasons.append(
            "profile pathnames are replaceable by the current user: " +
            ", ".join(mutable_paths))
    return {
        "id": profile_id,
        "platform": platform,
        "eligibleForHermetic": eligible,
        "ineligibilityReason": None if eligible else
            "; ".join(reasons) + "; this profile is development evidence only",
        "distroTools": distro,
        "digestBootstrap": bootstrap,
        "systemRuntime": {"allowedLoadRoots": load_roots},
        "systemTools": tools,
    }


def self_test_tool_lock(lock: dict, host_lock: dict) -> None:
    try:
        parse_json_text('{"outer":{"id":"first","id":"second"}}',
                        "duplicate-key self-test")
    except AssetError:
        pass
    else:
        fail("self-test failed to reject duplicate JSON keys")

    if is_darwin_tool_lock(lock):
        self_test_darwin_tool_lock(lock, host_lock)
    else:
        self_test_linux_tool_lock(lock, host_lock)


def self_test_cargo_git_build_policy(lock: dict) -> None:
    cosmwasm = next(
        asset for asset in lock["assets"]
        if asset["id"] == "cosmwasm-check-3.0.9-git-fe5b55d283f5"
    )
    if cargo_git_compatibility_rust_toolchain(cosmwasm) != "1.88.0":
        fail("self-test did not select the pinned cosmwasm-check Rust toolchain")
    sbpf = next(
        asset for asset in lock["assets"]
        if asset["id"] == "sbpf-0.2.2-git-d835bc6e638e"
    )
    if cargo_git_compatibility_rust_toolchain(sbpf) is not None:
        fail("self-test unexpectedly overrode the sbpf Rust toolchain")

    staging = Path("/proof-forge/cargo-git-staging")
    rustup_home = Path("/proof-forge/rustup")
    pinned_env = cargo_git_build_environment(
        staging, rustup_home, "1.88.0", "/host/bin"
    )
    expected_pinned_env = {
        "LC_ALL": "C",
        "TZ": "UTC",
        "HOME": str(staging / ".proof-forge-home"),
        "PATH": "/host/bin",
        "CARGO_HOME": str(staging / ".proof-forge-cargo-home"),
        "RUSTUP_HOME": str(rustup_home),
        "RUSTUP_TOOLCHAIN": "1.88.0",
    }
    if pinned_env != expected_pinned_env:
        fail("self-test observed a non-isolated pinned cargo-git build environment")
    ambient_env = cargo_git_build_environment(
        staging, rustup_home, None, "/host/bin"
    )
    expected_ambient_env = dict(expected_pinned_env)
    del expected_ambient_env["RUSTUP_TOOLCHAIN"]
    if ambient_env != expected_ambient_env:
        fail("self-test observed a non-isolated ambient cargo-git build environment")

    expected_marker = (
        b"proof-forge.cargo-git-build-policy.v1\n"
        b"rust-toolchain=1.88.0\n"
    )
    if cargo_git_build_policy_bytes(cosmwasm) != expected_marker:
        fail("self-test observed the wrong cosmwasm-check build-policy marker")
    if cargo_git_build_policy_bytes(sbpf) is not None:
        fail("self-test unexpectedly created an sbpf build-policy marker")

    with tempfile.TemporaryDirectory() as temporary:
        cache_dir = Path(temporary)
        if cargo_git_cached_policy_matches(cosmwasm, cache_dir):
            fail("self-test accepted a missing cargo-git build-policy marker")
        marker = cache_dir / CARGO_GIT_BUILD_POLICY_MARKER
        marker.write_bytes(expected_marker)
        os.chmod(marker, 0o444)
        if not cargo_git_cached_policy_matches(cosmwasm, cache_dir):
            fail("self-test rejected the exact cargo-git build-policy marker")
        os.chmod(marker, 0o644)
        if cargo_git_cached_policy_matches(cosmwasm, cache_dir):
            fail("self-test accepted a writable cargo-git build-policy marker")
        marker.unlink()
        target = cache_dir / "marker-target"
        target.write_bytes(expected_marker)
        os.chmod(target, 0o444)
        marker.symlink_to(target.name)
        if cargo_git_cached_policy_matches(cosmwasm, cache_dir):
            fail("self-test accepted a symlink cargo-git build-policy marker")


def self_test_cargo_git_mutations(lock: dict) -> None:
    mutations: list[tuple[str, dict]] = []
    bad_commit = copy.deepcopy(lock)
    cargo = next(a for a in bad_commit["assets"] if a.get("format") == "cargo-git")
    cargo["commit"] = "not-a-commit"
    mutations.append(("cargo-git bad commit", bad_commit))
    bad_package = copy.deepcopy(lock)
    cargo = next(a for a in bad_package["assets"] if a.get("format") == "cargo-git")
    cargo["package"] = "../escape"
    mutations.append(("cargo-git bad package", bad_package))
    bad_bin = copy.deepcopy(lock)
    cargo = next(a for a in bad_bin["assets"] if a.get("format") == "cargo-git")
    cargo["bin"] = ""
    mutations.append(("cargo-git empty bin", bad_bin))
    missing_bin = copy.deepcopy(lock)
    cargo = next(a for a in missing_bin["assets"] if a.get("format") == "cargo-git")
    del cargo["bin"]
    mutations.append(("cargo-git missing bin field", missing_bin))
    source_hash = copy.deepcopy(lock)
    sb = next(t for t in source_hash["tools"] if t.get("sourceBuild") is not None)
    sb["executableSha256"] = "0" * 64
    mutations.append(("sourceBuild with executableSha256", source_hash))
    source_runtime = copy.deepcopy(lock)
    sb = next(t for t in source_runtime["tools"] if t.get("sourceBuild") is not None)
    sb["runtimeFiles"] = [{"path": "lib/x", "sha256": "0" * 64}]
    mutations.append(("sourceBuild with runtimeFiles", source_runtime))
    version_mismatch = copy.deepcopy(lock)
    sb = next(t for t in version_mismatch["tools"] if t.get("sourceBuild") is not None)
    sb["version"] = "9.9.9"
    mutations.append(("sourceBuild version mismatch", version_mismatch))
    cargo_without_source = copy.deepcopy(lock)
    sb = next(t for t in cargo_without_source["tools"] if t.get("sourceBuild") is not None)
    sb["sourceBuild"] = None
    sb["executableSha256"] = "0" * 64
    mutations.append(("cargo-git tool without sourceBuild", cargo_without_source))
    bundle_cargo = copy.deepcopy(lock)
    cargo = next(a for a in bundle_cargo["assets"] if a.get("format") == "cargo-git")
    bundle_cargo["bundleFiles"].append({
        "path": "from-cargo",
        "assetId": cargo["id"],
        "member": None,
        "size": 1,
        "sha256": "0" * 64,
        "mode": "0555",
    })
    # keep bundleFiles sorted by path
    bundle_cargo["bundleFiles"] = sorted(
        bundle_cargo["bundleFiles"], key=lambda r: r["path"])
    mutations.append(("bundleFiles referencing cargo-git", bundle_cargo))
    for name, candidate in mutations:
        try:
            validate_tool_lock(candidate)
        except AssetError:
            continue
        fail(f"self-test failed to reject {name}")
    self_test_cargo_git_build_policy(lock)


def self_test_darwin_tool_lock(lock: dict, host_lock: dict) -> None:
    mutations: list[tuple[str, dict]] = []
    duplicate = copy.deepcopy(lock)
    duplicate["assets"].append(copy.deepcopy(duplicate["assets"][0]))
    mutations.append(("duplicate asset", duplicate))
    traversal = copy.deepcopy(lock)
    traversal["bundleFiles"][0]["path"] = "../escape"
    mutations.append(("bundle path traversal", traversal))
    non_normal_path = copy.deepcopy(lock)
    non_normal_path["bundleFiles"][0]["path"] = "bin//tool"
    mutations.append(("non-normal bundle path", non_normal_path))
    mismatch = copy.deepcopy(lock)
    content_tool = next(t for t in mismatch["tools"] if t.get("sourceBuild") is None)
    content_tool["executableSha256"] = "0" * 64
    mutations.append(("tool/bundle hash mismatch", mismatch))
    insecure_url = copy.deepcopy(lock)
    download = next(a for a in insecure_url["assets"] if a.get("format") in DOWNLOAD_FORMATS)
    download["url"] = "http://example.invalid/tool"
    mutations.append(("insecure URL", insecure_url))
    unknown_field = copy.deepcopy(lock)
    download = next(a for a in unknown_field["assets"] if a.get("format") in DOWNLOAD_FORMATS)
    download["unexpected"] = True
    mutations.append(("unknown asset field", unknown_field))
    unsafe_id = copy.deepcopy(lock)
    download = next(a for a in unsafe_id["assets"] if a.get("format") in DOWNLOAD_FORMATS)
    download["id"] = "../escape"
    mutations.append(("unsafe asset id", unsafe_id))
    missing_compiler_field = copy.deepcopy(lock)
    missing_compiler_field["compilerToolchain"].pop("sourceCommit")
    mutations.append(("missing compiler field", missing_compiler_field))
    invalid_entry_count = copy.deepcopy(lock)
    invalid_entry_count["compilerToolchain"]["entryCount"] = 0
    mutations.append(("invalid compiler entry count", invalid_entry_count))
    boolean_strip_components = copy.deepcopy(lock)
    boolean_strip_components["compilerToolchain"]["stripComponents"] = True
    mutations.append(("boolean compiler strip components", boolean_strip_components))
    invalid_compiler_version = copy.deepcopy(lock)
    invalid_compiler_version["compilerToolchain"]["version"] = "latest"
    mutations.append(("invalid compiler version", invalid_compiler_version))
    invalid_unpacked_size = copy.deepcopy(lock)
    invalid_unpacked_size["compilerToolchain"]["unpackedSize"] = MAX_COMPILER_UNPACKED_BYTES + 1
    mutations.append(("invalid compiler unpacked size", invalid_unpacked_size))
    missing_version_probe = copy.deepcopy(lock)
    missing_version_probe["compilerToolchain"]["versionProbes"].pop()
    mutations.append(("missing compiler version probe", missing_version_probe))
    foreign_version_probe = copy.deepcopy(lock)
    foreign_version_probe["compilerToolchain"]["versionProbes"][0]["path"] = "bin/foreign"
    mutations.append(("foreign compiler version probe", foreign_version_probe))
    tool_asset_mismatch = copy.deepcopy(lock)
    content_tool = next(t for t in tool_asset_mismatch["tools"] if t.get("sourceBuild") is None)
    content_tool["assetId"] = lock["compilerToolchain"]["assetId"]
    mutations.append(("tool/executable asset mismatch", tool_asset_mismatch))
    invalid_tool_version = copy.deepcopy(lock)
    content_tool = next(t for t in invalid_tool_version["tools"] if t.get("sourceBuild") is None)
    content_tool["version"] = "01.0.0"
    mutations.append(("invalid tool version", invalid_tool_version))
    invalid_unresolved_version = copy.deepcopy(lock)
    invalid_unresolved_version["unresolved"]["nearSandbox"] = "^2.13"
    mutations.append(("invalid unresolved version", invalid_unresolved_version))
    over_u64_version = copy.deepcopy(lock)
    over_u64_version["unresolved"]["nearSandbox"] = "18446744073709551616.0.0"
    mutations.append(("over-UInt64 unresolved version", over_u64_version))
    runtime_closure_mismatch = copy.deepcopy(lock)
    next(tool for tool in runtime_closure_mismatch["tools"]
         if tool["id"] == "wat2wasm")["runtimeFiles"] = []
    mutations.append(("runtime closure mismatch", runtime_closure_mismatch))
    legacy_schema = copy.deepcopy(lock)
    legacy_schema["schema"] = "proof-forge.toolchains.v2"
    mutations.append(("legacy v2 schema", legacy_schema))
    for name, candidate in mutations:
        try:
            validate_tool_lock(candidate)
        except AssetError:
            continue
        fail(f"self-test failed to reject {name}")

    self_test_cargo_git_mutations(lock)

    closure_classification = copy.deepcopy(lock)
    content_tool = next(
        t for t in closure_classification["tools"] if t.get("sourceBuild") is None)
    content_tool["assetId"] = lock["compilerToolchain"]["assetId"]
    try:
        validate_tool_lock(closure_classification)
    except ToolLockClosureError:
        pass
    except AssetError:
        fail("self-test classified a Tool Lock cross-reference as schema")
    else:
        fail("self-test accepted a broken Tool Lock cross-reference")

    darwin_profile_index = next(
        index for index, profile in enumerate(host_lock["profiles"])
        if host_profile_kind(profile) == "darwin"
    )
    validate_lock_pair(lock, host_lock)
    roots_mismatch = copy.deepcopy(host_lock)
    roots_mismatch["profiles"][darwin_profile_index][
        "systemRuntime"]["allowedLoadRoots"] = ["/usr/lib/"]
    validate_host_lock(roots_mismatch)
    try:
        validate_lock_pair(lock, roots_mismatch)
    except AssetError:
        pass
    else:
        fail("self-test failed to reject cross-lock runtime roots mismatch")


def self_test_host_lock_section_darwin(host_lock: dict) -> None:
    host_mutations: list[tuple[str, dict]] = []
    ineligible = copy.deepcopy(host_lock)
    ineligible["profiles"][0].pop("ineligibilityReason", None)
    host_mutations.append(("unexplained ineligible host", ineligible))
    unknown_host_field = copy.deepcopy(host_lock)
    unknown_host_field["profiles"][0]["platform"]["unexpected"] = "value"
    host_mutations.append(("unknown host field", unknown_host_field))
    relative_bootstrap = copy.deepcopy(host_lock)
    relative_bootstrap["profiles"][0]["digestBootstrap"]["path"] = "usr/bin/openssl"
    host_mutations.append(("relative digest bootstrap", relative_bootstrap))
    multiple_profiles = copy.deepcopy(host_lock)
    second_profile = copy.deepcopy(multiple_profiles["profiles"][0])
    second_profile["id"] = second_profile["id"] + "-other"
    multiple_profiles["profiles"].append(second_profile)
    host_mutations.append(("multiple host profiles", multiple_profiles))
    eligible_baseline = copy.deepcopy(host_lock)
    eligible_profile = eligible_baseline["profiles"][0]
    eligible_profile["eligibleForHermetic"] = True
    eligible_profile["ineligibilityReason"] = None
    eligible_profile["platform"].update({
        "arch": "arm64",
        "procTranslated": False,
        "sip": "enabled",
        "authenticatedRoot": "enabled",
        "systemVolumeSeal": "sealed",
    })
    eligible_profile["developerTools"]["xcodeMutableByCurrentUser"] = False
    validate_host_lock(eligible_baseline)
    eligibility_mutations = (
        ("non-arm64 eligible host", ("platform", "arch"), "x86_64"),
        ("translated eligible host", ("platform", "procTranslated"), True),
        ("SIP-disabled eligible host", ("platform", "sip"), "disabled"),
        ("authenticated-root-disabled eligible host",
         ("platform", "authenticatedRoot"), "disabled"),
        ("unsealed eligible host", ("platform", "systemVolumeSeal"), "broken"),
        ("mutable-Xcode eligible host",
         ("developerTools", "xcodeMutableByCurrentUser"), True),
    )
    for name, (section, field), value in eligibility_mutations:
        candidate = copy.deepcopy(eligible_baseline)
        candidate["profiles"][0][section][field] = value
        host_mutations.append((name, candidate))
    invalid_node_kind = copy.deepcopy(host_lock)
    invalid_node_kind["profiles"][0]["systemTools"][0]["nodeKind"] = "file"
    host_mutations.append(("invalid system tool node kind", invalid_node_kind))
    invalid_mode = copy.deepcopy(host_lock)
    invalid_mode["profiles"][0]["systemTools"][0]["mode"] = "755"
    host_mutations.append(("invalid system tool mode", invalid_mode))
    for name, candidate in host_mutations:
        try:
            validate_host_lock(candidate)
        except AssetError:
            continue
        fail(f"self-test failed to reject {name}")

def self_test_linux_tool_lock(lock: dict, host_lock: dict) -> None:
    # --- Tool Lock v4 linux (elfPolicy) fixtures ---
    linux_lock = lock

    linux_lock_mutations: list[tuple[str, dict]] = []
    v4_wrong_platform = copy.deepcopy(linux_lock)
    v4_wrong_platform["platform"] = "darwin-arm64"
    linux_lock_mutations.append(("v4 linux lock with darwin platform", v4_wrong_platform))
    legacy_v2 = copy.deepcopy(linux_lock)
    legacy_v2["schema"] = "proof-forge.toolchains.v2"
    linux_lock_mutations.append(("legacy v2 schema on linux lock", legacy_v2))
    legacy_v3 = copy.deepcopy(linux_lock)
    legacy_v3["schema"] = "proof-forge.toolchains.v3"
    linux_lock_mutations.append(("legacy v3 schema", legacy_v3))
    missing_elf_file = copy.deepcopy(linux_lock)
    del missing_elf_file["elfPolicy"]["files"][0]
    linux_lock_mutations.append(("elf policy missing a bundle file", missing_elf_file))
    unknown_elf_path = copy.deepcopy(linux_lock)
    unknown_elf_path["elfPolicy"]["files"][0]["path"] = "bin/unknown"
    linux_lock_mutations.append(("elf policy unknown bundle path", unknown_elf_path))
    unsorted_needed = copy.deepcopy(linux_lock)
    unsorted_needed["elfPolicy"]["files"][-1]["needed"] = [
        {"soname": "libz.so.1", "bundlePath": None},
        {"soname": "libc.so.6", "bundlePath": None},
    ]
    linux_lock_mutations.append(("elf needed not sorted", unsorted_needed))
    slash_soname = copy.deepcopy(linux_lock)
    slash_soname["elfPolicy"]["files"][0]["needed"] = [
        {"soname": "/etc/passwd", "bundlePath": None},
    ]
    linux_lock_mutations.append(("elf soname containing a slash", slash_soname))
    unknown_needed_bundle = copy.deepcopy(linux_lock)
    unknown_needed_bundle["elfPolicy"]["files"][0]["needed"] = [
        {"soname": "libx.so.1", "bundlePath": "bin/unknown"},
    ]
    linux_lock_mutations.append(("elf needed unknown bundle target", unknown_needed_bundle))
    relative_elf_root = copy.deepcopy(linux_lock)
    relative_elf_root["elfPolicy"]["allowedSystemLoadRoots"] = ["usr/lib/"]
    linux_lock_mutations.append(("elf policy relative load root", relative_elf_root))
    for name, candidate in linux_lock_mutations:
        try:
            validate_tool_lock(candidate)
        except AssetError:
            continue
        fail(f"self-test failed to reject {name}")

    self_test_cargo_git_mutations(linux_lock)

    validate_lock_pair(linux_lock, host_lock)
    linux_roots_mismatch = copy.deepcopy(host_lock)
    linux_profile_index = next(
        index for index, profile in enumerate(linux_roots_mismatch["profiles"])
        if host_profile_kind(profile) == "linux"
    )
    linux_roots_mismatch["profiles"][linux_profile_index][
        "systemRuntime"]["allowedLoadRoots"] = ["/usr/lib/"]
    validate_host_lock(linux_roots_mismatch)
    try:
        validate_lock_pair(linux_lock, linux_roots_mismatch)
    except AssetError:
        pass
    else:
        fail("self-test failed to reject linux cross-lock runtime roots mismatch")


def self_test_host_lock_section(host_lock: dict) -> None:
    # --- ADR-0016: Host Profile v2 (linux) fixtures ---
    linux_profile_fixture = {
        "id": "linux-x86_64-fixture-development",
        "platform": {
            "osReleaseId": "linuxmint",
            "osReleaseVersionId": "22.3",
            "kernelRelease": "6.17.0-23-generic",
            "arch": "x86_64",
            "secureBoot": "disabled",
        },
        "eligibleForHermetic": False,
        "ineligibilityReason": "fixture: secure boot is disabled",
        "distroTools": {
            "gitPath": "/usr/bin/git",
            "gitSha256": "0" * 64,
            "gitVersion": "git version 2.43.0",
            "pythonPath": "/usr/bin/python3.12",
            "pythonSha256": "0" * 64,
            "pythonVersion": "Python 3.12.3",
            "readelfPath": "/usr/bin/readelf",
            "readelfSha256": "0" * 64,
            "readelfVersion": "GNU readelf (GNU Binutils for Ubuntu) 2.42",
            "toolsMutableByCurrentUser": False,
        },
        "digestBootstrap": {
            "path": "/usr/bin/openssl",
            "sha256": "0" * 64,
            "knownAnswerInput": "abc",
            "knownAnswerSha256":
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        },
        "systemRuntime": {"allowedLoadRoots": ["/lib/", "/lib64/", "/usr/lib/"]},
        "systemTools": [
            {
                "id": "openssl",
                "path": "/usr/bin/openssl",
                "nodeKind": "regular",
                "linkTarget": None,
                "resolvedPath": "/usr/bin/openssl",
                "resolvedNlink": 1,
                "mode": "0755",
                "sha256": "0" * 64,
            },
        ],
    }
    dual_host_lock = {
        "schema": "proof-forge.host-profiles.v2",
        "profiles": [copy.deepcopy(host_lock["profiles"][0]), linux_profile_fixture],
    }
    validate_host_lock(dual_host_lock)

    v2_host_mutations: list[tuple[str, dict]] = []
    retired_v1 = copy.deepcopy(dual_host_lock)
    retired_v1["schema"] = "proof-forge.host-profiles.v1"
    v2_host_mutations.append(("retired v1 host lock schema", retired_v1))
    duplicate_kind = copy.deepcopy(dual_host_lock)
    second_linux = copy.deepcopy(linux_profile_fixture)
    second_linux["id"] = "linux-x86_64-fixture-other"
    duplicate_kind["profiles"].append(second_linux)
    v2_host_mutations.append(("two linux profiles", duplicate_kind))
    unknown_platform_keys = copy.deepcopy(dual_host_lock)
    unknown_platform_keys["profiles"][1]["platform"] = {"osReleaseId": "x"}
    v2_host_mutations.append(("unrecognized linux platform keys", unknown_platform_keys))
    free_form_secure_boot = copy.deepcopy(dual_host_lock)
    free_form_secure_boot["profiles"][1]["platform"]["secureBoot"] = "yes"
    v2_host_mutations.append(("secure boot free-form value", free_form_secure_boot))
    missing_distro_field = copy.deepcopy(dual_host_lock)
    del missing_distro_field["profiles"][1]["distroTools"]["readelfSha256"]
    v2_host_mutations.append(("missing distro tool field", missing_distro_field))
    relative_distro_path = copy.deepcopy(dual_host_lock)
    relative_distro_path["profiles"][1]["distroTools"]["gitPath"] = "usr/bin/git"
    v2_host_mutations.append(("relative distro tool path", relative_distro_path))
    linux_eligible_baseline = copy.deepcopy(dual_host_lock)
    linux_eligible_profile = linux_eligible_baseline["profiles"][1]
    linux_eligible_profile["eligibleForHermetic"] = True
    linux_eligible_profile["ineligibilityReason"] = None
    linux_eligible_profile["platform"]["secureBoot"] = "enabled"
    validate_host_lock(linux_eligible_baseline)
    for name, section, field, value in (
        ("linux eligible with secure boot disabled",
         "platform", "secureBoot", "disabled"),
        ("linux eligible with secure boot unavailable",
         "platform", "secureBoot", "unavailable"),
        ("linux eligible with a foreign arch", "platform", "arch", "riscv64"),
        ("linux eligible with mutable distro tools",
         "distroTools", "toolsMutableByCurrentUser", True),
    ):
        candidate = copy.deepcopy(linux_eligible_baseline)
        candidate["profiles"][1][section][field] = value
        v2_host_mutations.append((name, candidate))
    for name, candidate in v2_host_mutations:
        try:
            validate_host_lock(candidate)
        except AssetError:
            continue
        fail(f"self-test failed to reject {name}")

def self_test_archive_and_redirect() -> None:
    redirect_handler = StrictHTTPSRedirectHandler()
    authenticated = urllib.request.Request(
        "https://registry.example.invalid/v2/blob",
        headers={"Authorization": "Bearer secret"},
    )
    redirected = redirect_handler.redirect_request(
        authenticated, None, 302, "Found", {},
        "https://storage.example.invalid/signed/blob",
    )
    if redirected is None or redirected.has_header("Authorization"):
        fail("self-test failed to strip cross-origin redirect authorization")
    try:
        redirect_handler.redirect_request(
            authenticated, None, 302, "Found", {}, "http://registry.example.invalid/blob",
        )
    except AssetError:
        pass
    else:
        fail("self-test failed to reject an HTTPS downgrade redirect")

    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w") as archive:
        root_info = zipfile.ZipInfo("compiler/")
        root_info.create_system = 3
        root_info.external_attr = (stat.S_IFDIR | 0o755) << 16
        archive.writestr(root_info, b"")
        bin_info = zipfile.ZipInfo("compiler/bin/")
        bin_info.create_system = 3
        bin_info.external_attr = (stat.S_IFDIR | 0o755) << 16
        archive.writestr(bin_info, b"")
        file_info = zipfile.ZipInfo("compiler/bin/tool")
        file_info.create_system = 3
        file_info.external_attr = (stat.S_IFREG | 0o755) << 16
        archive.writestr(file_info, b"x")
    synthetic_compiler = {
        "archiveRoot": "compiler",
        "entryCount": 3,
        "unpackedSize": 1,
    }
    zip_buffer.seek(0)
    with zipfile.ZipFile(zip_buffer) as archive:
        validate_lean_zip(archive, synthetic_compiler, "synthetic")
        wrong_count = dict(synthetic_compiler, entryCount=4)
        try:
            validate_lean_zip(archive, wrong_count, "synthetic")
        except AssetError:
            pass
        else:
            fail("self-test failed to reject a Lean ZIP entry count mismatch")
        wrong_size = dict(synthetic_compiler, unpackedSize=2)
        try:
            validate_lean_zip(archive, wrong_size, "synthetic")
        except AssetError:
            pass
        else:
            fail("self-test failed to reject a Lean ZIP output size mismatch")

    symlink_buffer = io.BytesIO()
    with zipfile.ZipFile(symlink_buffer, "w") as archive:
        root_info = zipfile.ZipInfo("compiler/")
        root_info.create_system = 3
        root_info.external_attr = (stat.S_IFDIR | 0o755) << 16
        archive.writestr(root_info, b"")
        link_info = zipfile.ZipInfo("compiler/bin")
        link_info.create_system = 3
        link_info.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(link_info, b"target")
    symlink_buffer.seek(0)
    with zipfile.ZipFile(symlink_buffer) as archive:
        try:
            validate_lean_zip(
                archive,
                {"archiveRoot": "compiler", "entryCount": 2, "unpackedSize": 6},
                "synthetic-symlink",
            )
        except AssetError:
            pass
        else:
            fail("self-test failed to reject a Lean ZIP symlink")

    def expect_zip_rejection(name: str,
                             entries: list[tuple[str, int, bytes]],
                             unpacked_size: int) -> None:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for path, mode, payload in entries:
                info = zipfile.ZipInfo(path)
                info.create_system = 3
                info.external_attr = mode << 16
                archive.writestr(info, payload)
        buffer.seek(0)
        with zipfile.ZipFile(buffer) as archive:
            try:
                validate_lean_zip(
                    archive,
                    {
                        "archiveRoot": "compiler",
                        "entryCount": len(entries),
                        "unpackedSize": unpacked_size,
                    },
                    f"synthetic-{name}",
                )
            except AssetError:
                return
        fail(f"self-test failed to reject Lean ZIP {name}")

    directory_mode = stat.S_IFDIR | 0o755
    regular_mode = stat.S_IFREG | 0o755
    expect_zip_rejection(
        "traversal",
        [("compiler/", directory_mode, b""),
         ("compiler/../escape", regular_mode, b"x")],
        1,
    )
    expect_zip_rejection(
        "duplicate normalized path",
        [("compiler/", directory_mode, b""),
         ("compiler/bin/", directory_mode, b""),
         ("compiler/bin", regular_mode, b"x")],
        1,
    )
    expect_zip_rejection(
        "missing parent",
        [("compiler/", directory_mode, b""),
         ("compiler/bin/tool", regular_mode, b"x")],
        1,
    )
    expect_zip_rejection(
        "privilege bits",
        [("compiler/", directory_mode, b""),
         ("compiler/tool", stat.S_IFREG | 0o4755, b"x")],
        1,
    )
    expect_zip_rejection(
        "special node",
        [("compiler/", directory_mode, b""),
         ("compiler/fifo", stat.S_IFIFO | 0o644, b"x")],
        1,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, default=None)
    parser.add_argument("--host-lock", type=Path, default=DEFAULT_HOST_LOCK)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("validate")
    commands.add_parser("self-test")
    commands.add_parser("cache-root")
    observe = commands.add_parser("observe-host")
    observe.add_argument("--profile-id", required=True)
    validate_profile = commands.add_parser("validate-host-profile")
    validate_profile.add_argument("--input", type=Path, required=True)
    provision = commands.add_parser("provision")
    provision.add_argument("--group", choices=("all", "external", "lean"), default="all")
    provision.add_argument("--asset", action="append", default=[])
    external = commands.add_parser("materialize-external")
    external.add_argument("--destination", type=Path, required=True)
    verify = commands.add_parser("verify-external")
    verify.add_argument("--root", type=Path, required=True)
    lean = commands.add_parser("materialize-lean")
    lean.add_argument("--destination", type=Path, required=True)
    host = commands.add_parser("verify-host")
    host.add_argument("--profile-id", required=True)
    host.add_argument("--require-eligible", action="store_true")
    return parser


def main() -> None:
    if not sys.flags.isolated or not sys.flags.no_site:
        fail("run toolchain-assets with /usr/bin/python3 -I -S")
    args = build_parser().parse_args()
    if args.command == "observe-host":
        profile = observe_host_linux(args.profile_id)
        print(json.dumps(profile, indent=2))
        return
    if args.command == "validate-host-profile":
        validate_host_profile_file(args.input.resolve())
        return
    lock_path = args.lock if args.lock is not None else default_lock_path()
    lock, host_lock = load_locks(lock_path.resolve(), args.host_lock.resolve())
    host_platform = host_platform_id()
    if lock["platform"] != host_platform:
        fail(f"tool lock platform {lock['platform']} does not match host platform "
             f"{host_platform}")
    if args.command == "validate":
        print("toolchain-assets: lock validation ok")
    elif args.command == "self-test":
        names = list(dict.fromkeys(PLATFORM_LOCK_FILES.values()))
        paths = [path for path in (ROOT / name for name in names) if path.is_file()]
        if not paths:
            fail("no toolchain lock files found for self-test")
        for path in paths:
            self_test_tool_lock(validate_tool_lock(load_json(path.resolve())), host_lock)
        self_test_host_lock_section_darwin(host_lock)
        self_test_host_lock_section(host_lock)
        self_test_archive_and_redirect()
        print("toolchain-assets: self-test ok")
    elif args.command == "cache-root":
        print(cache_root())
    elif args.command == "provision":
        for asset in selected_assets(lock, args.group, args.asset):
            provision_asset(asset)
    elif args.command == "materialize-external":
        materialize_external(lock, host_lock, args.destination.resolve())
    elif args.command == "verify-external":
        verify_external(lock, host_lock, args.root)
    elif args.command == "materialize-lean":
        materialize_lean(lock, host_lock, args.destination.resolve())
    elif args.command == "verify-host":
        matching = [p for p in host_lock["profiles"] if p["id"] == args.profile_id]
        if len(matching) != 1:
            fail(f"unknown host profile: {args.profile_id}")
        verify_host(matching[0], require_eligible=args.require_eligible)
    else:  # pragma: no cover - argparse owns this boundary
        fail(f"unsupported command {args.command}")


if __name__ == "__main__":
    try:
        main()
    except (AssetError, OSError, subprocess.SubprocessError, tarfile.TarError,
            zipfile.BadZipFile, urllib.error.URLError) as error:
        print(f"toolchain-assets: {error}", file=sys.stderr)
        raise SystemExit(1) from error

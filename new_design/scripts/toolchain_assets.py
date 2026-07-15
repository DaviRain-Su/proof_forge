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
import json
import os
import posixpath
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.error
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath
from typing import BinaryIO, Iterator


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCK = ROOT / "toolchains.lock.json"
DEFAULT_HOST_LOCK = ROOT / "host-profiles.lock.json"
SHA256_RE = re.compile(r"[0-9a-f]{64}")
SOURCE_COMMIT_RE = re.compile(r"[0-9a-f]{40}")
SAFE_ASSET_ID_RE = re.compile(r"[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?")
SAFE_IDENTIFIER_RE = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9._-]{0,254}[A-Za-z0-9])?")
FORMATS = {"file", "tar.gz", "zip"}
MAX_ARCHIVE_MEMBERS = 100_000
MAX_OCI_TOKEN_BYTES = 64 * 1024
MAX_HTTPS_REDIRECTS = 5


class AssetError(RuntimeError):
    """A stable, user-facing asset validation failure."""


def fail(message: str) -> "None":
    raise AssetError(message)


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


def require_sha256(value: object, where: str) -> str:
    text = require_string(value, where)
    if SHA256_RE.fullmatch(text) is None:
        fail(f"{where} must be a lowercase SHA-256")
    return text


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


def validate_tool_lock(lock: dict) -> dict:
    require_keys(lock, {
        "schema", "platform", "assets", "compilerToolchain", "bundleFiles",
        "machoPolicy", "tools", "unresolved",
    }, "toolchain lock")
    if lock.get("schema") != "proof-forge.toolchains.v2":
        fail("unsupported toolchain lock schema")
    if lock.get("platform") != "darwin-arm64":
        fail("this lock must declare platform darwin-arm64")

    assets = require_list(lock.get("assets"), "assets")
    unique_sorted(assets, "id", "assets")
    asset_by_id: dict[str, dict] = {}
    for index, raw in enumerate(assets):
        asset = require_dict(raw, f"assets[{index}]")
        require_keys(asset, {"id", "url", "size", "sha256", "format"},
                     f"assets[{index}]", {"auth"})
        asset_id = require_safe_asset_id(asset.get("id"), f"assets[{index}].id")
        require_https_url(asset.get("url"), f"asset {asset_id}.url")
        size = asset.get("size")
        if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
            fail(f"asset {asset_id} size must be a positive integer")
        require_sha256(asset.get("sha256"), f"asset {asset_id}.sha256")
        if asset.get("format") not in FORMATS:
            fail(f"asset {asset_id} has unsupported format")
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
        asset_by_id[asset_id] = asset

    compiler = require_dict(lock.get("compilerToolchain"), "compilerToolchain")
    require_keys(compiler, {
        "id", "version", "sourceCommit", "platform", "assetId", "archiveRoot",
        "stripComponents", "executables", "versionArgs", "expectedVersion",
    }, "compilerToolchain")
    require_safe_asset_id(compiler.get("id"), "compilerToolchain.id")
    require_string(compiler.get("version"), "compilerToolchain.version")
    source_commit = require_string(compiler.get("sourceCommit"),
                                   "compilerToolchain.sourceCommit")
    if SOURCE_COMMIT_RE.fullmatch(source_commit) is None:
        fail("compilerToolchain.sourceCommit must be a lowercase 40-hex commit")
    if compiler.get("platform") != lock["platform"]:
        fail("compilerToolchain.platform does not match the lock")
    compiler_asset = require_string(compiler.get("assetId"), "compilerToolchain.assetId")
    if compiler_asset not in asset_by_id:
        fail("compilerToolchain references an unknown asset")
    if asset_by_id[compiler_asset]["format"] != "zip":
        fail("compilerToolchain asset must be a ZIP archive")
    archive_root = safe_relative(compiler.get("archiveRoot"), "compilerToolchain.archiveRoot")
    if len(PurePosixPath(archive_root).parts) != 1:
        fail("compilerToolchain.archiveRoot must be one path component")
    if compiler.get("stripComponents") != 1:
        fail("compilerToolchain.stripComponents must be 1")
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
    version_args = require_list(compiler.get("versionArgs"), "compilerToolchain.versionArgs")
    if not version_args or not all(isinstance(arg, str) and arg for arg in version_args):
        fail("compilerToolchain.versionArgs must contain non-empty strings")
    require_string(compiler.get("expectedVersion"), "compilerToolchain.expectedVersion")

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
            fail(f"bundle file {path} references an unknown asset")
        member = record.get("member")
        if asset_by_id[asset_id]["format"] == "file":
            if member is not None:
                fail(f"raw file asset {asset_id} must use a null member")
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
            fail(f"Mach-O policy references unknown bundle path {path}")
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
                fail(f"Mach-O external load for {path} targets an unknown bundle path")
            if bundle_path in bundle_targets:
                fail(f"Mach-O external loads for {path} repeat bundle path {bundle_path}")
            bundle_targets.add(bundle_path)
        macho_paths.add(path)
        macho_by_path[path] = record
    if macho_paths != set(bundle_by_path):
        fail("every bundle file must have an explicit Mach-O closure policy")

    tools = require_list(lock.get("tools"), "tools")
    if not tools:
        fail("tools must be non-empty")
    unique_sorted(tools, "id", "tools")
    for index, raw in enumerate(tools):
        tool = require_dict(raw, f"tools[{index}]")
        require_keys(tool, {
            "id", "version", "sourceUrl", "platform", "assetId", "executable",
            "defaultPath", "executableSha256", "runtimeLibrarySubdir",
            "runtimeFiles", "versionArgs", "expectedVersion", "licenseSpdx",
            "requiredByProfiles",
        }, f"tools[{index}]")
        tool_id = require_safe_asset_id(tool.get("id"), f"tools[{index}].id")
        require_string(tool.get("version"), f"tool {tool_id}.version")
        require_https_url(tool.get("sourceUrl"), f"tool {tool_id}.sourceUrl")
        if tool.get("platform") != lock["platform"]:
            fail(f"tool {tool_id} platform does not match the lock")
        tool_asset = require_string(tool.get("assetId"), f"tool {tool_id}.assetId")
        if tool_asset not in asset_by_id:
            fail(f"tool {tool_id} references an unknown asset")
        executable = safe_relative(tool.get("executable"), f"tool {tool_id}.executable")
        if executable not in bundle_by_path:
            fail(f"tool {tool_id} executable is absent from bundleFiles")
        if bundle_by_path[executable]["assetId"] != tool_asset:
            fail(f"tool {tool_id} asset disagrees with its executable bundle asset")
        default_path = require_string(tool.get("defaultPath"), f"tool {tool_id}.defaultPath")
        if (not default_path.startswith("~/") or "\\" in default_path or
                posixpath.normpath(default_path[2:]) != default_path[2:] or
                PurePosixPath(default_path[2:]).name != PurePosixPath(executable).name):
            fail(f"tool {tool_id} defaultPath must be a normalized home-relative executable path")
        executable_hash = require_sha256(tool.get("executableSha256"),
                                           f"tool {tool_id}.executableSha256")
        if executable_hash != bundle_by_path[executable]["sha256"]:
            fail(f"tool {tool_id} executable hash disagrees with bundleFiles")
        runtime_subdir = tool.get("runtimeLibrarySubdir")
        if runtime_subdir is not None:
            runtime_subdir = safe_relative(runtime_subdir, f"tool {tool_id}.runtimeLibrarySubdir")
        runtime_files = require_list(tool.get("runtimeFiles"), f"tool {tool_id}.runtimeFiles")
        unique_sorted(runtime_files, "path", f"tool {tool_id}.runtimeFiles")
        declared_runtime: set[str] = set()
        for runtime in runtime_files:
            runtime = require_dict(runtime, f"tool {tool_id}.runtimeFiles[]")
            require_keys(runtime, {"path", "sha256"}, f"tool {tool_id}.runtimeFiles[]")
            runtime_path = safe_relative(runtime.get("path"), f"tool {tool_id} runtime file path")
            if runtime_path not in bundle_by_path:
                fail(f"tool {tool_id} runtime file is absent from bundleFiles")
            runtime_hash = require_sha256(runtime.get("sha256"),
                                             f"tool {tool_id} runtime file sha256")
            if runtime_hash != bundle_by_path[runtime_path]["sha256"]:
                fail(f"tool {tool_id} runtime file hash disagrees with bundleFiles")
            declared_runtime.add(runtime_path)

        pending = [edge["bundlePath"] for edge in macho_by_path[executable]["externalLoads"]]
        closure: set[str] = set()
        while pending:
            dependency = pending.pop()
            if dependency in closure:
                continue
            if dependency == executable:
                fail(f"tool {tool_id} Mach-O bundle closure cycles to its executable")
            closure.add(dependency)
            pending.extend(edge["bundlePath"]
                           for edge in macho_by_path[dependency]["externalLoads"])
        if declared_runtime != closure:
            fail(f"tool {tool_id} runtimeFiles do not equal its Mach-O bundle closure")
        if closure and runtime_subdir is None:
            fail(f"tool {tool_id} with runtime files must declare runtimeLibrarySubdir")
        if not closure and runtime_subdir is not None:
            fail(f"tool {tool_id} without runtime files must not declare runtimeLibrarySubdir")
        if runtime_subdir is not None and any(
                not path.startswith(runtime_subdir + "/") for path in closure):
            fail(f"tool {tool_id} runtime file is outside runtimeLibrarySubdir")
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
            require_string(value, f"unresolved.{field}")

    return lock


def validate_host_lock(lock: dict) -> dict:
    require_keys(lock, {"schema", "profiles"}, "host profile lock")
    if lock.get("schema") != "proof-forge.host-profiles.v1":
        fail("unsupported host profile lock schema")
    profiles = require_list(lock.get("profiles"), "profiles")
    if not profiles:
        fail("host profile lock must contain at least one profile")
    unique_sorted(profiles, "id", "profiles")
    for index, raw in enumerate(profiles):
        profile = require_dict(raw, f"profiles[{index}]")
        require_keys(profile, {
            "id", "platform", "eligibleForHermetic", "ineligibilityReason",
            "developerTools", "digestBootstrap", "systemRuntime", "systemTools",
        }, f"profiles[{index}]")
        profile_id = require_safe_identifier(profile.get("id"), f"profiles[{index}].id")
        platform = require_dict(profile.get("platform"), f"profile {profile_id}.platform")
        require_keys(platform, {
            "productVersion", "buildVersion", "kernelRelease", "arch", "procTranslated",
            "sip", "authenticatedRoot", "systemVolumeSeal",
        }, f"profile {profile_id}.platform")
        for field in ("productVersion", "buildVersion", "kernelRelease", "arch",
                      "sip", "authenticatedRoot", "systemVolumeSeal"):
            require_string(platform.get(field), f"profile {profile_id}.platform.{field}")
        if not isinstance(platform.get("procTranslated"), bool):
            fail(f"profile {profile_id}.platform.procTranslated must be boolean")
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
            require_keys(tool, {"id", "path", "sha256"},
                         f"profile {profile_id}.systemTools[]")
            require_safe_asset_id(tool.get("id"), f"profile {profile_id} system tool id")
            require_absolute_file_path(tool.get("path"),
                                       f"profile {profile_id} system tool path")
            require_sha256(tool.get("sha256"), f"profile {profile_id} system tool sha256")
        developer = require_dict(profile.get("developerTools"), f"profile {profile_id}.developerTools")
        require_keys(developer, {
            "developerDir", "xcodeVersion", "xcodeBuildVersion", "gitPath", "gitSha256",
            "gitVersion", "otoolPath", "otoolSha256", "pythonPath", "pythonSha256",
            "pythonVersion",
        }, f"profile {profile_id}.developerTools")
        require_absolute_file_path(developer.get("developerDir"),
                                   f"profile {profile_id}.developerTools.developerDir")
        for field in ("xcodeVersion", "xcodeBuildVersion", "gitVersion", "pythonVersion"):
            require_string(developer.get(field), f"profile {profile_id}.developerTools.{field}")
        for field in ("gitSha256", "pythonSha256", "otoolSha256"):
            require_sha256(developer.get(field), f"profile {profile_id}.developerTools.{field}")
        for field in ("gitPath", "pythonPath", "otoolPath"):
            require_absolute_file_path(developer.get(field),
                                       f"profile {profile_id}.developerTools.{field}")
    return lock


def validate_lock_pair(tool_lock: dict, host_lock: dict) -> None:
    expected = tool_lock["machoPolicy"]["allowedSystemLoadRoots"]
    for profile in host_lock["profiles"]:
        observed = profile["systemRuntime"]["allowedLoadRoots"]
        if observed != expected:
            fail(f"profile {profile['id']} system runtime roots disagree with Mach-O policy")


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")
    return require_dict(value, str(path))


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
    digest = require_sha256(asset.get("sha256"), f"asset {asset_id}.sha256")
    root = cache_root()
    path = root / "sha256" / digest / asset_id
    if path.parent.parent.parent != root:
        fail(f"cached asset {asset_id} escaped the cache root")
    return path


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


def safe_https_open(request: urllib.request.Request, timeout: int):
    https_origin(request.full_url)
    opener = urllib.request.build_opener(StrictHTTPSRedirectHandler())
    response = opener.open(request, timeout=timeout)  # noqa: S310 - HTTPS enforced above
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


def provision_asset(asset: dict) -> Path:
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


def verify_external_tree(root: Path, bundle: dict[str, dict]) -> Path:
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

    expected_files = set(bundle)
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


def verify_external(lock: dict, host_lock: dict, root: Path) -> None:
    bundle = {record["path"]: record for record in lock["bundleFiles"]}
    root = verify_external_tree(root, bundle)

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

    tool_by_id = {tool["id"]: tool for tool in lock["tools"]}
    for tool_id in sorted(tool_by_id):
        tool = tool_by_id[tool_id]
        environment = {
            "HOME": "/var/empty",
            "LC_ALL": "C",
            "PATH": "/usr/bin:/bin",
            "TZ": "UTC",
            "DYLD_LIBRARY_PATH": str(root / "lib"),
            "DYLD_PRINT_LIBRARIES": "1",
        }
        probe = subprocess.run(
            [str(root / tool["executable"]), *tool["versionArgs"]],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
            timeout=10,
        )
        observed_version = probe.stdout + probe.stderr
        if probe.returncode != 0 or tool["expectedVersion"] not in observed_version:
            fail(f"external tool version probe failed for {tool_id}")
        loaded: set[Path] = set()
        for line in probe.stderr.splitlines():
            match = re.fullmatch(r"dyld\[\d+\]: <[^>]+> (/.+)", line)
            if match is not None:
                loaded.add(Path(match.group(1)))
        if not loaded:
            fail(f"DYLD load observation was empty for {tool_id}")
        for path in loaded:
            text = str(path)
            if text == str(root / tool["executable"]):
                continue
            if text.startswith(str(root) + "/") or text.startswith(system_roots):
                continue
            fail(f"external tool {tool_id} loaded outside its closure: {text}")
        macho = next(item for item in lock["machoPolicy"]["files"]
                     if item["path"] == tool["executable"])
        for edge in macho["externalLoads"]:
            required = (root / edge["bundlePath"]).resolve()
            if required not in loaded:
                fail(f"external tool {tool_id} did not load bundled {edge['bundlePath']}")
    print(f"toolchain-assets: verified Mach-O and runtime closure {root}")


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
        verify_external(lock, host_lock, staging)
        os.replace(staging, destination)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print(f"toolchain-assets: materialized external tool root {destination}")


def safe_zip_name(name: str, root: str) -> PurePosixPath | None:
    if "\x00" in name or "\\" in name or name.startswith("/"):
        fail(f"unsafe Lean ZIP path: {name!r}")
    path = PurePosixPath(name)
    if any(part in {"", ".", ".."} for part in path.parts):
        fail(f"non-normal Lean ZIP path: {name!r}")
    if not path.parts or path.parts[0] != root:
        fail(f"Lean ZIP has an unexpected top-level path: {name!r}")
    if len(path.parts) == 1:
        return None
    return PurePosixPath(*path.parts[1:])


def materialize_lean(lock: dict, destination: Path) -> None:
    compiler = lock["compilerToolchain"]
    asset = asset_map(lock)[compiler["assetId"]]
    staging = prepare_destination(destination)
    seen: set[str] = set()
    try:
        with cached_asset_snapshot(asset) as snapshot:
            with zipfile.ZipFile(snapshot) as archive:
                members = archive.infolist()
                if len(members) > MAX_ARCHIVE_MEMBERS:
                    fail(f"asset {asset['id']} exceeds the archive member limit")
                for info in members:
                    relative = safe_zip_name(info.filename.rstrip("/"),
                                             compiler["archiveRoot"])
                    if relative is None:
                        continue
                    normalized = relative.as_posix()
                    if normalized in seen:
                        fail(f"duplicate Lean ZIP path: {normalized}")
                    seen.add(normalized)
                    mode = info.external_attr >> 16
                    if stat.S_ISLNK(mode):
                        fail(f"Lean ZIP symlink is forbidden: {normalized}")
                    output = staging / normalized
                    if info.is_dir():
                        output.mkdir(parents=True, exist_ok=True)
                        continue
                    file_type = stat.S_IFMT(mode)
                    if file_type not in {0, stat.S_IFREG}:
                        fail(f"Lean ZIP special file is forbidden: {normalized}")
                    output.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(info, "r") as source, output.open("xb") as target:
                        shutil.copyfileobj(source, target, length=1024 * 1024)
                    os.chmod(output, 0o555 if mode & 0o111 else 0o444)
        for record in compiler["executables"]:
            path = staging / record["path"]
            if not path.is_file() or path.is_symlink():
                fail(f"Lean executable is missing: {record['path']}")
            actual = sha256_file(path)
            if actual != record["sha256"]:
                fail(f"Lean executable hash mismatch for {record['path']}: {actual}")
        environment = {"HOME": str(staging / ".home"), "LC_ALL": "C", "TZ": "UTC"}
        probe = subprocess.run(
            [str(staging / "bin/lean"), *compiler["versionArgs"]],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
            timeout=10,
        )
        observed = probe.stdout + probe.stderr
        if probe.returncode != 0 or compiler["expectedVersion"] not in observed:
            fail(f"Lean version probe failed: {observed.strip()}")
        os.replace(staging, destination)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print(f"toolchain-assets: materialized Lean toolchain {destination}")


def self_test(lock: dict, host_lock: dict) -> None:
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
    mismatch["tools"][0]["executableSha256"] = "0" * 64
    mutations.append(("tool/bundle hash mismatch", mismatch))
    insecure_url = copy.deepcopy(lock)
    insecure_url["assets"][0]["url"] = "http://example.invalid/tool"
    mutations.append(("insecure URL", insecure_url))
    unknown_field = copy.deepcopy(lock)
    unknown_field["assets"][0]["unexpected"] = True
    mutations.append(("unknown asset field", unknown_field))
    unsafe_id = copy.deepcopy(lock)
    unsafe_id["assets"][0]["id"] = "../escape"
    mutations.append(("unsafe asset id", unsafe_id))
    missing_compiler_field = copy.deepcopy(lock)
    missing_compiler_field["compilerToolchain"].pop("sourceCommit")
    mutations.append(("missing compiler field", missing_compiler_field))
    tool_asset_mismatch = copy.deepcopy(lock)
    tool_asset_mismatch["tools"][0]["assetId"] = lock["compilerToolchain"]["assetId"]
    mutations.append(("tool/executable asset mismatch", tool_asset_mismatch))
    runtime_closure_mismatch = copy.deepcopy(lock)
    next(tool for tool in runtime_closure_mismatch["tools"]
         if tool["id"] == "wat2wasm")["runtimeFiles"] = []
    mutations.append(("runtime closure mismatch", runtime_closure_mismatch))
    for name, candidate in mutations:
        try:
            validate_tool_lock(candidate)
        except AssetError:
            continue
        fail(f"self-test failed to reject {name}")
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
    for name, candidate in host_mutations:
        try:
            validate_host_lock(candidate)
        except AssetError:
            continue
        fail(f"self-test failed to reject {name}")

    roots_mismatch = copy.deepcopy(host_lock)
    roots_mismatch["profiles"][0]["systemRuntime"]["allowedLoadRoots"] = ["/usr/lib/"]
    validate_host_lock(roots_mismatch)
    try:
        validate_lock_pair(lock, roots_mismatch)
    except AssetError:
        pass
    else:
        fail("self-test failed to reject cross-lock runtime roots mismatch")

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
    print("toolchain-assets: self-test ok")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--host-lock", type=Path, default=DEFAULT_HOST_LOCK)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("validate")
    commands.add_parser("self-test")
    commands.add_parser("cache-root")
    provision = commands.add_parser("provision")
    provision.add_argument("--group", choices=("all", "external", "lean"), default="all")
    provision.add_argument("--asset", action="append", default=[])
    external = commands.add_parser("materialize-external")
    external.add_argument("--destination", type=Path, required=True)
    verify = commands.add_parser("verify-external")
    verify.add_argument("--root", type=Path, required=True)
    lean = commands.add_parser("materialize-lean")
    lean.add_argument("--destination", type=Path, required=True)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    lock, host_lock = load_locks(args.lock.resolve(), args.host_lock.resolve())
    if args.command == "validate":
        print("toolchain-assets: lock validation ok")
    elif args.command == "self-test":
        self_test(lock, host_lock)
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
        materialize_lean(lock, args.destination.resolve())
    else:  # pragma: no cover - argparse owns this boundary
        fail(f"unsupported command {args.command}")


if __name__ == "__main__":
    try:
        main()
    except (AssetError, OSError, subprocess.SubprocessError, tarfile.TarError,
            zipfile.BadZipFile, urllib.error.URLError) as error:
        print(f"toolchain-assets: {error}", file=sys.stderr)
        raise SystemExit(1) from error

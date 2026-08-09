#!/usr/bin/env python3
"""Explicit Aleo DevNet/Testnet deploy engine with a separate receipt.

This is a host-heavy engineering path. It consumes an existing, inspected
`proof-forge.output.v1` Aleo compile-profile directory. It never rebuilds the
program and never mutates build Finalize/OutputSet.

Mainnet and canary deployment are deliberately unsupported. Testnet requires a
regular, single-link, owner-only private-key file plus an explicit SHA-256 pin
for the out-of-Tool-Lock snarkOS binary. DevNet uses a funded local `--dev-key`
and therefore does not need a token or private-key file.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import ipaddress
import json
import os
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path, PurePosixPath
from typing import Any, NamedTuple, Sequence

RECEIPT_SCHEMA = "proof-forge.aleo-deployment-receipt.engineering.v1"
RECEIPT_SCHEMA_VERSION = "1.0.0"
RECEIPT_DOMAIN = b"pf.aleo-deployment-receipt.engineering.v1\x00"
OUTPUT_SCHEMA = "proof-forge.output.v1"
ALEO_COMPILE_PROFILE = "aleo-leo-4.0.2-u64-compile-v1"
SNARKOS_VERSION = "4.9.0"
DEFAULT_PUBLIC_ENDPOINT = "https://api.explorer.provable.com/v2"
DEFAULT_DEVNET_CONSENSUS_HEIGHTS = "0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17"
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_ARTIFACT_BYTES = 64 * 1024 * 1024
MAX_SNARKOS_BYTES = 512 * 1024 * 1024
MAX_OUTPUT_TREE_BYTES = 80 * 1024 * 1024
MAX_OUTPUT_TREE_ENTRIES = 1024
MAX_TOOL_OUTPUT_BYTES = 1024 * 1024
PROGRAM_ID_RE = re.compile(r"^[a-z][a-z0-9_]{0,30}\.aleo$")
PROGRAM_DECL_RE = re.compile(r"\A\s*program\s+([a-z][a-z0-9_]{0,30}\.aleo)\s*;")
TX_ID_RE = re.compile(r"\bat1[0-9a-z]{20,}\b")
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")


class AleoNetworkError(RuntimeError):
    exit_code = 7
    prefix = "PF-NETWORK-DEPLOY"

    def render(self) -> str:
        return f"{self.prefix}: {self}"


class NetworkConfigError(AleoNetworkError):
    exit_code = 2
    prefix = "PF-NETWORK-MISSING"


class ToolchainError(AleoNetworkError):
    exit_code = 2
    prefix = "PF-TOOLCHAIN-MISSING"


class OutputInputError(AleoNetworkError):
    exit_code = 6
    prefix = "PF-OUTPUT-MANIFEST"


class DeploymentError(AleoNetworkError):
    exit_code = 7
    prefix = "PF-NETWORK-DEPLOY"


class ReceiptError(AleoNetworkError):
    exit_code = 7
    prefix = "PF-NETWORK-RECEIPT"


class EndpointInfo(NamedTuple):
    network: str
    environment: str
    rest_network: str
    network_id: int
    base_url: str
    endpoint_sha256: str
    suggested_profile_id: str


class FileIdentity(NamedTuple):
    device: int
    inode: int
    owner: int
    mode: int
    links: int
    size: int
    modified_ns: int
    changed_ns: int


class SignerInfo(NamedTuple):
    tool_args: tuple[str, ...]
    receipt_kind: str
    public_receipt: dict[str, Any]
    redactions: tuple[str, ...] = ()
    private_key_path: Path | None = None
    private_key_identity: FileIdentity | None = None


class DeploymentInput(NamedTuple):
    output_dir: Path
    program_id: str
    artifact_program_name: str
    codegen_profile: str
    build_deployable: bool
    source_hash: str
    semantic_hash: str
    build_identity_digest: str
    plan_digest: str
    support_claim_digest: str
    registry_root_digest: str
    output_set_digest: str
    evidence_sha256: str
    instructions_bytes: bytes
    program_json_bytes: bytes
    instructions_sha256: str
    program_json_sha256: str


class ProcessResult(NamedTuple):
    returncode: int
    output: str


class ProcessRunError(DeploymentError):
    def __init__(
        self,
        message: str,
        *,
        output: str,
        returncode: int | None = None,
        timed_out: bool = False,
    ) -> None:
        super().__init__(message)
        self.output = output
        self.returncode = returncode
        self.timed_out = timed_out


class ProcessInterrupted(KeyboardInterrupt):
    def __init__(self, output: str) -> None:
        super().__init__()
        self.output = output


class SnarkosActionError(DeploymentError):
    def __init__(
        self,
        label: str,
        *,
        output: str,
        returncode: int | None,
        timed_out: bool,
    ) -> None:
        outcome = "timed out" if timed_out else f"failed with exit {returncode}"
        super().__init__(f"{label} {outcome}")
        self.output = output
        self.returncode = returncode
        self.timed_out = timed_out


class SnarkosActionInterrupted(KeyboardInterrupt):
    def __init__(self, label: str, output: str) -> None:
        super().__init__()
        self.label = label
        self.output = output


class ExecutionLog(NamedTuple):
    function: str
    inputs: tuple[str, ...]
    status: str
    output: str
    tool_exit_code: int | None


class SnarkosTool(NamedTuple):
    path: Path
    exec_path: str
    fd: int
    identity: FileIdentity
    version_line: str
    content_sha256: str


class ReceiptReservation(NamedTuple):
    destination: Path
    staging: Path
    parent_fd: int
    staging_fd: int


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _require_hex64(value: Any, label: str) -> str:
    if not isinstance(value, str) or HEX64_RE.fullmatch(value) is None:
        raise OutputInputError(f"{label} must be 64 lowercase hexadecimal characters")
    return value


def _reject_nul_or_control(value: str, label: str) -> None:
    if not value or any(ord(ch) < 0x20 or ord(ch) == 0x7F for ch in value):
        raise NetworkConfigError(f"{label} must be nonempty and contain no control characters")


def _canonical_path_no_symlink_existing(path: Path, *, label: str) -> Path:
    if not path.is_absolute():
        path = Path.cwd() / path
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current = current / component
        try:
            mode = current.lstat().st_mode
        except OSError as error:
            raise OutputInputError(f"cannot stat {label} path component: {error}") from error
        if stat.S_ISLNK(mode):
            raise OutputInputError(f"{label} path cannot contain symbolic links")
    return path.resolve(strict=True)


def _canonical_receipt_destination(path: Path) -> Path:
    if path.name in {"", ".", ".."}:
        raise ReceiptError("receipt directory must have a safe final component")
    if not path.is_absolute():
        path = Path.cwd() / path
    parent = path.parent
    current = Path(parent.anchor)
    for component in parent.parts[1:]:
        current = current / component
        try:
            mode = current.lstat().st_mode
        except OSError as error:
            raise ReceiptError(
                "receipt parent must already exist and contain no symbolic links"
            ) from error
        if stat.S_ISLNK(mode):
            raise ReceiptError("receipt parent path cannot contain symbolic links")
        if not stat.S_ISDIR(mode):
            raise ReceiptError("receipt parent path component must be a directory")
    return parent.resolve(strict=True) / path.name


def _is_equal_or_nested(a: Path, b: Path) -> bool:
    try:
        a.relative_to(b)
        return True
    except ValueError:
        pass
    try:
        b.relative_to(a)
        return True
    except ValueError:
        return False


def _reject_output_receipt_overlap(output_dir: Path, receipt_dir: Path) -> None:
    if _is_equal_or_nested(output_dir, receipt_dir):
        raise ReceiptError("--output-dir and --receipt-dir must not be equal, ancestors, or descendants")


def _canonical_host(host: str) -> str:
    lowered = host.lower()
    try:
        address = ipaddress.ip_address(lowered)
    except ValueError:
        try:
            lowered.encode("ascii")
        except UnicodeEncodeError as error:
            raise NetworkConfigError("endpoint host must be ASCII") from error
        if not re.fullmatch(r"[a-z0-9.-]+", lowered):
            raise NetworkConfigError("endpoint host has unsupported characters")
        if lowered.startswith(".") or lowered.endswith(".") or ".." in lowered:
            raise NetworkConfigError("endpoint host is not canonical")
        return lowered
    if isinstance(address, ipaddress.IPv6Address):
        return f"[{address.compressed}]"
    return address.compressed


def _host_is_loopback(host: str) -> bool:
    if host.lower() == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def normalize_endpoint(network: str, raw: str) -> EndpointInfo:
    """Validate and canonicalize the endpoint without network I/O."""
    if network in {"mainnet", "canary"}:
        raise NetworkConfigError(f"{network} deployment is disabled by product policy; use devnet or testnet")
    if network not in {"devnet", "testnet"}:
        raise NetworkConfigError("--network must be exactly devnet or testnet")
    _reject_nul_or_control(raw, "endpoint")
    try:
        parsed = urllib.parse.urlsplit(raw)
        port = parsed.port
    except ValueError as error:
        raise NetworkConfigError(f"invalid endpoint URL: {error}") from error
    if parsed.scheme.lower() not in {"http", "https"}:
        raise NetworkConfigError("endpoint scheme must be http or https")
    if parsed.username is not None or parsed.password is not None:
        raise NetworkConfigError("endpoint userinfo is forbidden")
    if parsed.query or parsed.fragment:
        raise NetworkConfigError("endpoint query and fragment are forbidden")
    if not parsed.hostname:
        raise NetworkConfigError("endpoint host is required")
    if any(ch.isspace() for ch in raw):
        raise NetworkConfigError("endpoint whitespace is forbidden")
    host = parsed.hostname
    loopback = _host_is_loopback(host)
    scheme = parsed.scheme.lower()
    if network == "devnet":
        if not loopback:
            raise NetworkConfigError("devnet endpoint must use localhost or a loopback IP")
    else:
        if scheme != "https":
            raise NetworkConfigError("public testnet endpoint must use https")
        if loopback:
            raise NetworkConfigError("public testnet endpoint cannot be loopback")
    canonical_host = _canonical_host(host)
    default_port = (scheme == "http" and port == 80) or (scheme == "https" and port == 443)
    authority = canonical_host if port is None or default_port else f"{canonical_host}:{port}"
    path = parsed.path or ""
    try:
        path.encode("ascii")
    except UnicodeEncodeError as error:
        raise NetworkConfigError("endpoint path must be ASCII") from error
    if "\\" in path or "//" in path or any(ch.isspace() for ch in path):
        raise NetworkConfigError("endpoint path is not canonical")
    if path and not path.startswith("/"):
        raise NetworkConfigError("endpoint path must be absolute")
    normalized_path = path.rstrip("/")
    base = f"{scheme}://{authority}{normalized_path}"
    return EndpointInfo(
        network=network,
        environment="local" if network == "devnet" else "public-testnet",
        rest_network="testnet",
        network_id=1,
        base_url=base,
        endpoint_sha256=_sha256_bytes(base.encode("ascii")),
        suggested_profile_id=(
            "aleo-devnet-local-engineering-v1"
            if network == "devnet"
            else "aleo-testnet-public-engineering-v1"
        ),
    )


def _reject_symlink_path_components(path: Path) -> None:
    if not path.is_absolute():
        raise NetworkConfigError("private-key file path must be absolute")
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current = current / component
        try:
            mode = current.lstat().st_mode
        except OSError as error:
            raise NetworkConfigError(f"cannot stat private-key file path component: {error}") from error
        if stat.S_ISLNK(mode):
            raise NetworkConfigError("private-key file path cannot contain symbolic links")


def _file_identity(info: os.stat_result) -> FileIdentity:
    return FileIdentity(
        device=info.st_dev,
        inode=info.st_ino,
        owner=info.st_uid,
        mode=info.st_mode,
        links=info.st_nlink,
        size=info.st_size,
        modified_ns=info.st_mtime_ns,
        changed_ns=info.st_ctime_ns,
    )


def validate_signer(
    network: str,
    *,
    private_key_file: Path | None,
    dev_key: int | None,
) -> SignerInfo:
    """Validate signer selection without reading private-key contents."""
    if network == "devnet":
        if private_key_file is not None:
            raise NetworkConfigError("devnet must use --dev-key; private-key files are reserved for public testnet")
        if dev_key is None:
            raise NetworkConfigError("devnet requires --dev-key <0..3>")
        if dev_key < 0 or dev_key > 3:
            raise NetworkConfigError("devnet --dev-key must be in 0..3")
        return SignerInfo(
            tool_args=("--dev-key", str(dev_key)),
            receipt_kind="dev-key",
            public_receipt={"kind": "dev-key", "index": dev_key, "secretRecorded": False},
        )
    if network != "testnet":
        raise NetworkConfigError("signer validation supports only devnet or testnet")
    if dev_key is not None:
        raise NetworkConfigError("public testnet cannot use a local --dev-key")
    if private_key_file is None:
        raise NetworkConfigError("public testnet requires --private-key-file <absolute-path>")
    path = private_key_file
    _reject_symlink_path_components(path)
    try:
        info = path.lstat()
    except OSError as error:
        raise NetworkConfigError(f"cannot stat private-key file: {error}") from error
    if not stat.S_ISREG(info.st_mode):
        raise NetworkConfigError("private-key file must be a regular file")
    if info.st_nlink != 1:
        raise NetworkConfigError("private-key file must have exactly one hard link")
    if hasattr(os, "getuid") and info.st_uid != os.getuid():
        raise NetworkConfigError("private-key file must be owned by the current user")
    mode = stat.S_IMODE(info.st_mode)
    if mode & 0o077:
        raise NetworkConfigError("private-key file must not grant group/other permissions (use mode 0600 or 0400)")
    if info.st_size <= 0 or info.st_size > 4096:
        raise NetworkConfigError("private-key file size must be in 1..4096 bytes")
    identity = _file_identity(info)
    absolute = path.resolve(strict=True)
    try:
        resolved_info = absolute.lstat()
    except OSError as error:
        raise NetworkConfigError(f"cannot restat private-key file: {error}") from error
    if _file_identity(resolved_info) != identity:
        raise NetworkConfigError("private-key file changed during validation")
    return SignerInfo(
        tool_args=(),
        receipt_kind="private-key-file-via-inherited-fd",
        public_receipt={
            "kind": "inherited-fd-from-private-key-file",
            "pathRecorded": False,
            "descriptorRecorded": False,
            "secretRecorded": False,
        },
        redactions=(str(path), str(absolute)),
        private_key_path=absolute,
        private_key_identity=identity,
    )


def _fd_reference_path(fd: int) -> str:
    root = "/proc/self/fd" if Path("/proc/self/fd").is_dir() else "/dev/fd"
    return f"{root}/{fd}"


def open_signer_for_children(signer: SignerInfo) -> tuple[int | None, tuple[str, ...]]:
    """Open the validated key without reading it and expose only an inherited FD.

    The real filesystem path never enters snarkOS argv. Linux uses
    `/proc/self/fd/<n>` and Darwin uses `/dev/fd/<n>`; `pass_fds` keeps the
    descriptor open across exec.
    """
    if signer.private_key_path is None:
        return None, signer.tool_args
    if signer.private_key_identity is None:
        raise NetworkConfigError("private-key identity is missing")
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(signer.private_key_path, flags)
    except OSError as error:
        raise NetworkConfigError(f"cannot open private-key file safely: {error}") from error
    try:
        opened = os.fstat(fd)
        current = signer.private_key_path.lstat()
        if (
            _file_identity(opened) != signer.private_key_identity
            or _file_identity(current) != signer.private_key_identity
            or not stat.S_ISREG(opened.st_mode)
            or opened.st_nlink != 1
            or opened.st_size <= 0
            or opened.st_size > 4096
            or opened.st_mode & 0o077
            or (hasattr(os, "getuid") and opened.st_uid != os.getuid())
        ):
            raise NetworkConfigError("private-key file changed after validation")
        return fd, ("--private-key-file", _fd_reference_path(fd))
    except Exception:
        os.close(fd)
        raise


def _safe_relative_artifact_path(raw: Any) -> str:
    if not isinstance(raw, str) or not raw or "\\" in raw or "\x00" in raw:
        raise OutputInputError("artifact path must be a nonempty portable relative path")
    path = PurePosixPath(raw)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise OutputInputError(f"unsafe artifact path '{raw}'")
    return raw


def _read_regular_single_link(path: Path, *, max_bytes: int, label: str) -> bytes:
    try:
        before = path.lstat()
    except OSError as error:
        raise OutputInputError(f"cannot stat {label}: {error}") from error
    if not stat.S_ISREG(before.st_mode):
        raise OutputInputError(f"{label} must be a regular file")
    if before.st_nlink != 1:
        raise OutputInputError(f"{label} must have exactly one hard link")
    if before.st_size < 0 or before.st_size > max_bytes:
        raise OutputInputError(f"{label} exceeds the {max_bytes}-byte read limit")
    try:
        data = path.read_bytes()
        after = path.lstat()
    except OSError as error:
        raise OutputInputError(f"cannot read {label}: {error}") from error
    if (
        before.st_dev != after.st_dev
        or before.st_ino != after.st_ino
        or before.st_size != after.st_size
        or before.st_mtime_ns != after.st_mtime_ns
        or len(data) != before.st_size
    ):
        raise OutputInputError(f"{label} changed during stable read")
    return data


def _manifest_descriptor_map(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw_files = manifest.get("files")
    if not isinstance(raw_files, list) or not raw_files:
        raise OutputInputError("manifest files must be a nonempty array")
    out: dict[str, dict[str, Any]] = {}
    for item in raw_files:
        if not isinstance(item, dict) or set(item) != {"role", "path", "size", "contentSha256"}:
            raise OutputInputError("manifest file descriptor has an invalid field set")
        path = _safe_relative_artifact_path(item["path"])
        if path in out:
            raise OutputInputError(f"manifest contains duplicate artifact path '{path}'")
        if item["role"] not in {"materialized-base", "finalized-extra"}:
            raise OutputInputError(f"manifest artifact '{path}' has an unsupported role")
        if not isinstance(item["size"], int) or isinstance(item["size"], bool) or item["size"] < 0:
            raise OutputInputError(f"manifest artifact '{path}' has an invalid size")
        _require_hex64(item["contentSha256"], f"artifact {path} contentSha256")
        out[path] = item
    return out


def _read_descriptor(output_dir: Path, descriptors: dict[str, dict[str, Any]], path: str) -> bytes:
    descriptor = descriptors[path]
    data = _read_regular_single_link(
        output_dir / Path(*PurePosixPath(path).parts),
        max_bytes=MAX_ARTIFACT_BYTES,
        label=f"artifact {path}",
    )
    if len(data) != descriptor["size"]:
        raise OutputInputError(f"artifact {path} size diverges from manifest")
    if _sha256_bytes(data) != descriptor["contentSha256"]:
        raise OutputInputError(f"artifact {path} digest diverges from manifest")
    return data


def load_deployment_input(output_dir: Path) -> DeploymentInput:
    """Load exact Aleo deploy inputs from an already-inspected OutputSet snapshot."""
    canonical_dir = _canonical_path_no_symlink_existing(output_dir, label="output directory")
    try:
        info = canonical_dir.stat()
    except OSError as error:
        raise OutputInputError(f"cannot stat output directory: {error}") from error
    if not stat.S_ISDIR(info.st_mode):
        raise OutputInputError("output path must be a directory")
    manifest_bytes = _read_regular_single_link(
        canonical_dir / "manifest.json",
        max_bytes=MAX_MANIFEST_BYTES,
        label="manifest.json",
    )
    try:
        manifest = json.loads(manifest_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise OutputInputError(f"manifest.json is not valid UTF-8 JSON: {error}") from error
    if not isinstance(manifest, dict):
        raise OutputInputError("manifest root must be an object")
    if manifest.get("schemaVersion") != OUTPUT_SCHEMA:
        raise OutputInputError(f"manifest schemaVersion must be {OUTPUT_SCHEMA}")
    if manifest.get("target") != "aleo":
        raise OutputInputError("deployment input must target aleo")
    if manifest.get("codegenProfile") != ALEO_COMPILE_PROFILE:
        raise OutputInputError(
            f"deployment input must use compile profile {ALEO_COMPILE_PROFILE}"
        )
    if not isinstance(manifest.get("deployable"), bool):
        raise OutputInputError("manifest deployable must be a JSON boolean")
    artifact_program_name = manifest.get("artifactProgramName")
    if not isinstance(artifact_program_name, str) or not artifact_program_name:
        raise OutputInputError("manifest artifactProgramName must be nonempty")
    descriptors = _manifest_descriptor_map(manifest)
    primary = [
        path
        for path, item in descriptors.items()
        if item["role"] == "materialized-base"
        and path.endswith(".aleo")
        and not path.endswith(".compiled.aleo")
    ]
    compiled = [
        path
        for path, item in descriptors.items()
        if item["role"] == "finalized-extra" and path.endswith(".compiled.aleo")
    ]
    program_meta = [
        path
        for path, item in descriptors.items()
        if item["role"] == "finalized-extra" and path.endswith(".leo-program.json")
    ]
    if len(primary) != 1 or len(compiled) != 1 or len(program_meta) != 1:
        raise OutputInputError(
            "Aleo deployment input requires exactly one base .aleo, one finalized .compiled.aleo, and one .leo-program.json"
        )
    primary_bytes = _read_descriptor(canonical_dir, descriptors, primary[0])
    compiled_bytes = _read_descriptor(canonical_dir, descriptors, compiled[0])
    if primary_bytes != compiled_bytes:
        raise OutputInputError("locked Leo compiled Instructions diverge from the materialized Aleo Instructions")
    program_json_bytes = _read_descriptor(canonical_dir, descriptors, program_meta[0])
    try:
        program_json = json.loads(program_json_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise OutputInputError(f"leo-program metadata is not valid UTF-8 JSON: {error}") from error
    if not isinstance(program_json, dict):
        raise OutputInputError("leo-program metadata root must be an object")
    program_id = program_json.get("program")
    if not isinstance(program_id, str) or PROGRAM_ID_RE.fullmatch(program_id) is None:
        raise OutputInputError("leo-program metadata has an invalid Aleo program id")
    if program_json.get("leo") != "4.0.2":
        raise OutputInputError("leo-program metadata must bind Leo 4.0.2")
    try:
        instructions_text = compiled_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise OutputInputError("compiled Aleo Instructions must be UTF-8") from error
    declaration = PROGRAM_DECL_RE.match(instructions_text)
    if declaration is None or declaration.group(1) != program_id:
        raise OutputInputError("compiled Aleo program declaration diverges from leo-program metadata")
    expected_stem = program_id.removesuffix(".aleo")
    if PurePosixPath(primary[0]).name != f"{expected_stem}.aleo":
        raise OutputInputError("base Aleo artifact filename diverges from embedded program id")
    return DeploymentInput(
        output_dir=canonical_dir,
        program_id=program_id,
        artifact_program_name=artifact_program_name,
        codegen_profile=manifest["codegenProfile"],
        build_deployable=manifest["deployable"],
        source_hash=_require_hex64(manifest.get("sourceHash"), "sourceHash"),
        semantic_hash=_require_hex64(manifest.get("semanticHash"), "semanticHash"),
        build_identity_digest=_require_hex64(
            manifest.get("buildIdentityDigest"), "buildIdentityDigest"
        ),
        plan_digest=_require_hex64(manifest.get("planDigest"), "planDigest"),
        support_claim_digest=_require_hex64(
            manifest.get("supportClaimDigest"), "supportClaimDigest"
        ),
        registry_root_digest=_require_hex64(
            manifest.get("engineeringRegistryRootDigest"),
            "engineeringRegistryRootDigest",
        ),
        output_set_digest=_require_hex64(
            manifest.get("outputSetDigest"), "outputSetDigest"
        ),
        evidence_sha256=_require_hex64(
            manifest.get("evidenceSha256"), "evidenceSha256"
        ),
        instructions_bytes=compiled_bytes,
        program_json_bytes=program_json_bytes,
        instructions_sha256=_sha256_bytes(compiled_bytes),
        program_json_sha256=_sha256_bytes(program_json_bytes),
    )


def snapshot_output_tree(source_dir: Path, destination: Path) -> Path:
    """Copy an OutputSet into a private no-symlink stable-read snapshot."""
    source = _canonical_path_no_symlink_existing(source_dir, label="output directory")
    if destination.exists() or destination.is_symlink():
        raise OutputInputError("output snapshot destination already exists")
    destination.mkdir(mode=0o700, parents=False)
    entry_count = 0
    total_bytes = 0
    for dirpath, dirnames, filenames in os.walk(source, topdown=True, followlinks=False):
        dirpath_p = Path(dirpath)
        rel_dir = dirpath_p.relative_to(source)
        for dirname in list(dirnames):
            src_child = dirpath_p / dirname
            mode = src_child.lstat().st_mode
            if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
                raise OutputInputError("output tree must not contain symlinks or special directories")
            if dirname in {"", ".", ".."} or "\x00" in dirname:
                raise OutputInputError("output tree contains an unsafe directory name")
            (destination / rel_dir / dirname).mkdir(mode=0o700, exist_ok=False)
            entry_count += 1
            if entry_count > MAX_OUTPUT_TREE_ENTRIES:
                raise OutputInputError("output tree exceeds entry count limit")
        for filename in filenames:
            if filename in {"", ".", ".."} or "\x00" in filename:
                raise OutputInputError("output tree contains an unsafe file name")
            src_file = dirpath_p / filename
            data = _read_regular_single_link(src_file, max_bytes=MAX_ARTIFACT_BYTES, label=f"output artifact {rel_dir / filename}")
            total_bytes += len(data)
            entry_count += 1
            if entry_count > MAX_OUTPUT_TREE_ENTRIES:
                raise OutputInputError("output tree exceeds entry count limit")
            if total_bytes > MAX_OUTPUT_TREE_BYTES:
                raise OutputInputError("output tree exceeds total byte limit")
            dst_file = destination / rel_dir / filename
            _write_exclusive(dst_file, data, 0o600)
    return destination


def _write_exclusive(path: Path, data: bytes, mode: int) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(fd, "wb", closefd=False) as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        os.close(fd)


def stage_snarkos_package(deployment_input: DeploymentInput, destination: Path) -> None:
    if destination.exists() or destination.is_symlink():
        raise OutputInputError(f"package staging destination already exists: {destination}")
    destination.mkdir(mode=0o700, parents=False)
    _write_exclusive(destination / "main.aleo", deployment_input.instructions_bytes, 0o600)
    _write_exclusive(destination / "program.json", deployment_input.program_json_bytes, 0o600)


def extract_transaction_id(text: str) -> str | None:
    matches = TX_ID_RE.findall(text.lower())
    if not matches:
        return None
    unique: list[str] = []
    for value in matches:
        if value not in unique:
            unique.append(value)
    return unique[-1]


def _log_evidence(text: str) -> dict[str, Any]:
    encoded = text.encode("utf-8", errors="replace")
    return {
        "bytes": len(encoded),
        "sha256": _sha256_bytes(encoded),
        "transactionId": extract_transaction_id(text),
    }


def build_receipt_payload(
    *,
    deployment_input: DeploymentInput,
    endpoint: EndpointInfo,
    signer_public: dict[str, Any],
    priority_fee_microcredits: int,
    snarkos_version_line: str,
    snarkos_content_sha256: str,
    deploy_log: str,
    deploy_tool_exit_code: int | None,
    execution_logs: Sequence[ExecutionLog],
    observations: Sequence[dict[str, Any]],
    deployment_status: str = "confirmed",
    program_visible: bool = True,
    failure: str | None = None,
) -> dict[str, Any]:
    deploy_evidence = _log_evidence(deploy_log)
    executions = []
    for execution in execution_logs:
        evidence = _log_evidence(execution.output)
        executions.append(
            {
                "function": execution.function,
                "inputs": list(execution.inputs),
                "status": execution.status,
                "transactionId": evidence["transactionId"],
                "toolExitCode": execution.tool_exit_code,
                "toolOutputBytes": evidence["bytes"],
                "toolOutputSha256": evidence["sha256"],
            }
        )
    return {
        "schema": RECEIPT_SCHEMA,
        "schemaVersion": RECEIPT_SCHEMA_VERSION,
        "maturity": "engineering-network-observation-not-formal-hermetic-or-release",
        "networkProfile": {
            "registrationStatus": "unregistered-engineering",
            "suggestedId": endpoint.suggested_profile_id,
            "formalIdentityDigest": None,
        },
        "network": {
            "environment": endpoint.environment,
            "aleoNetwork": endpoint.rest_network,
            "snarkosNetworkId": endpoint.network_id,
            "endpointBase": endpoint.base_url,
            "endpointSha256": endpoint.endpoint_sha256,
        },
        "build": {
            "target": "aleo",
            "codegenProfile": deployment_input.codegen_profile,
            "artifactProgramName": deployment_input.artifact_program_name,
            "programId": deployment_input.program_id,
            "buildDeployableClaim": deployment_input.build_deployable,
            "sourceHash": deployment_input.source_hash,
            "semanticHash": deployment_input.semantic_hash,
            "buildIdentityDigest": deployment_input.build_identity_digest,
            "planDigest": deployment_input.plan_digest,
            "supportClaimDigest": deployment_input.support_claim_digest,
            "engineeringRegistryRootDigest": deployment_input.registry_root_digest,
            "outputSetDigest": deployment_input.output_set_digest,
            "evidenceSha256": deployment_input.evidence_sha256,
            "instructionsSha256": deployment_input.instructions_sha256,
            "programMetadataSha256": deployment_input.program_json_sha256,
        },
        "signer": signer_public,
        "fee": {
            "policy": "snarkos-metered",
            "priorityFeeMicrocredits": priority_fee_microcredits,
            "actualFeeObserved": None,
        },
        "tool": {
            "name": "snarkos",
            "versionLine": snarkos_version_line,
            "contentSha256": _require_hex64(snarkos_content_sha256, "snarkos contentSha256"),
            "lockStatus": "outside-tool-lock",
        },
        "deployment": {
            "status": deployment_status,
            "transactionId": deploy_evidence["transactionId"],
            "programVisible": program_visible,
            "confirmationRule": "snarkos-wait-plus-rest-program-visibility",
            "toolExitCode": deploy_tool_exit_code,
            "toolOutputBytes": deploy_evidence["bytes"],
            "toolOutputSha256": deploy_evidence["sha256"],
        },
        "executions": executions,
        "observations": list(observations),
        "failure": failure,
        "security": {
            "privateKeyRecorded": False,
            "privateKeyPathRecorded": False,
            "rawToolOutputRecorded": False,
        },
    }


def _canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def _validate_safe_directory_fd(fd: int, label: str) -> os.stat_result:
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode):
        raise ReceiptError(f"{label} must be a directory")
    if hasattr(os, "getuid") and info.st_uid != os.getuid():
        raise ReceiptError(f"{label} must be owned by the current user")
    if info.st_mode & 0o022:
        raise ReceiptError(f"{label} must not be writable by group/other")
    return info


def _open_directory_fd(path: Path, label: str) -> int:
    flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_DIRECTORY", 0)
    )
    try:
        fd = os.open(path, flags)
    except OSError as error:
        raise ReceiptError(f"cannot open {label} safely: {error}") from error
    try:
        _validate_safe_directory_fd(fd, label)
    except BaseException:
        os.close(fd)
        raise
    return fd


def _same_identity(left: os.stat_result, right: os.stat_result) -> bool:
    return left.st_dev == right.st_dev and left.st_ino == right.st_ino


def _close_fd(fd: int) -> None:
    try:
        os.close(fd)
    except OSError:
        pass


def _write_exclusive_at(directory_fd: int, name: str, data: bytes, mode: int) -> None:
    fd = os.open(
        name,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0),
        mode,
        dir_fd=directory_fd,
    )
    try:
        with os.fdopen(fd, "wb", closefd=False) as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        os.close(fd)


def _rename_directory_noreplace(parent_fd: int, source: str, destination: str) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    source_bytes = os.fsencode(source)
    destination_bytes = os.fsencode(destination)
    if sys.platform.startswith("linux"):
        rename = getattr(libc, "renameat2", None)
        flags = 1  # RENAME_NOREPLACE
    elif sys.platform == "darwin":
        rename = getattr(libc, "renameatx_np", None)
        flags = 0x00000004  # RENAME_EXCL
    else:
        rename = None
        flags = 0
    if rename is None:
        raise ReceiptError("atomic no-replace receipt rename is unsupported on this host")
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(parent_fd, source_bytes, parent_fd, destination_bytes, flags) != 0:
        error_number = ctypes.get_errno()
        if error_number in {errno.EEXIST, errno.ENOTEMPTY}:
            raise ReceiptError(f"receipt destination appeared during deployment: {destination}")
        raise ReceiptError(
            f"atomic no-replace receipt rename failed: {os.strerror(error_number)}"
        )


def _reservation_entry_matches(
    reservation: ReceiptReservation,
    entry_name: str,
) -> bool:
    try:
        listed = os.stat(
            entry_name,
            dir_fd=reservation.parent_fd,
            follow_symlinks=False,
        )
        return _same_identity(os.fstat(reservation.staging_fd), listed)
    except OSError:
        return False


def receipt_reservation_is_committed(reservation: ReceiptReservation) -> bool:
    return _reservation_entry_matches(reservation, reservation.destination.name)


def close_receipt_reservation(reservation: ReceiptReservation) -> None:
    _close_fd(reservation.staging_fd)
    _close_fd(reservation.parent_fd)


def reserve_receipt_destination(receipt_dir: Path) -> ReceiptReservation:
    destination = _canonical_receipt_destination(receipt_dir)
    parent = destination.parent
    parent_fd = _open_directory_fd(parent, "receipt parent")
    staging_fd = -1
    staging: Path | None = None
    try:
        if not _same_identity(os.fstat(parent_fd), parent.lstat()):
            raise ReceiptError("receipt parent changed during reservation")
        try:
            os.stat(destination.name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise ReceiptError(f"receipt destination already exists: {destination}")
        staging = Path(tempfile.mkdtemp(prefix=f".{destination.name}.staging-", dir=parent))
        staging.chmod(0o700)
        staging_fd = _open_directory_fd(staging, "receipt staging directory")
        opened = os.fstat(staging_fd)
        listed = os.stat(staging.name, dir_fd=parent_fd, follow_symlinks=False)
        if not _same_identity(opened, listed):
            raise ReceiptError("receipt staging directory is not bound to the retained parent")
        return ReceiptReservation(
            destination=destination,
            staging=staging,
            parent_fd=parent_fd,
            staging_fd=staging_fd,
        )
    except BaseException:
        if staging_fd >= 0:
            _close_fd(staging_fd)
        if staging is not None:
            shutil.rmtree(staging, ignore_errors=True)
        _close_fd(parent_fd)
        raise


def publish_reserved_receipt(reservation: ReceiptReservation, payload: dict[str, Any]) -> Path:
    parent_info = _validate_safe_directory_fd(reservation.parent_fd, "receipt parent")
    parent_now = reservation.destination.parent.lstat()
    if not _same_identity(parent_info, parent_now):
        raise ReceiptError("receipt parent changed before publication")
    staging_info = _validate_safe_directory_fd(
        reservation.staging_fd, "receipt staging directory"
    )
    if not _reservation_entry_matches(reservation, reservation.staging.name):
        raise ReceiptError("receipt staging directory changed before publication")
    if "receiptSha256" in payload:
        raise ReceiptError("receipt payload must not predeclare receiptSha256")
    digest = _sha256_bytes(RECEIPT_DOMAIN + _canonical_json_bytes(payload))
    completed = dict(payload)
    completed["receiptSha256"] = digest
    rendered = (json.dumps(completed, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    _write_exclusive_at(reservation.staging_fd, "receipt.json", rendered, 0o644)
    try:
        os.fsync(reservation.staging_fd)
    except OSError:
        pass
    if not _same_identity(staging_info, _validate_safe_directory_fd(
        reservation.staging_fd, "receipt staging directory"
    )) or not _reservation_entry_matches(reservation, reservation.staging.name):
        raise ReceiptError("receipt staging directory changed before commit")
    _validate_safe_directory_fd(reservation.parent_fd, "receipt parent")
    _rename_directory_noreplace(
        reservation.parent_fd,
        reservation.staging.name,
        reservation.destination.name,
    )
    if not receipt_reservation_is_committed(reservation):
        raise ReceiptError("published receipt directory does not match retained staging identity")
    parent_after = reservation.destination.parent.lstat()
    if not _same_identity(os.fstat(reservation.parent_fd), parent_after):
        raise ReceiptError("receipt parent changed during publication")
    try:
        os.fsync(reservation.parent_fd)
    except OSError:
        pass
    return reservation.destination / "receipt.json"


def abandon_receipt_reservation(reservation: ReceiptReservation) -> None:
    if receipt_reservation_is_committed(reservation):
        close_receipt_reservation(reservation)
        return
    try:
        os.unlink("receipt.json", dir_fd=reservation.staging_fd)
    except OSError:
        pass
    try:
        if _reservation_entry_matches(reservation, reservation.staging.name):
            _close_fd(reservation.staging_fd)
            os.rmdir(reservation.staging.name, dir_fd=reservation.parent_fd)
        else:
            _close_fd(reservation.staging_fd)
    except OSError:
        _close_fd(reservation.staging_fd)
    _close_fd(reservation.parent_fd)


def write_receipt_atomic(receipt_dir: Path, payload: dict[str, Any]) -> Path:
    reservation = reserve_receipt_destination(receipt_dir)
    try:
        path = publish_reserved_receipt(reservation, payload)
        close_receipt_reservation(reservation)
        return path
    except BaseException:
        if receipt_reservation_is_committed(reservation):
            close_receipt_reservation(reservation)
        else:
            abandon_receipt_reservation(reservation)
        raise


def _sanitize_text(text: str, redactions: Sequence[str]) -> str:
    result = text
    for value in sorted({v for v in redactions if v}, key=len, reverse=True):
        result = result.replace(value, "<redacted>")
    return result


def _tail_lines(text: str, count: int = 40) -> str:
    lines = text.splitlines()
    return "\n".join(lines[-count:])


def _process_group_exists(group_id: int) -> bool:
    try:
        os.killpg(group_id, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _terminate_and_reap_process_group(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except OSError:
        pass
    if process.poll() is None:
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
    else:
        process.wait()
    deadline = time.monotonic() + 2.0
    while _process_group_exists(process.pid) and time.monotonic() < deadline:
        time.sleep(0.05)
    if _process_group_exists(process.pid):
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except OSError:
            pass
    if process.poll() is None:
        process.wait()


def _render_process_chunks(chunks: Sequence[bytes]) -> str:
    return b"".join(chunks).decode("utf-8", errors="replace")


def run_bounded_process(
    args: Sequence[str],
    *,
    cwd: Path | None,
    env: dict[str, str],
    timeout_seconds: int,
    max_output_bytes: int = MAX_TOOL_OUTPUT_BYTES,
    pass_fds: Sequence[int] = (),
) -> ProcessResult:
    """Run without rendering argv; bound wall time and combined output."""
    process = subprocess.Popen(
        list(args),
        cwd=str(cwd) if cwd is not None else None,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        pass_fds=tuple(pass_fds),
    )
    assert process.stdout is not None
    selector: selectors.BaseSelector | None = None
    chunks: list[bytes] = []
    total = 0
    deadline = time.monotonic() + timeout_seconds
    try:
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(args[0], timeout_seconds)
            events = selector.select(timeout=min(remaining, 1.0))
            if not events:
                continue
            for key, _mask in events:
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    break
                chunks.append(chunk)
                total += len(chunk)
                if total > max_output_bytes:
                    raise DeploymentError(
                        f"snarkos output exceeded {max_output_bytes} bytes"
                    )
            if selector is not None and not selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(args[0], timeout_seconds)
                try:
                    process.wait(timeout=remaining)
                except subprocess.TimeoutExpired as error:
                    raise subprocess.TimeoutExpired(args[0], timeout_seconds) from error
                break
        return ProcessResult(
            returncode=process.wait(),
            output=_render_process_chunks(chunks),
        )
    except BaseException as error:
        _terminate_and_reap_process_group(process)
        output = _render_process_chunks(chunks)
        if isinstance(error, subprocess.TimeoutExpired):
            raise ProcessRunError(
                f"snarkos timed out after {timeout_seconds} seconds",
                output=output,
                timed_out=True,
            ) from error
        if isinstance(error, DeploymentError):
            raise ProcessRunError(str(error), output=output) from error
        if isinstance(error, KeyboardInterrupt):
            raise ProcessInterrupted(output) from error
        raise
    finally:
        if selector is not None:
            selector.close()
        process.stdout.close()


def _runtime_env(home: Path) -> dict[str, str]:
    env = {
        "HOME": str(home),
        "PATH": "/usr/bin:/bin",
        "LANG": "C",
        "LC_ALL": "C",
        "RUST_BACKTRACE": "0",
    }
    for name in (
        "SSL_CERT_FILE",
        "SSL_CERT_DIR",
    ):
        value = os.environ.get(name)
        if value:
            env[name] = value
    return env


def _snarkos_candidate(raw: str | None) -> Path:
    candidate = raw or os.environ.get("PROOF_FORGE_ALEO_SNARKOS")
    if not candidate:
        candidate = str(
            Path.home()
            / ".cache"
            / "proof-forge-v2"
            / "aleo-devnet"
            / "cargo-install"
            / "bin"
            / "snarkos"
        )
    path = Path(candidate)
    if not path.is_absolute():
        raise ToolchainError("snarkos path must be absolute; PATH and relative fallback are forbidden")
    return path


def _snapshot_opened_snarkos_source(path: Path, network: str, destination: Path) -> str:
    if destination.exists() or destination.is_symlink():
        raise ToolchainError("snarkos snapshot destination already exists")
    source_flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        source_fd = os.open(path, source_flags)
    except OSError as error:
        raise ToolchainError(f"snarkos not found or not safely openable: {error}") from error
    destination_fd = -1
    try:
        before = os.fstat(source_fd)
        current = path.lstat()
        if before.st_dev != current.st_dev or before.st_ino != current.st_ino:
            raise ToolchainError("snarkos changed during safe open")
        if stat.S_ISLNK(current.st_mode) or not stat.S_ISREG(before.st_mode):
            raise ToolchainError("snarkos must be a regular non-symlink file")
        if not (before.st_mode & 0o111):
            raise ToolchainError("snarkos must be executable")
        if network == "testnet":
            if before.st_nlink != 1:
                raise ToolchainError(
                    "public testnet snarkos must have exactly one hard link; copy it to a private pinned tool path"
                )
            if before.st_mode & 0o022:
                raise ToolchainError(
                    "public testnet snarkos must not be writable by group/other"
                )
            if hasattr(os, "getuid") and before.st_uid != os.getuid():
                raise ToolchainError("public testnet snarkos must be owned by the current user")
        if before.st_size <= 0 or before.st_size > MAX_SNARKOS_BYTES:
            raise ToolchainError("snarkos size is outside the supported snapshot limit")
        destination_fd = os.open(
            destination,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0),
            0o700,
        )
        digest = hashlib.sha256()
        remaining = before.st_size
        with os.fdopen(destination_fd, "wb", closefd=False) as snapshot:
            while remaining > 0:
                chunk = os.read(source_fd, min(1024 * 1024, remaining))
                if not chunk:
                    break
                snapshot.write(chunk)
                digest.update(chunk)
                remaining -= len(chunk)
            snapshot.flush()
            os.fsync(snapshot.fileno())
        after = os.fstat(source_fd)
        snap_info = os.fstat(destination_fd)
        if (
            after.st_dev != before.st_dev
            or after.st_ino != before.st_ino
            or after.st_size != before.st_size
            or after.st_mtime_ns != before.st_mtime_ns
            or remaining != 0
            or snap_info.st_size != before.st_size
        ):
            raise ToolchainError("snarkos changed during stable snapshot")
        return digest.hexdigest()
    except BaseException:
        try:
            destination.unlink(missing_ok=True)
        except OSError:
            pass
        raise
    finally:
        if destination_fd >= 0:
            os.close(destination_fd)
        os.close(source_fd)


def _sha256_fd(fd: int) -> str:
    digest = hashlib.sha256()
    os.lseek(fd, 0, os.SEEK_SET)
    while True:
        chunk = os.read(fd, 1024 * 1024)
        if not chunk:
            break
        digest.update(chunk)
    os.lseek(fd, 0, os.SEEK_SET)
    return digest.hexdigest()


def _verify_retained_snarkos(tool: SnarkosTool) -> None:
    opened = os.fstat(tool.fd)
    if _file_identity(opened) != tool.identity:
        raise ToolchainError("retained snarkos executable identity changed")
    if not stat.S_ISREG(opened.st_mode) or not (opened.st_mode & 0o111):
        raise ToolchainError("retained snarkos executable is no longer executable")
    if _sha256_fd(tool.fd) != tool.content_sha256:
        raise ToolchainError("retained snarkos executable digest changed")


def prepare_snarkos_snapshot(
    raw: str | None,
    network: str,
    expected_sha256: str | None,
    destination: Path,
    *,
    probe_home: Path | None = None,
) -> SnarkosTool:
    path = _snarkos_candidate(raw)
    digest = _snapshot_opened_snarkos_source(path, network, destination)
    pin = expected_sha256 or os.environ.get("PROOF_FORGE_ALEO_SNARKOS_SHA256")
    retained_fd = -1
    try:
        if pin is not None:
            if HEX64_RE.fullmatch(pin) is None:
                raise ToolchainError("--snarkos-sha256 must be 64 lowercase hexadecimal characters")
            if digest != pin:
                raise ToolchainError("snarkos content SHA-256 does not match the explicit pin")
        elif network == "testnet":
            raise ToolchainError(
                "public testnet requires --snarkos-sha256 because snarkos is outside Tool Lock"
            )
        destination.chmod(0o500)
        flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
        retained_fd = os.open(destination, flags)
        opened = os.fstat(retained_fd)
        current = destination.lstat()
        if not _same_identity(opened, current):
            raise ToolchainError("snarkos snapshot changed during retained open")
        identity = _file_identity(opened)
        tool = SnarkosTool(
            path=destination.resolve(strict=True),
            exec_path=_fd_reference_path(retained_fd),
            fd=retained_fd,
            identity=identity,
            version_line="",
            content_sha256=digest,
        )
        _verify_retained_snarkos(tool)
        home = probe_home or Path.home()
        try:
            result = run_bounded_process(
                [tool.exec_path, "--version"],
                cwd=None,
                env=_runtime_env(home),
                timeout_seconds=20,
                max_output_bytes=64 * 1024,
                pass_fds=(tool.fd,),
            )
        except DeploymentError as error:
            raise ToolchainError(f"snarkos --version probe failed: {error}") from error
        if result.returncode != 0:
            raise ToolchainError(f"snarkos --version failed with exit {result.returncode}")
        version_line = result.output.strip().splitlines()[0] if result.output.strip() else ""
        if not re.search(rf"\bsnarkos\s+{re.escape(SNARKOS_VERSION)}\b", result.output):
            raise ToolchainError(f"expected snarkos {SNARKOS_VERSION}; got '{version_line}'")
        if network == "devnet" and "test_network" not in result.output:
            raise ToolchainError("devnet snarkos must report features=[...,test_network,...]")
        completed = tool._replace(version_line=version_line)
        _verify_retained_snarkos(completed)
        return completed
    except BaseException:
        if retained_fd >= 0:
            os.close(retained_fd)
        try:
            destination.unlink(missing_ok=True)
        except OSError:
            pass
        raise


def _inspect_output(root: Path, output_dir: Path) -> None:
    cli = root / ".lake" / "build" / "bin" / "proof-forge-next"
    if not cli.is_file() or not os.access(cli, os.X_OK):
        raise OutputInputError(
            f"product CLI missing at {cli}; run 'lake build proof_forge_next' before deploy"
        )
    try:
        result = run_bounded_process(
            [str(cli), "inspect", "--output-dir", str(output_dir), "--json"],
            cwd=root,
            env=_runtime_env(Path.home()),
            timeout_seconds=120,
            max_output_bytes=1024 * 1024,
        )
    except ProcessRunError as error:
        raise OutputInputError(
            f"product output inspection failed: {_tail_lines(error.output, 12)}"
        ) from error
    if result.returncode != 0:
        raise OutputInputError(
            f"product output inspection failed (exit {result.returncode}): {_tail_lines(result.output, 12)}"
        )


def _rest_url(endpoint: EndpointInfo, suffix: str) -> str:
    return f"{endpoint.base_url}/{endpoint.rest_network}/{suffix.lstrip('/')}"


def _http_get_text(url: str, *, timeout_seconds: float = 5.0) -> str:
    request = urllib.request.Request(
        url,
        method="GET",
        headers={"User-Agent": "proof-forge-next-aleo-network-engineering-v1"},
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        data = response.read(1024 * 1024 + 1)
        if len(data) > 1024 * 1024:
            raise DeploymentError("REST response exceeded 1 MiB")
        return data.decode("utf-8", errors="strict").strip()


def _wait_until(
    description: str,
    timeout_seconds: int,
    probe,
    *,
    interval_seconds: float = 3.0,
):
    deadline = time.monotonic() + timeout_seconds
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            value = probe()
            if value is not None:
                return value
        except (OSError, urllib.error.URLError, UnicodeError, ValueError) as error:
            last_error = error
        time.sleep(interval_seconds)
    detail = f"; last error: {last_error}" if last_error is not None else ""
    raise DeploymentError(f"timed out waiting for {description}{detail}")


def _wait_devnet_consensus(endpoint: EndpointInfo, timeout_seconds: int) -> int:
    url = _rest_url(endpoint, "consensus_version")

    def probe() -> int | None:
        raw = _http_get_text(url)
        value = int(raw.strip('"'))
        return value if value >= 18 else None

    return _wait_until("DevNet consensus version >= 18", timeout_seconds, probe)


def _wait_program_visible(endpoint: EndpointInfo, program_id: str, timeout_seconds: int) -> bool:
    url = _rest_url(endpoint, f"program/{program_id}")

    def probe() -> bool | None:
        raw = _http_get_text(url)
        return True if raw else None

    return bool(_wait_until(f"program visibility for {program_id}", timeout_seconds, probe))


def _wait_mapping(
    endpoint: EndpointInfo,
    program_id: str,
    mapping: str,
    key: str,
    expected_wire: str,
    timeout_seconds: int,
) -> dict[str, Any]:
    path = f"program/{program_id}/mapping/{mapping}/{key}"
    url = _rest_url(endpoint, path)

    def probe() -> str | None:
        raw = _http_get_text(url)
        return raw if raw == json.dumps(expected_wire) else None

    observed = _wait_until(
        f"mapping {mapping}[{key}] == {expected_wire}",
        timeout_seconds,
        probe,
    )
    return {
        "kind": "mapping",
        "path": f"{mapping}/{key}",
        "value": json.loads(observed),
    }


def _deploy_command(
    snarkos_exec: str,
    deployment_input: DeploymentInput,
    package: Path,
    endpoint: EndpointInfo,
    signer_args: Sequence[str],
    priority_fee: int,
    wait_timeout: int,
) -> list[str]:
    return [
        snarkos_exec,
        "developer",
        "deploy",
        deployment_input.program_id,
        "--path",
        str(package),
        *signer_args,
        "--endpoint",
        endpoint.base_url,
        "--network",
        str(endpoint.network_id),
        "--broadcast",
        "--wait",
        "--timeout",
        str(wait_timeout),
        "--priority-fee",
        str(priority_fee),
        "--noupdater",
        "--verbosity",
        "1",
    ]


def _execute_command(
    snarkos_exec: str,
    deployment_input: DeploymentInput,
    endpoint: EndpointInfo,
    signer_args: Sequence[str],
    priority_fee: int,
    wait_timeout: int,
    function: str,
    inputs: Sequence[str],
) -> list[str]:
    return [
        snarkos_exec,
        "developer",
        "execute",
        deployment_input.program_id,
        function,
        *inputs,
        *signer_args,
        "--endpoint",
        endpoint.base_url,
        "--network",
        str(endpoint.network_id),
        "--broadcast",
        "--wait",
        "--timeout",
        str(wait_timeout),
        "--priority-fee",
        str(priority_fee),
        "--noupdater",
        "--verbosity",
        "1",
    ]


def _print_safe_action_tail(
    label: str,
    output: str,
    redactions: Sequence[str],
    *,
    render_raw_tail: bool = True,
) -> None:
    if not render_raw_tail:
        evidence = _log_evidence(output)
        transaction_id = evidence["transactionId"] or "none"
        print(
            f"aleo-network: {label} output captured "
            f"bytes={evidence['bytes']} sha256={evidence['sha256']} "
            f"transactionId={transaction_id}; raw tail suppressed"
        )
        return
    safe_tail = _sanitize_text(_tail_lines(output), redactions)
    if safe_tail:
        print(f"aleo-network: {label} output tail:\n{safe_tail}")


def _run_snarkos_action(
    label: str,
    command: Sequence[str],
    *,
    cwd: Path,
    env: dict[str, str],
    process_timeout: int,
    redactions: Sequence[str],
    pass_fds: Sequence[int] = (),
    render_raw_tail: bool = True,
) -> str:
    try:
        result = run_bounded_process(
            command,
            cwd=cwd,
            env=env,
            timeout_seconds=process_timeout,
            pass_fds=pass_fds,
        )
    except ProcessRunError as error:
        _print_safe_action_tail(
            label,
            error.output,
            redactions,
            render_raw_tail=render_raw_tail,
        )
        raise SnarkosActionError(
            label,
            output=error.output,
            returncode=error.returncode,
            timed_out=error.timed_out,
        ) from error
    except ProcessInterrupted as error:
        _print_safe_action_tail(
            label,
            error.output,
            redactions,
            render_raw_tail=render_raw_tail,
        )
        raise SnarkosActionInterrupted(label, error.output) from error
    _print_safe_action_tail(
        label,
        result.output,
        redactions,
        render_raw_tail=render_raw_tail,
    )
    if result.returncode != 0:
        raise SnarkosActionError(
            label,
            output=result.output,
            returncode=result.returncode,
            timed_out=False,
        )
    return result.output


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    for token in argv:
        if token == "--private-key" or token.startswith("--private-key="):
            raise NetworkConfigError("raw --private-key is forbidden; use --private-key-file")
    parser = argparse.ArgumentParser(
        description="Deploy an existing Aleo compile-profile OutputSet to DevNet or public Testnet",
        allow_abbrev=False,
    )
    parser.add_argument("--output-dir")
    parser.add_argument("--receipt-dir")
    parser.add_argument("--network", choices=("devnet", "testnet", "mainnet", "canary"))
    parser.add_argument("--endpoint")
    parser.add_argument("--broadcast", action="store_true")
    parser.add_argument("--private-key-file")
    parser.add_argument("--dev-key", type=int)
    parser.add_argument("--snarkos")
    parser.add_argument("--snarkos-sha256")
    parser.add_argument("--priority-fee", type=int, default=0)
    parser.add_argument("--wait-timeout-seconds", type=int, default=600)
    parser.add_argument("--visibility-timeout-seconds", type=int, default=600)
    parser.add_argument("--execute-counter", "--execute", dest="execute_counter", action="store_true")
    parser.add_argument("--keep-workdir", action="store_true")
    args, unknown = parser.parse_known_args(argv)
    if unknown:
        raise NetworkConfigError("unknown argument(s) supplied")
    if not args.broadcast:
        raise NetworkConfigError("explicit --broadcast is required")
    if not args.output_dir:
        raise NetworkConfigError("--output-dir is required and must name an existing build OutputSet")
    if not args.receipt_dir:
        raise NetworkConfigError("--receipt-dir is required for the separate deployment receipt")
    if not args.network:
        raise NetworkConfigError("--network is required and must be devnet or testnet")
    if args.priority_fee < 0:
        raise NetworkConfigError("--priority-fee must be a nonnegative integer")
    if args.wait_timeout_seconds < 1 or args.wait_timeout_seconds > 3600:
        raise NetworkConfigError("--wait-timeout-seconds must be in 1..3600")
    if args.visibility_timeout_seconds < 1 or args.visibility_timeout_seconds > 3600:
        raise NetworkConfigError("--visibility-timeout-seconds must be in 1..3600")
    return args


def run(argv: Sequence[str]) -> Path:
    args = _parse_args(argv)
    if args.network in {"mainnet", "canary"}:
        raise NetworkConfigError(f"{args.network} deployment is disabled by product policy; use devnet or testnet")
    root = Path(__file__).resolve().parent.parent
    endpoint_raw = args.endpoint or (
        DEFAULT_PUBLIC_ENDPOINT if args.network == "testnet" else None
    )
    if endpoint_raw is None:
        raise NetworkConfigError("devnet requires an explicit loopback --endpoint")
    endpoint = normalize_endpoint(args.network, endpoint_raw)
    private_key_path = Path(args.private_key_file) if args.private_key_file else None
    signer = validate_signer(
        args.network,
        private_key_file=private_key_path,
        dev_key=args.dev_key,
    )
    output_dir = _canonical_path_no_symlink_existing(Path(args.output_dir), label="output directory")
    receipt_dir = _canonical_receipt_destination(Path(args.receipt_dir))
    _reject_output_receipt_overlap(output_dir, receipt_dir)
    receipt_reservation = reserve_receipt_destination(receipt_dir)
    workdir : Path | None = None
    snarkos_tool : SnarkosTool | None = None
    try:
        workdir = Path(tempfile.mkdtemp(prefix="proof-forge-aleo-network."))
        workdir.chmod(0o700)
        output_snapshot = snapshot_output_tree(output_dir, workdir / "output-snapshot")
        _inspect_output(root, output_snapshot)
        deployment_input = load_deployment_input(output_snapshot)
        package = workdir / "package"
        isolated_home = workdir / "home"
        isolated_home.mkdir(mode=0o700)
        runtime_env = _runtime_env(isolated_home)
        snarkos_tool = prepare_snarkos_snapshot(
            args.snarkos,
            args.network,
            args.snarkos_sha256,
            workdir / "snarkos",
            probe_home=isolated_home,
        )
        version_line = snarkos_tool.version_line
        snarkos_digest = snarkos_tool.content_sha256
    except BaseException:
        if snarkos_tool is not None:
            os.close(snarkos_tool.fd)
        abandon_receipt_reservation(receipt_reservation)
        if workdir is not None:
            shutil.rmtree(workdir, ignore_errors=True)
        raise
    assert snarkos_tool is not None
    if endpoint.network == "devnet":
        # The client and validators must use the same accelerated consensus
        # schedule. Otherwise the client can compute a pre-V18 base fee that
        # the V18 node rejects as insufficient even with a priority fee.
        runtime_env["CONSENSUS_VERSION_HEIGHTS"] = os.environ.get(
            "PROOF_FORGE_ALEO_CONSENSUS_HEIGHTS",
            DEFAULT_DEVNET_CONSENSUS_HEIGHTS,
        )
    deploy_log = ""
    deploy_tool_exit_code: int | None = None
    execution_logs: list[ExecutionLog] = []
    observations: list[dict[str, Any]] = []
    deploy_attempted = False
    deployed = False
    program_visible = False
    receipt_published = False
    signer_fd : int | None = None
    signer_args : tuple[str, ...] = signer.tool_args
    try:
        stage_snarkos_package(deployment_input, package)
        signer_fd, signer_args = open_signer_for_children(signer)
        action_redactions = signer.redactions + (
            () if signer_fd is None else (_fd_reference_path(signer_fd),)
        )
        print(f"aleo-network: network={endpoint.network} endpoint={endpoint.base_url}")
        print(f"aleo-network: program={deployment_input.program_id} outputSetDigest={deployment_input.output_set_digest}")
        print(f"aleo-network: snarkos=4.9.0 sha256={snarkos_digest} lockStatus=outside-tool-lock")
        print(f"aleo-network: signer={signer.receipt_kind} secret/path/descriptor not recorded")
        print("aleo-network: build Finalize remains network-free; receipt publishes separately")
        if endpoint.network == "devnet":
            version = _wait_devnet_consensus(endpoint, args.visibility_timeout_seconds)
            print(f"aleo-network: devnet consensus_version={version}")
        deploy_attempted = True
        _verify_retained_snarkos(snarkos_tool)
        action_fds = (snarkos_tool.fd,) + (() if signer_fd is None else (signer_fd,))
        try:
            deploy_log = _run_snarkos_action(
                "NETWORK-DEPLOY",
                _deploy_command(
                    snarkos_tool.exec_path,
                    deployment_input,
                    package,
                    endpoint,
                    signer_args,
                    args.priority_fee,
                    args.wait_timeout_seconds,
                ),
                cwd=package,
                env=runtime_env,
                process_timeout=args.wait_timeout_seconds + 120,
                redactions=action_redactions,
                pass_fds=action_fds,
                render_raw_tail=signer_fd is None,
            )
            deploy_tool_exit_code = 0
        except SnarkosActionError as action_error:
            deploy_log = action_error.output
            deploy_tool_exit_code = action_error.returncode
            raise
        except SnarkosActionInterrupted as action_error:
            deploy_log = action_error.output
            deploy_tool_exit_code = None
            raise
        deployed = True
        program_visible = _wait_program_visible(
            endpoint,
            deployment_input.program_id,
            args.visibility_timeout_seconds,
        )
        print("aleo-network: program visible through REST")
        if args.execute_counter:
            for function, inputs in (("initialize", ("1u64",)), ("increment", ("2u64",))):
                _verify_retained_snarkos(snarkos_tool)
                try:
                    log = _run_snarkos_action(
                        f"NETWORK-EXECUTE {function}",
                        _execute_command(
                            snarkos_tool.exec_path,
                            deployment_input,
                            endpoint,
                            signer_args,
                            args.priority_fee,
                            args.wait_timeout_seconds,
                            function,
                            inputs,
                        ),
                        cwd=package,
                        env=runtime_env,
                        process_timeout=args.wait_timeout_seconds + 120,
                        redactions=action_redactions,
                        pass_fds=action_fds,
                render_raw_tail=signer_fd is None,
                    )
                    execution_logs.append(
                        ExecutionLog(function, inputs, "confirmed", log, 0)
                    )
                except SnarkosActionError as action_error:
                    execution_logs.append(
                        ExecutionLog(
                            function,
                            inputs,
                            "timed-out" if action_error.timed_out else "failed",
                            action_error.output,
                            action_error.returncode,
                        )
                    )
                    raise
                except SnarkosActionInterrupted as action_error:
                    execution_logs.append(
                        ExecutionLog(function, inputs, "interrupted", action_error.output, None)
                    )
                    raise
            observations.append(
                _wait_mapping(
                    endpoint,
                    deployment_input.program_id,
                    "pf_state_0",
                    "0u8",
                    "3u64",
                    args.visibility_timeout_seconds,
                )
            )
            observations.append(
                _wait_mapping(
                    endpoint,
                    deployment_input.program_id,
                    "initialized",
                    "0u8",
                    "true",
                    args.visibility_timeout_seconds,
                )
            )
        payload = build_receipt_payload(
            deployment_input=deployment_input,
            endpoint=endpoint,
            signer_public=signer.public_receipt,
            priority_fee_microcredits=args.priority_fee,
            snarkos_version_line=version_line,
            snarkos_content_sha256=snarkos_digest,
            deploy_log=deploy_log,
            deploy_tool_exit_code=deploy_tool_exit_code,
            execution_logs=execution_logs,
            observations=observations,
            deployment_status="confirmed",
            program_visible=program_visible,
        )
        receipt_path = publish_reserved_receipt(receipt_reservation, payload)
        receipt_published = True
        print(f"aleo-network: receipt={receipt_path}")
        print("aleo-network: NETWORK-OK")
        return receipt_path
    except BaseException as error:
        if deploy_attempted:
            try:
                if isinstance(error, AleoNetworkError):
                    failure = error.render()
                elif isinstance(error, KeyboardInterrupt):
                    failure = "PF-NETWORK-DEPLOY: interrupted after deployment attempt"
                else:
                    failure = "PF-INTERNAL: unexpected failure after deployment attempt"
                payload = build_receipt_payload(
                    deployment_input=deployment_input,
                    endpoint=endpoint,
                    signer_public=signer.public_receipt,
                    priority_fee_microcredits=args.priority_fee,
                    snarkos_version_line=version_line,
                    snarkos_content_sha256=snarkos_digest,
                    deploy_log=deploy_log,
                    deploy_tool_exit_code=deploy_tool_exit_code,
                    execution_logs=execution_logs,
                    observations=observations,
                    deployment_status=(
                        "confirmed-partial" if deployed or program_visible else "attempted-unobserved"
                    ),
                    program_visible=program_visible,
                    failure=failure,
                )
                receipt_path = publish_reserved_receipt(receipt_reservation, payload)
                receipt_published = True
                print(f"aleo-network: partial receipt={receipt_path}", file=sys.stderr)
            except Exception as receipt_error:
                print(
                    f"PF-NETWORK-RECEIPT: failed to publish partial receipt: {receipt_error}",
                    file=sys.stderr,
                )
        raise
    finally:
        if signer_fd is not None:
            os.close(signer_fd)
        os.close(snarkos_tool.fd)
        if receipt_published or receipt_reservation_is_committed(receipt_reservation):
            close_receipt_reservation(receipt_reservation)
        else:
            abandon_receipt_reservation(receipt_reservation)
        if args.keep_workdir:
            print(f"aleo-network: retained workdir={workdir}")
        else:
            shutil.rmtree(workdir, ignore_errors=True)


def main(argv: Sequence[str] | None = None) -> int:
    try:
        run(sys.argv[1:] if argv is None else argv)
        return 0
    except AleoNetworkError as error:
        print(error.render(), file=sys.stderr)
        return error.exit_code
    except KeyboardInterrupt:
        print("PF-NETWORK-DEPLOY: interrupted", file=sys.stderr)
        return 130
    except Exception as error:
        print(f"PF-INTERNAL: Aleo network engine failed: {error}", file=sys.stderr)
        return 70


if __name__ == "__main__":
    raise SystemExit(main())

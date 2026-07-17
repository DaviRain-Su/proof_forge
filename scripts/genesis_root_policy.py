#!/usr/bin/env python3
"""Generate and validate the pre-cutover GenesisRootPolicyV1 object.

This tool accepts public Ed25519 key material only.  Canonical PF-JCS and
prime-subgroup point validation are delegated to the exact sibling
``bootstrap_task_objects.py`` implementation so the bootstrap formats do not
acquire a second JSON or curve implementation.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import re
import secrets
import stat
import sys
from pathlib import Path
from types import ModuleType
from typing import Any, Dict, NoReturn, Optional, Sequence, Tuple


SCHEMA = "proof-forge.genesis-root-policy.v1"
POLICY_ID = "proof-forge-genesis-root"
POLICY_VERSION = "1.0.0"
AUTHORITY_DOCUMENT = "GOV-GENESIS-001"
MAINTAINERS_DOCUMENT = "GOV-MAINTAINERS-001"
PRINCIPAL_ID = "davirain"
ALGORITHM = "ed25519"
ALLOWED_SCHEMAS = ("proof-forge.bootstrap-authority-policy.v1",)
CUTOVER_TASK = "TASK-D0-04"
POST_CUTOVER_DISPOSITION = "revoke-and-historical-only"
POLICY_DIGEST_DOMAIN = b"pf.genesis-root-policy.v1\x00"
MAX_POLICY_BYTES = 4 * 1024 * 1024

_POLICY_FIELDS = frozenset(
    {
        "algorithm",
        "allowedSchemas",
        "authorityDocument",
        "cutoverTask",
        "id",
        "keyId",
        "maintainersDocument",
        "postCutoverDisposition",
        "principalId",
        "publicKey",
        "schema",
        "version",
    }
)
_SAFE_ID_RE = re.compile(
    r"[A-Za-z0-9](?:[A-Za-z0-9._:+-]{0,254}[A-Za-z0-9])?"
)
_CORE_MODULE_NAME = "proof_forge_bootstrap_task_objects_for_genesis_root"
_CORE_REQUIRED_CALLABLES = (
    "canonical_pf_jcs",
    "decode_canonical_pf_jcs",
    "_decode_ed25519_public_key",
    "_require_prime_subgroup_public_key",
)
_CORE: Optional[ModuleType] = None


class GenesisRootPolicyError(Exception):
    """Stable fail-closed error exposed by the library and CLI."""


def _fail(message: str) -> NoReturn:
    raise GenesisRootPolicyError(message)


def _load_exact_bootstrap_core() -> ModuleType:
    global _CORE
    if _CORE is not None:
        return _CORE

    try:
        consumer = Path(__file__)
        if consumer.is_symlink():
            _fail("the genesis policy tool must not be a symlink")
        consumer = consumer.resolve(strict=True)
        candidate = consumer.with_name("bootstrap_task_objects.py")
        if candidate.is_symlink():
            _fail("bootstrap task object core must not be a symlink")
        core_path = candidate.resolve(strict=True)
        if core_path != candidate:
            _fail("bootstrap task object core changed exact path")

        spec = importlib.util.spec_from_file_location(_CORE_MODULE_NAME, core_path)
        if spec is None or spec.loader is None or spec.origin is None:
            _fail("bootstrap task object core loader is unavailable")
        if Path(spec.origin).resolve(strict=True) != core_path:
            _fail("bootstrap task object core origin changed")

        module = importlib.util.module_from_spec(spec)
        previous = sys.modules.get(_CORE_MODULE_NAME)
        sys.modules[_CORE_MODULE_NAME] = module
        try:
            spec.loader.exec_module(module)
        except Exception:
            if previous is None:
                sys.modules.pop(_CORE_MODULE_NAME, None)
            else:
                sys.modules[_CORE_MODULE_NAME] = previous
            raise
        for name in _CORE_REQUIRED_CALLABLES:
            if not callable(module.__dict__.get(name)):
                _fail(f"bootstrap task object core is missing {name}")
        if not isinstance(module.__dict__.get("Rejected"), type):
            _fail("bootstrap task object core rejection type is unavailable")
    except GenesisRootPolicyError:
        raise
    except Exception:
        _fail("cannot load the exact bootstrap task object core")

    _CORE = module
    return module


def _call_core(name: str, *args: object) -> object:
    core = _load_exact_bootstrap_core()
    rejected = core.__dict__["Rejected"]
    operation = core.__dict__[name]
    try:
        return operation(*args)
    except rejected as error:
        detail = getattr(error, "detail", "")
        _fail(str(detail) if detail else "bootstrap primitive rejected input")
    except GenesisRootPolicyError:
        raise
    except Exception:
        _fail("bootstrap primitive failed closed")


def canonical_policy_bytes(value: object) -> bytes:
    encoded = _call_core("canonical_pf_jcs", value)
    if type(encoded) is not bytes:
        _fail("canonical PF-JCS encoder returned an invalid result")
    assert isinstance(encoded, bytes)
    return encoded


def _require_public_key(value: object) -> str:
    encoded = _call_core(
        "_decode_ed25519_public_key",
        value,
        "GenesisRootPolicyV1.publicKey",
    )
    if type(encoded) is not bytes:
        _fail("Ed25519 public-key decoder returned an invalid result")
    assert isinstance(encoded, bytes)
    checked = _call_core(
        "_require_prime_subgroup_public_key",
        encoded,
        "GenesisRootPolicyV1.publicKey",
    )
    if checked != encoded:
        _fail("Ed25519 public-key validator returned an invalid result")
    assert isinstance(value, str)
    return value


def _require_safe_key_id(value: object) -> str:
    if (
        type(value) is not str
        or not value.isascii()
        or _SAFE_ID_RE.fullmatch(value) is None
    ):
        _fail("GenesisRootPolicyV1.keyId must be a safe-id")
    assert isinstance(value, str)
    return value


def validate_genesis_root_policy_bytes(data: bytes) -> Dict[str, Any]:
    """Validate exact canonical GenesisRootPolicyV1 bytes."""

    if type(data) is not bytes or len(data) > MAX_POLICY_BYTES:
        _fail("GenesisRootPolicyV1 input must be bounded bytes")
    decoded = _call_core("decode_canonical_pf_jcs", data)
    if type(decoded) is not dict:
        _fail("GenesisRootPolicyV1 must be an object")
    assert isinstance(decoded, dict)
    if len(decoded) != len(_POLICY_FIELDS) or set(decoded) != _POLICY_FIELDS:
        _fail("GenesisRootPolicyV1 has missing or unknown fields")

    exact_values = (
        ("schema", SCHEMA),
        ("id", POLICY_ID),
        ("version", POLICY_VERSION),
        ("authorityDocument", AUTHORITY_DOCUMENT),
        ("maintainersDocument", MAINTAINERS_DOCUMENT),
        ("principalId", PRINCIPAL_ID),
        ("algorithm", ALGORITHM),
        ("cutoverTask", CUTOVER_TASK),
        ("postCutoverDisposition", POST_CUTOVER_DISPOSITION),
    )
    for field, expected in exact_values:
        if type(decoded[field]) is not str or decoded[field] != expected:
            _fail(f"GenesisRootPolicyV1.{field} has the wrong exact value")

    allowed = decoded["allowedSchemas"]
    if (
        type(allowed) is not list
        or len(allowed) != 1
        or type(allowed[0]) is not str
        or tuple(allowed) != ALLOWED_SCHEMAS
    ):
        _fail("GenesisRootPolicyV1.allowedSchemas has the wrong exact value")
    _require_safe_key_id(decoded["keyId"])
    _require_public_key(decoded["publicKey"])

    # Keep this check explicit even though the decoder already enforces it.
    if canonical_policy_bytes(decoded) != data:
        _fail("GenesisRootPolicyV1 bytes are not canonical PF-JCS")
    return dict(decoded)


def build_genesis_root_policy(key_id: str, public_key: str) -> bytes:
    """Build canonical policy bytes from explicit public information."""

    checked_key_id = _require_safe_key_id(key_id)
    checked_public_key = _require_public_key(public_key)
    policy: Dict[str, object] = {
        "algorithm": ALGORITHM,
        "allowedSchemas": list(ALLOWED_SCHEMAS),
        "authorityDocument": AUTHORITY_DOCUMENT,
        "cutoverTask": CUTOVER_TASK,
        "id": POLICY_ID,
        "keyId": checked_key_id,
        "maintainersDocument": MAINTAINERS_DOCUMENT,
        "postCutoverDisposition": POST_CUTOVER_DISPOSITION,
        "principalId": PRINCIPAL_ID,
        "publicKey": checked_public_key,
        "schema": SCHEMA,
        "version": POLICY_VERSION,
    }
    encoded = canonical_policy_bytes(policy)
    validate_genesis_root_policy_bytes(encoded)
    return encoded


def genesis_root_policy_digest(data: bytes) -> str:
    """Return the domain-separated SHA-256 ContentRef digest."""

    validate_genesis_root_policy_bytes(data)
    return "sha256:" + hashlib.sha256(POLICY_DIGEST_DOMAIN + data).hexdigest()


def _same_inode(left: os.stat_result, right: os.stat_result) -> bool:
    return left.st_dev == right.st_dev and left.st_ino == right.st_ino


def _directory_flags() -> int:
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        _fail("this host lacks no-follow directory opens")
    return (
        os.O_RDONLY
        | os.O_DIRECTORY
        | getattr(os, "O_CLOEXEC", 0)
        | os.O_NOFOLLOW
    )


def _requested_components(path: Path) -> Tuple[bool, Tuple[str, ...]]:
    raw = os.fspath(path)
    if not raw or "\x00" in raw:
        _fail("policy path is empty or contains NUL")
    candidate = Path(raw)
    absolute = candidate.is_absolute()
    if absolute and candidate.anchor != "/":
        _fail("policy path has an unsupported anchor")
    parts = candidate.parts[1:] if absolute else candidate.parts
    if not parts or parts[-1] in ("", ".", ".."):
        _fail("policy path must name a file")
    if any(part in ("", ".", "..") for part in parts):
        _fail("policy path traversal is forbidden")
    return absolute, tuple(parts)


def _cwd_prefix_length(parts: Tuple[str, ...]) -> Optional[int]:
    """Find an absolute lexical prefix that identifies the open cwd.

    macOS commonly spells its temporary directory through the system ``/var``
    symlink.  Treating the already-open cwd as the authority anchor permits
    that inherited prefix while every component below cwd remains no-follow.
    """

    cwd_fd = os.open(".", _directory_flags())
    try:
        cwd_stat = os.fstat(cwd_fd)
    finally:
        os.close(cwd_fd)
    prefix = Path("/")
    for index, part in enumerate(parts[:-1], start=1):
        prefix = prefix / part
        try:
            prefix_stat = os.stat(prefix)
        except OSError:
            break
        if _same_inode(prefix_stat, cwd_stat):
            return index
    return None


def _open_parent_no_symlinks(path: Path) -> Tuple[int, str]:
    absolute, all_parts = _requested_components(path)
    if absolute:
        cwd_prefix = _cwd_prefix_length(all_parts)
    else:
        cwd_prefix = 0

    if cwd_prefix is not None:
        descriptor = os.open(".", _directory_flags())
        parts = all_parts[cwd_prefix:]
    else:
        descriptor = os.open("/", _directory_flags())
        parts = all_parts

    try:
        if not parts:
            _fail("policy path must name a file below its authority anchor")
        for component in parts[:-1]:
            next_descriptor: Optional[int] = None
            try:
                next_descriptor = os.open(
                    component,
                    _directory_flags(),
                    dir_fd=descriptor,
                )
                opened = os.fstat(next_descriptor)
                named = os.stat(
                    component,
                    dir_fd=descriptor,
                    follow_symlinks=False,
                )
            except OSError:
                if next_descriptor is not None:
                    os.close(next_descriptor)
                _fail("policy path contains an unavailable or linked directory")
            assert next_descriptor is not None
            if not stat.S_ISDIR(opened.st_mode) or not _same_inode(opened, named):
                os.close(next_descriptor)
                _fail("policy path directory changed during traversal")
            os.close(descriptor)
            descriptor = next_descriptor
        return descriptor, parts[-1]
    except Exception:
        os.close(descriptor)
        raise


def _read_open_file(descriptor: int, maximum: int) -> bytes:
    chunks = []
    remaining = maximum + 1
    while remaining:
        chunk = os.read(descriptor, min(remaining, 128 * 1024))
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    data = b"".join(chunks)
    if len(data) > maximum:
        _fail("GenesisRootPolicyV1 input exceeds the size limit")
    return data


def read_genesis_root_policy(path: Path) -> bytes:
    """Read a stable regular file without following path symlinks."""

    parent_fd, name = _open_parent_no_symlinks(path)
    descriptor: Optional[int] = None
    try:
        flags = (
            os.O_RDONLY
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NONBLOCK", 0)
            | os.O_NOFOLLOW
        )
        try:
            descriptor = os.open(name, flags, dir_fd=parent_fd)
            before = os.fstat(descriptor)
            named_before = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        except OSError:
            _fail("cannot open GenesisRootPolicyV1 input without following links")
        if (
            not stat.S_ISREG(before.st_mode)
            or not _same_inode(before, named_before)
            or before.st_nlink != 1
            or before.st_size > MAX_POLICY_BYTES
        ):
            _fail("GenesisRootPolicyV1 input must be one bounded regular file")
        data = _read_open_file(descriptor, MAX_POLICY_BYTES)
        after = os.fstat(descriptor)
        try:
            named_after = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        except OSError:
            _fail("GenesisRootPolicyV1 input changed during validation")
        stable_fields = (
            "st_dev",
            "st_ino",
            "st_mode",
            "st_nlink",
            "st_size",
            "st_mtime_ns",
            "st_ctime_ns",
        )
        if (
            len(data) != before.st_size
            or any(getattr(before, field) != getattr(after, field) for field in stable_fields)
            or not _same_inode(after, named_after)
        ):
            _fail("GenesisRootPolicyV1 input changed during validation")
        validate_genesis_root_policy_bytes(data)
        return data
    finally:
        if descriptor is not None:
            os.close(descriptor)
        os.close(parent_fd)


def _cleanup_name(directory_fd: int, name: str) -> None:
    try:
        os.unlink(name, dir_fd=directory_fd)
    except FileNotFoundError:
        return
    except OSError:
        return


def atomic_publish_no_clobber(output: Path, data: bytes) -> None:
    """Publish canonical bytes atomically without replacing any pathname."""

    validate_genesis_root_policy_bytes(data)
    parent_fd, final_name = _open_parent_no_symlinks(output)
    staging_name = (
        f".genesis-root-policy-{os.getpid()}-{secrets.token_hex(16)}.tmp"
    )
    staging_fd: Optional[int] = None
    staging_present = False
    final_linked = False
    published = False
    staged_stat: Optional[os.stat_result] = None
    try:
        try:
            os.stat(final_name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        except OSError:
            _fail("cannot inspect GenesisRootPolicyV1 output")
        else:
            _fail("GenesisRootPolicyV1 output already exists")

        flags = (
            os.O_WRONLY
            | os.O_CREAT
            | os.O_EXCL
            | getattr(os, "O_CLOEXEC", 0)
            | os.O_NOFOLLOW
        )
        try:
            staging_fd = os.open(
                staging_name,
                flags,
                0o600,
                dir_fd=parent_fd,
            )
            staging_present = True
            offset = 0
            while offset < len(data):
                written = os.write(staging_fd, data[offset:])
                if written <= 0:
                    _fail("short write while staging GenesisRootPolicyV1")
                offset += written
            os.fsync(staging_fd)
            os.fchmod(staging_fd, 0o400)
            os.fsync(staging_fd)
            staged_stat = os.fstat(staging_fd)
            if (
                not stat.S_ISREG(staged_stat.st_mode)
                or staged_stat.st_nlink != 1
                or staged_stat.st_size != len(data)
                or stat.S_IMODE(staged_stat.st_mode) != 0o400
            ):
                _fail("GenesisRootPolicyV1 staging inode failed validation")

            os.link(
                staging_name,
                final_name,
                src_dir_fd=parent_fd,
                dst_dir_fd=parent_fd,
                follow_symlinks=False,
            )
            final_linked = True
            final_stat = os.stat(
                final_name,
                dir_fd=parent_fd,
                follow_symlinks=False,
            )
            if (
                not _same_inode(staged_stat, final_stat)
                or final_stat.st_nlink != 2
                or final_stat.st_size != len(data)
            ):
                _fail("GenesisRootPolicyV1 output changed during publication")
            os.fsync(parent_fd)
            os.unlink(staging_name, dir_fd=parent_fd)
            staging_present = False
            os.fsync(parent_fd)
            final_stat = os.stat(
                final_name,
                dir_fd=parent_fd,
                follow_symlinks=False,
            )
            if (
                not _same_inode(staged_stat, final_stat)
                or final_stat.st_nlink != 1
                or stat.S_IMODE(final_stat.st_mode) != 0o400
            ):
                _fail("GenesisRootPolicyV1 output failed final validation")
            published = True
        except FileExistsError:
            _fail("GenesisRootPolicyV1 output already exists")
        except GenesisRootPolicyError:
            raise
        except OSError:
            _fail("atomic GenesisRootPolicyV1 publication failed")
    finally:
        if not published and final_linked and staged_stat is not None:
            try:
                named = os.stat(
                    final_name,
                    dir_fd=parent_fd,
                    follow_symlinks=False,
                )
                if _same_inode(staged_stat, named):
                    _cleanup_name(parent_fd, final_name)
            except OSError:
                pass
        if staging_fd is not None:
            os.close(staging_fd)
        if staging_present:
            _cleanup_name(parent_fd, staging_name)
        os.close(parent_fd)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="genesis_root_policy.py",
        description="Generate or validate a public-key-only GenesisRootPolicyV1",
        allow_abbrev=False,
    )
    commands = parser.add_subparsers(dest="command", required=True)

    generate = commands.add_parser(
        "generate",
        help="generate canonical policy bytes from an explicit public key",
        allow_abbrev=False,
    )
    generate.add_argument("--key-id", required=True)
    generate.add_argument("--public-key", required=True)
    generate.add_argument("--output", required=True)

    validate = commands.add_parser(
        "validate",
        help="validate an existing canonical policy",
        allow_abbrev=False,
    )
    validate.add_argument("--input", required=True)
    return parser


def _run(args: argparse.Namespace) -> int:
    if args.command == "generate":
        policy = build_genesis_root_policy(args.key_id, args.public_key)
        atomic_publish_no_clobber(Path(args.output), policy)
        print(
            "genesis-root-policy: generated "
            f"digest={genesis_root_policy_digest(policy)} output={args.output}"
        )
        return 0
    if args.command == "validate":
        policy = read_genesis_root_policy(Path(args.input))
        print(
            "genesis-root-policy: valid "
            f"digest={genesis_root_policy_digest(policy)} input={args.input}"
        )
        return 0
    _fail("unknown GenesisRootPolicyV1 command")


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        return _run(args)
    except GenesisRootPolicyError as error:
        print(f"genesis-root-policy: rejected: {error}", file=sys.stderr)
        return 1
    except Exception:
        print("genesis-root-policy: rejected: internal failure", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""TASK-D0-08 candidate-bound supply-chain closure and release binding.

Computes the resolved seven-kind logical component closure of every committed
per-platform Tool Lock file, renders the three-file sidecar set
(`supply-chain-closure.v1.json`, `bom.cdx.json`, `sbom-release-binding.v1.json`)
with atomic no-clobber 0444 writes, and independently recomputes the full set
for `--verify-existing`.  Development-level candidate binding only: no formal
evidence publication, freshness, revocation, or release signature.

Run with: /usr/bin/python3 -I -S scripts/sbom_closure.py --root . generate \
    --candidate candidate.json --output-dir build/sbom-closure
"""

from __future__ import annotations

import argparse
import errno
import fcntl
import hashlib
import importlib.util
import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

CLOSURE_SCHEMA = "proof-forge.supply-chain-closure.v1"
BINDING_SCHEMA = "proof-forge.sbom-release-binding.v1"
RUNTIME_MANIFEST_SCHEMA = "proof-forge.compiler-runtime-manifest.v1"
STANDARDS_MANIFEST_SCHEMA = "proof-forge.sbom-standards-manifest.v1"
PACKAGE_TREE_DOMAIN = "proof-forge.package-tree.v1"
GENERATOR_ID = "proof-forge-sbom-closure"
GENERATOR_VERSION = "1.0.0"

LOCK_FILES = ("toolchains.lock.json", "toolchains-linux-x86_64.lock.json")
LOCK_DIGEST_DOMAINS = {
    "proof-forge.toolchains.v2": "proof-forge.toolchains.v2",
    "proof-forge.toolchains.v3": "proof-forge.toolchains.v3",
}
LEGACY_LOCK_DOMAIN = "proof-forge.toolchain-lock.v1"
STANDARDS_MANIFEST_PATH = "supply-chain/standards-manifest.v1.json"
RUNTIME_MANIFESTS = {
    "darwin-arm64": "supply-chain/compiler-runtime-darwin-arm64.v1.json",
    "linux-x86_64": "supply-chain/compiler-runtime-linux-x86_64.v1.json",
}
LICENSE_INVENTORY_PATH = "docs/supply-chain/license-inventory.v1.json"
LICENSE_INVENTORY_SCHEMA = "proof-forge.license-inventory.v1"
LICENSE_POLICY_PATH = "docs/supply-chain/license-policy.v1.json"
LICENSE_POLICY_SCHEMA = "proof-forge.license-policy.v1"
SPDX_LICENSE_LIST_PATH = "supply-chain/standards/spdx-license-list-v3.27.0.json"
SPDX_EXCEPTIONS_PATH = "supply-chain/standards/spdx-exceptions-v3.27.0.json"
PACKAGE_FILES_MANIFEST_PATH = "supply-chain/lean-package-files.v1.json"
PACKAGE_FILES_SCHEMA = "proof-forge.lean-package-files.v1"
LEGACY_DIGEST_MAP_KEYS = {"bomSha256", "inventorySha256", "policySha256"}
SIDECAR_NAMES = (
    "supply-chain-closure.v1.json",
    "bom.cdx.json",
    "sbom-release-binding.v1.json",
)
MAX_INPUT_BYTES = 64 * 1024 * 1024
MAX_COMPONENTS = 4096
MAX_RELATIONSHIPS = 16384
MAX_FILE_SET = 4096
MAX_SIDECAR_BYTES = 64 * 1024 * 1024


class SbomClosureError(Exception):
    """Fail-closed supply-chain error; `code` is the stable PF-* diagnostic."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


def fail(code: str, detail: str) -> None:
    raise SbomClosureError(code, detail)


def _load_core():
    spec = importlib.util.spec_from_file_location(
        "proof_forge_supply_chain_core", REPO_ROOT / "scripts" / "supply_chain_core.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


CORE = _load_core()


def _wrap_core(operation, detail: str):
    """Run a supply_chain_core call, re-raising failures as SbomClosureError."""

    try:
        return operation()
    except CORE.SupplyChainError as error:
        fail(getattr(error, "code", "PF-SBOM-CLOSURE"), f"{detail}: {error}")


def read_regular_bytes(
    root: Path,
    relative: str,
    *,
    code: str = "PF-SBOM-IO",
    require_single_link: bool = False,
) -> bytes:
    """Read an input file without following symlinks; reject non-regular files."""

    if "\x00" in relative:
        fail(code, "input path contains an embedded NUL")
    parts = Path(relative).parts
    if not parts or Path(relative).is_absolute() or ".." in parts:
        fail(code, f"input path must be root-relative: {relative!r}")
    dir_fd = -1
    file_fd = -1
    try:
        dir_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW)
        for part in parts[:-1]:
            next_fd = os.open(
                part, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
                dir_fd=dir_fd,
            )
            os.close(dir_fd)
            dir_fd = next_fd
        file_fd = os.open(
            parts[-1],
            os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=dir_fd,
        )
        metadata = os.fstat(file_fd)
        if not stat.S_ISREG(metadata.st_mode):
            fail(code, f"input is not a regular file: {relative}")
        if require_single_link and metadata.st_nlink != 1:
            fail("PF-SBOM-IO", f"input must be a single-link file: {relative}")
        if metadata.st_size > MAX_INPUT_BYTES:
            fail("PF-SBOM-LIMIT", f"input exceeds byte budget: {relative}")
        chunks = []
        remaining = metadata.st_size
        with os.fdopen(file_fd, "rb", closefd=True) as handle:
            file_fd = -1
            while remaining > 0:
                chunk = handle.read(min(1 << 20, remaining))
                if not chunk:
                    fail(code, f"input truncated while reading: {relative}")
                chunks.append(chunk)
                remaining -= len(chunk)
        return b"".join(chunks)
    except SbomClosureError:
        raise
    except OSError as error:
        fail(code, f"cannot read {relative}: {error.strerror or error}")
    finally:
        if file_fd >= 0:
            os.close(file_fd)
        if dir_fd >= 0:
            os.close(dir_fd)
    return b""


def decode_json(raw: bytes, where: str) -> object:
    return _wrap_core(lambda: CORE.decode_json_document(raw), where)


def sha256_prefixed(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


# --- Candidate -----------------------------------------------------------------


def parse_candidate(candidate: object) -> dict[str, object]:
    if type(candidate) is not dict:
        fail("PF-SBOM-SCHEMA", "candidate must be an object")
    expected = {"archivePath", "commit", "treeObjectId", "archiveDigest", "archiveSize", "digest"}
    keys = set(candidate)
    if keys != expected:
        fail("PF-SBOM-SCHEMA", f"candidate fields must be exactly {sorted(expected)}")
    for field in ("commit", "treeObjectId", "digest"):
        value = candidate[field]
        if type(value) is not str or not __import__("re").fullmatch(r"[0-9a-f]{40}", value):
            fail("PF-SBOM-SCHEMA", f"candidate.{field} must be 40 lowercase hex")
    archive_digest = candidate["archiveDigest"]
    if type(archive_digest) is not str or not __import__("re").fullmatch(r"[0-9a-f]{64}", archive_digest):
        fail("PF-SBOM-SCHEMA", "candidate.archiveDigest must be 64 lowercase hex")
    size = candidate["archiveSize"]
    if type(size) is not int or size < 0:
        fail("PF-SBOM-SCHEMA", "candidate.archiveSize must be a non-negative integer")
    archive_path = candidate["archivePath"]
    if type(archive_path) is not str or not archive_path:
        fail("PF-SBOM-SCHEMA", "candidate.archivePath must be a non-empty string")
    return candidate


def bind_candidate_archive(candidate: dict[str, object]) -> None:
    """Bind the tuple to the real archive bytes before any inventory parsing."""

    archive = Path(candidate["archivePath"])
    try:
        fd = os.open(archive, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        fail("PF-SBOM-BIND", f"candidate archive unreadable: {error.strerror or error}")
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            fail("PF-SBOM-BIND", "candidate archive is not a regular file")
        if metadata.st_size != candidate["archiveSize"]:
            fail("PF-SBOM-BIND", "candidate archiveSize mismatch")
        digest = hashlib.sha256()
        with os.fdopen(fd, "rb", closefd=True) as handle:
            fd = -1
            for chunk in iter(lambda: handle.read(1 << 20), b""):
                digest.update(chunk)
        if digest.hexdigest() != candidate["archiveDigest"]:
            fail("PF-SBOM-BIND", "candidate archiveDigest mismatch")
    finally:
        if fd >= 0:
            os.close(fd)


# --- Tool Locks ------------------------------------------------------------------


def load_lock(root: Path, relative: str) -> dict[str, object]:
    raw = read_regular_bytes(root, relative)
    leaves = _wrap_core(
        lambda: CORE.enumerate_tool_lock_leaves(raw), f"{relative} validation"
    )
    value = decode_json(raw, f"{relative} decode")
    if type(value) is not dict:
        fail("PF-SBOM-SCHEMA", f"{relative} root must be an object")
    schema = value.get("schema")
    domain = LOCK_DIGEST_DOMAINS.get(schema)
    if domain is None:
        fail("PF-SBOM-SCHEMA", f"{relative} has an unknown lock schema {schema!r}")
    typed = CORE.domain_digest(domain, CORE.canonical_pf_jcs(value))
    return {
        "path": relative,
        "rawBytes": raw,
        "rawSha256": sha256_prefixed(raw),
        "typedDigest": typed,
        "domain": domain,
        "platform": value["platform"],
        "value": value,
        "leaves": leaves,
    }


# --- Standards -------------------------------------------------------------------


def load_standards(root: Path) -> dict[str, object]:
    raw = read_regular_bytes(root, STANDARDS_MANIFEST_PATH)
    manifest = decode_json(raw, "standards manifest")
    if type(manifest) is not dict or manifest.get("schema") != STANDARDS_MANIFEST_SCHEMA:
        fail("PF-SBOM-SCHEMA", "standards manifest schema mismatch")
    files = manifest.get("files")
    if type(files) is not list or len(files) != 4:
        fail("PF-SBOM-SCHEMA", "standards manifest must pin exactly 4 files")
    entries = []
    for entry in files:
        if type(entry) is not dict or set(entry) != {"path", "bytes", "sha256"}:
            fail("PF-SBOM-SCHEMA", "standards manifest entry shape mismatch")
        data = read_regular_bytes(root, entry["path"], code="PF-SBOM-BIND")
        if len(data) != entry["bytes"]:
            fail("PF-SBOM-BIND", f"standards file size mismatch: {entry['path']}")
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            fail("PF-SBOM-BIND", f"standards file digest mismatch: {entry['path']}")
        entries.append({"path": entry["path"], "bytes": entry["bytes"], "sha256": entry["sha256"]})
    entries.sort(key=lambda item: item["path"])
    return {
        "path": STANDARDS_MANIFEST_PATH,
        "rawSha256": sha256_prefixed(raw),
        "files": entries,
        "validator": manifest.get("validator"),
    }


# --- Compiler runtime manifests ----------------------------------------------------


def load_runtime_manifest(root: Path, platform: str, lock: dict[str, object]) -> dict[str, object]:
    relative = RUNTIME_MANIFESTS[platform]
    raw = read_regular_bytes(root, relative)
    manifest = decode_json(raw, relative)
    if type(manifest) is not dict or manifest.get("schema") != RUNTIME_MANIFEST_SCHEMA:
        fail("PF-SBOM-SCHEMA", f"{relative} schema mismatch")
    for field in ("platform", "compilerAssetId", "systemLoadRoots", "executables", "files", "loadEdges"):
        if field not in manifest:
            fail("PF-SBOM-SCHEMA", f"{relative} missing field {field}")
    if manifest["platform"] != platform:
        fail("PF-SBOM-CLOSURE", f"{relative} platform mismatch")
    lock_value = lock["value"]
    compiler = lock_value["compilerToolchain"]
    if manifest["compilerAssetId"] != compiler["assetId"]:
        fail("PF-SBOM-CLOSURE", f"{relative} compiler asset binding mismatch")

    lock_execs = {item["path"]: item["sha256"] for item in compiler["executables"]}
    manifest_execs = manifest["executables"]
    if type(manifest_execs) is not list:
        fail("PF-SBOM-SCHEMA", f"{relative} executables must be an array")
    seen_execs = {}
    for entry in manifest_execs:
        if type(entry) is not dict or set(entry) < {"path", "sha256"}:
            fail("PF-SBOM-SCHEMA", f"{relative} executable entry shape mismatch")
        seen_execs[entry["path"]] = entry["sha256"]
    if seen_execs != lock_execs:
        fail("PF-SBOM-CLOSURE", f"{relative} executables drift from the Tool Lock")

    files = manifest["files"]
    if type(files) is not list:
        fail("PF-SBOM-SCHEMA", f"{relative} files must be an array")
    file_paths = set()
    for entry in files:
        if type(entry) is not dict or set(entry) != {"path", "size", "sha256"}:
            fail("PF-SBOM-SCHEMA", f"{relative} file entry shape mismatch")
        if entry["path"] in file_paths:
            fail("PF-SBOM-CLOSURE", f"{relative} duplicate runtime file {entry['path']}")
        file_paths.add(entry["path"])

    roots = manifest["systemLoadRoots"]
    if type(roots) is not list or not all(type(item) is str for item in roots):
        fail("PF-SBOM-SCHEMA", f"{relative} systemLoadRoots must be a string array")
    edges = manifest["loadEdges"]
    if type(edges) is not list:
        fail("PF-SBOM-SCHEMA", f"{relative} loadEdges must be an array")
    owners = file_paths | set(seen_execs)
    reachable = set()
    for edge in edges:
        if type(edge) is not dict or set(edge) != {"owner", "needed", "resolved"}:
            fail("PF-SBOM-SCHEMA", f"{relative} loadEdge shape mismatch")
        owner = edge["owner"]
        resolved = edge["resolved"]
        if owner not in owners:
            fail("PF-SBOM-CLOSURE", f"{relative} loadEdge owner {owner} is unknown")
        if any(resolved.startswith(prefix) for prefix in roots):
            continue
        if resolved not in file_paths:
            fail(
                "PF-SBOM-CLOSURE",
                f"{relative} loadEdge {owner} -> {resolved} dangles outside the manifest",
            )
        if owner in seen_execs:
            reachable.add(resolved)
    # transitive reachability from executables
    queue = list(reachable)
    while queue:
        current = queue.pop()
        for edge in edges:
            if edge["owner"] == current and not any(
                edge["resolved"].startswith(prefix) for prefix in roots
            ):
                target = edge["resolved"]
                if target not in reachable:
                    reachable.add(target)
                    queue.append(target)
    orphans = file_paths - reachable
    if orphans:
        fail(
            "PF-SBOM-CLOSURE",
            f"{relative} runtime files unreachable from executables: {sorted(orphans)}",
        )
    return {"path": relative, "rawSha256": sha256_prefixed(raw), "manifest": manifest}


# --- Inventory / licenses ------------------------------------------------------------


_SPDX_TOKEN_RE = re.compile(r"\(|\)|[^\s()]+")


def _parse_spdx_primary(tokens: list[str], pos: int, code: str):
    if pos >= len(tokens):
        fail(code, "SPDX expression is truncated")
    token = tokens[pos]
    if token == "(":
        node, pos = _parse_spdx_or(tokens, pos + 1, code)
        if pos >= len(tokens) or tokens[pos] != ")":
            fail(code, "SPDX expression has unbalanced parentheses")
        return node, pos + 1
    if token in (")", "AND", "OR", "WITH"):
        fail(code, f"SPDX expression has an unexpected token {token!r}")
    return ("id", token), pos + 1


def _parse_spdx_with(tokens: list[str], pos: int, code: str):
    node, pos = _parse_spdx_primary(tokens, pos, code)
    if pos < len(tokens) and tokens[pos] == "WITH":
        if node[0] != "id":
            fail(code, "SPDX WITH must apply to a single license id")
        if pos + 1 >= len(tokens):
            fail(code, "SPDX WITH is missing its exception id")
        exception = tokens[pos + 1]
        if exception in ("(", ")", "AND", "OR", "WITH"):
            fail(code, "SPDX WITH has an invalid exception id")
        return ("with", node, exception), pos + 2
    return node, pos


def _parse_spdx_and(tokens: list[str], pos: int, code: str):
    node, pos = _parse_spdx_with(tokens, pos, code)
    children = [node]
    while pos < len(tokens) and tokens[pos] == "AND":
        node, pos = _parse_spdx_with(tokens, pos + 1, code)
        children.append(node)
    if len(children) == 1:
        return children[0], pos
    return ("and", tuple(children)), pos


def _parse_spdx_or(tokens: list[str], pos: int, code: str):
    node, pos = _parse_spdx_and(tokens, pos, code)
    children = [node]
    while pos < len(tokens) and tokens[pos] == "OR":
        node, pos = _parse_spdx_and(tokens, pos + 1, code)
        children.append(node)
    if len(children) == 1:
        return children[0], pos
    return ("or", tuple(children)), pos


def _render_spdx(node) -> str:
    tag = node[0]
    if tag == "id":
        return node[1]
    if tag == "with":
        return f"{_render_spdx(node[1])} WITH {node[2]}"
    if tag == "and":
        parts = []
        for child in node[1]:
            text = _render_spdx(child)
            if child[0] == "or":
                text = f"({text})"
            parts.append(text)
        return " AND ".join(sorted(parts))
    if tag == "or":
        return " OR ".join(sorted(_render_spdx(child) for child in node[1]))
    fail("PF-SBOM-LICENSE", "internal SPDX node is malformed")


def _spdx_license_ids(node) -> set[str]:
    tag = node[0]
    if tag == "id":
        return {node[1]}
    if tag == "with":
        return _spdx_license_ids(node[1])
    ids: set[str] = set()
    for child in node[1]:
        ids |= _spdx_license_ids(child)
    return ids


def _spdx_exception_ids(node) -> set[str]:
    tag = node[0]
    if tag == "id":
        return set()
    if tag == "with":
        return {node[2]} | _spdx_exception_ids(node[1])
    ids: set[str] = set()
    for child in node[1]:
        ids |= _spdx_exception_ids(child)
    return ids


def parse_spdx_expression(
    expression: object,
    license_ids: set[str],
    exception_ids: set[str],
    code: str,
):
    """Parse and canonical-check one SPDX expression against the pinned lists.

    Canonical form: single ASCII spaces, exact-case ids/operators, AND/OR
    operand sets sorted ascending, OR-of-ANDs precedence with parentheses only
    where binding requires them.
    """

    if type(expression) is not str or not expression:
        fail(code, "SPDX expression must be a non-empty string")
    tokens = _SPDX_TOKEN_RE.findall(expression)
    if not tokens or _SPDX_TOKEN_RE.sub("", expression).strip():
        fail(code, f"SPDX expression is not tokenizable: {expression!r}")
    node, pos = _parse_spdx_or(tokens, 0, code)
    if pos != len(tokens):
        fail(code, f"SPDX expression has trailing tokens: {expression!r}")
    for license_id in _spdx_license_ids(node):
        if license_id not in license_ids:
            fail(code, f"unknown SPDX license id {license_id!r}")
    for exception_id in _spdx_exception_ids(node):
        if exception_id not in exception_ids:
            fail(code, f"unknown SPDX exception id {exception_id!r}")
    if _render_spdx(node) != expression:
        fail(code, f"SPDX expression is not canonical: {expression!r}")
    return node


def load_spdx_standards(root: Path) -> tuple[set[str], set[str]]:
    """Load license/exception id sets from the hash-pinned standards files."""

    raw = read_regular_bytes(root, SPDX_LICENSE_LIST_PATH, code="PF-SBOM-LICENSE")
    listing = decode_json(raw, SPDX_LICENSE_LIST_PATH)
    entries = listing.get("licenses") if type(listing) is dict else None
    if type(entries) is not list or not entries:
        fail("PF-SBOM-LICENSE", "SPDX license list shape mismatch")
    license_ids: set[str] = set()
    for entry in entries:
        if type(entry) is not dict or type(entry.get("licenseId")) is not str:
            fail("PF-SBOM-LICENSE", "SPDX license list entry shape mismatch")
        license_ids.add(entry["licenseId"])
    raw = read_regular_bytes(root, SPDX_EXCEPTIONS_PATH, code="PF-SBOM-LICENSE")
    listing = decode_json(raw, SPDX_EXCEPTIONS_PATH)
    entries = listing.get("exceptions") if type(listing) is dict else None
    if type(entries) is not list or not entries:
        fail("PF-SBOM-LICENSE", "SPDX exception list shape mismatch")
    exception_ids: set[str] = set()
    for entry in entries:
        if type(entry) is not dict or type(entry.get("licenseExceptionId")) is not str:
            fail("PF-SBOM-LICENSE", "SPDX exception list entry shape mismatch")
        exception_ids.add(entry["licenseExceptionId"])
    return license_ids, exception_ids


def load_license_policy(
    root: Path, license_ids: set[str], exception_ids: set[str]
) -> dict[str, set[str]]:
    raw = read_regular_bytes(root, LICENSE_POLICY_PATH, code="PF-SBOM-POLICY")
    policy = decode_json(raw, LICENSE_POLICY_PATH)
    if type(policy) is not dict or policy.get("schema") != LICENSE_POLICY_SCHEMA:
        fail("PF-SBOM-POLICY", "license policy schema mismatch")
    lists: dict[str, list[str]] = {}
    for key in ("allow", "review", "deny"):
        items = policy.get(key)
        if type(items) is not list or not all(type(item) is str for item in items):
            fail("PF-SBOM-POLICY", f"policy.{key} must be a string array")
        if items != sorted(items) or len(set(items)) != len(items):
            fail("PF-SBOM-POLICY", f"policy.{key} must be sorted and unique")
        lists[key] = items
    expressions = {key: set(value) for key, value in lists.items()}
    if (
        expressions["allow"] & expressions["review"]
        or expressions["allow"] & expressions["deny"]
        or expressions["review"] & expressions["deny"]
    ):
        fail("PF-SBOM-POLICY", "policy allow/review/deny lists overlap")
    id_sets: dict[str, set[str]] = {}
    for key, items in lists.items():
        ids: set[str] = set()
        for expression in items:
            node = parse_spdx_expression(expression, license_ids, exception_ids, "PF-SBOM-POLICY")
            ids |= _spdx_license_ids(node)
        id_sets[key] = ids
    external = policy.get("externalCli", {})
    if type(external) is not dict:
        fail("PF-SBOM-POLICY", "policy.externalCli must be an object")
    allowed_deny = external.get("allowedDenyLicensesWhenNotRedistributable", [])
    if type(allowed_deny) is not list or not all(type(item) is str for item in allowed_deny):
        fail("PF-SBOM-POLICY", "policy.externalCli exceptions must be a string array")
    external_ids: set[str] = set()
    for expression in allowed_deny:
        node = parse_spdx_expression(expression, license_ids, exception_ids, "PF-SBOM-POLICY")
        external_ids |= _spdx_license_ids(node)
    if not external_ids <= id_sets["deny"]:
        fail("PF-SBOM-POLICY", "externalCli exception is not a deny-list subset")
    return {
        "allow": id_sets["allow"],
        "review": id_sets["review"],
        "deny": id_sets["deny"],
        "externalOk": external_ids,
    }


def _check_dependency_graph(adjacency: dict[str, list[str]], code: str, where: str) -> None:
    """Iterative DFS cycle check over a small string-keyed graph."""

    color: dict[str, int] = {}
    for start in adjacency:
        if color.get(start, 0):
            continue
        color[start] = 1
        stack: list[tuple[str, object]] = [(start, iter(adjacency[start]))]
        while stack:
            node, pending = stack[-1]
            advanced = False
            for target in pending:
                state = color.get(target, 0)
                if state == 1:
                    fail(code, f"{where} contains a dependency cycle at {target}")
                if state == 0:
                    color[target] = 1
                    stack.append((target, iter(adjacency.get(target, ()))))
                    advanced = True
                    break
            if not advanced:
                color[node] = 2
                stack.pop()


def load_license_inventory(
    root: Path,
    license_ids: set[str],
    exception_ids: set[str],
    policy: dict[str, set[str]],
) -> list[dict[str, object]]:
    raw = read_regular_bytes(root, LICENSE_INVENTORY_PATH)
    inventory = decode_json(raw, LICENSE_INVENTORY_PATH)
    if type(inventory) is not dict or inventory.get("schema") != LICENSE_INVENTORY_SCHEMA:
        fail("PF-SBOM-INVENTORY", "license inventory schema mismatch")
    components = inventory.get("components")
    if type(components) is not list or not components:
        fail("PF-SBOM-INVENTORY", "license inventory components must be a non-empty array")
    required = {
        "id", "name", "version", "type", "supplier", "licenseSpdx",
        "licenseFile", "licenseFileSha256", "redistributable", "dependsOn",
    }
    records: list[dict[str, object]] = []
    component_ids: list[str] = []
    for component in components:
        if type(component) is not dict or not required <= set(component):
            fail("PF-SBOM-INVENTORY", "license inventory component shape mismatch")
        component_id = component["id"]
        if type(component_id) is not str or not component_id:
            fail("PF-SBOM-INVENTORY", "license inventory component id must be a string")
        expression = component["licenseSpdx"]
        node = parse_spdx_expression(expression, license_ids, exception_ids, "PF-SBOM-LICENSE")
        license_file = component["licenseFile"]
        if type(license_file) is not str or not license_file:
            fail("PF-SBOM-INVENTORY", f"{component_id}: licenseFile must be a string")
        file_sha256 = component["licenseFileSha256"]
        if type(file_sha256) is not str or re.fullmatch(r"[0-9a-f]{64}", file_sha256) is None:
            fail("PF-SBOM-INVENTORY", f"{component_id}: licenseFileSha256 is malformed")
        redistributable = component["redistributable"]
        if type(redistributable) is not bool:
            fail("PF-SBOM-INVENTORY", f"{component_id}: redistributable must be a boolean")
        depends = component["dependsOn"]
        if type(depends) is not list or not all(type(item) is str for item in depends):
            fail("PF-SBOM-INVENTORY", f"{component_id}: dependsOn must be a string array")
        if depends != sorted(depends) or len(set(depends)) != len(depends):
            fail("PF-SBOM-INVENTORY", f"{component_id}: dependsOn must be sorted and unique")
        expression_ids = _spdx_license_ids(node)
        if expression_ids <= policy["allow"]:
            pass
        elif redistributable is False and expression_ids <= policy["externalOk"]:
            pass
        else:
            fail(
                "PF-SBOM-POLICY",
                f"{component_id}: license {expression!r} is not policy-allowed",
            )
        component_ids.append(component_id)
        records.append(
            {
                "id": component_id,
                "licenseFile": license_file,
                "licenseFileSha256": file_sha256,
                "licenseIds": expression_ids,
                "dependsOn": depends,
            }
        )
    if component_ids != sorted(component_ids) or len(set(component_ids)) != len(component_ids):
        fail("PF-SBOM-INVENTORY", "license inventory component ids must be unique and sorted")
    id_set = set(component_ids)
    for record in records:
        for dependency in record["dependsOn"]:
            if dependency == record["id"]:
                fail("PF-SBOM-INVENTORY", f"{record['id']} depends on itself")
            if dependency not in id_set:
                fail(
                    "PF-SBOM-INVENTORY",
                    f"{record['id']} depends on unknown component {dependency}",
                )
    _check_dependency_graph(
        {record["id"]: record["dependsOn"] for record in records},
        "PF-SBOM-INVENTORY",
        LICENSE_INVENTORY_PATH,
    )
    return records


LICENSE_BODY_MARKERS = {
    "Apache-2.0": (b"Apache License", b"Version 2.0"),
    "GPL-3.0-only": (b"GNU GENERAL PUBLIC LICENSE",),
    "GPL-3.0-or-later": (b"GNU GENERAL PUBLIC LICENSE",),
    "MIT": (b"Permission is hereby granted",),
}


def load_license_files(
    root: Path, records: list[dict[str, object]]
) -> dict[str, bytes]:
    """Re-hash every referenced license text and reject placeholder bodies."""

    markers_by_path: dict[str, set[bytes]] = {}
    for record in records:
        markers = markers_by_path.setdefault(record["licenseFile"], set())
        for license_id in record["licenseIds"]:
            markers |= set(LICENSE_BODY_MARKERS.get(license_id, ()))
    contents: dict[str, bytes] = {}
    for path in sorted(markers_by_path):
        data = read_regular_bytes(
            root, path, code="PF-SBOM-LICENSE", require_single_link=True
        )
        actual = hashlib.sha256(data).hexdigest()
        for record in records:
            if record["licenseFile"] != path:
                continue
            if actual != record["licenseFileSha256"]:
                fail("PF-SBOM-LICENSE", f"license file hash mismatch: {path}")
        for marker in sorted(markers_by_path[path]):
            if marker not in data:
                fail(
                    "PF-SBOM-LICENSE",
                    f"license file {path} is missing its license body marker",
                )
        contents[path] = data
    return contents


def load_license_closure(root: Path) -> dict[str, object]:
    license_ids, exception_ids = load_spdx_standards(root)
    policy = load_license_policy(root, license_ids, exception_ids)
    records = load_license_inventory(root, license_ids, exception_ids, policy)
    contents = load_license_files(root, records)
    return {
        "records": records,
        "mapping": {record["id"]: record["licenseFile"] for record in records},
        "contents": contents,
    }


# --- Lean package file set --------------------------------------------------------------


def load_package_files_manifest(root: Path) -> list[dict[str, object]]:
    raw = read_regular_bytes(root, PACKAGE_FILES_MANIFEST_PATH)
    manifest = decode_json(raw, PACKAGE_FILES_MANIFEST_PATH)
    if type(manifest) is not dict or manifest.get("schema") != PACKAGE_FILES_SCHEMA:
        fail("PF-SBOM-SCHEMA", "lean package files manifest schema mismatch")
    files = manifest.get("files")
    if type(files) is not list:
        fail("PF-SBOM-SCHEMA", "lean package files manifest must carry a files array")
    if len(files) > MAX_FILE_SET:
        fail("PF-SBOM-LIMIT", "lean package file set exceeds the pinned budget")
    records: list[dict[str, object]] = []
    for entry in files:
        if type(entry) is not dict or set(entry) != {"path", "bytes", "sha256"}:
            fail("PF-SBOM-SCHEMA", "lean package files entry shape mismatch")
        path = entry["path"]
        size = entry["bytes"]
        digest = entry["sha256"]
        if type(path) is not str or not path:
            fail("PF-SBOM-SCHEMA", "lean package files path must be a string")
        if type(size) is not int or size < 0:
            fail("PF-SBOM-SCHEMA", "lean package files bytes must be a non-negative integer")
        if type(digest) is not str or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            fail("PF-SBOM-SCHEMA", "lean package files sha256 is malformed")
        records.append({"path": path, "bytes": size, "sha256": digest})
    paths = [record["path"] for record in records]
    if paths != sorted(paths) or len(set(paths)) != len(paths):
        fail("PF-SBOM-SCHEMA", "lean package files must be unique and sorted by path")
    return records


# --- Closure resolution ---------------------------------------------------------------


def _component_id(kind: str, platform: str | None, name: str) -> str:
    if platform is None:
        return f"{kind}:{name}"
    return f"{kind}:{platform}:{name}"


def _validate_relationship_graph(
    relationships: list[dict[str, str]],
    component_ids: set[str],
    content_ids: set[str],
    root_ref: str,
) -> None:
    """Structural invariants over the typed relationship set (SB2-020).

    No self edges, no dangling endpoints, no duplicate typed edges, and the
    `loads` subgraph must stay acyclic.
    """

    known_ids = component_ids | content_ids | {root_ref}
    seen: set[tuple[str, str, str]] = set()
    loads_adjacency: dict[str, list[str]] = {}
    for relationship in relationships:
        kind = relationship["kind"]
        source = relationship["from"]
        target = relationship["to"]
        if source == target:
            fail("PF-SBOM-CLOSURE", f"self relationship on {source}")
        if source not in known_ids or target not in known_ids:
            fail(
                "PF-SBOM-CLOSURE",
                f"relationship {kind} {source} -> {target} has a dangling endpoint",
            )
        key = (kind, source, target)
        if key in seen:
            fail("PF-SBOM-CLOSURE", f"duplicate relationship {kind} {source} -> {target}")
        seen.add(key)
        if kind == "loads":
            loads_adjacency.setdefault(source, []).append(target)
    _check_dependency_graph(loads_adjacency, "PF-SBOM-CLOSURE", "loads relationship graph")


def resolve_closure(root: Path, locks: list[dict[str, object]]) -> dict[str, object]:
    components: dict[str, dict[str, object]] = {}
    relationships: list[dict[str, str]] = []
    contents: dict[str, dict[str, object]] = {}

    def add_content(digest: str) -> str:
        identity = contents.get(digest)
        if identity is None:
            identity = {"id": f"content:{digest[7:]}", "sha256": digest}
            contents[digest] = identity
        return identity["id"]

    def add_relationship(kind: str, source: str, target: str) -> None:
        if len(relationships) >= MAX_RELATIONSHIPS:
            fail("PF-SBOM-LIMIT", "typed relationship count exceeds budget")
        relationships.append({"kind": kind, "from": source, "to": target})

    def add_component(component: dict[str, object], content_digest: str) -> None:
        if len(components) >= MAX_COMPONENTS:
            fail("PF-SBOM-LIMIT", "component count exceeds budget")
        cid = component["id"]
        if cid in components:
            fail("PF-SBOM-INVENTORY", f"duplicate component id {cid}")
        components[cid] = component
        content_id = add_content(content_digest)
        component["contentRef"] = content_id
        add_relationship("has-content", cid, content_id)

    license_bundle = load_license_closure(root)
    license_mapping: dict[str, str] = license_bundle["mapping"]
    license_contents: dict[str, bytes] = license_bundle["contents"]
    license_components: dict[str, str] = {}
    for license_path in sorted(set(license_mapping.values())):
        data = license_contents[license_path]
        component_id = _component_id("bundled-license-text", None, license_path)
        license_components[license_path] = component_id
        add_component(
            {
                "id": component_id,
                "kind": "bundled-license-text",
                "path": license_path,
                "size": len(data),
            },
            sha256_prefixed(data),
        )

    for lock in locks:
        platform = lock["platform"]
        leaves = lock["leaves"]
        value = lock["value"]
        asset_components: dict[str, str] = {}
        bundle_owner: dict[str, str] = {}
        tool_by_bundle: dict[str, str] = {}
        for tool in value["tools"]:
            tool_by_bundle[tool["executable"]] = tool["id"]
        bundle_leaf_by_path = {
            leaf.ref.path: leaf for leaf in leaves if leaf.ref.kind == "bundle-file"
        }

        for leaf in leaves:
            if leaf.ref.kind == "asset":
                component_id = _component_id("download-asset", platform, leaf.asset_id)
                asset_components[leaf.asset_id] = component_id
                add_component(
                    {
                        "id": component_id,
                        "kind": "download-asset",
                        "platform": platform,
                        "assetId": leaf.asset_id,
                        "size": leaf.size,
                        "toolLockRefs": ["asset"],
                    },
                    leaf.digest,
                )

        for leaf in leaves:
            if leaf.ref.kind == "compiler-executable":
                component_id = _component_id("compiler-executable", platform, leaf.ref.path)
                if leaf.asset_id not in asset_components:
                    fail("PF-SBOM-CLOSURE", f"compiler executable {leaf.ref.path} has no asset")
                add_component(
                    {
                        "id": component_id,
                        "kind": "compiler-executable",
                        "platform": platform,
                        "path": leaf.ref.path,
                        "toolLockRefs": ["compiler-executable"],
                    },
                    leaf.digest,
                )
                add_relationship("unpacks-to", asset_components[leaf.asset_id], component_id)
            elif leaf.ref.kind == "tool-executable":
                component_id = _component_id("tool-executable", platform, leaf.ref.id)
                if leaf.asset_id not in asset_components:
                    fail("PF-SBOM-CLOSURE", f"tool executable {leaf.ref.id} has no asset")
                bundle_leaf = bundle_leaf_by_path.get(leaf.ref.path)
                if (
                    bundle_leaf is None
                    or bundle_leaf.digest != leaf.digest
                    or bundle_leaf.size != leaf.size
                ):
                    fail(
                        "PF-SBOM-CLOSURE",
                        f"tool executable {leaf.ref.id} does not join its bundle-file leaf",
                    )
                add_component(
                    {
                        "id": component_id,
                        "kind": "tool-executable",
                        "platform": platform,
                        "toolId": leaf.ref.id,
                        "path": leaf.ref.path,
                        "size": leaf.size,
                        "toolLockRefs": ["tool-executable", "bundle-file"],
                    },
                    leaf.digest,
                )
                add_relationship("unpacks-to", asset_components[leaf.asset_id], component_id)

        for leaf in leaves:
            if leaf.ref.kind == "bundle-file":
                if leaf.asset_id not in asset_components:
                    fail(
                        "PF-SBOM-CLOSURE",
                        f"bundle file {leaf.ref.path} references missing asset {leaf.asset_id}",
                    )
                if leaf.ref.path in tool_by_bundle:
                    continue  # already owned by the tool-executable component
                component_id = _component_id("runtime-dylib-file", platform, leaf.ref.path)
                bundle_owner[leaf.ref.path] = component_id
                add_component(
                    {
                        "id": component_id,
                        "kind": "runtime-dylib-file",
                        "platform": platform,
                        "path": leaf.ref.path,
                        "size": leaf.size,
                        "toolLockRefs": ["bundle-file"],
                    },
                    leaf.digest,
                )
                add_relationship("unpacks-to", asset_components[leaf.asset_id], component_id)
            elif leaf.ref.kind == "tool-runtime-file":
                component_id = bundle_owner.get(leaf.ref.path)
                if component_id is None:
                    fail(
                        "PF-SBOM-CLOSURE",
                        f"tool runtime file {leaf.ref.path} has no bundle owner",
                    )
                bundle_leaf = bundle_leaf_by_path.get(leaf.ref.path)
                if (
                    bundle_leaf is None
                    or bundle_leaf.digest != leaf.digest
                    or bundle_leaf.size != leaf.size
                ):
                    fail(
                        "PF-SBOM-CLOSURE",
                        f"tool runtime file {leaf.ref.path} does not join its bundle-file leaf",
                    )
                refs = components[component_id]["toolLockRefs"]
                refs.append("tool-runtime-file")
                refs.sort()
                tool_component = _component_id("tool-executable", platform, leaf.ref.id)
                if tool_component not in components:
                    fail("PF-SBOM-CLOSURE", f"tool runtime owner {leaf.ref.id} is missing")
                add_relationship("loads", tool_component, component_id)

        runtime = load_runtime_manifest(root, platform, lock)
        manifest = runtime["manifest"]
        compiler_asset_component = asset_components[manifest["compilerAssetId"]]
        runtime_components: dict[str, str] = {}
        for entry in manifest["files"]:
            component_id = _component_id("runtime-dylib-file", platform, entry["path"])
            runtime_components[entry["path"]] = component_id
            add_component(
                {
                    "id": component_id,
                    "kind": "runtime-dylib-file",
                    "platform": platform,
                    "path": entry["path"],
                    "size": entry["size"],
                    "toolLockRefs": [],
                    "compilerRuntime": True,
                },
                "sha256:" + entry["sha256"],
            )
            add_relationship("unpacks-to", compiler_asset_component, component_id)
        for edge in manifest["loadEdges"]:
            resolved = edge["resolved"]
            if any(resolved.startswith(prefix) for prefix in manifest["systemLoadRoots"]):
                continue
            source_path = edge["owner"]
            if source_path in runtime_components:
                source = runtime_components[source_path]
            else:
                source = _component_id("compiler-executable", platform, source_path)
                if source not in components:
                    fail("PF-SBOM-CLOSURE", f"load edge owner {source_path} unresolved")
            add_relationship("loads", source, runtime_components[resolved])

    # licensed-under edges: every download asset + the lean package root
    for lock in locks:
        platform = lock["platform"]
        for asset in lock["value"]["assets"]:
            component_id = _component_id("download-asset", platform, asset["id"])
            inventory_id = None
            for key in license_mapping:
                prefix, _, version = key.partition("-")
                alternatives = {key, f"{prefix}-v{version}" if version else key}
                if any(asset["id"] == alt or asset["id"].startswith(alt + "-") for alt in alternatives):
                    inventory_id = key
                    break
            if inventory_id is None:
                fail("PF-SBOM-LICENSE", f"asset {asset['id']} has no license inventory entry")
            license_path = license_mapping[inventory_id]
            add_relationship("licensed-under", component_id, license_components[license_path])

    pinned_files = load_package_files_manifest(root)
    package_files = ["ProofForgeV2.lean"]
    package_root = root / "ProofForgeV2"
    if package_root.is_dir():
        package_files.extend(
            str(path.relative_to(root))
            for path in sorted(package_root.rglob("*.lean"))
        )
    if len(package_files) > MAX_FILE_SET:
        fail("PF-SBOM-LIMIT", "lean package file set exceeds the pinned budget")
    actual_records: dict[str, dict[str, object]] = {}
    for relative in package_files:
        data = read_regular_bytes(root, relative)
        actual_records[relative] = {
            "path": relative,
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        }
    if actual_records != {record["path"]: record for record in pinned_files}:
        fail(
            "PF-SBOM-CLOSURE",
            "lean package file set drifts from the pinned manifest",
        )
    file_records = [actual_records[path] for path in sorted(actual_records)]
    tree_identity = CORE.domain_digest(
        PACKAGE_TREE_DOMAIN, CORE.canonical_pf_jcs({"files": file_records})
    )
    package_component_id = _component_id("lean-package", None, "proof-forge-next")
    add_component(
        {
            "id": package_component_id,
            "kind": "lean-package",
            "fileSet": file_records,
        },
        tree_identity,
    )
    if "proof-forge-next" in license_mapping:
        add_relationship(
            "licensed-under",
            package_component_id,
            license_components[license_mapping["proof-forge-next"]],
        )

    root_ref = "proof-forge:synthetic-bom-root"
    for component_id in sorted(components):
        add_relationship("bom-member", root_ref, component_id)

    _validate_relationship_graph(
        relationships,
        set(components),
        {identity["id"] for identity in contents.values()},
        root_ref,
    )

    component_list = [components[key] for key in sorted(components)]
    kind_counts: dict[str, int] = {}
    for component in component_list:
        kind_counts[component["kind"]] = kind_counts.get(component["kind"], 0) + 1
    relationship_counts: dict[str, int] = {}
    for relationship in relationships:
        kind = relationship["kind"]
        relationship_counts[kind] = relationship_counts.get(kind, 0) + 1

    return {
        "components": component_list,
        "contentIdentities": [contents[key] for key in sorted(contents)],
        "relationships": sorted(
            relationships,
            key=lambda item: (item["kind"], item["from"], item["to"]),
        ),
        "counts": {
            "toolLockLeafRefs": sum(len(lock["leaves"]) for lock in locks),
            "logicalComponents": {
                "byKind": kind_counts,
                "total": len(component_list),
            },
            "contentIdentities": len(contents),
            "typedRelationships": {
                "byKind": relationship_counts,
                "total": len(relationships),
            },
        },
        "syntheticRootRef": root_ref,
    }


# --- Rendering -----------------------------------------------------------------------


def _derive_bom_ref(component: dict[str, object]) -> str:
    preimage = {
        "contentRef": component["contentRef"],
        "id": component["id"],
        "kind": component["kind"],
        "platform": component.get("platform"),
    }
    digest = CORE.domain_digest(
        "proof-forge.sbom-component.v1", CORE.canonical_pf_jcs(preimage)
    )
    return "urn:proofforge:component:" + digest[7:]


def render_bom(closure: dict[str, object], candidate: dict[str, object]) -> dict[str, object]:
    components = []
    for component in closure["components"]:
        bom_ref = _derive_bom_ref(component)
        components.append(
            {
                "bom-ref": bom_ref,
                "type": "library" if component["kind"] == "runtime-dylib-file" else "application",
                "name": component["id"],
                "properties": [
                    {"name": "proof-forge:kind", "value": component["kind"]},
                    {"name": "proof-forge:contentRef", "value": component["contentRef"]},
                ],
            }
        )
    root_ref = CORE.candidate_root_bom_ref("sha256:" + candidate["archiveDigest"])
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "version": 1,
        "metadata": {
            "component": {
                "bom-ref": root_ref,
                "type": "application",
                "name": "proof-forge-next-candidate",
                "hashes": [{"alg": "SHA-256", "content": candidate["archiveDigest"]}],
            }
        },
        "components": components,
        "dependencies": [
            {
                "ref": root_ref,
                "dependsOn": [item["bom-ref"] for item in components],
            }
        ],
    }


def render_closure_document(
    closure: dict[str, object],
    candidate: dict[str, object],
    locks: list[dict[str, object]],
    standards: dict[str, object],
) -> dict[str, object]:
    return {
        "schema": CLOSURE_SCHEMA,
        "candidate": {
            "commit": candidate["commit"],
            "treeObjectId": candidate["treeObjectId"],
            "archiveDigest": candidate["archiveDigest"],
            "archiveSize": candidate["archiveSize"],
            "digest": candidate["digest"],
        },
        "toolLocks": [
            {
                "path": lock["path"],
                "platform": lock["platform"],
                "rawSha256": lock["rawSha256"],
                "typedDigest": lock["typedDigest"],
                "domain": lock["domain"],
            }
            for lock in locks
        ],
        "standards": {
            "manifest": standards["path"],
            "manifestSha256": standards["rawSha256"],
            "files": standards["files"],
        },
        "components": closure["components"],
        "contentIdentities": closure["contentIdentities"],
        "relationships": closure["relationships"],
        "counts": closure["counts"],
        "syntheticRootRef": closure["syntheticRootRef"],
    }


def render_binding(
    candidate: dict[str, object],
    locks: list[dict[str, object]],
    standards: dict[str, object],
    closure_bytes: bytes,
    bom_bytes: bytes,
) -> dict[str, object]:
    return {
        "schema": BINDING_SCHEMA,
        "candidate": {
            "commit": candidate["commit"],
            "treeObjectId": candidate["treeObjectId"],
            "archiveDigest": candidate["archiveDigest"],
            "archiveSize": candidate["archiveSize"],
            "digest": candidate["digest"],
        },
        "toolLocks": [
            {"path": lock["path"], "rawSha256": lock["rawSha256"], "typedDigest": lock["typedDigest"]}
            for lock in locks
        ],
        "standards": {"manifest": standards["path"], "manifestSha256": standards["rawSha256"]},
        "closureSha256": sha256_prefixed(closure_bytes),
        "bomSha256": sha256_prefixed(bom_bytes),
        "generator": {"id": GENERATOR_ID, "version": GENERATOR_VERSION},
    }


# --- Atomic output ---------------------------------------------------------------------


FAULT_INJECTION_POINTS = (
    "write",
    "fsync-file",
    "chmod",
    "fsync-staging",
    "rename",
    "fsync-parent",
)

# Test-only fault-injection seam: point name -> exception instance to raise.
# Production runs leave this empty; tests install and restore it per case.
_IO_FAULTS: dict[str, BaseException] = {}


def _fault_point(name: str) -> None:
    error = _IO_FAULTS.get(name)
    if error is not None:
        raise error


def write_sidecars_atomic(destination: Path, files: dict[str, bytes]) -> None:
    if os.path.lexists(destination):
        fail("PF-OUTPUT-ATOMICITY", f"destination already exists: {destination}")
    parent = destination.parent
    try:
        parent_stat = os.lstat(parent)
    except OSError:
        fail("PF-OUTPUT-ATOMICITY", f"destination parent missing: {parent}")
    if stat.S_ISLNK(parent_stat.st_mode):
        fail("PF-SBOM-IO", f"destination parent is a symlink: {parent}")
    if not stat.S_ISDIR(parent_stat.st_mode):
        fail("PF-OUTPUT-ATOMICITY", f"destination parent missing: {parent}")
    if parent_stat.st_mode & 0o022:
        fail("PF-SBOM-IO", f"destination parent is group/world-writable: {parent}")
    for name, data in files.items():
        if len(data) > MAX_SIDECAR_BYTES:
            fail("PF-SBOM-LIMIT", f"sidecar {name} exceeds the byte budget")
    staging = Path(
        tempfile.mkdtemp(prefix=destination.name + ".staging-", dir=parent)
    )
    renamed = False
    try:
        for name, data in files.items():
            if name not in SIDECAR_NAMES:
                fail("PF-SBOM-SCHEMA", f"unexpected sidecar {name}")
            path = staging / name
            _fault_point("write")
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o444)
            try:
                with os.fdopen(fd, "wb", closefd=True) as handle:
                    fd = -1
                    handle.write(data)
                    handle.flush()
                    _fault_point("fsync-file")
                    os.fsync(handle.fileno())
            finally:
                if fd >= 0:
                    os.close(fd)
            _fault_point("chmod")
            os.chmod(path, 0o444)
        dir_fd = os.open(staging, os.O_RDONLY | os.O_DIRECTORY)
        try:
            _fault_point("fsync-staging")
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
        if destination.exists():
            fail("PF-OUTPUT-ATOMICITY", f"destination appeared during staging: {destination}")
        _fault_point("rename")
        os.rename(staging, destination)
        renamed = True
        parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            _fault_point("fsync-parent")
            os.fsync(parent_fd)
        finally:
            os.close(parent_fd)
    except SbomClosureError:
        raise
    except BaseException as error:
        fail("PF-OUTPUT-ATOMICITY", f"sidecar publication failed at {destination}: {error}")
    finally:
        if not renamed and Path(staging).exists():
            for item in Path(staging).iterdir():
                item.chmod(0o644)
                item.unlink()
            Path(staging).rmdir()


# --- Public API -------------------------------------------------------------------------


def compute_closure(root: Path, candidate: dict[str, object]) -> dict[str, object]:
    candidate = parse_candidate(candidate)
    bind_candidate_archive(candidate)
    if not root.is_dir():
        fail("PF-SBOM-IO", f"root is not a directory: {root}")
    locks = [load_lock(root, relative) for relative in LOCK_FILES]
    standards = load_standards(root)
    closure = resolve_closure(root, locks)
    return {
        "candidate": candidate,
        "locks": locks,
        "standards": standards,
        "closure": closure,
    }


def render_sidecars(computed: dict[str, object]) -> dict[str, bytes]:
    candidate = computed["candidate"]
    locks = computed["locks"]
    standards = computed["standards"]
    closure = computed["closure"]
    closure_doc = render_closure_document(closure, candidate, locks, standards)
    bom_doc = render_bom(closure, candidate)
    closure_bytes = CORE.canonical_pf_jcs(closure_doc)
    bom_bytes = CORE.canonical_pf_jcs(bom_doc)
    binding_doc = render_binding(candidate, locks, standards, closure_bytes, bom_bytes)
    binding_bytes = CORE.canonical_pf_jcs(binding_doc)
    return {
        "supply-chain-closure.v1.json": closure_bytes,
        "bom.cdx.json": bom_bytes,
        "sbom-release-binding.v1.json": binding_bytes,
    }


def generate_sidecars(
    *,
    root: Path,
    candidate: dict[str, object],
    destination: Path,
    timeout: float | None = None,
) -> None:
    del timeout  # generation is synchronous; FIFO/non-regular inputs fail fast
    computed = compute_closure(Path(root), candidate)
    files = render_sidecars(computed)
    write_sidecars_atomic(Path(destination), files)


def _legacy_sidecar_code(actual: bytes) -> str:
    """Classify a mismatching sidecar: known legacy schema -> PF-SBOM-SCHEMA.

    The D0-05 legacy outputs (`license-inventory.v1`, null-root CycloneDX BOM,
    digest-map) are rejected on the release path without fallback; anything
    else is a plain binding mismatch.
    """

    try:
        value = CORE.decode_json_document(actual)
    except Exception:  # noqa: BLE001 - undecodable bytes are never legacy
        return "PF-SBOM-BIND"
    if type(value) is dict:
        if value.get("schema") == LICENSE_INVENTORY_SCHEMA:
            return "PF-SBOM-SCHEMA"
        if LEGACY_DIGEST_MAP_KEYS <= set(value):
            return "PF-SBOM-SCHEMA"
        if value.get("bomFormat") == "CycloneDX":
            metadata = value.get("metadata")
            component = metadata.get("component") if type(metadata) is dict else None
            if type(component) is dict and "hashes" not in component:
                return "PF-SBOM-SCHEMA"
    return "PF-SBOM-BIND"


def verify_existing(*, root: Path, candidate: dict[str, object], destination: Path) -> None:
    computed = compute_closure(Path(root), candidate)
    expected = render_sidecars(computed)
    destination = Path(destination)
    try:
        destination_stat = os.lstat(destination)
    except OSError:
        fail("PF-SBOM-BIND", f"sidecar directory missing: {destination}")
    if stat.S_ISLNK(destination_stat.st_mode):
        fail("PF-SBOM-IO", f"sidecar directory is a symlink: {destination}")
    if not stat.S_ISDIR(destination_stat.st_mode):
        fail("PF-SBOM-BIND", f"sidecar directory missing: {destination}")
    actual_names = sorted(item.name for item in destination.iterdir())
    if tuple(actual_names) != tuple(sorted(SIDECAR_NAMES)):
        fail("PF-SBOM-BIND", f"sidecar directory members differ: {actual_names}")
    for name, expected_bytes in expected.items():
        target = destination / name
        try:
            fd = os.open(target, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
        except OSError as error:
            fail("PF-SBOM-IO", f"sidecar {name} cannot be opened: {error.strerror or error}")
        try:
            metadata = os.fstat(fd)
            if not stat.S_ISREG(metadata.st_mode):
                fail("PF-SBOM-IO", f"sidecar {name} is not a regular file")
            if metadata.st_nlink != 1:
                fail("PF-SBOM-IO", f"sidecar {name} is not a single-link file")
            if metadata.st_size > MAX_SIDECAR_BYTES:
                fail("PF-SBOM-LIMIT", f"sidecar {name} exceeds the byte budget")
            with os.fdopen(fd, "rb", closefd=True) as handle:
                fd = -1
                actual = handle.read()
        finally:
            if fd >= 0:
                os.close(fd)
        if actual != expected_bytes:
            fail(
                _legacy_sidecar_code(actual),
                f"sidecar {name} differs from the recomputed bytes",
            )


def read_external_regular_bytes(path: Path, *, code: str = "PF-SBOM-IO") -> bytes:
    """Read a checkout-external regular file (candidate JSON/archive family)."""

    try:
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        fail(code, f"cannot read {path}: {error.strerror or error}")
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            fail(code, f"not a regular file: {path}")
        if metadata.st_size > MAX_INPUT_BYTES:
            fail("PF-SBOM-LIMIT", f"input exceeds byte budget: {path}")
        with os.fdopen(fd, "rb", closefd=True) as handle:
            fd = -1
            return handle.read()
    finally:
        if fd >= 0:
            os.close(fd)
    return b""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="sbom_closure.py")
    parser.add_argument("--root", required=True, type=Path)
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("generate", "verify-existing"):
        child = sub.add_parser(command)
        child.add_argument("--candidate", required=True, type=Path)
        child.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    candidate = decode_json(read_external_regular_bytes(args.candidate), "candidate")
    try:
        if args.command == "generate":
            generate_sidecars(root=args.root, candidate=candidate, destination=args.output_dir)
        else:
            verify_existing(root=args.root, candidate=candidate, destination=args.output_dir)
    except SbomClosureError as error:
        print(f"{error.code}: {error.detail}", file=sys.stderr)
        return 1
    print(f"sbom-closure: {args.command} ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

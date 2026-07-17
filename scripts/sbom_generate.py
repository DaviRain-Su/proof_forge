#!/usr/bin/env python3
"""Deterministic license inventory validation and CycloneDX 1.6 SBOM generation.

Dependency-free. Intended for TASK-D0-05 / TST-SBOM-001 development gates.
Does not claim formal hermetic release evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any


INVENTORY_SCHEMA = "proof-forge.license-inventory.v1"
POLICY_SCHEMA = "proof-forge.license-policy.v1"
ROOT_COMPONENT_ID = "proof-forge-next"
SPDX_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.+_-]{0,127}$")
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")


class SbomError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


class DuplicateJsonKey(ValueError):
    pass


def fail(code: str, message: str) -> None:
    raise SbomError(code, message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJsonKey(f"duplicate object key {key!r}")
        result[key] = value
    return result


def sha256_project_regular_file(root: Path, relative: str, component_id: str) -> str:
    """Hash a repository file without following any path-component symlink."""
    if "\x00" in relative:
        fail(
            "PF-SBOM-LICENSE",
            f"{component_id}: licenseFile contains an embedded NUL",
        )
    parts = Path(relative).parts
    if not parts:
        fail("PF-SBOM-LICENSE", f"{component_id}: empty licenseFile path")

    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
    file_flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
    directory_fd = -1
    file_fd = -1
    try:
        directory_fd = os.open(root, directory_flags)
        for part in parts[:-1]:
            next_fd = os.open(part, directory_flags, dir_fd=directory_fd)
            os.close(directory_fd)
            directory_fd = next_fd
        file_fd = os.open(parts[-1], file_flags, dir_fd=directory_fd)
        metadata = os.fstat(file_fd)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            fail(
                "PF-SBOM-LICENSE",
                f"{component_id}: licenseFile must be a regular single-link "
                f"non-symlink file: {relative}",
            )

        digest = hashlib.sha256()
        with os.fdopen(file_fd, "rb", closefd=True) as handle:
            file_fd = -1
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
        return digest.hexdigest()
    except (OSError, ValueError) as error:
        fail(
            "PF-SBOM-LICENSE",
            f"{component_id}: licenseFile must be a regular non-symlink file "
            f"inside the repository: {relative}: {error}",
        )
    finally:
        if file_fd >= 0:
            os.close(file_fd)
        if directory_fd >= 0:
            os.close(directory_fd)


def load_json(path: Path) -> Any:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        fail("PF-SBOM-IO", f"cannot read {path}: {error}")
    try:
        return json.loads(text, object_pairs_hook=reject_duplicate_object_keys)
    except DuplicateJsonKey as error:
        fail("PF-SBOM-JSON", f"invalid JSON in {path}: {error}")
    except json.JSONDecodeError as error:
        fail("PF-SBOM-JSON", f"invalid JSON in {path}: {error}")


def require_dict(value: Any, where: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail("PF-SBOM-SCHEMA", f"{where} must be an object")
    return value


def require_str(value: Any, where: str) -> str:
    if not isinstance(value, str) or not value:
        fail("PF-SBOM-SCHEMA", f"{where} must be a non-empty string")
    return value


def require_bool(value: Any, where: str) -> bool:
    if not isinstance(value, bool):
        fail("PF-SBOM-SCHEMA", f"{where} must be a boolean")
    return value


def canonical_json(value: Any) -> bytes:
    """RFC 8785-inspired: UTF-8, sorted object keys, no insignificant whitespace."""
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
        allow_nan=False,
    ).encode("utf-8")


def load_policy(path: Path) -> dict[str, Any]:
    raw = require_dict(load_json(path), "license-policy")
    if raw.get("schema") != POLICY_SCHEMA:
        fail("PF-SBOM-POLICY", f"policy schema must be {POLICY_SCHEMA}")
    for key in ("allow", "review", "deny"):
        items = raw.get(key)
        if not isinstance(items, list) or not items or not all(isinstance(x, str) for x in items):
            fail("PF-SBOM-POLICY", f"policy.{key} must be a non-empty string array")
        if items != sorted(items):
            fail("PF-SBOM-POLICY", f"policy.{key} must be sorted ascending")
        if len(set(items)) != len(items):
            fail("PF-SBOM-POLICY", f"policy.{key} must be unique")
    external = require_dict(raw.get("externalCli", {}), "policy.externalCli")
    allowed_deny = external.get("allowedDenyLicensesWhenNotRedistributable", [])
    if not isinstance(allowed_deny, list) or not all(isinstance(x, str) for x in allowed_deny):
        fail("PF-SBOM-POLICY", "externalCli.allowedDenyLicensesWhenNotRedistributable invalid")
    return raw


def validate_component(component: dict[str, Any], root: Path, policy: dict[str, Any]) -> None:
    required = (
        "id", "name", "version", "type", "supplier", "licenseSpdx",
        "licenseFile", "licenseFileSha256", "redistributable", "dependsOn",
    )
    missing = [key for key in required if key not in component]
    if missing:
        fail("PF-SBOM-INVENTORY", f"component missing fields {missing}")
    component_id = require_str(component["id"], "component.id")
    require_str(component["name"], "component.name")
    require_str(component["version"], "component.version")
    ctype = require_str(component["type"], "component.type")
    if ctype not in {"application", "library", "firmware", "file", "operating-system"}:
        fail("PF-SBOM-INVENTORY", f"{component_id}: unsupported type {ctype}")
    # sha256 is mandatory for every component except the root product component
    # (enforced in load_inventory): the product archive digest cannot be pinned
    # inside a file that is itself part of that archive (TASK-D0-08 scope).
    digest = component.get("sha256")
    if digest is not None:
        digest = require_str(digest, "component.sha256")
        if not HEX64_RE.fullmatch(digest):
            fail("PF-SBOM-INVENTORY", f"{component_id}: sha256 must be 64 lowercase hex")
    require_str(component["supplier"], "component.supplier")
    license_spdx = require_str(component["licenseSpdx"], "component.licenseSpdx")
    if not SPDX_RE.fullmatch(license_spdx):
        fail("PF-SBOM-INVENTORY", f"{component_id}: invalid SPDX expression token")
    if license_spdx in {"NOASSERTION", "NONE", "UNKNOWN", "unknown"}:
        fail("PF-SBOM-LICENSE", f"{component_id}: NOASSERTION/unknown license blocked")
    license_file = require_str(component["licenseFile"], "component.licenseFile")
    if Path(license_file).is_absolute() or ".." in Path(license_file).parts:
        fail("PF-SBOM-INVENTORY", f"{component_id}: licenseFile must be project-relative")
    expected = require_str(component["licenseFileSha256"], "component.licenseFileSha256")
    if not HEX64_RE.fullmatch(expected):
        fail("PF-SBOM-INVENTORY", f"{component_id}: licenseFileSha256 invalid")
    actual = sha256_project_regular_file(root, license_file, component_id)
    if actual != expected:
        fail(
            "PF-SBOM-LICENSE",
            f"{component_id}: license file hash mismatch expected={expected} actual={actual}",
        )
    redistributable = require_bool(component["redistributable"], "component.redistributable")
    depends = component["dependsOn"]
    if not isinstance(depends, list) or not all(isinstance(x, str) for x in depends):
        fail("PF-SBOM-INVENTORY", f"{component_id}: dependsOn must be a string array")
    if depends != sorted(depends) or len(set(depends)) != len(depends):
        fail("PF-SBOM-INVENTORY", f"{component_id}: dependsOn must be unique and sorted")

    allow = set(policy["allow"])
    review = set(policy["review"])
    deny = set(policy["deny"])
    external_ok = set(
        policy.get("externalCli", {}).get("allowedDenyLicensesWhenNotRedistributable", [])
    )
    if license_spdx in deny:
        if not (not redistributable and license_spdx in external_ok):
            fail(
                "PF-SBOM-POLICY",
                f"{component_id}: license {license_spdx} denied by policy "
                f"(redistributable={redistributable})",
            )
    elif license_spdx in review:
        fail("PF-SBOM-POLICY", f"{component_id}: license {license_spdx} requires review")
    elif license_spdx not in allow:
        fail("PF-SBOM-POLICY", f"{component_id}: license {license_spdx} not in allow list")


def load_inventory(path: Path, root: Path, policy: dict[str, Any]) -> dict[str, Any]:
    raw = require_dict(load_json(path), "license-inventory")
    if raw.get("schema") != INVENTORY_SCHEMA:
        fail("PF-SBOM-INVENTORY", f"inventory schema must be {INVENTORY_SCHEMA}")
    components = raw.get("components")
    if not isinstance(components, list) or not components:
        fail("PF-SBOM-INVENTORY", "components must be a non-empty array")
    ids: list[str] = []
    for index, item in enumerate(components):
        component = require_dict(item, f"components[{index}]")
        validate_component(component, root, policy)
        if "sha256" not in component and component["id"] != ROOT_COMPONENT_ID:
            fail(
                "PF-SBOM-INVENTORY",
                f"{component['id']}: sha256 required for non-root components",
            )
        ids.append(component["id"])
    if ids != sorted(ids):
        fail("PF-SBOM-INVENTORY", "components must be sorted by id ascending")
    if len(set(ids)) != len(ids):
        fail("PF-SBOM-INVENTORY", "component ids must be unique")
    id_set = set(ids)
    for component in components:
        for dependency in component["dependsOn"]:
            if dependency not in id_set:
                fail(
                    "PF-SBOM-INVENTORY",
                    f"{component['id']} depends on unknown {dependency}",
                )
            if dependency == component["id"]:
                fail("PF-SBOM-INVENTORY", f"{component['id']} self-dependency")
    return raw


def license_ids(expression: str) -> set[str]:
    """Collect license ids from a simple SPDX expression (OR/AND/WITH, parens)."""
    ids: set[str] = set()
    tokens = expression.replace("(", " ").replace(")", " ").split()
    skip_exception = False
    for token in tokens:
        if skip_exception:
            skip_exception = False
            continue
        marker = token.upper()
        if marker in {"OR", "AND"}:
            continue
        if marker == "WITH":
            skip_exception = True
            continue
        ids.add(token)
    return ids


def check_lock_closure(root: Path, inventory: dict[str, Any]) -> None:
    """Fail closed (PF-SBOM-CLOSURE) unless every locked asset/tool is covered by
    the inventory with a matching SHA-256 and a consistent SPDX license id.
    A dual-licensed tool expression (e.g. "MIT OR Apache-2.0") is consistent when
    the inventory records one of the offered license ids."""
    lock = require_dict(load_json(root / "toolchains.lock.json"), "toolchains.lock")
    assets = lock.get("assets")
    tools = lock.get("tools")
    if not isinstance(assets, list) or not isinstance(tools, list):
        fail("PF-SBOM-CLOSURE", "toolchains.lock.json must contain assets and tools arrays")
    components_by_digest: dict[str, dict[str, Any]] = {}
    for component in inventory["components"]:
        digest = component.get("sha256")
        if isinstance(digest, str):
            components_by_digest[digest] = component
    asset_digests: dict[str, str] = {}
    for asset in assets:
        if not isinstance(asset, dict):
            fail("PF-SBOM-CLOSURE", "toolchains.lock.json asset entries must be objects")
        asset_id = asset.get("id")
        digest = asset.get("sha256")
        if (not isinstance(asset_id, str) or not asset_id or
                not isinstance(digest, str) or not HEX64_RE.fullmatch(digest)):
            fail("PF-SBOM-CLOSURE", "toolchains.lock.json asset id/sha256 invalid")
        if digest not in components_by_digest:
            fail(
                "PF-SBOM-CLOSURE",
                f"locked asset {asset_id} ({digest[:12]}…) missing from license inventory",
            )
        asset_digests[asset_id] = digest
    for tool in tools:
        if not isinstance(tool, dict):
            fail("PF-SBOM-CLOSURE", "toolchains.lock.json tool entries must be objects")
        tool_id = tool.get("id")
        asset_id = tool.get("assetId")
        expression = tool.get("licenseSpdx")
        if (not isinstance(tool_id, str) or not tool_id or
                not isinstance(asset_id, str) or
                not isinstance(expression, str) or not expression):
            fail("PF-SBOM-CLOSURE", "toolchains.lock.json tool id/assetId/licenseSpdx invalid")
        digest = asset_digests.get(asset_id)
        if digest is None:
            fail("PF-SBOM-CLOSURE", f"tool {tool_id} references unknown asset {asset_id}")
        component = components_by_digest[digest]
        if component["licenseSpdx"] not in license_ids(expression):
            fail(
                "PF-SBOM-CLOSURE",
                f"tool {tool_id} license '{expression}' inconsistent with inventory "
                f"component {component['id']} license '{component['licenseSpdx']}'",
            )


def component_ref(component: dict[str, Any]) -> str:
    digest = component.get("sha256")
    if isinstance(digest, str) and digest:
        return f"urn:proofforge:component:{digest}"
    return f"urn:proofforge:component:id:{component['id']}"


def generate_cyclonedx(inventory: dict[str, Any]) -> dict[str, Any]:
    components_out: list[dict[str, Any]] = []
    dependencies_out: list[dict[str, Any]] = []
    for component in inventory["components"]:
        ref = component_ref(component)
        entry = {
            "bom-ref": ref,
            "type": component["type"],
            "name": component["name"],
            "version": component["version"],
            "supplier": {"name": component["supplier"]},
            "licenses": [
                {
                    "license": {
                        "id": component["licenseSpdx"],
                    }
                }
            ],
            "properties": [
                {"name": "proofforge:component-id", "value": component["id"]},
                {
                    "name": "proofforge:redistributable",
                    "value": "true" if component["redistributable"] else "false",
                },
                {
                    "name": "proofforge:license-file",
                    "value": component["licenseFile"],
                },
            ],
        }
        if "sha256" in component:
            entry["hashes"] = [
                {
                    "alg": "SHA-256",
                    "content": component["sha256"],
                }
            ]
        components_out.append(entry)
        dep_refs = [component_ref(next(
            c for c in inventory["components"] if c["id"] == dep_id
        )) for dep_id in component["dependsOn"]]
        dependencies_out.append({
            "ref": ref,
            "dependsOn": sorted(dep_refs),
        })
    components_out.sort(key=lambda item: item["bom-ref"])
    dependencies_out.sort(key=lambda item: item["ref"])
    document = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "name": "proof-forge-next",
                "bom-ref": component_ref(
                    next(
                        c for c in inventory["components"]
                        if c["id"] == ROOT_COMPONENT_ID
                    )
                ),
            },
            "tools": {
                "components": [
                    {
                        "type": "application",
                        "name": "proof-forge-sbom-generate",
                        "version": "0.1.0",
                    }
                ]
            },
        },
        "components": components_out,
        "dependencies": dependencies_out,
    }
    return document


def write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def build_from_repo(root: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, str]]:
    policy_path = root / "docs/supply-chain/license-policy.v1.json"
    inventory_path = root / "docs/supply-chain/license-inventory.v1.json"
    policy = load_policy(policy_path)
    inventory = load_inventory(inventory_path, root, policy)
    check_lock_closure(root, inventory)
    bom = generate_cyclonedx(inventory)
    digests = {
        "policySha256": sha256_bytes(canonical_json(policy)),
        "inventorySha256": sha256_bytes(canonical_json(inventory)),
        "bomSha256": sha256_bytes(canonical_json(bom)),
    }
    return inventory, bom, digests


def cmd_generate(root: Path, output_dir: Path) -> int:
    inventory, bom, digests = build_from_repo(root)
    write_bytes(output_dir / "license-inventory.v1.json", canonical_json(inventory) + b"\n")
    write_bytes(output_dir / "bom.cdx.json", canonical_json(bom) + b"\n")
    write_bytes(output_dir / "sbom-digests.v1.json", canonical_json(digests) + b"\n")
    print(f"sbom-generate: ok inventory={digests['inventorySha256'][:12]}… "
          f"bom={digests['bomSha256'][:12]}…")
    return 0


def cmd_verify(root: Path, output_dir: Path) -> int:
    inventory, bom, digests = build_from_repo(root)
    expected_inventory = (output_dir / "license-inventory.v1.json").read_bytes()
    expected_bom = (output_dir / "bom.cdx.json").read_bytes()
    expected_digests = load_json(output_dir / "sbom-digests.v1.json")
    if expected_inventory != canonical_json(inventory) + b"\n":
        fail("PF-SBOM-BIND", "inventory bytes drifted from generator")
    if expected_bom != canonical_json(bom) + b"\n":
        fail("PF-SBOM-BIND", "bom bytes drifted from generator")
    if expected_digests != digests:
        fail("PF-SBOM-BIND", "digest map drifted from generator")
    print("sbom-verify: ok")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    sub = parser.add_subparsers(dest="command", required=True)
    generate = sub.add_parser("generate")
    generate.add_argument(
        "--output-dir",
        type=Path,
        default=Path("build/sbom"),
    )
    verify = sub.add_parser("verify")
    verify.add_argument(
        "--output-dir",
        type=Path,
        default=Path("build/sbom"),
    )
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    try:
        if arguments.command == "generate":
            return cmd_generate(root, arguments.output_dir.resolve())
        if arguments.command == "verify":
            return cmd_verify(root, arguments.output_dir.resolve())
        fail("PF-SBOM-CLI", f"unknown command {arguments.command}")
    except SbomError as error:
        print(f"{error.code}: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

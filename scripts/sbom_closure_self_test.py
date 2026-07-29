#!/usr/bin/env python3
"""TST-SBOM-002 acceptance self-test (TASK-D0-08).

Independent fixture/validator.  The oracle pins the frozen exact counts as
constants (freeze package `frozenCounts`, docs/05-test-spec.md D0-08 section)
and recomputes expectations from committed inputs only; it never derives
expectations from production output.

RED contract: every SB2 case fails while `scripts/sbom_closure.py` does not
exist, and the legacy D0-05 generator (`scripts/sbom_generate.py`) must never
be able to make this acceptance green.  Run with:

    /usr/bin/python3 -I -S scripts/sbom_closure_self_test.py
"""

from __future__ import annotations

import hashlib
import errno
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PRODUCTION_RELATIVE = "scripts/sbom_closure.py"
PRODUCTION_PATH = REPO_ROOT / PRODUCTION_RELATIVE

# --- Frozen exact counts (docs/governance/task-freeze-packages/TASK-D0-08.json) ---

FROZEN_LEAF_REFS = {
    "toolchains.lock.json": {
        "asset": 6,
        "bundle-file": 6,
        "compiler-executable": 2,
        "tool-executable": 5,
        "tool-runtime-file": 1,
        "total": 20,
    },
    "toolchains-linux-x86_64.lock.json": {
        "asset": 5,
        "bundle-file": 5,
        "compiler-executable": 2,
        "tool-executable": 5,
        "tool-runtime-file": 0,
        "total": 17,
    },
}
FROZEN_LEAF_TOTAL = 37
FROZEN_COMPILER_RUNTIME = {"darwin-arm64": 5, "linux-x86_64": 5, "total": 10}
FROZEN_COMPONENTS = {
    "lean-package": 1,
    "source-dependency": 0,
    "download-asset": 11,
    "compiler-executable": 4,
    "tool-executable": 10,
    "runtime-dylib-file": 11,
    "bundled-license-text": 4,
    "total": 41,
}
FROZEN_PACKAGE_FILE_SET = 30
FROZEN_CONTENT_IDENTITIES = 37
FROZEN_RELATIONSHIPS = {
    "has-content": 41,
    "unpacks-to": 25,
    "loads": 27,
    "licensed-under": 12,
    "bom-member": 41,
    "total": 146,
}
FROZEN_STANDARDS_FILES = 4
FROZEN_SIDECAR_FILES = (
    "supply-chain-closure.v1.json",
    "bom.cdx.json",
    "sbom-release-binding.v1.json",
)
FROZEN_STANDARDS_PINS = {
    "supply-chain/standards/cyclonedx-bom-1.6.schema.json": (
        252625,
        "3e92dddbc30cf7f6a02b80f0942b1a4cfd4fb1c26f1dfc4310afa9d613cafb93",
    ),
    "supply-chain/standards/spdx-license-list-v3.27.0.json": (
        318777,
        "157789ba91984aecba5c67b84168dbbd41a235b910a7569aa64bf42a88b24290",
    ),
    "supply-chain/standards/spdx-exceptions-v3.27.0.json": (
        37918,
        "650f497016c3a979ec4062067625aedfc10211220abb3b587ca1fb05a22c34eb",
    ),
    "supply-chain/standards/spdx-license-expressions-v2.3.md": (
        11972,
        "2da19cea85d4f7af6c5196cfe92d7d14bdb070b39f47bb4e11a060f075b9c378",
    ),
}
LEGACY_DIGEST_DOMAIN = "proof-forge.toolchain-lock.v1"
EXPECTED_ERROR_CODES = {
    "PF-SBOM-BIND",
    "PF-SBOM-CLOSURE",
    "PF-SBOM-INVENTORY",
    "PF-SBOM-IO",
    "PF-SBOM-JSON",
    "PF-SBOM-LICENSE",
    "PF-SBOM-LIMIT",
    "PF-SBOM-POLICY",
    "PF-SBOM-SCHEMA",
    "PF-OUTPUT-ATOMICITY",
    "PF-RESOURCE-OUTPUT",
}

# --- Oracle: independent closure recompute from committed inputs ----------------


def _load_module(relative: str, name: str):
    spec = importlib.util.spec_from_file_location(name, REPO_ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def oracle_leaf_counts() -> dict[str, dict[str, int]]:
    """Recompute per-platform Tool Lock leaf counts via the authoritative core."""

    core = _load_module("scripts/supply_chain_core.py", "pf_supply_chain_core_oracle")
    counts: dict[str, dict[str, int]] = {}
    for name in FROZEN_LEAF_REFS:
        raw = (REPO_ROOT / name).read_bytes()
        leaves = core.enumerate_tool_lock_leaves(raw)
        per: dict[str, int] = {}
        for leaf in leaves:
            per[leaf.ref.kind] = per.get(leaf.ref.kind, 0) + 1
        per["total"] = len(leaves)
        counts[name] = per
    return counts


def oracle_standards_digests() -> dict[str, tuple[int, str]]:
    result: dict[str, tuple[int, str]] = {}
    for relative in FROZEN_STANDARDS_PINS:
        data = (REPO_ROOT / relative).read_bytes()
        result[relative] = (len(data), hashlib.sha256(data).hexdigest())
    return result


def oracle_package_file_set() -> list[str]:
    files = [REPO_ROOT / "ProofForgeV2.lean"]
    package_source_suffixes = {".lean", ".c", ".h"}
    files.extend(
        sorted(
            path
            for path in (REPO_ROOT / "ProofForgeV2").rglob("*")
            if path.suffix in package_source_suffixes
        )
    )
    return [str(path.relative_to(REPO_ROOT)) for path in files]


# --- Fixture harness ------------------------------------------------------------


def _copy_inputs(destination: Path) -> None:
    """Assemble a synthetic SBOM input root from the real committed inputs."""

    inputs = [
        "toolchains.lock.json",
        "toolchains-linux-x86_64.lock.json",
        "lake-manifest.json",
        "LICENSE",
        "ProofForgeV2.lean",
        "docs/supply-chain/license-inventory.v1.json",
        "docs/supply-chain/license-policy.v1.json",
    ]
    for relative in inputs:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO_ROOT / relative, target)
    for directory in ("licenses", "supply-chain", "ProofForgeV2"):
        target = destination / directory
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(REPO_ROOT / directory, target)


def build_input_root(base: Path, name: str = "input-root") -> Path:
    root = base / name
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    _copy_inputs(root)
    return root


def candidate_fixture(base: Path) -> dict[str, object]:
    """Checkout-external fixed candidate tuple backed by a real archive file."""

    archive = base / "candidate-archive.tar"
    if not archive.exists():
        archive.write_bytes(b"proof-forge-candidate-archive-fixture\n")
    data = archive.read_bytes()
    return {
        "archivePath": str(archive),
        "commit": "0" * 40,
        "treeObjectId": "1" * 40,
        "archiveDigest": hashlib.sha256(data).hexdigest(),
        "archiveSize": len(data),
        "digest": "2" * 40,
    }


def write_candidate(root: Path, candidate: dict[str, object]) -> Path:
    path = root / "candidate.json"
    path.write_text(json.dumps(candidate, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


class CaseFailure(AssertionError):
    pass


def check(condition: bool, detail: str) -> None:
    if not condition:
        raise CaseFailure(detail)


def require_production():
    """Import the production module; every SB2 case is RED while it is absent."""

    if not PRODUCTION_PATH.is_file():
        raise CaseFailure(
            f"RED: production module {PRODUCTION_RELATIVE} does not exist yet"
        )
    module = _load_module(PRODUCTION_RELATIVE, "pf_sbom_closure_production")
    for entry in (
        "compute_closure",
        "generate_sidecars",
        "verify_existing",
        "SbomClosureError",
    ):
        if not hasattr(module, entry):
            raise CaseFailure(f"RED: production module has no `{entry}` entry point")
    return module


# --- SB2 cases ------------------------------------------------------------------


def case_sb2_001_happy_path(base: Path) -> None:
    """Frozen denominators, 3 sidecars, dual-root byte-identical, 0444 modes."""

    production = require_production()
    candidate = candidate_fixture(base)
    sidecars = []
    for name in ("root-a", "root-b"):
        root = build_input_root(base, name)
        destination = base / f"{name}-out"
        production.generate_sidecars(
            root=root, candidate=candidate, destination=destination
        )
        sidecars.append(destination)
    for destination in sidecars:
        entries = sorted(item.name for item in destination.iterdir())
        check(
            tuple(entries) == tuple(sorted(FROZEN_SIDECAR_FILES)),
            f"sidecar closure must be exactly {sorted(FROZEN_SIDECAR_FILES)}, got {entries}",
        )
        for item in destination.iterdir():
            mode = stat.S_IMODE(item.stat().st_mode)
            check(mode == 0o444, f"{item.name} mode {mode:o} != 0444")
    for filename in FROZEN_SIDECAR_FILES:
        left = (sidecars[0] / filename).read_bytes()
        right = (sidecars[1] / filename).read_bytes()
        check(left == right, f"{filename} is not byte-identical across roots")
    closure = json.loads((sidecars[0] / "supply-chain-closure.v1.json").read_text())
    check(
        closure["counts"]["logicalComponents"]["total"] == FROZEN_COMPONENTS["total"],
        "logical component denominator drifted from frozen counts",
    )
    check(
        closure["counts"]["toolLockLeafRefs"] == FROZEN_LEAF_TOTAL,
        "Tool Lock leaf denominator drifted from frozen counts",
    )
    check(
        closure["counts"]["typedRelationships"]["total"] == FROZEN_RELATIONSHIPS["total"],
        "typed relationship denominator drifted from frozen counts",
    )
    check(
        closure["counts"]["contentIdentities"] == FROZEN_CONTENT_IDENTITIES,
        "content identity denominator drifted from frozen counts",
    )


def case_sb2_003_legacy_digest_domain_rejected(base: Path) -> None:
    """A legacy proof-forge.toolchain-lock.v1 typed digest must PF-SBOM-BIND."""

    production = require_production()
    root = build_input_root(base)
    raw = json.loads((root / "toolchains.lock.json").read_text())
    raw["legacyTypedDigest"] = LEGACY_DIGEST_DOMAIN
    (root / "toolchains.lock.json").write_text(json.dumps(raw), encoding="utf-8")
    expect_error(
        production,
        root,
        base / "out-sb2-003",
        {"PF-SBOM-BIND", "PF-SBOM-CLOSURE", "PF-SBOM-SCHEMA"},
        "legacy digest domain must fail closed",
    )


def case_sb2_007_same_bytes_distinct_components(base: Path) -> None:
    """solc asset/bundle/tool-executable share content but keep distinct bom-refs."""

    production = require_production()
    root = build_input_root(base)
    destination = base / "out-sb2-007"
    production.generate_sidecars(
        root=root, candidate=candidate_fixture(base), destination=destination
    )
    bom = json.loads((destination / "bom.cdx.json").read_text())
    refs = {
        component.get("bom-ref")
        for component in bom["components"]
        if "solc" in json.dumps(component)
    }
    check(len(refs) >= 2, "same-bytes solc identities collapsed into one bom-ref")


def case_sb2_008_libcrypto_join(base: Path) -> None:
    """libcrypto bundle-file and tool-runtime refs join one runtime component."""

    production = require_production()
    root = build_input_root(base)
    destination = base / "out-sb2-008"
    production.generate_sidecars(
        root=root, candidate=candidate_fixture(base), destination=destination
    )
    closure = json.loads((destination / "supply-chain-closure.v1.json").read_text())
    runtime = [
        component
        for component in closure["components"]
        if component.get("kind") == "runtime-dylib-file"
        and "libcrypto" in component.get("id", "")
    ]
    check(len(runtime) == 1, "libcrypto must join exactly one runtime component")
    refs = set(runtime[0].get("toolLockRefs", []))
    check(
        refs == {"bundle-file", "tool-runtime-file"},
        f"libcrypto must retain both leaf refs, got {refs}",
    )


def case_sb2_009_leaf_mapping_mutation(base: Path) -> None:
    """Delete/add/duplicate one leaf mapping -> PF-SBOM-CLOSURE, zero output."""

    production = require_production()
    root = build_input_root(base)
    lock_path = root / "toolchains.lock.json"
    raw = json.loads(lock_path.read_text())
    raw["assets"] = raw["assets"][:-1]
    lock_path.write_text(json.dumps(raw), encoding="utf-8")
    expect_error(
        production,
        root,
        base / "out-sb2-009",
        {"PF-SBOM-CLOSURE"},
        "removed asset leaf must fail closed",
    )


def case_sb2_011_runtime_manifest_mutation(base: Path) -> None:
    """Compiler runtime member/edge substitution -> PF-SBOM-CLOSURE."""

    production = require_production()
    root = build_input_root(base)
    manifest = root / "supply-chain" / "compiler-runtime-darwin-arm64.v1.json"
    check(manifest.is_file(), "committed darwin compiler-runtime manifest missing")
    raw = json.loads(manifest.read_text())
    raw["files"] = raw["files"][:-1]
    manifest.write_text(json.dumps(raw), encoding="utf-8")
    expect_error(
        production,
        root,
        base / "out-sb2-011",
        {"PF-SBOM-CLOSURE"},
        "runtime manifest member removal must fail closed",
    )


def case_sb2_018_candidate_mismatch(base: Path) -> None:
    """Candidate tuple mismatch -> PF-SBOM-BIND before archive inventory parsing."""

    production = require_production()
    root = build_input_root(base)
    candidate = candidate_fixture(base)
    candidate["archiveSize"] = int(candidate["archiveSize"]) + 1
    expect_error(
        production,
        root,
        base / "out-sb2-018",
        {"PF-SBOM-BIND"},
        "candidate archiveSize mismatch must fail closed",
        candidate=candidate,
    )


def case_sb2_019_synthetic_root(base: Path) -> None:
    """Synthetic root hash must equal candidate archive raw SHA-256."""

    production = require_production()
    root = build_input_root(base)
    candidate = candidate_fixture(base)
    destination = base / "out-sb2-019"
    production.generate_sidecars(root=root, candidate=candidate, destination=destination)
    bom = json.loads((destination / "bom.cdx.json").read_text())
    root_ref = bom.get("metadata", {}).get("component", {})
    check(
        root_ref.get("hashes", [{}])[0].get("content") == candidate["archiveDigest"],
        "synthetic BOM root must bind the candidate archive raw SHA-256",
    )
    closure = json.loads((destination / "supply-chain-closure.v1.json").read_text())
    ids = [component.get("id") for component in closure["components"]]
    check(
        ids.count(root_ref.get("bom-ref")) == 0,
        "synthetic root must not double as an inventory component",
    )


def case_sb2_022_standards_identity_mutation(base: Path) -> None:
    """Standards file substitution -> PF-SBOM-BIND, zero output."""

    production = require_production()
    root = build_input_root(base)
    target = root / "supply-chain/standards/spdx-license-list-v3.27.0.json"
    data = bytearray(target.read_bytes())
    data[-2] = ord("0") if data[-2] != ord("0") else ord("1")
    target.write_bytes(bytes(data))
    expect_error(
        production,
        root,
        base / "out-sb2-022",
        {"PF-SBOM-BIND", "PF-SBOM-LICENSE", "PF-SBOM-CLOSURE"},
        "standards identity substitution must fail closed",
    )


def case_sb2_023_binding_substitution(base: Path) -> None:
    """Binding field substitution must fail verify-existing closed."""

    production = require_production()
    root = build_input_root(base)
    candidate = candidate_fixture(base)
    destination = base / "out-sb2-023"
    production.generate_sidecars(root=root, candidate=candidate, destination=destination)
    binding_path = destination / "sbom-release-binding.v1.json"
    binding = json.loads(binding_path.read_text())
    binding["generator"] = "tampered-generator"
    binding_path.chmod(0o644)
    binding_path.write_text(json.dumps(binding), encoding="utf-8")
    binding_path.chmod(0o444)
    try:
        production.verify_existing(root=root, candidate=candidate, destination=destination)
    except production.SbomClosureError as error:
        check(
            error.code in {"PF-SBOM-BIND", "PF-SBOM-CLOSURE"},
            f"binding substitution raised {error.code}",
        )
        return
    raise CaseFailure("tampered binding unexpectedly verified")


def case_sb2_025_input_race(base: Path) -> None:
    """Blocking FIFO input must fail within the timeout budget, zero output."""

    production = require_production()
    root = build_input_root(base)
    fifo = root / "toolchains.lock.json"
    fifo.unlink()
    os.mkfifo(fifo, 0o444)
    expect_error(
        production,
        root,
        base / "out-sb2-025",
        {"PF-SBOM-IO", "PF-SBOM-LIMIT", "PF-SBOM-CLOSURE"},
        "blocking FIFO input must fail closed",
        timeout=30.0,
    )


def case_sb2_028_no_clobber(base: Path) -> None:
    """Pre-existing destination is never clobbered; winner stays complete."""

    production = require_production()
    root = build_input_root(base)
    candidate = candidate_fixture(base)
    destination = base / "out-sb2-028"
    destination.mkdir()
    marker = destination / "supply-chain-closure.v1.json"
    marker.write_text("pre-existing", encoding="utf-8")
    try:
        production.generate_sidecars(root=root, candidate=candidate, destination=destination)
    except production.SbomClosureError as error:
        check(
            error.code == "PF-OUTPUT-ATOMICITY",
            f"no-clobber violation raised {error.code}",
        )
        check(
            marker.read_text(encoding="utf-8") == "pre-existing",
            "pre-existing destination was clobbered",
        )
        return
    raise CaseFailure("pre-existing destination unexpectedly overwritten")


def case_sb2_028_fault_injection(base: Path) -> None:
    """Per-point write/fsync/rename faults and signal stand-ins.

    Every pre-rename failure must report PF-OUTPUT-ATOMICITY with zero output
    and no staging residue; an fsync-parent failure must report failure (never
    success) while leaving a complete destination that verify-existing can
    still confirm.
    """

    production = require_production()
    root = build_input_root(base)
    candidate = candidate_fixture(base)
    pre_rename_points = ("write", "fsync-file", "chmod", "fsync-staging", "rename")
    for point in pre_rename_points:
        destination = base / f"out-sb2-028-fault-{point}"
        production._IO_FAULTS[point] = OSError(errno.EIO, f"injected {point} fault")
        try:
            try:
                production.generate_sidecars(
                    root=root, candidate=candidate, destination=destination
                )
            except production.SbomClosureError as error:
                check(
                    error.code == "PF-OUTPUT-ATOMICITY",
                    f"{point}: got {error.code}, expected PF-OUTPUT-ATOMICITY",
                )
            else:
                raise CaseFailure(f"{point}: generation unexpectedly succeeded")
            check(not destination.exists(), f"{point}: failure left a destination")
            residue = [
                item
                for item in destination.parent.iterdir()
                if item.name.startswith(destination.name + ".staging-")
            ]
            check(not residue, f"{point}: staging residue {residue}")
        finally:
            production._IO_FAULTS.pop(point, None)
    # signal stand-in: KeyboardInterrupt at the write point
    destination = base / "out-sb2-028-signal"
    production._IO_FAULTS["write"] = KeyboardInterrupt()
    try:
        try:
            production.generate_sidecars(root=root, candidate=candidate, destination=destination)
        except production.SbomClosureError as error:
            check(
                error.code == "PF-OUTPUT-ATOMICITY",
                f"signal: got {error.code}, expected PF-OUTPUT-ATOMICITY",
            )
        else:
            raise CaseFailure("signal: generation unexpectedly succeeded")
        check(not destination.exists(), "signal: failure left a destination")
    finally:
        production._IO_FAULTS.pop("write", None)
    # fsync-parent failure: failure reported, destination complete and verifiable
    destination = base / "out-sb2-028-parent-fsync"
    production._IO_FAULTS["fsync-parent"] = OSError(errno.EIO, "injected fsync-parent fault")
    try:
        try:
            production.generate_sidecars(root=root, candidate=candidate, destination=destination)
        except production.SbomClosureError as error:
            check(
                error.code == "PF-OUTPUT-ATOMICITY",
                f"fsync-parent: got {error.code}, expected PF-OUTPUT-ATOMICITY",
            )
        else:
            raise CaseFailure("fsync-parent: generation unexpectedly reported success")
    finally:
        production._IO_FAULTS.pop("fsync-parent", None)
    check(destination.exists(), "fsync-parent: destination should remain complete")
    production.verify_existing(root=root, candidate=candidate, destination=destination)


# --- GREEN phase-2 shared helpers -------------------------------------------------------


def _load_json_doc(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _locate_locked_jv(root: Path) -> Path | None:
    """Return a jv binary only when its bytes match the platform lock pin."""

    import platform

    machine = platform.machine() or "x86_64"
    tag = f"linux-{machine}" if sys.platform.startswith("linux") else "darwin-arm64"
    lock_path = root / ("toolchains.lock.json" if tag == "darwin-arm64" else f"toolchains-{tag}.lock.json")
    if not lock_path.is_file():
        return None
    lock = _load_json_doc(lock_path)
    tool = next((item for item in lock.get("tools", []) if item.get("id") == "jv"), None)
    if tool is None:
        return None
    expected = tool.get("executableSha256")
    candidates = []
    env_root = os.environ.get("PROOF_FORGE_TOOL_ROOT")
    if env_root:
        candidates.append(Path(env_root) / "jv")
    candidates.append(REPO_ROOT / "build" / "tool-root" / tag / "jv")
    candidates.append(
        Path.home() / ".cache" / "proof-forge-v2" / "tool-root" / tag / "jv"
    )
    for candidate in candidates:
        if not candidate.is_file():
            continue
        digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
        if digest == expected:
            return candidate
    return None


def _dump_json_doc(path: Path, value: object) -> None:
    path.write_text(
        json.dumps(value, indent=1, sort_keys=True) + "\n", encoding="utf-8"
    )


def _rewrite_sidecar(path: Path, data: bytes) -> None:
    path.chmod(0o644)
    path.write_bytes(data)
    path.chmod(0o444)


def _rewrite_sidecar_json(path: Path, value: object) -> None:
    _rewrite_sidecar(
        path, json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n"
    )


def expect_verify_error(
    production,
    root: Path,
    candidate: dict[str, object],
    destination: Path,
    codes: set[str],
    detail: str,
) -> None:
    try:
        production.verify_existing(root=root, candidate=candidate, destination=destination)
    except production.SbomClosureError as error:
        check(error.code in codes, f"{detail}: got {error.code}, expected {sorted(codes)}")
        return
    raise CaseFailure(f"{detail}: verification unexpectedly succeeded")


# --- SB2 cases (GREEN phase-2) ----------------------------------------------------------


def case_sb2_002_lock_whitespace_layout(base: Path) -> None:
    """Whitespace/key-layout-only lock change: typed digest stable, raw changes."""

    production = require_production()
    candidate = candidate_fixture(base)
    root_a = build_input_root(base, "sb2-002-root-a")
    out_a = base / "sb2-002-out-a"
    production.generate_sidecars(root=root_a, candidate=candidate, destination=out_a)
    root_b = build_input_root(base, "sb2-002-root-b")
    lock_path = root_b / "toolchains.lock.json"
    original = lock_path.read_bytes()
    _dump_json_doc(lock_path, _load_json_doc(lock_path))
    check(lock_path.read_bytes() != original, "layout mutation must change the lock bytes")
    out_b = base / "sb2-002-out-b"
    production.generate_sidecars(root=root_b, candidate=candidate, destination=out_b)
    closure_a = _load_json_doc(out_a / "supply-chain-closure.v1.json")
    closure_b = _load_json_doc(out_b / "supply-chain-closure.v1.json")
    lock_a = next(
        entry for entry in closure_a["toolLocks"] if entry["path"] == "toolchains.lock.json"
    )
    lock_b = next(
        entry for entry in closure_b["toolLocks"] if entry["path"] == "toolchains.lock.json"
    )
    check(
        lock_a["typedDigest"] == lock_b["typedDigest"],
        "ToolLockV2Digest must be invariant under whitespace/layout",
    )
    check(
        lock_a["rawSha256"] != lock_b["rawSha256"],
        "raw toolchainLockSha256 must track the exact lock bytes",
    )
    check(
        (out_a / "bom.cdx.json").read_bytes() == (out_b / "bom.cdx.json").read_bytes(),
        "BOM carries no raw lock digest and must stay byte-identical",
    )
    check(
        (out_a / "sbom-release-binding.v1.json").read_bytes()
        != (out_b / "sbom-release-binding.v1.json").read_bytes(),
        "release binding must track the raw lock digest",
    )


def case_sb2_004_raw_typed_digest_swap(base: Path) -> None:
    """Swapping raw/typed lock digests inside the binding must PF-SBOM-BIND."""

    production = require_production()
    root = build_input_root(base, "sb2-004-root")
    candidate = candidate_fixture(base)
    destination = base / "sb2-004-out"
    production.generate_sidecars(root=root, candidate=candidate, destination=destination)
    binding_path = destination / "sbom-release-binding.v1.json"
    binding = _load_json_doc(binding_path)
    entry = binding["toolLocks"][0]
    entry["rawSha256"], entry["typedDigest"] = entry["typedDigest"], entry["rawSha256"]
    _rewrite_sidecar_json(binding_path, binding)
    expect_verify_error(
        production, root, candidate, destination, {"PF-SBOM-BIND"},
        "raw/typed digest swap",
    )


def case_sb2_005_legacy_schema_rejected(base: Path) -> None:
    """Legacy inventory/null-root BOM/digest-map -> PF-SBOM-SCHEMA, no fallback."""

    production = require_production()
    root = build_input_root(base, "sb2-005-root")
    candidate = candidate_fixture(base)
    destination = base / "sb2-005-out"
    production.generate_sidecars(root=root, candidate=candidate, destination=destination)
    payloads = (
        (
            "supply-chain-closure.v1.json",
            {"schema": "proof-forge.license-inventory.v1", "components": []},
        ),
        (
            "bom.cdx.json",
            {
                "bomFormat": "CycloneDX",
                "specVersion": "1.6",
                "version": 1,
                "metadata": {
                    "component": {
                        "type": "application",
                        "name": "proof-forge-next",
                        "bom-ref": "urn:proofforge:component:id:proof-forge-next",
                    }
                },
                "components": [],
                "dependencies": [],
            },
        ),
        (
            "sbom-release-binding.v1.json",
            {
                "bomSha256": "sha256:" + "0" * 64,
                "inventorySha256": "sha256:" + "1" * 64,
                "policySha256": "sha256:" + "2" * 64,
            },
        ),
    )
    for name, payload in payloads:
        target = destination / name
        original = target.read_bytes()
        _rewrite_sidecar_json(target, payload)
        expect_verify_error(
            production, root, candidate, destination, {"PF-SBOM-SCHEMA"},
            f"legacy schema in {name}",
        )
        _rewrite_sidecar(target, original)
    production.verify_existing(root=root, candidate=candidate, destination=destination)


def case_sb2_006_json_attacks(base: Path) -> None:
    """Duplicate keys, unknown/missing fields, Bool-as-int, float/NaN, bad UTF-8."""

    production = require_production()
    lock_name = "toolchains.lock.json"

    def mutate_duplicate_key(root: Path) -> None:
        path = root / lock_name
        text = path.read_text(encoding="utf-8").rstrip()
        check(text.endswith("}"), "lock layout assumption failed")
        path.write_text(
            text[:-1] + ', "schema": "proof-forge.toolchains.v2"}\n', encoding="utf-8"
        )

    def mutate_unknown_field(root: Path) -> None:
        path = root / lock_name
        value = _load_json_doc(path)
        value["unexpectedField"] = 1
        _dump_json_doc(path, value)

    def mutate_missing_field(root: Path) -> None:
        path = root / lock_name
        value = _load_json_doc(path)
        del value["assets"]
        _dump_json_doc(path, value)

    def mutate_bool_as_int(root: Path) -> None:
        path = root / lock_name
        value = _load_json_doc(path)
        value["assets"][0]["size"] = True
        _dump_json_doc(path, value)

    def mutate_float(root: Path) -> None:
        path = root / lock_name
        value = _load_json_doc(path)
        value["assets"][0]["size"] = value["assets"][0]["size"] + 0.5
        _dump_json_doc(path, value)

    def mutate_nan(root: Path) -> None:
        path = root / lock_name
        text = path.read_text(encoding="utf-8")
        mutated = text.replace('"size": 49415553', '"size": NaN', 1)
        check(mutated != text, "NaN injection anchor missing")
        path.write_text(mutated, encoding="utf-8")

    def mutate_invalid_utf8(root: Path) -> None:
        path = root / lock_name
        data = bytearray(path.read_bytes())
        data[len(data) // 2] = 0xFF
        path.write_bytes(bytes(data))

    sub_cases = (
        ("duplicate-key", mutate_duplicate_key, {"PF-SBOM-JSON"}),
        ("unknown-field", mutate_unknown_field, {"PF-SBOM-SCHEMA", "PF-SBOM-JSON"}),
        ("missing-field", mutate_missing_field, {"PF-SBOM-SCHEMA", "PF-SBOM-JSON"}),
        ("bool-as-int", mutate_bool_as_int, {"PF-SBOM-SCHEMA", "PF-SBOM-JSON"}),
        ("float", mutate_float, {"PF-SBOM-SCHEMA", "PF-SBOM-JSON"}),
        ("nan", mutate_nan, {"PF-SBOM-JSON"}),
        ("invalid-utf8", mutate_invalid_utf8, {"PF-SBOM-JSON"}),
    )
    for name, mutate, codes in sub_cases:
        root = build_input_root(base, f"sb2-006-root-{name}")
        mutate(root)
        expect_error(
            production, root, base / f"sb2-006-out-{name}", codes, f"SB2-006 {name}"
        )


def case_sb2_010_tool_bundle_join_drift(base: Path) -> None:
    """Executable/runtime SHA drift or wrong bundle join -> PF-SBOM-CLOSURE."""

    production = require_production()
    lock_name = "toolchains.lock.json"

    def mutate_executable_sha(root: Path) -> None:
        path = root / lock_name
        value = _load_json_doc(path)
        value["tools"][0]["executableSha256"] = "0" * 64
        _dump_json_doc(path, value)

    def mutate_runtime_sha(root: Path) -> None:
        path = root / lock_name
        value = _load_json_doc(path)
        tool = next(tool for tool in value["tools"] if tool["runtimeFiles"])
        tool["runtimeFiles"][0]["sha256"] = "0" * 64
        _dump_json_doc(path, value)

    def mutate_bundle_join(root: Path) -> None:
        path = root / lock_name
        value = _load_json_doc(path)
        tool = value["tools"][0]
        other = next(
            bundle
            for bundle in value["bundleFiles"]
            if bundle["assetId"] != tool["assetId"]
        )
        tool["executable"] = other["path"]
        _dump_json_doc(path, value)

    sub_cases = (
        ("executable-sha", mutate_executable_sha),
        ("runtime-sha", mutate_runtime_sha),
        ("bundle-join", mutate_bundle_join),
    )
    for name, mutate in sub_cases:
        root = build_input_root(base, f"sb2-010-root-{name}")
        mutate(root)
        expect_error(
            production,
            root,
            base / f"sb2-010-out-{name}",
            {"PF-SBOM-CLOSURE"},
            f"SB2-010 {name}",
        )


def case_sb2_012_package_file_set_mutation(base: Path) -> None:
    """Package file-set member missing or extra -> PF-SBOM-CLOSURE."""

    production = require_production()

    def mutate_missing(root: Path) -> None:
        (root / "ProofForgeV2" / "Targets" / "Solana.lean").unlink()

    def mutate_extra(root: Path) -> None:
        (root / "ProofForgeV2" / "Ambient.lean").write_text(
            "-- ambient\n", encoding="utf-8"
        )

    for name, mutate in (("missing", mutate_missing), ("extra", mutate_extra)):
        root = build_input_root(base, f"sb2-012-root-{name}")
        mutate(root)
        expect_error(
            production,
            root,
            base / f"sb2-012-out-{name}",
            {"PF-SBOM-CLOSURE"},
            f"SB2-012 {name}",
        )


def case_sb2_013_same_count_substitution(base: Path) -> None:
    """Same-count file-set substitution or content drift -> PF-SBOM-CLOSURE."""

    production = require_production()

    def mutate_substitute(root: Path) -> None:
        target = root / "ProofForgeV2" / "Targets" / "Solana.lean"
        target.rename(root / "ProofForgeV2" / "Targets" / "SolanaRenamed.lean")

    def mutate_drift(root: Path) -> None:
        target = root / "ProofForgeV2" / "Targets" / "Solana.lean"
        with target.open("a", encoding="utf-8") as handle:
            handle.write("\n-- drift\n")

    for name, mutate in (("substitute", mutate_substitute), ("drift", mutate_drift)):
        root = build_input_root(base, f"sb2-013-root-{name}")
        mutate(root)
        expect_error(
            production,
            root,
            base / f"sb2-013-out-{name}",
            {"PF-SBOM-CLOSURE"},
            f"SB2-013 {name}",
        )


def case_sb2_014_inventory_graph_mutation(base: Path) -> None:
    """Duplicate/dangling/cyclic/self inventory dependencies -> PF-SBOM-INVENTORY."""

    production = require_production()
    inventory_name = "docs/supply-chain/license-inventory.v1.json"

    def mutate_duplicate(root: Path) -> None:
        path = root / inventory_name
        value = _load_json_doc(path)
        value["components"].append(dict(value["components"][0]))
        _dump_json_doc(path, value)

    def mutate_dangling(root: Path) -> None:
        path = root / inventory_name
        value = _load_json_doc(path)
        value["components"][0]["dependsOn"] = ["ghost-0.0.1"]
        _dump_json_doc(path, value)

    def mutate_cycle(root: Path) -> None:
        path = root / inventory_name
        value = _load_json_doc(path)
        by_id = {component["id"]: component for component in value["components"]}
        by_id["foundry-v0.3.0"]["dependsOn"] = ["jv-6.0.2"]
        by_id["jv-6.0.2"]["dependsOn"] = ["foundry-v0.3.0"]
        _dump_json_doc(path, value)

    def mutate_self(root: Path) -> None:
        path = root / inventory_name
        value = _load_json_doc(path)
        value["components"][0]["dependsOn"] = [value["components"][0]["id"]]
        _dump_json_doc(path, value)

    sub_cases = (
        ("duplicate", mutate_duplicate),
        ("dangling", mutate_dangling),
        ("cycle", mutate_cycle),
        ("self", mutate_self),
    )
    for name, mutate in sub_cases:
        root = build_input_root(base, f"sb2-014-root-{name}")
        mutate(root)
        expect_error(
            production,
            root,
            base / f"sb2-014-out-{name}",
            {"PF-SBOM-INVENTORY"},
            f"SB2-014 {name}",
        )


def case_sb2_015_license_file_attacks(base: Path) -> None:
    """License tamper/symlink/hardlink/placeholder -> PF-SBOM-LICENSE or PF-SBOM-IO."""

    production = require_production()

    def mutate_tamper(root: Path) -> None:
        target = root / "licenses" / "MIT.txt"
        with target.open("ab") as handle:
            handle.write(b"tampered\n")

    def mutate_symlink(root: Path) -> None:
        target = root / "licenses" / "GPL-3.0.txt"
        target.unlink()
        target.symlink_to("Apache-2.0.txt")

    def mutate_hardlink(root: Path) -> None:
        os.link(root / "licenses" / "MIT.txt", root / "licenses" / "MIT-alias.txt")

    def mutate_placeholder(root: Path) -> None:
        target = root / "licenses" / "MIT.txt"
        target.write_bytes(b"placeholder license text\n")
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        inventory_path = root / "docs/supply-chain/license-inventory.v1.json"
        value = _load_json_doc(inventory_path)
        for component in value["components"]:
            if component["licenseFile"] == "licenses/MIT.txt":
                component["licenseFileSha256"] = digest
        _dump_json_doc(inventory_path, value)

    sub_cases = (
        ("tamper", mutate_tamper, {"PF-SBOM-LICENSE"}),
        ("symlink", mutate_symlink, {"PF-SBOM-LICENSE", "PF-SBOM-IO"}),
        ("hardlink", mutate_hardlink, {"PF-SBOM-IO", "PF-SBOM-LICENSE"}),
        ("placeholder", mutate_placeholder, {"PF-SBOM-LICENSE"}),
    )
    for name, mutate, codes in sub_cases:
        root = build_input_root(base, f"sb2-015-root-{name}")
        mutate(root)
        expect_error(
            production, root, base / f"sb2-015-out-{name}", codes, f"SB2-015 {name}"
        )


def case_sb2_016_spdx_expression_attacks(base: Path) -> None:
    """Malformed/unknown/case/order/noncanonical SPDX expressions -> PF-SBOM-LICENSE."""

    production = require_production()
    inventory_name = "docs/supply-chain/license-inventory.v1.json"

    def expression_mutation(expression: str):
        def apply(root: Path) -> None:
            path = root / inventory_name
            value = _load_json_doc(path)
            value["components"][0]["licenseSpdx"] = expression
            _dump_json_doc(path, value)

        return apply

    sub_cases = (
        ("unknown", expression_mutation("NotARealLicense-1.0")),
        ("case", expression_mutation("mit")),
        ("order", expression_mutation("MIT OR Apache-2.0")),
        ("whitespace", expression_mutation("MIT  OR Apache-2.0")),
        ("malformed", expression_mutation("MIT OR")),
    )
    for name, mutate in sub_cases:
        root = build_input_root(base, f"sb2-016-root-{name}")
        mutate(root)
        expect_error(
            production,
            root,
            base / f"sb2-016-out-{name}",
            {"PF-SBOM-LICENSE"},
            f"SB2-016 {name}",
        )


def case_sb2_017_policy_attacks(base: Path) -> None:
    """Policy overlap/non-subset/unknown + review/deny expressions -> PF-SBOM-POLICY."""

    production = require_production()
    policy_name = "docs/supply-chain/license-policy.v1.json"
    inventory_name = "docs/supply-chain/license-inventory.v1.json"

    def mutate_overlap(root: Path) -> None:
        path = root / policy_name
        value = _load_json_doc(path)
        value["review"] = sorted(value["review"] + ["MIT"])
        _dump_json_doc(path, value)

    def mutate_external_subset(root: Path) -> None:
        path = root / policy_name
        value = _load_json_doc(path)
        value["externalCli"]["allowedDenyLicensesWhenNotRedistributable"] = ["MIT"]
        _dump_json_doc(path, value)

    def mutate_unknown_policy_expression(root: Path) -> None:
        path = root / policy_name
        value = _load_json_doc(path)
        value["allow"] = sorted(value["allow"] + ["NotAReal-9.9"])
        _dump_json_doc(path, value)

    def mutate_review_expression(root: Path) -> None:
        path = root / inventory_name
        value = _load_json_doc(path)
        by_id = {component["id"]: component for component in value["components"]}
        by_id["wabt-1.0.41"]["licenseSpdx"] = "MPL-2.0"
        _dump_json_doc(path, value)

    def mutate_deny_expression(root: Path) -> None:
        path = root / inventory_name
        value = _load_json_doc(path)
        by_id = {component["id"]: component for component in value["components"]}
        by_id["foundry-v0.3.0"]["licenseSpdx"] = "GPL-3.0-only"
        _dump_json_doc(path, value)

    sub_cases = (
        ("overlap", mutate_overlap),
        ("external-subset", mutate_external_subset),
        ("unknown-policy-expression", mutate_unknown_policy_expression),
        ("review-expression", mutate_review_expression),
        ("deny-expression", mutate_deny_expression),
    )
    for name, mutate in sub_cases:
        root = build_input_root(base, f"sb2-017-root-{name}")
        mutate(root)
        expect_error(
            production,
            root,
            base / f"sb2-017-out-{name}",
            {"PF-SBOM-POLICY"},
            f"SB2-017 {name}",
        )


def case_sb2_020_relationship_attacks(base: Path) -> None:
    """Self/cycle/missing/duplicate typed relationships -> PF-SBOM-CLOSURE."""

    production = require_production()
    manifest_name = "supply-chain/compiler-runtime-darwin-arm64.v1.json"

    def mutate_self(root: Path) -> None:
        path = root / manifest_name
        value = _load_json_doc(path)
        value["loadEdges"].append(
            {
                "owner": "lib/lean/libInit_shared.dylib",
                "needed": "lib/lean/libInit_shared.dylib",
                "resolved": "lib/lean/libInit_shared.dylib",
            }
        )
        _dump_json_doc(path, value)

    def mutate_cycle(root: Path) -> None:
        path = root / manifest_name
        value = _load_json_doc(path)
        value["loadEdges"].extend(
            [
                {
                    "owner": "lib/lean/libInit_shared.dylib",
                    "needed": "libleanshared.dylib",
                    "resolved": "lib/lean/libleanshared.dylib",
                },
                {
                    "owner": "lib/lean/libleanshared.dylib",
                    "needed": "libInit_shared.dylib",
                    "resolved": "lib/lean/libInit_shared.dylib",
                },
            ]
        )
        _dump_json_doc(path, value)

    def mutate_missing(root: Path) -> None:
        path = root / manifest_name
        value = _load_json_doc(path)
        value["loadEdges"] = [
            edge
            for edge in value["loadEdges"]
            if not (
                edge["owner"] == "bin/lake"
                and edge["resolved"] == "lib/lean/libLake_shared.dylib"
            )
        ]
        _dump_json_doc(path, value)

    def mutate_duplicate(root: Path) -> None:
        path = root / manifest_name
        value = _load_json_doc(path)
        edge = next(
            edge
            for edge in value["loadEdges"]
            if edge["owner"] == "bin/lake"
            and edge["resolved"] == "lib/lean/libLake_shared.dylib"
        )
        value["loadEdges"].append(dict(edge))
        _dump_json_doc(path, value)

    sub_cases = (
        ("self", mutate_self),
        ("cycle", mutate_cycle),
        ("missing", mutate_missing),
        ("duplicate", mutate_duplicate),
    )
    for name, mutate in sub_cases:
        root = build_input_root(base, f"sb2-020-root-{name}")
        mutate(root)
        expect_error(
            production,
            root,
            base / f"sb2-020-out-{name}",
            {"PF-SBOM-CLOSURE"},
            f"SB2-020 {name}",
        )


def case_sb2_021_sidecar_substitution(base: Path) -> None:
    """Closure component or BOM bom-ref substitution -> verify-existing PF-SBOM-BIND."""

    production = require_production()
    root = build_input_root(base, "sb2-021-root")
    candidate = candidate_fixture(base)
    destination = base / "sb2-021-out"
    production.generate_sidecars(root=root, candidate=candidate, destination=destination)

    closure_path = destination / "supply-chain-closure.v1.json"
    original = closure_path.read_bytes()
    closure = _load_json_doc(closure_path)
    closure["components"][0]["size"] = 1
    _rewrite_sidecar_json(closure_path, closure)
    expect_verify_error(
        production, root, candidate, destination, {"PF-SBOM-BIND"},
        "closure component substitution",
    )
    _rewrite_sidecar(closure_path, original)

    bom_path = destination / "bom.cdx.json"
    original = bom_path.read_bytes()
    bom = _load_json_doc(bom_path)
    bom["components"][0]["bom-ref"] = "urn:proofforge:component:" + "0" * 64
    _rewrite_sidecar_json(bom_path, bom)
    expect_verify_error(
        production, root, candidate, destination, {"PF-SBOM-BIND"},
        "BOM bom-ref substitution",
    )
    _rewrite_sidecar(bom_path, original)

    production.verify_existing(root=root, candidate=candidate, destination=destination)


def case_sb2_024_sidecar_dir_attacks(base: Path) -> None:
    """Extra/missing/symlink/FIFO sidecar members -> PF-SBOM-BIND or PF-SBOM-IO."""

    production = require_production()
    root = build_input_root(base, "sb2-024-root")
    candidate = candidate_fixture(base)
    destination = base / "sb2-024-out"
    production.generate_sidecars(root=root, candidate=candidate, destination=destination)
    bom_path = destination / "bom.cdx.json"
    bom_bytes = bom_path.read_bytes()

    extra = destination / "extra.json"
    extra.write_text("{}\n", encoding="utf-8")
    expect_verify_error(
        production, root, candidate, destination, {"PF-SBOM-BIND"}, "extra member"
    )
    extra.unlink()

    bom_path.chmod(0o644)
    bom_path.unlink()
    expect_verify_error(
        production, root, candidate, destination, {"PF-SBOM-BIND"}, "missing member"
    )

    bom_path.symlink_to("supply-chain-closure.v1.json")
    expect_verify_error(
        production, root, candidate, destination, {"PF-SBOM-IO"}, "symlink member"
    )
    bom_path.unlink()

    os.mkfifo(bom_path, 0o444)
    expect_verify_error(
        production, root, candidate, destination, {"PF-SBOM-IO"}, "FIFO member"
    )
    bom_path.unlink()

    bom_path.write_bytes(bom_bytes)
    bom_path.chmod(0o444)
    production.verify_existing(root=root, candidate=candidate, destination=destination)


def case_sb2_026_destination_parent_attacks(base: Path) -> None:
    """Destination parent symlink or group/world-writable -> PF-SBOM-IO."""

    production = require_production()
    root = build_input_root(base, "sb2-026-root")

    real_parent = base / "sb2-026-real"
    real_parent.mkdir()
    link_parent = base / "sb2-026-link"
    link_parent.symlink_to(real_parent, target_is_directory=True)
    candidate = candidate_fixture(base)
    expect_error(
        production,
        root,
        link_parent / "out",
        {"PF-SBOM-IO"},
        "destination parent symlink must fail closed",
        candidate=candidate,
    )
    check(
        not list(real_parent.iterdir()),
        "symlink-parent failure left output behind",
    )

    for mode, name in ((0o775, "group"), (0o777, "world")):
        parent = base / f"sb2-026-{mode:o}"
        parent.mkdir()
        parent.chmod(mode)
        expect_error(
            production,
            root,
            parent / "out",
            {"PF-SBOM-IO"},
            f"{name}-writable destination parent must fail closed",
            candidate=candidate,
        )


def case_sb2_027_regenerate_no_clobber(base: Path) -> None:
    """Second generation at one destination fails; the first output stays intact."""

    production = require_production()
    root = build_input_root(base, "sb2-027-root")
    candidate = candidate_fixture(base)
    destination = base / "sb2-027-out"
    production.generate_sidecars(root=root, candidate=candidate, destination=destination)
    snapshot = {
        item.name: (item.read_bytes(), stat.S_IMODE(item.stat().st_mode))
        for item in destination.iterdir()
    }
    try:
        production.generate_sidecars(
            root=root, candidate=candidate, destination=destination
        )
    except production.SbomClosureError as error:
        check(
            error.code == "PF-OUTPUT-ATOMICITY",
            f"re-generation raised {error.code}",
        )
    else:
        raise CaseFailure("re-generation unexpectedly succeeded")
    after = {
        item.name: (item.read_bytes(), stat.S_IMODE(item.stat().st_mode))
        for item in destination.iterdir()
    }
    check(after == snapshot, "first generation output was not preserved")


def case_sb2_029_environment_invariance(base: Path) -> None:
    """Different TZ/locale/umask/HOME/cwd must not change sidecar bytes or modes."""

    require_production()
    root = build_input_root(base, "sb2-029-root")
    candidate = candidate_fixture(base)
    candidate_path = write_candidate(root, candidate)
    home_a = base / "sb2-029-home-a"
    home_a.mkdir()
    home_b = base / "sb2-029-home-b"
    home_b.mkdir()
    environments = (
        ({"HOME": str(home_a), "TZ": "UTC", "LC_ALL": "C"}, 0o022, str(root)),
        ({"HOME": str(home_b), "TZ": "Pacific/Kiritimati", "LC_ALL": "C.UTF-8"}, 0o077, str(base)),
    )
    outputs = []
    for index, (extra_env, umask, cwd) in enumerate(environments):
        destination = base / f"sb2-029-out-{index}"
        result = subprocess.run(
            [
                "/usr/bin/python3", "-I", "-S", str(PRODUCTION_PATH),
                "--root", str(root), "generate",
                "--candidate", str(candidate_path),
                "--output-dir", str(destination),
            ],
            capture_output=True,
            text=True,
            timeout=120,
            env={"PATH": "/usr/bin:/bin", **extra_env},
            cwd=cwd,
            preexec_fn=lambda value=umask: os.umask(value),
        )
        check(result.returncode == 0, f"SB2-029 generation failed: {result.stderr}")
        outputs.append(destination)
    for name in FROZEN_SIDECAR_FILES:
        left = (outputs[0] / name).read_bytes()
        right = (outputs[1] / name).read_bytes()
        check(left == right, f"{name} differs across environments")
    for destination in outputs:
        for item in destination.iterdir():
            check(
                stat.S_IMODE(item.stat().st_mode) == 0o444,
                f"{item.name} mode drifted across environments",
            )


def case_sb2_030_schema_only_bom_rejected(base: Path) -> None:
    """A CycloneDX-shaped but unrecomputed BOM must be rejected (PF-SBOM-BIND).

    When the lock-pinned jv binary is materialized, the generated BOM is also
    validated live against the pinned CycloneDX schema; the consumer rejection
    of identity-tampered BOMs holds either way.
    """

    production = require_production()
    root = build_input_root(base, "sb2-030-root")
    candidate = candidate_fixture(base)
    destination = base / "sb2-030-out"
    production.generate_sidecars(root=root, candidate=candidate, destination=destination)
    bom_path = destination / "bom.cdx.json"
    bom = _load_json_doc(bom_path)
    check(
        bom.get("bomFormat") == "CycloneDX" and bom.get("specVersion") == "1.6",
        "BOM shape assumption failed",
    )
    jv = _locate_locked_jv(root)
    if jv is not None:
        result = subprocess.run(
            [str(jv), str(root / "supply-chain/standards/cyclonedx-bom-1.6.schema.json"), str(bom_path)],
            capture_output=True,
            text=True,
            timeout=120,
        )
        check(
            result.returncode == 0,
            f"locked jv rejected the generated BOM: {result.stdout}{result.stderr}",
        )
    bom["components"][0]["hashes"] = [{"alg": "SHA-256", "content": "0" * 64}]
    _rewrite_sidecar_json(bom_path, bom)
    expect_verify_error(
        production, root, candidate, destination, {"PF-SBOM-BIND"},
        "schema-only BOM must be rejected",
    )


def case_sb2_031_limits(base: Path) -> None:
    """Equal-limit passes, over-limit -> PF-SBOM-LIMIT, all zero-output."""

    production = require_production()

    def attempt(attribute: str, value: int, name: str) -> bool:
        root = build_input_root(base, f"sb2-031-root-{name}")
        destination = base / f"sb2-031-out-{name}"
        original = getattr(production, attribute)
        setattr(production, attribute, value)
        try:
            production.generate_sidecars(
                root=root, candidate=candidate_fixture(base), destination=destination
            )
        except production.SbomClosureError as error:
            check(
                error.code == "PF-SBOM-LIMIT",
                f"{name}: got {error.code}, expected PF-SBOM-LIMIT",
            )
            check(
                not destination.exists() or not any(destination.iterdir()),
                f"{name}: failure left output behind",
            )
            return False
        finally:
            setattr(production, attribute, original)
        return True

    def expect_pass(attribute: str, value: int, name: str) -> None:
        check(attempt(attribute, value, name), f"{name}: equal limit must pass")

    def expect_fail(attribute: str, value: int, name: str) -> None:
        check(not attempt(attribute, value, name), f"{name}: over limit must fail")

    expect_pass("MAX_COMPONENTS", FROZEN_COMPONENTS["total"], "components-equal")
    expect_fail("MAX_COMPONENTS", FROZEN_COMPONENTS["total"] - 1, "components-over")
    expect_pass("MAX_RELATIONSHIPS", FROZEN_RELATIONSHIPS["total"], "relationships-equal")
    expect_fail("MAX_RELATIONSHIPS", FROZEN_RELATIONSHIPS["total"] - 1, "relationships-over")
    # FROZEN_PACKAGE_FILE_SET remains the D0-08 acceptance-time denominator.
    # SB2-031 is a generic limit-boundary probe, so derive the current fixture
    # cardinality from the test-owned tree oracle, never production output/sidecars.
    package_file_set = len(oracle_package_file_set())
    expect_pass("MAX_FILE_SET", package_file_set, "file-set-equal")
    expect_fail("MAX_FILE_SET", package_file_set - 1, "file-set-over")

    probe_root = build_input_root(base, "sb2-031-root-probe")
    probe = base / "sb2-031-out-probe"
    production.generate_sidecars(
        root=probe_root, candidate=candidate_fixture(base), destination=probe
    )
    largest = max(item.stat().st_size for item in probe.iterdir())
    expect_pass("MAX_SIDECAR_BYTES", largest, "sidecar-equal")
    expect_fail("MAX_SIDECAR_BYTES", largest - 1, "sidecar-over")


def expect_error(
    production,
    root: Path,
    destination: Path,
    codes: set[str],
    detail: str,
    candidate: dict[str, object] | None = None,
    timeout: float = 60.0,
) -> None:
    try:
        production.generate_sidecars(
            root=root,
            candidate=candidate or candidate_fixture(destination.parent),
            destination=destination,
            timeout=timeout,
        )
    except production.SbomClosureError as error:
        check(error.code in codes, f"{detail}: got {error.code}, expected {codes}")
        check(
            not destination.exists() or not any(destination.iterdir()),
            f"{detail}: failure left output behind",
        )
        return
    raise CaseFailure(f"{detail}: generation unexpectedly succeeded")


def case_legacy_generator_cannot_go_green(base: Path) -> None:
    """The D0-05 legacy generator output must never satisfy this acceptance."""

    legacy_out = base / "legacy-out"
    result = subprocess.run(
        [
            "/usr/bin/python3",
            "-I",
            "-S",
            str(REPO_ROOT / "scripts/sbom_generate.py"),
            "--root",
            str(REPO_ROOT),
            "generate",
            "--output-dir",
            str(legacy_out),
        ],
        capture_output=True,
        text=True,
        timeout=120,
    )
    check(result.returncode == 0, f"legacy generator failed to run: {result.stderr}")
    names = (
        {item.name for item in legacy_out.iterdir()}
        if legacy_out.exists()
        else set()
    )
    check(
        "supply-chain-closure.v1.json" not in names,
        "legacy generator unexpectedly emitted the closure sidecar",
    )
    check(
        "sbom-release-binding.v1.json" not in names,
        "legacy generator unexpectedly emitted the release binding sidecar",
    )
    # The legacy BOM carries a null/synthetic root and no frozen counts: it is a
    # legacy negative by construction, never TST-SBOM-002 evidence.


CASES = (
    ("SB2-001", case_sb2_001_happy_path),
    ("SB2-002", case_sb2_002_lock_whitespace_layout),
    ("SB2-003", case_sb2_003_legacy_digest_domain_rejected),
    ("SB2-004", case_sb2_004_raw_typed_digest_swap),
    ("SB2-005", case_sb2_005_legacy_schema_rejected),
    ("SB2-006", case_sb2_006_json_attacks),
    ("SB2-007", case_sb2_007_same_bytes_distinct_components),
    ("SB2-008", case_sb2_008_libcrypto_join),
    ("SB2-009", case_sb2_009_leaf_mapping_mutation),
    ("SB2-010", case_sb2_010_tool_bundle_join_drift),
    ("SB2-011", case_sb2_011_runtime_manifest_mutation),
    ("SB2-012", case_sb2_012_package_file_set_mutation),
    ("SB2-013", case_sb2_013_same_count_substitution),
    ("SB2-014", case_sb2_014_inventory_graph_mutation),
    ("SB2-015", case_sb2_015_license_file_attacks),
    ("SB2-016", case_sb2_016_spdx_expression_attacks),
    ("SB2-017", case_sb2_017_policy_attacks),
    ("SB2-018", case_sb2_018_candidate_mismatch),
    ("SB2-019", case_sb2_019_synthetic_root),
    ("SB2-020", case_sb2_020_relationship_attacks),
    ("SB2-021", case_sb2_021_sidecar_substitution),
    ("SB2-022", case_sb2_022_standards_identity_mutation),
    ("SB2-023", case_sb2_023_binding_substitution),
    ("SB2-024", case_sb2_024_sidecar_dir_attacks),
    ("SB2-025", case_sb2_025_input_race),
    ("SB2-026", case_sb2_026_destination_parent_attacks),
    ("SB2-027", case_sb2_027_regenerate_no_clobber),
    ("SB2-028", case_sb2_028_no_clobber),
    ("SB2-028-FAULTS", case_sb2_028_fault_injection),
    ("SB2-029", case_sb2_029_environment_invariance),
    ("SB2-030", case_sb2_030_schema_only_bom_rejected),
    ("SB2-031", case_sb2_031_limits),
    ("LEGACY-NOT-GREEN", case_legacy_generator_cannot_go_green),
)


def main() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="pf-sbom-closure-test-") as temporary:
        base = Path(temporary)
        for name, case in CASES:
            try:
                case(base)
            except CaseFailure as error:
                failures.append(f"{name}: {error}")
            except Exception as error:  # noqa: BLE001 - report and continue
                failures.append(f"{name}: unexpected {type(error).__name__}: {error}")
    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1
    print("sbom-closure-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

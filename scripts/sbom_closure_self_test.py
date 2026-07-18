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
    files.extend(sorted((REPO_ROOT / "ProofForgeV2").rglob("*.lean")))
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


def candidate_fixture() -> dict[str, object]:
    """Checkout-external fixed candidate tuple (synthetic but well-formed)."""

    archive = b"proof-forge-candidate-archive-fixture\n"
    return {
        "commit": "0" * 40,
        "treeObjectId": "1" * 40,
        "archiveDigest": hashlib.sha256(archive).hexdigest(),
        "archiveSize": len(archive),
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
    candidate = candidate_fixture()
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
            tuple(entries) == FROZEN_SIDECAR_FILES,
            f"sidecar closure must be exactly {FROZEN_SIDECAR_FILES}, got {entries}",
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
        root=root, candidate=candidate_fixture(), destination=destination
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
        root=root, candidate=candidate_fixture(), destination=destination
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
    candidate = candidate_fixture()
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
    candidate = candidate_fixture()
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
    candidate = candidate_fixture()
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
    candidate = candidate_fixture()
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
            candidate=candidate or candidate_fixture(),
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
    ("SB2-003", case_sb2_003_legacy_digest_domain_rejected),
    ("SB2-007", case_sb2_007_same_bytes_distinct_components),
    ("SB2-008", case_sb2_008_libcrypto_join),
    ("SB2-009", case_sb2_009_leaf_mapping_mutation),
    ("SB2-011", case_sb2_011_runtime_manifest_mutation),
    ("SB2-018", case_sb2_018_candidate_mismatch),
    ("SB2-019", case_sb2_019_synthetic_root),
    ("SB2-022", case_sb2_022_standards_identity_mutation),
    ("SB2-023", case_sb2_023_binding_substitution),
    ("SB2-025", case_sb2_025_input_race),
    ("SB2-028", case_sb2_028_no_clobber),
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

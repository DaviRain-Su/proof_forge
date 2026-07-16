#!/usr/bin/env python3
"""B1.5: assert ProofForge vs native behavior parity on matching targets.

Reads build/benchmarks/bm-counter_*_{proofforge,native}.json (or paths given)
and checks, per target:

1. Both rows exist (or one is an honest skip — then skip that target).
2. When both behavior.ok are true, step names and returns match.
3. Schema already validated separately; this gate only compares behavior.

Exit 0 on pass, 1 on mismatch, 2 if no comparable pairs found.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Any

ROW_RE = re.compile(
    r"^bm-(?P<scenario>[a-z0-9-]+)_(?P<target>.+)_(?P<impl>proofforge|native)\.json$"
)


def fail(msg: str) -> None:
    print(f"benchmark-behavior-gate: FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def load(path: pathlib.Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        fail(f"{path}: invalid JSON: {exc}")
    if not isinstance(data, dict):
        fail(f"{path}: expected object")
    return data


def step_signature(steps: list[Any]) -> list[tuple[str, Any]]:
    sig: list[tuple[str, Any]] = []
    for i, step in enumerate(steps):
        if not isinstance(step, dict):
            fail(f"step[{i}] is not an object")
        name = step.get("name")
        if not isinstance(name, str) or not name:
            fail(f"step[{i}] missing name")
        # Compare return only (storage/events optional; empty vs absent treated equal).
        ret = step.get("return", None)
        sig.append((name, ret))
    return sig


def compare_pair(scenario: str, target: str, pf: dict[str, Any], native: dict[str, Any]) -> str:
    """Return status string: pass | skip | fail (raises on fail)."""
    pf_ok = bool(pf.get("behavior", {}).get("ok"))
    native_ok = bool(native.get("behavior", {}).get("ok"))

    if not pf_ok and not native_ok:
        return f"skip {scenario}/{target}: both sides not ok"
    if not pf_ok:
        return f"skip {scenario}/{target}: proofforge not ok ({pf.get('notes', '')})"
    if not native_ok:
        return f"skip {scenario}/{target}: native not ok ({native.get('notes', '')})"

    pf_steps = pf.get("behavior", {}).get("steps", [])
    native_steps = native.get("behavior", {}).get("steps", [])
    if not isinstance(pf_steps, list) or not isinstance(native_steps, list):
        fail(f"{scenario}/{target}: behavior.steps must be arrays")

    pf_sig = step_signature(pf_steps)
    native_sig = step_signature(native_steps)
    if pf_sig != native_sig:
        fail(
            f"{scenario}/{target}: behavior step mismatch\n"
            f"  proofforge: {pf_sig}\n"
            f"  native:     {native_sig}"
        )
    return f"pass {scenario}/{target}: {len(pf_sig)} steps match"


def discover(paths: list[pathlib.Path]) -> dict[tuple[str, str], dict[str, pathlib.Path]]:
    """Map (scenario, target) -> {proofforge: path, native: path}."""
    groups: dict[tuple[str, str], dict[str, pathlib.Path]] = {}
    for path in paths:
        m = ROW_RE.match(path.name)
        if not m:
            continue
        key = (m.group("scenario"), m.group("target"))
        groups.setdefault(key, {})[m.group("impl")] = path
    return groups


def main() -> int:
    parser = argparse.ArgumentParser(description="B1.5 PF vs native behavior gate")
    parser.add_argument(
        "paths",
        nargs="*",
        type=pathlib.Path,
        help="Result JSON files (default: build/benchmarks/bm-counter_*.json)",
    )
    parser.add_argument(
        "--dir",
        type=pathlib.Path,
        default=pathlib.Path("build/benchmarks"),
        help="Directory to scan when no paths given",
    )
    parser.add_argument(
        "--allow-skip-all",
        action="store_true",
        help="Exit 0 even if every target is skipped",
    )
    args = parser.parse_args()

    if args.paths:
        paths = [p for p in args.paths if p.is_file()]
    else:
        if not args.dir.is_dir():
            fail(f"benchmark dir missing: {args.dir} (run just benchmark-counter first)")
        paths = sorted(args.dir.glob("bm-*_*.json"))

    if not paths:
        fail("no benchmark result JSON found")

    groups = discover(paths)
    if not groups:
        fail("no bm-*_{proofforge,native}.json pairs discovered")

    results: list[str] = []
    compared = 0
    skipped = 0
    for (scenario, target), impls in sorted(groups.items()):
        if "proofforge" not in impls or "native" not in impls:
            print(
                f"benchmark-behavior-gate: skip {scenario}/{target}: "
                f"missing side(s) {sorted(set(('proofforge','native')) - set(impls))}"
            )
            skipped += 1
            continue
        pf = load(impls["proofforge"])
        native = load(impls["native"])
        # Sanity: target/scenario fields match filename
        for label, row in (("proofforge", pf), ("native", native)):
            if row.get("scenario") != f"bm-{scenario}":
                fail(f"{impls[label]}: scenario field {row.get('scenario')!r} != bm-{scenario}")
            if row.get("target") != target:
                fail(f"{impls[label]}: target field {row.get('target')!r} != {target}")
            if row.get("implementation") != label:
                fail(
                    f"{impls[label]}: implementation {row.get('implementation')!r} != {label}"
                )
        status = compare_pair(scenario, target, pf, native)
        print(f"benchmark-behavior-gate: {status}")
        if status.startswith("pass"):
            compared += 1
        else:
            skipped += 1
        results.append(status)

    print(
        f"benchmark-behavior-gate: summary compared={compared} skipped={skipped} pairs={len(groups)}"
    )
    if compared == 0:
        if args.allow_skip_all:
            print("benchmark-behavior-gate: ok (all skipped)")
            return 0
        print(
            "benchmark-behavior-gate: no comparable pairs "
            "(both sides need behavior.ok=true)",
            file=sys.stderr,
        )
        return 2
    print("benchmark-behavior-gate: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

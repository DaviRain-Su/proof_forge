#!/usr/bin/env python3
"""PERF-1 engineering harness: measure product `check` wall times on a ~1000-node ProgramV1.

NFR-007 / TST-PERF-001 formal receipt (exact PerformanceProfileV1 host, 30-sample
p95 gates, golden hash edit protocol) is **not** claimed here. This script:

  * generates a deterministic wide+deep S1-compatible program
  * optionally runs cold `proof-forge-next check` samples (new OS process each)
  * prints p50 / p95 (nearest-rank) / max and sample count
  * never claims incremental compilation

Usage:
  python3 scripts/perf_check_harness.py --write-fixture build/perf-check-v1
  lake env python3 scripts/perf_check_harness.py --run --samples 10 \\
      --cli .lake/build/bin/proof-forge-next
"""

from __future__ import annotations

import argparse
import json
import math
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path


HEADER = "import ProofForgeV2\n\nnamespace Examples\n\nopen ProofForgeV2.Language\n\n"


def generate_source(*, states: int, terms: int) -> str:
    """Deterministic program: many public UInt64 states + one view with summed params.

    Approximate Syntax node pressure scales with states + terms (engineering
    ~1000-node class; not formal SPEC-LANG-001 exact 1000-node fixture).
    """
    lines = [HEADER, "program PerfThousand where\n"]
    for i in range(states):
        lines.append(f"  state s{i} : UInt64\n")
    lines.append("  init(seed : UInt64) do\n")
    lines.append("    s0 := seed\n")
    # Entry: many checked adds of public params (no private) for S1 product path.
    params = ", ".join(f"p{i} : UInt64" for i in range(min(terms, 16)))
    lines.append(f"  entry run({params}) : UInt64 do\n")
    if terms <= 0:
        lines.append("    return s0\n")
    else:
        # Chain of adds using state and params (keep product-admitted shapes).
        expr_parts = ["s0"] + [f"p{i}" for i in range(min(terms, 16))]
        # Pad with repeated s0 to raise expression nodes without new params.
        while len(expr_parts) < terms:
            expr_parts.append("s0")
        lines.append("    return " + " + ".join(expr_parts[:terms]) + "\n")
    lines.append("  view get() : UInt64 do\n")
    lines.append("    return s0\n")
    lines.append("\nend Examples\n")
    return "".join(lines)


def nearest_rank_p95(samples_ms: list[float]) -> float:
    if not samples_ms:
        return float("inf")
    ordered = sorted(samples_ms)
    # Formal NFR uses nearest-rank index 29 of 30; for n samples use ceil(0.95*n)-1.
    idx = max(0, min(len(ordered) - 1, math.ceil(0.95 * len(ordered)) - 1))
    return ordered[idx]


def write_fixture(root: Path, states: int, terms: int) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    src = root / "Examples"
    src.mkdir(parents=True, exist_ok=True)
    text = generate_source(states=states, terms=terms)
    path = src / "PerfThousand.lean"
    path.write_text(text, encoding="utf-8")
    meta = {
        "schema": "proof-forge.perf-check-harness.v1",
        "states": states,
        "terms": terms,
        "notes": "engineering PERF-1; not formal TST-PERF-001 / PerformanceProfileV1 receipt",
        "source_relpath": "Examples/PerfThousand.lean",
        "module": "Examples.PerfThousand",
    }
    (root / "manifest.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    return path


def run_cold_samples(cli: Path, root: Path, samples: int, timeout_s: float) -> list[float]:
    """Cold samples: each is a new OS process (no session reuse).

    Fixture lives under `root/Examples/…` but product `--root` is the **package**
    root so Loader can resolve `ProofForgeV2` via the ambient lake env
    (`lake env python3 scripts/perf_check_harness.py --run`).
    """
    times: list[float] = []
    pkg = Path.cwd().resolve()
    # Prefer package-relative path when fixture is under the package tree.
    try:
        source_rel = (root.resolve() / "Examples" / "PerfThousand.lean").relative_to(pkg)
    except ValueError:
        source_rel = root.resolve() / "Examples" / "PerfThousand.lean"
    args_base = [
        str(cli.resolve()),
        "check",
        str(source_rel),
        "--module",
        "Examples.PerfThousand",
        "--root",
        str(pkg),
    ]
    for i in range(samples):
        t0 = time.perf_counter()
        try:
            proc = subprocess.run(
                args_base,
                cwd=str(pkg),
                capture_output=True,
                text=True,
                timeout=timeout_s,
            )
        except subprocess.TimeoutExpired:
            times.append(float("inf"))
            continue
        dt_ms = (time.perf_counter() - t0) * 1000.0
        if proc.returncode != 0:
            # Product path may fail closed on large shapes; still record time but flag.
            sys.stderr.write(
                f"sample {i}: exit={proc.returncode} stderr={proc.stderr[:400]!r}\n"
            )
            times.append(float("inf"))
        else:
            times.append(dt_ms)
    return times


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write-fixture", type=Path, default=None)
    ap.add_argument("--states", type=int, default=80, help="public UInt64 state count")
    ap.add_argument("--terms", type=int, default=32, help="add-expression term count")
    ap.add_argument("--run", action="store_true")
    ap.add_argument("--cli", type=Path, default=Path(".lake/build/bin/proof-forge-next"))
    ap.add_argument("--samples", type=int, default=10)
    ap.add_argument("--timeout", type=float, default=30.0)
    args = ap.parse_args()

    fixture_root = args.write_fixture or Path("build/perf-check-v1")
    write_fixture(fixture_root, args.states, args.terms)
    print(f"fixture written under {fixture_root}")

    if not args.run:
        return 0

    if not args.cli.is_file():
        print(f"CLI missing: {args.cli} (build proof_forge_next first)", file=sys.stderr)
        return 2

    samples = run_cold_samples(args.cli, fixture_root, args.samples, args.timeout)
    finite = [s for s in samples if math.isfinite(s)]
    report = {
        "schema": "proof-forge.perf-check-harness-report.v1",
        "samples_ms": samples,
        "finite_count": len(finite),
        "p50_ms": statistics.median(finite) if finite else None,
        "p95_ms": nearest_rank_p95(finite) if finite else None,
        "max_ms": max(finite) if finite else None,
        "nfr007_claim": False,
        "incremental_compilation_claim": False,
        "note": "Engineering PERF-1 sample only; formal PerformanceProfileV1 receipt not produced",
    }
    print(json.dumps(report, indent=2))
    out = fixture_root / "report.json"
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"report written {out}")
    return 0 if finite else 1


if __name__ == "__main__":
    raise SystemExit(main())

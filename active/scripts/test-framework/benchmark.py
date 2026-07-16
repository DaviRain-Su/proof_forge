#!/usr/bin/env python3

import argparse
import json
import pathlib
import statistics
from collections.abc import Sequence


def improvement_percent(serial_seconds: float, parallel_seconds: float) -> float:
    if serial_seconds <= 0:
        raise ValueError("serial seconds must be positive")
    return (serial_seconds - parallel_seconds) / serial_seconds * 100.0


def render_report(serial_seconds: float, runs: Sequence[dict]) -> str:
    if not runs:
        raise ValueError("at least one parallel run is required")
    parallel_seconds = statistics.mean(float(run["totalSeconds"]) for run in runs)
    improvement = improvement_percent(serial_seconds, parallel_seconds)
    accepted = improvement >= 35.0 and len(runs) >= 3
    lines = [
        "# Test Timing Baseline",
        "",
        f"Commit: `{runs[-1].get('commit', '')}`",
        "",
        "| Metric | Result |",
        "|---|---:|",
        f"| Serial warm-cache wall time | {serial_seconds:.2f}s |",
        f"| Parallel mean wall time | {parallel_seconds:.2f}s |",
        f"| Improvement | {improvement:.2f}% |",
        f"| Stable parallel runs | {len(runs)} |",
        f"| Default-cutover qualification | {'PASS' if accepted else 'PENDING'} |",
        "",
        "## Parallel Runs",
        "",
        "| Run | Jobs | Wall time |",
        "|---:|---:|---:|",
    ]
    for index, run in enumerate(runs, 1):
        lines.append(f"| {index} | {run['jobs']} | {float(run['totalSeconds']):.2f}s |")
    lines.extend(["", "## Lane Work", "", "| Lane | Latest cumulative work |", "|---|---:|"])
    for lane, seconds in sorted(runs[-1].get("lanes", {}).items()):
        lines.append(f"| `{lane}` | {float(seconds):.2f}s |")
    recipes = sorted(
        runs[-1].get("recipes", []), key=lambda recipe: float(recipe["seconds"]), reverse=True
    )[:10]
    lines.extend(["", "## Slowest Recipes", "", "| Recipe | Time |", "|---|---:|"])
    for recipe in recipes:
        lines.append(f"| `{recipe['name']}` | {float(recipe['seconds']):.2f}s |")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Render ProofForge test timing evidence")
    parser.add_argument("--serial-seconds", type=float, required=True)
    parser.add_argument("--commit", help="configuration commit represented by the runs")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("timings", nargs="+", type=pathlib.Path)
    args = parser.parse_args()
    runs = [json.loads(path.read_text(encoding="utf-8")) for path in args.timings]
    if args.commit:
        for run in runs:
            run["commit"] = args.commit
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render_report(args.serial_seconds, runs), encoding="utf-8")
    print(f"test-benchmark: wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

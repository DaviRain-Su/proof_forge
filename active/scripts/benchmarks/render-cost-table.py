#!/usr/bin/env python3
"""B1.6: render a markdown cost/artifact table from bm-counter result rows.

Does **not** invent a cross-chain score. Per-target native costs and artifact
sizes are listed side-by-side with ProofForge. Missing costs are shown as `—`.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from datetime import datetime, timezone
from typing import Any

ROW_RE = re.compile(
    r"^bm-(?P<scenario>[a-z0-9-]+)_(?P<target>.+)_(?P<impl>proofforge|native)\.json$"
)

TARGET_ORDER = ["evm", "solana-sbpf-asm", "wasm-near", "psy-dpn", "aleo-leo"]
COST_LABELS = {
    "evm_gas": "gas",
    "solana_cu": "CU",
    "wasmtime_fuel_delta": "fuelΔ",
    "wasmtime_fuel_cumulative": "fuelΣ",
    "near_gas": "near_gas",
}


def load(path: pathlib.Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def discover(directory: pathlib.Path) -> dict[tuple[str, str], dict[str, dict[str, Any]]]:
    groups: dict[tuple[str, str], dict[str, dict[str, Any]]] = {}
    for path in sorted(directory.glob("bm-*_*.json")):
        m = ROW_RE.match(path.name)
        if not m:
            continue
        key = (m.group("scenario"), m.group("target"))
        groups.setdefault(key, {})[m.group("impl")] = load(path)
    return groups


def fmt_costs(costs: dict[str, Any] | None) -> str:
    if not costs:
        return "—"
    parts: list[str] = []
    for key, value in costs.items():
        label = COST_LABELS.get(key, key)
        if isinstance(value, dict):
            step_bits = []
            for step, amount in value.items():
                step_bits.append(f"{step}={amount}")
            parts.append(f"{label}[{', '.join(step_bits)}]")
        else:
            parts.append(f"{label}={value}")
    return "; ".join(parts) if parts else "—"


def ratio(pf: int | float | None, native: int | float | None) -> str:
    if pf is None or native is None or native == 0:
        return "—"
    return f"{pf / native:.2f}×"


def render(groups: dict[tuple[str, str], dict[str, dict[str, Any]]], out: pathlib.Path) -> None:
    lines: list[str] = []
    lines.append("# Benchmark matrix (generated)")
    lines.append("")
    lines.append(f"Generated: `{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}`")
    lines.append("")
    lines.append("Source rows: `build/benchmarks/bm-*_*_{proofforge,native}.json`")
    lines.append("")
    lines.append("Rules:")
    lines.append("")
    lines.append("- No cross-chain score (gas ≠ CU ≠ fuel).")
    lines.append("- Behavior parity is gated separately (`just benchmark-behavior-gate`).")
    lines.append("- Empty costs mean the runner deferred that dimension (honest `—`).")
    lines.append("")

    # Group by scenario
    scenarios = sorted({s for (s, _) in groups})
    for scenario in scenarios:
        lines.append(f"## `bm-{scenario}`")
        lines.append("")
        lines.append(
            "| Target | PF ok | Native ok | PF artifact | Native artifact | PF/native size | PF costs | Native costs |"
        )
        lines.append(
            "|--------|------:|----------:|------------:|----------------:|---------------:|----------|--------------|"
        )

        targets = [t for t in TARGET_ORDER if (scenario, t) in groups]
        # any extra targets
        extras = sorted({t for (s, t) in groups if s == scenario and t not in targets})
        for target in targets + extras:
            impls = groups[(scenario, target)]
            pf = impls.get("proofforge")
            native = impls.get("native")
            pf_ok = "yes" if pf and pf.get("behavior", {}).get("ok") else "no"
            native_ok = "yes" if native and native.get("behavior", {}).get("ok") else "no"
            pf_bytes = pf.get("artifactBytes") if pf else None
            native_bytes = native.get("artifactBytes") if native else None
            pf_costs = fmt_costs(pf.get("costs") if pf else None)
            native_costs = fmt_costs(native.get("costs") if native else None)
            lines.append(
                f"| `{target}` | {pf_ok} | {native_ok} | "
                f"{pf_bytes if pf_bytes is not None else '—'} | "
                f"{native_bytes if native_bytes is not None else '—'} | "
                f"{ratio(pf_bytes, native_bytes)} | "
                f"{pf_costs} | {native_costs} |"
            )
        lines.append("")

        # Notes
        lines.append("<details><summary>Row notes</summary>")
        lines.append("")
        for target in targets + extras:
            impls = groups[(scenario, target)]
            for label in ("proofforge", "native"):
                row = impls.get(label)
                if not row:
                    continue
                note = (row.get("notes") or "").strip() or "(none)"
                lines.append(f"- **{target}/{label}**: {note}")
        lines.append("")
        lines.append("</details>")
        lines.append("")

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")
    print(f"wrote {out}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dir",
        type=pathlib.Path,
        default=pathlib.Path("build/benchmarks"),
    )
    parser.add_argument(
        "-o",
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("docs/generated/benchmark-counter.md"),
    )
    args = parser.parse_args()
    if not args.dir.is_dir():
        print(f"render-cost-table: missing {args.dir}", file=sys.stderr)
        return 1
    groups = discover(args.dir)
    if not groups:
        print(f"render-cost-table: no rows in {args.dir}", file=sys.stderr)
        return 1
    render(groups, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

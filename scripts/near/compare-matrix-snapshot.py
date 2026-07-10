#!/usr/bin/env python3
"""Regenerate testkit/compare/MATRIX.md from live sandbox-report.json files.

Usage (repo root):
  python3 scripts/near/compare-matrix-snapshot.py
"""

from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPORT_ROOT = ROOT / "build/testkit/compare/near"
OUT = ROOT / "testkit/compare/MATRIX.md"

KINDS = {
    "counter": "baseline",
    "value-vault": "state",
    "fungible-token": "NEP-141 body",
    "ownable": "access",
    "staking-vault": "deposit map",
    "role-gated-token": "nested roles",
    "fee-token": "FT+fee",
    "remote-call": "promise",
    "status-message": "map U64",
    "guestbook": "maps U64",
    "storage-deposit": "NEP-145-lite",
    "pausable": "mixin",
    "reentrancy-guard": "mixin",
    "ownable-pausable": "compose",
    "array-example": "pure",
    "ownable-hash": "hash owner",
    "host-env-probe": "host env",
    "auth-remote-call": "promise+debit",
    "access-control": "roles",
    "external-token-transfer": "NEP-141 client",
    "external-vault": "vault client",
    "pro-rata-vault": "share vault",
    "soulbound-token": "non-transferable",
    "ft-peer-client": "protocol FT client",
    "vesting-vault": "HostEnv vesting",
    "escrow-vault": "escrow state machine",
    "timelock-vault": "HostEnv timelock",
    "height-lock-vault": "HostEnv height lock",
}

REPORT_SCHEMA = "proof-forge.testkit.compare.near-sandbox.v1"
REQUIRED_COVERAGE_DIMENSIONS = (
    "callSequence",
    "successStatus",
    "arguments",
    "caller",
    "returnValues",
    "logs",
    "storage",
)


def load_rows(report_root: Path) -> list[dict[str, object]]:
    rows = []
    for d in sorted(report_root.iterdir()):
        p = d / "sandbox-report.json"
        if not p.is_file():
            continue
        r = json.loads(p.read_text())
        c = r.get("comparison") or {}
        w = c.get("wasmBytes") or {}
        cg = c.get("callGasBurnt") or {}
        st = c.get("storageUsageBytes") or {}
        wx = w.get("nearSdk_vs_proofForge_ratio")
        cx = cg.get("nearSdk_vs_proofForge_ratio")
        sx = st.get("nearSdk_vs_proofForge_ratio")
        schema_ok = r.get("schema") == REPORT_SCHEMA
        observed_match = c.get("observedSemanticMatch") is True
        semantic_match = c.get("semanticMatch") is True
        coverage = c.get("observationCoverage")
        eligibility_issues: list[str] = []
        if not schema_ok:
            eligibility_issues.append("schema")
        if not observed_match:
            eligibility_issues.append("observedSemanticMatch")
        if not semantic_match:
            eligibility_issues.append("semanticMatch")
        if isinstance(coverage, dict):
            coverage_complete = coverage.get("complete") is True
            raw_missing = coverage.get("missing")
            missing_is_empty = isinstance(raw_missing, list) and not raw_missing
            missing = [str(item) for item in raw_missing] if isinstance(raw_missing, list) else []
            raw_covered = coverage.get("covered")
            covered_is_valid = isinstance(raw_covered, list) and all(
                isinstance(item, str) for item in raw_covered
            )
            covered = set(raw_covered) if covered_is_valid else set()
            covered_complete = covered_is_valid and all(
                dimension in covered for dimension in REQUIRED_COVERAGE_DIMENSIONS
            )
            if not coverage_complete:
                eligibility_issues.append("coverageComplete")
            if not isinstance(raw_missing, list):
                eligibility_issues.append("missingDimensions")
            elif raw_missing:
                # Preserve concrete missing dimensions in the status table.
                pass
            if not covered_complete:
                eligibility_issues.append("coveredDimensions")
            coverage_consistent = coverage_complete and missing_is_empty and covered_complete
            if coverage_consistent:
                coverage_status = "complete"
            elif coverage_complete:
                coverage_status = "inconsistent"
            else:
                coverage_status = "incomplete"
        else:
            coverage_complete = False
            coverage_status = "missing (legacy schema)"
            missing_is_empty = False
            covered_complete = False
            missing = []
            eligibility_issues.append("observationCoverage")
        display_missing = list(dict.fromkeys(missing + eligibility_issues))
        rows.append(
            {
                "id": d.name,
                "contract": r.get("contract") or d.name,
                "pf": int(w.get("proofForge") or 0),
                "sdk": int(w.get("nearSdk") or 0),
                "wx": float(wx) if wx is not None else 0.0,
                "cx": float(cx) if cx is not None else None,
                "sx": float(sx) if sx is not None else None,
                "observed": c.get("observedSemanticMatch"),
                "coverage_complete": coverage_complete,
                "coverage_status": coverage_status,
                "missing": display_missing,
                "verified": (
                    schema_ok
                    and observed_match
                    and semantic_match
                    and coverage_complete
                    and missing_is_empty
                    and covered_complete
                ),
            }
        )
    return rows


def render_matrix(rows: list[dict[str, object]]) -> str:
    verified = sorted(
        (row for row in rows if row["verified"]),
        key=lambda row: float(row["wx"]),
        reverse=True,
    )
    wxs = [float(row["wx"]) for row in verified]
    cxs = [float(row["cx"]) for row in verified if row["cx"] is not None]

    lines: list[str] = []
    lines.append("# NEAR compare matrix — observation-aware snapshot\n\n")
    lines.append("**Generated by** `scripts/near/compare-matrix-snapshot.py`  \n")
    lines.append(f"**Live dual-deploy reports:** **{len(rows)}**  \n")
    lines.append(f"**Semantically verified reports:** **{len(verified)}**  \n")
    lines.append("**Ratio:** near-sdk ÷ ProofForge  \n")
    lines.append(
        "**Leaderboard eligibility:** exact v1 schema, "
        "`observedSemanticMatch=true`, `semanticMatch=true`, and complete, "
        "internally consistent coverage (`missing=[]`; `covered` contains every "
        "required dimension).\n\n"
    )
    lines.append("## Verified leaderboard (wasm×)\n\n")
    if verified:
        lines.append(
            "| Rank | Contract | PF wasm | sdk wasm | **wasm×** | call× | storage× | Kind |\n"
        )
        lines.append(
            "|-----:|----------|--------:|---------:|----------:|------:|---------:|------|\n"
        )
        for index, row in enumerate(verified, 1):
            call_ratio = f"{float(row['cx']):.2f}×" if row["cx"] is not None else "—"
            storage_ratio = (
                f"{float(row['sx']):.1f}×" if row["sx"] is not None else "—"
            )
            lines.append(
                f"| {index} | {row['contract']} | {row['pf']} | {row['sdk']} | "
                f"**~{float(row['wx']):.1f}×** | {call_ratio} | {storage_ratio} | "
                f"{KINDS.get(str(row['id']), '')} |\n"
            )
    else:
        lines.append(
            "No report currently has complete observation coverage. Performance "
            "ratios remain measurements, but are not ranked as semantic comparisons.\n"
        )

    if verified and cxs:
        lines.append("\n### Verified stats\n\n")
        lines.append("| Stat | wasm× | call× |\n|------|------:|------:|\n")
        lines.append(f"| min | {min(wxs):.1f}× | {min(cxs):.2f}× |\n")
        lines.append(
            f"| **median** | **{statistics.median(wxs):.1f}×** | "
            f"**{statistics.median(cxs):.2f}×** |\n"
        )
        lines.append(
            f"| mean | {statistics.mean(wxs):.1f}× | {statistics.mean(cxs):.2f}× |\n"
        )
        lines.append(f"| max | {max(wxs):.1f}× | {max(cxs):.2f}× |\n")

    lines.append("\n## Observation status\n\n")
    lines.append("| Contract | observed semantics | coverage | verified | missing |\n")
    lines.append("|----------|--------------------|----------|----------|---------|\n")
    for row in sorted(rows, key=lambda item: str(item["contract"])):
        observed = row["observed"]
        observed_status = "match" if observed is True else "mismatch" if observed is False else "unknown"
        missing = ", ".join(row["missing"]) or "—"
        verified_status = "yes" if row["verified"] else "no"
        lines.append(
            f"| {row['contract']} | {observed_status} | {row['coverage_status']} | "
            f"{verified_status} | {missing} |\n"
        )

    lines.append("\n### Interpretation\n\n")
    lines.append(
        "1. `observedSemanticMatch` compares only evidence recorded by the sandbox harness.\n"
    )
    lines.append(
        "2. A successful dual deploy or matching partial observations do not establish full semantics.\n"
    )
    lines.append(
        "3. Size, gas, and storage ratios enter the leaderboard only when the exact v1 "
        "schema and every semantic and coverage eligibility condition agree.\n"
    )
    lines.append(
        "\n```sh\njust near-compare-live-measure auth-remote-call\n"
        "just near-compare-matrix\njust near-compare-all-live\n```\n"
    )
    return "".join(lines)


def main() -> int:
    if not REPORT_ROOT.is_dir():
        print(f"missing reports dir: {REPORT_ROOT}", file=sys.stderr)
        return 1
    rows = load_rows(REPORT_ROOT)
    if not rows:
        print("no sandbox-report.json found", file=sys.stderr)
        return 1
    rendered = render_matrix(rows)
    OUT.write_text(rendered)
    verified_count = sum(1 for row in rows if row["verified"])
    print(f"wrote {OUT.relative_to(ROOT)} ({len(rows)} contracts)")
    print(f"semantically verified leaderboard entries: {verified_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

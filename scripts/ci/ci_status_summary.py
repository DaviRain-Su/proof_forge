#!/usr/bin/env python3
"""Summarize path-filtered CI lanes without treating blocked work as green."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


LANE_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
RESULTS = {"success", "failure", "cancelled", "skipped"}


def load_matrix(raw: str) -> dict[str, dict[str, Any]]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"matrix is not valid JSON: {exc.msg}") from exc
    if not isinstance(value, dict) or not value:
        raise ValueError("matrix must be a non-empty object")

    matrix: dict[str, dict[str, Any]] = {}
    for lane, entry in value.items():
        if not isinstance(lane, str) or LANE_RE.fullmatch(lane) is None:
            raise ValueError(f"invalid lane name: {lane!r}")
        if not isinstance(entry, dict) or set(entry) != {"selected", "result", "reason"}:
            raise ValueError(
                f"lane {lane!r} must contain exactly selected, result, and reason"
            )
        selected = entry["selected"]
        result = entry["result"]
        reason = entry["reason"]
        if not isinstance(selected, bool):
            raise ValueError(f"lane {lane!r} selected must be a boolean")
        if result not in RESULTS:
            raise ValueError(f"lane {lane!r} has invalid result: {result!r}")
        if not isinstance(reason, str) or not reason.strip():
            raise ValueError(f"lane {lane!r} reason must be a non-empty string")
        matrix[lane] = entry
    return matrix


def contract_status(selected: bool, result: str) -> str:
    if result == "failure":
        return "FAIL"
    if result == "success":
        return "PASS"
    if not selected and result == "skipped":
        return "SKIP"
    return "BLOCKED"


def markdown_cell(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def render(matrix: dict[str, dict[str, Any]]) -> tuple[str, str, bool]:
    lines = []
    rows = []
    failed = False
    for lane, entry in matrix.items():
        selected = entry["selected"]
        result = entry["result"]
        status = contract_status(selected, result)
        failed = failed or status in {"FAIL", "BLOCKED"}
        lines.append(f"{status:<7} {lane}: result={result}; reason={entry['reason']}")
        rows.append(
            "| "
            + " | ".join(
                markdown_cell(value)
                for value in (
                    lane,
                    "yes" if selected else "no",
                    result,
                    status,
                    entry["reason"],
                )
            )
            + " |"
        )

    verdict = "FAIL" if failed else "PASS"
    console = "\n".join(["CI required-lane status", *lines, f"ci-required: {verdict}"])
    summary = "\n".join(
        [
            "## CI required-lane status",
            "",
            "| Lane | Selected | GitHub result | Contract status | Selection reason |",
            "|---|---:|---|---|---|",
            *rows,
            "",
            f"**ci-required: {verdict}**",
            "",
            "`SKIP` is valid only for a path-excluded lane. A selected lane that did not "
            "run is `BLOCKED` and fails this gate.",
            "",
        ]
    )
    return console, summary, failed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", required=True, help="JSON lane-status matrix")
    parser.add_argument("--summary", type=Path, help="append Markdown to this file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        matrix = load_matrix(args.matrix)
    except ValueError as exc:
        print(f"ci-status-summary: invalid input: {exc}", file=sys.stderr)
        return 2

    console, summary, failed = render(matrix)
    print(console)
    if args.summary is not None:
        with args.summary.open("a", encoding="utf-8") as handle:
            handle.write(summary)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

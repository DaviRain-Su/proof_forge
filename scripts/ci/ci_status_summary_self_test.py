#!/usr/bin/env python3
"""Self-test the required-lane pass/fail/skip/blocked contract."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "ci" / "ci_status_summary.py"


def lane(selected: bool, result: str, reason: str = "self-test") -> dict[str, object]:
    return {"selected": selected, "result": result, "reason": reason}


def check(
    name: str,
    matrix: object,
    expected_code: int,
    expected_fragments: tuple[str, ...],
) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        summary = Path(tmp) / "summary.md"
        raw = matrix if isinstance(matrix, str) else json.dumps(matrix)
        completed = subprocess.run(
            [
                sys.executable,
                "-I",
                "-S",
                str(SCRIPT),
                "--matrix",
                raw,
                "--summary",
                str(summary),
            ],
            cwd=ROOT,
            check=False,
            text=True,
            capture_output=True,
        )
        combined = completed.stdout + completed.stderr
        if summary.exists():
            combined += summary.read_text(encoding="utf-8")
        if completed.returncode != expected_code:
            raise AssertionError(
                f"{name}: expected exit {expected_code}, got {completed.returncode}\n{combined}"
            )
        for fragment in expected_fragments:
            if fragment not in combined:
                raise AssertionError(f"{name}: missing {fragment!r}\n{combined}")
    print(f"ok {name}")


def main() -> int:
    check(
        "pass_and_clean_skip",
        {
            "docs": lane(True, "success", "always"),
            "lean-product": lane(False, "skipped", "path filter"),
        },
        0,
        ("PASS    docs", "SKIP    lean-product", "ci-required: PASS"),
    )
    check(
        "selected_skip_is_blocked",
        {"target-smoke": lane(True, "skipped")},
        1,
        ("BLOCKED target-smoke", "ci-required: FAIL"),
    )
    check(
        "cancelled_is_blocked",
        {"near-runtime": lane(True, "cancelled")},
        1,
        ("BLOCKED near-runtime",),
    )
    check(
        "failure_is_failure_even_when_unselected",
        {"solana-runtime": lane(False, "failure")},
        1,
        ("FAIL    solana-runtime",),
    )
    check(
        "invalid_input_fails_closed",
        {"docs": {"selected": "true", "result": "success", "reason": "always"}},
        2,
        ("selected must be a boolean",),
    )
    check(
        "malformed_json_fails_closed",
        "{not-json",
        2,
        ("matrix is not valid JSON",),
    )
    print("ci_status_summary_self_test: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

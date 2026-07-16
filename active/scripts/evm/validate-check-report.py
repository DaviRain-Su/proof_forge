#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from typing import Any


def fail(message: str) -> None:
    raise SystemExit(f"check-report-validate: {message}")


def expect(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def expect_object(value: Any, name: str) -> dict:
    expect(isinstance(value, dict), f"{name} must be an object")
    return value


def expect_string(value: Any, name: str) -> str:
    expect(isinstance(value, str) and value, f"{name} must be a non-empty string")
    return value


def expect_array(value: Any, name: str) -> list:
    expect(isinstance(value, list), f"{name} must be an array")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expect-target", required=True)
    parser.add_argument("--expect-status", default="ok")
    parser.add_argument("--expect-input")
    parser.add_argument("report")
    args = parser.parse_args()

    report = expect_object(json.loads(open(args.report, encoding="utf-8").read()), "report")
    expect(report.get("schemaVersion") == 1, "schemaVersion must be 1")
    expect(report.get("kind") == "proof-forge-check-report", "kind mismatch")
    expect(report.get("command") == "check", "command must be check")
    expect(expect_string(report.get("target"), "target") == args.expect_target, "target mismatch")
    expect(report.get("status") == args.expect_status, "status mismatch")
    if args.expect_input is not None:
        expect(report.get("input") == args.expect_input, "input mismatch")

    diagnostics = expect_array(report.get("diagnostics"), "diagnostics")
    for idx, item in enumerate(diagnostics):
        diag = expect_object(item, f"diagnostics[{idx}]")
        expect_string(diag.get("severity"), f"diagnostics[{idx}].severity")
        expect_string(diag.get("code"), f"diagnostics[{idx}].code")
        expect_string(diag.get("message"), f"diagnostics[{idx}].message")

    validation = expect_object(report.get("validation"), "validation")
    expect(isinstance(validation.get("status"), str), "validation.status must be a string")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

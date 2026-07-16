#!/usr/bin/env python3
"""Regression tests for compare-matrix semantic eligibility."""

from __future__ import annotations

import importlib.util
import copy
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("compare-matrix-snapshot.py")
SPEC = importlib.util.spec_from_file_location("compare_matrix_snapshot", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MATRIX = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MATRIX)


def valid_report(name: str) -> dict[str, object]:
    return {
        "schema": "proof-forge.testkit.compare.near-sandbox.v1",
        "contract": name,
        "comparison": {
            "semanticMatch": True,
            "observedSemanticMatch": True,
            "observationCoverage": {
                "complete": True,
                "covered": list(MATRIX.REQUIRED_COVERAGE_DIMENSIONS),
                "missing": [],
            },
            "wasmBytes": {
                "proofForge": 10,
                "nearSdk": 100,
                "nearSdk_vs_proofForge_ratio": 10.0,
            },
            "callGasBurnt": {"nearSdk_vs_proofForge_ratio": 1.1},
            "storageUsageBytes": {"nearSdk_vs_proofForge_ratio": 2.0},
        },
    }


def write_report(root: Path, name: str, report: dict[str, object]) -> None:
    report_dir = root / name
    report_dir.mkdir()
    (report_dir / "sandbox-report.json").write_text(json.dumps(report))


def comparison(report: dict[str, object]) -> dict[str, object]:
    value = report["comparison"]
    assert isinstance(value, dict)
    return value


def coverage(report: dict[str, object]) -> dict[str, object]:
    value = comparison(report)["observationCoverage"]
    assert isinstance(value, dict)
    return value


def legacy_report(name: str) -> dict[str, object]:
    return {
        "contract": name,
        "comparison": {
            "semanticMatch": True,
        "observedSemanticMatch": True,
            "wasmBytes": {
                "proofForge": 10,
                "nearSdk": 100,
                "nearSdk_vs_proofForge_ratio": 10.0,
            },
            "callGasBurnt": {"nearSdk_vs_proofForge_ratio": 1.1},
            "storageUsageBytes": {"nearSdk_vs_proofForge_ratio": 2.0},
        },
    }


class MatrixEligibilityTest(unittest.TestCase):
    def test_only_complete_semantic_reports_enter_leaderboard(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_report(root, "verified", valid_report("verified"))

            invalid: dict[str, dict[str, object]] = {}
            invalid["wrong-schema"] = copy.deepcopy(valid_report("wrong-schema"))
            invalid["wrong-schema"]["schema"] = "proof-forge.testkit.compare.near-sandbox.v0"
            invalid["observed-false"] = copy.deepcopy(valid_report("observed-false"))
            comparison(invalid["observed-false"])["observedSemanticMatch"] = False
            invalid["semantic-false"] = copy.deepcopy(valid_report("semantic-false"))
            comparison(invalid["semantic-false"])["semanticMatch"] = False
            invalid["complete-false"] = copy.deepcopy(valid_report("complete-false"))
            coverage(invalid["complete-false"])["complete"] = False
            invalid["missing-nonempty"] = copy.deepcopy(valid_report("missing-nonempty"))
            coverage(invalid["missing-nonempty"])["missing"] = ["caller"]
            invalid["covered-incomplete"] = copy.deepcopy(valid_report("covered-incomplete"))
            coverage(invalid["covered-incomplete"])["covered"] = ["logs"]
            invalid["covered-malformed"] = copy.deepcopy(valid_report("covered-malformed"))
            coverage(invalid["covered-malformed"])["covered"] = [{}]

            for name, report in invalid.items():
                write_report(root, name, report)
            write_report(root, "legacy", legacy_report("legacy"))

            rows = MATRIX.load_rows(root)
            output = MATRIX.render_matrix(rows)
            leaderboard = output.split("## Observation status", 1)[0]

            self.assertIn("| 1 | verified |", leaderboard)
            for name in invalid:
                self.assertNotIn(name, leaderboard)
            self.assertNotIn("legacy", leaderboard)
            self.assertIn("| missing-nonempty | match | inconsistent | no | caller |", output)
            self.assertIn("| covered-incomplete | match | inconsistent | no | coveredDimensions |", output)
            self.assertIn("| covered-malformed | match | inconsistent | no | coveredDimensions |", output)
            self.assertIn("| legacy | match | missing (legacy schema) | no | schema, observationCoverage |", output)


if __name__ == "__main__":
    unittest.main()

import pathlib
import sys
import unittest

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from benchmark import improvement_percent, render_report


class BenchmarkTest(unittest.TestCase):
    def test_improvement_percent(self) -> None:
        self.assertAlmostEqual(improvement_percent(100.0, 60.0), 40.0)

    def test_rejects_nonpositive_serial_time(self) -> None:
        with self.assertRaisesRegex(ValueError, "serial seconds must be positive"):
            improvement_percent(0.0, 10.0)

    def test_report_contains_acceptance_and_lane_data(self) -> None:
        run = {
                "commit": "abc123",
                "jobs": 4,
                "totalSeconds": 60.0,
                "lanes": {"evm": 55.0, "solana": 40.0},
                "recipes": [{"name": "slow", "seconds": 30.0}],
            }
        report = render_report(serial_seconds=100.0, runs=[run, run, run])
        self.assertIn("40.00%", report)
        self.assertIn("PASS", report)
        self.assertIn("`evm`", report)
        self.assertIn("`slow`", report)


if __name__ == "__main__":
    unittest.main()

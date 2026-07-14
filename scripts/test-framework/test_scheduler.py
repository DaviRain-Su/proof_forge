import json
import pathlib
import sys
import tempfile
import time
import unittest


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from scheduler import CommandSpec, detect_jobs, run_commands


class SchedulerTest(unittest.TestCase):
    def command(self, name: str, seconds: float, exit_code: int = 0,
                execution: str = "lane_serial") -> CommandSpec:
        code = f"import time; time.sleep({seconds}); raise SystemExit({exit_code})"
        return CommandSpec(name, name, execution, (sys.executable, "-c", code))

    def test_detect_jobs_caps_automatic_value_at_four(self) -> None:
        self.assertEqual(detect_jobs({}, None), 1)
        self.assertEqual(detect_jobs({}, 1), 1)
        self.assertEqual(detect_jobs({}, 8), 4)

    def test_detect_jobs_accepts_positive_override(self) -> None:
        self.assertEqual(detect_jobs({"JOBS": "7"}, 2), 7)

    def test_detect_jobs_rejects_invalid_override(self) -> None:
        for value in ("0", "-1", "many"):
            with self.subTest(value=value), self.assertRaisesRegex(
                ValueError, "JOBS must be a positive integer"
            ):
                detect_jobs({"JOBS": value}, 8)

    def test_runs_independent_commands_concurrently(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            started = time.monotonic()
            report = run_commands(
                [self.command("one", 0.35), self.command("two", 0.35)],
                jobs=2,
                run_dir=pathlib.Path(directory),
            )
            elapsed = time.monotonic() - started
        self.assertTrue(report.ok)
        self.assertLess(elapsed, 0.65)

    def test_exclusive_command_runs_alone(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            started = time.monotonic()
            report = run_commands(
                [
                    self.command("one", 0.3),
                    self.command("exclusive", 0.2, execution="exclusive"),
                ],
                jobs=2,
                run_dir=pathlib.Path(directory),
            )
            elapsed = time.monotonic() - started
        self.assertTrue(report.ok)
        self.assertGreater(elapsed, 0.45)

    def test_busy_lane_does_not_block_ready_other_lane(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            started = time.monotonic()
            report = run_commands(
                [
                    CommandSpec(
                        "one",
                        "lane-a",
                        "lane_serial",
                        self.command("one", 0.4).argv,
                    ),
                    CommandSpec(
                        "two",
                        "lane-a",
                        "lane_serial",
                        self.command("two", 0.05).argv,
                    ),
                    CommandSpec(
                        "three",
                        "lane-b",
                        "lane_serial",
                        self.command("three", 0.4).argv,
                    ),
                ],
                jobs=2,
                run_dir=pathlib.Path(directory),
            )
            elapsed = time.monotonic() - started
        self.assertTrue(report.ok)
        self.assertLess(elapsed, 0.7)

    def test_failure_cancels_remaining_processes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            started = time.monotonic()
            report = run_commands(
                [self.command("fail", 0.1, 9), self.command("slow", 5.0)],
                jobs=2,
                run_dir=pathlib.Path(directory),
            )
            elapsed = time.monotonic() - started
        self.assertFalse(report.ok)
        self.assertEqual(report.failed_command, "fail")
        self.assertLess(elapsed, 2.0)

    def test_writes_machine_readable_timing_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = pathlib.Path(directory)
            report = run_commands(
                [self.command("one", 0.01)], jobs=1, run_dir=run_dir
            )
            payload = json.loads((run_dir / "timings.json").read_text())
        self.assertTrue(report.ok)
        self.assertEqual(payload["jobs"], 1)
        self.assertEqual(payload["recipes"][0]["name"], "one")
        self.assertEqual(payload["recipes"][0]["status"], "passed")


if __name__ == "__main__":
    unittest.main()

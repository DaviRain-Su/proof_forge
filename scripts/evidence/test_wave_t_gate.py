#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
GATE = REPO_ROOT / "scripts" / "evidence" / "wave_t_gate.py"


class WaveTGateTest(unittest.TestCase):
    def make_repo(self, root: pathlib.Path) -> None:
        subprocess.run(["git", "init", "-q", root], check=True)
        subprocess.run(["git", "-C", root, "config", "user.email", "test@example.com"], check=True)
        subprocess.run(["git", "-C", root, "config", "user.name", "Wave T Test"], check=True)
        (root / "tracked.txt").write_text("tracked\n", encoding="utf-8")
        subprocess.run(["git", "-C", root, "add", "tracked.txt"], check=True)
        subprocess.run(["git", "-C", root, "commit", "-qm", "fixture"], check=True)

    def write_manifest(self, root: pathlib.Path, command: list[str]) -> pathlib.Path:
        manifest = {
            "schemaVersion": "proof-forge.wave-t-gates.v1",
            "requiredTaskIds": ["T-TEST"],
            "gates": [
                {
                    "taskId": "T-TEST",
                    "implementationCommit": "HEAD",
                    "oracle": {"id": "fixture-oracle", "version": "1"},
                    "command": command,
                }
            ],
            "artifacts": [
                {
                    "id": "fixture-artifact",
                    "path": "artifact.bin",
                    "adapter": {"id": "fixture-adapter", "version": "1"},
                }
            ],
        }
        path = root / "manifest.json"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        return path

    def run_gate(self, root: pathlib.Path, manifest: pathlib.Path) -> tuple[subprocess.CompletedProcess[str], pathlib.Path]:
        output = root / "evidence.json"
        result = subprocess.run(
            [
                sys.executable,
                str(GATE),
                "--manifest",
                str(manifest),
                "--output",
                str(output),
                "--repo-root",
                str(root),
            ],
            text=True,
            capture_output=True,
        )
        return result, output

    def test_records_successful_command_and_artifact_digests(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            (root / "artifact.bin").write_bytes(b"artifact")
            manifest = self.write_manifest(root, [sys.executable, "-c", "print('gate: ok')"])

            result, output = self.run_gate(root, manifest)

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["format"], "proof-forge.wave-t-evidence.v1")
            self.assertEqual(report["result"], "passed")
            self.assertEqual(report["gates"][0]["status"], "passed")
            self.assertRegex(report["gates"][0]["runResultSha256"], r"^[0-9a-f]{64}$")
            self.assertRegex(report["artifacts"][0]["sha256"], r"^[0-9a-f]{64}$")

    def test_rejects_unknown_implementation_commit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            (root / "artifact.bin").write_bytes(b"artifact")
            manifest = self.write_manifest(root, [sys.executable, "-c", "print('gate: ok')"])
            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["gates"][0]["implementationCommit"] = "does-not-exist"
            manifest.write_text(json.dumps(data), encoding="utf-8")

            result, _ = self.run_gate(root, manifest)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unknown implementation commit", result.stderr)

    def test_rejects_dirty_worktree_when_clean_evidence_is_required(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            (root / "artifact.bin").write_bytes(b"artifact")
            manifest = self.write_manifest(root, [sys.executable, "-c", "print('gate: ok')"])
            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["requireCleanWorktree"] = True
            manifest.write_text(json.dumps(data), encoding="utf-8")
            (root / "tracked.txt").write_text("dirty\n", encoding="utf-8")

            result, _ = self.run_gate(root, manifest)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("clean worktree", result.stderr)

    def test_rejects_untracked_files_when_clean_evidence_is_required(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            (root / "artifact.bin").write_bytes(b"artifact")
            manifest = self.write_manifest(root, [sys.executable, "-c", "print('gate: ok')"])
            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["requireCleanWorktree"] = True
            manifest.write_text(json.dumps(data), encoding="utf-8")
            subprocess.run(["git", "-C", root, "add", "artifact.bin", "manifest.json"], check=True)
            subprocess.run(["git", "-C", root, "commit", "-qm", "gate fixture"], check=True)
            (root / "untracked.txt").write_text("untracked\n", encoding="utf-8")

            result, _ = self.run_gate(root, manifest)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("clean worktree", result.stderr)

    def test_rejects_skip_marker_even_when_command_exits_zero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            (root / "artifact.bin").write_bytes(b"artifact")
            manifest = self.write_manifest(root, [sys.executable, "-c", "print('SKIP: tool unavailable')"])

            result, output = self.run_gate(root, manifest)

            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(output.is_file(), result.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["result"], "failed")
            self.assertEqual(report["gates"][0]["status"], "failed")
            self.assertIn("skip marker", report["gates"][0]["failure"])


if __name__ == "__main__":
    unittest.main()

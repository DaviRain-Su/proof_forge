#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
GATE = REPO_ROOT / "scripts" / "evidence" / "wave_t_gate.py"
PRODUCTION_MANIFEST = REPO_ROOT / "scripts" / "evidence" / "wave-t-gates.json"


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
                    "producedByOracleId": "fixture-oracle",
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
            manifest = self.write_manifest(
                root,
                [
                    sys.executable,
                    "-c",
                    "from pathlib import Path; Path('artifact.bin').write_bytes(b'artifact'); print('gate: ok')",
                ],
            )

            result, output = self.run_gate(root, manifest)

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["format"], "proof-forge.wave-t-evidence.v1")
            self.assertEqual(report["result"], "passed")
            self.assertEqual(report["gates"][0]["status"], "passed")
            self.assertRegex(report["gates"][0]["runResultSha256"], r"^[0-9a-f]{64}$")
            self.assertRegex(report["artifacts"][0]["sha256"], r"^[0-9a-f]{64}$")

    def test_preserves_multiline_tool_version_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            (root / "artifact.bin").write_bytes(b"artifact")
            manifest = self.write_manifest(
                root,
                [
                    sys.executable,
                    "-c",
                    "from pathlib import Path; Path('artifact.bin').write_bytes(b'artifact'); print('gate: ok')",
                ],
            )
            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["tools"] = [
                {
                    "id": "multiline-tool",
                    "command": [sys.executable, "-c", "print('tool heading\\nVersion: 1.2.3')"],
                }
            ]
            manifest.write_text(json.dumps(data), encoding="utf-8")

            result, output = self.run_gate(root, manifest)

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["tools"][0]["version"], "tool heading\nVersion: 1.2.3")

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

    def test_rejects_implementation_commit_outside_head_history(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            tree = subprocess.run(
                ["git", "-C", root, "rev-parse", "HEAD^{tree}"],
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            orphan = subprocess.run(
                ["git", "-C", root, "commit-tree", tree, "-m", "orphan"],
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            manifest = self.write_manifest(
                root,
                [
                    sys.executable,
                    "-c",
                    "from pathlib import Path; Path('artifact.bin').write_bytes(b'artifact')",
                ],
            )
            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["gates"][0]["implementationCommit"] = orphan
            manifest.write_text(json.dumps(data), encoding="utf-8")

            result, _ = self.run_gate(root, manifest)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("not an ancestor", result.stderr)

    def test_ci_fetches_history_and_runs_wave_t_gate(self) -> None:
        github = (REPO_ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
        woodpecker = (REPO_ROOT / ".woodpecker.yml").read_text(encoding="utf-8")
        justfile = (REPO_ROOT / "justfile").read_text(encoding="utf-8")

        build_test_checkout = github.split("  build-test:", 1)[1].split("      - name: Install just", 1)[0]
        self.assertIn("fetch-depth: 0", build_test_checkout)
        self.assertIn("just wave-t-gate", github)
        self.assertIn("just wave-t-gate", woodpecker)
        self.assertIn("partial: false", woodpecker)
        self.assertIn("depth: 0", woodpecker)
        github_mirror = justfile.split("github-build-test:", 1)[1].split("\n# Run the GitHub", 1)[0]
        self.assertIn("just wave-t-gate", github_mirror)
        self.assertIn("scripts/near/install-sandbox-ci.sh", github)
        woodpecker_setup = (REPO_ROOT / "scripts" / "ci" / "woodpecker-setup.sh").read_text(encoding="utf-8")
        self.assertIn("scripts/near/install-sandbox-ci.sh", woodpecker_setup)

    def test_near_sandbox_gates_pin_the_checked_binary_before_cargo(self) -> None:
        scripts = [
            "scripts/near/abi-client-sandbox-smoke.sh",
            "scripts/near/ft-security-sandbox-smoke.sh",
            "scripts/near/map-hash-alias-sandbox-smoke.sh",
        ]
        for relative in scripts:
            with self.subTest(script=relative):
                text = (REPO_ROOT / relative).read_text(encoding="utf-8")
                export_at = text.find("export NEAR_SANDBOX_BIN_PATH=")
                cargo_at = text.find("cargo run")
                self.assertGreaterEqual(export_at, 0)
                self.assertGreater(cargo_at, export_at)

    def test_solana_background_stop_escalates_when_term_is_ignored(self) -> None:
        helper = REPO_ROOT / "scripts" / "solana" / "stop-background-process.sh"
        process = subprocess.Popen(["bash", "-c", "trap '' TERM; while :; do sleep 1; done"])
        try:
            result = subprocess.run(
                ["bash", str(helper), str(process.pid)],
                text=True,
                capture_output=True,
                timeout=5,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            process.wait(timeout=2)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

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

    def test_rejects_skipped_parenthesized_marker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            manifest = self.write_manifest(
                root,
                [
                    sys.executable,
                    "-c",
                    "from pathlib import Path; Path('artifact.bin').write_bytes(b'artifact'); print('SKIPPED (not available)')",
                ],
            )

            result, output = self.run_gate(root, manifest)

            self.assertNotEqual(result.returncode, 0)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertIn("skip marker", report["gates"][0]["failure"])

    def test_rejects_embedded_skipped_marker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            manifest = self.write_manifest(
                root,
                [
                    sys.executable,
                    "-c",
                    "from pathlib import Path; Path('artifact.bin').write_bytes(b'artifact'); print('gate: skipped')",
                ],
            )

            result, output = self.run_gate(root, manifest)

            self.assertNotEqual(result.returncode, 0)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertIn("skip marker", report["gates"][0]["failure"])

    def test_rejects_stale_artifact_not_regenerated_by_gate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            (root / "artifact.bin").write_bytes(b"stale")
            manifest = self.write_manifest(root, [sys.executable, "-c", "print('gate: ok')"])

            result, output = self.run_gate(root, manifest)

            self.assertNotEqual(result.returncode, 0)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["artifacts"][0]["status"], "missing")

    def test_rejects_artifact_modified_after_producing_gate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_repo(root)
            manifest = self.write_manifest(
                root,
                [
                    sys.executable,
                    "-c",
                    "from pathlib import Path; Path('artifact.bin').write_bytes(b'original')",
                ],
            )
            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["requiredTaskIds"].append("T-LATE")
            data["gates"].append(
                {
                    "taskId": "T-LATE",
                    "implementationCommit": "HEAD",
                    "oracle": {"id": "late-mutator", "version": "1"},
                    "command": [
                        sys.executable,
                        "-c",
                        "from pathlib import Path; Path('artifact.bin').write_bytes(b'mutated')",
                    ],
                }
            )
            manifest.write_text(json.dumps(data), encoding="utf-8")

            result, output = self.run_gate(root, manifest)

            self.assertNotEqual(result.returncode, 0)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["result"], "failed")
            self.assertIn("changed after producing gate", report["artifactIntegrityFailure"])

    def test_production_manifest_rejects_deleted_required_entries(self) -> None:
        original = json.loads(PRODUCTION_MANIFEST.read_text(encoding="utf-8"))
        mutations = {
            "gate": lambda data: data["gates"].pop(),
            "tool": lambda data: data["tools"].pop(),
            "artifact": lambda data: data["artifacts"].pop(),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                path = pathlib.Path(tmp) / "manifest.json"
                data = json.loads(json.dumps(original))
                mutate(data)
                path.write_text(json.dumps(data), encoding="utf-8")
                result = subprocess.run(
                    [sys.executable, str(GATE), "--manifest", str(path), "--validate-manifest-only"],
                    text=True,
                    capture_output=True,
                    cwd=REPO_ROOT,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("production manifest", result.stderr)

    def test_normal_production_run_cannot_disable_strict_profile(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "manifest.json"
            data = json.loads(PRODUCTION_MANIFEST.read_text(encoding="utf-8"))
            data["profile"] = "not-production"
            data["requiredTaskIds"] = ["T-TEST"]
            data["gates"] = [
                {
                    "taskId": "T-TEST",
                    "implementationCommit": "HEAD",
                    "oracle": {"id": "fixture", "version": "1"},
                    "command": ["true"],
                }
            ]
            data["tools"] = []
            data["artifacts"] = []
            path.write_text(json.dumps(data), encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(GATE),
                    "--production",
                    "--manifest",
                    str(path),
                    "--output",
                    str(pathlib.Path(tmp) / "evidence.json"),
                    "--repo-root",
                    str(REPO_ROOT),
                ],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("production manifest", result.stderr)


if __name__ == "__main__":
    unittest.main()

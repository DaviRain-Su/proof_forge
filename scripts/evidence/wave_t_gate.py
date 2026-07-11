#!/usr/bin/env python3
"""Run the Wave-T safety gates and emit artifact-bound JSON evidence."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
from typing import Any


FORMAT = "proof-forge.wave-t-evidence.v1"
MANIFEST_SCHEMA = "proof-forge.wave-t-gates.v1"
SKIP_PATTERN = re.compile(
    r"(?im)^\s*(?:skip|skipped)\s*:|"
    r"\b(?:missing tool|tool unavailable|not installed|not on path|prerequisite[^\n]*missing)\b"
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(command: list[str], cwd: pathlib.Path) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def git_value(repo_root: pathlib.Path, *args: str) -> str:
    result = run(["git", *args], repo_root)
    if result.returncode != 0:
        raise ValueError(result.stdout.decode("utf-8", errors="replace").strip())
    return result.stdout.decode("utf-8", errors="replace").strip()


def checked_command(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or not value or not all(isinstance(item, str) and item for item in value):
        raise ValueError(f"{label} must be a non-empty array of strings")
    return value


def write_report(path: pathlib.Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--repo-root", type=pathlib.Path, default=pathlib.Path.cwd())
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    home = pathlib.Path.home()
    preferred_paths = [home / ".elan" / "bin", home / ".local" / "bin", home / ".foundry" / "bin"]
    os.environ["PATH"] = os.pathsep.join(str(path) for path in preferred_paths) + os.pathsep + os.environ["PATH"]
    manifest_bytes = args.manifest.read_bytes()
    manifest = json.loads(manifest_bytes)
    if manifest.get("schemaVersion") != MANIFEST_SCHEMA:
        raise ValueError(f"expected manifest schema {MANIFEST_SCHEMA}")

    required_task_ids = manifest.get("requiredTaskIds")
    if (
        not isinstance(required_task_ids, list)
        or not required_task_ids
        or not all(isinstance(task_id, str) and task_id for task_id in required_task_ids)
        or len(set(required_task_ids)) != len(required_task_ids)
    ):
        raise ValueError("requiredTaskIds must be a non-empty array of unique strings")
    gates = manifest.get("gates")
    if not isinstance(gates, list) or not gates:
        raise ValueError("gates must be a non-empty array")
    covered_task_ids = {gate.get("taskId") for gate in gates}
    missing_task_ids = [task_id for task_id in required_task_ids if task_id not in covered_task_ids]
    if missing_task_ids:
        raise ValueError(f"required Wave-T tasks have no gate: {', '.join(missing_task_ids)}")

    resolved_commits: list[str] = []
    for gate in gates:
        implementation_commit = gate.get("implementationCommit")
        if not isinstance(implementation_commit, str) or not implementation_commit:
            raise ValueError(f"gate {gate.get('taskId')} has no implementation commit")
        result = run(["git", "rev-parse", "--verify", f"{implementation_commit}^{{commit}}"], repo_root)
        if result.returncode != 0:
            raise ValueError(
                f"gate {gate.get('taskId')} references unknown implementation commit {implementation_commit}"
            )
        resolved_commits.append(result.stdout.decode("utf-8", errors="replace").strip())

    revision = git_value(repo_root, "rev-parse", "HEAD")
    dirty = bool(git_value(repo_root, "status", "--porcelain"))
    if manifest.get("requireCleanWorktree") is True and dirty:
        raise ValueError("Wave-T evidence requires a clean worktree")
    report: dict[str, Any] = {
        "format": FORMAT,
        "generatedAt": datetime.datetime.now(datetime.UTC).isoformat(),
        "source": {"revision": revision, "dirty": dirty},
        "manifestSha256": sha256_bytes(manifest_bytes),
        "result": "passed",
        "tools": [],
        "gates": [],
        "artifacts": [],
    }

    failed = False
    for tool in manifest.get("tools", []):
        command = checked_command(tool.get("command"), f"tool {tool.get('id', '<unknown>')}")
        result = run(command, repo_root)
        output = result.stdout.decode("utf-8", errors="replace").strip()
        status = "passed" if result.returncode == 0 and output and not SKIP_PATTERN.search(output) else "failed"
        report["tools"].append(
            {
                "id": tool.get("id"),
                "command": shlex.join(command),
                "status": status,
                "version": output.splitlines()[0] if output else "",
                "outputSha256": sha256_bytes(result.stdout),
            }
        )
        failed = failed or status == "failed"

    logs_dir = args.output.parent / "wave-t-logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    for index, gate in enumerate(gates):
        task_id = gate.get("taskId")
        command = checked_command(gate.get("command"), f"gate {task_id}")
        result = run(command, repo_root)
        output_text = result.stdout.decode("utf-8", errors="replace")
        log_path = logs_dir / f"{index + 1:02d}-{task_id}.log"
        log_path.write_bytes(result.stdout)
        failure = None
        if result.returncode != 0:
            failure = f"command exited {result.returncode}"
        elif SKIP_PATTERN.search(output_text):
            failure = "command output contains a skip marker or missing-tool marker"
        status = "failed" if failure else "passed"
        report["gates"].append(
            {
                "taskId": task_id,
                "implementationCommit": resolved_commits[index],
                "command": shlex.join(command),
                "oracle": gate.get("oracle"),
                "status": status,
                "exitCode": result.returncode,
                "runResultSha256": sha256_bytes(result.stdout),
                "log": str(log_path.relative_to(args.output.parent)),
                **({"failure": failure} if failure else {}),
            }
        )
        failed = failed or failure is not None

    for artifact in manifest.get("artifacts", []):
        artifact_path = repo_root / artifact.get("path", "")
        if not artifact_path.is_file():
            failed = True
            report["artifacts"].append(
                {
                    "id": artifact.get("id"),
                    "path": artifact.get("path"),
                    "adapter": artifact.get("adapter"),
                    "status": "missing",
                }
            )
            continue
        data = artifact_path.read_bytes()
        report["artifacts"].append(
            {
                "id": artifact.get("id"),
                "path": artifact.get("path"),
                "adapter": artifact.get("adapter"),
                "status": "present",
                "bytes": len(data),
                "sha256": sha256_bytes(data),
            }
        )

    if failed:
        report["result"] = "failed"
    write_report(args.output, report)
    print(f"wave-t-gate: {report['result']} ({len(report['gates'])} gates, {len(report['artifacts'])} artifacts)")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"wave-t-gate: {error}", file=sys.stderr)
        raise SystemExit(1)

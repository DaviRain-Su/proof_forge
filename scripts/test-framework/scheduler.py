#!/usr/bin/env python3

import argparse
import dataclasses
import datetime
import json
import os
import pathlib
import signal
import subprocess
import sys
import time
from collections.abc import Mapping, Sequence

from manifest import RecipeSpec, load_manifest
from select_tests import changed_paths, resolve_base, select_tags


@dataclasses.dataclass(frozen=True)
class CommandSpec:
    name: str
    lane: str
    execution: str
    argv: tuple[str, ...]


@dataclasses.dataclass(frozen=True)
class RecipeResult:
    name: str
    lane: str
    status: str
    seconds: float
    return_code: int


@dataclasses.dataclass(frozen=True)
class RunReport:
    ok: bool
    failed_command: str | None
    seconds: float
    results: tuple[RecipeResult, ...]


@dataclasses.dataclass
class _Running:
    spec: CommandSpec
    process: subprocess.Popen[bytes]
    log_file: object
    started: float


def detect_jobs(env: Mapping[str, str], cpu_count: int | None) -> int:
    override = env.get("JOBS")
    if override is not None:
        try:
            jobs = int(override)
        except ValueError as error:
            raise ValueError("JOBS must be a positive integer") from error
        if jobs <= 0:
            raise ValueError("JOBS must be a positive integer")
        return jobs
    return min(cpu_count or 1, 4)


def _terminate(running: _Running) -> None:
    if running.process.poll() is not None:
        return
    try:
        os.killpg(running.process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        running.process.wait(timeout=1.0)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(running.process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def _write_report(
    run_dir: pathlib.Path,
    jobs: int,
    started: float,
    results: Sequence[RecipeResult],
) -> None:
    lane_seconds: dict[str, float] = {}
    for result in results:
        lane_seconds[result.lane] = lane_seconds.get(result.lane, 0.0) + result.seconds
    payload = {
        "schemaVersion": 1,
        "commit": subprocess.run(
            ["git", "rev-parse", "HEAD"], capture_output=True, text=True
        ).stdout.strip(),
        "cpuCount": os.cpu_count(),
        "jobs": jobs,
        "totalSeconds": round(time.monotonic() - started, 3),
        "lanes": lane_seconds,
        "recipes": [
            {
                "name": result.name,
                "lane": result.lane,
                "status": result.status,
                "seconds": round(result.seconds, 3),
                "returnCode": result.return_code,
            }
            for result in results
        ],
    }
    (run_dir / "timings.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )


def run_commands(
    commands: Sequence[CommandSpec], jobs: int, run_dir: pathlib.Path
) -> RunReport:
    if jobs <= 0:
        raise ValueError("jobs must be positive")
    run_dir.mkdir(parents=True, exist_ok=True)
    pending = list(commands)
    active: list[_Running] = []
    results: list[RecipeResult] = []
    started = time.monotonic()
    failed_command: str | None = None

    try:
        while pending or active:
            launched = False
            while pending and len(active) < jobs:
                active_exclusive = any(item.spec.execution == "exclusive" for item in active)
                if active_exclusive:
                    break

                candidate_index: int | None = None
                for index, candidate in enumerate(pending):
                    if candidate.execution == "exclusive":
                        if index == 0 and not active:
                            candidate_index = index
                        break
                    lane_busy = any(
                        item.spec.lane == candidate.lane
                        and candidate.execution != "isolated"
                        for item in active
                    )
                    if not lane_busy:
                        candidate_index = index
                        break
                if candidate_index is None:
                    break
                candidate = pending.pop(candidate_index)
                log_path = run_dir / f"{candidate.lane}.log"
                log_file = log_path.open("ab")
                log_file.write(f"\n=== {candidate.name} ===\n".encode())
                log_file.flush()
                process = subprocess.Popen(
                    candidate.argv,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                active.append(
                    _Running(candidate, process, log_file, time.monotonic())
                )
                launched = True
                if candidate.execution == "exclusive":
                    break

            completed: list[_Running] = []
            for running in active:
                code = running.process.poll()
                if code is None:
                    continue
                seconds = time.monotonic() - running.started
                status = "passed" if code == 0 else "failed"
                results.append(
                    RecipeResult(
                        running.spec.name,
                        running.spec.lane,
                        status,
                        seconds,
                        code,
                    )
                )
                running.log_file.close()
                completed.append(running)
                if code != 0 and failed_command is None:
                    failed_command = running.spec.name
            for running in completed:
                active.remove(running)

            if failed_command is not None:
                for running in active:
                    _terminate(running)
                    seconds = time.monotonic() - running.started
                    results.append(
                        RecipeResult(
                            running.spec.name,
                            running.spec.lane,
                            "cancelled",
                            seconds,
                            running.process.returncode or -signal.SIGTERM,
                        )
                    )
                    running.log_file.close()
                active.clear()
                pending.clear()
                break
            if not launched and not completed:
                time.sleep(0.02)
    except BaseException:
        for running in active:
            _terminate(running)
            running.log_file.close()
        raise
    finally:
        _write_report(run_dir, jobs, started, results)

    return RunReport(
        failed_command is None,
        failed_command,
        time.monotonic() - started,
        tuple(results),
    )


def _commands(recipes: Sequence[RecipeSpec]) -> list[CommandSpec]:
    return [
        CommandSpec(recipe.name, recipe.lane, recipe.execution, ("just", recipe.name))
        for recipe in recipes
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run conflict-aware ProofForge tests")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--full", action="store_true")
    mode.add_argument("--lane")
    mode.add_argument("--fast", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--manifest",
        type=pathlib.Path,
        default=pathlib.Path(__file__).with_name("lanes.json"),
    )
    args = parser.parse_args()

    try:
        jobs = detect_jobs(os.environ, os.cpu_count())
        manifest = load_manifest(args.manifest)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"test-scheduler: {error}", file=sys.stderr)
        return 2
    recipes = list(manifest.recipes)
    if args.lane:
        if args.lane not in manifest.lanes:
            print(f"test-scheduler: unknown lane `{args.lane}`", file=sys.stderr)
            return 2
        recipes = [recipe for recipe in recipes if recipe.lane == args.lane]
    elif args.fast:
        try:
            paths = changed_paths(resolve_base())
        except subprocess.CalledProcessError as error:
            print(f"test-scheduler: git selection failed: {error}", file=sys.stderr)
            return 2
        tags = select_tags(paths)
        recipes = [recipe for recipe in recipes if tags.intersection(recipe.tags)]
        print(f"check-fast: tags={','.join(sorted(tags))} paths={len(paths)}")
    commands = _commands(recipes)
    if args.dry_run:
        print(f"jobs={jobs}")
        for command in commands:
            print(f"{command.lane}\t{command.execution}\t{command.name}")
        return 0

    run_id = datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ")
    run_dir = pathlib.Path("build/test-lanes") / run_id
    report = run_commands(commands, jobs, run_dir)
    slowest = sorted(report.results, key=lambda result: result.seconds, reverse=True)[:5]
    for result in slowest:
        print(f"{result.seconds:8.2f}s  {result.name}  (just {result.name})")
    if not report.ok:
        print(
            f"test-scheduler: failed at `{report.failed_command}`; logs: {run_dir}",
            file=sys.stderr,
        )
        return 1
    print(f"test-scheduler: ok ({report.seconds:.2f}s, logs: {run_dir})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

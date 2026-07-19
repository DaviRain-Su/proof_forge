#!/usr/bin/env python3
"""Genesis trust-upgrade replay runner (TASK-D0-07 slice S8).

GOV-GENESIS-001 §5 requires the eligible-host replay of every frozen
genesis TST; GOV-PRECUTOVER-001 §4.1 adds TST-HOST-002 and TST-SBOM-002.
This runner reads the committed manifest
(``docs/governance/genesis-replay.v1.json``), executes each leg as a
bounded subprocess with a private TMPDIR and umask 0022, records per-leg
exit status/log sha256/duration into a
``proof-forge.genesis-replay-report.v1`` JSON report, and fails the whole
run when any leg is red (overallStatus failed + nonzero exit).  Stage-0
legs are invoked in the authoritative ``env -i`` form directly.  The
report is development evidence for the D0-07 closure; it is not formal or
hermetic evidence.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Mapping, NoReturn, Optional, Sequence, Tuple


REPORT_SCHEMA = "proof-forge.genesis-replay-report.v1"
MANIFEST_SCHEMA = "proof-forge.genesis-replay-manifest.v1"
FROZEN_TST_IDS = (
    "TST-DOC-001",
    "TST-ISO-001",
    "TST-EVIDENCE-001",
    "TST-HOST-001",
    "TST-TOOL-001",
    "TST-SBOM-001",
    "TST-COMMON-001",
    "TST-HOST-002",
    "TST-SBOM-002",
)
TASK_OF_TST = {
    "TST-DOC-001": "TASK-D0-01",
    "TST-ISO-001": "TASK-D0-02",
    "TST-EVIDENCE-001": "TASK-D0-03",
    "TST-HOST-001": "TASK-D0-03",
    "TST-TOOL-001": "TASK-D0-03",
    "TST-SBOM-001": "TASK-D0-05",
    "TST-COMMON-001": "TASK-D0-06",
    "TST-HOST-002": "TASK-D0-09",
    "TST-SBOM-002": "TASK-D0-08",
}
MAX_LOG_BYTES = 16 * 1024 * 1024
DEFAULT_TIMEOUT_SECONDS = 1200.0


class GenesisReplayError(Exception):
    """Stable replay failure."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise GenesisReplayError(code, detail)


def _manifest(detail: str) -> NoReturn:
    _fail("PF-GENESIS-REPLAY-MANIFEST", detail)


def _stage0(detail: str) -> NoReturn:
    _fail("PF-GENESIS-REPLAY-STAGE0", detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-GENESIS-REPLAY-IO", detail)


def _failed(detail: str) -> NoReturn:
    _fail("PF-GENESIS-REPLAY-FAILED", detail)


def validate_manifest(manifest: object) -> dict:
    """Validate the closed replay-manifest wire."""
    if type(manifest) is not dict:
        _manifest("manifest must be a JSON object")
    if set(manifest) != {"schema", "version", "governance", "environment", "legs"}:
        _manifest("manifest must be a closed object")
    if manifest["schema"] != MANIFEST_SCHEMA:
        _manifest("manifest schema is not v1")
    if manifest["version"] != "1.0.0":
        _manifest("manifest version must be 1.0.0")
    if type(manifest["governance"]) is not dict or not manifest["governance"]:
        _manifest("governance must be a non-empty object")
    environment = manifest["environment"]
    if type(environment) is not dict or "umask" not in environment:
        _manifest("environment must carry the umask pin")
    legs = manifest["legs"]
    if type(legs) is not list or not legs:
        _manifest("legs must be a non-empty array")
    seen = set()
    for index, leg in enumerate(legs):
        where = f"legs[{index}]"
        if type(leg) is not dict or not {
            "tstId", "taskId", "closingGate", "commands", "mappingNotes"
        } <= set(leg):
            _manifest(f"{where} must carry tstId/taskId/closingGate/commands/mappingNotes")
        tst_id = leg["tstId"]
        if tst_id not in FROZEN_TST_IDS:
            _manifest(f"{where}.tstId is not a frozen genesis TST")
        if tst_id in seen:
            _manifest(f"duplicate leg for {tst_id}")
        seen.add(tst_id)
        if leg["taskId"] != TASK_OF_TST[tst_id]:
            _manifest(f"{where}.taskId does not own {tst_id}")
        commands = leg["commands"]
        if type(commands) is not list or not commands:
            _manifest(f"{where}.commands must be a non-empty array")
        for command_index, command in enumerate(commands):
            command_where = f"{where}.commands[{command_index}]"
            if type(command) is not list or not command:
                _manifest(f"{command_where} must be a non-empty argv")
            if any(type(part) is not str or not part or "\x00" in part
                   for part in command):
                _manifest(f"{command_where} entries must be non-empty NUL-free text")
            if not command[0].startswith("/") and command[0] not in ("just", "lake"):
                _manifest(f"{command_where}[0] must be absolute or a pinned launcher")
        if type(leg["mappingNotes"]) is not list or any(
            type(note) is not str for note in leg["mappingNotes"]
        ):
            _manifest(f"{where}.mappingNotes must be an array of text")
    return manifest


def load_manifest(path) -> dict:
    manifest_path = Path(path)
    if not manifest_path.is_file():
        _manifest("manifest file is missing")
    try:
        manifest = json.loads(manifest_path.read_bytes().decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        _manifest("manifest is not valid JSON")
    return validate_manifest(manifest)


def build_report(*, run_utc: str, host_profile_id: str, legs: list) -> dict:
    """Assemble the replay report with failure aggregation."""
    statuses = [
        command["status"] for leg in legs for command in leg["commands"]
    ]
    overall = "passed" if all(status == "passed" for status in statuses) else "failed"
    return {
        "schema": REPORT_SCHEMA,
        "runUtc": run_utc,
        "hostProfileId": host_profile_id,
        "legs": legs,
        "overallStatus": overall,
    }


def _authoritative_stage0(repo_root: str) -> Tuple[str, bytes]:
    argv = (
        "/usr/bin/env", "-i", "HOME=/var/empty", "PATH=/usr/bin:/bin",
        "LC_ALL=C", "TZ=UTC", "/bin/bash", "--noprofile", "--norc",
        "scripts/verify_host_stage0.sh", "--require-eligible",
    )
    try:
        result = subprocess.run(
            argv, cwd=repo_root, capture_output=True, timeout=360,
        )
    except (OSError, subprocess.TimeoutExpired):
        _stage0("authoritative Stage-0 invocation failed")
    if result.returncode != 0:
        _stage0("authoritative Stage-0 did not prove an eligible host")
    try:
        observation = json.loads(result.stdout.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        _stage0("host observation is not a bounded JSON document")
    if type(observation) is not dict or observation.get("eligibleForHermetic") is not True:
        _stage0("host observation does not prove an eligible host")
    return observation["hostProfileId"], result.stdout


def _run_command(command: Sequence[str], *, env: Mapping[str, str],
                 cwd: str, timeout_seconds: float,
                 log_path: Path) -> dict:
    started = time.monotonic()
    argv = list(command)
    if argv[0] in ("just", "lake"):
        # Launcher commands resolve through the invoking PATH (the restricted
        # child env deliberately does not carry the user's tool bins).
        resolved = shutil.which(argv[0])
        if resolved is None:
            return {
                "command": argv,
                "exitCode": 127,
                "logSha256": hashlib.sha256(b"launcher not found").hexdigest(),
                "durationMs": int((time.monotonic() - started) * 1000),
                "status": "failed",
            }
        argv[0] = resolved
    try:
        process = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=cwd,
            env=dict(env),
            close_fds=True,
            start_new_session=True,
        )
    except OSError as error:
        return {
            "command": argv,
            "exitCode": 127,
            "logSha256": hashlib.sha256(str(error).encode()).hexdigest(),
            "durationMs": int((time.monotonic() - started) * 1000),
            "status": "failed",
        }
    timed_out = False
    try:
        output, _ = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        output, _ = process.communicate()
    duration_ms = int((time.monotonic() - started) * 1000)
    if len(output) > MAX_LOG_BYTES:
        output = output[:MAX_LOG_BYTES]
    log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        log_path.unlink()
    except FileNotFoundError:
        pass
    log_path.write_bytes(output)
    os.chmod(log_path, 0o400)
    exit_code = process.returncode
    status = "passed" if exit_code == 0 and not timed_out else "failed"
    return {
        "command": list(command),
        "exitCode": exit_code if not timed_out else None,
        "logSha256": hashlib.sha256(output).hexdigest(),
        "durationMs": duration_ms,
        "status": "failed" if timed_out else status,
        **({"timedOut": True} if timed_out else {}),
    }


def run_replay(*, manifest_path: str, output_dir: str, repo_root: str) -> dict:
    """Execute every manifest leg and publish the replay report."""
    manifest = load_manifest(manifest_path)
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    home = output / "home"
    cache = output / "cache"
    # The evidence-core self-tests walk every output path component and reject
    # group/writable parents; /tmp (1777) and developer roots like ~/dev (775)
    # fail.  Child TMPDIR therefore lives on the user-cache chain (all
    # components 0755/0700).  The umask pin must land before any mkdir so the
    # intermediate components are not created group-writable.
    os.umask(0o022)
    tmpdir = Path(os.path.expanduser("~/.cache/proof-forge-genesis-replay/tmp"))
    for directory in (tmpdir.parent, tmpdir, home, cache):
        directory.mkdir(parents=True, exist_ok=True)
        os.chmod(directory, 0o700)
    host_profile_id, _ = _authoritative_stage0(repo_root)
    run_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    env = {
        "PATH": "/usr/bin:/bin",
        "LC_ALL": "C",
        "TZ": "UTC",
        "HOME": str(home),
        "XDG_CACHE_HOME": str(cache),
        "TMPDIR": str(tmpdir),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }
    legs = []
    for leg in manifest["legs"]:
        results = []
        for index, command in enumerate(leg["commands"]):
            timeout_seconds = float(leg.get("timeoutSeconds", DEFAULT_TIMEOUT_SECONDS))
            log_path = output / "logs" / f"{leg['tstId']}-{index}.log"
            results.append(
                _run_command(
                    command,
                    env=env,
                    cwd=repo_root,
                    timeout_seconds=timeout_seconds,
                    log_path=log_path,
                )
            )
        legs.append(
            {
                "tstId": leg["tstId"],
                "taskId": leg["taskId"],
                "commands": results,
                "mappingNotes": leg["mappingNotes"],
            }
        )
    report = build_report(
        run_utc=run_utc, host_profile_id=host_profile_id, legs=legs
    )
    report_path = output / f"report-{run_utc.replace(':', '').replace('-', '')}.json"
    try:
        report_path.unlink()
    except FileNotFoundError:
        pass
    report_path.write_bytes(
        json.dumps(report, indent=2, sort_keys=True).encode("utf-8") + b"\n"
    )
    os.chmod(report_path, 0o400)
    for leg in legs:
        leg_status = all(
            command["status"] == "passed" for command in leg["commands"]
        )
        marker = "ok" if leg_status else "FAIL"
        for command in leg["commands"]:
            print(
                f"leg: {marker} {leg['tstId']} "
                f"exit={command['exitCode']} "
                f"sha256:{command['logSha256'][:16]} "
                f"({command['durationMs']}ms)"
            )
    print(f"report: {report_path} overallStatus={report['overallStatus']}")
    if report["overallStatus"] != "passed":
        _failed("at least one genesis replay leg is red")
    return report


def main(argv: Optional[list] = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    options = {"--manifest": None, "--output": None, "--repo-root": None}
    index = 0
    while index < len(args):
        flag = args[index]
        if flag not in options or index + 1 >= len(args):
            print(
                "usage: genesis_replay.py --manifest <path> --output <dir> "
                "[--repo-root <path>]",
                file=sys.stderr,
            )
            return 2
        options[flag] = args[index + 1]
        index += 2
    if options["--manifest"] is None or options["--output"] is None:
        print(
            "usage: genesis_replay.py --manifest <path> --output <dir> "
            "[--repo-root <path>]",
            file=sys.stderr,
        )
        return 2
    repo_root = options["--repo-root"] or str(Path(__file__).resolve().parent.parent)
    try:
        run_replay(
            manifest_path=options["--manifest"],
            output_dir=options["--output"],
            repo_root=repo_root,
        )
        return 0
    except GenesisReplayError as error:
        print(f"{error.code}: {error.detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

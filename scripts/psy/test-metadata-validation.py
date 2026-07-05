#!/usr/bin/env python3
"""Unit tests for write-artifact-metadata.py validation rules.

Tests the metadata consistency rules:
1. Capability/contextOp consistency
2. Crosscall target dependency validation
3. Dedup sanity

Run: python3 scripts/psy/test-metadata-validation.py
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
WRITER = ROOT / "scripts" / "psy" / "write-artifact-metadata.py"


def make_stub_files(dir: Path) -> dict:
    """Create minimal stub artifact files for the writer."""
    file_names = ["source.psy", "pkg.psy", "circuit.json", "abi.json", "exec.log", "Dargo.toml"]
    contents = [b"// psy source", b"// package source", b"{}", b"{}", b"log", b"[package]"]
    for name, content in zip(file_names, contents):
        (dir / name).write_bytes(content)
    return {k: str(dir / k) for k in file_names}


def make_plan_meta(
    contextOps=None,
    crosscalls=None,
    events=None,
    capabilities=None,
    moduleName="TestProbe",
) -> str:
    """Create a plan-metadata JSON string."""
    return json.dumps({
        "targetId": "psy-dpn",
        "moduleName": moduleName,
        "entrypoints": [],
        "events": events or [],
        "contextOps": contextOps or [],
        "crosscalls": crosscalls or [],
        "capabilities": capabilities or [],
    })


def run_writer(
    tmpdir: Path,
    plan_meta: str,
    capabilities: list[str],
    dependencies: list[str] | None = None,
) -> tuple[int, str]:
    """Run write-artifact-metadata.py with the given plan metadata and capabilities."""
    paths = make_stub_files(tmpdir)
    plan_file = tmpdir / "plan-meta.json"
    plan_file.write_text(plan_meta)
    out_file = tmpdir / "artifact.json"
    dep_args = [arg for dep in (dependencies or []) for arg in ("--dependency", dep)]
    result = subprocess.run([
        sys.executable, str(WRITER),
        "--root", str(tmpdir),
        "--fixture", "TestProbe",
        "--source", paths["source.psy"],
        "--package-source", paths["pkg.psy"],
        "--circuit-json", paths["circuit.json"],
        "--abi-json", paths["abi.json"],
        "--execute-log", paths["exec.log"],
        "--dargo-manifest", paths["Dargo.toml"],
        "--out", str(out_file),
        "--dargo", "/bin/true",
        "--execute-result", "result_vm: [0]",
        "--plan-metadata", str(plan_file),
    ] + [arg for cap in capabilities for arg in ("--capability", cap)] + dep_args,
        capture_output=True, text=True,
    )
    return result.returncode, result.stderr


def test_pass_case() -> bool:
    """Valid metadata with all capabilities present should pass."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        meta = make_plan_meta(
            contextOps=[{"name": "userId"}, {"name": "contractId"}, {"name": "checkpointId"}],
            capabilities=["caller.sender", "account.explicit", "env.block"],
        )
        rc, stderr = run_writer(tmpdir, meta, ["caller.sender", "account.explicit", "env.block", "zk.circuit"])
        if rc != 0:
            print(f"FAIL: test_pass_case: expected 0, got {rc}: {stderr}")
            return False
        print("ok: test_pass_case")
        return True


def test_missing_context_op_capability() -> bool:
    """contextOp present but its required capability missing should fail."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        meta = make_plan_meta(
            contextOps=[{"name": "userId"}],
            capabilities=["caller.sender"],
        )
        # Pass only env.block, missing caller.sender
        rc, stderr = run_writer(tmpdir, meta, ["env.block", "zk.circuit"])
        if rc == 0:
            print("FAIL: test_missing_context_op_capability: expected non-zero")
            return False
        if "caller.sender" not in stderr:
            print(f"FAIL: test_missing_context_op_capability: error should mention caller.sender: {stderr}")
            return False
        print("ok: test_missing_context_op_capability")
        return True


def test_empty_crosscall_target() -> bool:
    """crosscall with empty targetContractId should fail."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        meta = make_plan_meta(
            crosscalls=[{"targetContractId": ""}],
        )
        rc, stderr = run_writer(tmpdir, meta, ["zk.circuit"])
        if rc == 0:
            print("FAIL: test_empty_crosscall_target: expected non-zero")
            return False
        if "targetContractId" not in stderr:
            print(f"FAIL: test_empty_crosscall_target: error should mention targetContractId: {stderr}")
            return False
        print("ok: test_empty_crosscall_target")
        return True


def test_missing_crosscall_dependency() -> bool:
    """crosscall target that is not declared and not this/self should fail."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        meta = make_plan_meta(
            crosscalls=[{"targetContractId": "remote"}],
        )
        rc, stderr = run_writer(tmpdir, meta, ["zk.circuit"])
        if rc == 0:
            print("FAIL: test_missing_crosscall_dependency: expected non-zero")
            return False
        if "remote" not in stderr:
            print(f"FAIL: test_missing_crosscall_dependency: error should mention remote: {stderr}")
            return False
        print("ok: test_missing_crosscall_dependency")
        return True


def test_crosscall_self_allowed() -> bool:
    """crosscall target 'self' should be allowed without a dependency."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        meta = make_plan_meta(
            crosscalls=[{"targetContractId": "self"}],
        )
        rc, stderr = run_writer(tmpdir, meta, ["zk.circuit"])
        if rc != 0:
            print(f"FAIL: test_crosscall_self_allowed: expected 0, got {rc}: {stderr}")
            return False
        print("ok: test_crosscall_self_allowed")
        return True


def test_crosscall_this_allowed() -> bool:
    """crosscall target 'this' should be allowed without a dependency."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        meta = make_plan_meta(
            crosscalls=[{"targetContractId": "this"}],
        )
        rc, stderr = run_writer(tmpdir, meta, ["zk.circuit"])
        if rc != 0:
            print(f"FAIL: test_crosscall_this_allowed: expected 0, got {rc}: {stderr}")
            return False
        print("ok: test_crosscall_this_allowed")
        return True


def test_crosscall_dependency_allowed() -> bool:
    """crosscall target declared as --dependency should be allowed."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        meta = make_plan_meta(
            crosscalls=[{"targetContractId": "remote"}],
        )
        rc, stderr = run_writer(tmpdir, meta, ["zk.circuit"], dependencies=["remote"])
        if rc != 0:
            print(f"FAIL: test_crosscall_dependency_allowed: expected 0, got {rc}: {stderr}")
            return False
        print("ok: test_crosscall_dependency_allowed")
        return True


def test_duplicate_context_ops() -> bool:
    """duplicate contextOps should fail."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        meta = make_plan_meta(
            contextOps=[{"name": "userId"}, {"name": "userId"}],
            capabilities=["caller.sender"],
        )
        rc, stderr = run_writer(tmpdir, meta, ["caller.sender", "zk.circuit"])
        if rc == 0:
            print("FAIL: test_duplicate_context_ops: expected non-zero")
            return False
        if "duplicate" not in stderr:
            print(f"FAIL: test_duplicate_context_ops: error should mention duplicate: {stderr}")
            return False
        print("ok: test_duplicate_context_ops")
        return True


def test_duplicate_events() -> bool:
    """duplicate events should fail."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        evt = {"name": "Foo", "fields": [{"name": "v", "type": "Felt"}]}
        meta = make_plan_meta(events=[evt, evt])
        rc, stderr = run_writer(tmpdir, meta, ["zk.circuit"])
        if rc == 0:
            print("FAIL: test_duplicate_events: expected non-zero")
            return False
        print("ok: test_duplicate_events")
        return True


def test_plan_caps_subset_of_smoke() -> bool:
    """smoke capabilities may be a superset of plan capabilities."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        meta = make_plan_meta(capabilities=["storage.scalar"])
        rc, stderr = run_writer(tmpdir, meta, ["storage.scalar", "zk.circuit"])
        if rc != 0:
            print(f"FAIL: test_plan_caps_subset_of_smoke: expected 0, got {rc}: {stderr}")
            return False
        print("ok: test_plan_caps_subset_of_smoke")
        return True


def test_plan_caps_not_subset() -> bool:
    """plan capability missing from smoke list should fail."""
    with tempfile.TemporaryDirectory() as d:
        tmpdir = Path(d)
        meta = make_plan_meta(capabilities=["storage.scalar", "caller.sender"])
        rc, stderr = run_writer(tmpdir, meta, ["storage.scalar"])
        if rc == 0:
            print("FAIL: test_plan_caps_not_subset: expected non-zero")
            return False
        if "caller.sender" not in stderr:
            print(f"FAIL: test_plan_caps_not_subset: error should mention caller.sender: {stderr}")
            return False
        print("ok: test_plan_caps_not_subset")
        return True


def main() -> int:
    tests = [
        test_pass_case,
        test_missing_context_op_capability,
        test_empty_crosscall_target,
        test_missing_crosscall_dependency,
        test_crosscall_self_allowed,
        test_crosscall_this_allowed,
        test_crosscall_dependency_allowed,
        test_duplicate_context_ops,
        test_duplicate_events,
        test_plan_caps_subset_of_smoke,
        test_plan_caps_not_subset,
    ]
    failures = 0
    for test in tests:
        if not test():
            failures += 1
    if failures == 0:
        print(f"\nmetadata-validation: {len(tests)} tests passed")
        return 0
    else:
        print(f"\nmetadata-validation: {failures}/{len(tests)} tests failed")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

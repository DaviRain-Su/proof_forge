#!/usr/bin/env python3
"""Acceptance tests for linux host profiles and per-platform lock dispatch.

TASK-D0-09 / TST-HOST-002: linux host profile generator/validator positive
and negative vectors (secureBoot/arch/mutability per eligibility predicate),
linux <-> darwin tool lock and host profile cross rejection, the v1 -> v2
migration error, missing-observation fail-closed behavior, and the standalone
``validate-host-profile`` closed loop. darwin fixtures are only exercised
statically here; darwin TST-HOST-001 semantics are unchanged.

The production module is intentionally loaded from its exact sibling pathname:
isolated Python does not add the script directory to ``sys.path``, and this
test must not make a repository-relative import path into an authority
selector.
"""

from __future__ import annotations

import contextlib
import copy
import importlib.util
import io
import json
import shutil
import sys
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Callable


MODULE_PATH = Path(__file__).with_name("toolchain_assets.py")
MODULE_NAME = "proof_forge_toolchain_assets"
ROOT = MODULE_PATH.resolve().parents[1]
HOST_LOCK_PATH = ROOT / "host-profiles.lock.json"
V1_RETIREMENT_TEXT = ("host profile lock v1 is retired; migrate to "
                      "proof-forge.host-profiles.v2 (ADR-0016)")


def load_producer() -> ModuleType:
    assert sys.flags.isolated, "host-profiles self-test requires isolated Python (-I)"
    assert sys.flags.no_site, "host-profiles self-test requires no-site Python (-S)"
    assert MODULE_PATH.is_file(), "missing scripts/toolchain_assets.py"
    spec = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
    assert spec is not None and spec.loader is not None, "producer import spec unavailable"
    module = importlib.util.module_from_spec(spec)
    sys.modules[MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


def rejection_text(module: ModuleType, thunk: Callable[[], object]) -> str:
    try:
        thunk()
    except module.AssetError as error:
        return str(error)
    raise AssertionError("expected an AssetError rejection")


def run_main(module: ModuleType, argv: list[str]) -> str:
    real_argv = sys.argv
    sys.argv = ["toolchain_assets.py", *argv]
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stdout(buffer):
            module.main()
    finally:
        sys.argv = real_argv
    return buffer.getvalue()


def registered_host_lock(module: ModuleType) -> dict:
    host_lock = module.load_json(HOST_LOCK_PATH)
    module.validate_host_lock(host_lock)
    return host_lock


def profile_index(module: ModuleType, host_lock: dict, kind: str) -> int:
    return next(
        index for index, profile in enumerate(host_lock["profiles"])
        if module.host_profile_kind(profile) == kind
    )


def test_registered_lock_accepted(module: ModuleType) -> None:
    host_lock = registered_host_lock(module)
    kinds = sorted(module.host_profile_kind(profile) for profile in host_lock["profiles"])
    assert kinds == ["darwin", "linux"], kinds


def test_static_eligibility_negatives(module: ModuleType) -> None:
    host_lock = registered_host_lock(module)
    linux_index = profile_index(module, host_lock, "linux")
    baseline = copy.deepcopy(host_lock)
    profile = baseline["profiles"][linux_index]
    profile["eligibleForHermetic"] = True
    profile["ineligibilityReason"] = None
    profile["platform"]["secureBoot"] = "enabled"
    module.validate_host_lock(baseline)
    for name, section, field, value in (
            ("secure boot disabled", "platform", "secureBoot", "disabled"),
            ("secure boot unavailable", "platform", "secureBoot", "unavailable"),
            ("foreign arch", "platform", "arch", "riscv64"),
            ("mutable distro tools", "distroTools", "toolsMutableByCurrentUser", True),
    ):
        candidate = copy.deepcopy(baseline)
        candidate["profiles"][linux_index][section][field] = value
        text = rejection_text(module, lambda c=candidate: module.validate_host_lock(c))
        assert "marked eligible" in text, (name, text)


def test_v1_migration_error(module: ModuleType) -> None:
    host_lock = registered_host_lock(module)
    retired = copy.deepcopy(host_lock)
    retired["schema"] = "proof-forge.host-profiles.v1"
    text = rejection_text(module, lambda: module.validate_host_lock(retired))
    assert text == V1_RETIREMENT_TEXT, text


def test_closed_field_sets(module: ModuleType) -> None:
    host_lock = registered_host_lock(module)
    linux_index = profile_index(module, host_lock, "linux")
    darwin_index = profile_index(module, host_lock, "darwin")
    mutations: list[tuple[str, dict]] = []
    unknown_linux_key = copy.deepcopy(host_lock)
    unknown_linux_key["profiles"][linux_index]["platform"]["unexpected"] = "x"
    mutations.append(("unknown linux platform key", unknown_linux_key))
    missing_linux_key = copy.deepcopy(host_lock)
    del missing_linux_key["profiles"][linux_index]["platform"]["secureBoot"]
    mutations.append(("missing linux platform key", missing_linux_key))
    unknown_darwin_key = copy.deepcopy(host_lock)
    unknown_darwin_key["profiles"][darwin_index]["platform"]["unexpected"] = "x"
    mutations.append(("unknown darwin platform key", unknown_darwin_key))
    missing_darwin_key = copy.deepcopy(host_lock)
    del missing_darwin_key["profiles"][darwin_index]["platform"]["sip"]
    mutations.append(("missing darwin platform key", missing_darwin_key))
    unknown_profile_key = copy.deepcopy(host_lock)
    unknown_profile_key["profiles"][linux_index]["unexpected"] = True
    mutations.append(("unknown linux profile key", unknown_profile_key))
    missing_profile_section = copy.deepcopy(host_lock)
    del missing_profile_section["profiles"][linux_index]["distroTools"]
    mutations.append(("missing linux distroTools", missing_profile_section))
    for name, candidate in mutations:
        text = rejection_text(module, lambda c=candidate: module.validate_host_lock(c))
        assert "unrecognized field set" in text or "fields" in text, (name, text)


def test_reason_shape_matches_eligibility(module: ModuleType) -> None:
    host_lock = registered_host_lock(module)
    linux_index = profile_index(module, host_lock, "linux")
    profile = host_lock["profiles"][linux_index]
    flipped_reason = copy.deepcopy(host_lock)
    if profile["eligibleForHermetic"]:
        # An eligible profile must keep a null reason; any stale reason rejects.
        flipped_reason["profiles"][linux_index]["ineligibilityReason"] = "stale reason"
    else:
        # An ineligible profile must carry a human reason; null rejects.
        flipped_reason["profiles"][linux_index]["ineligibilityReason"] = None
    text = rejection_text(module, lambda: module.validate_host_lock(flipped_reason))
    assert "ineligibilityReason" in text, text
    missing_reason = copy.deepcopy(host_lock)
    del missing_reason["profiles"][linux_index]["ineligibilityReason"]
    text = rejection_text(module, lambda: module.validate_host_lock(missing_reason))
    assert "ineligibilityReason" in text, text


def test_mutability_predicate(module: ModuleType) -> None:
    if module.host_platform_kind() != "linux":
        return
    real_observe_tool = module.observe_linux_system_tool
    with tempfile.TemporaryDirectory() as temp:
        mutable_copy = Path(temp) / "openssl-copy"
        baseline = module.observe_host_linux("host-profiles-self-test-baseline")
        shutil.copy2(baseline["digestBootstrap"]["path"], mutable_copy)

        def redirected_system_tool(tool_id: str) -> dict:
            record = real_observe_tool(tool_id)
            if tool_id == "bash":
                record = dict(record, resolvedPath=str(mutable_copy))
            return record

        module.observe_linux_system_tool = redirected_system_tool
        try:
            profile = module.observe_host_linux("host-profiles-self-test-mutable-tool")
        finally:
            module.observe_linux_system_tool = real_observe_tool
        assert not profile["eligibleForHermetic"]
        assert "system tool bash" in profile["ineligibilityReason"]
        assert str(mutable_copy) in profile["ineligibilityReason"]

        def redirected_bootstrap(tool_id: str) -> dict:
            record = real_observe_tool(tool_id)
            if tool_id == "openssl":
                record = dict(record, path=str(mutable_copy))
            return record

        module.observe_linux_system_tool = redirected_bootstrap
        try:
            profile = module.observe_host_linux("host-profiles-self-test-mutable-bootstrap")
        finally:
            module.observe_linux_system_tool = real_observe_tool
        assert not profile["eligibleForHermetic"]
        assert "digest bootstrap" in profile["ineligibilityReason"]
        assert str(mutable_copy) in profile["ineligibilityReason"]

        profile = module.observe_host_linux("host-profiles-self-test-verify-bootstrap")
        profile["digestBootstrap"]["path"] = str(mutable_copy)
        profile["eligibleForHermetic"] = True
        profile["ineligibilityReason"] = None
        with contextlib.redirect_stdout(io.StringIO()):
            text = rejection_text(
                module, lambda: module.verify_host_linux(profile, require_eligible=False))
        assert "digest bootstrap" in text and str(mutable_copy) in text, text

        profile = module.observe_host_linux("host-profiles-self-test-verify-tool")
        profile["eligibleForHermetic"] = True
        profile["ineligibilityReason"] = None
        bash_path = next(
            record["resolvedPath"] for record in profile["systemTools"]
            if record["id"] == "bash"
        )
        real_mutable = module.path_mutable_by_current_user

        def fake_mutable(path: Path, label: str) -> bool:
            if str(path) == bash_path:
                return True
            return real_mutable(path, label)

        module.path_mutable_by_current_user = fake_mutable
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                text = rejection_text(
                    module, lambda: module.verify_host_linux(profile, require_eligible=False))
        finally:
            module.path_mutable_by_current_user = real_mutable
        assert "system tool bash" in text and bash_path in text, text

        profile = module.observe_host_linux("host-profiles-self-test-verify-clean")
        profile["eligibleForHermetic"] = True
        profile["ineligibilityReason"] = None
        with contextlib.redirect_stdout(io.StringIO()):
            module.verify_host_linux(profile, require_eligible=True)


def test_lock_platform_dispatch(module: ModuleType) -> None:
    host_platform = module.host_platform_id()
    native_lock = ROOT / module.PLATFORM_LOCK_FILES[host_platform]
    output = run_main(module, ["--lock", str(native_lock), "validate"])
    assert "lock validation ok" in output, output
    foreign_platform = (
        "darwin-arm64" if host_platform != "darwin-arm64" else "linux-x86_64")
    foreign_lock = ROOT / module.PLATFORM_LOCK_FILES[foreign_platform]
    text = rejection_text(
        module, lambda: run_main(module, ["--lock", str(foreign_lock), "validate"]))
    expected = (f"tool lock platform {foreign_platform} does not match host platform "
                f"{host_platform}")
    assert text == expected, text
    real_probe = module.host_platform_id
    module.host_platform_id = lambda: foreign_platform
    try:
        text = rejection_text(
            module, lambda: run_main(module, ["--lock", str(native_lock), "validate"]))
    finally:
        module.host_platform_id = real_probe
    expected = (f"tool lock platform {host_platform} does not match host platform "
                f"{foreign_platform}")
    assert text == expected, text


def test_verify_host_cross_profile_rejected(module: ModuleType) -> None:
    host_lock = registered_host_lock(module)
    foreign_kind = "darwin" if module.host_platform_kind() == "linux" else "linux"
    foreign = host_lock["profiles"][profile_index(module, host_lock, foreign_kind)]
    text = rejection_text(
        module, lambda: run_main(module, ["verify-host", "--profile-id", foreign["id"]]))
    assert f"is a {foreign_kind} profile; this host is" in text, text


def test_duplicate_kind_rejected(module: ModuleType) -> None:
    host_lock = registered_host_lock(module)
    for index, profile in enumerate(host_lock["profiles"]):
        candidate = copy.deepcopy(host_lock)
        duplicate = copy.deepcopy(candidate["profiles"][index])
        duplicate["id"] = duplicate["id"] + "-other"
        candidate["profiles"].insert(index + 1, duplicate)
        text = rejection_text(module, lambda c=candidate: module.validate_host_lock(c))
        assert "at most one" in text, text


def test_missing_observations_fail_closed(module: ModuleType) -> None:
    if module.host_platform_kind() != "linux":
        return
    real_efivar = module.SECURE_BOOT_EFIVAR
    module.SECURE_BOOT_EFIVAR = Path("/definitely/missing/efivar")
    try:
        profile = module.observe_host_linux("host-profiles-self-test-no-efivar")
    finally:
        module.SECURE_BOOT_EFIVAR = real_efivar
    assert profile["platform"]["secureBoot"] == "unavailable"
    assert not profile["eligibleForHermetic"]
    assert "secure boot is unavailable" in profile["ineligibilityReason"]
    text = rejection_text(
        module, lambda: module.observe_linux_system_tool("definitely-missing-pf-tool"))
    assert "definitely-missing-pf-tool" in text and "missing" in text, text


def test_validate_host_profile_command(module: ModuleType) -> None:
    host_lock = registered_host_lock(module)
    linux_profile = host_lock["profiles"][profile_index(module, host_lock, "linux")]
    with tempfile.TemporaryDirectory() as temp:
        input_path = Path(temp) / "profile.json"
        input_path.write_text(json.dumps(linux_profile), encoding="utf-8")
        output = run_main(module, ["validate-host-profile", "--input", str(input_path)])
        summary = json.loads(output)
        assert summary["eligibleForHermetic"] is linux_profile["eligibleForHermetic"], summary
        assert summary["profileKind"] == "linux", summary
        assert summary["ineligibilityReason"] == linux_profile["ineligibilityReason"], summary

        if module.host_platform_kind() == "linux":
            observed = module.observe_host_linux("host-profiles-self-test-observed")
            input_path.write_text(json.dumps(observed), encoding="utf-8")
            output = run_main(
                module, ["validate-host-profile", "--input", str(input_path)])
            summary = json.loads(output)
            assert summary["eligibleForHermetic"] is observed["eligibleForHermetic"], summary
            assert summary["ineligibilityReason"] == observed["ineligibilityReason"], summary

        tampered_secure_boot = copy.deepcopy(linux_profile)
        tampered_secure_boot["platform"]["secureBoot"] = "yes"
        input_path.write_text(json.dumps(tampered_secure_boot), encoding="utf-8")
        text = rejection_text(
            module,
            lambda: run_main(module, ["validate-host-profile", "--input", str(input_path)]))
        assert "secureBoot" in text, text

        wrong_reason = copy.deepcopy(linux_profile)
        if linux_profile["eligibleForHermetic"]:
            wrong_reason["ineligibilityReason"] = "stale reason"
        else:
            wrong_reason["ineligibilityReason"] = None
        input_path.write_text(json.dumps(wrong_reason), encoding="utf-8")
        text = rejection_text(
            module,
            lambda: run_main(module, ["validate-host-profile", "--input", str(input_path)]))
        assert "ineligibilityReason" in text, text

        unknown_key = copy.deepcopy(linux_profile)
        unknown_key["unexpected"] = True
        input_path.write_text(json.dumps(unknown_key), encoding="utf-8")
        text = rejection_text(
            module,
            lambda: run_main(module, ["validate-host-profile", "--input", str(input_path)]))
        assert "unknown fields" in text, text

        inconsistent_eligible = copy.deepcopy(linux_profile)
        inconsistent_eligible["eligibleForHermetic"] = True
        inconsistent_eligible["ineligibilityReason"] = None
        inconsistent_eligible["platform"]["secureBoot"] = "disabled"
        input_path.write_text(json.dumps(inconsistent_eligible), encoding="utf-8")
        text = rejection_text(
            module,
            lambda: run_main(module, ["validate-host-profile", "--input", str(input_path)]))
        assert "marked eligible" in text, text


def test_cross_lock_roots_rejected(module: ModuleType) -> None:
    host_lock = registered_host_lock(module)
    darwin_lock = module.validate_tool_lock(module.load_json(ROOT / "toolchains.lock.json"))
    linux_lock = module.validate_tool_lock(
        module.load_json(ROOT / "toolchains-linux-x86_64.lock.json"))
    darwin_index = profile_index(module, host_lock, "darwin")
    linux_index = profile_index(module, host_lock, "linux")
    linux_only = {
        "schema": "proof-forge.host-profiles.v2",
        "profiles": [copy.deepcopy(host_lock["profiles"][linux_index])],
    }
    module.validate_host_lock(linux_only)
    text = rejection_text(module, lambda: module.validate_lock_pair(darwin_lock, linux_only))
    assert "exactly one darwin profile" in text, text
    darwin_with_linux_roots = copy.deepcopy(host_lock)
    darwin_with_linux_roots["profiles"][darwin_index][
        "systemRuntime"]["allowedLoadRoots"] = ["/lib/", "/lib64/", "/usr/lib/"]
    module.validate_host_lock(darwin_with_linux_roots)
    text = rejection_text(
        module, lambda: module.validate_lock_pair(darwin_lock, darwin_with_linux_roots))
    assert "disagree with the load policy" in text, text
    linux_with_darwin_roots = copy.deepcopy(host_lock)
    linux_with_darwin_roots["profiles"][linux_index][
        "systemRuntime"]["allowedLoadRoots"] = ["/System/Library/", "/usr/lib/"]
    module.validate_host_lock(linux_with_darwin_roots)
    text = rejection_text(
        module, lambda: module.validate_lock_pair(linux_lock, linux_with_darwin_roots))
    assert "disagree with the load policy" in text, text


def main() -> int:
    try:
        module = load_producer()
        test_registered_lock_accepted(module)
        test_static_eligibility_negatives(module)
        test_v1_migration_error(module)
        test_closed_field_sets(module)
        test_reason_shape_matches_eligibility(module)
        test_mutability_predicate(module)
        test_lock_platform_dispatch(module)
        test_verify_host_cross_profile_rejected(module)
        test_duplicate_kind_rejected(module)
        test_missing_observations_fail_closed(module)
        test_validate_host_profile_command(module)
        test_cross_lock_roots_rejected(module)
    except (AssertionError, AttributeError, OSError, ImportError, SyntaxError) as error:
        print(f"host-profiles-self-test: FAIL: {error}", file=sys.stderr)
        return 1
    print("host-profiles-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""RED acceptance tests for the pre-cutover GenesisRootPolicyV1 tool.

This is a standalone governance bootstrap slice.  It deliberately does not
model BootstrapAuthorityPolicyV1, claim a TST ID, or close TASK-D0-04.  The
production CLI is expected at the exact sibling path
``scripts/genesis_root_policy.py`` and must handle public key material only.
"""

from __future__ import annotations

import copy
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Any


TOOL = Path(__file__).with_name("genesis_root_policy.py")
SCHEMA = "proof-forge.genesis-root-policy.v1"
POLICY_ID = "proof-forge-genesis-root"
POLICY_VERSION = "1.0.0"
KEY_ID = "genesis-root-key-1"
RFC_8032_PUBLIC_KEY = (
    "d75a980182b10ab7d54bfed3c964073a"
    "0ee172f3daa62325af021a68f707511a"
)
ED25519_ZERO_ENCODING = "00" * 32
ED25519_IDENTITY_ENCODING = "01" + "00" * 31
ED25519_NONCANONICAL_Y = "ed" + "ff" * 30 + "7f"
ED25519_MIXED_ORDER_POINT = "95" + "99" * 31
EXPECTED_POLICY_DIGEST = (
    "sha256:c970ec4b383eab64f1624ddbd670de65"
    "f2b56bed5c4a67db969113947d10d440"
)
MODULE_NAME = "proof_forge_genesis_root_policy_self_test_subject"

# Declaration order here is also the RFC 8785 UTF-16 code-unit order because
# every v1 field name is ASCII.  EXPECTED_POLICY_BYTES remains the independent,
# checked-in byte oracle rather than trusting the reference encoder alone.
VALID_POLICY: dict[str, Any] = {
    "algorithm": "ed25519",
    "allowedSchemas": ["proof-forge.bootstrap-authority-policy.v1"],
    "authorityDocument": "GOV-GENESIS-001",
    "cutoverTask": "TASK-D0-04",
    "id": POLICY_ID,
    "keyId": KEY_ID,
    "maintainersDocument": "GOV-MAINTAINERS-001",
    "postCutoverDisposition": "revoke-and-historical-only",
    "principalId": "davirain",
    "publicKey": RFC_8032_PUBLIC_KEY,
    "schema": SCHEMA,
    "version": POLICY_VERSION,
}
EXPECTED_POLICY_BYTES = (
    b'{"algorithm":"ed25519","allowedSchemas":'
    b'["proof-forge.bootstrap-authority-policy.v1"],'
    b'"authorityDocument":"GOV-GENESIS-001",'
    b'"cutoverTask":"TASK-D0-04",'
    b'"id":"proof-forge-genesis-root",'
    b'"keyId":"genesis-root-key-1",'
    b'"maintainersDocument":"GOV-MAINTAINERS-001",'
    b'"postCutoverDisposition":"revoke-and-historical-only",'
    b'"principalId":"davirain",'
    b'"publicKey":"d75a980182b10ab7d54bfed3c964073a'
    b'0ee172f3daa62325af021a68f707511a",'
    b'"schema":"proof-forge.genesis-root-policy.v1",'
    b'"version":"1.0.0"}'
)


def reference_pf_jcs(value: Any) -> bytes:
    """Encode this ASCII-key, integer-free closed fixture canonically."""

    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def load_tool() -> ModuleType:
    spec = importlib.util.spec_from_file_location(MODULE_NAME, TOOL)
    expect(
        spec is not None and spec.loader is not None and spec.origin is not None,
        "production CLI import spec unavailable",
    )
    assert spec is not None and spec.loader is not None and spec.origin is not None
    expect(
        Path(spec.origin).resolve(strict=True) == TOOL.resolve(strict=True),
        "production CLI import origin changed",
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


def invoke(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-I", "-S", str(TOOL), *args],
        cwd=cwd,
        check=False,
        text=True,
        capture_output=True,
        timeout=10,
    )


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def expect_ok(label: str, result: subprocess.CompletedProcess[str]) -> None:
    if result.returncode != 0:
        raise AssertionError(
            f"{label}: expected success, got {result.returncode}; "
            f"stdout={result.stdout!r}; stderr={result.stderr!r}"
        )


def expect_fail(label: str, result: subprocess.CompletedProcess[str]) -> None:
    if result.returncode == 0:
        raise AssertionError(f"{label}: expected fail-closed nonzero exit")
    if "traceback" in result.stderr.lower():
        raise AssertionError(f"{label}: failure leaked a traceback: {result.stderr!r}")


def generate_args(output: Path, public_key: str = RFC_8032_PUBLIC_KEY) -> list[str]:
    return [
        "generate",
        "--key-id",
        KEY_ID,
        "--public-key",
        public_key,
        "--output",
        str(output),
    ]


def validate(path: Path, cwd: Path) -> subprocess.CompletedProcess[str]:
    return invoke(["validate", "--input", str(path)], cwd)


def mutated(field: str, value: Any) -> dict[str, Any]:
    policy = copy.deepcopy(VALID_POLICY)
    policy[field] = value
    return policy


def assert_reference_fixture() -> None:
    expect(
        list(VALID_POLICY) == sorted(VALID_POLICY),
        "test fixture fields must already be in canonical UTF-16/ASCII order",
    )
    expect(
        reference_pf_jcs(VALID_POLICY) == EXPECTED_POLICY_BYTES,
        "hard-coded canonical byte oracle disagrees with reference encoder",
    )
    expect(b"\n" not in EXPECTED_POLICY_BYTES, "policy must be one line")
    expect(b"\r" not in EXPECTED_POLICY_BYTES, "policy must not contain CR")
    expect(
        not EXPECTED_POLICY_BYTES.endswith(b"\n"),
        "policy must not have a trailing newline",
    )


def test_cli_surface(base: Path) -> None:
    root_help = invoke(["--help"], base)
    generate_help = invoke(["generate", "--help"], base)
    validate_help = invoke(["validate", "--help"], base)
    expect_ok("root help", root_help)
    expect_ok("generate help", generate_help)
    expect_ok("validate help", validate_help)

    root_text = root_help.stdout + root_help.stderr
    generate_text = generate_help.stdout + generate_help.stderr
    validate_text = validate_help.stdout + validate_help.stderr
    expect("generate" in root_text and "validate" in root_text, "root help commands")
    for option in ("--public-key", "--key-id", "--output"):
        expect(option in generate_text, f"generate help must expose {option}")
    expect("--input" in validate_text, "validate help must expose --input")

    all_help = "\n".join((root_text, generate_text, validate_text)).lower()
    for forbidden in ("--private-key", "--seed", "generate-key", "keygen"):
        expect(forbidden not in all_help, f"CLI must not expose {forbidden}")

    forbidden_cases = (
        (
            "private-key option",
            [*generate_args(base / "private.json"), "--private-key", "00" * 32],
            base / "private.json",
        ),
        (
            "seed option",
            [*generate_args(base / "seed.json"), "--seed", "00" * 32],
            base / "seed.json",
        ),
        (
            "generate-key command",
            ["generate-key", "--output", str(base / "generated-key.json")],
            base / "generated-key.json",
        ),
        (
            "keygen command",
            ["keygen", "--output", str(base / "keygen.json")],
            base / "keygen.json",
        ),
    )
    for label, args, output in forbidden_cases:
        result = invoke(args, base)
        expect_fail(label, result)
        expect(not output.exists(), f"{label}: must leave zero output")


def test_deterministic_generation_and_validation(base: Path) -> None:
    first = base / "first.json"
    second = base / "second.json"
    first_result = invoke(generate_args(first), base)
    expect_ok("first generation", first_result)
    expect(
        f"digest={EXPECTED_POLICY_DIGEST}" in first_result.stdout,
        "generate CLI must print the fixed domain-separated digest",
    )
    expect_ok(
        "second generation with reordered CLI options",
        invoke(
            [
                "generate",
                "--output",
                str(second),
                "--public-key",
                RFC_8032_PUBLIC_KEY,
                "--key-id",
                KEY_ID,
            ],
            base,
        ),
    )

    expect(first.read_bytes() == EXPECTED_POLICY_BYTES, "first canonical bytes")
    expect(second.read_bytes() == EXPECTED_POLICY_BYTES, "second canonical bytes")
    expect(first.read_bytes() == second.read_bytes(), "deterministic generation")
    expect_ok("validate generated policy", validate(first, base))

    explicit = base / "rfc8032.json"
    explicit.write_bytes(EXPECTED_POLICY_BYTES)
    expect_ok("validate RFC 8032 public-key policy", validate(explicit, base))

    expect(
        {path.name for path in base.iterdir()}
        == {"first.json", "second.json", "rfc8032.json"},
        "successful generation must not leave staging files",
    )


def test_digest_known_answer(module: ModuleType) -> None:
    digest = module.genesis_root_policy_digest(EXPECTED_POLICY_BYTES)
    expect(
        digest == EXPECTED_POLICY_DIGEST,
        f"domain-separated digest drifted: {digest!r}",
    )


def expect_invalid_bytes(label: str, raw: bytes, base: Path) -> None:
    candidate = base / "candidate.json"
    candidate.write_bytes(raw)
    before = candidate.read_bytes()
    result = validate(candidate, base)
    expect_fail(label, result)
    expect(candidate.read_bytes() == before, f"{label}: validator mutated input")


def test_closed_schema_and_noncanonical_inputs(base: Path) -> None:
    for field in VALID_POLICY:
        policy = copy.deepcopy(VALID_POLICY)
        del policy[field]
        expect_invalid_bytes(
            f"missing field {field}", reference_pf_jcs(policy), base
        )

    extra = copy.deepcopy(VALID_POLICY)
    extra["extra"] = "forbidden"
    expect_invalid_bytes("unknown field", reference_pf_jcs(extra), base)

    duplicate = EXPECTED_POLICY_BYTES.replace(
        b'"schema":"proof-forge.genesis-root-policy.v1",',
        b'"schema":"proof-forge.genesis-root-policy.v1",'
        b'"schema":"proof-forge.genesis-root-policy.v1",',
        1,
    )
    expect_invalid_bytes("duplicate object key", duplicate, base)

    exact_mutations = (
        ("boolean schema", "schema", True),
        ("wrong schema", "schema", "proof-forge.genesis-root-policy.v2"),
        ("boolean id", "id", True),
        ("wrong id", "id", "proof-forge-genesis-root-2"),
        ("boolean version", "version", True),
        ("wrong version", "version", "1.0.1"),
        ("wrong authority document", "authorityDocument", "GOV-GENESIS-002"),
        (
            "wrong maintainers document",
            "maintainersDocument",
            "GOV-MAINTAINERS-002",
        ),
        ("wrong principal", "principalId", "another-maintainer"),
        ("invalid key id", "keyId", "-genesis-root-key"),
        ("wrong algorithm casing", "algorithm", "Ed25519"),
        ("wrong algorithm", "algorithm", "ed448"),
        ("wrong cutover", "cutoverTask", "TASK-D0-07"),
        (
            "wrong disposition",
            "postCutoverDisposition",
            "retain-active",
        ),
        ("allowed schema string", "allowedSchemas", "proof-forge.bootstrap-authority-policy.v1"),
        ("allowed schema empty", "allowedSchemas", []),
        (
            "allowed schema wrong",
            "allowedSchemas",
            ["proof-forge.bootstrap-authority-policy.v2"],
        ),
        (
            "allowed schema duplicate",
            "allowedSchemas",
            [
                "proof-forge.bootstrap-authority-policy.v1",
                "proof-forge.bootstrap-authority-policy.v1",
            ],
        ),
        (
            "allowed schema extra",
            "allowedSchemas",
            [
                "proof-forge.bootstrap-authority-policy.v1",
                "proof-forge.task-approval.v1",
            ],
        ),
    )
    for label, field, value in exact_mutations:
        expect_invalid_bytes(label, reference_pf_jcs(mutated(field, value)), base)

    key_mutations = (
        ("boolean public key", True),
        ("short public key", RFC_8032_PUBLIC_KEY[:-2]),
        ("non-hex public key", "zz" * 32),
        ("uppercase public key", RFC_8032_PUBLIC_KEY.upper()),
        ("zero public key", ED25519_ZERO_ENCODING),
        ("small-order identity public key", ED25519_IDENTITY_ENCODING),
        ("noncanonical point public key", ED25519_NONCANONICAL_Y),
        ("mixed-order public key", ED25519_MIXED_ORDER_POINT),
    )
    for label, value in key_mutations:
        expect_invalid_bytes(
            label, reference_pf_jcs(mutated("publicKey", value)), base
        )

    reversed_policy = {
        key: VALID_POLICY[key] for key in reversed(tuple(VALID_POLICY))
    }
    reordered = json.dumps(
        reversed_policy, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    expect(reordered != EXPECTED_POLICY_BYTES, "reorder fixture must be noncanonical")
    noncanonical_inputs = (
        ("reordered object keys", reordered),
        ("pretty JSON", json.dumps(VALID_POLICY, sort_keys=True, indent=2).encode()),
        ("leading whitespace", b" " + EXPECTED_POLICY_BYTES),
        ("trailing newline", EXPECTED_POLICY_BYTES + b"\n"),
        ("trailing space", EXPECTED_POLICY_BYTES + b" "),
    )
    for label, raw in noncanonical_inputs:
        expect_invalid_bytes(label, raw, base)


def test_generate_rejects_invalid_public_keys(base: Path) -> None:
    invalid_keys = (
        RFC_8032_PUBLIC_KEY[:-2],
        "zz" * 32,
        RFC_8032_PUBLIC_KEY.upper(),
        ED25519_ZERO_ENCODING,
        ED25519_IDENTITY_ENCODING,
        ED25519_NONCANONICAL_Y,
        ED25519_MIXED_ORDER_POINT,
    )
    for index, public_key in enumerate(invalid_keys):
        case = base / f"invalid-key-{index}"
        case.mkdir()
        output = case / "policy.json"
        result = invoke(generate_args(output, public_key), case)
        expect_fail(f"generate invalid public key {index}", result)
        expect(list(case.iterdir()) == [], "invalid key must leave zero output")

    missing_cases = (
        (
            "missing explicit public key",
            ["generate", "--key-id", KEY_ID, "--output", str(base / "missing-key.json")],
            base / "missing-key.json",
        ),
        (
            "missing explicit key id",
            [
                "generate",
                "--public-key",
                RFC_8032_PUBLIC_KEY,
                "--output",
                str(base / "missing-id.json"),
            ],
            base / "missing-id.json",
        ),
        (
            "missing explicit output",
            [
                "generate",
                "--public-key",
                RFC_8032_PUBLIC_KEY,
                "--key-id",
                KEY_ID,
            ],
            None,
        ),
    )
    for label, args, output in missing_cases:
        result = invoke(args, base)
        expect_fail(label, result)
        if output is not None:
            expect(not output.exists(), f"{label}: must leave zero output")


def test_filesystem_fail_closed_and_atomicity(base: Path) -> None:
    existing_parent = base / "existing"
    existing_parent.mkdir()
    existing = existing_parent / "policy.json"
    existing.write_bytes(b"do-not-overwrite")
    result = invoke(generate_args(existing), existing_parent)
    expect_fail("existing output", result)
    expect(existing.read_bytes() == b"do-not-overwrite", "existing output changed")
    expect(
        {path.name for path in existing_parent.iterdir()} == {"policy.json"},
        "existing-output failure left staging files",
    )

    symlink_parent = base / "direct-symlink"
    symlink_parent.mkdir()
    target = symlink_parent / "target.json"
    target.write_bytes(b"do-not-follow")
    link = symlink_parent / "policy.json"
    link.symlink_to(target.name)
    result = invoke(generate_args(link), symlink_parent)
    expect_fail("symlink output", result)
    expect(link.is_symlink(), "symlink output was replaced")
    expect(target.read_bytes() == b"do-not-follow", "symlink target changed")
    expect(
        {path.name for path in symlink_parent.iterdir()}
        == {"policy.json", "target.json"},
        "symlink-output failure left staging files",
    )

    parent_symlink_case = base / "parent-symlink"
    parent_symlink_case.mkdir()
    real_parent = parent_symlink_case / "real"
    real_parent.mkdir()
    alias = parent_symlink_case / "alias"
    alias.symlink_to(real_parent.name, target_is_directory=True)
    result = invoke(generate_args(alias / "policy.json"), parent_symlink_case)
    expect_fail("symlink output parent", result)
    expect(list(real_parent.iterdir()) == [], "symlink parent escaped output")

    directory_parent = base / "directory-output"
    directory_parent.mkdir()
    directory_output = directory_parent / "policy.json"
    directory_output.mkdir()
    result = invoke(generate_args(directory_output), directory_parent)
    expect_fail("directory output", result)
    expect(directory_output.is_dir(), "directory output was replaced")
    expect(
        {path.name for path in directory_parent.iterdir()} == {"policy.json"},
        "directory-output failure left staging files",
    )

    invalid_parent = base / "prevalidation-failure"
    invalid_parent.mkdir()
    invalid_output = invalid_parent / "policy.json"
    result = invoke(generate_args(invalid_output, ED25519_ZERO_ENCODING), invalid_parent)
    expect_fail("prevalidation atomic failure", result)
    expect(list(invalid_parent.iterdir()) == [], "failed generation left partial files")

    validate_parent = base / "validate-symlink"
    validate_parent.mkdir()
    real_input = validate_parent / "real.json"
    real_input.write_bytes(EXPECTED_POLICY_BYTES)
    input_link = validate_parent / "policy.json"
    input_link.symlink_to(real_input.name)
    result = validate(input_link, validate_parent)
    expect_fail("symlink validation input", result)
    expect(input_link.is_symlink(), "validator replaced symlink input")
    expect(real_input.read_bytes() == EXPECTED_POLICY_BYTES, "validator changed target")

    input_parent_case = base / "validate-parent-symlink"
    input_parent_case.mkdir()
    real_input_parent = input_parent_case / "real"
    real_input_parent.mkdir()
    parent_input = real_input_parent / "policy.json"
    parent_input.write_bytes(EXPECTED_POLICY_BYTES)
    input_alias = input_parent_case / "alias"
    input_alias.symlink_to(real_input_parent.name, target_is_directory=True)
    result = validate(input_alias / "policy.json", input_parent_case)
    expect_fail("symlink validation input parent", result)
    expect(
        parent_input.read_bytes() == EXPECTED_POLICY_BYTES,
        "validator changed input reached through parent symlink",
    )

    fifo_case = base / "validate-fifo"
    fifo_case.mkdir()
    fifo = fifo_case / "policy.json"
    os.mkfifo(fifo)
    result = validate(fifo, fifo_case)
    expect_fail("FIFO validation input", result)
    expect(stat_is_fifo(fifo), "validator replaced FIFO input")

    hardlink_case = base / "validate-hardlink"
    hardlink_case.mkdir()
    hardlink_source = hardlink_case / "source.json"
    hardlink_source.write_bytes(EXPECTED_POLICY_BYTES)
    hardlink_input = hardlink_case / "policy.json"
    os.link(hardlink_source, hardlink_input)
    result = validate(hardlink_input, hardlink_case)
    expect_fail("hardlink validation input", result)
    expect(
        hardlink_source.read_bytes() == EXPECTED_POLICY_BYTES
        and hardlink_input.read_bytes() == EXPECTED_POLICY_BYTES,
        "validator changed hardlinked input",
    )


def stat_is_fifo(path: Path) -> bool:
    import stat

    return stat.S_ISFIFO(path.lstat().st_mode)


def expect_library_rejected(
    label: str,
    module: ModuleType,
    operation: Any,
) -> Any:
    error_type = module.GenesisRootPolicyError
    try:
        operation()
    except error_type as error:
        return error
    except Exception as error:
        raise AssertionError(
            f"{label}: leaked unexpected {type(error).__name__}: {error}"
        ) from None
    raise AssertionError(f"{label}: expected GenesisRootPolicyError")


def expect_empty_failed_publish(case: Path, output: Path, label: str) -> None:
    expect(not output.exists(), f"{label}: published a partial/failing output")
    expect(list(case.iterdir()) == [], f"{label}: left staging residue")


def test_atomic_failure_injection(base: Path, module: ModuleType) -> None:
    write_case = base / "write-failure"
    write_case.mkdir()
    write_output = write_case / "policy.json"
    original_write = module.os.write
    writes = 0

    def partial_then_fail(descriptor: int, data: bytes) -> int:
        nonlocal writes
        writes += 1
        if writes == 1:
            return original_write(descriptor, data[: max(1, len(data) // 2)])
        raise OSError("injected write failure")

    module.os.write = partial_then_fail
    try:
        expect_library_rejected(
            "write failure",
            module,
            lambda: module.atomic_publish_no_clobber(
                write_output, EXPECTED_POLICY_BYTES
            ),
        )
    finally:
        module.os.write = original_write
    expect_empty_failed_publish(write_case, write_output, "write failure")

    fsync_case = base / "post-link-fsync-failure"
    fsync_case.mkdir()
    fsync_output = fsync_case / "policy.json"
    original_fsync = module.os.fsync
    fsyncs = 0

    def fail_first_parent_fsync(descriptor: int) -> None:
        nonlocal fsyncs
        fsyncs += 1
        if fsyncs == 3:
            raise OSError("injected post-link fsync failure")
        original_fsync(descriptor)

    module.os.fsync = fail_first_parent_fsync
    try:
        expect_library_rejected(
            "post-link fsync failure",
            module,
            lambda: module.atomic_publish_no_clobber(
                fsync_output, EXPECTED_POLICY_BYTES
            ),
        )
    finally:
        module.os.fsync = original_fsync
    expect_empty_failed_publish(
        fsync_case, fsync_output, "post-link fsync failure"
    )

    race_case = base / "publish-race"
    race_case.mkdir()
    race_output = race_case / "policy.json"
    original_link = module.os.link
    competitor = b"competitor-wins"
    race_observation: dict[str, Any] = {}

    def inject_competitor(
        source: str,
        destination: str,
        *,
        src_dir_fd: int,
        dst_dir_fd: int,
        follow_symlinks: bool,
    ) -> None:
        del source, src_dir_fd, follow_symlinks
        descriptor = module.os.open(
            destination,
            module.os.O_WRONLY | module.os.O_CREAT | module.os.O_EXCL,
            0o600,
            dir_fd=dst_dir_fd,
        )
        race_observation["created"] = True
        try:
            written = original_write(descriptor, competitor)
            expect(written == len(competitor), "race fixture short write")
        finally:
            module.os.close(descriptor)
        raise FileExistsError("injected competing publisher")

    module.os.link = inject_competitor
    try:
        race_error = expect_library_rejected(
            "publish race",
            module,
            lambda: module.atomic_publish_no_clobber(
                race_output, EXPECTED_POLICY_BYTES
            ),
        )
    finally:
        module.os.link = original_link
    expect(
        race_output.exists(),
        "publish race removed competitor; "
        f"error={race_error!s} observation={race_observation!r} entries="
        f"{sorted(path.name for path in race_case.iterdir())!r}",
    )
    expect(race_output.read_bytes() == competitor, "publish race clobbered winner")
    expect(
        {path.name for path in race_case.iterdir()} == {"policy.json"},
        "publish race left staging residue",
    )


def main() -> int:
    assert_reference_fixture()
    expect(
        TOOL.is_file() and not TOOL.is_symlink(),
        f"RED: production CLI is missing at exact path {TOOL}",
    )
    module = load_tool()
    test_digest_known_answer(module)
    with tempfile.TemporaryDirectory(prefix="pf-genesis-root-policy-") as temporary:
        root = Path(temporary).resolve(strict=True)
        cli = root / "cli"
        cli.mkdir()
        test_cli_surface(cli)

        generation = root / "generation"
        generation.mkdir()
        test_deterministic_generation_and_validation(generation)

        schema = root / "schema"
        schema.mkdir()
        test_closed_schema_and_noncanonical_inputs(schema)

        generate_invalid = root / "generate-invalid"
        generate_invalid.mkdir()
        test_generate_rejects_invalid_public_keys(generate_invalid)

        filesystem = root / "filesystem"
        filesystem.mkdir()
        test_filesystem_fail_closed_and_atomicity(filesystem)

        fault_injection = root / "fault-injection"
        fault_injection.mkdir()
        test_atomic_failure_injection(fault_injection, module)

    print("genesis-root-policy-self-test: ok")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.TimeoutExpired) as error:
        print(f"genesis-root-policy-self-test: {error}", file=sys.stderr)
        raise SystemExit(1) from None

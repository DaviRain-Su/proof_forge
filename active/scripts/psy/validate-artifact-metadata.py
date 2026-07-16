#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


REQUIRED_ARTIFACTS = ("source", "packageSource", "circuitJson", "abiJson", "executeLog", "dargoManifest")
REQUIRED_VALIDATIONS = ("dargoTest", "dargoCompile", "dargoExecute", "dargoGenerateAbi", "dargoPackage")


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"psy-metadata-validate: {message}")


def expect_object(value: Any, name: str) -> dict:
    expect(isinstance(value, dict), f"{name} must be an object")
    return value


def expect_string(value: Any, name: str) -> str:
    expect(isinstance(value, str) and value, f"{name} must be a non-empty string")
    return value


def file_entry(root: Path, entry: dict, name: str) -> Path:
    path = root / expect_string(entry.get("path"), f"artifacts.{name}.path")
    expect(path.is_file(), f"artifacts.{name}.path does not exist: {path}")
    data = path.read_bytes()
    expect(entry.get("bytes") == len(data), f"artifacts.{name}.bytes mismatch")
    expect(
        entry.get("sha256") == hashlib.sha256(data).hexdigest(),
        f"artifacts.{name}.sha256 mismatch",
    )
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("metadata")
    args = parser.parse_args()

    root = Path(args.root)
    metadata_path = Path(args.metadata)
    metadata = expect_object(json.loads(metadata_path.read_text()), "metadata")

    expect(metadata.get("schemaVersion") == 1, "schemaVersion must be 1")
    expect(metadata.get("target") == "psy-dpn", "target must be psy-dpn")
    expect(metadata.get("targetFamily") == "zk-circuit-sourcegen", "targetFamily mismatch")
    expect(metadata.get("artifactKind") == "psy-circuit-json", "artifactKind mismatch")
    expect_string(metadata.get("fixture"), "fixture")

    # Z1.2: primary/final output honesty relative to dargoCompile.
    validation_preview = metadata.get("validation") if isinstance(metadata.get("validation"), dict) else {}
    dargo_compile = validation_preview.get("dargoCompile")
    primary = metadata.get("primaryOutput")
    final = metadata.get("finalOutput")
    lower = metadata.get("lowerBoundary")
    if dargo_compile == "passed":
        expect(
            primary == "dpn-bytecode-json",
            "primaryOutput must be dpn-bytecode-json when dargoCompile=passed",
        )
        expect(
            final == "dpn-bytecode-json",
            "finalOutput must be dpn-bytecode-json when dargoCompile=passed",
        )
        expect(
            lower == "DPNFunctionCircuitDefinition",
            "lowerBoundary must name DPNFunctionCircuitDefinition when compile passed",
        )
    elif dargo_compile in ("notRun", "unavailable", "failed"):
        expect(
            final in (None, "null") or final is None,
            "finalOutput must be null/absent when dargoCompile is not passed",
        )
        expect(
            primary in ("psy-source", "dpn-bytecode-json", None)
            or isinstance(primary, str),
            "primaryOutput must be present as a string when set",
        )
        if final not in (None, "null") and final is not None:
            raise SystemExit(
                "psy-metadata-validate: finalOutput must not claim DPN when compile skipped"
            )

    capabilities = metadata.get("capabilities")
    expect(isinstance(capabilities, list) and capabilities, "capabilities must be a non-empty array")
    for idx, capability in enumerate(capabilities):
        expect_string(capability, f"capabilities[{idx}]")

    toolchain = expect_object(metadata.get("toolchain"), "toolchain")
    dargo = expect_object(toolchain.get("dargo"), "toolchain.dargo")
    expect_string(dargo.get("path"), "toolchain.dargo.path")
    expect(dargo.get("version") is None or isinstance(dargo.get("version"), str), "toolchain.dargo.version must be null or string")

    artifacts = expect_object(metadata.get("artifacts"), "artifacts")
    for artifact_name in REQUIRED_ARTIFACTS:
        file_entry(root, expect_object(artifacts.get(artifact_name), f"artifacts.{artifact_name}"), artifact_name)
    expect(
        artifacts["packageSource"]["sha256"] == artifacts["source"]["sha256"],
        "artifacts.packageSource.sha256 must match artifacts.source.sha256",
    )
    dargo_manifest = (root / artifacts["dargoManifest"]["path"]).read_text()
    expect("[package]" in dargo_manifest, "artifacts.dargoManifest must contain a [package] section")
    expect("type = \"bin\"" in dargo_manifest, "artifacts.dargoManifest must describe a bin package")
    expect("[dependencies]" in dargo_manifest, "artifacts.dargoManifest must contain a [dependencies] section")
    if "deployJson" in artifacts:
        file_entry(root, expect_object(artifacts.get("deployJson"), "artifacts.deployJson"), "deployJson")

    validation = expect_object(metadata.get("validation"), "validation")
    for key in REQUIRED_VALIDATIONS:
        status = validation.get(key)
        expect(
            status in ("notRun", "passed", "failed", "unavailable"),
            f"validation.{key} must be one of: notRun, passed, failed, unavailable (got {status!r})",
        )
    if "deployJson" in artifacts:
        status = validation.get("deployManifest")
        expect(
            status in ("notRun", "passed", "failed", "unavailable"),
            f"validation.deployManifest must be one of: notRun, passed, failed, unavailable (got {status!r})",
        )
    execute_result = expect_string(validation.get("executeResult"), "validation.executeResult")

    execute_log = (root / artifacts["executeLog"]["path"]).read_text()
    for expected in [part.strip() for part in execute_result.split(";") if part.strip()]:
        expect(expected in execute_log, f"execute log does not contain expected result: {expected}")

    # Honesty rule: if executeResult was verified against the execute log, then
    # dargoExecute must be "passed", not "notRun"/"unavailable"/"failed".
    expect(
        validation.get("dargoExecute") == "passed",
        "validation.dargoExecute must be 'passed' when executeResult is verifiable in the execute log",
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

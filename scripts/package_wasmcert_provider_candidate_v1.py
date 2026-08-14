#!/usr/bin/env python3
"""Package one fail-closed WasmCert provider candidate and runtime closure.

The output is deliberately not a Tool Lock asset. It records exact build
inputs, probes the native executable, closes non-system Darwin dependencies,
and emits a canonical candidate manifest for later human admission.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform as host_platform
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = "proof-forge.wasmcert-provider-candidate.v1"
EXECUTABLE = "proof-forge-wasmcert-provider-v1"
SOURCE_REVISION = "9ab0f87f03fff5507749efc273ec662fe27e6d14"
EXPECTED_VERSION = f"{EXECUTABLE} 1.0.0 {SOURCE_REVISION}"
PLATFORM_HOSTS = {
    "darwin-arm64": ("Darwin", "arm64"),
    "linux-x86_64": ("Linux", "x86_64"),
}
SYSTEM_ROOTS = {
    "darwin-arm64": ("/System/Library/", "/usr/lib/"),
    "linux-x86_64": ("/lib/", "/lib64/", "/usr/lib/"),
}
HEX_40 = re.compile(r"[0-9a-f]{40}")
HEX_64 = re.compile(r"[0-9a-f]{64}")
REPOSITORY_OBSERVATION_SCHEMA = "proof-forge.opam-repository-observation.v1"
CANONICAL_TREE_DIGEST = "sha256(u64be(pathLen)||pathUtf8||u64be(size)||sha256(content))*"
EXPECTED_REPOSITORIES = [
    ("default", "https://opam.ocaml.org"),
    ("rocq-released", "https://rocq-prover.org/opam/released"),
]


def fail(message: str) -> "None":
    raise SystemExit(f"package-wasmcert-provider-candidate: {message}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(args: list[str]) -> str:
    try:
        completed = subprocess.run(
            args, check=True, capture_output=True, text=True, timeout=60
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        fail(f"command failed: {' '.join(args)} ({error})")
    return completed.stdout


def under_roots(path: str, roots: tuple[str, ...]) -> bool:
    return any(path.startswith(root) for root in roots)


def parse_packages(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    names: set[str] = set()
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 2 or fields[0] in names:
            fail(f"{path}:{number}: invalid package inventory row")
        names.add(fields[0])
        rows.append({"name": fields[0], "version": fields[1]})
    if not rows:
        fail(f"{path}: package inventory is empty")
    return sorted(rows, key=lambda row: row["name"].encode("utf-8"))


def parse_repository_observation(path: Path) -> dict[str, object]:
    raw = path.read_text(encoding="utf-8")
    try:
        observation = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        fail(f"{path}: invalid repository observation ({error})")
    canonical = json.dumps(
        observation, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ) + "\n"
    if raw != canonical:
        fail(f"{path}: repository observation is not canonical JSON")
    if not isinstance(observation, dict) or set(observation) != {
        "canonicalTreeDigest",
        "reposConfigSha256",
        "repositories",
        "schema",
    }:
        fail(f"{path}: repository observation has an unknown or missing field")
    if observation["schema"] != REPOSITORY_OBSERVATION_SCHEMA:
        fail(f"{path}: repository observation schema differs")
    if observation["canonicalTreeDigest"] != CANONICAL_TREE_DIGEST:
        fail(f"{path}: repository tree digest algorithm differs")
    if not isinstance(observation["reposConfigSha256"], str) or not HEX_64.fullmatch(
        observation["reposConfigSha256"]
    ):
        fail(f"{path}: repos-config digest must be exact lowercase SHA-256")
    repositories = observation["repositories"]
    if not isinstance(repositories, list) or len(repositories) != len(EXPECTED_REPOSITORIES):
        fail(f"{path}: repository snapshot inventory must contain both exact repositories")
    for row, (expected_name, expected_url) in zip(repositories, EXPECTED_REPOSITORIES):
        if not isinstance(row, dict) or set(row) != {
            "fileCount", "name", "path", "sha256", "size", "storage", "url"
        }:
            fail(f"{path}: repository snapshot has an unknown or missing field")
        if row["name"] != expected_name or row["url"] != expected_url:
            fail(f"{path}: repository name/origin differs from the frozen inventory")
        if not isinstance(row["sha256"], str) or not HEX_64.fullmatch(row["sha256"]):
            fail(f"{path}: repository snapshot digest must be exact lowercase SHA-256")
        if type(row["size"]) is not int or row["size"] <= 0:
            fail(f"{path}: repository snapshot size must be positive")
        if type(row["fileCount"]) is not int or row["fileCount"] <= 0:
            fail(f"{path}: repository snapshot file count must be positive")
        if row["storage"] == "archive-bytes-v1":
            if row["path"] != f"repo/{expected_name}.tar.gz" or row["fileCount"] != 1:
                fail(f"{path}: archive repository descriptor is inconsistent")
        elif row["storage"] == "canonical-file-tree-v1":
            if row["path"] != f"repo/{expected_name}":
                fail(f"{path}: tree repository descriptor is inconsistent")
        else:
            fail(f"{path}: unsupported repository snapshot storage kind")
    return observation


def file_descriptor(path: Path, relative: str, mode: str) -> dict[str, object]:
    metadata = path.stat()
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        fail(f"candidate leaf is not a regular non-symlink file: {path}")
    if mode in {"0444", "0555"} and stat.S_IMODE(metadata.st_mode) != int(mode, 8):
        fail(f"candidate leaf mode differs from {mode}: {path}")
    return {
        "mode": mode,
        "path": relative,
        "sha256": sha256_file(path),
        "size": metadata.st_size,
    }


def linux_policy(provider: Path, report: Path) -> tuple[list[dict[str, object]], list[str]]:
    dynamic = run(["readelf", "-d", str(provider)])
    resolved = run(["ldd", str(provider)])
    report.write_text(
        "## readelf -d\n" + dynamic + "\n## ldd\n" + resolved,
        encoding="utf-8",
    )
    if "not found" in resolved:
        fail("ldd reported an unresolved dependency")

    needed = sorted(set(re.findall(r"Shared library: \[([^]]+)\]", dynamic)))
    runpaths = re.findall(r"Library (?:runpath|rpath): \[([^]]*)\]", dynamic)
    if len(runpaths) > 1:
        fail("ELF declares multiple RUNPATH/RPATH records")
    runpath = runpaths[0] if runpaths else None

    resolved_by_name: dict[str, str] = {}
    for line in resolved.splitlines():
        match = re.match(r"\s*(\S+)\s+=>\s+(/\S+)", line)
        if match:
            resolved_by_name[match.group(1)] = match.group(2)
    system_loads: list[str] = []
    for soname in needed:
        path = resolved_by_name.get(soname)
        if path is None:
            fail(f"ldd did not resolve ELF dependency '{soname}'")
        if not under_roots(path, SYSTEM_ROOTS["linux-x86_64"]):
            fail(f"Linux candidate has a non-system dependency '{path}'")
        system_loads.append(path)
    policy = [{
        "needed": [{"bundlePath": None, "soname": name} for name in needed],
        "path": EXECUTABLE,
        "runpath": runpath,
    }]
    return policy, sorted(system_loads)


def otool_loads(path: Path) -> list[str]:
    output = run(["/usr/bin/otool", "-L", str(path)])
    lines = output.splitlines()
    if not lines:
        fail(f"otool emitted no dependency report for {path}")
    loads: list[str] = []
    for raw in lines[1:]:
        line = raw.strip()
        if not line:
            continue
        loads.append(line.split(" (", 1)[0])
    return loads


def otool_install_id(path: Path) -> str | None:
    completed = subprocess.run(
        ["/usr/bin/otool", "-D", str(path)],
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if completed.returncode != 0:
        return None
    lines = [
        line.strip()
        for line in completed.stdout.splitlines()[1:]
        if line.strip() and not line.rstrip().endswith(":")
    ]
    if len(set(lines)) > 1:
        fail(f"Mach-O has multiple install IDs: {path}")
    return lines[0] if lines else None


def darwin_policy(
    provider: Path, staging: Path, report: Path
) -> tuple[list[dict[str, object]], list[str]]:
    pending: list[tuple[Path, str]] = [(provider, EXECUTABLE)]
    seen: set[str] = set()
    policy: list[dict[str, object]] = []
    system_loads: set[str] = set()
    raw_reports: list[str] = []
    runtime_dir = staging / "lib"

    while pending:
        binary, relative = pending.pop(0)
        if relative in seen:
            continue
        seen.add(relative)
        raw_reports.append(f"## otool -L {relative}\n{run(['/usr/bin/otool', '-L', str(binary)])}")
        install_id = otool_install_id(binary)
        external: list[dict[str, str]] = []
        for install_name in otool_loads(binary):
            if install_name == install_id:
                continue
            if under_roots(install_name, SYSTEM_ROOTS["darwin-arm64"]):
                system_loads.add(install_name)
                continue
            if install_name.startswith("@") or not install_name.startswith("/"):
                fail(f"unsupported non-absolute Mach-O load '{install_name}'")
            source = Path(install_name).resolve(strict=True)
            bundle_path = f"lib/{source.name}"
            destination = staging / bundle_path
            runtime_dir.mkdir(parents=True, exist_ok=True)
            if destination.exists():
                if sha256_file(destination) != sha256_file(source):
                    fail(f"runtime dependency basename collision at '{bundle_path}'")
            else:
                shutil.copyfile(source, destination)
                destination.chmod(0o444)
            external.append({"bundlePath": bundle_path, "installName": install_name})
            pending.append((destination, bundle_path))
        policy.append({
            "externalLoads": sorted(external, key=lambda row: row["installName"].encode("utf-8")),
            "installId": install_id,
            "path": relative,
        })

    report.write_text("\n".join(raw_reports), encoding="utf-8")
    return sorted(policy, key=lambda row: str(row["path"]).encode("utf-8")), sorted(system_loads)


def canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", required=True, type=Path)
    parser.add_argument("--platform", required=True, choices=sorted(PLATFORM_HOSTS))
    parser.add_argument("--proof-forge-revision", required=True)
    parser.add_argument("--installed-packages", required=True, type=Path)
    parser.add_argument("--opam-repositories", required=True, type=Path)
    parser.add_argument("--repeat-build-report", required=True, type=Path)
    parser.add_argument("--opam-version", required=True)
    parser.add_argument("--ocaml-version", required=True)
    parser.add_argument("--dune-version", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    if not HEX_40.fullmatch(args.proof_forge_revision):
        fail("ProofForge revision must be exactly 40 lowercase hex characters")
    expected_host = PLATFORM_HOSTS[args.platform]
    observed_host = (host_platform.system(), host_platform.machine())
    if observed_host != expected_host:
        fail(f"platform {args.platform} requires host {expected_host}, got {observed_host}")
    provider = args.provider.resolve(strict=True)
    if provider.is_symlink() or not provider.is_file():
        fail("provider must be a regular non-symlink file")
    observed_version = run([str(provider), "--version"]).strip()
    if observed_version != EXPECTED_VERSION:
        fail(f"provider version mismatch: {observed_version!r}")
    provider_sha256 = sha256_file(provider)
    repeat_build_text = args.repeat_build_report.resolve(strict=True).read_text(encoding="utf-8")
    required_repeat_lines = {
        f"build-wasmcert-provider: platform={args.platform}",
        f"build-wasmcert-provider: sha256={provider_sha256}",
        "build-wasmcert-provider: repeat-check=2/2-byte-identical",
        "build-wasmcert-provider: provider remains unprovisioned and product activation stays fail closed",
    }
    observed_repeat_lines = set(repeat_build_text.splitlines())
    missing_repeat_lines = sorted(required_repeat_lines - observed_repeat_lines)
    if missing_repeat_lines:
        fail(f"repeat-build report lacks exact binding lines: {missing_repeat_lines}")
    if args.output.exists():
        fail(f"output already exists: {args.output}")

    authority_path = ROOT / "supply-chain/wasmcert-coq-authority.v1.json"
    authority = json.loads(authority_path.read_text(encoding="utf-8"))
    if authority.get("revision") != SOURCE_REVISION:
        fail("source authority revision differs from the candidate schema")

    staging = args.output.parent / f".{args.output.name}.tmp-{os.getpid()}"
    if staging.exists():
        fail(f"temporary output already exists: {staging}")
    staging.mkdir(parents=True)
    try:
        candidate_provider = staging / EXECUTABLE
        shutil.copyfile(provider, candidate_provider)
        candidate_provider.chmod(0o555)
        repeat_build_report = staging / "repeat-build.txt"
        repeat_build_report.write_text(repeat_build_text, encoding="utf-8")
        repeat_build_report.chmod(0o444)
        report = staging / "runtime-dependencies.txt"
        if args.platform == "linux-x86_64":
            policy, system_loads = linux_policy(candidate_provider, report)
            policy_kind = "elf"
        else:
            policy, system_loads = darwin_policy(candidate_provider, staging, report)
            policy_kind = "macho"
        report.chmod(0o444)

        input_paths = [
            ROOT / "scripts/build_wasmcert_provider_v1.sh",
            ROOT / "scripts/package_wasmcert_provider_candidate_v1.py",
            ROOT / "supply-chain/wasmcert-coq-authority.v1.json",
            ROOT / "tools/wasmcert-provider/dune.v1",
            ROOT / "tools/wasmcert-provider/opam-packages.v1.lock",
            ROOT / "tools/wasmcert-provider/proof_forge_wasmcert_provider_v1.ml",
        ]
        build_inputs = [
            file_descriptor(path, path.relative_to(ROOT).as_posix(), "source")
            for path in input_paths
        ]
        installed_packages = parse_packages(args.installed_packages)
        locked_packages = parse_packages(ROOT / "tools/wasmcert-provider/opam-packages.v1.lock")
        repository_observation = parse_repository_observation(args.opam_repositories)
        installed_by_name = {row["name"]: row["version"] for row in installed_packages}
        for row in locked_packages:
            if installed_by_name.get(row["name"]) != row["version"]:
                fail(f"installed package inventory differs for {row['name']}")

        payload_files: list[dict[str, object]] = []
        for path in sorted(staging.rglob("*"), key=lambda item: item.as_posix().encode("utf-8")):
            if not path.is_file():
                continue
            relative = path.relative_to(staging).as_posix()
            mode = "0555" if relative == EXECUTABLE else "0444"
            payload_files.append(file_descriptor(path, relative, mode))

        manifest = {
            "assurance": {
                "productActivated": False,
                "repeatBuildsByteIdentical": 2,
                "toolLockAdmitted": False,
            },
            "buildInputs": build_inputs,
            "buildToolVersions": {
                "dune": args.dune_version,
                "ocaml": args.ocaml_version,
                "opam": args.opam_version,
            },
            "installedPackages": installed_packages,
            "lockedPackages": locked_packages,
            "opamRepositories": repository_observation,
            "payloadFiles": payload_files,
            "platform": args.platform,
            "proofForgeRevision": args.proof_forge_revision,
            "providerSource": {
                "release": authority["release"],
                "repository": authority["repository"],
                "revision": authority["revision"],
            },
            "runtimePolicy": {
                "allowedSystemLoadRoots": list(SYSTEM_ROOTS[args.platform]),
                "files": policy,
                "kind": policy_kind,
                "observedSystemLoads": system_loads,
            },
            "schema": SCHEMA,
            "versionProbe": observed_version,
        }
        (staging / "candidate.json").write_text(canonical_json(manifest), encoding="utf-8")
        staging.rename(args.output)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    print(f"package-wasmcert-provider-candidate: platform={args.platform}")
    print(f"package-wasmcert-provider-candidate: output={args.output}")
    print(f"package-wasmcert-provider-candidate: executable-sha256={sha256_file(args.output / EXECUTABLE)}")
    print("package-wasmcert-provider-candidate: tool-lock-admitted=false")
    print("package-wasmcert-provider-candidate: product-activated=false")


if __name__ == "__main__":
    main()

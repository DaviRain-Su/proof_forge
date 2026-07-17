#!/usr/bin/env python3
"""Pre-freeze tests for archive-derived compiler runtime file witnesses.

This is preparation adjacent to pending TASK-D0-08.  It does not run the
formal TST-SBOM-002/SB2-011 acceptance, discover a real Mach-O closure, or
claim that CompilerRuntimeClosureManifestV1 publication is implemented.
"""

from __future__ import annotations

import hashlib
import importlib.util
import io
import os
import stat
import sys
import tempfile
import zipfile
from pathlib import Path
from types import ModuleType
from typing import Callable


ROOT = Path(__file__).resolve().parents[1]
TOOLCHAIN_ASSETS = ROOT / "scripts" / "toolchain_assets.py"


def load_toolchain_assets() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "proof_forge_runtime_witness_assets",
        TOOLCHAIN_ASSETS,
    )
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load toolchain_assets.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def expect_asset_error(
    module: ModuleType,
    detail: str,
    action: Callable[[], object],
) -> None:
    try:
        action()
    except module.AssetError as error:
        if detail not in str(error):
            raise AssertionError(
                f"expected AssetError containing {detail!r}, got {error!r}"
            ) from error
    else:
        raise AssertionError(f"expected AssetError containing {detail!r}")


def add_zip_entry(
    archive: zipfile.ZipFile,
    path: str,
    mode: int,
    payload: bytes,
) -> None:
    info = zipfile.ZipInfo(path)
    info.create_system = 3
    info.external_attr = mode << 16
    archive.writestr(info, payload)


def synthetic_archive() -> tuple[io.BytesIO, dict[str, bytes]]:
    payloads = {
        "bin/lake": b"synthetic-lake-entrypoint",
        "lib/shared.dylib": b"synthetic-shared-runtime",
        "notes.txt": b"unreachable-non-runtime-file",
    }
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        add_zip_entry(archive, "compiler/", stat.S_IFDIR | 0o755, b"")
        add_zip_entry(archive, "compiler/bin/", stat.S_IFDIR | 0o755, b"")
        add_zip_entry(
            archive,
            "compiler/bin/lake",
            stat.S_IFREG | 0o755,
            payloads["bin/lake"],
        )
        add_zip_entry(archive, "compiler/lib/", stat.S_IFDIR | 0o755, b"")
        add_zip_entry(
            archive,
            "compiler/lib/shared.dylib",
            stat.S_IFREG | 0o644,
            payloads["lib/shared.dylib"],
        )
        add_zip_entry(
            archive,
            "compiler/notes.txt",
            stat.S_IFREG | 0o644,
            payloads["notes.txt"],
        )
    buffer.seek(0)
    return buffer, payloads


def extract_fixture(
    module: ModuleType,
    base: Path,
) -> tuple[Path, dict[str, dict[str, object]], dict[str, bytes]]:
    buffer, payloads = synthetic_archive()
    compiler = {
        "archiveRoot": "compiler",
        "entryCount": 6,
        "unpackedSize": sum(len(payload) for payload in payloads.values()),
    }
    staging = base / "staging"
    staging.mkdir(mode=0o700)
    with zipfile.ZipFile(buffer) as archive:
        validated = module.validate_lean_zip(archive, compiler, "synthetic")
        manifest = module.extract_lean_zip(
            archive,
            validated,
            staging,
            compiler["unpackedSize"],
        )
    return staging, manifest, payloads


def overwrite_regular(path: Path, payload: bytes, mode: int) -> None:
    os.chmod(path, 0o600)
    path.write_bytes(payload)
    os.chmod(path, mode)


def test_archive_derived_witness(module: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-runtime-witness-") as temporary:
        base = Path(temporary)
        staging, manifest, payloads = extract_fixture(module, base)

        for relative, payload in sorted(payloads.items()):
            record = manifest[relative]
            expected = hashlib.sha256(payload).hexdigest()
            if record.get("sha256") != expected:
                raise AssertionError(
                    f"extraction digest witness mismatch for {relative}"
                )
            actual = module.verify_extracted_file_witness(
                staging,
                relative,
                record,
                f"synthetic member {relative}",
            )
            if actual != expected:
                raise AssertionError(
                    f"verified extracted digest mismatch for {relative}"
                )

        for relative in ("bin", "lib"):
            if "sha256" in manifest[relative]:
                raise AssertionError("directory record acquired a file digest")

        relative = "lib/shared.dylib"
        target = staging / relative
        record = manifest[relative]
        original = payloads[relative]
        expected_mode = record["mode"]
        if type(expected_mode) is not int:
            raise AssertionError("fixture file mode is not an integer")

        tampered = bytes([original[0] ^ 1]) + original[1:]
        overwrite_regular(target, tampered, expected_mode)
        expect_asset_error(
            module,
            "digest witness mismatch",
            lambda: module.verify_extracted_file_witness(
                staging, relative, record, "same-size mutation"
            ),
        )

        overwrite_regular(target, original + b"x", expected_mode)
        expect_asset_error(
            module,
            "size witness mismatch",
            lambda: module.verify_extracted_file_witness(
                staging, relative, record, "size mutation"
            ),
        )
        overwrite_regular(target, original, expected_mode)

        link = staging / "lib" / "second-link.dylib"
        os.chmod(link.parent, 0o755)
        os.link(target, link)
        os.chmod(link.parent, 0o555)
        expect_asset_error(
            module,
            "exactly one hard link",
            lambda: module.verify_extracted_file_witness(
                staging, relative, record, "hardlink mutation"
            ),
        )
        os.chmod(link.parent, 0o755)
        link.unlink()
        os.chmod(link.parent, 0o555)

        symlink_target = base / "symlink-target"
        symlink_target.write_bytes(original)
        os.chmod(target.parent, 0o755)
        target.unlink()
        target.symlink_to(symlink_target)
        os.chmod(target.parent, 0o555)
        expect_asset_error(
            module,
            "regular non-symlink",
            lambda: module.verify_extracted_file_witness(
                staging, relative, record, "symlink mutation"
            ),
        )
        os.chmod(target.parent, 0o755)
        target.unlink()
        target.write_bytes(original)
        os.chmod(target, expected_mode)
        os.chmod(target.parent, 0o555)

        replacement = staging / "lib" / "replacement.dylib"
        os.chmod(replacement.parent, 0o755)
        replacement.write_bytes(original)
        os.chmod(replacement, expected_mode)
        original_open = module.os.open
        raced_open = False

        def replace_before_open(path: object, flags: int) -> int:
            nonlocal raced_open
            if Path(path) == target and not raced_open:
                raced_open = True
                os.replace(replacement, target)
            return original_open(path, flags)

        module.os.open = replace_before_open
        try:
            expect_asset_error(
                module,
                "changed before it could be opened",
                lambda: module.verify_extracted_file_witness(
                    staging, relative, record, "lstat/open race"
                ),
            )
        finally:
            module.os.open = original_open
        os.chmod(target.parent, 0o555)

        original_read = module.os.read
        raced_read = False

        def change_metadata_during_read(descriptor: int, size: int) -> bytes:
            nonlocal raced_read
            chunk = original_read(descriptor, size)
            if chunk and not raced_read:
                raced_read = True
                metadata = target.stat()
                os.utime(
                    target,
                    ns=(metadata.st_atime_ns, metadata.st_mtime_ns + 1_000_000_000),
                )
            return chunk

        module.os.read = change_metadata_during_read
        try:
            expect_asset_error(
                module,
                "changed while being read",
                lambda: module.verify_extracted_file_witness(
                    staging, relative, record, "read race"
                ),
            )
        finally:
            module.os.read = original_read

        malformed = dict(record, unexpected=True)
        expect_asset_error(
            module,
            "witness fields",
            lambda: module.verify_extracted_file_witness(
                staging, relative, malformed, "unknown witness field"
            ),
        )


def main() -> int:
    if not sys.flags.isolated or not sys.flags.no_site:
        raise AssertionError("run with /usr/bin/python3 -I -S")
    module = load_toolchain_assets()
    test_archive_derived_witness(module)
    print("compiler-runtime-closure-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

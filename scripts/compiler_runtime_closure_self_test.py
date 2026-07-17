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
        "notes.txt": b"",
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
        base = Path(temporary).resolve(strict=True)
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

        def replace_before_open(
            path: object,
            flags: int,
            mode: int = 0o777,
            *,
            dir_fd: int | None = None,
        ) -> int:
            nonlocal raced_open
            if path == target.name and dir_fd is not None and not raced_open:
                raced_open = True
                os.replace(replacement, target)
            return original_open(path, flags, mode, dir_fd=dir_fd)

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

        original_open = module.os.open
        changed_mode = False

        def change_mode_before_open(
            path: object,
            flags: int,
            mode: int = 0o777,
            *,
            dir_fd: int | None = None,
        ) -> int:
            nonlocal changed_mode
            if path == target.name and dir_fd is not None and not changed_mode:
                changed_mode = True
                os.chmod(target, 0o600)
            return original_open(path, flags, mode, dir_fd=dir_fd)

        module.os.open = change_mode_before_open
        try:
            expect_asset_error(
                module,
                "changed before it could be opened",
                lambda: module.verify_extracted_file_witness(
                    staging, relative, record, "same-inode mode race"
                ),
            )
        finally:
            module.os.open = original_open
        os.chmod(target, expected_mode)

        outside_link = base / "outside-hardlink"
        original_open = module.os.open
        added_hardlink = False

        def add_hardlink_before_open(
            path: object,
            flags: int,
            mode: int = 0o777,
            *,
            dir_fd: int | None = None,
        ) -> int:
            nonlocal added_hardlink
            if path == target.name and dir_fd is not None and not added_hardlink:
                added_hardlink = True
                os.link(target, outside_link)
            return original_open(path, flags, mode, dir_fd=dir_fd)

        module.os.open = add_hardlink_before_open
        try:
            expect_asset_error(
                module,
                "changed before it could be opened",
                lambda: module.verify_extracted_file_witness(
                    staging, relative, record, "same-inode hardlink race"
                ),
            )
        finally:
            module.os.open = original_open
            outside_link.unlink(missing_ok=True)

        original_open = module.os.open
        original_fstat = module.os.fstat
        child_descriptor: int | None = None

        def capture_child_open(
            path: object,
            flags: int,
            mode: int = 0o777,
            *,
            dir_fd: int | None = None,
        ) -> int:
            nonlocal child_descriptor
            descriptor = original_open(path, flags, mode, dir_fd=dir_fd)
            if path == "lib" and dir_fd is not None:
                child_descriptor = descriptor
            return descriptor

        def fail_child_fstat(descriptor: int) -> os.stat_result:
            if descriptor == child_descriptor:
                raise OSError("injected child fstat failure")
            return original_fstat(descriptor)

        module.os.open = capture_child_open
        module.os.fstat = fail_child_fstat
        try:
            expect_asset_error(
                module,
                "cannot safely read child fstat failure",
                lambda: module.verify_extracted_file_witness(
                    staging, relative, record, "child fstat failure"
                ),
            )
        finally:
            module.os.open = original_open
            module.os.fstat = original_fstat
        if child_descriptor is None:
            raise AssertionError("child directory descriptor was not captured")
        try:
            original_fstat(child_descriptor)
        except OSError:
            pass
        else:
            raise AssertionError("child directory descriptor leaked after fstat failure")

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
        if not raced_read:
            raise AssertionError("metadata race injection did not execute")

        overwrite_regular(target, original, expected_mode)
        original_read = module.os.read
        truncated_read = False

        def truncate_during_read(descriptor: int, size: int) -> bytes:
            nonlocal truncated_read
            chunk = original_read(descriptor, size)
            if chunk and not truncated_read:
                truncated_read = True
                overwrite_regular(target, original[:-1], expected_mode)
            return chunk

        module.os.read = truncate_during_read
        try:
            expect_asset_error(
                module,
                "changed while being read",
                lambda: module.verify_extracted_file_witness(
                    staging, relative, record, "truncate race"
                ),
            )
        finally:
            module.os.read = original_read
        if not truncated_read:
            raise AssertionError("truncate race injection did not execute")

        overwrite_regular(target, original, expected_mode)
        original_read = module.os.read
        grown_read = False

        def grow_during_read(descriptor: int, size: int) -> bytes:
            nonlocal grown_read
            chunk = original_read(descriptor, size)
            if chunk and not grown_read:
                grown_read = True
                overwrite_regular(target, original + b"x", expected_mode)
            return chunk

        module.os.read = grow_during_read
        try:
            expect_asset_error(
                module,
                "exceeded its size witness",
                lambda: module.verify_extracted_file_witness(
                    staging, relative, record, "growth race"
                ),
            )
        finally:
            module.os.read = original_read
        if not grown_read:
            raise AssertionError("growth race injection did not execute")
        overwrite_regular(target, original, expected_mode)

        os.chmod(target.parent, 0o755)
        target.unlink()
        os.mkfifo(target, expected_mode)
        os.chmod(target.parent, 0o555)
        expect_asset_error(
            module,
            "regular non-symlink",
            lambda: module.verify_extracted_file_witness(
                staging, relative, record, "FIFO mutation"
            ),
        )
        os.chmod(target.parent, 0o755)
        target.unlink()
        target.write_bytes(original)
        os.chmod(target, expected_mode)
        os.chmod(target.parent, 0o555)

        ancestor_alias = base / "ancestor-alias"
        ancestor_alias.symlink_to(base, target_is_directory=True)
        expect_asset_error(
            module,
            "root must not traverse symlinked ancestors",
            lambda: module.verify_extracted_file_witness(
                ancestor_alias / "staging",
                relative,
                record,
                "symlink ancestor",
            ),
        )
        ancestor_alias.unlink()

        moved_base = base.with_name(f"{base.name}-moved")
        original_read = module.os.read
        renamed_parent = False

        def rename_parent_during_read(descriptor: int, size: int) -> bytes:
            nonlocal renamed_parent
            chunk = original_read(descriptor, size)
            if chunk and not renamed_parent:
                renamed_parent = True
                os.rename(base, moved_base)
            return chunk

        module.os.read = rename_parent_during_read
        try:
            expect_asset_error(
                module,
                "cannot safely read root parent rename",
                lambda: module.verify_extracted_file_witness(
                    staging, relative, record, "root parent rename"
                ),
            )
        finally:
            module.os.read = original_read
            if moved_base.exists():
                os.rename(moved_base, base)
        if not renamed_parent:
            raise AssertionError("root-parent rename injection did not execute")

        original_open = module.os.open
        original_close = module.os.close
        opened_descriptors: list[int] = []
        failed_close_descriptor: int | None = None

        def capture_all_opens(
            path: object,
            flags: int,
            mode: int = 0o777,
            *,
            dir_fd: int | None = None,
        ) -> int:
            descriptor = original_open(path, flags, mode, dir_fd=dir_fd)
            opened_descriptors.append(descriptor)
            return descriptor

        def fail_first_close(descriptor: int) -> None:
            nonlocal failed_close_descriptor
            if failed_close_descriptor is None:
                failed_close_descriptor = descriptor
                raise OSError("injected close failure")
            original_close(descriptor)

        module.os.open = capture_all_opens
        module.os.close = fail_first_close
        try:
            expect_asset_error(
                module,
                "cannot safely close close failure",
                lambda: module.verify_extracted_file_witness(
                    staging, relative, record, "close failure"
                ),
            )
        finally:
            module.os.open = original_open
            module.os.close = original_close
            if failed_close_descriptor is not None:
                original_close(failed_close_descriptor)
        if failed_close_descriptor is None:
            raise AssertionError("close failure injection did not execute")
        for descriptor in opened_descriptors:
            try:
                os.fstat(descriptor)
            except OSError:
                pass
            else:
                raise AssertionError("descriptor leaked after close failure")

        malformed = dict(record, unexpected=True)
        expect_asset_error(
            module,
            "witness fields",
            lambda: module.verify_extracted_file_witness(
                staging, relative, malformed, "unknown witness field"
            ),
        )
        for field in ("size", "mode"):
            bool_record = dict(record)
            bool_record[field] = True
            expect_asset_error(
                module,
                f"{field} witness is invalid",
                lambda bool_record=bool_record, field=field:
                    module.verify_extracted_file_witness(
                        staging,
                        relative,
                        bool_record,
                        f"boolean {field}",
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

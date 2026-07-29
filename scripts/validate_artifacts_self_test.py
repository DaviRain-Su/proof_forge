#!/usr/bin/env python3
"""Independent self-test for validate_artifacts.exact_physical_closure (S7c).

Synthesizes temp trees and invokes the shared helper exported by
validate_artifacts.py — does not reimplement closure logic.
"""

from __future__ import annotations

import os
import stat
import sys
import tempfile
from pathlib import Path

# Import the production helper (same process; no network).
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

import validate_artifacts as va  # noqa: E402


def _fail(msg: str) -> None:
    raise AssertionError(msg)


def _expect_exit(label: str, needle: str, fn) -> None:
    try:
        fn()
    except SystemExit as exc:
        text = str(exc)
        if needle not in text:
            _fail(f"{label}: expected {needle!r} in {text!r}")
        return
    _fail(f"{label}: expected SystemExit containing {needle!r}")


def _write(path: Path, body: str = "x\n") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")


def test_happy_flat() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "b.txt")
        _write(root / "manifest.json", "{}\n")
        _write(root / "evidence.json", "{}\n")
        va.exact_physical_closure(
            root,
            {"a.txt", "b.txt", "manifest.json", "evidence.json"},
            label="happy-flat",
        )


def test_happy_nested() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "top.json")
        _write(root / "relations" / "r0" / "src" / "main.nr")
        _write(root / "relations" / "r0" / "Nargo.toml")
        _write(root / "manifest.json", "{}\n")
        _write(root / "evidence.json", "{}\n")
        files = {
            "top.json",
            "relations/r0/src/main.nr",
            "relations/r0/Nargo.toml",
            "manifest.json",
            "evidence.json",
        }
        va.exact_physical_closure(root, files, label="happy-nested")


def test_missing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "manifest.json")
        _write(root / "evidence.json")
        _expect_exit(
            "missing",
            "missing regular file",
            lambda: va.exact_physical_closure(
                root, {"a.txt", "b.txt", "manifest.json", "evidence.json"}, label="missing"
            ),
        )


def test_unlisted() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "extra.txt")
        _write(root / "manifest.json")
        _write(root / "evidence.json")
        _expect_exit(
            "unlisted",
            "unexpected file",
            lambda: va.exact_physical_closure(
                root, {"a.txt", "manifest.json", "evidence.json"}, label="unlisted"
            ),
        )


def test_extra_dir() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "manifest.json")
        _write(root / "evidence.json")
        (root / "junk").mkdir()
        _expect_exit(
            "extra-dir",
            "unexpected directory",
            lambda: va.exact_physical_closure(
                root, {"a.txt", "manifest.json", "evidence.json"}, label="extra-dir"
            ),
        )


def test_symlink_file() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "manifest.json")
        _write(root / "evidence.json")
        os.symlink("a.txt", root / "link.txt")
        _expect_exit(
            "symlink-file",
            "symbolic link",
            lambda: va.exact_physical_closure(
                root,
                {"a.txt", "link.txt", "manifest.json", "evidence.json"},
                label="symlink-file",
            ),
        )


def test_symlink_dir() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "manifest.json")
        _write(root / "evidence.json")
        os.symlink(".", root / "loop")
        _expect_exit(
            "symlink-dir",
            "symbolic link",
            lambda: va.exact_physical_closure(
                root, {"a.txt", "manifest.json", "evidence.json"}, label="symlink-dir"
            ),
        )


def test_fifo() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "manifest.json")
        _write(root / "evidence.json")
        fifo = root / "pipe.fifo"
        os.mkfifo(fifo)
        assert stat.S_ISFIFO(os.lstat(fifo).st_mode)
        _expect_exit(
            "fifo",
            "non-regular",
            lambda: va.exact_physical_closure(
                root, {"a.txt", "manifest.json", "evidence.json"}, label="fifo"
            ),
        )


def test_unlisted_extra_sidecar_name() -> None:
    """Unlisted extra root file (not envelope name-collision policy).

    Logical base-vs-sidecar collision remains Lean-only; see
    Tests/Materialization/EngineeringDiskClosureV1.lean sidecar-collide and
    publisher dual-defense extras named evidence.json/manifest.json.
    """
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "manifest.json")
        _write(root / "evidence.json")
        _write(root / "other.json")
        _expect_exit(
            "unlisted-extra",
            "unexpected file",
            lambda: va.exact_physical_closure(
                root, {"a.txt", "manifest.json", "evidence.json"}, label="unlisted-extra"
            ),
        )


def test_evidence_sidecar_symlink() -> None:
    """Envelope: evidence.json must be a real regular file, not a symlink."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "manifest.json")
        os.symlink("a.txt", root / "evidence.json")
        _expect_exit(
            "evidence-symlink",
            "symbolic link",
            lambda: va.exact_physical_closure(
                root,
                {"a.txt", "manifest.json", "evidence.json"},
                label="evidence-symlink",
            ),
        )


def test_manifest_as_directory() -> None:
    """Envelope: manifest.json must be a regular file, not a directory."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "evidence.json")
        (root / "manifest.json").mkdir()
        _expect_exit(
            "manifest-as-dir",
            "unexpected directory",
            lambda: va.exact_physical_closure(
                root,
                {"a.txt", "manifest.json", "evidence.json"},
                label="manifest-as-dir",
            ),
        )


def test_dir_entry_cap_many_unlisted() -> None:
    """Many unlisted root files trip per-directory entry cap before walk fan-out."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "a.txt")
        _write(root / "manifest.json")
        _write(root / "evidence.json")
        # Expected direct children = 3; slack = MAX_DIR_ENTRY_SLACK.
        for i in range(100):
            _write(root / f"unlisted-{i}.txt")
        _expect_exit(
            "dir-entry-cap",
            "too many directory entries",
            lambda: va.exact_physical_closure(
                root, {"a.txt", "manifest.json", "evidence.json"}, label="dir-entry-cap"
            ),
        )


def test_limits_file_count() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        # Logical over-limit: helper rejects before walk when expected set is huge.
        huge = {f"f{i}.txt" for i in range(va.MAX_CLOSURE_FILES + 1)}
        _expect_exit(
            "file-count",
            "too many closure files",
            lambda: va.exact_physical_closure(root, huge, label="file-count"),
        )


def test_limits_file_size() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        big = root / "big.bin"
        # Sparse file slightly over 64 MiB.
        with open(big, "wb") as fh:
            fh.truncate(va.MAX_CLOSURE_FILE_BYTES + 1)
        _write(root / "manifest.json")
        _write(root / "evidence.json")
        _expect_exit(
            "file-size",
            "file exceeds size limit",
            lambda: va.exact_physical_closure(
                root, {"big.bin", "manifest.json", "evidence.json"}, label="file-size"
            ),
        )


def test_limits_total_size() -> None:
    """Several under-per-file sparse files whose sum exceeds 256 MiB total."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        chunk = 53 * 1024 * 1024  # 53 MiB each; 5 × 53 = 265 MiB > 256 MiB
        names = [f"chunk{i}.bin" for i in range(5)]
        for name in names:
            with open(root / name, "wb") as fh:
                fh.truncate(chunk)
        _write(root / "manifest.json")
        _write(root / "evidence.json")
        expected = set(names) | {"manifest.json", "evidence.json"}
        _expect_exit(
            "total-size",
            "total closure size exceeds limit",
            lambda: va.exact_physical_closure(root, expected, label="total-size"),
        )


def main() -> None:
    test_happy_flat()
    test_happy_nested()
    test_missing()
    test_unlisted()
    test_extra_dir()
    test_symlink_file()
    test_symlink_dir()
    test_fifo()
    test_unlisted_extra_sidecar_name()
    test_evidence_sidecar_symlink()
    test_manifest_as_directory()
    test_dir_entry_cap_many_unlisted()
    test_limits_file_count()
    test_limits_file_size()
    test_limits_total_size()
    print("validate_artifacts_self_test: ok")


if __name__ == "__main__":
    main()

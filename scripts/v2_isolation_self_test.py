#!/usr/bin/env python3
"""Synthetic single-mutation acceptance for ``TST-ISO-001``."""

from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Callable


CHECKER_PATH = Path(__file__).with_name("v2_isolation.py")
FORBIDDEN_CHECKOUT = "/parent/proof_forge"


def load_checker() -> ModuleType:
    if not CHECKER_PATH.is_file():
        raise AssertionError(
            "RED: scripts/v2_isolation.py has not implemented TST-ISO-001"
        )
    spec = importlib.util.spec_from_file_location(
        "proof_forge_v2_isolation_checker",
        CHECKER_PATH,
    )
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load the exact sibling isolation checker")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")


def baseline(root: Path) -> None:
    write(
        root / "lakefile.lean",
        """import Lake
open Lake DSL

package «proof-forge-next» where
  version := v!"0.1.0"

@[default_target]
lean_lib ProofForgeV2 where
  roots := #[`ProofForgeV2]

lean_lib ProofForgeV2Tests where
  roots := #[`Tests]

lean_exe proof_forge_next where
  exeName := "proof-forge-next"
  root := `ProofForgeV2.CLI.Main

lean_exe proof_forge_next_tests where
  exeName := "proof-forge-next-tests"
  root := `Tests
""",
    )
    write(
        root / "lake-manifest.json",
        json.dumps(
            {
                "version": "1.2.0",
                "packagesDir": ".lake/packages",
                "packages": [],
                "name": "«proof-forge-next»",
                "lakeDir": ".lake",
                "fixedToolchain": False,
            },
            indent=2,
            ensure_ascii=False,
        ) + "\n",
    )
    write(root / "lean-toolchain", "leanprover/lean4:v4.31.0\n")
    write(root / "justfile", "build:\n    lake build ProofForgeV2 proof_forge_next\n")
    write(root / "ProofForgeV2.lean", "import ProofForgeV2.CLI.Main\n")
    write(
        root / "ProofForgeV2/CLI/Main.lean",
        "namespace ProofForgeV2.CLI\n\ndef main : IO Unit := pure ()\n\nend ProofForgeV2.CLI\n",
    )
    write(root / "ProofForgeV2/ActiveField.lean", "def active := true\n")
    write(root / "Tests.lean", "def main : IO Unit := pure ()\n")


def replace(path: Path, old: str, new: str) -> None:
    body = path.read_text(encoding="utf-8")
    if old not in body:
        raise AssertionError(f"fixture replacement source is absent: {old!r}")
    path.write_text(body.replace(old, new, 1), encoding="utf-8")


def expect_rejected(
    checker: ModuleType,
    label: str,
    mutation: Callable[[Path], None],
) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-v2-isolation-negative-") as temp:
        root = Path(temp) / "product"
        baseline(root)
        mutation(root)
        try:
            checker.check_product_tree(root, FORBIDDEN_CHECKOUT)
        except checker.IsolationError:
            return
        raise AssertionError(f"negative mutation was accepted: {label}")


def expect_git_tree_rejected(checker: ModuleType, label: str, mode: bytes) -> None:
    payload = mode + b" blob " + (b"0" * 40) + b"\tlegacy\x00"
    try:
        checker.check_git_tree_records(payload)
    except checker.IsolationError:
        return
    raise AssertionError(f"negative Git tree mutation was accepted: {label}")


def main() -> int:
    checker = load_checker()
    with tempfile.TemporaryDirectory(prefix="pf-v2-isolation-positive-") as temp:
        root = Path(temp) / "product"
        baseline(root)
        checker.check_product_tree(root, FORBIDDEN_CHECKOUT)

    mutations: tuple[tuple[str, Callable[[Path], None]], ...] = (
        ("missing lakefile", lambda root: (root / "lakefile.lean").unlink()),
        ("missing manifest", lambda root: (root / "lake-manifest.json").unlink()),
        ("missing toolchain", lambda root: (root / "lean-toolchain").unlink()),
        ("missing lowercase justfile", lambda root: (root / "justfile").rename(root / "Justfile")),
        ("missing library root marker", lambda root: (root / "ProofForgeV2.lean").unlink()),
        ("missing CLI root marker", lambda root: (root / "ProofForgeV2/CLI/Main.lean").unlink()),
        ("package drift", lambda root: replace(root / "lakefile.lean", "package «proof-forge-next»", "package proof_forge_next")),
        ("library drift", lambda root: replace(root / "lakefile.lean", "lean_lib ProofForgeV2", "lean_lib ProofForge")),
        ("library root drift", lambda root: replace(root / "lakefile.lean", "roots := #[`ProofForgeV2]", "roots := #[`ProofForge]")),
        ("legacy extra library root", lambda root: replace(root / "lakefile.lean", "roots := #[`ProofForgeV2]", "roots := #[`ProofForgeV2, `ProofForge]")),
        ("legacy extra library", lambda root: write(root / "lakefile.lean", (root / "lakefile.lean").read_text(encoding="utf-8") + "\nlean_lib ProofForge where\n  roots := #[`ProofForge]\n")),
        ("executable target drift", lambda root: replace(root / "lakefile.lean", "lean_exe proof_forge_next", "lean_exe proof_forge")),
        ("executable filename drift", lambda root: replace(root / "lakefile.lean", 'exeName := "proof-forge-next"', 'exeName := "proof-forge"')),
        ("executable root drift", lambda root: replace(root / "lakefile.lean", "root := `ProofForgeV2.CLI.Main", "root := `ProofForge.CLI.Main")),
        ("manifest name drift", lambda root: replace(root / "lake-manifest.json", "«proof-forge-next»", "proof_forge_next")),
        ("parent require", lambda root: write(root / "lakefile.lean", (root / "lakefile.lean").read_text(encoding="utf-8") + '\nrequire parent from "../parent"\n')),
        ("relative local require", lambda root: write(root / "lakefile.lean", (root / "lakefile.lean").read_text(encoding="utf-8") + '\nrequire sibling from "sibling"\n')),
        ("multiline local require", lambda root: write(root / "lakefile.lean", (root / "lakefile.lean").read_text(encoding="utf-8") + '\nrequire parent from\n  "../parent"\n')),
        ("bare local Git require", lambda root: write(root / "lakefile.lean", (root / "lakefile.lean").read_text(encoding="utf-8") + '\nrequire sibling from git "sibling"\n')),
        ("absolute local Git require", lambda root: write(root / "lakefile.lean", (root / "lakefile.lean").read_text(encoding="utf-8") + '\nrequire sibling from git "/tmp/sibling"\n')),
        ("manifest path dependency", lambda root: replace(root / "lake-manifest.json", '"packages": []', '"packages": [{"type":"path","name":"parent","url":"../parent"}]')),
        ("manifest bare Git dependency", lambda root: replace(root / "lake-manifest.json", '"packages": []', '"packages": [{"type":"git","name":"sibling","url":"sibling"}]')),
        ("manifest parent Git subdirectory", lambda root: replace(root / "lake-manifest.json", '"packages": []', '"packages": [{"type":"git","name":"dep","url":"https://example.invalid/dep.git","subDir":"../sibling"}]')),
        ("legacy import", lambda root: write(root / "ProofForgeV2/Legacy.lean", "import ProofForge.Backend\n")),
        ("public legacy import outside library", lambda root: write(root / "Examples/Legacy.lean", "public import ProofForge.Backend\n")),
        ("active module import", lambda root: write(root / "Tests/Legacy.lean", "import active.ProofForge\n")),
        ("bare active module import", lambda root: write(root / "Tests/Legacy.lean", "import active\n")),
        ("multiline active module import", lambda root: write(root / "Tests/Legacy.lean", "import\n  active\n")),
        ("active fallback", lambda root: write(root / "ProofForgeV2/Legacy.lean", 'def fallback := "active/ProofForge.lean"\n')),
        ("product symlink", lambda root: (root / "ProofForgeV2/Linked.lean").symlink_to(root / "ProofForgeV2.lean")),
        ("submodule marker", lambda root: write(root / ".gitmodules", "[submodule \"legacy\"]\n\tpath = legacy\n")),
        ("active archive leakage", lambda root: write(root / "active/ProofForge.lean", "def legacy := true\n")),
        ("git metadata leakage", lambda root: write(root / ".git/config", "[core]\n")),
        ("lake cache leakage", lambda root: write(root / ".lake/build/cache", "old\n")),
        ("build output leakage", lambda root: write(root / "build/old.olean", "old\n")),
        ("old binary leakage", lambda root: write(root / "ProofForgeV2/old.wasm", "old\n")),
        ("absolute checkout path", lambda root: write(root / "ProofForgeV2/Path.lean", f'def oldRoot := "{FORBIDDEN_CHECKOUT}/active"\n')),
        ("absolute checkout path in justfile", lambda root: write(root / "justfile", f'build:\n    lake --dir {FORBIDDEN_CHECKOUT} build\n')),
    )
    for label, mutation in mutations:
        expect_rejected(checker, label, mutation)
    checker.check_git_tree_records(
        b"100644 blob " + (b"0" * 40) + b"\tlakefile.lean\x00"
    )
    expect_git_tree_rejected(checker, "tracked symlink", b"120000")
    expect_git_tree_rejected(checker, "tracked submodule", b"160000")

    print(f"v2-isolation-self-test: ok ({len(mutations) + 2} mutations)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        raise SystemExit(f"v2-isolation-self-test: {error}")

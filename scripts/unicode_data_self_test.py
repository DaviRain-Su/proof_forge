#!/usr/bin/env python3
"""Self-tests for scripts/generate_unicode_data.py (Unicode 17.0.0 pin).

Covers:
  - pinned size/SHA-256 verification
  - missing and tampered input fail-closed (zero output)
  - deterministic repeated Lean emission
  - NormalizationTest.txt parse + pure-table NFC/NFD oracle consistency
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import traceback
from pathlib import Path
from types import ModuleType
from typing import Callable, Tuple


ROOT = Path(__file__).resolve().parents[1]
GENERATOR_PATH = ROOT / "scripts" / "generate_unicode_data.py"
DEFAULT_LOCK = ROOT / "unicode.lock.json"
DEFAULT_INPUT = ROOT / "build" / "unicode-input" / "17.0.0"
CHECKED_IN_OUTPUT = ROOT / "ProofForgeV2" / "Core" / "UnicodeData.lean"


def load_generator() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "proof_forge_generate_unicode_data",
        GENERATOR_PATH,
    )
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load generate_unicode_data.py")
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves forward annotations through sys.modules while the
    # imported module is executing. Mirror normal import machinery here.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def expect_fail(
    label: str,
    fn: Callable[[], object],
    code_prefix: str,
) -> None:
    try:
        fn()
    except Exception as error:  # noqa: BLE001 — generator raises typed errors
        code = getattr(error, "code", "")
        text = f"{code}: {error}" if code else str(error)
        if code_prefix not in text and code != code_prefix:
            raise AssertionError(
                f"{label}: expected error containing {code_prefix!r}, got {text!r}"
            ) from error
        return
    raise AssertionError(f"{label}: expected failure {code_prefix}")


def copy_pinned_inputs(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for name in (
        "UnicodeData.txt",
        "CompositionExclusions.txt",
        "NormalizationTest.txt",
    ):
        shutil.copy2(source / name, destination / name)


def test_pinned_inputs(gen: ModuleType, input_dir: Path, lock_path: Path) -> None:
    inputs = gen.load_pinned_inputs(input_dir, lock_path)
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    expect(inputs.unicode_version == lock["unicodeVersion"], "unicode version pin")
    expect(
        inputs.normalization_annex == lock["normalizationAnnex"],
        "normalization annex pin",
    )
    for entry in lock["files"]:
        name = entry["name"]
        path = input_dir / name
        expect(path.is_file(), f"{name} present")
        expect(path.stat().st_size == entry["size"], f"{name} size pin")
        expect(sha256_file(path) == entry["sha256"], f"{name} digest pin")
        expect(inputs.digests[name] == entry["sha256"], f"{name} loaded digest")
        expect(inputs.sizes[name] == entry["size"], f"{name} loaded size")


def test_missing_input(gen: ModuleType, input_dir: Path, lock_path: Path) -> None:
    for name in (
        "UnicodeData.txt",
        "CompositionExclusions.txt",
        "NormalizationTest.txt",
    ):
        with tempfile.TemporaryDirectory(prefix="pf-unicode-missing-") as temporary:
            base = Path(temporary)
            copy_pinned_inputs(input_dir, base)
            (base / name).unlink()
            out = base / "out.lean"
            expect_fail(
                f"missing {name}",
                lambda: gen.generate(base, lock_path, out),
                "PF-UNICODE-INPUT-MISSING",
            )
            expect(not out.exists(), f"missing {name} must leave zero output")


def test_tampered_size(gen: ModuleType, input_dir: Path, lock_path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-unicode-size-") as temporary:
        base = Path(temporary)
        copy_pinned_inputs(input_dir, base)
        target = base / "CompositionExclusions.txt"
        target.write_bytes(target.read_bytes() + b"\n")
        out = base / "out.lean"
        expect_fail(
            "tampered size",
            lambda: gen.generate(base, lock_path, out),
            "PF-UNICODE-INPUT-SIZE",
        )
        expect(not out.exists(), "size mismatch must leave zero output")


def test_tampered_digest(gen: ModuleType, input_dir: Path, lock_path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="pf-unicode-digest-") as temporary:
        base = Path(temporary)
        copy_pinned_inputs(input_dir, base)
        target = base / "NormalizationTest.txt"
        data = bytearray(target.read_bytes())
        # Flip a byte without changing length.
        index = min(100, len(data) - 1)
        data[index] = (data[index] + 1) % 256
        target.write_bytes(bytes(data))
        out = base / "out.lean"
        expect_fail(
            "tampered digest",
            lambda: gen.generate(base, lock_path, out),
            "PF-UNICODE-INPUT-DIGEST",
        )
        expect(not out.exists(), "digest mismatch must leave zero output")


def test_closed_lock_schema(gen: ModuleType, lock_path: Path) -> None:
    original_text = lock_path.read_text(encoding="utf-8")
    original = json.loads(original_text)

    def mutated(label: str, transform: Callable[[dict], None]) -> None:
        with tempfile.TemporaryDirectory(prefix="pf-unicode-lock-") as temporary:
            path = Path(temporary) / "unicode.lock.json"
            value = json.loads(json.dumps(original))
            transform(value)
            path.write_text(json.dumps(value), encoding="utf-8")
            expect_fail(label, lambda: gen.load_lock(path), "PF-UNICODE-LOCK-SCHEMA")

    def raw_mutated(label: str, value: str) -> None:
        with tempfile.TemporaryDirectory(prefix="pf-unicode-lock-raw-") as temporary:
            path = Path(temporary) / "unicode.lock.json"
            path.write_text(value, encoding="utf-8")
            expect_fail(label, lambda: gen.load_lock(path), "PF-UNICODE-LOCK-JSON")

    mutated("unknown root field", lambda value: value.__setitem__("extra", True))
    mutated("wrong Unicode version", lambda value: value.__setitem__("unicodeVersion", "18.0.0"))
    mutated(
        "wrong normalization annex",
        lambda value: value.__setitem__("normalizationAnnex", "UAX #15 revision 58"),
    )
    mutated("wrong generator", lambda value: value.__setitem__("generator", "other.py"))
    mutated("wrong generated output", lambda value: value.__setitem__("generatedOutputs", []))
    mutated("runtime dependency", lambda value: value.__setitem__("runtimeDependencies", ["icu"]))
    mutated("duplicate input", lambda value: value["files"].__setitem__(1, value["files"][0]))
    mutated("extra input", lambda value: value["files"].append(dict(value["files"][0])))
    mutated("wrong input order", lambda value: value["files"].reverse())
    mutated(
        "wrong input URL",
        lambda value: value["files"][0].__setitem__("url", "https://example.invalid/UnicodeData.txt"),
    )
    mutated("unknown input field", lambda value: value["files"][0].__setitem__("extra", True))
    raw_mutated(
        "duplicate root key",
        original_text.replace(
            '"unicodeVersion": "17.0.0",',
            '"unicodeVersion": "18.0.0",\n  "unicodeVersion": "17.0.0",',
            1,
        ),
    )
    raw_mutated(
        "duplicate nested key",
        original_text.replace(
            '"name": "UnicodeData.txt",',
            '"name": "Wrong.txt",\n      "name": "UnicodeData.txt",',
            1,
        ),
    )


def test_deterministic_emit(gen: ModuleType, input_dir: Path, lock_path: Path) -> str:
    with tempfile.TemporaryDirectory(prefix="pf-unicode-det-") as temporary:
        base = Path(temporary)
        out1 = base / "a" / "UnicodeData.lean"
        out2 = base / "b" / "UnicodeData.lean"
        _inputs1, tables1, lean1 = gen.generate(input_dir, lock_path, out1)
        _inputs2, tables2, lean2 = gen.generate(input_dir, lock_path, out2)
        bytes1 = out1.read_bytes()
        bytes2 = out2.read_bytes()
        expect(bytes1 == bytes2, "Lean output must be byte-identical across runs")
        expect(out1.stat().st_mode & 0o777 == 0o644, "Lean output mode must be 0644")
        expect(out2.stat().st_mode & 0o777 == 0o644, "repeated output mode must be 0644")
        expect(lean1 == lean2, "in-memory Lean source must be deterministic")
        expect(bytes1 == lean1.encode("utf-8"), "file bytes match emitted string")
        expect(CHECKED_IN_OUTPUT.is_file(), "checked-in UnicodeData.lean must exist")
        expect(
            bytes1 == CHECKED_IN_OUTPUT.read_bytes(),
            "checked-in UnicodeData.lean must exactly match pinned regeneration",
        )
        expect(len(tables1.ccc) == len(tables2.ccc), "ccc count stable")
        expect(
            len(tables1.canonical_decomp) == len(tables2.canonical_decomp),
            "decomp count stable",
        )
        expect(
            len(tables1.composition) == len(tables2.composition),
            "composition count stable",
        )
        # Structural invariants (Lean emission sorts; in-memory maps need not).
        expect(all(1 <= cls <= 255 for cls in tables1.ccc.values()), "ccc nonzero 1..255")
        expect(
            all(mapping != (cp,) for cp, mapping in tables1.canonical_decomp.items()),
            "decomp table omits identity rows",
        )
        expect(
            len(tables1.composition_exclusions)
            == len(set(tables1.composition_exclusions)),
            "exclusions unique",
        )
        # Lean tables appear sorted by construction in emit_lean.
        for label, needle in (
            ("ccc", "canonicalCombiningClassTable"),
            ("decomp", "canonicalDecompositionTable"),
            ("comp", "compositionPairTable"),
            ("excl", "compositionExclusionTable"),
            ("cc", "generalCategoryCcRanges"),
        ):
            expect(needle in lean1, f"{label} table present")
        expect("AUTO-GENERATED" in lean1, "generated banner present")
        expect('unicodeVersion : String := "17.0.0"' in lean1, "version constant")
        expect("UAX #15 revision 57" in lean1, "annex constant")
        expect("canonicalCombiningClassTable" in lean1, "ccc table symbol")
        expect("canonicalDecompositionTable" in lean1, "decomp table symbol")
        expect("compositionPairTable" in lean1, "composition table symbol")
        expect("compositionExclusionTable" in lean1, "exclusion table symbol")
        expect("generalCategoryCcRanges" in lean1, "Cc ranges symbol")
        expect("hangulSBase" in lean1, "Hangul constants present")
        # The generated module may carry the Unicode license URL in a comment,
        # but it must not embed source/download locations or executable network
        # configuration.
        expect("www.unicode.org/Public/" not in lean1, "no UCD download URLs in Lean data")
        expect("url :=" not in lean1, "no runtime URL fields in Lean data")
        expect("Unicode License v3" in lean1, "generated data carries Unicode notice")
        return lean1


def test_normalization_oracle(
    gen: ModuleType, input_dir: Path, lock_path: Path
) -> Tuple[int, int, int]:
    inputs = gen.load_pinned_inputs(input_dir, lock_path)
    tables = gen.extract_tables(inputs)
    vectors = gen.parse_normalization_test(inputs.normalization_test)
    expect(len(vectors) > 1000, f"expected large corpus, got {len(vectors)}")
    complement_count = gen.verify_normalization_oracle(tables, vectors)

    # Spot checks for Hangul and combining order (still from official vectors).
    hangul_hits = 0
    for vector in vectors:
        if any(0xAC00 <= cp < 0xAC00 + 11172 for cp in vector.source):
            hangul_hits += 1
            break
    expect(hangul_hits >= 1, "corpus includes Hangul coverage")
    expect(complement_count > 1000, "C3 assigned-code-point complement must be exercised")
    return len(vectors), len(tables.composition), complement_count


def test_no_network_and_no_unicodedata_import(gen: ModuleType) -> None:
    source = GENERATOR_PATH.read_text(encoding="utf-8")
    banned = (
        "import urllib",
        "from urllib",
        "import requests",
        "import http",
        "from http",
        "import unicodedata",
        "from unicodedata",
        "socket.",
        "urlopen",
    )
    for token in banned:
        expect(token not in source, f"generator must not use {token!r}")


def resolve_input_dir() -> Path:
    env = os.environ.get("PROOF_FORGE_UNICODE_INPUT")
    if env:
        return Path(env)
    if DEFAULT_INPUT.is_dir():
        return DEFAULT_INPUT
    raise AssertionError(
        "Unicode input directory not found; set PROOF_FORGE_UNICODE_INPUT "
        f"or materialize the pinned files under {DEFAULT_INPUT}"
    )


def main() -> int:
    print("unicode_data_self_test: loading generator")
    gen = load_generator()
    test_no_network_and_no_unicodedata_import(gen)

    lock_path = Path(os.environ.get("PROOF_FORGE_UNICODE_LOCK", str(DEFAULT_LOCK)))
    input_dir = resolve_input_dir()
    print(f"unicode_data_self_test: lock={lock_path}")
    print(f"unicode_data_self_test: input_dir={input_dir}")

    print("unicode_data_self_test: pinned inputs")
    test_pinned_inputs(gen, input_dir, lock_path)

    print("unicode_data_self_test: missing input fail-closed")
    test_missing_input(gen, input_dir, lock_path)

    print("unicode_data_self_test: tampered size fail-closed")
    test_tampered_size(gen, input_dir, lock_path)

    print("unicode_data_self_test: tampered digest fail-closed")
    test_tampered_digest(gen, input_dir, lock_path)

    print("unicode_data_self_test: closed lock schema")
    test_closed_lock_schema(gen, lock_path)

    print("unicode_data_self_test: deterministic emit")
    lean = test_deterministic_emit(gen, input_dir, lock_path)
    print(f"unicode_data_self_test: lean_bytes={len(lean.encode('utf-8'))}")

    print("unicode_data_self_test: NormalizationTest oracle (full corpus)")
    vector_count, composition_count, complement_count = test_normalization_oracle(
        gen, input_dir, lock_path
    )
    print(
        f"unicode_data_self_test: vectors={vector_count} "
        f"composition_pairs={composition_count} "
        f"c3_complement={complement_count}"
    )

    print("unicode_data_self_test: ok")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:  # noqa: BLE001
        traceback.print_exc()
        raise SystemExit(1)

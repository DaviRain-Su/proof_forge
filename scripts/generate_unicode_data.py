#!/usr/bin/env python3
"""Offline Unicode 17.0.0 UCD → pure Lean table generator for ProofForge V2.

Accepts only local UCD files that match unicode.lock.json (byte size + SHA-256).
Does not download, and does not call ambient ICU/Foundation/unicodedata for
generation. A pure table-driven NFC oracle is used only by the self-test suite.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Mapping, Optional, Sequence, Set, Tuple


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCK = ROOT / "unicode.lock.json"
DEFAULT_OUTPUT = ROOT / "ProofForgeV2" / "Core" / "UnicodeData.lean"

EXPECTED_UNICODE_VERSION = "17.0.0"
EXPECTED_NORMALIZATION_ANNEX = "UAX #15 revision 57"
EXPECTED_LOCK_KEYS = {
    "schemaVersion",
    "unicodeVersion",
    "normalizationAnnex",
    "files",
    "generator",
    "generatedOutputs",
    "runtimeDependencies",
}
EXPECTED_FILE_NAMES = (
    "UnicodeData.txt",
    "CompositionExclusions.txt",
    "NormalizationTest.txt",
)
EXPECTED_FILE_KEYS = {"name", "url", "size", "sha256"}
EXPECTED_GENERATOR = "scripts/generate_unicode_data.py"
EXPECTED_GENERATED_OUTPUTS = ["ProofForgeV2/Core/UnicodeData.lean"]

# Hangul syllable algorithmic constants (UAX #15).
SBASE = 0xAC00
LBASE = 0x1100
VBASE = 0x1161
TBASE = 0x11A7
LCOUNT = 19
VCOUNT = 21
TCOUNT = 28
NCOUNT = VCOUNT * TCOUNT  # 588
SCOUNT = LCOUNT * NCOUNT  # 11172


class UnicodeGenError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def fail(code: str, message: str) -> None:
    raise UnicodeGenError(code, message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _closed_json_object(pairs: Sequence[Tuple[str, object]]) -> dict:
    result: dict = {}
    for key, value in pairs:
        if key in result:
            fail("PF-UNICODE-LOCK-JSON", f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def load_lock(path: Path) -> dict:
    try:
        raw = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_closed_json_object,
        )
    except OSError as error:
        fail("PF-UNICODE-LOCK-IO", f"cannot read lock {path}: {error}")
    except json.JSONDecodeError as error:
        fail("PF-UNICODE-LOCK-JSON", f"invalid lock JSON {path}: {error}")
    if not isinstance(raw, dict):
        fail("PF-UNICODE-LOCK-SCHEMA", "lock root must be an object")
    if set(raw) != EXPECTED_LOCK_KEYS:
        fail(
            "PF-UNICODE-LOCK-SCHEMA",
            "lock fields must be exact: " + ", ".join(sorted(EXPECTED_LOCK_KEYS)),
        )
    schema_version = raw.get("schemaVersion")
    if type(schema_version) is not int or schema_version != 1:
        fail("PF-UNICODE-LOCK-SCHEMA", "schemaVersion must be 1")
    if raw.get("unicodeVersion") != EXPECTED_UNICODE_VERSION:
        fail(
            "PF-UNICODE-LOCK-SCHEMA",
            f"unicodeVersion must be {EXPECTED_UNICODE_VERSION}",
        )
    if raw.get("normalizationAnnex") != EXPECTED_NORMALIZATION_ANNEX:
        fail(
            "PF-UNICODE-LOCK-SCHEMA",
            f"normalizationAnnex must be {EXPECTED_NORMALIZATION_ANNEX}",
        )
    if raw.get("generator") != EXPECTED_GENERATOR:
        fail("PF-UNICODE-LOCK-SCHEMA", f"generator must be {EXPECTED_GENERATOR}")
    if raw.get("generatedOutputs") != EXPECTED_GENERATED_OUTPUTS:
        fail(
            "PF-UNICODE-LOCK-SCHEMA",
            "generatedOutputs must contain only the canonical UnicodeData.lean path",
        )
    if raw.get("runtimeDependencies") != []:
        fail("PF-UNICODE-LOCK-SCHEMA", "runtimeDependencies must be empty")
    files = raw.get("files")
    if not isinstance(files, list) or len(files) != len(EXPECTED_FILE_NAMES):
        fail("PF-UNICODE-LOCK-SCHEMA", "files must contain the three exact UCD inputs")
    names = [entry.get("name") if isinstance(entry, dict) else None for entry in files]
    if names != list(EXPECTED_FILE_NAMES):
        fail(
            "PF-UNICODE-LOCK-SCHEMA",
            "files must use the canonical unique order: " + ", ".join(EXPECTED_FILE_NAMES),
        )
    for entry in files:
        if not isinstance(entry, dict):
            fail("PF-UNICODE-LOCK-SCHEMA", "files[] entries must be objects")
        if set(entry) != EXPECTED_FILE_KEYS:
            fail(
                "PF-UNICODE-LOCK-SCHEMA",
                f"{entry.get('name', 'files[]')}: fields must be name,url,size,sha256",
            )
        if not isinstance(entry["name"], str) or not entry["name"]:
            fail("PF-UNICODE-LOCK-SCHEMA", "files[].name must be non-empty string")
        expected_url = (
            f"https://www.unicode.org/Public/{EXPECTED_UNICODE_VERSION}/ucd/{entry['name']}"
        )
        if entry["url"] != expected_url:
            fail(
                "PF-UNICODE-LOCK-SCHEMA",
                f"{entry['name']}: url must be {expected_url}",
            )
        if isinstance(entry["size"], bool) or not isinstance(entry["size"], int) or entry["size"] < 0:
            fail("PF-UNICODE-LOCK-SCHEMA", f"{entry['name']}: size must be non-negative int")
        digest = entry["sha256"]
        if not isinstance(digest, str) or len(digest) != 64 or any(
            c not in "0123456789abcdef" for c in digest
        ):
            fail("PF-UNICODE-LOCK-SCHEMA", f"{entry['name']}: sha256 must be 64 lowercase hex")
    return raw


def read_pinned_file(path: Path, expected_size: int, expected_sha256: str) -> bytes:
    if not path.is_file():
        fail("PF-UNICODE-INPUT-MISSING", f"missing required input: {path}")
    try:
        data = path.read_bytes()
    except OSError as error:
        fail("PF-UNICODE-INPUT-IO", f"cannot read {path}: {error}")
    if len(data) != expected_size:
        fail(
            "PF-UNICODE-INPUT-SIZE",
            f"{path.name}: size {len(data)} != pinned {expected_size}",
        )
    digest = sha256_bytes(data)
    if digest != expected_sha256:
        fail(
            "PF-UNICODE-INPUT-DIGEST",
            f"{path.name}: sha256 {digest} != pinned {expected_sha256}",
        )
    return data


@dataclass(frozen=True)
class PinnedInputs:
    unicode_version: str
    normalization_annex: str
    unicode_data: bytes
    composition_exclusions: bytes
    normalization_test: bytes
    digests: Mapping[str, str]
    sizes: Mapping[str, int]


def load_pinned_inputs(input_dir: Path, lock_path: Path) -> PinnedInputs:
    lock = load_lock(lock_path)
    by_name = {entry["name"]: entry for entry in lock["files"]}
    required = ("UnicodeData.txt", "CompositionExclusions.txt", "NormalizationTest.txt")
    for name in required:
        if name not in by_name:
            fail("PF-UNICODE-LOCK-SCHEMA", f"lock missing required file {name}")
    loaded: Dict[str, bytes] = {}
    digests: Dict[str, str] = {}
    sizes: Dict[str, int] = {}
    for name in required:
        entry = by_name[name]
        data = read_pinned_file(input_dir / name, entry["size"], entry["sha256"])
        loaded[name] = data
        digests[name] = entry["sha256"]
        sizes[name] = entry["size"]
    return PinnedInputs(
        unicode_version=lock["unicodeVersion"],
        normalization_annex=lock["normalizationAnnex"],
        unicode_data=loaded["UnicodeData.txt"],
        composition_exclusions=loaded["CompositionExclusions.txt"],
        normalization_test=loaded["NormalizationTest.txt"],
        digests=digests,
        sizes=sizes,
    )


def parse_codepoint(token: str, where: str) -> int:
    token = token.strip()
    if not token:
        fail("PF-UNICODE-PARSE", f"{where}: empty code point")
    try:
        value = int(token, 16)
    except ValueError as error:
        fail("PF-UNICODE-PARSE", f"{where}: invalid code point {token!r}: {error}")
    if value < 0 or value > 0x10FFFF:
        fail("PF-UNICODE-PARSE", f"{where}: code point out of range {token}")
    return value


@dataclass
class UcdTables:
    """Extracted canonical normalization tables (excluding Hangul algorithmics)."""

    # code → nonzero canonical combining class
    ccc: Dict[int, int] = field(default_factory=dict)
    # code → full recursive canonical decomposition (Hangul syllables omitted)
    canonical_decomp: Dict[int, Tuple[int, ...]] = field(default_factory=dict)
    # composition exclusions (explicit list only; Full_Composition_Exclusion derived at use)
    composition_exclusions: Set[int] = field(default_factory=set)
    # (starter, second) → composite primary composites (non-Hangul)
    composition: Dict[Tuple[int, int], int] = field(default_factory=dict)
    # merged inclusive ranges for General_Category=Cc
    cc_ranges: List[Tuple[int, int]] = field(default_factory=list)
    # assigned Unicode scalar values used for UAX #15 C3 complement checks
    assigned_codepoints: Set[int] = field(default_factory=set)


def _is_hangul_syllable(cp: int) -> bool:
    return SBASE <= cp < SBASE + SCOUNT


def parse_unicode_data(data: bytes) -> Tuple[Dict[int, int], Dict[int, Tuple[int, ...]], List[Tuple[int, int]], Dict[int, str]]:
    """Return (ccc, raw_canonical_decomp, cc_ranges, general_category)."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        fail("PF-UNICODE-PARSE", f"UnicodeData.txt is not UTF-8: {error}")

    ccc: Dict[int, int] = {}
    raw_decomp: Dict[int, Tuple[int, ...]] = {}
    category: Dict[int, str] = {}
    cc_points: List[int] = []

    # Range expansion state for First/Last pairs.
    pending_first: Optional[Tuple[int, str, str, int, Optional[Tuple[int, ...]]]] = None

    for line_no, line in enumerate(text.splitlines(), start=1):
        if not line or line.startswith("#"):
            continue
        fields = line.split(";")
        if len(fields) < 15:
            fail("PF-UNICODE-PARSE", f"UnicodeData.txt:{line_no}: expected >=15 fields")
        cp = parse_codepoint(fields[0], f"UnicodeData.txt:{line_no}")
        name = fields[1]
        gen_cat = fields[2]
        try:
            combining = int(fields[3])
        except ValueError as error:
            fail("PF-UNICODE-PARSE", f"UnicodeData.txt:{line_no}: CCC: {error}")
        if combining < 0 or combining > 255:
            fail("PF-UNICODE-PARSE", f"UnicodeData.txt:{line_no}: CCC out of range")
        decomp_field = fields[5].strip()
        raw_mapping: Optional[Tuple[int, ...]] = None
        if decomp_field:
            if decomp_field.startswith("<"):
                # Compatibility decomposition — ignore mapping body for canonical tables.
                raw_mapping = None
            else:
                parts = decomp_field.split()
                raw_mapping = tuple(
                    parse_codepoint(part, f"UnicodeData.txt:{line_no}:decomp")
                    for part in parts
                )

        if name.endswith(", First>"):
            pending_first = (cp, name, gen_cat, combining, raw_mapping)
            continue
        if name.endswith(", Last>"):
            if pending_first is None:
                fail("PF-UNICODE-PARSE", f"UnicodeData.txt:{line_no}: Last without First")
            first_cp, first_name, first_cat, first_ccc, first_map = pending_first
            pending_first = None
            if first_cat != gen_cat or first_ccc != combining or first_map != raw_mapping:
                fail(
                    "PF-UNICODE-PARSE",
                    f"UnicodeData.txt:{line_no}: First/Last property mismatch",
                )
            for value in range(first_cp, cp + 1):
                category[value] = gen_cat
                if combining != 0:
                    ccc[value] = combining
                if raw_mapping is not None and not _is_hangul_syllable(value):
                    raw_decomp[value] = raw_mapping
                if gen_cat == "Cc":
                    cc_points.append(value)
            continue

        if pending_first is not None:
            fail("PF-UNICODE-PARSE", f"UnicodeData.txt:{line_no}: expected Last after First")

        category[cp] = gen_cat
        if combining != 0:
            ccc[cp] = combining
        if raw_mapping is not None and not _is_hangul_syllable(cp):
            raw_decomp[cp] = raw_mapping
        if gen_cat == "Cc":
            cc_points.append(cp)

    if pending_first is not None:
        fail("PF-UNICODE-PARSE", "UnicodeData.txt: trailing First without Last")

    cc_ranges = _merge_ranges(sorted(set(cc_points)))
    return ccc, raw_decomp, cc_ranges, category


def _merge_ranges(sorted_points: Sequence[int]) -> List[Tuple[int, int]]:
    if not sorted_points:
        return []
    ranges: List[Tuple[int, int]] = []
    start = prev = sorted_points[0]
    for value in sorted_points[1:]:
        if value == prev + 1:
            prev = value
            continue
        ranges.append((start, prev))
        start = prev = value
    ranges.append((start, prev))
    return ranges


def parse_composition_exclusions(data: bytes) -> Set[int]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        fail("PF-UNICODE-PARSE", f"CompositionExclusions.txt is not UTF-8: {error}")
    exclusions: Set[int] = set()
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.split("#", 1)[0].strip()
        if not stripped:
            continue
        # Single code point per line (no ranges in this file for 17.0.0).
        exclusions.add(parse_codepoint(stripped, f"CompositionExclusions.txt:{line_no}"))
    return exclusions


def expand_canonical_decomp(
    raw: Mapping[int, Tuple[int, ...]],
) -> Dict[int, Tuple[int, ...]]:
    """Fully expand recursive canonical decompositions (Hangul handled separately)."""
    memo: Dict[int, Tuple[int, ...]] = {}

    def expand(cp: int) -> Tuple[int, ...]:
        if cp in memo:
            return memo[cp]
        if _is_hangul_syllable(cp):
            memo[cp] = hangul_decompose(cp)
            return memo[cp]
        mapping = raw.get(cp)
        if mapping is None:
            memo[cp] = (cp,)
            return memo[cp]
        expanded: List[int] = []
        for part in mapping:
            expanded.extend(expand(part))
        result = tuple(expanded)
        memo[cp] = result
        return result

    full: Dict[int, Tuple[int, ...]] = {}
    for cp in raw:
        full[cp] = expand(cp)
    return full


def hangul_decompose(cp: int) -> Tuple[int, ...]:
    s_index = cp - SBASE
    if s_index < 0 or s_index >= SCOUNT:
        return (cp,)
    l = LBASE + s_index // NCOUNT
    v = VBASE + (s_index % NCOUNT) // TCOUNT
    t = TBASE + s_index % TCOUNT
    if t == TBASE:
        return (l, v)
    return (l, v, t)


def hangul_compose_pair(first: int, second: int) -> Optional[int]:
    # L + V → LV
    if LBASE <= first < LBASE + LCOUNT and VBASE <= second < VBASE + VCOUNT:
        l_index = first - LBASE
        v_index = second - VBASE
        return SBASE + (l_index * VCOUNT + v_index) * TCOUNT
    # LV + T → LVT
    s_index = first - SBASE
    if 0 <= s_index < SCOUNT and s_index % TCOUNT == 0:
        if TBASE < second < TBASE + TCOUNT:
            t_index = second - TBASE
            return first + t_index
    return None


def build_composition_table(
    raw_decomp: Mapping[int, Tuple[int, ...]],
    ccc: Mapping[int, int],
    exclusions: Set[int],
) -> Dict[Tuple[int, int], int]:
    """Primary composites from singleton-length-2 canonical decompositions."""
    composition: Dict[Tuple[int, int], int] = {}
    for composite, mapping in raw_decomp.items():
        if len(mapping) != 2:
            continue
        if composite in exclusions:
            continue
        first, second = mapping
        # First character of a primary composite must be a starter (CCC=0).
        if ccc.get(first, 0) != 0:
            continue
        if _is_hangul_syllable(composite):
            continue
        composition[(first, second)] = composite
    return composition


def extract_tables(inputs: PinnedInputs) -> UcdTables:
    ccc, raw_decomp, cc_ranges, category = parse_unicode_data(inputs.unicode_data)
    exclusions = parse_composition_exclusions(inputs.composition_exclusions)
    full_decomp = expand_canonical_decomp(raw_decomp)
    # Store only non-identity full decompositions that came from UCD mappings
    # (Hangul syllables remain algorithmic and are not table rows).
    table_decomp = {
        cp: mapping
        for cp, mapping in full_decomp.items()
        if mapping != (cp,) and not _is_hangul_syllable(cp)
    }
    composition = build_composition_table(raw_decomp, ccc, exclusions)
    return UcdTables(
        ccc=ccc,
        canonical_decomp=table_decomp,
        composition_exclusions=exclusions,
        composition=composition,
        cc_ranges=cc_ranges,
        assigned_codepoints={
            cp for cp in category if not (0xD800 <= cp <= 0xDFFF)
        },
    )


# ---------------------------------------------------------------------------
# Pure NFC oracle (table-driven; used by generator self-test only)
# ---------------------------------------------------------------------------


def _get_ccc(cp: int, tables: UcdTables) -> int:
    return tables.ccc.get(cp, 0)


def _decompose_char(cp: int, tables: UcdTables) -> Tuple[int, ...]:
    if _is_hangul_syllable(cp):
        return hangul_decompose(cp)
    return tables.canonical_decomp.get(cp, (cp,))


def canonical_decompose_sequence(codes: Sequence[int], tables: UcdTables) -> List[int]:
    out: List[int] = []
    for cp in codes:
        out.extend(_decompose_char(cp, tables))
    # Canonical ordering: stable sort by CCC, starters (0) are segment barriers.
    return _canonical_reorder(out, tables)


def _canonical_reorder(codes: List[int], tables: UcdTables) -> List[int]:
    if len(codes) <= 1:
        return list(codes)
    result = list(codes)
    # Bubble sort as specified by UAX #15 D109 / implementations: only swap
    # adjacent pairs where ccc(a) > ccc(b) > 0.
    changed = True
    while changed:
        changed = False
        for i in range(len(result) - 1):
            a = _get_ccc(result[i], tables)
            b = _get_ccc(result[i + 1], tables)
            if a != 0 and b != 0 and a > b:
                result[i], result[i + 1] = result[i + 1], result[i]
                changed = True
    return result


def _compose_pair(first: int, second: int, tables: UcdTables) -> Optional[int]:
    hangul = hangul_compose_pair(first, second)
    if hangul is not None:
        return hangul
    return tables.composition.get((first, second))


def canonical_compose(codes: Sequence[int], tables: UcdTables) -> List[int]:
    """UAX #15 composition algorithm over a canonically ordered NFD sequence."""
    if not codes:
        return []
    out: List[int] = []
    starter_pos = -1
    last_class = -1
    for ch in codes:
        ch_class = _get_ccc(ch, tables)
        if starter_pos >= 0:
            # Blocked iff some character B between starter and ch has
            # ccc(B) == 0 or ccc(B) >= ccc(ch). Tracked via last_class.
            # last_class == 0 means the previous emitted char was the starter
            # (or a successful composition back onto the starter slot).
            blocked = last_class != 0 and last_class >= ch_class
            if not blocked:
                composite = _compose_pair(out[starter_pos], ch, tables)
                if composite is not None:
                    out[starter_pos] = composite
                    # Combining mark consumed; last_class unchanged.
                    continue
        if ch_class == 0:
            starter_pos = len(out)
            last_class = 0
        else:
            last_class = ch_class
        out.append(ch)
    return out


def to_nfd(codes: Sequence[int], tables: UcdTables) -> List[int]:
    return canonical_decompose_sequence(codes, tables)


def to_nfc(codes: Sequence[int], tables: UcdTables) -> List[int]:
    return canonical_compose(to_nfd(codes, tables), tables)


# ---------------------------------------------------------------------------
# NormalizationTest parsing
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class NormalizationVector:
    source: Tuple[int, ...]
    nfc: Tuple[int, ...]
    nfd: Tuple[int, ...]
    nfkc: Tuple[int, ...]
    nfkd: Tuple[int, ...]
    part: str
    line_no: int


def parse_codepoint_sequence(field: str, where: str) -> Tuple[int, ...]:
    field = field.strip()
    if not field:
        return ()
    return tuple(parse_codepoint(part, where) for part in field.split())


def parse_normalization_test(data: bytes) -> List[NormalizationVector]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        fail("PF-UNICODE-PARSE", f"NormalizationTest.txt is not UTF-8: {error}")
    vectors: List[NormalizationVector] = []
    part = "unknown"
    for line_no, line in enumerate(text.splitlines(), start=1):
        if not line:
            continue
        if line.startswith("@Part"):
            part = line[1:].split("#", 1)[0].strip()
            continue
        if line.startswith("#"):
            continue
        body = line.split("#", 1)[0].rstrip()
        if not body:
            continue
        fields = body.split(";")
        # Format: c1;c2;c3;c4;c5;  (trailing empty after final semicolon)
        if len(fields) < 5:
            fail(
                "PF-UNICODE-PARSE",
                f"NormalizationTest.txt:{line_no}: expected >=5 fields, got {len(fields)}",
            )
        source = parse_codepoint_sequence(fields[0], f"NormalizationTest.txt:{line_no}:c1")
        nfc = parse_codepoint_sequence(fields[1], f"NormalizationTest.txt:{line_no}:c2")
        nfd = parse_codepoint_sequence(fields[2], f"NormalizationTest.txt:{line_no}:c3")
        nfkc = parse_codepoint_sequence(fields[3], f"NormalizationTest.txt:{line_no}:c4")
        nfkd = parse_codepoint_sequence(fields[4], f"NormalizationTest.txt:{line_no}:c5")
        vectors.append(
            NormalizationVector(
                source=source,
                nfc=nfc,
                nfd=nfd,
                nfkc=nfkc,
                nfkd=nfkd,
                part=part,
                line_no=line_no,
            )
        )
    if not vectors:
        fail("PF-UNICODE-PARSE", "NormalizationTest.txt produced zero vectors")
    return vectors


def verify_normalization_oracle(
    tables: UcdTables,
    vectors: Sequence[NormalizationVector],
) -> int:
    """Check every NFC/NFD invariant required by NormalizationTest.txt."""
    for vector in vectors:
        got_nfd = tuple(to_nfd(vector.source, tables))
        if got_nfd != vector.nfd:
            fail(
                "PF-UNICODE-ORACLE",
                f"NFD mismatch line {vector.line_no} part {vector.part}: "
                f"got {got_nfd!r} want {vector.nfd!r}",
            )
        got_nfc = tuple(to_nfc(vector.source, tables))
        if got_nfc != vector.nfc:
            fail(
                "PF-UNICODE-ORACLE",
                f"NFC mismatch line {vector.line_no} part {vector.part}: "
                f"got {got_nfc!r} want {vector.nfc!r}",
            )
        # Conformance: c2 == toNFC(c1) == toNFC(c2) == toNFC(c3)
        if tuple(to_nfc(vector.nfc, tables)) != vector.nfc:
            fail(
                "PF-UNICODE-ORACLE",
                f"NFC not idempotent on c2 line {vector.line_no}",
            )
        if tuple(to_nfc(vector.nfd, tables)) != vector.nfc:
            fail(
                "PF-UNICODE-ORACLE",
                f"toNFC(c3) != c2 line {vector.line_no}",
            )
        if tuple(to_nfd(vector.nfc, tables)) != vector.nfd:
            fail(
                "PF-UNICODE-ORACLE",
                f"toNFD(c2) != c3 line {vector.line_no}",
            )
        if tuple(to_nfd(vector.nfd, tables)) != vector.nfd:
            fail(
                "PF-UNICODE-ORACLE",
                f"NFD not idempotent on c3 line {vector.line_no}",
            )
        # c4/c5 are compatibility-normalized fixtures, but the conformance
        # clauses still require canonical NFC/NFD over those exact sequences.
        # This does not require implementing NFKC/NFKD.
        if tuple(to_nfc(vector.nfkc, tables)) != vector.nfkc:
            fail(
                "PF-UNICODE-ORACLE",
                f"toNFC(c4) != c4 line {vector.line_no}",
            )
        if tuple(to_nfc(vector.nfkd, tables)) != vector.nfkc:
            fail(
                "PF-UNICODE-ORACLE",
                f"toNFC(c5) != c4 line {vector.line_no}",
            )
        if tuple(to_nfd(vector.nfkc, tables)) != vector.nfkd:
            fail(
                "PF-UNICODE-ORACLE",
                f"toNFD(c4) != c5 line {vector.line_no}",
            )
        if tuple(to_nfd(vector.nfkd, tables)) != vector.nfkd:
            fail(
                "PF-UNICODE-ORACLE",
                f"toNFD(c5) != c5 line {vector.line_no}",
            )

    part1_listed: Set[int] = set()
    for vector in vectors:
        if vector.part == "Part1":
            if len(vector.source) != 1:
                fail(
                    "PF-UNICODE-ORACLE",
                    f"Part1 line {vector.line_no} must contain one source code point",
                )
            part1_listed.add(vector.source[0])

    # UAX #15 conformance clause C3 also covers every assigned scalar not
    # explicitly listed in Part1. NFC/NFD must leave each such scalar alone.
    complement = tables.assigned_codepoints - part1_listed
    for cp in sorted(complement):
        if tuple(to_nfc((cp,), tables)) != (cp,):
            fail(
                "PF-UNICODE-ORACLE",
                f"C3 complement NFC identity failed for U+{cp:04X}",
            )
        if tuple(to_nfd((cp,), tables)) != (cp,):
            fail(
                "PF-UNICODE-ORACLE",
                f"C3 complement NFD identity failed for U+{cp:04X}",
            )
    return len(complement)


# ---------------------------------------------------------------------------
# Lean emission
# ---------------------------------------------------------------------------


def _hex_u32(value: int) -> str:
    return f"0x{value:04X}" if value <= 0xFFFF else f"0x{value:06X}"


def emit_lean(inputs: PinnedInputs, tables: UcdTables) -> str:
    """Emit deterministic Lean source for ProofForgeV2.Core.UnicodeData."""
    lines: List[str] = []
    lines.append("/-")
    lines.append("  AUTO-GENERATED by scripts/generate_unicode_data.py")
    lines.append("  DO NOT EDIT BY HAND.")
    lines.append("  Derived from Unicode Data Files.")
    lines.append("  Copyright © 1991-2025 Unicode, Inc. All rights reserved.")
    lines.append("  Use is governed by the Unicode License v3:")
    lines.append("  https://www.unicode.org/license.txt")
    lines.append(f"  Unicode version : {inputs.unicode_version}")
    lines.append(f"  Normalization   : {inputs.normalization_annex}")
    lines.append(f"  UnicodeData.txt SHA-256: {inputs.digests['UnicodeData.txt']}")
    lines.append(
        f"  CompositionExclusions.txt SHA-256: {inputs.digests['CompositionExclusions.txt']}"
    )
    lines.append(
        f"  NormalizationTest.txt SHA-256: {inputs.digests['NormalizationTest.txt']}"
    )
    lines.append("-/")
    lines.append("namespace ProofForgeV2.Core.UnicodeData")
    lines.append("")
    # Array notation elaborates as a nested syntax tree; the pinned Unicode
    # tables exceed Lean's default recursion budget even though lookups are
    # iterative at runtime.
    lines.append("set_option maxRecDepth 100000")
    lines.append("")
    lines.append(f'def unicodeVersion : String := "{inputs.unicode_version}"')
    lines.append(f'def normalizationAnnex : String := "{inputs.normalization_annex}"')
    lines.append("")
    lines.append("structure SourceFilePin where")
    lines.append("  name : String")
    lines.append("  size : Nat")
    lines.append("  sha256 : String")
    lines.append("  deriving Repr, Inhabited")
    lines.append("")
    lines.append("def sourceFilePins : Array SourceFilePin := #[")
    pin_rows = []
    for name in (
        "UnicodeData.txt",
        "CompositionExclusions.txt",
        "NormalizationTest.txt",
    ):
        pin_rows.append(
            "  { name := \"%s\", size := %d, sha256 := \"%s\" }"
            % (name, inputs.sizes[name], inputs.digests[name])
        )
    lines.append(",\n".join(pin_rows))
    lines.append("]")
    lines.append("")

    # CCC table: sorted by code point.
    ccc_items = sorted(tables.ccc.items())
    lines.append("/-- Nonzero canonical combining classes, sorted by code point. -/")
    lines.append("def canonicalCombiningClassTable : Array (UInt32 × UInt8) := #[")
    ccc_rows = [
        f"  ({_hex_u32(cp)}, {cls})" for cp, cls in ccc_items
    ]
    lines.append(",\n".join(ccc_rows))
    lines.append("]")
    lines.append("")

    # Canonical decomposition table: sorted by code point.
    decomp_items = sorted(tables.canonical_decomp.items())
    lines.append("structure CanonicalDecomposition where")
    lines.append("  code : UInt32")
    lines.append("  mapping : Array UInt32")
    lines.append("  deriving Repr, Inhabited")
    lines.append("")
    lines.append(
        "/-- Fully expanded non-Hangul canonical decompositions, sorted by code point. -/"
    )
    lines.append("def canonicalDecompositionTable : Array CanonicalDecomposition := #[")
    decomp_rows = []
    for cp, mapping in decomp_items:
        map_lit = ", ".join(_hex_u32(x) for x in mapping)
        decomp_rows.append(
            f"  {{ code := {_hex_u32(cp)}, mapping := #[{map_lit}] }}"
        )
    lines.append(",\n".join(decomp_rows))
    lines.append("]")
    lines.append("")

    # Composition exclusions sorted.
    excl = sorted(tables.composition_exclusions)
    lines.append("/-- Explicit CompositionExclusions.txt code points, sorted. -/")
    lines.append("def compositionExclusionTable : Array UInt32 := #[")
    excl_rows = [f"  {_hex_u32(cp)}" for cp in excl]
    lines.append(",\n".join(excl_rows))
    lines.append("]")
    lines.append("")

    # Composition pairs sorted by (first, second).
    comp_items = sorted(tables.composition.items(), key=lambda kv: (kv[0][0], kv[0][1], kv[1]))
    lines.append("structure CompositionPair where")
    lines.append("  first : UInt32")
    lines.append("  second : UInt32")
    lines.append("  composite : UInt32")
    lines.append("  deriving Repr, Inhabited")
    lines.append("")
    lines.append(
        "/-- Primary composition pairs (non-Hangul), sorted by (first, second). -/"
    )
    lines.append("def compositionPairTable : Array CompositionPair := #[")
    comp_rows = [
        f"  {{ first := {_hex_u32(a)}, second := {_hex_u32(b)}, composite := {_hex_u32(c)} }}"
        for (a, b), c in comp_items
    ]
    lines.append(",\n".join(comp_rows))
    lines.append("]")
    lines.append("")

    # Cc ranges.
    lines.append("structure CodepointRange where")
    lines.append("  start : UInt32")
    lines.append("  endInclusive : UInt32")
    lines.append("  deriving Repr, Inhabited")
    lines.append("")
    lines.append("/-- Merged inclusive General_Category=Cc ranges, sorted. -/")
    lines.append("def generalCategoryCcRanges : Array CodepointRange := #[")
    cc_rows = [
        f"  {{ start := {_hex_u32(a)}, endInclusive := {_hex_u32(b)} }}"
        for a, b in tables.cc_ranges
    ]
    lines.append(",\n".join(cc_rows))
    lines.append("]")
    lines.append("")

    # Hangul constants for pure-Lean algorithmic composition/decomposition.
    lines.append("/-- Hangul syllable base (UAX #15). -/")
    lines.append(f"def hangulSBase : UInt32 := {_hex_u32(SBASE)}")
    lines.append(f"def hangulLBase : UInt32 := {_hex_u32(LBASE)}")
    lines.append(f"def hangulVBase : UInt32 := {_hex_u32(VBASE)}")
    lines.append(f"def hangulTBase : UInt32 := {_hex_u32(TBASE)}")
    lines.append(f"def hangulLCount : Nat := {LCOUNT}")
    lines.append(f"def hangulVCount : Nat := {VCOUNT}")
    lines.append(f"def hangulTCount : Nat := {TCOUNT}")
    lines.append(f"def hangulNCount : Nat := {NCOUNT}")
    lines.append(f"def hangulSCount : Nat := {SCOUNT}")
    lines.append("")
    lines.append(
        f"/-- Table row counts for TST/generator alignment (Unicode {inputs.unicode_version}). -/"
    )
    lines.append(f"def canonicalCombiningClassCount : Nat := {len(ccc_items)}")
    lines.append(f"def canonicalDecompositionCount : Nat := {len(decomp_items)}")
    lines.append(f"def compositionExclusionCount : Nat := {len(excl)}")
    lines.append(f"def compositionPairCount : Nat := {len(comp_items)}")
    lines.append(f"def generalCategoryCcRangeCount : Nat := {len(tables.cc_ranges)}")
    lines.append("")
    lines.append("end ProofForgeV2.Core.UnicodeData")
    lines.append("")
    return "\n".join(lines)


def write_output(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Deterministic trailing newline.
    data = content.encode("utf-8")
    if not data.endswith(b"\n"):
        data += b"\n"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o644)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    except BaseException:
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass
        raise


def generate(
    input_dir: Path,
    lock_path: Path,
    output_path: Path,
    *,
    verify_oracle: bool = False,
) -> Tuple[PinnedInputs, UcdTables, str]:
    inputs = load_pinned_inputs(input_dir, lock_path)
    tables = extract_tables(inputs)
    if verify_oracle:
        vectors = parse_normalization_test(inputs.normalization_test)
        verify_normalization_oracle(tables, vectors)
    lean = emit_lean(inputs, tables)
    write_output(output_path, lean)
    return inputs, tables, lean


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate ProofForgeV2/Core/UnicodeData.lean from pinned local UCD files.",
    )
    parser.add_argument(
        "--input-dir",
        type=Path,
        required=True,
        help="Directory containing UnicodeData.txt, CompositionExclusions.txt, NormalizationTest.txt",
    )
    parser.add_argument(
        "--lock",
        type=Path,
        default=DEFAULT_LOCK,
        help=f"Path to unicode.lock.json (default: {DEFAULT_LOCK})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Lean output path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--verify-oracle",
        action="store_true",
        help="Also run pure-table NFC/NFD oracle against NormalizationTest.txt before emit",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Write Lean source to stdout instead of --output",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    try:
        # Fail closed before any output write: pin verify → extract → optional oracle.
        inputs = load_pinned_inputs(args.input_dir, args.lock)
        tables = extract_tables(inputs)
        if args.verify_oracle:
            vectors = parse_normalization_test(inputs.normalization_test)
            verify_normalization_oracle(tables, vectors)
        lean = emit_lean(inputs, tables)
        if args.stdout:
            sys.stdout.write(lean)
            if not lean.endswith("\n"):
                sys.stdout.write("\n")
        else:
            write_output(args.output, lean)
            print(
                f"wrote {args.output} "
                f"(ccc={len(tables.ccc)} decomp={len(tables.canonical_decomp)} "
                f"comp={len(tables.composition)} excl={len(tables.composition_exclusions)} "
                f"cc_ranges={len(tables.cc_ranges)})",
                file=sys.stderr,
            )
        return 0
    except UnicodeGenError as error:
        print(f"{error.code}: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

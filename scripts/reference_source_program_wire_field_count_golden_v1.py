#!/usr/bin/env python3
"""Independent PA125 field-count negative golden descriptor for D1-PA-126."""

import hashlib
import importlib.util
from pathlib import Path
import sys

BASE_SCRIPT = Path(__file__).with_name("reference_source_program_wire_golden_v1.py")
SPEC = importlib.util.spec_from_file_location("pa125_source_wire_golden", BASE_SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load the PA125 independent oracle")
base = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(base)

SCHEMA = "proof-forge.source-program-field-count-golden-prerequisite.v1"
SCOPE = "pa125-base-first-occurrence-exact-field-count"
BASE_CASE = "full-tag-valid-v1"
BASE_FILE = "testdata/golden/source-program-v1/full-tag-v1/canonical.bin"
BASE_SHA256 = "5d38eaca671e503ae50a517cc8ffaddba20b370d11da22f6bcdb807089aa64ce"
PACKAGE = Path("testdata/golden/source-program-v1/field-count-v1")
MANIFEST = "manifest.json"


def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)


def encode_with_offsets(value, offset, records):
    if isinstance(value, bytes):
        return value
    if isinstance(value, base.ArrayValue):
        output = base.u32le(len(value.items))
        for item in value.items:
            output += encode_with_offsets(item, offset + len(output), records)
        return output
    if isinstance(value, base.OptionValue):
        if value.value is None:
            return b"\x00"
        return b"\x01" + encode_with_offsets(value.value, offset + 1, records)
    if isinstance(value, base.Tagged):
        tag_bytes = value.tag.encode("ascii")
        field_offset = offset + 4 + len(tag_bytes)
        records.append((value.tag, field_offset, len(value.fields)))
        output = base.u32le(len(tag_bytes)) + tag_bytes + base.u16le(len(value.fields))
        for _field_name, field_value in value.fields:
            output += encode_with_offsets(field_value, offset + len(output), records)
        return output
    raise RuntimeError(f"unknown PA125 value type {type(value)!r}")


def case_id(tag, expected, mutated):
    normalized = tag.lower().replace(".", "-")
    return f"field-count-{normalized}-{expected}-to-{mutated}"


def expected_descriptor(root):
    base.validate_checked_in(root)
    expected_binary, _base_document = base.expected_package()
    prefix = base.qualified(base.MODULE) + base.qualified(base.PROGRAM_IDENTITY, 2)
    records = []
    encoded = prefix + encode_with_offsets(base.build_fixture(), len(prefix), records)
    require(encoded == expected_binary, "offset encoder differs from PA125 canonical bytes")
    require(hashlib.sha256(encoded).hexdigest() == BASE_SHA256, "PA125 base digest")

    first = {}
    for tag, offset, count in records:
        first.setdefault(tag, (offset, count))
    require(set(first) == base.WIRE_TAGS and len(first) == 84, "closed 84-tag selection")
    for tag, (offset, count) in first.items():
        require(0 <= offset <= len(encoded) - 2, f"offset range for {tag}")
        require(int.from_bytes(encoded[offset:offset + 2], "little") == count,
                f"base field count for {tag}")
        require(offset == min(candidate_offset for candidate_tag, candidate_offset, _count in records
                              if candidate_tag == tag), f"lowest offset for {tag}")

    nullary = sum(count == 0 for _offset, count in first.values())
    positive = len(first) - nullary
    require(nullary == 28 and positive == 56, "28/56 field-count partition")
    mutations = []
    for tag in sorted(first):
        offset, expected = first[tag]
        mutated_counts = [1] if expected == 0 else [expected - 1, expected + 1]
        for mutated in mutated_counts:
            mutations.append({
                "caseId": case_id(tag, expected, mutated),
                "expectedCount": expected,
                "expectedError": f"tag '{tag}' must declare {expected} fields",
                "fieldCountOffset": offset,
                "mutatedCount": mutated,
                "tag": tag,
            })
    require(len(mutations) == 140, "140 mutation rows")
    require(mutations == sorted(mutations, key=lambda row: (row["tag"], row["mutatedCount"])),
            "mutation row order")
    require(len({(row["tag"], row["mutatedCount"]) for row in mutations}) == 140,
            "mutation row uniqueness")

    document = {
        "baseCanonicalBytesSha256": "sha256:" + BASE_SHA256,
        "baseCanonicalFile": BASE_FILE,
        "baseCaseId": BASE_CASE,
        "mutationCount": 140,
        "mutations": mutations,
        "nullaryTagCount": 28,
        "positiveFieldTagCount": 56,
        "schema": SCHEMA,
        "scope": SCOPE,
        "tagCount": 84,
    }
    return document


def package_paths(root):
    directory = root / PACKAGE
    return directory, directory / MANIFEST


def validate_checked_in(root):
    document = expected_descriptor(root)
    directory, manifest_path = package_paths(root)
    require(directory.is_dir(), f"missing field-count golden directory: {PACKAGE}")
    require({path.name for path in directory.iterdir()} == {MANIFEST},
            "field-count golden package must contain exactly manifest.json")
    actual = manifest_path.read_bytes()
    require(actual == base.canonical_json(document), "field-count manifest mismatch")
    require(len(actual) <= 128 * 1024, "field-count manifest exceeds frozen byte bound")


def emit(root):
    document = expected_descriptor(root)
    _directory, manifest_path = package_paths(root)
    base.atomic_write(manifest_path, base.canonical_json(document))
    validate_checked_in(root)


def main(argv):
    root = Path(__file__).resolve().parents[1]
    try:
        if argv == ["--emit"]:
            emit(root)
            print("reference_source_program_wire_field_count_golden_v1: emitted 140 84 28 56")
            return 0
        if argv == ["--self-check"]:
            validate_checked_in(root)
            print("reference_source_program_wire_field_count_golden_v1: ok 140 84 28 56")
            return 0
        print("usage: reference_source_program_wire_field_count_golden_v1.py --emit|--self-check",
              file=sys.stderr)
        return 2
    except (OSError, RuntimeError, ValueError) as error:
        print(f"reference_source_program_wire_field_count_golden_v1: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

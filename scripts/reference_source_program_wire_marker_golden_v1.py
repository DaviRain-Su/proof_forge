#!/usr/bin/env python3
"""Independent PA125 Bool/Option marker negative descriptor for D1-PA-127."""

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

SCHEMA = "proof-forge.source-program-marker-golden-prerequisite.v1"
SCOPE = "pa125-base-lowest-bool-option-noncanonical-marker"
BASE_CASE = "full-tag-valid-v1"
BASE_FILE = "testdata/golden/source-program-v1/full-tag-v1/canonical.bin"
BASE_SHA256 = "5d38eaca671e503ae50a517cc8ffaddba20b370d11da22f6bcdb807089aa64ce"
PACKAGE = Path("testdata/golden/source-program-v1/marker-v1")
MANIFEST = "manifest.json"
OPTION_FIELDS = {
    ("Stmt.Assert", "error"),
    ("Stmt.If", "elseBlock"),
    ("Stmt.Let", "typeAnn"),
    ("Stmt.Return", "value"),
}


def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)


def encode_with_offsets(value, offset, records, owner_tag=None, field_name=None):
    if isinstance(value, bytes):
        return value
    if isinstance(value, base.ArrayValue):
        output = base.u32le(len(value.items))
        for item in value.items:
            output += encode_with_offsets(
                item, offset + len(output), records, owner_tag, field_name)
        return output
    if isinstance(value, base.OptionValue):
        marker = 0 if value.value is None else 1
        records.append(("option", owner_tag, field_name, marker, offset))
        if value.value is None:
            return b"\x00"
        return b"\x01" + encode_with_offsets(
            value.value, offset + 1, records, owner_tag, field_name)
    if isinstance(value, base.Tagged):
        tag_bytes = value.tag.encode("ascii")
        output = base.u32le(len(tag_bytes)) + tag_bytes + base.u16le(len(value.fields))
        for index, (child_name, child) in enumerate(value.fields):
            child_offset = offset + len(output)
            if value.tag == "Literal.Bool" and index == 0:
                require(isinstance(child, bytes) and child in (b"\x00", b"\x01"),
                        "PA125 Literal.Bool marker shape")
                records.append(("bool", value.tag, "value", child[0], child_offset))
            output += encode_with_offsets(
                child, child_offset, records, value.tag, child_name)
        return output
    raise RuntimeError(f"unknown PA125 value type {type(value)!r}")


def case_id(kind, owner_tag, field_name, base_marker):
    owner = owner_tag.lower().replace(".", "-")
    return f"marker-{kind}-{owner}-{field_name.lower()}-{base_marker}-to-2"


def expected_descriptor(root):
    base.validate_checked_in(root)
    expected_binary, _base_document = base.expected_package()
    prefix = base.qualified(base.MODULE) + base.qualified(base.PROGRAM_IDENTITY, 2)
    records = []
    encoded = prefix + encode_with_offsets(
        base.build_fixture(), len(prefix), records)
    require(encoded == expected_binary, "offset encoder differs from PA125 canonical bytes")
    require(hashlib.sha256(encoded).hexdigest() == BASE_SHA256, "PA125 base digest")

    bool_records = [record for record in records if record[0] == "bool"]
    option_records = [record for record in records if record[0] == "option"]
    require(len(bool_records) == 25 and len(option_records) == 16,
            "25/16 marker occurrence partition")
    require({(owner, field) for _kind, owner, field, _marker, _offset in option_records}
            == OPTION_FIELDS, "closed option owner/field inventory")

    expected_keys = {
        ("bool", "Literal.Bool", "value", marker) for marker in (0, 1)
    } | {
        ("option", owner, field, marker)
        for owner, field in OPTION_FIELDS for marker in (0, 1)
    }
    selected = {}
    for kind, owner, field, marker, offset in records:
        key = (kind, owner, field, marker)
        selected.setdefault(key, offset)
    require(set(selected) == expected_keys and len(selected) == 10,
            "closed 10-key marker selection")

    mutations = []
    for kind, owner, field, marker in sorted(selected):
        offset = selected[(kind, owner, field, marker)]
        matching_offsets = [record_offset
                            for record_kind, record_owner, record_field,
                            record_marker, record_offset in records
                            if (record_kind, record_owner, record_field, record_marker)
                            == (kind, owner, field, marker)]
        require(offset == min(matching_offsets), f"lowest marker offset for {kind}/{owner}/{field}/{marker}")
        require(0 <= offset < len(encoded) and encoded[offset] == marker,
                f"base marker byte for {kind}/{owner}/{field}/{marker}")
        mutations.append({
            "baseMarker": marker,
            "caseId": case_id(kind, owner, field, marker),
            "expectedError": "invalid bool marker" if kind == "bool"
                             else "invalid option marker",
            "fieldName": field,
            "markerKind": kind,
            "markerOffset": offset,
            "mutatedMarker": 2,
            "ownerTag": owner,
        })
    require(len({row["markerOffset"] for row in mutations}) == 10,
            "marker offsets are not unique")
    require(mutations == sorted(
        mutations,
        key=lambda row: (row["markerKind"], row["ownerTag"],
                         row["fieldName"], row["baseMarker"])),
        "mutation row order")

    return {
        "baseCanonicalBytesSha256": "sha256:" + BASE_SHA256,
        "baseCanonicalFile": BASE_FILE,
        "baseCaseId": BASE_CASE,
        "boolMutationCount": 2,
        "boolOccurrenceCount": 25,
        "mutationCount": 10,
        "mutations": mutations,
        "optionFieldCount": 4,
        "optionMutationCount": 8,
        "optionOccurrenceCount": 16,
        "schema": SCHEMA,
        "scope": SCOPE,
    }


def package_paths(root):
    directory = root / PACKAGE
    return directory, directory / MANIFEST


def validate_checked_in(root):
    document = expected_descriptor(root)
    directory, manifest_path = package_paths(root)
    require(directory.is_dir(), f"missing marker golden directory: {PACKAGE}")
    require({path.name for path in directory.iterdir()} == {MANIFEST},
            "marker golden package must contain exactly manifest.json")
    actual = manifest_path.read_bytes()
    require(actual == base.canonical_json(document), "marker manifest mismatch")
    require(len(actual) <= 32 * 1024, "marker manifest exceeds frozen byte bound")


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
            print("reference_source_program_wire_marker_golden_v1: emitted 10 2 8 25 16")
            return 0
        if argv == ["--self-check"]:
            validate_checked_in(root)
            print("reference_source_program_wire_marker_golden_v1: ok 10 2 8 25 16")
            return 0
        print("usage: reference_source_program_wire_marker_golden_v1.py --emit|--self-check",
              file=sys.stderr)
        return 2
    except (OSError, RuntimeError, ValueError) as error:
        print(f"reference_source_program_wire_marker_golden_v1: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

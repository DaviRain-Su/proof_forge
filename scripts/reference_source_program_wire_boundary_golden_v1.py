#!/usr/bin/env python3
"""Independent PA125 scalar/length/truncation/trailing mutation descriptor."""

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

SCHEMA = "proof-forge.source-program-boundary-golden-prerequisite.v1"
SCOPE = "pa125-base-scalar-length-truncation-trailing"
BASE_CASE = "full-tag-valid-v1"
BASE_FILE = "testdata/golden/source-program-v1/full-tag-v1/canonical.bin"
BASE_SHA256 = "a7075ca364c099e18510c1f5a8961449e3859d6a45fec46820d327a7d095a0d8"
PACKAGE = Path("testdata/golden/source-program-v1/boundary-v1")
MANIFEST = "manifest.json"


def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)


def sha256_wire(payload):
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def encoded_string(value):
    raw = value.encode("utf-8")
    return base.u32le(len(raw)) + raw


def encode_qualified(parts, offset, owner, field, records):
    output = base.u32le(len(parts))
    records.append({
        "kind": "array-count", "offset": offset, "owner": owner,
        "field": field, "value": len(parts),
    })
    for index, part in enumerate(parts):
        raw = part.encode("utf-8")
        child_offset = offset + len(output)
        records.append({
            "kind": "string-length", "offset": child_offset,
            "owner": owner, "field": field, "index": index,
            "value": len(raw), "text": part,
        })
        output += base.u32le(len(raw)) + raw
    return output


def encode_with_offsets(value, offset, records, owner=None, field=None, index=None):
    if isinstance(value, bytes):
        records.append({
            "kind": "scalar-bytes", "offset": offset, "size": len(value),
            "owner": owner, "field": field, "index": index,
            "hex": value.hex(),
        })
        return value
    if isinstance(value, base.ArrayValue):
        output = base.u32le(len(value.items))
        records.append({
            "kind": "array-count", "offset": offset, "owner": owner,
            "field": field, "value": len(value.items),
        })
        for child_index, child in enumerate(value.items):
            output += encode_with_offsets(
                child, offset + len(output), records, owner, field, child_index)
        return output
    if isinstance(value, base.OptionValue):
        marker = 0 if value.value is None else 1
        output = bytes((marker,))
        if value.value is not None:
            output += encode_with_offsets(
                value.value, offset + 1, records, owner, field, 0)
        return output
    if isinstance(value, base.Tagged):
        tag_bytes = value.tag.encode("ascii")
        records.extend((
            {"kind": "tag-length", "offset": offset, "owner": value.tag,
             "field": None, "value": len(tag_bytes)},
            {"kind": "tag-bytes", "offset": offset + 4, "owner": value.tag,
             "field": None, "size": len(tag_bytes), "text": value.tag},
            {"kind": "field-count", "offset": offset + 4 + len(tag_bytes),
             "owner": value.tag, "field": None, "value": len(value.fields)},
        ))
        output = base.u32le(len(tag_bytes)) + tag_bytes + base.u16le(len(value.fields))
        for child_index, (child_field, child) in enumerate(value.fields):
            output += encode_with_offsets(
                child, offset + len(output), records,
                value.tag, child_field, child_index)
        return output
    raise RuntimeError(f"unknown PA125 value type {type(value)!r}")


def selected(records, kind, owner, field=None, occurrence=0):
    matches = [row for row in records
               if row["kind"] == kind and row.get("owner") == owner
               and (field is None or row.get("field") == field)]
    require(len(matches) > occurrence, f"missing offset selection {kind}/{owner}/{field}")
    return matches[occurrence]


def expected_descriptor(root):
    base.validate_checked_in(root)
    expected_binary, _base_document = base.expected_package()
    records = []
    prefix = encode_qualified(base.MODULE, 0, "Root", "moduleName", records)
    prefix += encode_qualified(
        base.PROGRAM_IDENTITY, len(prefix), "Root", "programIdentity", records)
    encoded = prefix + encode_with_offsets(base.build_fixture(), len(prefix), records)
    require(encoded == expected_binary, "offset encoder differs from PA125 canonical bytes")
    require(hashlib.sha256(encoded).hexdigest() == BASE_SHA256, "PA125 base digest")

    mutations = []

    def add(case_id, category, expected_error, offset, remove_length, replacement=b""):
        require(0 <= offset <= len(encoded), f"{case_id}: offset")
        require(0 <= remove_length <= len(encoded) - offset, f"{case_id}: remove range")
        removed = encoded[offset:offset + remove_length]
        mutated = encoded[:offset] + replacement + encoded[offset + remove_length:]
        require(mutated != encoded, f"{case_id}: mutation aliases base")
        mutations.append({
            "caseId": case_id,
            "category": category,
            "expectedError": expected_error,
            "mutatedSha256": sha256_wire(mutated),
            "mutatedSize": len(mutated),
            "offset": offset,
            "removeLength": remove_length,
            "removedSha256": sha256_wire(removed),
            "replacementHex": replacement.hex(),
        })

    # Root truncation and exact-consume boundaries.
    for name, retained, error in (
        ("empty", 0, "truncated"),
        ("u32-one-byte", 1, "truncated"),
        ("u32-three-bytes", 3, "truncated"),
        ("after-module-count", 4, "truncated"),
        ("partial-module-length", 7, "truncated"),
        ("partial-module-value", 13, "string length exceeds remaining"),
        ("final-byte", len(encoded) - 1, "string length exceeds remaining"),
    ):
        add(f"truncate-{name}", "truncation", error,
            retained, len(encoded) - retained)
    integer = selected(records, "scalar-bytes", "Literal.Integer", "")
    retained = integer["offset"] + 31
    add("truncate-u256", "truncation", "truncated",
        retained, len(encoded) - retained)
    add("trailing-one-byte", "trailing", "trailing bytes",
        len(encoded), 0, b"\x00")

    module_count = selected(records, "array-count", "Root", "moduleName")
    identity_count = selected(records, "array-count", "Root", "programIdentity")
    for value in (0, 257, 0xFFFFFFFF):
        add(f"module-component-count-{value}", "component-count",
            "source qualified name must contain 1..256 components",
            module_count["offset"], 4, base.u32le(value))
    for value in (0, 1, 257, 0xFFFFFFFF):
        add(f"program-identity-count-{value}", "component-count",
            "source qualified id must contain 2..256 components",
            identity_count["offset"], 4, base.u32le(value))

    module_length = selected(records, "string-length", "Root", "moduleName")
    identity_length = selected(records, "string-length", "Root", "programIdentity")
    program_name = selected(records, "scalar-bytes", "Program", "name")
    for owner, row in (("module", module_length), ("program-name", program_name)):
        for value in (0, 241, 0xFFFFFFFF):
            add(f"{owner}-length-{value}", "component-length",
                "source name component must contain 1..240 UTF-8 bytes",
                row["offset"], 4, base.u32le(value))

    add("module-invalid-utf8", "unicode", "invalid UTF-8",
        module_length["offset"] + 4, 1, b"\xff")
    add("identity-invalid-utf8", "unicode", "invalid UTF-8",
        identity_length["offset"] + 4, 1, b"\xff")
    add("module-non-nfc", "unicode",
        "string must already be NFC under Unicode 17.0.0",
        module_length["offset"], 4 + len("Golden"), encoded_string("e\u0301"))
    add("module-control", "unicode",
        "source name component must not contain a Cc code point",
        module_length["offset"], 4 + len("Golden"), encoded_string("A\nB"))
    add("module-closing-guillemet", "unicode",
        "source name component must not contain closing guillemet",
        module_length["offset"], 4 + len("Golden"), encoded_string("A\u00bbB"))

    program_tag_length = selected(records, "tag-length", "Program")
    program_tag_bytes = selected(records, "tag-bytes", "Program")
    for value in (0, 22, 0xFFFFFFFF):
        add(f"program-tag-length-{value}", "tag-framing",
            "tag length must be 1..21 bytes",
            program_tag_length["offset"], 4, base.u32le(value))
    add("program-tag-invalid-utf8", "tag-framing", "invalid UTF-8 tag",
        program_tag_bytes["offset"], 1, b"\xff")
    add("program-tag-nonascii", "tag-framing", "tag must be ASCII",
        program_tag_bytes["offset"], 2, "é".encode("utf-8"))

    add("module-identity-mismatch", "identity",
        "program identity must begin with the exact module name components",
        module_length["offset"] + 4, 1, b"X")
    add("program-name-mismatch", "identity",
        "program name must equal the last program identity component",
        program_name["offset"] + 4, 1, b"X")

    program_items = selected(records, "array-count", "Program", "items")
    add("program-items-empty", "array-count", "program items must be nonempty",
        program_items["offset"], 4, base.u32le(0))
    add("program-items-count-max", "array-count", "array count exceeds caller limit",
        program_items["offset"], 4, base.u32le(0xFFFFFFFF))
    for owner, field in (
        ("StructDecl", "fields"), ("EnumDecl", "variants"),
        ("Block", "statements"), ("Expr.Match", "arms"),
        ("Pattern.Constructor", "args"),
    ):
        row = selected(records, "array-count", owner, field)
        slug = owner.lower().replace(".", "-")
        add(f"{slug}-{field.lower()}-count-max", "array-count",
            "array count exceeds caller limit",
            row["offset"], 4, base.u32le(0xFFFFFFFF))

    for tag in ("Type.UInt", "Type.Int"):
        width = selected(records, "scalar-bytes", tag, "width")
        slug = tag.split(".")[1].lower()
        for value in (0, 7, 257, 0xFFFF):
            add(f"{slug}-width-{value}", "integer-width",
                "integer width must be one of 8,16,32,64,128,256",
                width["offset"], 2, base.u16le(value))

    for case_id, owner, field, value, error in (
        ("array-length-4097", "Type.Array", "length", 4097,
         "array length must be 0..4096"),
        ("bytes-length-4097", "Type.Bytes", "length", 4097,
         "bytes length must be 0..4096"),
        ("for-bound-4097", "Stmt.For", "bound", 4097,
         "for bound must be 0..4096"),
    ):
        row = selected(records, "scalar-bytes", owner, field)
        add(case_id, "numeric-bound", error, row["offset"], 4, base.u32le(value))

    literal_string = selected(records, "scalar-bytes", "Literal.String", "")
    add("literal-string-non-nfc", "unicode",
        "string must already be NFC under Unicode 17.0.0",
        literal_string["offset"], literal_string["size"], encoded_string("cafe\u0301"))
    add("literal-string-invalid-utf8", "unicode", "invalid UTF-8",
        literal_string["offset"] + 4, 1, b"\xff")
    add("literal-string-length-max", "string-length",
        "string length exceeds remaining",
        literal_string["offset"], 4, base.u32le(0xFFFFFFFF))

    for owner, field, slug in (
        ("ExtensionReq", "id", "extension"),
        ("ProofDecl", "theorem", "theorem"),
    ):
        row = selected(records, "scalar-bytes", owner, field)
        for value in (0, 1, 257, 0xFFFFFFFF):
            add(f"{slug}-qid-count-{value}", "qualified-id-count",
                "source qualified id must contain 2..256 components",
                row["offset"], 4, base.u32le(value))

    version = selected(records, "scalar-bytes", "ExtensionReq", "version")
    digest = selected(records, "scalar-bytes", "ExtensionReq", "digest")
    field_id = selected(records, "scalar-bytes", "Type.Field", "id")
    add("extension-semver-invalid", "validated-scalar",
        "extension version must use canonical exact SemVer",
        version["offset"] + 8, 1, b"x")
    add("extension-digest-uppercase", "validated-scalar",
        "extension digest must use canonical sha256 spelling",
        digest["offset"] + 11, 1, b"A")
    add("extension-digest-prefix", "validated-scalar",
        "extension digest must use canonical sha256 spelling",
        digest["offset"] + 4, 1, b"X")
    add("field-id-invalid", "validated-scalar",
        "field id must be bn254_fr, bls12_377_fr, or goldilocks",
        field_id["offset"] + 11, 1, b"x")

    mutations.sort(key=lambda row: row["caseId"])
    require(len(mutations) == len({row["caseId"] for row in mutations}),
            "mutation case ids must be unique")
    signatures = {
        (row["offset"], row["removeLength"], row["replacementHex"])
        for row in mutations
    }
    require(len(signatures) == len(mutations), "mutation operations must be unique")
    category_counts = []
    for category in sorted({row["category"] for row in mutations}):
        category_counts.append({
            "category": category,
            "count": sum(row["category"] == category for row in mutations),
        })
    require(len(mutations) == 67, f"expected 67 mutations, found {len(mutations)}")
    require(sum(row["count"] for row in category_counts) == len(mutations),
            "category partition")
    return {
        "baseCanonicalBytesSha256": "sha256:" + BASE_SHA256,
        "baseCanonicalFile": BASE_FILE,
        "baseCaseId": BASE_CASE,
        "categories": category_counts,
        "categoryCount": len(category_counts),
        "mutationCount": len(mutations),
        "mutations": mutations,
        "schema": SCHEMA,
        "scope": SCOPE,
    }


def package_paths(root):
    directory = root / PACKAGE
    return directory, directory / MANIFEST


def validate_checked_in(root):
    document = expected_descriptor(root)
    directory, manifest_path = package_paths(root)
    require(directory.is_dir(), f"missing boundary golden directory: {PACKAGE}")
    require({path.name for path in directory.iterdir()} == {MANIFEST},
            "boundary golden package must contain exactly manifest.json")
    actual = manifest_path.read_bytes()
    require(actual == base.canonical_json(document), "boundary manifest mismatch")
    require(len(actual) <= 128 * 1024, "boundary manifest exceeds frozen byte bound")


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
            print("reference_source_program_wire_boundary_golden_v1: emitted 67")
            return 0
        if argv == ["--self-check"]:
            validate_checked_in(root)
            print("reference_source_program_wire_boundary_golden_v1: ok 67")
            return 0
        print("usage: reference_source_program_wire_boundary_golden_v1.py --emit|--self-check",
              file=sys.stderr)
        return 2
    except (OSError, RuntimeError, ValueError) as error:
        print(f"reference_source_program_wire_boundary_golden_v1: FAIL: {error}",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

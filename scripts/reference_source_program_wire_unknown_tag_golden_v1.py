#!/usr/bin/env python3
"""Independent PA125 unknown-tag negative descriptor for D1-PA-128."""

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

SCHEMA = "proof-forge.source-program-unknown-tag-golden-prerequisite.v1"
SCOPE = "pa125-base-first-occurrence-one-byte-unknown-tag"
BASE_CASE = "full-tag-valid-v1"
BASE_FILE = "testdata/golden/source-program-v1/full-tag-v1/canonical.bin"
BASE_SHA256 = "5d38eaca671e503ae50a517cc8ffaddba20b370d11da22f6bcdb807089aa64ce"
PACKAGE = Path("testdata/golden/source-program-v1/unknown-tag-v1")
MANIFEST = "manifest.json"
MUTATED_FIRST_BYTE = ord("X")


def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)


def diagnostic_groups():
    groups = {
        "binary-op": {tag for tag in base.WIRE_TAGS if tag.startswith("BinaryOp.")},
        "visibility": {tag for tag in base.WIRE_TAGS if tag.startswith("Visibility.")},
        "unary-op": {tag for tag in base.WIRE_TAGS if tag.startswith("UnaryOp.")},
        "literal": {tag for tag in base.WIRE_TAGS if tag.startswith("Literal.")},
        "type": {tag for tag in base.WIRE_TAGS if tag.startswith("Type.")},
        "pattern": {tag for tag in base.WIRE_TAGS if tag.startswith("Pattern.")},
        "place": {tag for tag in base.WIRE_TAGS if tag.startswith("Place.")},
        "expr": {tag for tag in base.WIRE_TAGS if tag.startswith("Expr.")},
        "stmt": {tag for tag in base.WIRE_TAGS if tag.startswith("Stmt.")},
        "program": {"Program"},
        "program-item": {
            "StateDecl", "StructDecl", "EnumDecl", "ConstDecl", "EventDecl",
            "ErrorDecl", "InitDecl", "EntryDecl", "ViewDecl", "FnDecl",
            "InvariantDecl", "ExtensionReq", "ProofDecl",
        },
        "param": {"Param"},
        "field-decl": {"FieldDecl"},
        "enum-variant": {"EnumVariant"},
        "block": {"Block"},
        "stmt-match-arm": {"StmtMatchArm"},
        "expr-match-arm": {"ExprMatchArm"},
        "external-call": {"ExternalCallExpr"},
    }
    observed = set()
    for family, tags in groups.items():
        require(not observed.intersection(tags), f"overlapping diagnostic family {family}")
        observed.update(tags)
    require(len(groups) == 18 and observed == base.WIRE_TAGS,
            "closed 84-tag/18-family diagnostic mapping")
    return groups


def encode_with_tag_offsets(value, offset, records):
    if isinstance(value, bytes):
        return value
    if isinstance(value, base.ArrayValue):
        output = base.u32le(len(value.items))
        for item in value.items:
            output += encode_with_tag_offsets(item, offset + len(output), records)
        return output
    if isinstance(value, base.OptionValue):
        if value.value is None:
            return b"\x00"
        return b"\x01" + encode_with_tag_offsets(value.value, offset + 1, records)
    if isinstance(value, base.Tagged):
        tag_bytes = value.tag.encode("ascii")
        records.append((value.tag, offset + 4))
        output = base.u32le(len(tag_bytes)) + tag_bytes + base.u16le(len(value.fields))
        for _field_name, child in value.fields:
            output += encode_with_tag_offsets(child, offset + len(output), records)
        return output
    raise RuntimeError(f"unknown PA125 value type {type(value)!r}")


def case_id(tag):
    return "unknown-tag-" + tag.lower().replace(".", "-")


def expected_descriptor(root):
    base.validate_checked_in(root)
    expected_binary, _base_document = base.expected_package()
    prefix = base.qualified(base.MODULE) + base.qualified(base.PROGRAM_IDENTITY, 2)
    records = []
    encoded = prefix + encode_with_tag_offsets(base.build_fixture(), len(prefix), records)
    require(encoded == expected_binary, "offset encoder differs from PA125 canonical bytes")
    require(hashlib.sha256(encoded).hexdigest() == BASE_SHA256, "PA125 base digest")

    groups = diagnostic_groups()
    family_by_tag = {tag: family for family, tags in groups.items() for tag in tags}
    first = {}
    for tag, offset in records:
        first.setdefault(tag, offset)
    require(set(first) == base.WIRE_TAGS and len(first) == 84,
            "closed first-occurrence tag inventory")

    mutations = []
    for tag in sorted(first):
        offset = first[tag]
        original = tag.encode("ascii")
        matching = [candidate for candidate_tag, candidate in records if candidate_tag == tag]
        require(offset == min(matching), f"lowest tag offset for {tag}")
        require(encoded[offset:offset + len(original)] == original,
                f"base tag bytes for {tag}")
        require(original[0] != MUTATED_FIRST_BYTE, f"canonical tag begins with X: {tag}")
        mutated = "X" + tag[1:]
        mutated_bytes = mutated.encode("ascii")
        require(len(mutated_bytes) == len(original) and mutated_bytes[1:] == original[1:],
                f"one-byte tag mutation for {tag}")
        require(mutated not in base.WIRE_TAGS, f"mutated tag aliases inventory: {tag}")
        family = family_by_tag[tag]
        mutations.append({
            "caseId": case_id(tag),
            "diagnosticFamily": family,
            "expectedError": f"unknown {family} tag '{mutated}'",
            "mutatedFirstByte": MUTATED_FIRST_BYTE,
            "mutatedTag": mutated,
            "originalFirstByte": original[0],
            "originalTag": tag,
            "tagByteOffset": offset,
        })
    require(len(mutations) == 84 and len({row["tagByteOffset"] for row in mutations}) == 84,
            "84 unique tag mutations")
    require(mutations == sorted(mutations, key=lambda row: row["originalTag"]),
            "mutation row order")

    families = sorted(groups)
    return {
        "baseCanonicalBytesSha256": "sha256:" + BASE_SHA256,
        "baseCanonicalFile": BASE_FILE,
        "baseCaseId": BASE_CASE,
        "diagnosticFamilies": families,
        "diagnosticFamilyCount": 18,
        "mutationCount": 84,
        "mutations": mutations,
        "schema": SCHEMA,
        "scope": SCOPE,
        "tagCount": 84,
    }


def package_paths(root):
    directory = root / PACKAGE
    return directory, directory / MANIFEST


def validate_checked_in(root):
    document = expected_descriptor(root)
    directory, manifest_path = package_paths(root)
    require(directory.is_dir(), f"missing unknown-tag golden directory: {PACKAGE}")
    require({path.name for path in directory.iterdir()} == {MANIFEST},
            "unknown-tag golden package must contain exactly manifest.json")
    actual = manifest_path.read_bytes()
    require(actual == base.canonical_json(document), "unknown-tag manifest mismatch")
    require(len(actual) <= 96 * 1024, "unknown-tag manifest exceeds frozen byte bound")


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
            print("reference_source_program_wire_unknown_tag_golden_v1: emitted 84 18")
            return 0
        if argv == ["--self-check"]:
            validate_checked_in(root)
            print("reference_source_program_wire_unknown_tag_golden_v1: ok 84 18")
            return 0
        print("usage: reference_source_program_wire_unknown_tag_golden_v1.py --emit|--self-check",
              file=sys.stderr)
        return 2
    except (OSError, RuntimeError, ValueError) as error:
        print(f"reference_source_program_wire_unknown_tag_golden_v1: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

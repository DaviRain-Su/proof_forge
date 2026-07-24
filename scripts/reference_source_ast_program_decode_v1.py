#!/usr/bin/env python3
"""Independent D1-PA-117 ProgramV1 tagged-value decoder oracle."""

import sys
import unicodedata


class Rejected(Exception):
    pass


def reject(detail):
    raise Rejected(detail)


def u16le(value):
    return bytes((value & 255, (value >> 8) & 255))


def u32le(value):
    return bytes((value & 255, (value >> 8) & 255,
                  (value >> 16) & 255, (value >> 24) & 255))


def read_u16(raw, offset):
    if len(raw) - offset < 2:
        reject("truncated")
    return raw[offset] | raw[offset + 1] << 8, offset + 2


def read_u32(raw, offset):
    if len(raw) - offset < 4:
        reject("truncated")
    value = (raw[offset] | raw[offset + 1] << 8 |
             raw[offset + 2] << 16 | raw[offset + 3] << 24)
    return value, offset + 4


def decode_tag(raw, offset):
    length, offset = read_u32(raw, offset)
    if not 1 <= length <= 21:
        reject("tag length must be 1..21 bytes")
    if len(raw) - offset < length:
        reject("truncated")
    encoded = raw[offset:offset + length]
    try:
        tag = encoded.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        reject("invalid UTF-8 tag")
    if any(ord(char) > 127 for char in tag):
        reject("tag must be ASCII")
    return tag, offset + length


def decode_name(raw, offset):
    length, offset = read_u32(raw, offset)
    if not 1 <= length <= 240:
        reject("source name component must contain 1..240 UTF-8 bytes")
    if len(raw) - offset < length:
        reject("string length exceeds remaining")
    encoded = raw[offset:offset + length]
    try:
        name = encoded.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        reject("invalid UTF-8")
    if unicodedata.normalize("NFC", name) != name:
        reject("string must use pinned NFC normalization")
    return name, offset + length


def encoded_tag(tag):
    value = tag.encode("ascii")
    return u32le(len(value)) + value


def tagged(tag, field_count, payload=b""):
    return encoded_tag(tag) + u16le(field_count) + payload


STATE_ITEM = bytes.fromhex(
    "0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963"
    "000007000000656e61626c656409000000547970652e426f6f6c0000")
CONST_ITEM = bytes.fromhex(
    "09000000436f6e73744465636c0300030000006d617809000000547970652e55496e7401"
    "0000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e74"
    "656765720100001000000000000000000000000000000000000000000000000000000000"
    "000000")
EMPTY_STRUCT = tagged("StructDecl", 2, u32le(5) + b"Store" + u32le(0))
BAD_CONST = tagged("ConstDecl", 3,
                   u32le(3) + b"max" + encoded_tag("BogusType") +
                   encoded_tag("BogusValue"))

PROGRAM_STATE = bytes.fromhex(
    "0700000050726f6772616d02000400000044656d6f01000000" + STATE_ITEM.hex())
PROGRAM_ORDER = bytes.fromhex(
    "0700000050726f6772616d02000400000044656d6f02000000" +
    STATE_ITEM.hex() + CONST_ITEM.hex())
PROGRAM_REVERSED = bytes.fromhex(
    "0700000050726f6772616d02000400000044656d6f02000000" +
    CONST_ITEM.hex() + STATE_ITEM.hex())


def decode_item(raw, offset, depth, nodes):
    if raw.startswith(STATE_ITEM, offset):
        if depth < 2:
            reject("depth budget exhausted")
        if nodes < 2:
            reject("node budget exhausted")
        return "state", offset + len(STATE_ITEM), nodes - 2
    if raw.startswith(CONST_ITEM, offset):
        if depth < 2:
            reject("depth budget exhausted")
        if nodes < 3:
            reject("node budget exhausted")
        return "const", offset + len(CONST_ITEM), nodes - 3
    if raw.startswith(EMPTY_STRUCT, offset):
        reject("struct fields must be nonempty")
    if raw.startswith(BAD_CONST, offset):
        reject("unknown type tag 'BogusType'")
    tag, _after_tag = decode_tag(raw, offset)
    if tag not in {
            "StateDecl", "StructDecl", "EnumDecl", "ConstDecl", "EventDecl",
            "ErrorDecl", "InitDecl", "EntryDecl", "ViewDecl", "FnDecl",
            "InvariantDecl", "ExtensionReq", "ProofDecl"}:
        reject(f"unknown program-item tag '{tag}'")
    reject(f"unexpected nonfixture item '{tag}'")


def decode_program(raw, depth, nodes):
    tag, offset = decode_tag(raw, 0)
    if tag != "Program":
        reject(f"unknown program tag '{tag}'")
    field_count, offset = read_u16(raw, offset)
    if field_count != 2:
        reject("tag 'Program' must declare 2 fields")
    if depth == 0:
        reject("depth budget exhausted")
    if nodes == 0:
        reject("node budget exhausted")
    nodes -= 1
    name, offset = decode_name(raw, offset)
    count, offset = read_u32(raw, offset)
    if count == 0:
        reject("program items must be nonempty")
    if count > nodes:
        reject("array count exceeds caller limit")
    items = []
    for _index in range(count):
        item, offset, nodes = decode_item(raw, offset, depth - 1, nodes)
        items.append(item)
    return (name, tuple(items)), offset, nodes


def finish(raw, offset):
    if offset != len(raw):
        reject("trailing bytes")


def mutate_field_count(raw, field_count):
    _tag, offset = decode_tag(raw, 0)
    return raw[:offset] + u16le(field_count) + raw[offset + 2:]


def expect_rejected(label, expected, operation):
    try:
        operation()
    except Rejected as error:
        if str(error) != expected:
            raise SystemExit(f"{label}: expected {expected}, got {error}")
        return
    raise SystemExit(f"{label}: unexpectedly succeeded")


def program_bytes(name, item_payload):
    return tagged("Program", 2, u32le(len(name)) + name.encode("utf-8") + item_payload)


def self_check():
    positives = 0
    cases = (
        ("state", PROGRAM_STATE, 3, 3, ("Demo", ("state",))),
        ("order", PROGRAM_ORDER, 3, 6, ("Demo", ("state", "const"))),
        ("reversed", PROGRAM_REVERSED, 3, 6, ("Demo", ("const", "state"))),
    )
    for label, raw, depth, nodes, expected in cases:
        value, offset, residual = decode_program(raw, depth, nodes)
        if value != expected or residual != 0:
            raise SystemExit(f"{label}: positive value/residual mismatch")
        finish(raw, offset)
        positives += 1
    if PROGRAM_ORDER == PROGRAM_REVERSED:
        raise SystemExit("program order bytes aliased")

    field_counts = 0
    for invalid in (1, 3):
        mutated = mutate_field_count(PROGRAM_STATE, invalid)
        expect_rejected(f"field-count-{invalid}",
                        "tag 'Program' must declare 2 fields",
                        lambda b=mutated: decode_program(b, 0, 0))
        field_counts += 1

    boundaries = 0
    boundary_cases = (
        (u32le(0), 0, 0, "tag length must be 1..21 bytes"),
        (u32le(1) + b"\xff", 0, 0, "invalid UTF-8 tag"),
        (encoded_tag("StateDecl"), 0, 0, "unknown program tag 'StateDecl'"),
        (tagged("Program", 2), 0, 0, "depth budget exhausted"),
        (tagged("Program", 2), 1, 0, "node budget exhausted"),
        (program_bytes("", u32le(0xffffffff)), 2, 8,
         "source name component must contain 1..240 UTF-8 bytes"),
        (program_bytes("Demo", u32le(0)), 2, 8, "program items must be nonempty"),
        (program_bytes("Demo", u32le(2)), 2, 2, "array count exceeds caller limit"),
        (program_bytes("Demo", u32le(0xffffffff)), 2, 100,
         "array count exceeds caller limit"),
        (program_bytes("Demo", u32le(1) + encoded_tag("BogusItem")), 2, 8,
         "unknown program-item tag 'BogusItem'"),
        (program_bytes("Demo", u32le(1) + encoded_tag("Type.Bool")), 2, 8,
         "unknown program-item tag 'Type.Bool'"),
        (PROGRAM_STATE, 2, 3, "depth budget exhausted"),
        (PROGRAM_STATE, 3, 2, "node budget exhausted"),
        (program_bytes("Demo", u32le(2) + STATE_ITEM + encoded_tag("BogusItem")), 3, 6,
         "unknown program-item tag 'BogusItem'"),
        (program_bytes("Demo", u32le(2) + STATE_ITEM + EMPTY_STRUCT), 4, 6,
         "struct fields must be nonempty"),
        (program_bytes("Demo", u32le(2) + BAD_CONST + STATE_ITEM), 4, 8,
         "unknown type tag 'BogusType'"),
    )
    for index, (raw, depth, nodes, expected) in enumerate(boundary_cases, 1):
        expect_rejected(f"boundary-{index}", expected,
                        lambda b=raw, d=depth, n=nodes: decode_program(b, d, n))
        boundaries += 1

    value, offset, residual = decode_program(PROGRAM_STATE + b"\x00", 3, 3)
    if value != ("Demo", ("state",)) or residual != 0:
        raise SystemExit("boundary-17: decoded value changed")
    expect_rejected("boundary-17", "trailing bytes",
                    lambda: finish(PROGRAM_STATE + b"\x00", offset))
    boundaries += 1

    if (positives, field_counts, boundaries) != (3, 2, 17):
        raise SystemExit(f"inventory {positives} {field_counts} {boundaries}")
    print("reference_source_ast_program_decode_v1: ok 3 2 17")


if __name__ == "__main__":
    if sys.argv[1:] != ["--self-check"]:
        print("usage: reference_source_ast_program_decode_v1.py --self-check",
              file=sys.stderr)
        raise SystemExit(2)
    self_check()

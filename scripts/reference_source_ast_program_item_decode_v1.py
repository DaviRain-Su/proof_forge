#!/usr/bin/env python3
"""Independent D1-PA-116 no-wrapper ProgramItemV1 dispatch oracle."""

import sys


class Rejected(Exception):
    pass


def reject(detail):
    raise Rejected(detail)


def u16le(value):
    return bytes((value & 0xFF, (value >> 8) & 0xFF))


def u32le(value):
    return bytes((value & 0xFF, (value >> 8) & 0xFF,
                  (value >> 16) & 0xFF, (value >> 24) & 0xFF))


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


def peek_tag(raw):
    length, offset = read_u32(raw, 0)
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


ROUTES = {
    "StateDecl": ("state", 3),
    "StructDecl": ("struct", 2),
    "EnumDecl": ("enum", 2),
    "ConstDecl": ("const", 3),
    "EventDecl": ("event", 2),
    "ErrorDecl": ("error", 2),
    "InitDecl": ("init", 2),
    "EntryDecl": ("entry", 4),
    "ViewDecl": ("view", 4),
    "FnDecl": ("fn", 4),
    "InvariantDecl": ("invariant", 2),
    "ExtensionReq": ("extensionReq", 3),
    "ProofDecl": ("proof", 3),
}


def dispatch(raw, depth, nodes, handlers):
    tag, _after_tag = peek_tag(raw)
    if tag not in ROUTES:
        reject(f"unknown program-item tag '{tag}'")
    return handlers[tag](raw, depth, nodes)


def fixed_handler(tag, expected_raw, expected_depth, expected_nodes):
    route, _field_count = ROUTES[tag]

    def handle(raw, depth, nodes):
        if raw != expected_raw:
            raise SystemExit(f"{route}: dispatcher did not pass original bytes")
        if depth != expected_depth or nodes != expected_nodes:
            raise SystemExit(f"{route}: dispatcher changed caller budget")
        return route, len(raw), 0

    return handle


def field_count_handler(tag):
    expected = ROUTES[tag][1]

    def handle(raw, depth, nodes):
        if depth != 0 or nodes != 0:
            raise SystemExit(f"{tag}: field-count budget changed")
        observed_tag, offset = peek_tag(raw)
        if observed_tag != tag:
            raise SystemExit(f"{tag}: wrong delegated tag")
        actual, _offset = read_u16(raw, offset)
        if actual != expected:
            reject(f"tag '{tag}' must declare {expected} fields")
        reject("field-count mutation unexpectedly valid")

    return handle


def mutate_field_count(raw, field_count):
    _tag, offset = peek_tag(raw)
    return raw[:offset] + u16le(field_count) + raw[offset + 2:]


def encoded_tag(tag):
    encoded = tag.encode("ascii")
    return u32le(len(encoded)) + encoded


def tagged(tag, field_count, payload=b""):
    return encoded_tag(tag) + u16le(field_count) + payload


FIXTURES = {
    "StateDecl": (2, 2, "0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"),
    "StructDecl": (3, 3, "0a0000005374727563744465636c02000500000053746f726501000000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001"),
    "EnumDecl": (3, 5, "08000000456e756d4465636c02000600000043686f696365020000000b000000456e756d56617269616e740200040000004e6f6e65000000000b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000"),
    "ConstDecl": (2, 3, "09000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"),
    "EventDecl": (1, 1, "090000004576656e744465636c02000400000050696e6700000000"),
    "ErrorDecl": (1, 1, "090000004572726f724465636c020005000000456d70747900000000"),
    "InitDecl": (4, 9, "08000000496e69744465636c02000200000005000000506172616d0300110000005669736962696c6974792e5075626c6963000005000000737461727409000000547970652e55496e740100400005000000506172616d0300120000005669736962696c6974792e507269766174650000060000007365637265740a000000547970652e4669656c64010008000000626e3235345f667205000000426c6f636b0100010000000b00000053746d742e41737369676e02000a000000506c6163652e4e616d65010005000000636f756e740c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"),
    "EntryDecl": (5, 12, "09000000456e7472794465636c04000300000072756e0300000005000000506172616d0300110000005669736962696c6974792e5075626c6963000002000000746f0e000000547970652e5072696e636970616c000005000000506172616d0300120000005669736962696c6974792e50726976617465000006000000616d6f756e7409000000547970652e55496e740100400005000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000040000006e6f74650a000000547970652e427974657301000000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e74"),
    "ViewDecl": (4, 5, "08000000566965774465636c0400030000006765740000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000"),
    "FnDecl": (5, 9, "06000000466e4465636c04000700000068656c706572320100000005000000506172616d0300110000005669736962696c6974792e5075626c69630000010000007809000000547970652e55496e740100400009000000547970652e556e6974000005000000426c6f636b0100010000000700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e01000000"),
    "InvariantDecl": (4, 5, "0d000000496e76617269616e744465636c020007000000626f756e6465640b000000457870722e42696e61727903000b00000042696e6172794f702e4c7400000a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e740c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"),
    "ExtensionReq": (1, 1, "0c000000457874656e73696f6e5265710300020000000400000044656d6f070000004665617475726505000000312e302e30470000007368613235363a30303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030"),
    "ProofDecl": (1, 1, "0900000050726f6f664465636c030004000000736166650f00000050726f6f664b696e642e486f6c64730000020000000600000050726f6f66730400000073616665"),
}


def expect_rejected(label, expected, operation):
    try:
        operation()
    except Rejected as error:
        if str(error) != expected:
            raise SystemExit(f"{label}: expected {expected}, got {error}")
        return
    raise SystemExit(f"{label}: unexpectedly succeeded")


def delegation_error(tag, exact_raw, exact_depth, exact_nodes, detail):
    def handle(raw, depth, nodes):
        if raw != exact_raw:
            raise SystemExit(f"{tag}: delegation lost original bytes")
        if depth != exact_depth or nodes != exact_nodes:
            raise SystemExit(f"{tag}: delegation changed budgets")
        reject(detail)
    return handle


def self_check():
    positives = 0
    handlers = {}
    raw_fixtures = {}
    for tag, (depth, nodes, expected_hex) in FIXTURES.items():
        raw = bytes.fromhex(expected_hex)
        raw_fixtures[tag] = raw
        handlers[tag] = fixed_handler(tag, raw, depth, nodes)
    for tag, (depth, nodes, _expected_hex) in FIXTURES.items():
        route, consumed, residual = dispatch(raw_fixtures[tag], depth, nodes, handlers)
        if route != ROUTES[tag][0] or consumed != len(raw_fixtures[tag]) or residual != 0:
            raise SystemExit(f"{tag}: positive projection mismatch")
        positives += 1

    field_counts = 0
    fc_handlers = {tag: field_count_handler(tag) for tag in ROUTES}
    for tag, (_route, expected) in ROUTES.items():
        for invalid in (expected - 1, expected + 1):
            mutated = mutate_field_count(raw_fixtures[tag], invalid)
            want = f"tag '{tag}' must declare {expected} fields"
            expect_rejected(f"fc-{tag}-{invalid}", want,
                            lambda b=mutated: dispatch(b, 0, 0, fc_handlers))
            field_counts += 1

    alias_payload = b"shared-payload"
    alias_groups = (("EventDecl", "ErrorDecl"),
                    ("EntryDecl", "ViewDecl", "FnDecl"))
    for group in alias_groups:
        encoded = [tagged(tag, ROUTES[tag][1], alias_payload) for tag in group]
        if len(set(encoded)) != len(group):
            raise SystemExit("alias bytes collapsed")
        if len({ROUTES[tag][0] for tag in group}) != len(group):
            raise SystemExit("alias routes collapsed")

    boundaries = 0
    malformed = (
        (u32le(0), "tag length must be 1..21 bytes"),
        (u32le(22), "tag length must be 1..21 bytes"),
        (u32le(4) + b"Bo", "truncated"),
        (u32le(1) + b"\xff", "invalid UTF-8 tag"),
        (u32le(2) + "é".encode("utf-8"), "tag must be ASCII"),
        (encoded_tag("BogusItem"), "unknown program-item tag 'BogusItem'"),
        (encoded_tag("Type.Bool"), "unknown program-item tag 'Type.Bool'"),
    )
    for index, (raw, detail) in enumerate(malformed, 1):
        expect_rejected(f"boundary-{index}", detail,
                        lambda b=raw: dispatch(b, 0, 0, handlers))
        boundaries += 1

    delegated = (
        ("StateDecl", tagged("StateDecl", 3), 0, 0, "depth budget exhausted"),
        ("StateDecl", tagged("StateDecl", 3), 1, 0, "node budget exhausted"),
        ("StateDecl", tagged("StateDecl", 3, tagged("Type.Bool", 0) + u32le(0) + encoded_tag("BogusType")), 3, 8, "unknown visibility tag 'Type.Bool'"),
        ("StructDecl", tagged("StructDecl", 2, u32le(5) + b"Store" + u32le(0)), 3, 8, "struct fields must be nonempty"),
        ("EnumDecl", tagged("EnumDecl", 2, u32le(6) + b"Choice" + u32le(0)), 3, 8, "enum variants must be nonempty"),
        ("EventDecl", tagged("EventDecl", 2, u32le(4) + b"Ping" + u32le(2)), 2, 1, "array count exceeds caller limit"),
        ("ErrorDecl", tagged("ErrorDecl", 2, u32le(5) + b"Empty" + u32le(1) + encoded_tag("BogusParam")), 2, 8, "unknown param tag 'BogusParam'"),
        ("ConstDecl", tagged("ConstDecl", 3, u32le(3) + b"max" + encoded_tag("BogusType") + encoded_tag("BogusValue")), 3, 8, "unknown type tag 'BogusType'"),
        ("InitDecl", tagged("InitDecl", 2, u32le(0) + tagged("Block", 1, u32le(0))), 3, 8, "block statements must be nonempty"),
        ("ExtensionReq", tagged("ExtensionReq", 3, u32le(1) + u32le(4) + b"Only" + u32le(3) + b"bad" + u32le(3) + b"bad"), 1, 1, "source qualified id must contain 2..256 components"),
        ("ProofDecl", tagged("ProofDecl", 3, u32le(4) + b"safe" + tagged("ProofKind.Holds", 0) + u32le(1) + u32le(4) + b"Only"), 1, 1, "source qualified id must contain 2..256 components"),
    )
    for index, (tag, raw, depth, nodes, detail) in enumerate(delegated, 8):
        local_handlers = dict(handlers)
        local_handlers[tag] = delegation_error(tag, raw, depth, nodes, detail)
        expect_rejected(f"boundary-{index}", detail,
                        lambda b=raw, d=depth, n=nodes, hs=local_handlers:
                        dispatch(b, d, n, hs))
        boundaries += 1

    state_with_trailing = raw_fixtures["StateDecl"] + b"\x00"
    state_handler = fixed_handler("StateDecl", state_with_trailing, 2, 2)
    local_handlers = dict(handlers)
    local_handlers["StateDecl"] = state_handler
    _route, consumed, _residual = dispatch(state_with_trailing, 2, 2, local_handlers)
    consumed -= 1
    expect_rejected("boundary-19", "trailing bytes",
                    lambda: reject("trailing bytes") if consumed != len(state_with_trailing)
                    else None)
    boundaries += 1

    if (positives, field_counts, boundaries) != (13, 26, 19):
        raise SystemExit(f"inventory {positives} {field_counts} {boundaries}")
    print("reference_source_ast_program_item_decode_v1: ok 13 26 19")


if __name__ == "__main__":
    if sys.argv[1:] != ["--self-check"]:
        print("usage: reference_source_ast_program_item_decode_v1.py --self-check",
              file=sys.stderr)
        raise SystemExit(2)
    self_check()

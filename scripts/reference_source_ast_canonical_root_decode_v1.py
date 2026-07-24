#!/usr/bin/env python3
"""Independent selected-wire oracle for frozen D1-PA-118."""
import sys
import unicodedata
MAX_BYTES = 16 * 1024 * 1024
MAX_NODES = 100000
MAX_DEPTH = 256
class DecodeError(Exception):
    pass
def fail(detail):
    raise DecodeError(detail)
def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)
def take(data, offset, count):
    if len(data) - offset < count:
        fail("truncated")
    return data[offset:offset + count], offset + count
def dec_u16(data, offset):
    raw, offset = take(data, offset, 2)
    return raw[0] + raw[1] * 256, offset
def dec_u32(data, offset):
    raw, offset = take(data, offset, 4)
    return int.from_bytes(raw, "little"), offset
def dec_name(data, offset):
    length, offset = dec_u32(data, offset)
    if not 1 <= length <= 240:
        fail("source name component must contain 1..240 UTF-8 bytes")
    if len(data) - offset < length:
        fail("string length exceeds remaining")
    raw, offset = take(data, offset, length)
    try:
        value = raw.decode("utf-8")
    except UnicodeDecodeError:
        fail("invalid UTF-8")
    if unicodedata.normalize("NFC", value) != value:
        fail("string must use NFC normalization")
    if any(unicodedata.category(ch) == "Cc" for ch in value):
        fail("source name component must not contain control characters")
    if "\u00bb" in value:
        fail("source name component must not contain closing guillemet")
    return value, offset
def dec_name_array(data, offset, minimum, count_error):
    count, offset = dec_u32(data, offset)
    if not minimum <= count <= 256:
        fail(count_error)
    values = []
    for _ in range(count):
        value, offset = dec_name(data, offset)
        values.append(value)
    return values, offset
def dec_tag(data, offset):
    length, offset = dec_u32(data, offset)
    if not 1 <= length <= 21:
        fail("tag length must be 1..21 bytes")
    raw, offset = take(data, offset, length)
    try:
        tag = raw.decode("utf-8")
    except UnicodeDecodeError:
        fail("invalid UTF-8 tag")
    if any(ord(ch) > 127 for ch in tag):
        fail("tag must be ASCII")
    return tag, offset
def dec_head(data, offset, expected, fields, family):
    tag, offset = dec_tag(data, offset)
    if tag != expected:
        fail(f"unknown {family} tag '{tag}'")
    actual, offset = dec_u16(data, offset)
    if actual != fields:
        fail(f"tag '{tag}' must declare {fields} fields")
    return offset
def charge(nodes):
    if nodes == 0:
        fail("node budget exhausted")
    return nodes - 1
def dec_visibility(data, offset):
    tag, offset = dec_tag(data, offset)
    if tag not in ("Visibility.Public", "Visibility.Private", "Visibility.Commitment"):
        fail(f"unknown visibility tag '{tag}'")
    fields, offset = dec_u16(data, offset)
    if fields != 0:
        fail(f"tag '{tag}' must declare 0 fields")
    return tag, offset
def dec_type(data, offset, depth, nodes):
    tag, after_tag = dec_tag(data, offset)
    counts = {"Type.Bool": 0, "Type.Unit": 0, "Type.Option": 1}
    if tag not in counts:
        fail(f"unknown type tag '{tag}'")
    fields, after_head = dec_u16(data, after_tag)
    if fields != counts[tag]:
        fail(f"tag '{tag}' must declare {counts[tag]} fields")
    if depth == 0:
        fail("depth budget exhausted")
    nodes = charge(nodes)
    if tag == "Type.Bool":
        return ("bool",), after_head, nodes
    if tag == "Type.Unit":
        return ("unit",), after_head, nodes
    child, offset, nodes = dec_type(data, after_head, depth - 1, nodes)
    return ("option", child), offset, nodes
def dec_param(data, offset, depth, nodes):
    offset = dec_head(data, offset, "Param", 3, "param")
    if depth == 0:
        fail("depth budget exhausted")
    nodes = charge(nodes)
    visibility, offset = dec_visibility(data, offset)
    name, offset = dec_name(data, offset)
    type_, offset, nodes = dec_type(data, offset, depth - 1, nodes)
    return (visibility, name, type_), offset, nodes
def dec_literal_bool(data, offset):
    offset = dec_head(data, offset, "Literal.Bool", 1, "literal")
    marker, offset = take(data, offset, 1)
    if marker[0] not in (0, 1):
        fail("invalid bool marker")
    return marker[0] == 1, offset
def dec_expr(data, offset, depth, nodes):
    offset = dec_head(data, offset, "Expr.Literal", 1, "expr")
    if depth == 0:
        fail("depth budget exhausted")
    nodes = charge(nodes)
    value, offset = dec_literal_bool(data, offset)
    return ("literal_bool", value), offset, nodes
def dec_stmt(data, offset, depth, nodes):
    offset = dec_head(data, offset, "Stmt.Return", 1, "stmt")
    if depth == 0:
        fail("depth budget exhausted")
    nodes = charge(nodes)
    marker, offset = take(data, offset, 1)
    if marker[0] == 0:
        return ("return", None), offset, nodes
    if marker[0] != 1:
        fail("invalid option marker")
    value, offset, nodes = dec_expr(data, offset, depth - 1, nodes)
    return ("return", value), offset, nodes
def dec_block(data, offset, depth, nodes):
    offset = dec_head(data, offset, "Block", 1, "block")
    if depth == 0:
        fail("depth budget exhausted")
    nodes = charge(nodes)
    count, offset = dec_u32(data, offset)
    if count == 0:
        fail("block statements must be nonempty")
    if count > nodes:
        fail("array count exceeds caller limit")
    statements = []
    for _ in range(count):
        statement, offset, nodes = dec_stmt(data, offset, depth - 1, nodes)
        statements.append(statement)
    return statements, offset, nodes
def dec_state(data, offset, depth, nodes):
    offset = dec_head(data, offset, "StateDecl", 3, "state-decl")
    if depth == 0:
        fail("depth budget exhausted")
    nodes = charge(nodes)
    visibility, offset = dec_visibility(data, offset)
    name, offset = dec_name(data, offset)
    type_, offset, nodes = dec_type(data, offset, depth - 1, nodes)
    return ("state", visibility, name, type_), offset, nodes
def dec_entry(data, offset, depth, nodes):
    offset = dec_head(data, offset, "EntryDecl", 4, "entry-decl")
    if depth == 0:
        fail("depth budget exhausted")
    nodes = charge(nodes)
    name, offset = dec_name(data, offset)
    count, offset = dec_u32(data, offset)
    if count > nodes:
        fail("array count exceeds caller limit")
    params = []
    for _ in range(count):
        param, offset, nodes = dec_param(data, offset, depth - 1, nodes)
        params.append(param)
    result, offset, nodes = dec_type(data, offset, depth - 1, nodes)
    body, offset, nodes = dec_block(data, offset, depth - 1, nodes)
    return ("entry", name, params, result, body), offset, nodes
def dec_item(data, offset, depth, nodes):
    tag, _ = dec_tag(data, offset)
    if tag == "StateDecl":
        return dec_state(data, offset, depth, nodes)
    if tag == "EntryDecl":
        return dec_entry(data, offset, depth, nodes)
    fail(f"unknown program-item tag '{tag}'")
def dec_program(data, offset, depth, nodes):
    tag, after_tag = dec_tag(data, offset)
    if tag != "Program":
        fail(f"unknown program tag '{tag}'")
    fields, offset = dec_u16(data, after_tag)
    if fields != 2:
        fail("tag 'Program' must declare 2 fields")
    if depth == 0:
        fail("depth budget exhausted")
    nodes = charge(nodes)
    name, offset = dec_name(data, offset)
    count, offset = dec_u32(data, offset)
    if count == 0:
        fail("program items must be nonempty")
    if count > nodes:
        fail("array count exceeds caller limit")
    items = []
    for _ in range(count):
        item, offset, nodes = dec_item(data, offset, depth - 1, nodes)
        items.append(item)
    return {"name": name, "items": items}, offset, nodes
def validate_unit(module_name, identity, program):
    if identity[:len(module_name)] != module_name:
        fail("program identity must begin with the exact module name components")
    if len(identity) <= len(module_name):
        fail("program identity must strictly extend the module name")
    if program["name"] != identity[-1]:
        fail("program name must equal the last program identity component")
    if not any(item[0] == "entry" for item in program["items"]):
        fail("program must declare at least one entry or view")
    seen = set()
    for item in program["items"]:
        if item[0] == "state":
            if item[2] in seen:
                fail("program contains duplicate state declarations")
            seen.add(item[2])
def decode_root(data):
    if len(data) > MAX_BYTES:
        fail("source exceeds the 16 MiB limit")
    module_name, offset = dec_name_array(
        data, 0, 1, "source qualified name must contain 1..256 components")
    identity, offset = dec_name_array(
        data, offset, 2, "source qualified id must contain 2..256 components")
    program, offset, _nodes = dec_program(data, offset, MAX_DEPTH, MAX_NODES)
    if offset != len(data):
        fail("trailing bytes")
    validate_unit(module_name, identity, program)
    return {"module": module_name, "identity": identity, "program": program}
def u16(value):
    return value.to_bytes(2, "little")
def u32(value):
    return value.to_bytes(4, "little")
def string_bytes(value):
    raw = value.encode("utf-8")
    return u32(len(raw)) + raw
def tagged(tag, fields):
    return string_bytes(tag) + u16(len(fields)) + b"".join(fields)
def name_array(values):
    return u32(len(values)) + b"".join(string_bytes(value) for value in values)
def program_bytes(name, items):
    return tagged("Program", [string_bytes(name), u32(len(items)) + b"".join(items)])
def state_bytes(type_):
    return tagged("StateDecl", [tagged("Visibility.Public", []), string_bytes("enabled"), type_])
def return_none():
    return tagged("Stmt.Return", [b"\x00"])
def return_some_bool():
    literal = tagged("Literal.Bool", [b"\x01"])
    expression = tagged("Expr.Literal", [literal])
    return tagged("Stmt.Return", [b"\x01" + expression])
def entry_bytes(block):
    return tagged("EntryDecl", [string_bytes("run"), u32(0), tagged("Type.Unit", []), block])
def root_bytes(module_name, identity, program):
    return name_array(module_name) + name_array(identity) + program
def deep_root(option_count):
    type_ = tagged("Type.Bool", [])
    for _ in range(option_count):
        type_ = tagged("Type.Option", [type_])
    block = tagged("Block", [u32(1) + return_none()])
    return root_bytes(["Root"], ["Root", "Demo"],
                      program_bytes("Demo", [state_bytes(type_), entry_bytes(block)]))
def wide_root(none_count):
    statements = return_none() * none_count + return_some_bool()
    block = tagged("Block", [u32(none_count + 1) + statements])
    return root_bytes(["Root"], ["Root", "Demo"],
                      program_bytes("Demo", [entry_bytes(block)]))
def enc_type(value):
    if value[0] == "bool":
        return tagged("Type.Bool", [])
    if value[0] == "unit":
        return tagged("Type.Unit", [])
    return tagged("Type.Option", [enc_type(value[1])])
def enc_stmt(value):
    if value[1] is None:
        return return_none()
    return return_some_bool()
def enc_item(value):
    if value[0] == "state":
        return tagged("StateDecl", [tagged(value[1], []), string_bytes(value[2]), enc_type(value[3])])
    params = [tagged("Param", [tagged(p[0], []), string_bytes(p[1]), enc_type(p[2])])
              for p in value[2]]
    block = tagged("Block", [u32(len(value[4])) + b"".join(enc_stmt(v) for v in value[4])])
    return tagged("EntryDecl", [string_bytes(value[1]), u32(len(params)) + b"".join(params),
                                enc_type(value[3]), block])
def encode_root(unit):
    program = unit["program"]
    return root_bytes(unit["module"], unit["identity"],
                      program_bytes(program["name"], [enc_item(v) for v in program["items"]]))
def expect_error(label, expected, thunk):
    try:
        thunk()
    except DecodeError as error:
        require(str(error) == expected, f"{label}: expected {expected}, got {error}")
        return
    raise RuntimeError(f"{label}: unexpectedly succeeded")
def self_check():
    fixed = bytes.fromhex(
        "0100000004000000526f6f740200000004000000526f6f740400000044656d6f"
        "0700000050726f6772616d02000400000044656d6f020000000900000053746174"
        "654465636c0300110000005669736962696c6974792e5075626c6963000007000000"
        "656e61626c656409000000547970652e426f6f6c000009000000456e7472794465"
        "636c04000300000072756e0000000009000000547970652e556e6974000005000000"
        "426c6f636b0100010000000b00000053746d742e52657475726e010000")
    unit = decode_root(fixed)
    require(unit["module"] == ["Root"], "positive-fixed: module")
    require(unit["identity"] == ["Root", "Demo"], "positive-fixed: identity")
    require(len(unit["program"]["items"]) == 2, "positive-fixed: items")
    require(encode_root(unit) == fixed, "positive-fixed: re-encode")
    deep = deep_root(253)
    deep_unit = decode_root(deep)
    require(len(deep_unit["program"]["items"]) == 2, "positive-depth-256: items")
    require(encode_root(deep_unit) == deep, "positive-depth-256: re-encode")
    wide = wide_root(99994)
    wide_unit = decode_root(wide)
    require(len(wide_unit["program"]["items"][0][4]) == 99995,
            "positive-nodes-100000: statements")
    require(encode_root(wide_unit) == wide, "positive-nodes-100000: re-encode")
    expect_error("boundary-1", "source exceeds the 16 MiB limit",
                 lambda: decode_root(b"\x00" * (MAX_BYTES + 1)))
    expect_error("boundary-2", "trailing bytes",
                 lambda: decode_root(fixed + b"\x00" * (MAX_BYTES - len(fixed))))
    expect_error("boundary-3", "source qualified name must contain 1..256 components",
                 lambda: decode_root(u32(0) + u32(0xffffffff) + string_bytes("BogusProgram")))
    expect_error("boundary-4", "source name component must contain 1..240 UTF-8 bytes",
                 lambda: decode_root(u32(1) + u32(0) + u32(0xffffffff)))
    expect_error("boundary-5", "source qualified id must contain 2..256 components",
                 lambda: decode_root(name_array(["Root"]) + u32(1) + string_bytes("Only") +
                                     string_bytes("BogusProgram")))
    expect_error("boundary-6", "unknown program tag 'StateDecl'",
                 lambda: decode_root(name_array(["Root"]) + name_array(["Root", "Demo"]) +
                                     string_bytes("StateDecl")))
    empty_entry = entry_bytes(tagged("Block", [u32(0)]))
    local_bad = root_bytes(["Root"], ["Elsewhere", "Demo"],
                           program_bytes("Demo", [empty_entry])) + b"\x00"
    expect_error("boundary-7", "block statements must be nonempty", lambda: decode_root(local_bad))
    state_only_nonprefix = root_bytes(["Root"], ["Elsewhere", "Demo"],
                                      program_bytes("Demo", [state_bytes(tagged("Type.Bool", []))]))
    expect_error("boundary-8", "trailing bytes",
                 lambda: decode_root(state_only_nonprefix + b"\x00"))
    expect_error("boundary-9", "program identity must begin with the exact module name components",
                 lambda: decode_root(root_bytes(["Root"], ["Elsewhere", "Demo"],
                                    program_bytes("Wrong", [state_bytes(tagged("Type.Bool", []))]))))
    expect_error("boundary-10", "program name must equal the last program identity component",
                 lambda: decode_root(root_bytes(["Root"], ["Root", "Demo"],
                                    program_bytes("Wrong", [state_bytes(tagged("Type.Bool", []))]))))
    expect_error("boundary-11", "program must declare at least one entry or view",
                 lambda: decode_root(root_bytes(["Root"], ["Root", "Demo"],
                                    program_bytes("Demo", [state_bytes(tagged("Type.Bool", []))]))))
    expect_error("boundary-12", "depth budget exhausted", lambda: decode_root(deep_root(254)))
    expect_error("boundary-13", "node budget exhausted", lambda: decode_root(wide_root(99995)))
    expect_error("boundary-14", "source qualified name must contain 1..256 components",
                 lambda: decode_root(u32(257)))
    expect_error("boundary-15", "source qualified id must contain 2..256 components",
                 lambda: decode_root(name_array(["Root"]) + u32(257)))
def main(argv):
    if argv != ["--self-check"]:
        print("usage: reference_source_ast_canonical_root_decode_v1.py --self-check", file=sys.stderr)
        return 2
    self_check()
    print("reference_source_ast_canonical_root_decode_v1: ok 3 15")
    return 0
if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

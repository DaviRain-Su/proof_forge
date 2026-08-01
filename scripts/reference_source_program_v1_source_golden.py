#!/usr/bin/env python3
"""Independent source-driven full-tag ProgramV1 golden emitter/checker (B3).

Models the frozen source-derived ProgramV1 value and encoder without importing
Lean or project code. Does not treat a Lean-emitted manifest as the expected
answer: --self-check recomputes the package from the independent model and the
checked-in source.lean UTF-8 bytes.
"""

import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unicodedata

SCHEMA = "proof-forge.source-program-v1-source-full-tag-golden.v1"
SCOPE = "source-driven-programv1-command-and-loader"
CASE_ID = "source-full-tag-v1"
MODULE = ["Tests", "Language", "ProgramV1SourceFullTagGolden", "Source"]
PROGRAM_IDENTITY = MODULE + ["FullTag"]
PACKAGE = Path("testdata/golden/source-program-v1/source-full-tag-v1")
MANIFEST = "manifest.json"
CANONICAL = "canonical.bin"
SOURCE = "source.lean"
WIDTHS = {8, 16, 32, 64, 128, 256}
MAX_U256 = (1 << 256) - 1

WIRE_TAGS = set("""
BinaryOp.Add BinaryOp.And BinaryOp.BitAnd BinaryOp.BitOr BinaryOp.BitXor
BinaryOp.Div BinaryOp.Eq BinaryOp.Ge BinaryOp.Gt BinaryOp.Le BinaryOp.Lt
BinaryOp.Mod BinaryOp.Mul BinaryOp.Ne BinaryOp.Or BinaryOp.Shl BinaryOp.Shr
BinaryOp.Sub Block ConstDecl EntryDecl EnumDecl EnumVariant ErrorDecl EventDecl
Expr.Binary Expr.Constructor Expr.Literal Expr.LocalCall Expr.Match Expr.Place
Expr.Unary ExprMatchArm ExtensionReq ExternalCallExpr FieldDecl FnDecl InitDecl
InvariantDecl Literal.Bool Literal.Integer Literal.String Param Pattern.Bind
Pattern.Constructor Pattern.Literal Pattern.Wildcard Place.Field Place.Index
Place.Name Program ProofDecl StateDecl Stmt.Assert Stmt.Assign Stmt.Call
Stmt.Emit Stmt.For Stmt.If Stmt.Let Stmt.Match Stmt.Return Stmt.Revert
Stmt.Schedule StmtMatchArm StructDecl Type.Array Type.Bool Type.Bytes Type.Field
Type.Int Type.Map Type.Named Type.Option Type.Principal Type.String Type.UInt Type.Unit
UnaryOp.BitNot UnaryOp.Neg UnaryOp.Not ViewDecl Visibility.Commitment
Visibility.Private Visibility.Public
""".split())

NODE_TAGS = set("""
Program StateDecl StructDecl EnumDecl ConstDecl EventDecl ErrorDecl InitDecl
EntryDecl ViewDecl FnDecl InvariantDecl ExtensionReq ProofDecl Param FieldDecl
EnumVariant Block StmtMatchArm ExprMatchArm ExternalCallExpr Type.Bool Type.UInt
Type.Int Type.Principal Type.Unit Type.String Type.Named Type.Array Type.Map Type.Option
Type.Bytes Type.Field Stmt.Let Stmt.Assign Stmt.If Stmt.Match Stmt.For
Stmt.Assert Stmt.Revert Stmt.Emit Stmt.Return Stmt.Call Stmt.Schedule
Expr.Literal Expr.Place Expr.Constructor Expr.Unary Expr.Binary Expr.LocalCall
Expr.Match Place.Name Place.Field Place.Index Pattern.Wildcard Pattern.Bind
Pattern.Literal Pattern.Constructor
""".split())

EDGE_PAIRS = {tuple(value.split(":", 1)) for value in """
Program:items StateDecl:type StructDecl:fields EnumDecl:variants ConstDecl:type
ConstDecl:value EventDecl:params ErrorDecl:params InitDecl:params InitDecl:body
EntryDecl:params EntryDecl:result EntryDecl:body ViewDecl:params ViewDecl:result
ViewDecl:body FnDecl:params FnDecl:result FnDecl:body InvariantDecl:predicate
Param:type FieldDecl:type EnumVariant:payloadTypes Block:statements
StmtMatchArm:pattern StmtMatchArm:body ExprMatchArm:pattern ExprMatchArm:value
ExternalCallExpr:args Type.Array:element Type.Map:key Type.Map:value
Type.Option:element Stmt.Let:typeAnn Stmt.Let:value Stmt.Assign:target
Stmt.Assign:value Stmt.If:condition Stmt.If:thenBlock Stmt.If:elseBlock
Stmt.Match:scrutinee Stmt.Match:arms Stmt.For:start Stmt.For:endExclusive
Stmt.For:body Stmt.Assert:condition Stmt.Revert:args Stmt.Emit:args
Stmt.Return:value Stmt.Call:call Stmt.Schedule:call Expr.Place:place
Expr.Constructor:args Expr.Unary:operand Expr.Binary:lhs Expr.Binary:rhs
Expr.LocalCall:args Expr.Match:scrutinee Expr.Match:arms Place.Field:base
Place.Index:base Place.Index:index Pattern.Constructor:args
""".split()}


class Tagged:
    def __init__(self, tag, fields=(), node=True):
        self.tag = tag
        self.fields = tuple(fields)
        self.node = node


class ArrayValue:
    def __init__(self, items):
        self.items = tuple(items)


class OptionValue:
    def __init__(self, value):
        self.value = value


def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)


def u16le(value):
    require(0 <= value < (1 << 16), "u16 out of range")
    return value.to_bytes(2, "little")


def u32le(value):
    require(0 <= value < (1 << 32), "u32 out of range")
    return value.to_bytes(4, "little")


def u256le(value):
    require(0 <= value <= MAX_U256, "u256 out of range")
    return value.to_bytes(32, "little")


def string(value):
    require(unicodedata.normalize("NFC", value) == value, "string is not NFC")
    raw = value.encode("utf-8")
    return u32le(len(raw)) + raw


def ident(value):
    raw = value.encode("utf-8")
    require(1 <= len(raw) <= 240, "ident length")
    require(unicodedata.normalize("NFC", value) == value, "ident is not NFC")
    require("\u00bb" not in value and not any(unicodedata.category(c) == "Cc" for c in value),
            "invalid ident scalar")
    return string(value)


def qualified(parts, minimum=1):
    require(minimum <= len(parts) <= 256, "qualified component count")
    return u32le(len(parts)) + b"".join(ident(part) for part in parts)


def scalar_tag(tag, *fields):
    return Tagged(tag, tuple(("", value) for value in fields), node=False)


def node(tag, *fields):
    return Tagged(tag, fields, node=True)


def array(*items):
    return ArrayValue(items)


def option(value=None):
    return OptionValue(value)


def encode(value, observed_tags):
    if isinstance(value, bytes):
        return value
    if isinstance(value, ArrayValue):
        return u32le(len(value.items)) + b"".join(encode(item, observed_tags) for item in value.items)
    if isinstance(value, OptionValue):
        if value.value is None:
            return b"\x00"
        return b"\x01" + encode(value.value, observed_tags)
    if isinstance(value, Tagged):
        observed_tags.add(value.tag)
        tag_bytes = value.tag.encode("ascii")
        fields = b"".join(encode(field_value, observed_tags)
                          for _field_name, field_value in value.fields)
        return u32le(len(tag_bytes)) + tag_bytes + u16le(len(value.fields)) + fields
    raise RuntimeError(f"unknown value type {type(value)!r}")


def immediate_children(value):
    if isinstance(value, Tagged) and value.node:
        return [value]
    if isinstance(value, ArrayValue):
        return [item for item in value.items if isinstance(item, Tagged) and item.node]
    if isinstance(value, OptionValue) and isinstance(value.value, Tagged) and value.value.node:
        return [value.value]
    return []


def canonical_visits(root):
    pending = [(root, ())]
    visits = []
    while pending:
        current, path = pending.pop()
        visits.append((current.tag, path))
        for field_name, value in reversed(current.fields):
            children = immediate_children(value)
            for index in range(len(children) - 1, -1, -1):
                pending.append((children[index], path + ((current.tag, field_name, index),)))
    return visits


def visibility(name):
    return scalar_tag(f"Visibility.{name}")


def type_null(name):
    return node(f"Type.{name}")


def type_uint(width):
    require(width in WIDTHS, "invalid uint width")
    return node("Type.UInt", ("width", u16le(width)))


def type_int(width):
    require(width in WIDTHS, "invalid int width")
    return node("Type.Int", ("width", u16le(width)))


def type_named(name):
    return node("Type.Named", ("name", ident(name)))


def type_array(element, length):
    require(0 <= length <= 4096, "array length")
    return node("Type.Array", ("element", element), ("length", u32le(length)))


def type_map(key, value):
    return node("Type.Map", ("key", key), ("value", value))


def type_option(element):
    return node("Type.Option", ("element", element))


def type_bytes(length):
    require(0 <= length <= 4096, "bytes length")
    return node("Type.Bytes", ("length", u32le(length)))


def type_field(field_id):
    require(field_id == "bn254_fr", "field id")
    return node("Type.Field", ("id", ident(field_id)))


def literal_bool(value):
    return scalar_tag("Literal.Bool", b"\x01" if value else b"\x00")


def literal_integer(value):
    return scalar_tag("Literal.Integer", u256le(value))


def literal_string(value):
    return scalar_tag("Literal.String", string(value))


def expr_literal(value):
    return node("Expr.Literal", ("literal", value))


def place_name(name):
    return node("Place.Name", ("name", ident(name)))


def place_field(base, field_name):
    return node("Place.Field", ("base", base), ("field", ident(field_name)))


def place_index(base, index):
    return node("Place.Index", ("base", base), ("index", index))


def expr_place(place):
    return node("Expr.Place", ("place", place))


def expr_constructor(name, args):
    return node("Expr.Constructor", ("constructor", qualified(name, 2)), ("args", ArrayValue(args)))


def expr_unary(op, operand):
    return node("Expr.Unary", ("op", scalar_tag(f"UnaryOp.{op}")), ("operand", operand))


def expr_binary(op, lhs, rhs):
    return node("Expr.Binary", ("op", scalar_tag(f"BinaryOp.{op}")),
                ("lhs", lhs), ("rhs", rhs))


def expr_local(callee, args):
    return node("Expr.LocalCall", ("callee", ident(callee)), ("args", ArrayValue(args)))


def pattern_wildcard():
    return node("Pattern.Wildcard")


def pattern_bind(name):
    return node("Pattern.Bind", ("name", ident(name)))


def pattern_literal(value):
    return node("Pattern.Literal", ("literal", value))


def pattern_constructor(name, args):
    return node("Pattern.Constructor", ("constructor", qualified(name, 2)),
                ("args", ArrayValue(args)))


def expr_arm(pattern, value):
    return node("ExprMatchArm", ("pattern", pattern), ("value", value))


def expr_match(scrutinee, arms):
    require(arms, "expression match arms")
    return node("Expr.Match", ("scrutinee", scrutinee), ("arms", ArrayValue(arms)))


def block(statements):
    require(statements, "block statements")
    return node("Block", ("statements", ArrayValue(statements)))


def external_call(callee, args):
    return node("ExternalCallExpr", ("callee", qualified(callee, 2)),
                ("args", ArrayValue(args)))


def stmt_arm(pattern, body):
    return node("StmtMatchArm", ("pattern", pattern), ("body", body))


def param(label, name, type_value):
    return node("Param", ("visibility", visibility(label)), ("name", ident(name)),
                ("type", type_value))


def field_decl(name, type_value):
    return node("FieldDecl", ("name", ident(name)), ("type", type_value))


def enum_variant(name, payload_types):
    return node("EnumVariant", ("name", ident(name)),
                ("payloadTypes", ArrayValue(payload_types)))


def build_fixture():
    """Source-derived ProgramV1 model for source-full-tag-v1/source.lean."""
    zero = expr_literal(literal_integer(0))
    maximum = expr_literal(literal_integer(MAX_U256))
    false_value = expr_literal(literal_bool(False))
    true_value = expr_literal(literal_bool(True))
    unicode_value = expr_literal(literal_string("café"))
    place = place_index(place_field(place_name("slot"), "value"), zero)
    place_expr = expr_place(place)
    ctor_empty = expr_constructor(["Choice", "Empty"], [])
    ctor_many = expr_constructor(["Choice", "Filled"], [true_value, unicode_value])
    unary = [expr_unary(name, zero) for name in ("Neg", "Not", "BitNot")]
    binary_names = ("Add", "Sub", "Mul", "Div", "Mod", "Eq", "Ne", "Lt", "Le",
                    "Gt", "Ge", "And", "Or", "BitAnd", "BitOr", "BitXor", "Shl", "Shr")
    binary = [expr_binary(name, zero, maximum) for name in binary_names]
    local_empty = expr_local("helper", [])
    local_many = expr_local("helper", [zero, maximum])
    rich_pattern = pattern_constructor(["Choice", "Filled"], [
        pattern_wildcard(), pattern_bind("bound"), pattern_literal(literal_bool(True)),
        pattern_constructor(["Choice", "Empty"], []),
    ])
    match_expr = expr_match(false_value, [
        expr_arm(rich_pattern, ctor_many),
        expr_arm(pattern_literal(literal_string("café")), local_empty),
    ])
    # Emit/call args intentionally omit match_expr (source places match only on return).
    emit_call_args = [zero, maximum, false_value, true_value, unicode_value, place_expr,
                      ctor_empty, ctor_many, *unary, *binary, local_empty, local_many]

    return_some = block([node("Stmt.Return", ("value", option(unicode_value)))])
    return_none = block([node("Stmt.Return", ("value", option()))])
    match_stmt = node("Stmt.Match", ("scrutinee", true_value), ("arms", array(
        stmt_arm(rich_pattern, block([node("Stmt.Assert", ("condition", true_value),
                                           ("error", option()))])),
        stmt_arm(pattern_bind("other"), return_some),
    )))
    loop_body = block([node("Stmt.Emit", ("event", ident("Changed")),
                            ("args", array(zero, unicode_value)))])
    init_body = block([
        node("Stmt.Let", ("name", ident("typedLocal")),
             ("typeAnn", option(type_option(type_null("Bool")))), ("value", ctor_many)),
        node("Stmt.Let", ("name", ident("plainLocal")),
             ("typeAnn", option()), ("value", local_empty)),
        node("Stmt.Assign", ("target", place), ("value", binary[0])),
        node("Stmt.If", ("condition", true_value), ("thenBlock", return_some),
             ("elseBlock", option(return_none))),
        node("Stmt.If", ("condition", false_value), ("thenBlock", return_none),
             ("elseBlock", option())),
        match_stmt,
        node("Stmt.For", ("binder", ident("i0")), ("start", zero),
             ("endExclusive", maximum), ("bound", u32le(0)), ("body", loop_body)),
        node("Stmt.For", ("binder", ident("i4096")), ("start", zero),
             ("endExclusive", maximum), ("bound", u32le(4096)), ("body", loop_body)),
        node("Stmt.Assert", ("condition", place_expr), ("error", option())),
        node("Stmt.Assert", ("condition", true_value), ("error", option(ident("Failure")))),
        node("Stmt.Revert", ("error", ident("Failure")), ("args", array())),
        node("Stmt.Revert", ("error", ident("Failure")), ("args", array(zero, maximum))),
        node("Stmt.Emit", ("event", ident("Changed")), ("args", ArrayValue(emit_call_args))),
        node("Stmt.Return", ("value", option(match_expr))),
        node("Stmt.Return", ("value", option())),
        node("Stmt.Call", ("call", external_call(["Peer", "perform"], emit_call_args))),
        node("Stmt.Schedule", ("call", external_call(["Peer", "followup"], []))),
    ])

    all_types = [type_null("Bool")]
    all_types += [type_uint(width) for width in sorted(WIDTHS)]
    all_types += [type_int(width) for width in sorted(WIDTHS)]
    all_types += [type_null("Principal"), type_null("String"), type_null("Unit"), type_named("Record")]
    all_types += [type_array(type_null("Bool"), 0), type_array(type_uint(8), 4096)]
    all_types += [type_map(type_uint(16), type_int(16)), type_option(type_null("Principal"))]
    all_types += [type_bytes(0), type_bytes(4096), type_field("bn254_fr")]

    items = [
        node("StateDecl", ("visibility", visibility("Public")), ("name", ident("cell")),
             ("type", type_array(type_null("Bool"), 1))),
        node("StructDecl", ("name", ident("Record")), ("fields", array(
            field_decl("first", type_null("Bool")),
            field_decl("café", type_map(type_uint(8), type_int(8))),
            field_decl("raw.with.dot", type_uint(64)),
        ))),
        node("EnumDecl", ("name", ident("Choice")), ("variants", array(
            enum_variant("Filled", all_types), enum_variant("Empty", []),
        ))),
        node("ConstDecl", ("name", ident("limit")), ("type", type_uint(256)),
             ("value", maximum)),
        node("EventDecl", ("name", ident("Changed")), ("params", array(
            param("Public", "who", type_null("Principal")),
            param("Private", "eventValue", type_uint(64)),
        ))),
        node("ErrorDecl", ("name", ident("Failure")), ("params", array(
            param("Commitment", "code", type_uint(32)),
        ))),
        node("InitDecl", ("params", array(
            param("Public", "seed", type_uint(64)),
            param("Private", "owner", type_null("Principal")),
        )), ("body", init_body)),
        node("EntryDecl", ("name", ident("run")),
             ("params", array(param("Public", "input", type_uint(64)))),
             ("result", type_map(type_uint(64), type_int(64))), ("body", return_some)),
        node("ViewDecl", ("name", ident("read")),
             ("params", array(param("Public", "key", type_uint(64)))),
             ("result", type_option(type_null("Bool"))), ("body", return_none)),
        node("FnDecl", ("name", ident("helper")),
             ("params", array(param("Public", "arg", type_field("bn254_fr")))),
             ("result", type_bytes(4096)),
             ("body", block([node("Stmt.Return", ("value", option(local_many)))]))),
        node("InvariantDecl", ("name", ident("safe")), ("predicate", true_value)),
        node("ExtensionReq", ("id", qualified(["ext", "demo"], 2)),
             ("version", string("1.0.0")),
             ("digest", string("sha256:" + "0" * 64))),
        node("ProofDecl", ("invariant", ident("safe")),
             ("theorem", qualified(["Golden", "theorem"], 2))),
    ]
    return node("Program", ("name", ident("FullTag")), ("items", ArrayValue(items)))


def walk_values(value):
    yield value
    if isinstance(value, Tagged):
        for _name, child in value.fields:
            yield from walk_values(child)
    elif isinstance(value, ArrayValue):
        for child in value.items:
            yield from walk_values(child)
    elif isinstance(value, OptionValue) and value.value is not None:
        yield from walk_values(value.value)


def option_coverage(root):
    result = {}
    for value in walk_values(root):
        if isinstance(value, Tagged):
            for field_name, child in value.fields:
                if isinstance(child, OptionValue):
                    result.setdefault((value.tag, field_name), set()).add(child.value is not None)
    return result


def tagged_field_u32(root, tag, index):
    values = set()
    for value in walk_values(root):
        if isinstance(value, Tagged) and value.tag == tag:
            raw = value.fields[index][1]
            require(isinstance(raw, bytes) and len(raw) == 4, f"{tag} field width")
            values.add(int.from_bytes(raw, "little"))
    return values


def tagged_field_u16(root, tag, index):
    values = set()
    for value in walk_values(root):
        if isinstance(value, Tagged) and value.tag == tag:
            raw = value.fields[index][1]
            require(isinstance(raw, bytes) and len(raw) == 2, f"{tag} field width")
            values.add(int.from_bytes(raw, "little"))
    return values


def tagged_field_bytes(root, tag, index):
    values = set()
    for value in walk_values(root):
        if isinstance(value, Tagged) and value.tag == tag:
            raw = value.fields[index][1]
            require(isinstance(raw, bytes), f"{tag} field bytes")
            values.add(raw)
    return values


def path_document(path):
    return [{"parentTag": parent, "fieldTag": field_name, "index": index}
            for parent, field_name, index in path]


def node_id(path):
    payload = {"module": MODULE, "program": PROGRAM_IDENTITY, "path": path_document(path)}
    jcs = json.dumps(payload, ensure_ascii=False, sort_keys=True,
                     separators=(",", ":")).encode("utf-8")
    digest = hashlib.sha256(b"pf.source-node.v1\0" + jcs).digest()[:16]
    return "nodeid:" + digest.hex()


def canonical_json(document):
    def compact(value):
        return json.dumps(value, ensure_ascii=False, sort_keys=True,
                          separators=(",", ":"))

    lines = ["{"]
    keys = sorted(document)
    for key_index, key in enumerate(keys):
        comma = "," if key_index + 1 < len(keys) else ""
        rendered_key = json.dumps(key, ensure_ascii=False)
        value = document[key]
        if isinstance(value, list):
            lines.append(f"  {rendered_key}: [")
            for item_index, item in enumerate(value):
                item_comma = "," if item_index + 1 < len(value) else ""
                lines.append(f"    {compact(item)}{item_comma}")
            lines.append(f"  ]{comma}")
        else:
            lines.append(f"  {rendered_key}: {compact(value)}{comma}")
    lines.append("}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def _path_tuple(path_doc):
    return tuple((seg["parentTag"], seg["fieldTag"], seg["index"]) for seg in path_doc)


def representative_spans(source_bytes, visits):
    """Pin representative exact production spans; verify against frozen source UTF-8.

    Offsets are source-derived (measured against source.lean). Each row is checked
    for path membership in the independent visit preorder and for UTF-8 slice
    contents, without reading Lean-emitted manifests.
    """
    visit_index = {path: tag for tag, path in visits}
    # Frozen exact spans for nested type/expr/escaped/Unicode coverage.
    frozen = [
        ("Program", [], 111, 6028, None),
        ("StateDecl",
         [{"parentTag": "Program", "fieldTag": "items", "index": 0}],
         135, 167, b"state public cell : Array Bool 1"),
        ("FieldDecl",
         [{"parentTag": "Program", "fieldTag": "items", "index": 1},
          {"parentTag": "StructDecl", "fieldTag": "fields", "index": 1}],
         211, 233, "café : Map UInt8 Int8".encode("utf-8")),
        ("FieldDecl",
         [{"parentTag": "Program", "fieldTag": "items", "index": 1},
          {"parentTag": "StructDecl", "fieldTag": "fields", "index": 2}],
         238, 263, "«raw.with.dot» : UInt64".encode("utf-8")),
        ("Type.Field",
         [{"parentTag": "Program", "fieldTag": "items", "index": 2},
          {"parentTag": "EnumDecl", "fieldTag": "variants", "index": 0},
          {"parentTag": "EnumVariant", "fieldTag": "payloadTypes", "index": 23}],
         517, 522, b"Field"),
        ("Expr.Literal",
         [{"parentTag": "Program", "fieldTag": "items", "index": 6},
          {"parentTag": "InitDecl", "fieldTag": "body", "index": 0},
          {"parentTag": "Block", "fieldTag": "statements", "index": 0},
          {"parentTag": "Stmt.Let", "fieldTag": "value", "index": 0},
          {"parentTag": "Expr.Constructor", "fieldTag": "args", "index": 1}],
         877, 884, "\"café\"".encode("utf-8")),
        ("Expr.Match",
         [{"parentTag": "Program", "fieldTag": "items", "index": 6},
          {"parentTag": "InitDecl", "fieldTag": "body", "index": 0},
          {"parentTag": "Block", "fieldTag": "statements", "index": 13},
          {"parentTag": "Stmt.Return", "fieldTag": "value", "index": 0}],
         3551, 3681, None),
        ("Stmt.Schedule",
         [{"parentTag": "Program", "fieldTag": "items", "index": 6},
          {"parentTag": "InitDecl", "fieldTag": "body", "index": 0},
          {"parentTag": "Block", "fieldTag": "statements", "index": 16}],
         5520, 5544, b"schedule Peer.followup()"),
        ("ExtensionReq",
         [{"parentTag": "Program", "fieldTag": "items", "index": 11}],
         5866, 5994, None),
        ("ProofDecl",
         [{"parentTag": "Program", "fieldTag": "items", "index": 12}],
         5997, 6028, b"proof safe using Golden.theorem"),
    ]
    rows = []
    for tag, path_doc, start, end, expected_slice in frozen:
        path = _path_tuple(path_doc)
        require(path in visit_index, f"representative path missing for {tag}")
        require(visit_index[path] == tag, f"representative tag mismatch for {tag}")
        require(0 <= start <= end <= len(source_bytes), f"span OOB for {tag}")
        slice_bytes = source_bytes[start:end]
        if expected_slice is not None:
            require(slice_bytes == expected_slice,
                    f"span slice mismatch for {tag}: {slice_bytes!r}")
        else:
            require(len(slice_bytes) > 0, f"empty span for {tag}")
        rows.append({
            "constructorTag": tag,
            "path": path_doc,
            "startByte": start,
            "endByte": end,
        })
    return rows


def expected_package(root):
    source_path = root / PACKAGE / SOURCE
    require(source_path.is_file(), f"missing source authority: {PACKAGE / SOURCE}")
    source_bytes = source_path.read_bytes()
    require(source_bytes.decode("utf-8").encode("utf-8") == source_bytes, "source must be UTF-8")

    root_ast = build_fixture()
    observed_tags = set()
    canonical = qualified(MODULE) + qualified(PROGRAM_IDENTITY, 2) + encode(root_ast, observed_tags)
    visits = canonical_visits(root_ast)
    node_tags = {tag for tag, _path in visits}
    edges = {(parent, field_name) for _tag, path in visits
             for parent, field_name, _index in path}
    paths = [path for _tag, path in visits]

    require(len(WIRE_TAGS) == 85 and observed_tags == WIRE_TAGS,
            f"wire tag inventory missing={sorted(WIRE_TAGS - observed_tags)} extra={sorted(observed_tags - WIRE_TAGS)}")
    require(len(NODE_TAGS) == 58 and node_tags == NODE_TAGS,
            f"node tag inventory missing={sorted(NODE_TAGS - node_tags)} extra={sorted(node_tags - NODE_TAGS)}")
    require(len(EDGE_PAIRS) == 63 and edges == EDGE_PAIRS,
            f"edge inventory missing={sorted(EDGE_PAIRS - edges)} extra={sorted(edges - EDGE_PAIRS)}")
    require(len(paths) == len(set(paths)), "node paths are not unique")
    items = root_ast.fields[1][1]
    require(isinstance(items, ArrayValue), "Program.items fixture shape")
    item_tags = {item.tag for item in items.items}
    require(len(items.items) == 13 and len(item_tags) == 13 and
            sum(item.tag == "InitDecl" for item in items.items) == 1,
            "13 unique ProgramItem alternatives and one init")
    # PA125-aligned shape coverage: fail closed if option/literal/array discriminants regress.
    require(tagged_field_u16(root_ast, "Type.UInt", 0) == WIDTHS, "UInt widths")
    require(tagged_field_u16(root_ast, "Type.Int", 0) == WIDTHS, "Int widths")
    require({0, 4096}.issubset(tagged_field_u32(root_ast, "Type.Array", 1)), "Array lengths")
    require({0, 4096}.issubset(tagged_field_u32(root_ast, "Type.Bytes", 0)), "Bytes lengths")
    require(tagged_field_u32(root_ast, "Stmt.For", 3) == {0, 4096}, "For bounds")
    require(tagged_field_bytes(root_ast, "Literal.Bool", 0) == {b"\x00", b"\x01"},
            "Bool false/true")
    require(tagged_field_bytes(root_ast, "Literal.Integer", 0) ==
            {u256le(0), u256le(MAX_U256)}, "Integer zero/max")
    array_sizes = {len(value.items) for value in walk_values(root_ast)
                   if isinstance(value, ArrayValue)}
    require(0 in array_sizes and 1 in array_sizes and any(size > 1 for size in array_sizes),
            "empty/single/multiple arrays")
    options = option_coverage(root_ast)
    for pair in (("Stmt.Let", "typeAnn"), ("Stmt.If", "elseBlock"),
                 ("Stmt.Assert", "error"), ("Stmt.Return", "value")):
        require(options.get(pair) == {False, True}, f"option coverage {pair}")
    require(any(isinstance(value, Tagged) and value.tag == "FieldDecl" and
                value.fields[0][1] == ident("café") for value in walk_values(root_ast)),
            "NFC Unicode Ident coverage")
    require(string("café") in tagged_field_bytes(root_ast, "Literal.String", 0),
            "NFC Unicode String coverage")
    require(len(canonical) <= 64 * 1024, "canonical binary exceeds frozen bound")

    rows = [{"constructorTag": tag, "path": path_document(path), "nodeId": node_id(path)}
            for tag, path in visits]
    reps = representative_spans(source_bytes, visits)
    document = {
        "canonicalBytesSha256": "sha256:" + hashlib.sha256(canonical).hexdigest(),
        "canonicalFile": CANONICAL,
        "caseId": CASE_ID,
        "edgePairs": [{"parentTag": parent, "fieldTag": field_name}
                      for parent, field_name in sorted(edges)],
        "expectedNodePathsAndIds": rows,
        "expectedSourceHash": "sha256:" + hashlib.sha256(b"pf.source.v1\0" + canonical).hexdigest(),
        "moduleName": MODULE,
        "nodeTags": sorted(node_tags),
        "programIdentity": PROGRAM_IDENTITY,
        "representativeSpans": reps,
        "schema": SCHEMA,
        "scope": SCOPE,
        "sourceByteDigest": "sha256:" + hashlib.sha256(source_bytes).hexdigest(),
        "sourceByteSize": len(source_bytes),
        "sourceFile": SOURCE,
        "spanCount": len(visits),
        "wireTags": sorted(observed_tags),
    }
    return canonical, document, source_bytes


def package_paths(root):
    directory = root / PACKAGE
    return directory, directory / MANIFEST, directory / CANONICAL, directory / SOURCE


def validate_checked_in(root):
    expected_binary, expected_document, _source = expected_package(root)
    directory, manifest_path, canonical_path, source_path = package_paths(root)
    require(directory.is_dir(), f"missing golden package directory: {PACKAGE}")
    names = {path.name for path in directory.iterdir() if path.is_file()}
    require(names == {MANIFEST, CANONICAL, SOURCE},
            f"golden package must contain exactly source.lean/manifest.json/canonical.bin, got {sorted(names)}")
    actual_manifest = manifest_path.read_bytes()
    actual_binary = canonical_path.read_bytes()
    require(actual_binary == expected_binary, "canonical.bin mismatch")
    require(actual_manifest == canonical_json(expected_document), "manifest.json mismatch")
    require(len(actual_manifest) <= 320 * 1024, "manifest exceeds frozen byte bound")
    require(source_path.read_bytes() == _source, "source.lean drift")


def atomic_write(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.",
                                         delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def emit(root):
    canonical, document, _source = expected_package(root)
    _directory, manifest_path, canonical_path, _source_path = package_paths(root)
    atomic_write(canonical_path, canonical)
    atomic_write(manifest_path, canonical_json(document))
    validate_checked_in(root)


def main(argv):
    root = Path(__file__).resolve().parents[1]
    try:
        if argv == ["--emit"]:
            emit(root)
            print("reference_source_program_v1_source_golden: emitted 1 85 58 63")
            return 0
        if argv == ["--self-check"]:
            validate_checked_in(root)
            print("reference_source_program_v1_source_golden: ok 1 85 58 63")
            return 0
        print("usage: reference_source_program_v1_source_golden.py --emit|--self-check",
              file=sys.stderr)
        return 2
    except (OSError, RuntimeError, ValueError) as error:
        print(f"reference_source_program_v1_source_golden: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

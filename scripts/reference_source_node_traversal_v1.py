#!/usr/bin/env python3
"""Independent canonical ProgramV1 node-preorder oracle for D1-PA-121."""

import hashlib
import sys

MAX_DEPTH_EDGES = 255
MAX_NODES = 100000
DEPTH_ERROR = "source node traversal exceeds the nesting bound"
NODE_ERROR = "source node traversal exceeds the node limit"


class TraversalError(Exception):
    pass


def node(tag, *fields):
    return (tag, list(fields))


def field(name, *children):
    return (name, list(children))


N = node
F = field


def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)


def canonical_visits(root):
    pending = [(root, ())]
    visits = []
    while pending:
        current, path = pending.pop()
        if len(visits) >= MAX_NODES:
            raise TraversalError(NODE_ERROR)
        tag, fields = current
        visits.append((tag, path))
        for field_name, children in reversed(fields):
            if len(children) > MAX_NODES:
                raise TraversalError(NODE_ERROR)
            if children and len(path) >= MAX_DEPTH_EDGES:
                raise TraversalError(DEPTH_ERROR)
            for index in range(len(children) - 1, -1, -1):
                pending.append((children[index], path + ((tag, field_name, index),)))
    return visits


def inventory_text(visits):
    lines = []
    for tag, path in visits:
        rendered = "/".join(
            f"{parent}.{field_name}[{index}]"
            for parent, field_name, index in path
        )
        lines.append(f"{tag}|{rendered}\n")
    return "".join(lines)


def inventory_sha256(visits):
    return hashlib.sha256(inventory_text(visits).encode("utf-8")).hexdigest()


def expr_leaf():
    return N("Expr.Literal")


def return_block(present=True):
    value = F("value", expr_leaf()) if present else F("value")
    return N("Block", F("statements", N("Stmt.Return", value)))


def type_inventory():
    return [
        N("Type.Bool"), N("Type.UInt"), N("Type.Int"), N("Type.Principal"),
        N("Type.Unit"), N("Type.Named"),
        N("Type.Array", F("element", N("Type.Bool"))),
        N("Type.Map", F("key", N("Type.UInt")), F("value", N("Type.Int"))),
        N("Type.Option", F("element", N("Type.Principal"))),
        N("Type.Bytes"), N("Type.Field"),
    ]


def rich_pattern():
    return N("Pattern.Constructor", F("args",
        N("Pattern.Wildcard"), N("Pattern.Bind"), N("Pattern.Literal"),
        N("Pattern.Constructor", F("args"))))


def place_tree():
    return N("Place.Index",
        F("base", N("Place.Field", F("base", N("Place.Name")))),
        F("index", expr_leaf()))


def expression_inventory():
    literal = expr_leaf()
    place = N("Expr.Place", F("place", place_tree()))
    constructor = N("Expr.Constructor", F("args", expr_leaf(),
        N("Expr.Place", F("place", N("Place.Name")))))
    unary = N("Expr.Unary", F("operand", expr_leaf()))
    binary = N("Expr.Binary", F("lhs", expr_leaf()), F("rhs", expr_leaf()))
    local = N("Expr.LocalCall", F("args", expr_leaf(), unary))
    match_expr = N("Expr.Match", F("scrutinee", expr_leaf()), F("arms",
        N("ExprMatchArm", F("pattern", rich_pattern()), F("value", binary)),
        N("ExprMatchArm", F("pattern", N("Pattern.Wildcard")),
          F("value", N("Expr.LocalCall", F("args"))))))
    return [literal, place, constructor, unary, binary, local, match_expr]


def rich_block():
    expressions = expression_inventory()
    external_all = N("ExternalCallExpr", F("args", *expressions))
    match_stmt = N("Stmt.Match", F("scrutinee", expr_leaf()), F("arms",
        N("StmtMatchArm", F("pattern", rich_pattern()),
          F("body", N("Block", F("statements",
            N("Stmt.Assert", F("condition", expr_leaf())))))),
        N("StmtMatchArm", F("pattern", N("Pattern.Bind")),
          F("body", return_block()))))
    statements = [
        N("Stmt.Let",
          F("typeAnn", N("Type.Option", F("element", N("Type.Bool")))),
          F("value", expressions[2])),
        N("Stmt.Assign", F("target", place_tree()), F("value", expressions[4])),
        N("Stmt.If", F("condition", expr_leaf()),
          F("thenBlock", return_block()), F("elseBlock", return_block(False))),
        match_stmt,
        N("Stmt.For", F("start", expr_leaf()), F("endExclusive", expressions[4]),
          F("body", N("Block", F("statements",
            N("Stmt.Emit", F("args", expr_leaf(), expressions[3])))))),
        N("Stmt.Assert", F("condition", expressions[1])),
        N("Stmt.Revert", F("args", expr_leaf(), expressions[2])),
        N("Stmt.Emit", F("args", expressions[5], expressions[6])),
        N("Stmt.Return", F("value", expressions[3])),
        N("Stmt.Call", F("call", external_all)),
        N("Stmt.Schedule", F("call",
          N("ExternalCallExpr", F("args", expr_leaf())))),
    ]
    return N("Block", F("statements", *statements))


def comprehensive_program():
    all_types = type_inventory()
    items = [
        N("StateDecl", F("type", N("Type.Array", F("element", N("Type.Bool"))))),
        N("StructDecl", F("fields",
          N("FieldDecl", F("type", N("Type.Bool"))),
          N("FieldDecl", F("type", N("Type.Map",
            F("key", N("Type.UInt")), F("value", N("Type.Int"))))))),
        N("EnumDecl", F("variants",
          N("EnumVariant", F("payloadTypes", *all_types)),
          N("EnumVariant", F("payloadTypes")))),
        N("ConstDecl",
          F("type", N("Type.Option", F("element", N("Type.Bool")))),
          F("value", expression_inventory()[6])),
        N("EventDecl", F("params",
          N("Param", F("type", N("Type.Bool"))),
          N("Param", F("type", N("Type.Array", F("element", N("Type.UInt"))))))),
        N("ErrorDecl", F("params",
          N("Param", F("type", N("Type.Map",
            F("key", N("Type.UInt")), F("value", N("Type.Int"))))))),
        N("InitDecl", F("params",
          N("Param", F("type", N("Type.Named"))),
          N("Param", F("type", N("Type.Principal")))), F("body", rich_block())),
        N("EntryDecl", F("params", N("Param", F("type", N("Type.Bool")))),
          F("result", N("Type.Map", F("key", N("Type.UInt")),
            F("value", N("Type.Int")))), F("body", return_block())),
        N("ViewDecl", F("params", N("Param", F("type", N("Type.Unit")))),
          F("result", N("Type.Option", F("element", N("Type.Bool")))),
          F("body", return_block(False))),
        N("FnDecl", F("params", N("Param", F("type", N("Type.Field")))),
          F("result", N("Type.Bytes")), F("body", return_block())),
        N("InvariantDecl", F("predicate", expression_inventory()[1])),
        N("ExtensionReq"), N("ProofDecl"),
    ]
    return N("Program", F("items", *items))


NODE_TAGS = set("""
Program StateDecl StructDecl EnumDecl ConstDecl EventDecl ErrorDecl InitDecl
EntryDecl ViewDecl FnDecl InvariantDecl ExtensionReq ProofDecl Param FieldDecl
EnumVariant Block StmtMatchArm ExprMatchArm ExternalCallExpr Type.Bool Type.UInt
Type.Int Type.Principal Type.Unit Type.Named Type.Array Type.Map Type.Option
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

EXPECTED_COUNT = 214
EXPECTED_SHA256 = "b7ff1648d1679d5a598621dc6f83101c51ffce57a86c804c13b00d117396b3e0"
EXPECTED_ABSENCE_SHA256 = "5fcb4463c92481e6514a8600721fc53d6b119e4eae95dbdd4c4a8130750fbcd2"


def nested_option_program(count):
    value = N("Type.Bool")
    for _ in range(count):
        value = N("Type.Option", F("element", value))
    return N("Program", F("items", N("StateDecl", F("type", value))))


def wide_program(item_count):
    return N("Program", F("items", *([N("ExtensionReq")] * item_count)))


def absence_program():
    block = N("Block", F("statements",
        N("Stmt.Let", F("typeAnn"), F("value", expr_leaf())),
        N("Stmt.If", F("condition", expr_leaf()),
          F("thenBlock", return_block(False)), F("elseBlock")),
        N("Stmt.Return", F("value")), N("Stmt.Revert", F("args"))))
    return N("Program", F("items",
        N("InitDecl", F("params"), F("body", block))))


def expect_error(label, expected, operation):
    try:
        operation()
    except TraversalError as error:
        require(str(error) == expected, f"{label}: {error}")
        return
    raise RuntimeError(f"{label}: unexpectedly succeeded")


def self_check():
    visits = canonical_visits(comprehensive_program())
    tags = {tag for tag, _path in visits}
    pairs = {segment[:2] for _tag, path in visits for segment in path}
    paths = [path for _tag, path in visits]
    require(len(NODE_TAGS) == 57 and tags == NODE_TAGS, "closed tag inventory")
    require(len(EDGE_PAIRS) == 63 and pairs == EDGE_PAIRS, "closed edge inventory")
    require(len(paths) == len(set(paths)), "comprehensive paths must be unique")
    require(len(visits) == EXPECTED_COUNT, f"comprehensive count: {len(visits)}")
    require(inventory_sha256(visits) == EXPECTED_SHA256,
            f"comprehensive sha256: {inventory_sha256(visits)}")

    absent = canonical_visits(absence_program())
    require(inventory_sha256(absent) == EXPECTED_ABSENCE_SHA256,
            f"absence sha256: {inventory_sha256(absent)}")
    absent_pairs = {segment[:2] for _tag, path in absent for segment in path}
    forbidden = {("Stmt.Let", "typeAnn"), ("Stmt.If", "elseBlock"),
                 ("Stmt.Return", "value"), ("Stmt.Revert", "args")}
    require(absent_pairs.isdisjoint(forbidden), "absent/empty child emitted a visit")

    at_depth = canonical_visits(nested_option_program(253))
    require(len(at_depth) == 256, f"depth-limit count: {len(at_depth)}")
    expect_error("over-depth", DEPTH_ERROR,
                 lambda: canonical_visits(nested_option_program(254)))

    at_nodes = canonical_visits(wide_program(99999))
    require(len(at_nodes) == MAX_NODES, f"node-limit count: {len(at_nodes)}")
    expect_error("over-nodes", NODE_ERROR,
                 lambda: canonical_visits(wide_program(100000)))


def main(argv):
    if argv != ["--self-check"]:
        print("usage: reference_source_node_traversal_v1.py --self-check", file=sys.stderr)
        return 2
    try:
        self_check()
    except (RuntimeError, TraversalError) as error:
        print(f"reference_source_node_traversal_v1: FAIL: {error}", file=sys.stderr)
        return 1
    print("reference_source_node_traversal_v1: ok 4 2")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Independent source-raw NodeId preimage/truncation oracle for D1-PA-120/122."""

import hashlib
import json
import sys

DOMAIN = b"pf.source-node.v1\x00"
CARDINALITY = {
    ("Program", "items"): "array",
    ("StateDecl", "type"): "direct",
    ("ConstDecl", "type"): "direct",
    ("Type.Map", "key"): "direct",
    ("Type.Map", "value"): "direct",
}
ITEM_TAGS = {"StateDecl", "ConstDecl"}
TYPE_TAGS = {"Type.Bool", "Type.Map", "Type.Option"}


class PreimageError(Exception):
    pass


def fail(detail):
    raise PreimageError(detail)


def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)


def validate_identity(module_name, program_identity):
    if not 2 <= len(program_identity) <= 256:
        fail("source qualified id must contain 2..256 components")
    if len(program_identity) <= len(module_name):
        fail("program identity must strictly extend the module name")
    if program_identity[:len(module_name)] != module_name:
        fail("program identity must begin with the exact module name components")


def permits_child(previous, child_tag):
    edge = (previous["parentTag"], previous["fieldTag"])
    if edge == ("Program", "items"):
        return child_tag in ITEM_TAGS
    if edge in {("StateDecl", "type"), ("ConstDecl", "type"),
                ("Type.Map", "key"), ("Type.Map", "value")}:
        return child_tag in TYPE_TAGS
    return False


def validate_path(path):
    if len(path) > 255:
        fail("source node path exceeds the nesting bound")
    previous = None
    for edge in path:
        if previous is None:
            if edge["parentTag"] != "Program":
                fail("non-root source node paths must begin at Program")
        elif not permits_child(previous, edge["parentTag"]):
            fail("source node path contains an impossible constructor transition")
        cardinality = CARDINALITY.get((edge["parentTag"], edge["fieldTag"]))
        if cardinality is None:
            fail("source node path contains an unknown constructor/field pair")
        if cardinality == "direct" and edge["index"] != 0:
            fail("direct source node path fields require index zero")
        previous = edge


def node_id_preimage(module_name, program_identity, path):
    validate_identity(module_name, program_identity)
    validate_path(path)
    value = {"module": module_name, "program": program_identity, "path": path}
    canonical = json.dumps(value, ensure_ascii=False, separators=(",", ":"),
                           sort_keys=True).encode("utf-8")
    return DOMAIN + canonical


def node_id_text(preimage):
    return "nodeid:" + hashlib.sha256(preimage).digest()[:16].hex()


def edge(parent_tag, field_tag, index=0):
    return {"parentTag": parent_tag, "fieldTag": field_tag, "index": index}


def expect_error(label, expected, thunk):
    try:
        thunk()
    except PreimageError as error:
        require(str(error) == expected, f"{label}: expected {expected}, got {error}")
        return
    raise RuntimeError(f"{label}: unexpectedly succeeded")


def self_check():
    root_hex = (
        "70662e736f757263652d6e6f64652e7631007b226d6f64756c65223a5b2244656d6f"
        "225d2c2270617468223a5b5d2c2270726f6772616d223a5b2244656d6f222c22436f75"
        "6e746572225d7d")
    root = node_id_preimage(["Demo"], ["Demo", "Counter"], [])
    require(root.hex() == root_hex, "positive-1: root bytes")
    require(hashlib.sha256(root).hexdigest() ==
            "58c75af894b6f832163564705c9f23ef3a02df045126baf9492f89844f7ef08f",
            "positive-1: root hash")
    require(node_id_text(root) == "nodeid:58c75af894b6f832163564705c9f23ef",
            "positive-1: root NodeId")

    item_hex = (
        "70662e736f757263652d6e6f64652e7631007b226d6f64756c65223a5b2244656d6f"
        "225d2c2270617468223a5b7b226669656c64546167223a226974656d73222c22696e64"
        "6578223a302c22706172656e74546167223a2250726f6772616d227d5d2c2270726f67"
        "72616d223a5b2244656d6f222c22436f756e746572225d7d")
    item_path = [edge("Program", "items")]
    item = node_id_preimage(["Demo"], ["Demo", "Counter"], item_path)
    require(item.hex() == item_hex, "positive-2: item bytes")
    require(hashlib.sha256(item).hexdigest() ==
            "17ac87bb9262ace7d062c77c38a17d0ddcd69fbff4e7927ed8fe9d02af454822",
            "positive-2: item hash")
    require(node_id_text(item) == "nodeid:17ac87bb9262ace7d062c77c38a17d0d",
            "positive-2: item NodeId")

    raw_hex = (
        "70662e736f757263652d6e6f64652e7631007b226d6f64756c65223a5b22412e4222"
        "5d2c2270617468223a5b7b226669656c64546167223a226974656d73222c22696e6465"
        "78223a312c22706172656e74546167223a2250726f6772616d227d5d2c2270726f6772"
        "616d223a5b22412e42222c22505c22515c5c52225d7d")
    raw_path = [edge("Program", "items", 1)]
    raw = node_id_preimage(["A.B"], ["A.B", 'P"Q\\R'], raw_path)
    require(raw.hex() == raw_hex, "positive-3: raw escaped bytes")
    require(hashlib.sha256(raw).hexdigest() ==
            "1d20bd4f37f942a52977fa9aade547fb0cbe5317f04f777ca50973de99e1e495",
            "positive-3: raw escaped hash")
    require(node_id_text(raw) == "nodeid:1d20bd4f37f942a52977fa9aade547fb",
            "positive-3: raw escaped NodeId")

    split = node_id_preimage(["A", "B"], ["A", "B", 'P"Q\\R'], raw_path)
    parent_a = node_id_preimage(["Demo"], ["Demo", "Counter"],
                                [edge("Program", "items"), edge("StateDecl", "type")])
    parent_b = node_id_preimage(["Demo"], ["Demo", "Counter"],
                                [edge("Program", "items"), edge("ConstDecl", "type")])
    field_a = node_id_preimage(["Demo"], ["Demo", "Counter"],
        [edge("Program", "items"), edge("StateDecl", "type"), edge("Type.Map", "key")])
    field_b = node_id_preimage(["Demo"], ["Demo", "Counter"],
        [edge("Program", "items"), edge("StateDecl", "type"), edge("Type.Map", "value")])
    require(raw != split and parent_a != parent_b and field_a != field_b and item != raw,
            "positive-4: raw/parent/field/index sensitivity")
    require(node_id_text(raw) != node_id_text(split) and
            node_id_text(parent_a) != node_id_text(parent_b) and
            node_id_text(field_a) != node_id_text(field_b) and
            node_id_text(item) != node_id_text(raw),
            "positive-4: candidate sensitivity")

    expect_error("negative-1", "source qualified id must contain 2..256 components",
                 lambda: node_id_preimage(["Demo"], ["Demo"], []))
    expect_error("negative-2", "program identity must strictly extend the module name",
                 lambda: node_id_preimage(["Demo", "Inner"], ["Demo", "Inner"], []))
    expect_error("negative-3", "program identity must begin with the exact module name components",
                 lambda: node_id_preimage(["Demo"], ["Elsewhere", "Counter"], []))
    expect_error("negative-4", "source node path contains an unknown constructor/field pair",
                 lambda: node_id_preimage(["Demo"], ["Demo", "Counter"],
                                          [edge("Program", "name")]))
    expect_error("negative-5", "source node path contains an unknown constructor/field pair",
                 lambda: node_id_preimage(["Demo"], ["Demo", "Counter"],
                                          [edge("Program", "fields")]))
    expect_error("negative-6", "non-root source node paths must begin at Program",
                 lambda: node_id_preimage(["Demo"], ["Demo", "Counter"],
                                          [edge("Type.Map", "key")]))
    expect_error("negative-7", "source node path contains an impossible constructor transition",
                 lambda: node_id_preimage(["Demo"], ["Demo", "Counter"],
                    [edge("Program", "items"), edge("Type.Map", "key")]))
    expect_error("negative-8", "direct source node path fields require index zero",
                 lambda: node_id_preimage(["Demo"], ["Demo", "Counter"],
                    [edge("Program", "items"), edge("StateDecl", "type", 1)]))
    over = [edge("Program", "items")] + [edge("StateDecl", "type")] + \
        [edge("Type.Map", "key")] * 254
    expect_error("negative-9", "source node path exceeds the nesting bound",
                 lambda: node_id_preimage(["Demo"], ["Demo", "Counter"], over))


def main(argv):
    if argv != ["--self-check"]:
        print("usage: reference_source_node_id_preimage_v1.py --self-check", file=sys.stderr)
        return 2
    self_check()
    print("reference_source_node_id_preimage_v1: ok 4 9")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

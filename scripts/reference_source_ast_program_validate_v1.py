#!/usr/bin/env python3
"""Independent PA105 ProgramV1 declaration-set validation oracle (no Lean/ProofForge, stdlib only)."""
import sys
E = {
"init_max": "program must declare at most one init",
"need_callable": "program must declare at least one entry or view",
"state_dup": "program contains duplicate state declarations",
"entryview_dup": "program contains duplicate entry/view declarations",
"event_dup": "program contains duplicate event declarations",
"error_dup": "program contains duplicate error declarations",
"struct_dup": "program contains duplicate struct declarations",
"enum_dup": "program contains duplicate enum declarations",
"const_dup": "program contains duplicate const declarations",
"fn_dup": "program contains duplicate fn declarations",
"callable_dup": "program contains duplicate callable declarations",
"invariant_dup": "program contains duplicate invariant declarations",
"ext_dup": "program contains duplicate extension requirements",
"proof_dup": "program contains duplicate proof references",
}
def unknown_inv(x): return f"proof reference names unknown invariant '{x}'"
def dup_fields(k, x): return f"{k} '{x}' contains duplicate fields"
def dup_variants(k, x): return f"{k} '{x}' contains duplicate variants"
def dup_params(k, x): return f"{k} '{x}' contains duplicate parameters"
def dup_any(seq):
    seen = set()
    for v in seq:
        if v in seen: return True
        seen.add(v)
    return False
def names(items, kind):
    return [it["name"] for it in items if it["kind"] == kind]
def validate(items):
    """22-rule fixed category order; source order within each rule."""
    # 1 multiple init
    if sum(1 for it in items if it["kind"] == "init") > 1: raise ValueError(E["init_max"])
    # 2 zero entry/view
    if not any(it["kind"] in ("entry", "view") for it in items): raise ValueError(E["need_callable"])
    # 3..10 per-kind name uniqueness (entry+view share one namespace at rule 4)
    for rule, kinds in (("state_dup", ("state",)), ("entryview_dup", ("entry", "view")),
                        ("event_dup", ("event",)), ("error_dup", ("error",)),
                        ("struct_dup", ("struct",)), ("enum_dup", ("enum",)),
                        ("const_dup", ("const",)), ("fn_dup", ("fn",))):
        if dup_any([it["name"] for it in items if it["kind"] in kinds]): raise ValueError(E[rule])
    # 11 callable namespace (entry/view/fn combined)
    if dup_any([it["name"] for it in items if it["kind"] in ("entry", "view", "fn")]):
        raise ValueError(E["callable_dup"])
    # 12 invariant names
    if dup_any(names(items, "invariant")): raise ValueError(E["invariant_dup"])
    # 13 extension ID component-array equality
    if dup_any([tuple(it["id"]) for it in items if it["kind"] == "extension"]):
        raise ValueError(E["ext_dup"])
    # 14 at most one proof reference per invariant (source order)
    seen = set()
    for it in items:
        if it["kind"] == "proof":
            if it["invariant"] in seen: raise ValueError(E["proof_dup"])
            seen.add(it["invariant"])
    # 15 proof reference binds a declared invariant
    declared = {it["name"] for it in items if it["kind"] == "invariant"}
    for it in items:
        if it["kind"] == "proof" and it["invariant"] not in declared:
            raise ValueError(unknown_inv(it["invariant"]))
    # 16..22 intra-record params/fields/variants in fixed kind order
    for it in items:
        if it["kind"] == "init" and dup_any(it.get("params", [])):
            raise ValueError("initializer contains duplicate parameters")
    for it in items:
        if it["kind"] == "struct" and dup_any(it.get("fields", [])):
            raise ValueError(dup_fields("struct", it["name"]))
    for it in items:
        if it["kind"] == "enum" and dup_any(it.get("variants", [])):
            raise ValueError(dup_variants("enum", it["name"]))
    for kind in ("event", "error", "entry", "view", "fn"):
        for it in items:
            if it["kind"] == kind and dup_any(it.get("params", [])):
                raise ValueError(dup_params(kind, it["name"]))
def encode(items):
    """Serializer-neutrality model: encoding NEVER runs set validation."""
    return b"".join(f"<{it['kind']}:{it.get('name', '')}>".encode() for it in items)
# fixtures
P = lambda n: {"kind": "invariant", "name": n}
def base():
    return [
        {"kind": "state", "name": "count"}, {"kind": "struct", "name": "Store", "fields": ["total", "flag"]},
        {"kind": "enum", "name": "Choice", "variants": ["None", "Some"]},
        {"kind": "const", "name": "max"}, {"kind": "event", "name": "Ping", "params": []},
        {"kind": "error", "name": "Denied", "params": ["who"]},
        {"kind": "extension", "id": ["Demo", "Feature"], "version": "1.0.0", "digest": "sha256:00"},
        {"kind": "proof", "name": "safe", "invariant": "safe"}, P("safe"),
        {"kind": "init", "params": ["start"]},
        {"kind": "entry", "name": "run", "params": ["to"]},
        {"kind": "view", "name": "get", "params": []},
        {"kind": "fn", "name": "helper", "params": ["x"]},
    ]
G = {
"positive_full": base(),
"positive_proof_forward": [{"kind": "proof", "name": "bounded", "invariant": "bounded"},
    {"kind": "invariant", "name": "bounded"},
    {"kind": "entry", "name": "run", "params": []}],
"positive_view_only": [{"kind": "state", "name": "count"}, {"kind": "view", "name": "get", "params": []}],
}
NEG = [
("init_max", [{"kind": "init", "params": []}, {"kind": "init", "params": []}, {"kind": "entry", "name": "run", "params": []}], E["init_max"]),
("need_callable", [{"kind": "state", "name": "count"}], E["need_callable"]),
("state_dup", [{"kind": "state", "name": "count"}, {"kind": "state", "name": "count"}, {"kind": "entry", "name": "run", "params": []}], E["state_dup"]),
("entryview_dup", [{"kind": "entry", "name": "run", "params": []}, {"kind": "view", "name": "run", "params": []}], E["entryview_dup"]),
("event_dup", [{"kind": "event", "name": "Ping", "params": []}, {"kind": "event", "name": "Ping", "params": []}, {"kind": "entry", "name": "run", "params": []}], E["event_dup"]),
("error_dup", [{"kind": "error", "name": "Denied", "params": []}, {"kind": "error", "name": "Denied", "params": []}, {"kind": "entry", "name": "run", "params": []}], E["error_dup"]),
("struct_dup", [{"kind": "struct", "name": "Store", "fields": []}, {"kind": "struct", "name": "Store", "fields": []}, {"kind": "entry", "name": "run", "params": []}], E["struct_dup"]),
("enum_dup", [{"kind": "enum", "name": "Choice", "variants": []}, {"kind": "enum", "name": "Choice", "variants": []}, {"kind": "entry", "name": "run", "params": []}], E["enum_dup"]),
("const_dup", [{"kind": "const", "name": "max"}, {"kind": "const", "name": "max"}, {"kind": "entry", "name": "run", "params": []}], E["const_dup"]),
("fn_dup", [{"kind": "fn", "name": "helper", "params": []}, {"kind": "fn", "name": "helper", "params": []}, {"kind": "entry", "name": "run", "params": []}], E["fn_dup"]),
("callable_dup", [{"kind": "entry", "name": "run", "params": []}, {"kind": "fn", "name": "run", "params": []}], E["callable_dup"]),
("invariant_dup", [P("safe"), P("safe"), {"kind": "entry", "name": "run", "params": []}], E["invariant_dup"]),
("ext_dup", [{"kind": "extension", "id": ["Demo", "Feature"], "version": "1.0.0", "digest": "sha256:00"},
    {"kind": "extension", "id": ["Demo", "Feature"], "version": "2.0.0", "digest": "sha256:11"},
    {"kind": "entry", "name": "run", "params": []}], E["ext_dup"]),
("proof_dup", [P("safe"), {"kind": "proof", "name": "p1", "invariant": "safe"}, {"kind": "proof", "name": "p2", "invariant": "safe"}, {"kind": "entry", "name": "run", "params": []}], E["proof_dup"]),
("proof_unknown", [{"kind": "proof", "name": "p1", "invariant": "ghost"}, {"kind": "entry", "name": "run", "params": []}], unknown_inv("ghost")),
("init_params", [{"kind": "init", "params": ["a", "a"]}, {"kind": "entry", "name": "run", "params": []}], "initializer contains duplicate parameters"),
("struct_fields", [{"kind": "struct", "name": "Store", "fields": ["x", "x"]}, {"kind": "entry", "name": "run", "params": []}], dup_fields("struct", "Store")),
("enum_variants", [{"kind": "enum", "name": "Choice", "variants": ["A", "A"]}, {"kind": "entry", "name": "run", "params": []}], dup_variants("enum", "Choice")),
("event_params", [{"kind": "event", "name": "Ping", "params": ["a", "a"]}, {"kind": "entry", "name": "run", "params": []}], dup_params("event", "Ping")),
("error_params", [{"kind": "error", "name": "Denied", "params": ["w", "w"]}, {"kind": "entry", "name": "run", "params": []}], dup_params("error", "Denied")),
("entry_params", [{"kind": "entry", "name": "run", "params": ["a", "a"]}], dup_params("entry", "run")),
("view_params", [{"kind": "view", "name": "get", "params": ["a", "a"]}], dup_params("view", "get")),
("fn_params", [{"kind": "fn", "name": "helper", "params": ["x", "x"]}, {"kind": "entry", "name": "run", "params": []}], dup_params("fn", "helper")),
]
PRIO = [
("p1_init_before_zero", [{"kind": "init", "params": []}, {"kind": "init", "params": []}], E["init_max"]),
("p2_zero_before_state", [{"kind": "state", "name": "count"}, {"kind": "state", "name": "count"}], E["need_callable"]),
("p3_state_before_entry", [{"kind": "state", "name": "x"}, {"kind": "state", "name": "x"},
    {"kind": "entry", "name": "run", "params": []}, {"kind": "entry", "name": "run", "params": []}], E["state_dup"]),
("p4_event_before_struct", [{"kind": "event", "name": "Ping", "params": []}, {"kind": "event", "name": "Ping", "params": []},
    {"kind": "struct", "name": "S", "fields": []}, {"kind": "struct", "name": "S", "fields": []}, {"kind": "entry", "name": "run", "params": []}], E["event_dup"]),
("p5_fn_before_callable", [{"kind": "fn", "name": "run", "params": []}, {"kind": "fn", "name": "run", "params": []},
    {"kind": "entry", "name": "run", "params": []}], E["fn_dup"]),
("p6_state_before_unknown_proof", [{"kind": "state", "name": "x"}, {"kind": "state", "name": "x"},
    {"kind": "proof", "name": "p", "invariant": "ghost"}, {"kind": "entry", "name": "run", "params": []}], E["state_dup"]),
("p7_profdup_before_unknown", [P("safe"), {"kind": "proof", "name": "p1", "invariant": "safe"},
    {"kind": "proof", "name": "p2", "invariant": "safe"}, {"kind": "proof", "name": "p3", "invariant": "ghost"},
    {"kind": "entry", "name": "run", "params": []}], E["proof_dup"]),
]
def self_check():
    for k, items in G.items():
        validate(items)
        encode(items)  # serializer stays neutral
    for name, items, want in NEG + PRIO:
        try:
            validate(items)
            raise SystemExit(f"{name}: unexpectedly ok")
        except ValueError as e:
            if str(e) != want: raise SystemExit(f"{name}: got '{e}' want '{want}'")
    bad = base() + [{"kind": "state", "name": "count"}]
    encode(bad)  # duplicate-state program still ENCODES (serializer neutrality)
    try:
        validate(bad)
        raise SystemExit("neutrality: validate must reject")
    except ValueError as e:
        if str(e) != E["state_dup"]: raise SystemExit(f"neutrality: {e}")
    print("reference_source_ast_program_validate_v1: ok", len(G), len(NEG), len(PRIO))
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_program_validate_v1.py --self-check")

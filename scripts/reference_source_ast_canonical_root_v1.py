#!/usr/bin/env python3
"""Independent PA104 canonical-root wire oracle (no Lean/ProofForge, stdlib only).
Root hex are checked-in literals from /tmp/pa104_python_root_probe.md, never computed at runtime."""
import sys, unicodedata
QID_ERR = "source qualified id must contain 2..256 components"
LONGER_ERR = "program identity must strictly extend the module name"
PREFIX_ERR = "program identity must begin with the exact module name components"
NAME_ERR = "program name must equal the last program identity component"
ITEMS_ERR = "program items must be nonempty"
STRUCT_ERR = "struct fields must be nonempty"
W_ERR = "integer width must be one of 8,16,32,64,128,256"
U256_ERR = "u256 magnitude exceeds 2^256-1"
LIT_STATE_OK = ("0100000004000000526f6f740200000004000000526f6f740400000044656d6f0700000050726f6772616d02000400000044656d6f01000000"
"0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000")
LIT_TWO_ORDER = ("0100000004000000526f6f740200000004000000526f6f740400000044656d6f0700000050726f6772616d02000400000044656d6f02000000"
"0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
"09000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c0100"
"0f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000")
LIT_DEEP_MOD = ("02000000010000004101000000420300000001000000410100000042040000004d61696e0700000050726f6772616d0200040000004d61696e01000000"
"0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000")
def u16le(v): return bytes((v & 255, (v >> 8) & 255))
def u32le(v): return bytes((v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255))
def u256le(n):
    if not 0 <= n < (1 << 256): raise ValueError(U256_ERR)
    return n.to_bytes(32, "little")
def _force(x): return x() if callable(x) else x
def enc_str(s):
    if unicodedata.normalize("NFC", s) != s: raise ValueError("non-NFC")
    r = s.encode("utf-8"); return u32le(len(r)) + r
def enc_tag(tag, fs):
    tb = tag.encode("ascii")
    return u32le(len(tb)) + tb + u16le(len(fs)) + b"".join(_force(f) for f in fs)
def enc_arr(xs): return u32le(len(xs)) + b"".join(_force(x) for x in xs)
def enc_qn(ps):
    if not 1 <= len(ps) <= 256: raise ValueError("source qualified name must contain 1..256 components")
    return enc_arr([enc_str(p) for p in ps])
def enc_qid(ps):
    if not 2 <= len(ps) <= 256: raise ValueError(QID_ERR)
    return enc_arr([enc_str(p) for p in ps])
def null(t): return enc_tag(t, [])
def vis(v): return null(f"Visibility.{v}")
def t_uint(w):
    if w not in (8, 16, 32, 64, 128, 256): raise ValueError(W_ERR)
    return enc_tag("Type.UInt", [u16le(w)])
def lit_int(n): return enc_tag("Literal.Integer", [u256le(n)])
def e_lit(l): return enc_tag("Expr.Literal", [l])
def d_struct(n, fs):
    if not fs: raise ValueError(STRUCT_ERR)
    return enc_tag("StructDecl", [enc_str(n), enc_arr(fs)])
def d_state(v, n, t): return enc_tag("StateDecl", [vis(v), enc_str(n), t])
def d_const(n, t, v): return enc_tag("ConstDecl", [enc_str(n), t, v])
def enc_program(n, items):
    if not items: raise ValueError(ITEMS_ERR)
    return enc_tag("Program", [enc_str(n), enc_arr(items)])
def validate_join(mod, ident):
    if not 2 <= len(ident) <= 256: raise ValueError(QID_ERR)
    if len(ident) <= len(mod): raise ValueError(LONGER_ERR)
    if ident[:len(mod)] != mod: raise ValueError(PREFIX_ERR)
def enc_root(mod, ident, prog_name, prog_items):
    validate_join(mod, ident)
    if prog_name != ident[-1]: raise ValueError(NAME_ERR)
    return enc_qn(mod) + enc_qid(ident) + enc_program(prog_name, prog_items)
STATE = d_state("Public", "enabled", null("Type.Bool"))
CONST = d_const("max", t_uint(256), e_lit(lit_int(4096)))
G = {
"root_state_ok": (LIT_STATE_OK, lambda: enc_root(["Root"], ["Root", "Demo"], "Demo", [STATE])),
"root_two_order": (LIT_TWO_ORDER, lambda: enc_root(["Root"], ["Root", "Demo"], "Demo", [STATE, CONST])),
"root_deep_mod": (LIT_DEEP_MOD, lambda: enc_root(["A", "B"], ["A", "B", "Main"], "Main", [STATE])),
}
def _fail(name, want, fn):
    try: fn(); raise SystemExit(f"{name}: unexpectedly ok")
    except ValueError as e:
        if str(e) != want: raise SystemExit(f"{name}: got {e}")
def self_check():
    for k, (want, fn) in G.items():
        got = fn().hex()
        if got != want: raise SystemExit(f"{k}: got {got}")
    _fail("qid1", QID_ERR, lambda: enc_root(["Root"], ["Root"], "Demo", [STATE]))
    _fail("equal_two_comp", LONGER_ERR, lambda: enc_root(["A", "B"], ["A", "B"], "Demo", [STATE]))
    _fail("nonprefix", PREFIX_ERR, lambda: enc_root(["A", "B"], ["A", "C", "D"], "D", [STATE]))
    _fail("bad_join_first", PREFIX_ERR, lambda: enc_root(["A", "B"], ["A", "C", "D"], "Wrong", []))
    _fail("wrong_name_first", NAME_ERR, lambda: enc_root(["Root"], ["Root", "Demo"], "Other", []))
    _fail("empty_items", ITEMS_ERR, lambda: enc_root(["Root"], ["Root", "Demo"], "Demo", []))
    _fail("struct_child", STRUCT_ERR,
          lambda: enc_root(["Root"], ["Root", "Demo"], "Demo", [lambda: d_struct("Store", [])]))
    _fail("const_w24_first", W_ERR,
          lambda: enc_root(["Root"], ["Root", "Demo"], "Demo",
                           [lambda: d_const("max", lambda: t_uint(24), lambda: lit_int(1 << 256))]))
    print("reference_source_ast_canonical_root_v1: ok 3")
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_canonical_root_v1.py --self-check")

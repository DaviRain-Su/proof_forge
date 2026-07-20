#!/usr/bin/env python3
"""Independent PA103 Program (name+items) wire oracle (no Lean/ProofForge, stdlib only).
Expected hex are checked-in literals independently verified against /tmp/pa103_lean_probe.md;
they are never computed by this oracle at runtime."""
import sys, unicodedata
U256_ERR = "u256 magnitude exceeds 2^256-1"
W_ERR = "integer width must be one of 8,16,32,64,128,256"
ITEMS_ERR = "program items must be nonempty"
STRUCT_ERR = "struct fields must be nonempty"
LIT_STATE_ONLY = ("0700000050726f6772616d02000400000044656d6f010000000900000053746174654465"
"636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c"
"656409000000547970652e426f6f6c0000")
LIT_TWO_ORDER = ("0700000050726f6772616d02000400000044656d6f020000000900000053746174654465"
"636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c"
"656409000000547970652e426f6f6c000009000000436f6e73744465636c030003000000"
"6d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c"
"01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000"
"00000000000000000000000000000000000000")
LIT_TWO_REV = ("0700000050726f6772616d02000400000044656d6f0200000009000000436f6e73744465"
"636c0300030000006d617809000000547970652e55496e74010000010c00000045787072"
"2e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000"
"000000000000000000000000000000000000000000000000000000090000005374617465"
"4465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61"
"626c656409000000547970652e426f6f6c0000")
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
def null(t): return enc_tag(t, [])
def vis(v): return null(f"Visibility.{v}")
def t_uint(w):
    if w not in (8, 16, 32, 64, 128, 256): raise ValueError(W_ERR)
    return enc_tag("Type.UInt", [u16le(w)])
def lit_int(n): return enc_tag("Literal.Integer", [u256le(n)])
def e_lit(l): return enc_tag("Expr.Literal", [l])
def enc_field(n, t): return enc_tag("FieldDecl", [enc_str(n), t])
def d_struct(n, fs):
    if not fs: raise ValueError(STRUCT_ERR)
    return enc_tag("StructDecl", [enc_str(n), enc_arr(fs)])
def d_state(v, n, t): return enc_tag("StateDecl", [vis(v), enc_str(n), t])
def d_const(n, t, v): return enc_tag("ConstDecl", [enc_str(n), t, v])
def d_item(fn): return fn()
def enc_program(n, items):
    if not items: raise ValueError(ITEMS_ERR)
    return enc_tag("Program", [enc_str(n), enc_arr(items)])
STATE = d_state("Public", "enabled", null("Type.Bool"))
CONST = d_const("max", t_uint(256), e_lit(lit_int(4096)))
def item_state(): return d_item(lambda: STATE)
def item_const(): return d_item(lambda: CONST)
G = {
"prog_state_only": (LIT_STATE_ONLY, lambda: enc_program("Demo", [item_state])),
"prog_two_order": (LIT_TWO_ORDER, lambda: enc_program("Demo", [item_state, item_const])),
"prog_two_reversed": (LIT_TWO_REV, lambda: enc_program("Demo", [item_const, item_state])),
}
def _fail(name, want, fn):
    try: fn(); raise SystemExit(f"{name}: unexpectedly ok")
    except ValueError as e:
        if str(e) != want: raise SystemExit(f"{name}: got {e}")
def self_check():
    for k, (want, fn) in G.items():
        got = fn().hex()
        if got != want: raise SystemExit(f"{k}: got {got}")
        if not got.startswith("0700000050726f6772616d"):
            raise SystemExit(f"{k}: missing Program prefix")
    if G["prog_two_order"][0] == G["prog_two_reversed"][0]: raise SystemExit("order alias")
    _fail("empty_items", ITEMS_ERR, lambda: enc_program("Demo", []))
    _fail("struct_empty", STRUCT_ERR, lambda: enc_program("Demo", [lambda: d_struct("Store", [])]))
    _fail("const_w24_first", W_ERR,
          lambda: enc_program("Demo", [lambda: d_const("max", lambda: t_uint(24), lambda: lit_int(1 << 256))]))
    _fail("state_then_struct", STRUCT_ERR,
          lambda: enc_program("Demo", [item_state, lambda: d_struct("Store", [])]))
    print("reference_source_ast_program_v1: ok 3")
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_program_v1.py --self-check")

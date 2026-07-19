#!/usr/bin/env python3
"""Independent PA101 spine-dependent declaration-record wire oracle (no Lean/ProofForge)."""
import sys, unicodedata
W_ERR = "integer width must be one of 8,16,32,64,128,256"
U256_ERR = "u256 magnitude exceeds 2^256-1"
FIELD_ERR = "field id must be bn254_fr"
BLK_ERR = "block statements must be nonempty"
def u16le(v): return bytes((v & 255, (v >> 8) & 255))
def u32le(v): return bytes((v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255))
def u256le(n):
    if not 0 <= n < (1 << 256): raise ValueError(U256_ERR)
    return n.to_bytes(32, "little")
def _force(x): return x() if callable(x) else x
def enc_bool(b): return b"\x01" if b else b"\x00"
def enc_str(s):
    if unicodedata.normalize("NFC", s) != s: raise ValueError("non-NFC")
    r = s.encode("utf-8"); return u32le(len(r)) + r
def enc_ident(s):
    if unicodedata.normalize("NFC", s) != s: raise ValueError("non-NFC")
    r = s.encode("utf-8")
    if not 1 <= len(r) <= 240: raise ValueError("raw length")
    if "»" in s: raise ValueError("closing guillemet")
    if any(ord(c) <= 0x1F or 0x7F <= ord(c) <= 0x9F for c in s): raise ValueError("Cc")
    return enc_str(s)
def enc_tag(tag, fs):
    tb = tag.encode("ascii")
    return u32le(len(tb)) + tb + u16le(len(fs)) + b"".join(_force(f) for f in fs)
def enc_arr(xs): return u32le(len(xs)) + b"".join(_force(x) for x in xs)
def null(t): return enc_tag(t, [])
def enc_opt(x): return b"\x00" if x is None else b"\x01" + _force(x)
def vis(v): return null(f"Visibility.{v}")
def t_uint(w):
    if w not in (8, 16, 32, 64, 128, 256): raise ValueError(W_ERR)
    return enc_tag("Type.UInt", [u16le(w)])
def t_bytes(n):
    if not 0 <= n <= 4096: raise ValueError("bytes length must be 0..4096")
    return enc_tag("Type.Bytes", [u32le(n)])
def t_field(i):
    if i != "bn254_fr": raise ValueError(FIELD_ERR)
    return enc_tag("Type.Field", [enc_ident(i)])
def lit_bool(b): return enc_tag("Literal.Bool", [enc_bool(b)])
def lit_int(n): return enc_tag("Literal.Integer", [u256le(n)])
def p_name(n): return enc_tag("Place.Name", [enc_ident(n)])
def e_lit(l): return enc_tag("Expr.Literal", [l])
def e_place(p): return enc_tag("Expr.Place", [p])
def e_binary(op, l, r): return enc_tag("Expr.Binary", [null(f"BinaryOp.{op}"), l, r])
def s_assign(t, v): return enc_tag("Stmt.Assign", [t, v])
def s_return(v): return enc_tag("Stmt.Return", [enc_opt(v)])
def s_if(c, t, e): return enc_tag("Stmt.If", [c, t, enc_opt(e)])
def enc_block(stmts):
    if not stmts: raise ValueError(BLK_ERR)
    return enc_tag("Block", [enc_arr(stmts)])
def enc_param(v, n, t): return enc_tag("Param", [vis(v), enc_ident(n), t])
def enc_const(n, t, v): return enc_tag("ConstDecl", [enc_ident(n), t, v])
def enc_invariant(n, p): return enc_tag("InvariantDecl", [enc_ident(n), p])
def enc_init(ps, b): return enc_tag("InitDecl", [enc_arr(ps), b])
def enc_entrylike(tag, n, ps, r, b): return enc_tag(tag, [enc_ident(n), enc_arr(ps), r, b])
# literal pieces
TU64, TU256 = t_uint(64).hex(), t_uint(256).hex()
TB, TP, TUNIT = null("Type.Bool").hex(), null("Type.Principal").hex(), null("Type.Unit").hex()
TB0, TFR = t_bytes(0).hex(), t_field("bn254_fr").hex()
VP, VQ, VC = (vis("Public").hex(), vis("Private").hex(), vis("Commitment").hex())
def N(s): return (u32le(len(s.encode())) + s.encode()).hex()
def E_INT(n): return e_lit(lit_int(n)).hex()
E_L1, E_TRUE = E_INT(1), e_lit(lit_bool(True)).hex()
PL_C = p_name("count").hex()
E_PL_C = e_place(p_name("count")).hex()
P_START = enc_param("Public", "start", t_uint(64)).hex()
P_SECRET = enc_param("Private", "secret", t_field("bn254_fr")).hex()
P_TO = enc_param("Public", "to", null("Type.Principal")).hex()
P_AMOUNT = enc_param("Private", "amount", t_uint(64)).hex()
P_NOTE = enc_param("Commitment", "note", t_bytes(0)).hex()
P_X = enc_param("Public", "x", t_uint(64)).hex()
BLK_ASSIGN = enc_block([s_assign(p_name("count"), bytes.fromhex(E_L1))]).hex()
BLK_RET_PLC = enc_block([s_return(e_place(p_name("count")))]).hex()
BLK_RET_0 = enc_block([s_return(e_lit(lit_int(0)))]).hex()
BLK_IF = enc_block([s_if(bytes.fromhex(E_TRUE), enc_block([s_return(None)]), None)]).hex()
G = {
"const_max": ("09000000436f6e73744465636c0300" + N("max") + TU256 + E_INT(4096),
    lambda: enc_const("max", t_uint(256), e_lit(lit_int(4096)))),
"invariant_bounded": ("0d000000496e76617269616e744465636c0200" + N("bounded")
    + "0b000000457870722e42696e61727903000b00000042696e6172794f702e4c740000" + E_PL_C + E_INT(4096),
    lambda: enc_invariant("bounded", e_binary("Lt", e_place(p_name("count")), e_lit(lit_int(4096))))),
"init_two_params": ("08000000496e69744465636c020002000000" + P_START + P_SECRET + BLK_ASSIGN,
    lambda: enc_init([bytes.fromhex(P_START), bytes.fromhex(P_SECRET)], bytes.fromhex(BLK_ASSIGN))),
"entry_run": ("09000000456e7472794465636c0400" + N("run") + "03000000" + P_TO + P_AMOUNT + P_NOTE
    + TU64 + BLK_RET_PLC,
    lambda: enc_entrylike("EntryDecl", "run", [bytes.fromhex(P_TO), bytes.fromhex(P_AMOUNT),
        bytes.fromhex(P_NOTE)], t_uint(64), bytes.fromhex(BLK_RET_PLC))),
"entry_swapped": ("09000000456e7472794465636c0400" + N("run") + "03000000" + P_AMOUNT + P_TO + P_NOTE
    + TU64 + BLK_RET_PLC,
    lambda: enc_entrylike("EntryDecl", "run", [bytes.fromhex(P_AMOUNT), bytes.fromhex(P_TO),
        bytes.fromhex(P_NOTE)], t_uint(64), bytes.fromhex(BLK_RET_PLC))),
"view_get_empty": ("08000000566965774465636c0400" + N("get") + "00000000" + TU64 + BLK_RET_0,
    lambda: enc_entrylike("ViewDecl", "get", [], t_uint(64), bytes.fromhex(BLK_RET_0))),
"fn_helper2": ("06000000466e4465636c0400" + N("helper2") + "01000000" + P_X + TUNIT + BLK_IF,
    lambda: enc_entrylike("FnDecl", "helper2", [bytes.fromhex(P_X)], null("Type.Unit"),
        bytes.fromhex(BLK_IF))),
}
def _fail(name, want, fn):
    try: fn(); raise SystemExit(f"{name}: unexpectedly ok")
    except ValueError as e:
        if want is not None and str(e) != want: raise SystemExit(f"{name}: {e}")
def self_check():
    for k, (want, fn) in G.items():
        got = fn().hex()
        if got != want: raise SystemExit(f"{k}: got {got}")
    if G["entry_run"][0] == G["entry_swapped"][0]: raise SystemExit("entry order alias")
    view_run = enc_entrylike("ViewDecl", "run", [bytes.fromhex(P_TO), bytes.fromhex(P_AMOUNT),
        bytes.fromhex(P_NOTE)], t_uint(64), bytes.fromhex(BLK_RET_PLC)).hex()
    if G["entry_run"][0] == view_run: raise SystemExit("entry/view tag alias")
    _fail("const_w24_hostile", W_ERR, lambda: enc_const("max", lambda: t_uint(24),
        lambda: lit_int(1 << 256)))
    _fail("const_hostile_value", U256_ERR, lambda: enc_const("max", t_uint(256),
        lambda: lit_int(1 << 256)))
    _fail("invariant_hostile", U256_ERR, lambda: enc_invariant("bounded",
        lambda: e_binary("Lt", e_place(p_name("count")), lit_int(1 << 256))))
    _fail("init_empty_body", BLK_ERR, lambda: enc_init([bytes.fromhex(P_START)],
        lambda: enc_block([])))
    _fail("entry_first_param_field", FIELD_ERR, lambda: enc_entrylike("EntryDecl", "run",
        [lambda: enc_param("Public", "to", lambda: t_field("bad_fr"))], lambda: t_uint(24),
        lambda: enc_block([])))
    _fail("view_w24_result", W_ERR, lambda: enc_entrylike("ViewDecl", "get", [],
        lambda: t_uint(24), lambda: enc_block([])))
    _fail("fn_empty_body", BLK_ERR, lambda: enc_entrylike("FnDecl", "helper2",
        [bytes.fromhex(P_X)], null("Type.Unit"), lambda: enc_block([])))
    _fail("raw_close", "closing guillemet", lambda: enc_ident("»"))
    _fail("raw_cc", "Cc", lambda: enc_ident("a\x00"))
    print("reference_source_ast_spine_decl_v1: ok 7")
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_spine_decl_v1.py --self-check")

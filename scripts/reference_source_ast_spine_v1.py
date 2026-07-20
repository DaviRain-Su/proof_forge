#!/usr/bin/env python3
"""Independent PA100 mutual-spine wire oracle (no Lean/ProofForge)."""
import sys, unicodedata
QID_ERR = "source qualified id must contain 2..256 components"
U256_ERR = "u256 magnitude exceeds 2^256-1"
BLK_ERR = "block statements must be nonempty"
SMA_ERR = "stmt match arms must be nonempty"
EMA_ERR = "expr match arms must be nonempty"
FOR_ERR = "for bound must be 0..4096"
def u16le(v): return bytes((v & 255, (v >> 8) & 255))
def u32le(v): return bytes((v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255))
def u256le(n):
    if not 0 <= n < (1 << 256): raise ValueError(U256_ERR)
    return n.to_bytes(32, "little")
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
def _force(x): return x() if callable(x) else x
def enc_arr(xs): return u32le(len(xs)) + b"".join(_force(x) for x in xs)
def enc_qid(ps):
    if not 2 <= len(ps) <= 256: raise ValueError(QID_ERR)
    return enc_arr([enc_ident(p) for p in ps])
def null(t): return enc_tag(t, [])
def enc_opt(x): return b"\x00" if x is None else b"\x01" + x
def lit_bool(b): return enc_tag("Literal.Bool", [enc_bool(b)])
def lit_int(n): return enc_tag("Literal.Integer", [u256le(n)])
def pat_w(): return null("Pattern.Wildcard")
def pat_b(n): return enc_tag("Pattern.Bind", [enc_ident(n)])
# spine encoders: local checks before children, then left-to-right field order
def p_name(n): return enc_tag("Place.Name", [enc_ident(n)])
def p_field(b, f): return enc_tag("Place.Field", [b, enc_ident(f)])
def p_index(b, i): return enc_tag("Place.Index", [b, i])
def e_lit(l): return enc_tag("Expr.Literal", [l])
def e_place(p): return enc_tag("Expr.Place", [p])
def e_ctor(q, args): return enc_tag("Expr.Constructor", [enc_qid(q), enc_arr(args)])
def e_unary(op, x): return enc_tag("Expr.Unary", [null(f"UnaryOp.{op}"), x])
def e_binary(op, l, r): return enc_tag("Expr.Binary", [null(f"BinaryOp.{op}"), l, r])
def e_local(c, args): return enc_tag("Expr.LocalCall", [enc_ident(c), enc_arr(args)])
def e_arm(p, v): return enc_tag("ExprMatchArm", [p, v])
def e_match(s, arms):
    if not arms: raise ValueError(EMA_ERR)
    return enc_tag("Expr.Match", [s, enc_arr(arms)])
def s_let(n, ta, v): return enc_tag("Stmt.Let", [enc_ident(n), enc_opt(ta), v])
def s_assign(t, v): return enc_tag("Stmt.Assign", [t, v])
def s_if(c, t, e): return enc_tag("Stmt.If", [c, t, enc_opt(e)])
def s_arm(p, b): return enc_tag("StmtMatchArm", [p, b])
def s_match(s, arms):
    if not arms: raise ValueError(SMA_ERR)
    return enc_tag("Stmt.Match", [s, enc_arr(arms)])
def s_for(b, st, en, bd, body):
    if bd > 4096: raise ValueError(FOR_ERR)
    return enc_tag("Stmt.For", [enc_ident(b), st, en, u32le(bd), body])
def s_assert(c, e): return enc_tag("Stmt.Assert", [c, enc_opt(e)])
def s_revert(e, args): return enc_tag("Stmt.Revert", [enc_ident(e), enc_arr(args)])
def s_emit(e, args): return enc_tag("Stmt.Emit", [enc_ident(e), enc_arr(args)])
def s_return(v): return enc_tag("Stmt.Return", [enc_opt(v)])
def x_call(q, args): return enc_tag("ExternalCallExpr", [enc_qid(q), enc_arr(args)])
def s_call(c): return enc_tag("Stmt.Call", [c])
def s_schedule(c): return enc_tag("Stmt.Schedule", [c])
def enc_block(stmts):
    if not stmts: raise ValueError(BLK_ERR)
    return enc_tag("Block", [enc_arr(stmts)])
# literal pieces
N = lambda s: u32le(len(s.encode())) + s.encode()
L0, L1, L2, LK, L64 = (lit_int(0).hex(), lit_int(1).hex(), lit_int(2).hex(),
                       lit_int(4096).hex(), lit_int(1 << 64).hex())
LT, TB, PW = lit_bool(True).hex(), null("Type.Bool").hex(), pat_w().hex()
PN_X = null("Place.Name").hex()[:8] + "506c6163652e4e616d65" + "0100" + N("x").hex()
QS, QN, QM = (enc_qid(["Option", "some"]).hex(), enc_qid(["Option", "none"]).hex(),
              enc_qid(["Math", "add"]).hex())
E_L1, E_L2, E_LK, E_LT, E_L64 = (e_lit(bytes.fromhex(L1)).hex(), e_lit(bytes.fromhex(L2)).hex(),
    e_lit(bytes.fromhex(LK)).hex(), e_lit(bytes.fromhex(LT)).hex(), e_lit(bytes.fromhex(L64)).hex())
PL_X = p_name("x").hex(); PL_S = p_name("s").hex(); PL_A = p_name("arr").hex()
RET0, RET1 = s_return(None).hex(), s_return(bytes.fromhex(E_L1)).hex()
BLK1 = enc_block([bytes.fromhex(RET0)]).hex()
BLK2 = enc_block([bytes.fromhex(RET0), s_emit("Ping", [])]).hex()
BLKR = enc_block([s_emit("Ping", []), bytes.fromhex(RET0)]).hex()
SA_W = s_arm(bytes.fromhex(PW), bytes.fromhex(BLK1)).hex()
EA_B1 = e_arm(pat_b("x"), bytes.fromhex(E_L1)).hex()
EA_W2 = e_arm(bytes.fromhex(PW), bytes.fromhex(E_L2)).hex()
X0, X1 = x_call(["Math", "add"], []).hex(), x_call(["Math", "add"], [bytes.fromhex(E_L1)]).hex()
G = {
"place_name": (PL_X, lambda: p_name("x")),
"place_field": ("0b000000506c6163652e4669656c640200" + PL_S + N("total").hex(),
    lambda: p_field(p_name("s"), "total")),
"place_index": ("0b000000506c6163652e496e6465780200" + PL_A + E_L1,
    lambda: p_index(p_name("arr"), bytes.fromhex(E_L1))),
"expr_literal": ("0c000000457870722e4c69746572616c0100" + L64, lambda: e_lit(bytes.fromhex(L64))),
"expr_place": ("0a000000457870722e506c6163650100" + PL_X, lambda: e_place(p_name("x"))),
"expr_ctor_some": ("10000000457870722e436f6e7374727563746f720200" + QS + "01000000" + E_LT,
    lambda: e_ctor(["Option", "some"], [bytes.fromhex(E_LT)])),
"expr_ctor_none": ("10000000457870722e436f6e7374727563746f720200" + QN + "00000000",
    lambda: e_ctor(["Option", "none"], [])),
"expr_ctor_order_a": ("10000000457870722e436f6e7374727563746f720200" + QS + "02000000" + E_L1 + E_L2,
    lambda: e_ctor(["Option", "some"], [bytes.fromhex(E_L1), bytes.fromhex(E_L2)])),
"expr_ctor_order_b": ("10000000457870722e436f6e7374727563746f720200" + QS + "02000000" + E_L2 + E_L1,
    lambda: e_ctor(["Option", "some"], [bytes.fromhex(E_L2), bytes.fromhex(E_L1)])),
"expr_unary": ("0a000000457870722e556e61727902000b000000556e6172794f702e4e65670000" + E_L1,
    lambda: e_unary("Neg", bytes.fromhex(E_L1))),
"expr_binary": ("0b000000457870722e42696e61727903000c00000042696e6172794f702e4164640000" + E_L1 + E_L2,
    lambda: e_binary("Add", bytes.fromhex(E_L1), bytes.fromhex(E_L2))),
"expr_local": ("0e000000457870722e4c6f63616c43616c6c0200" + N("helper").hex() + "01000000" + E_L1,
    lambda: e_local("helper", [bytes.fromhex(E_L1)])),
"expr_match": ("0a000000457870722e4d617463680200" + E_L1 + "02000000" + EA_B1 + EA_W2,
    lambda: e_match(bytes.fromhex(E_L1), [bytes.fromhex(EA_B1), bytes.fromhex(EA_W2)])),
"stmt_let_none": ("0800000053746d742e4c65740300" + N("x").hex() + "00" + E_L1,
    lambda: s_let("x", None, bytes.fromhex(E_L1))),
"stmt_let_some": ("0800000053746d742e4c65740300" + N("y").hex() + "01" + TB + E_LT,
    lambda: s_let("y", bytes.fromhex(TB), bytes.fromhex(E_LT))),
"stmt_assign": ("0b00000053746d742e41737369676e0200" + PL_X + E_L1,
    lambda: s_assign(p_name("x"), bytes.fromhex(E_L1))),
"stmt_if_none": ("0700000053746d742e49660300" + E_LT + BLK1 + "00",
    lambda: s_if(bytes.fromhex(E_LT), bytes.fromhex(BLK1), None)),
"stmt_if_some": ("0700000053746d742e49660300" + E_LT + BLK1 + "01" +
    enc_block([bytes.fromhex(RET1)]).hex(),
    lambda: s_if(bytes.fromhex(E_LT), bytes.fromhex(BLK1), enc_block([bytes.fromhex(RET1)]))),
"stmt_match": ("0a00000053746d742e4d617463680200" + E_L1 + "01000000" + SA_W,
    lambda: s_match(bytes.fromhex(E_L1), [bytes.fromhex(SA_W)])),
"stmt_for_0": ("0800000053746d742e466f720500" + N("i").hex() + e_lit(lit_int(0)).hex() + E_LK + "00000000" + BLK1,
    lambda: s_for("i", e_lit(lit_int(0)), bytes.fromhex(E_LK), 0, bytes.fromhex(BLK1))),
"stmt_for_4096": ("0800000053746d742e466f720500" + N("i").hex() + e_lit(lit_int(0)).hex() + E_LK + "00100000" + BLK1,
    lambda: s_for("i", e_lit(lit_int(0)), bytes.fromhex(E_LK), 4096, bytes.fromhex(BLK1))),
"stmt_assert_none": ("0b00000053746d742e4173736572740200" + E_LT + "00",
    lambda: s_assert(bytes.fromhex(E_LT), None)),
"stmt_assert_some": ("0b00000053746d742e4173736572740200" + E_LT + "01" + N("Denied").hex(),
    lambda: s_assert(bytes.fromhex(E_LT), N("Denied"))),
"stmt_revert_empty": ("0b00000053746d742e5265766572740200" + N("Denied").hex() + "00000000",
    lambda: s_revert("Denied", [])),
"stmt_revert_one": ("0b00000053746d742e5265766572740200" + N("Denied").hex() + "01000000" + E_L1,
    lambda: s_revert("Denied", [bytes.fromhex(E_L1)])),
"stmt_emit": ("0900000053746d742e456d69740200" + N("Ping").hex() + "00000000",
    lambda: s_emit("Ping", [])),
"stmt_return_none": (RET0, lambda: s_return(None)),
"stmt_return_some": (RET1, lambda: s_return(bytes.fromhex(E_L1))),
"stmt_call": ("0900000053746d742e43616c6c0100" + X0, lambda: s_call(bytes.fromhex(X0))),
"stmt_schedule": ("0d00000053746d742e5363686564756c650100" + X1, lambda: s_schedule(bytes.fromhex(X1))),
"block_single": (BLK1, lambda: enc_block([bytes.fromhex(RET0)])),
"block_multi": (BLK2, lambda: enc_block([bytes.fromhex(RET0), s_emit("Ping", [])])),
"block_reversed": (BLKR, lambda: enc_block([s_emit("Ping", []), bytes.fromhex(RET0)])),
"stmt_arm": (SA_W, lambda: s_arm(bytes.fromhex(PW), bytes.fromhex(BLK1))),
"expr_arm": (EA_B1, lambda: e_arm(pat_b("x"), bytes.fromhex(E_L1))),
"external": (X0, lambda: x_call(["Math", "add"], [])),
}
def _fail(name, want, fn):
    try: fn(); raise SystemExit(f"{name}: unexpectedly ok")
    except ValueError as e:
        if want is not None and str(e) != want: raise SystemExit(f"{name}: {e}")
def self_check():
    for k, (want, fn) in G.items():
        got = fn().hex()
        if got != want: raise SystemExit(f"{k}: got {got}")
    if G["expr_ctor_order_a"][0] == G["expr_ctor_order_b"][0]: raise SystemExit("ctor order alias")
    if G["block_multi"][0] == G["block_reversed"][0]: raise SystemExit("block order alias")
    _fail("empty_block", BLK_ERR, lambda: enc_block([]))
    _fail("empty_stmt_match", SMA_ERR, lambda: s_match(bytes.fromhex(E_L1), []))
    _fail("empty_expr_match", EMA_ERR, lambda: e_match(bytes.fromhex(E_L1), []))
    _fail("for_4097", FOR_ERR, lambda: s_for("i", e_lit(lit_int(0)), bytes.fromhex(E_LK), 4097, bytes.fromhex(BLK1)))
    _fail("ctor_qid1", QID_ERR, lambda: e_ctor(["Only"], []))
    _fail("external_qid1", QID_ERR, lambda: x_call(["Only"], []))
    _fail("qid_before_hostile_ctor", QID_ERR, lambda: e_ctor(["Only"], [lambda: lit_int(1 << 256)]))
    _fail("qid_before_hostile_ext", QID_ERR, lambda: x_call(["Only"], [lambda: lit_int(1 << 256)]))
    _fail("arms_before_hostile", SMA_ERR, lambda: s_match(lambda: lit_int(1 << 256), []))
    _fail("bound_before_hostile", FOR_ERR, lambda: s_for("i", lambda: lit_int(1 << 256), bytes.fromhex(E_LK), 4097, bytes.fromhex(BLK1)))
    _fail("child_propagate", U256_ERR, lambda: e_ctor(["Option", "some"], [lambda: lit_int(1 << 256)]))
    _fail("raw_close", "closing guillemet", lambda: p_name("»"))
    _fail("raw_cc", "Cc", lambda: p_name("a\x00"))
    print("reference_source_ast_spine_v1: ok", len(G))
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_spine_v1.py --self-check")

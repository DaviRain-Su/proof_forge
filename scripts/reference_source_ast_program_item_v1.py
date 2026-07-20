#!/usr/bin/env python3
"""Independent PA102 ProgramItemV1 no-wrapper dispatch oracle (no Lean/ProofForge, stdlib only)."""
import sys, unicodedata
QID_ERR = "source qualified id must contain 2..256 components"
W_ERR = "integer width must be one of 8,16,32,64,128,256"
U256_ERR = "u256 magnitude exceeds 2^256-1"
BLK_ERR = "block statements must be nonempty"
STRUCT_ERR = "struct fields must be nonempty"
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
def enc_qid(ps):
    if not 2 <= len(ps) <= 256: raise ValueError(QID_ERR)
    return enc_arr([enc_str(p) for p in ps])
def null(t): return enc_tag(t, [])
def vis(v): return null(f"Visibility.{v}")
def t_uint(w):
    if w not in (8, 16, 32, 64, 128, 256): raise ValueError(W_ERR)
    return enc_tag("Type.UInt", [u16le(w)])
def t_bytes(n): return enc_tag("Type.Bytes", [u32le(n)])
def t_field(i):
    if i != "bn254_fr": raise ValueError("field id must be bn254_fr")
    return enc_tag("Type.Field", [enc_str(i)])
def t_map(k, v): return enc_tag("Type.Map", [k, v])
def lit_bool(b): return enc_tag("Literal.Bool", [b"\x01" if b else b"\x00"])
def lit_int(n): return enc_tag("Literal.Integer", [u256le(n)])
def p_name(n): return enc_tag("Place.Name", [enc_str(n)])
def e_lit(l): return enc_tag("Expr.Literal", [l])
def e_place(p): return enc_tag("Expr.Place", [p])
def e_binary(op, l, r): return enc_tag("Expr.Binary", [null(f"BinaryOp.{op}"), l, r])
def s_assign(t, v): return enc_tag("Stmt.Assign", [t, v])
def s_return(v): return enc_tag("Stmt.Return", [b"\x00" if v is None else b"\x01" + _force(v)])
def s_if(c, t, e): return enc_tag("Stmt.If", [c, t, b"\x00" if e is None else b"\x01" + _force(e)])
def enc_block(stmts):
    if not stmts: raise ValueError(BLK_ERR)
    return enc_tag("Block", [enc_arr(stmts)])
def enc_param(v, n, t): return enc_tag("Param", [vis(v), enc_str(n), t])
def enc_field(n, t): return enc_tag("FieldDecl", [enc_str(n), t])
def enc_variant(n, tys): return enc_tag("EnumVariant", [enc_str(n), enc_arr(tys)])
def d_state(v, n, t): return enc_tag("StateDecl", [vis(v), enc_str(n), t])
def d_struct(n, fs):
    if not fs: raise ValueError(STRUCT_ERR)
    return enc_tag("StructDecl", [enc_str(n), enc_arr(fs)])
def d_enum(n, vs): return enc_tag("EnumDecl", [enc_str(n), enc_arr(vs)])
def d_event(n, ps): return enc_tag("EventDecl", [enc_str(n), enc_arr(ps)])
def d_error(n, ps): return enc_tag("ErrorDecl", [enc_str(n), enc_arr(ps)])
def d_ext(i, v, d):
    iB = enc_qid(i); semver(v); digest(d)
    return enc_tag("ExtensionReq", [iB, enc_str(v), enc_str(d)])
def semver(s):
    core, _, rest = s.partition("-")
    nums = core.split(".")
    if len(nums) != 3 or any(not n.isdigit() or (len(n) > 1 and n[0] == "0") for n in nums):
        raise ValueError("extension version must use canonical exact SemVer")
    if rest and not all(all(c.isalnum() or c == "-" for c in i) and i for i in rest.replace("+", ".").split(".")):
        raise ValueError("extension version must use canonical exact SemVer")
def digest(s):
    if not (s.startswith("sha256:") and len(s) == 71 and all(c in "0123456789abcdef" for c in s[7:])):
        raise ValueError("extension digest must use canonical sha256 spelling")
def d_const(n, t, v): return enc_tag("ConstDecl", [enc_str(n), t, v])
def d_invariant(n, p): return enc_tag("InvariantDecl", [enc_str(n), p])
def d_init(ps, b): return enc_tag("InitDecl", [enc_arr(ps), b])
def d_entrylike(tag, n, ps, r, b): return enc_tag(tag, [enc_str(n), enc_arr(ps), r, b])
def d_proof(inv, th): return enc_tag("ProofDecl", [enc_str(inv), enc_qid(th)])
def N(s): return (u32le(len(s.encode())) + s.encode()).hex()
TU64, TU256 = t_uint(64).hex(), t_uint(256).hex()
TB, TP, TUNIT = null("Type.Bool").hex(), null("Type.Principal").hex(), null("Type.Unit").hex()
TB0, TFR = t_bytes(0).hex(), t_field("bn254_fr").hex()
TMAP = t_map(null("Type.Bool"), null("Type.Unit")).hex()
VP, VQ, VC = vis("Public").hex(), vis("Private").hex(), vis("Commitment").hex()
def E_INT(n): return e_lit(lit_int(n)).hex()
def E_LITB(b): return e_lit(lit_bool(b)).hex()
P_PLC = e_place(p_name("count")).hex()
FD_COUNT = enc_field("count", t_uint(256)).hex()
FD_ITEMS = enc_field("items", t_map(null("Type.Bool"), null("Type.Unit"))).hex()
V_NONE = enc_variant("None", []).hex()
V_SOME = enc_variant("Some", [null("Type.Bool"), null("Type.Principal")]).hex()
P_START = enc_param("Public", "start", t_uint(64)).hex()
P_SECRET = enc_param("Private", "secret", t_field("bn254_fr")).hex()
P_TO = enc_param("Public", "to", null("Type.Principal")).hex()
P_AMOUNT = enc_param("Private", "amount", t_uint(64)).hex()
P_NOTE = enc_param("Commitment", "note", t_bytes(0)).hex()
P_X = enc_param("Public", "x", t_uint(64)).hex()
BLK_ASSIGN = enc_block([s_assign(p_name("count"), bytes.fromhex(E_INT(1)))]).hex()
BLK_RET_PLC = enc_block([s_return(e_place(p_name("count")))]).hex()
BLK_RET_0 = enc_block([s_return(e_lit(lit_int(0)))]).hex()
BLK_IF = enc_block([s_if(bytes.fromhex(E_LITB(True)), enc_block([s_return(None)]), None)]).hex()
DIG0 = "sha256:" + "0" * 64
G = {
"item_state": ("0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000",
    lambda: d_state("Public", "enabled", null("Type.Bool"))),
"item_struct": ("0a0000005374727563744465636c02000500000053746f726501000000" + FD_COUNT,
    lambda: d_struct("Store", [bytes.fromhex(FD_COUNT)])),
"item_enum": ("08000000456e756d4465636c02000600000043686f69636502000000" + V_NONE + V_SOME,
    lambda: d_enum("Choice", [bytes.fromhex(V_NONE), bytes.fromhex(V_SOME)])),
"item_const": ("09000000436f6e73744465636c0300" + N("max") + TU256 + E_INT(4096),
    lambda: d_const("max", t_uint(256), e_lit(lit_int(4096)))),
"item_event": ("090000004576656e744465636c02000400000050696e6700000000",
    lambda: d_event("Ping", [])),
"item_error": ("090000004572726f724465636c020005000000456d70747900000000",
    lambda: d_error("Empty", [])),
"item_init": ("08000000496e69744465636c020002000000" + P_START + P_SECRET + BLK_ASSIGN,
    lambda: d_init([bytes.fromhex(P_START), bytes.fromhex(P_SECRET)], bytes.fromhex(BLK_ASSIGN))),
"item_entry": ("09000000456e7472794465636c0400" + N("run") + "03000000" + P_TO + P_AMOUNT + P_NOTE + TU64 + BLK_RET_PLC,
    lambda: d_entrylike("EntryDecl", "run", [bytes.fromhex(P_TO), bytes.fromhex(P_AMOUNT), bytes.fromhex(P_NOTE)], t_uint(64), bytes.fromhex(BLK_RET_PLC))),
"item_view": ("08000000566965774465636c0400" + N("get") + "00000000" + TU64 + BLK_RET_0,
    lambda: d_entrylike("ViewDecl", "get", [], t_uint(64), bytes.fromhex(BLK_RET_0))),
"item_fn": ("06000000466e4465636c0400" + N("helper2") + "01000000" + P_X + TUNIT + BLK_IF,
    lambda: d_entrylike("FnDecl", "helper2", [bytes.fromhex(P_X)], null("Type.Unit"), bytes.fromhex(BLK_IF))),
"item_invariant": ("0d000000496e76617269616e744465636c0200" + N("bounded")
    + "0b000000457870722e42696e61727903000b00000042696e6172794f702e4c740000" + P_PLC + E_INT(4096),
    lambda: d_invariant("bounded", e_binary("Lt", e_place(p_name("count")), e_lit(lit_int(4096))))),
"item_extension_req": ("0c000000457874656e73696f6e5265710300020000000400000044656d6f070000004665617475726505000000312e302e30470000007368613235363a" + "30" * 64,
    lambda: d_ext(["Demo", "Feature"], "1.0.0", DIG0)),
"item_proof": ("0900000050726f6f664465636c02000400000073616665020000000600000050726f6f66730400000073616665",
    lambda: d_proof("safe", ["Proofs", "safe"])),
}
def _fail(name, want, fn):
    try: fn(); raise SystemExit(f"{name}: unexpectedly ok")
    except ValueError as e:
        if want is not None and str(e) != want: raise SystemExit(f"{name}: {e}")
def self_check():
    def dispatch(route_fn):
        """Pure no-wrapper dispatch: emits the routed record encoding byte-for-byte, adds no tag."""
        return route_fn()
    for k, (want, fn) in G.items():
        if dispatch(fn).hex() != want: raise SystemExit(f"{k}: dispatch/hex mismatch")
        if dispatch(fn) != fn(): raise SystemExit(f"{k}: dispatch not byte-identical to record")
    ev = d_event("Ping", []).hex(); er = d_error("Ping", []).hex()
    if ev == er: raise SystemExit("event/error alias")
    shared = [bytes.fromhex(P_TO), bytes.fromhex(P_AMOUNT), bytes.fromhex(P_NOTE)]
    trio = [d_entrylike(t, "run", shared, t_uint(64), bytes.fromhex(BLK_RET_PLC)).hex()
            for t in ("EntryDecl", "ViewDecl", "FnDecl")]
    if len(set(trio)) != 3: raise SystemExit("entry/view/fn alias")
    _fail("struct_empty", STRUCT_ERR, lambda: d_struct("Store", []))
    _fail("const_w24_hostile", W_ERR, lambda: d_const("max", lambda: t_uint(24), lambda: lit_int(1 << 256)))
    _fail("init_empty_body", BLK_ERR, lambda: d_init([bytes.fromhex(P_START)], enc_block([])))
    _fail("ext_qid_first", QID_ERR, lambda: d_ext(["Only"], "not-a-semver", "bad"))
    print("reference_source_ast_program_item_v1: ok 13")
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_program_item_v1.py --self-check")

#!/usr/bin/env python3
"""Independent PA97 Pattern wire oracle (no Lean/ProofForge)."""
import sys, unicodedata
U256 = 1 << 256
QID_ERR = "source qualified id must contain 2..256 components"
def u16le(v): return bytes((v & 255, (v >> 8) & 255))
def u32le(v): return bytes((v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255))
def u256le(n):
    if not 0 <= n < U256: raise ValueError("u256 magnitude exceeds 2^256-1")
    return n.to_bytes(32, "little")
def enc_bool(b): return b"\x01" if b else b"\x00"
def enc_str(s):
    if unicodedata.normalize("NFC", s) != s: raise ValueError("non-NFC")
    r = s.encode("utf-8"); return u32le(len(r)) + r
def enc_ident(s):
    if unicodedata.normalize("NFC", s) != s: raise ValueError("non-NFC")
    r = s.encode("utf-8")
    if not 1 <= len(r) <= 240: raise ValueError("raw length")
    if "\u00bb" in s: raise ValueError("closing guillemet")
    if any(ord(c) <= 0x1F or 0x7F <= ord(c) <= 0x9F for c in s): raise ValueError("Cc")
    return enc_str(s)
def enc_tag(tag, fs):
    if not tag or any(ord(c) > 127 for c in tag): raise ValueError("tag")
    tb = tag.encode("ascii")
    return u32le(len(tb)) + tb + u16le(len(fs)) + b"".join(fs)
def enc_arr(xs): return u32le(len(xs)) + b"".join(xs)
def enc_qid(ps):
    if not 2 <= len(ps) <= 256: raise ValueError(QID_ERR)
    return enc_arr([enc_ident(p) for p in ps])
def lit_bool(b): return enc_tag("Literal.Bool", [enc_bool(b)])
def lit_int(n): return enc_tag("Literal.Integer", [u256le(n)])
def lit_str(s): return enc_tag("Literal.String", [enc_str(s)])
def pat_w(): return enc_tag("Pattern.Wildcard", [])
def pat_b(n): return enc_tag("Pattern.Bind", [enc_ident(n)])
def pat_l(lit): return enc_tag("Pattern.Literal", [lit])
def pat_c(qid, args):
    return enc_tag("Pattern.Constructor", [enc_qid(qid), enc_arr(args)])
# checked-in goldens; never production-generated
G = {
"pat_wildcard": ("100000005061747465726e2e57696c64636172640000", pat_w),
"pat_bind_x": ("0c0000005061747465726e2e42696e6401000100000078", lambda: pat_b("x")),
"pat_bind_foobar": ("0c0000005061747465726e2e42696e64010007000000666f6f2d626172", lambda: pat_b("foo-bar")),
"pat_lit_bool_f": ("0f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010000",
    lambda: pat_l(lit_bool(False))),
"pat_lit_bool_t": ("0f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001",
    lambda: pat_l(lit_bool(True))),
"pat_lit_int_2_64": ("0f0000005061747465726e2e4c69746572616c01000f0000004c69746572616c2e496e74656765720100"
    + "00"*8 + "01" + "00"*23, lambda: pat_l(lit_int(1 << 64))),
"pat_lit_str_cafe": ("0f0000005061747465726e2e4c69746572616c01000e0000004c69746572616c2e537472696e67010005000000636166c3a9",
    lambda: pat_l(lit_str("café"))),
"pat_ctor_empty": ("130000005061747465726e2e436f6e7374727563746f72020002000000060000004f7074696f6e040000006e6f6e6500000000",
    lambda: pat_c(["Option", "none"], [])),
"pat_ctor_wild": ("130000005061747465726e2e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d6501000000100000005061747465726e2e57696c64636172640000",
    lambda: pat_c(["Option", "some"], [pat_w()])),
"pat_ctor_ordered": ("130000005061747465726e2e436f6e7374727563746f720200020000000400000044656d6f0400000050616972020000000c0000005061747465726e2e42696e64010001000000780f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001",
    lambda: pat_c(["Demo", "Pair"], [pat_b("x"), pat_l(lit_bool(True))])),
"pat_ctor_reversed": ("130000005061747465726e2e436f6e7374727563746f720200020000000400000044656d6f0400000050616972020000000f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c0100010c0000005061747465726e2e42696e6401000100000078",
    lambda: pat_c(["Demo", "Pair"], [pat_l(lit_bool(True)), pat_b("x")])),
"pat_ctor_nested": ("130000005061747465726e2e436f6e7374727563746f720200020000000100000041010000004202000000130000005061747465726e2e436f6e7374727563746f720200020000000100000043010000004401000000100000005061747465726e2e57696c646361726400000c0000005061747465726e2e42696e6401000100000079",
    lambda: pat_c(["A", "B"], [pat_c(["C", "D"], [pat_w()]), pat_b("y")])),
}
def _fail(name, fn):
    try: fn(); raise SystemExit(f"{name}: unexpectedly ok")
    except ValueError: pass
def self_check():
    for k, (want, fn) in G.items():
        got = fn().hex()
        if got != want: raise SystemExit(f"{k}: got {got}")
    if G["pat_ctor_ordered"][0] == G["pat_ctor_reversed"][0]:
        raise SystemExit("ordered==reversed")
    _fail("qid1", lambda: pat_c(["Only"], []))
    _fail("u256", lambda: pat_l(lit_int(U256)))
    _fail("nfd", lambda: pat_l(lit_str("e\u0301")))
    # invalid QID wins over invalid nested literal (qid checked first)
    _fail("qid_before_lit", lambda: pat_c(["Only"], [pat_l(lit_int(U256))]))
    _fail("raw_close", lambda: pat_b("»"))
    _fail("raw_cc", lambda: pat_b("a\x00"))
    print("reference_source_ast_pattern_v1: ok", len(G))
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_pattern_v1.py --self-check")

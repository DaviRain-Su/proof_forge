#!/usr/bin/env python3
"""Independent SPEC-SOURCE-WIRE-001 leaf AST encode oracle (no Lean/ProofForge)."""
import sys, unicodedata
U16, U256 = 0xFFFF, 1 << 256
WIDTHS = (8, 16, 32, 64, 128, 256)
def u16le(v):
    if not 0 <= v <= U16: raise ValueError("u16")
    return bytes((v & 255, (v >> 8) & 255))
def u32le(v):
    if not 0 <= v <= 0xFFFFFFFF: raise ValueError("u32")
    return bytes((v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255))
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
def null(tag): return enc_tag(tag, [])
def width_ok(w):
    if w not in WIDTHS: raise ValueError("integer width must be one of 8,16,32,64,128,256")
def len_ok(kind, n):
    if not 0 <= n <= 4096: raise ValueError(f"{kind} length must be 0..4096")
def enc_uint(w): width_ok(w); return enc_tag("Type.UInt", [u16le(w)])
def enc_int(w): width_ok(w); return enc_tag("Type.Int", [u16le(w)])
def enc_named(n): return enc_tag("Type.Named", [enc_ident(n)])
def enc_bytes(n): len_ok("bytes", n); return enc_tag("Type.Bytes", [u32le(n)])
def enc_array(el, n): len_ok("array", n); return enc_tag("Type.Array", [el, u32le(n)])
def enc_option(el): return enc_tag("Type.Option", [el])
def enc_map(k, v): return enc_tag("Type.Map", [k, v])
def enc_field(i):
    if i != "bn254_fr": raise ValueError("field id must be bn254_fr")
    return enc_tag("Type.Field", [enc_ident(i)])
def enc_lit_bool(b): return enc_tag("Literal.Bool", [enc_bool(b)])
def enc_lit_int(n): return enc_tag("Literal.Integer", [u256le(n)])
def enc_lit_str(s): return enc_tag("Literal.String", [enc_str(s)])
# checked-in goldens (table-verbatim); encoder must match, never import production
G = {
"vis_public": ("110000005669736962696c6974792e5075626c69630000", lambda: null("Visibility.Public")),
"vis_private": ("120000005669736962696c6974792e507269766174650000", lambda: null("Visibility.Private")),
"vis_commitment": ("150000005669736962696c6974792e436f6d6d69746d656e740000", lambda: null("Visibility.Commitment")),
"type_bool": ("09000000547970652e426f6f6c0000", lambda: null("Type.Bool")),
"type_principal": ("0e000000547970652e5072696e636970616c0000", lambda: null("Type.Principal")),
"type_unit": ("09000000547970652e556e69740000", lambda: null("Type.Unit")),
"type_uint_8": ("09000000547970652e55496e7401000800", lambda: enc_uint(8)),
"type_uint_16": ("09000000547970652e55496e7401001000", lambda: enc_uint(16)),
"type_uint_32": ("09000000547970652e55496e7401002000", lambda: enc_uint(32)),
"type_uint_64": ("09000000547970652e55496e7401004000", lambda: enc_uint(64)),
"type_uint_128": ("09000000547970652e55496e7401008000", lambda: enc_uint(128)),
"type_uint_256": ("09000000547970652e55496e7401000001", lambda: enc_uint(256)),
"type_int_8": ("08000000547970652e496e7401000800", lambda: enc_int(8)),
"type_int_16": ("08000000547970652e496e7401001000", lambda: enc_int(16)),
"type_int_32": ("08000000547970652e496e7401002000", lambda: enc_int(32)),
"type_int_64": ("08000000547970652e496e7401004000", lambda: enc_int(64)),
"type_int_128": ("08000000547970652e496e7401008000", lambda: enc_int(128)),
"type_int_256": ("08000000547970652e496e7401000001", lambda: enc_int(256)),
"type_named_foobar": ("0a000000547970652e4e616d6564010007000000666f6f2d626172", lambda: enc_named("foo-bar")),
"type_map_bool_unit": ("08000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000",
    lambda: enc_map(null("Type.Bool"), null("Type.Unit"))),
"type_bytes_0": ("0a000000547970652e4279746573010000000000", lambda: enc_bytes(0)),
"type_bytes_4096": ("0a000000547970652e4279746573010000100000", lambda: enc_bytes(4096)),
"type_array_bool_0": ("0a000000547970652e4172726179020009000000547970652e426f6f6c000000000000",
    lambda: enc_array(null("Type.Bool"), 0)),
"type_array_bool_4096": ("0a000000547970652e4172726179020009000000547970652e426f6f6c000000100000",
    lambda: enc_array(null("Type.Bool"), 4096)),
"type_array_opt_bytes": ("0a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000",
    lambda: enc_array(enc_option(enc_bytes(0)), 0)),
"type_option_bytes0": ("0b000000547970652e4f7074696f6e01000a000000547970652e4279746573010000000000",
    lambda: enc_option(enc_bytes(0))),
"type_field_bn254": ("0a000000547970652e4669656c64010008000000626e3235345f6672", lambda: enc_field("bn254_fr")),
"lit_bool_f": ("0c0000004c69746572616c2e426f6f6c010000", lambda: enc_lit_bool(False)),
"lit_bool_t": ("0c0000004c69746572616c2e426f6f6c010001", lambda: enc_lit_bool(True)),
"lit_int_0": ("0f0000004c69746572616c2e496e74656765720100" + "00" * 32, lambda: enc_lit_int(0)),
"lit_int_gt_u64": ("0f0000004c69746572616c2e496e74656765720100" + "00" * 8 + "01" + "00" * 23,
    lambda: enc_lit_int(1 << 64)),
"lit_int_max": ("0f0000004c69746572616c2e496e74656765720100" + "ff" * 32, lambda: enc_lit_int(U256 - 1)),
"lit_str_hi": ("0e0000004c69746572616c2e537472696e670100020000006869", lambda: enc_lit_str("hi")),
"lit_str_cafe": ("0e0000004c69746572616c2e537472696e67010005000000636166c3a9", lambda: enc_lit_str("café")),
"unary_neg": ("0b000000556e6172794f702e4e65670000", lambda: null("UnaryOp.Neg")),
"unary_not": ("0b000000556e6172794f702e4e6f740000", lambda: null("UnaryOp.Not")),
"unary_bitnot": ("0e000000556e6172794f702e4269744e6f740000", lambda: null("UnaryOp.BitNot")),
"bin_add": ("0c00000042696e6172794f702e4164640000", lambda: null("BinaryOp.Add")),
"bin_sub": ("0c00000042696e6172794f702e5375620000", lambda: null("BinaryOp.Sub")),
"bin_mul": ("0c00000042696e6172794f702e4d756c0000", lambda: null("BinaryOp.Mul")),
"bin_div": ("0c00000042696e6172794f702e4469760000", lambda: null("BinaryOp.Div")),
"bin_mod": ("0c00000042696e6172794f702e4d6f640000", lambda: null("BinaryOp.Mod")),
"bin_eq": ("0b00000042696e6172794f702e45710000", lambda: null("BinaryOp.Eq")),
"bin_ne": ("0b00000042696e6172794f702e4e650000", lambda: null("BinaryOp.Ne")),
"bin_lt": ("0b00000042696e6172794f702e4c740000", lambda: null("BinaryOp.Lt")),
"bin_le": ("0b00000042696e6172794f702e4c650000", lambda: null("BinaryOp.Le")),
"bin_gt": ("0b00000042696e6172794f702e47740000", lambda: null("BinaryOp.Gt")),
"bin_ge": ("0b00000042696e6172794f702e47650000", lambda: null("BinaryOp.Ge")),
"bin_and": ("0c00000042696e6172794f702e416e640000", lambda: null("BinaryOp.And")),
"bin_or": ("0b00000042696e6172794f702e4f720000", lambda: null("BinaryOp.Or")),
"bin_bitand": ("0f00000042696e6172794f702e426974416e640000", lambda: null("BinaryOp.BitAnd")),
"bin_bitor": ("0e00000042696e6172794f702e4269744f720000", lambda: null("BinaryOp.BitOr")),
"bin_bitxor": ("0f00000042696e6172794f702e426974586f720000", lambda: null("BinaryOp.BitXor")),
"bin_shl": ("0c00000042696e6172794f702e53686c0000", lambda: null("BinaryOp.Shl")),
"bin_shr": ("0c00000042696e6172794f702e5368720000", lambda: null("BinaryOp.Shr")),
}
def _fail(name, fn):
    try: fn(); raise SystemExit(f"{name}: unexpectedly ok")
    except ValueError: pass
def self_check():
    for k, (want, fn) in G.items():
        got = fn().hex()
        if got != want: raise SystemExit(f"{k}: got {got}")
    if G["bin_or"][0] == G["bin_bitor"][0]: raise SystemExit("logicalOr==bitOr")
    _fail("uint_24", lambda: enc_uint(24)); _fail("int_0", lambda: enc_int(0))
    _fail("arr_4097", lambda: enc_array(null("Type.Bool"), 4097))
    _fail("bytes_4097", lambda: enc_bytes(4097))
    _fail("field_other", lambda: enc_field("bls12_381_fr"))
    _fail("raw_close", lambda: enc_named("»")); _fail("raw_cc", lambda: enc_named("a\x00"))
    _fail("int_2_256", lambda: enc_lit_int(U256)); _fail("nfd", lambda: enc_lit_str("e\u0301"))
    print("reference_source_ast_leaf_v1: ok", len(G))
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_leaf_v1.py --self-check")

#!/usr/bin/env python3
"""Independent PA96 supporting-record wire oracle (no Lean/ProofForge)."""
import sys, unicodedata
WIDTHS = (8, 16, 32, 64, 128, 256)
def u16le(v): return bytes((v & 255, (v >> 8) & 255))
def u32le(v): return bytes((v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255))
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
def null(t): return enc_tag(t, [])
def width_ok(w):
    if w not in WIDTHS: raise ValueError("integer width must be one of 8,16,32,64,128,256")
def len_ok(kind, n):
    if not 0 <= n <= 4096: raise ValueError(f"{kind} length must be 0..4096")
def enc_uint(w): width_ok(w); return enc_tag("Type.UInt", [u16le(w)])
def enc_bytes(n): len_ok("bytes", n); return enc_tag("Type.Bytes", [u32le(n)])
def enc_array(el, n): len_ok("array", n); return enc_tag("Type.Array", [el, u32le(n)])
def enc_option(el): return enc_tag("Type.Option", [el])
def enc_map(k, v): return enc_tag("Type.Map", [k, v])
def enc_arr(xs): return u32le(len(xs)) + b"".join(xs)
def enc_param(vis, name, ty):
    return enc_tag("Param", [null(f"Visibility.{vis}"), enc_ident(name), ty])
def enc_field(name, ty): return enc_tag("FieldDecl", [enc_ident(name), ty])
def enc_variant(name, tys): return enc_tag("EnumVariant", [enc_ident(name), enc_arr(tys)])
# checked-in goldens; never production-generated
G = {
"param_public_bool": ("05000000506172616d0300110000005669736962696c6974792e5075626c69630000010000007809000000547970652e426f6f6c0000",
    lambda: enc_param("Public", "x", null("Type.Bool"))),
"param_private_unit": ("05000000506172616d0300120000005669736962696c6974792e507269766174650000010000007909000000547970652e556e69740000",
    lambda: enc_param("Private", "y", null("Type.Unit"))),
"param_commitment_u64": ("05000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000010000007a09000000547970652e55496e7401004000",
    lambda: enc_param("Commitment", "z", enc_uint(64))),
"param_nested_aob": ("05000000506172616d0300110000005669736962696c6974792e5075626c69630000030000006172720a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000",
    lambda: enc_param("Public", "arr", enc_array(enc_option(enc_bytes(0)), 0))),
"param_raw_foobar": ("05000000506172616d0300110000005669736962696c6974792e5075626c6963000007000000666f6f2d62617209000000547970652e426f6f6c0000",
    lambda: enc_param("Public", "foo-bar", null("Type.Bool"))),
"field_uint256": ("090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001",
    lambda: enc_field("count", enc_uint(256))),
"field_map_bool_unit": ("090000004669656c644465636c0200050000006974656d7308000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000",
    lambda: enc_field("items", enc_map(null("Type.Bool"), null("Type.Unit")))),
"variant_empty": ("0b000000456e756d56617269616e740200040000004e6f6e6500000000",
    lambda: enc_variant("None", [])),
"variant_bool_principal": ("0b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000",
    lambda: enc_variant("Some", [null("Type.Bool"), null("Type.Principal")])),
"variant_nested_opt": ("0b000000456e756d56617269616e7402000400000057726170010000000b000000547970652e4f7074696f6e010009000000547970652e556e69740000",
    lambda: enc_variant("Wrap", [enc_option(null("Type.Unit"))])),
}
def _fail(name, fn):
    try: fn(); raise SystemExit(f"{name}: unexpectedly ok")
    except ValueError: pass
def self_check():
    for k, (want, fn) in G.items():
        got = fn().hex()
        if got != want: raise SystemExit(f"{k}: got {got}")
    _fail("param_w24", lambda: enc_param("Public", "bad", enc_uint(24)))
    _fail("field_w24", lambda: enc_field("bad", enc_uint(24)))
    _fail("var_b4097", lambda: enc_variant("B", [enc_bytes(4097)]))
    _fail("raw_close", lambda: enc_param("Public", "»", null("Type.Bool")))
    _fail("raw_cc", lambda: enc_field("a\x00", null("Type.Bool")))
    print("reference_source_ast_support_v1: ok", len(G))
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_support_v1.py --self-check")

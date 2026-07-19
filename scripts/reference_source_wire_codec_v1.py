#!/usr/bin/env python3
"""Independent SPEC-SOURCE-WIRE-001 primitive codec reference (no Lean/ProofForge)."""
from __future__ import annotations
import sys, unicodedata
U16, U256 = 0xFFFF, 1 << 256

def u8(v):
    if not 0 <= v <= 0xFF: raise ValueError("u8")
    return bytes((v,))
def u16le(v):
    if not 0 <= v <= U16: raise ValueError("u16")
    return bytes((v & 255, (v >> 8) & 255))
def u32le(v):
    if not 0 <= v <= 0xFFFFFFFF: raise ValueError("u32")
    return bytes((v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255))
def u256le(n):
    if not 0 <= n < U256: raise ValueError("u256 overflow")
    return n.to_bytes(32, "little")
def enc_bool(b): return b"\x01" if b else b"\x00"
def enc_opt(x): return b"\x00" if x is None else b"\x01" + x
def enc_arr(xs): return u32le(len(xs)) + b"".join(xs)
def _nfc(s):
    if unicodedata.normalize("NFC", s) != s: raise ValueError("non-NFC")
def enc_str(s):
    _nfc(s); r = s.encode("utf-8"); return u32le(len(r)) + r
def enc_ident(s):
    _nfc(s)
    if (not s or s == "_" or s[0].isdigit() or any(c in ".-" for c in s)
            or not (s[0].isalpha() or s[0] == "_")
            or not all(c.isalnum() or c == "_" for c in s)):
        raise ValueError("invalid ident")
    return enc_str(s)
def enc_qn(ps):
    if not 1 <= len(ps) <= 256: raise ValueError("qn")
    return enc_arr([enc_ident(p) for p in ps])
def enc_qi(ps):
    if not 2 <= len(ps) <= 256: raise ValueError("qi")
    return enc_arr([enc_ident(p) for p in ps])
def enc_tag(tag, fs):
    if not tag or any(ord(c) > 127 for c in tag): raise ValueError("tag")
    if len(fs) > U16: raise ValueError("field count")
    tb = tag.encode("ascii")
    return u32le(len(tb)) + tb + u16le(len(fs)) + b"".join(fs)

G = {
    "u8_0": ("00", lambda: u8(0)), "u8_max": ("ff", lambda: u8(255)),
    "u16_0x0102": ("0201", lambda: u16le(0x0102)),
    "u32_0x01020304": ("04030201", lambda: u32le(0x01020304)),
    "u256_0": ("00" * 32, lambda: u256le(0)),
    "u256_max": ("ff" * 32, lambda: u256le(U256 - 1)),
    "bool_f": ("00", lambda: enc_bool(False)), "bool_t": ("01", lambda: enc_bool(True)),
    "opt_none": ("00", lambda: enc_opt(None)), "opt_some_u8_7": ("0107", lambda: enc_opt(u8(7))),
    "arr_empty": ("00000000", lambda: enc_arr([])),
    "arr_u8_1_2": ("020000000102", lambda: enc_arr([u8(1), u8(2)])),
    "ident_Foo": ("03000000466f6f", lambda: enc_ident("Foo")),
    "ident_alpha": ("02000000ceb1", lambda: enc_ident("α")),
    "str_hi": ("020000006869", lambda: enc_str("hi")),
    "str_cafe": ("05000000636166c3a9", lambda: enc_str("café")),
    "qn_Counter": ("0100000007000000436f756e746572", lambda: enc_qn(["Counter"])),
    "qi_Demo_Counter": ("020000000400000044656d6f07000000436f756e746572",
                        lambda: enc_qi(["Demo", "Counter"])),
    "tag_Visibility.Public": ("110000005669736962696c6974792e5075626c69630000",
                              lambda: enc_tag("Visibility.Public", [])),
    "tag_Program": ("0700000050726f6772616d020007000000436f756e74657200000000",
                    lambda: enc_tag("Program", [enc_ident("Counter"), enc_arr([])])),
}
F = [("u256_overflow", lambda: u256le(U256)),
     ("non_nfc", lambda: enc_str(unicodedata.normalize("NFD", "é"))),
     ("invalid_ident", lambda: enc_ident("1bad")), ("qn_empty", lambda: enc_qn([])),
     ("qi_one", lambda: enc_qi(["Only"])), ("qi_257", lambda: enc_qi(["C"] * 257)),
     ("tag_empty", lambda: enc_tag("", [])), ("tag_non_ascii", lambda: enc_tag("Pα", [])),
     ("field_count", lambda: enc_tag("T", [b""] * 65536))]

def self_check():
    for n, (w, f) in G.items():
        g = f().hex()
        if g != w: raise SystemExit(f"GOLDEN {n}: got {g} want {w}")
    for lab, f in F:
        try: f(); raise SystemExit(f"NEGATIVE {lab}: ok")
        except ValueError: pass
    print("reference_source_wire_codec_v1: ok")

if __name__ == "__main__":
    if sys.argv[1:] == ["--self-check"]: self_check()
    else:
        sys.stderr.write("usage: reference_source_wire_codec_v1.py --self-check\n"); sys.exit(2)

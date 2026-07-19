#!/usr/bin/env python3
"""Independent SPEC-SOURCE-WIRE-001 primitive codec reference (no Lean/ProofForge)."""
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
def enc_opt(enc, x): return b"\x00" if x is None else b"\x01" + enc(x)
def enc_arr(enc, xs): return u32le(len(xs)) + b"".join(enc(x) for x in xs)
def _nfc(s):
    if unicodedata.normalize("NFC", s) != s: raise ValueError("non-NFC")
def enc_str(s):
    _nfc(s); r = s.encode("utf-8"); return u32le(len(r)) + r
def _raw_ok(s):
    """SourceNameComponentV1 raw rules (no Name.toString / isId*)."""
    _nfc(s)
    raw = s.encode("utf-8")
    if not 1 <= len(raw) <= 240: raise ValueError("raw length")
    if "\u00bb" in s: raise ValueError("closing guillemet")
    if any(ord(c) <= 0x1F or 0x7F <= ord(c) <= 0x9F for c in s): raise ValueError("Cc")
def enc_ident(s):
    _raw_ok(s)
    return enc_str(s)
def _between(n, lo, hi): return lo <= n <= hi
def _letter_like(c):
    n = ord(c)
    return ((_between(n, 0x3B1, 0x3C9) and n != 0x3BB)
            or (_between(n, 0x391, 0x3A9) and n not in (0x3A0, 0x3A3))
            or any(_between(n, a, b) for a, b in ((0x3CA, 0x3FB), (0x1F00, 0x1FFE),
                   (0x2100, 0x214F), (0x1D49C, 0x1D59F), (0x100, 0x17F)))
            or (_between(n, 0xC0, 0xFF) and n not in (0xD7, 0xF7)))
def _id_first(c): return c == "_" or c.isascii() and c.isalpha() or _letter_like(c)
def _id_rest(c):
    n = ord(c)
    return (_id_first(c) or c.isascii() and c.isdigit() or c in "'!?"
            or _between(n, 0x2080, 0x2089) or _between(n, 0x2090, 0x209C)
            or _between(n, 0x1D62, 0x1D6A) or n == 0x2C7C)
def _common_ident(s):
    _nfc(s)
    if not 1 <= len(s.encode()) <= 240 or s == "_" or not _id_first(s[0]) or not all(map(_id_rest, s[1:])):
        raise ValueError("invalid common ident")
def enc_qn(ps):
    if not 1 <= len(ps) <= 256: raise ValueError("qn")
    for p in ps: _common_ident(p)
    return enc_arr(enc_ident, ps)
def enc_qi(ps):
    if not 2 <= len(ps) <= 256: raise ValueError("qi")
    for p in ps: _common_ident(p)
    return enc_arr(enc_ident, ps)
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
    "opt_none": ("00", lambda: enc_opt(u8, None)),
    "opt_some_u8_7": ("0107", lambda: enc_opt(u8, 7)),
    "arr_empty": ("00000000", lambda: enc_arr(u8, [])),
    "arr_u8_1_2": ("020000000102", lambda: enc_arr(u8, [1, 2])),
    "ident_Foo": ("03000000466f6f", lambda: enc_ident("Foo")),
    "ident_alpha": ("02000000ceb1", lambda: enc_ident("α")),
    "ident_1bad": ("0400000031626164", lambda: enc_ident("1bad")),
    "ident_us": ("010000005f", lambda: enc_ident("_")),
    "ident_hyphen": ("07000000666f6f2d626172", lambda: enc_ident("foo-bar")),
    "ident_open": ("02000000c2ab", lambda: enc_ident("«")),
    "ident_240": ("f0000000" + "41" * 240, lambda: enc_ident("A" * 240)),
    "str_hi": ("020000006869", lambda: enc_str("hi")),
    "str_cafe": ("05000000636166c3a9", lambda: enc_str("café")),
    "qn_Counter": ("0100000007000000436f756e746572", lambda: enc_qn(["Counter"])),
    "qi_Demo_Counter": ("020000000400000044656d6f07000000436f756e746572",
                        lambda: enc_qi(["Demo", "Counter"])),
    "tag_Visibility.Public": ("110000005669736962696c6974792e5075626c69630000",
                              lambda: enc_tag("Visibility.Public", [])),
    "tag_Program": ("0700000050726f6772616d020007000000436f756e74657200000000",
                    lambda: enc_tag("Program", [enc_ident("Counter"), enc_arr(u8, [])])),
}
def fail_child(_): raise ValueError("child-failed")
F = [("u256_overflow", lambda: u256le(U256)),
     ("non_nfc", lambda: enc_str(unicodedata.normalize("NFD", "é"))),
     ("raw_empty", lambda: enc_ident("")),
     ("raw_241", lambda: enc_ident("A" * 241)),
     ("raw_nfd", lambda: enc_ident("e\u0301")),
     ("raw_cc", lambda: enc_ident("a\x00b")),
     ("raw_closing", lambda: enc_ident("»")),
     ("qn_empty", lambda: enc_qn([])),
     ("qi_one", lambda: enc_qi(["Only"])), ("qi_257", lambda: enc_qi(["C"] * 257)),
     ("opt_child", lambda: enc_opt(fail_child, 1)),
     ("arr_child", lambda: enc_arr(fail_child, [1, 2])),
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

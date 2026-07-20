#!/usr/bin/env python3
"""Independent SPEC-SOURCE-WIRE-001 recursive TypeV1 decode oracle (no Lean/ProofForge)."""
import sys, unicodedata
NFC_ERR = "string must already be NFC under Unicode 17.0.0"
IDENT_LEN_ERR = "source name component must contain 1..240 UTF-8 bytes"
WIDTH_ERR = "integer width must be one of 8,16,32,64,128,256"
WIDTHS = (8, 16, 32, 64, 128, 256)
def u16le(v): return bytes((v & 255, (v >> 8) & 255))
def u32le(v):
    return bytes((v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255))
def enc_tag(tag, fields):
    tb = tag.encode("ascii")
    return u32le(len(tb)) + tb + u16le(len(fields)) + b"".join(fields)
# cursor = (bytes, offset); every failure is ValueError(exact production message)
def take(b, o, n):
    if len(b) - o < n: raise ValueError("truncated")
    return b[o:o + n], o + n
def dec_u16(b, o):
    d, o = take(b, o, 2); return d[0] + d[1] * 256, o
def dec_u32(b, o):
    d, o = take(b, o, 4)
    return d[0] + d[1] * 256 + d[2] * 65536 + d[3] * 16777216, o
def finish(b, o):
    if o != len(b): raise ValueError("trailing bytes")
def dec_tag(b, o):  # bounded 1..21 before read/copy, then remaining, UTF-8, ASCII
    n, o = dec_u32(b, o)
    if not 1 <= n <= 21: raise ValueError("tag length must be 1..21 bytes")
    raw, o = take(b, o, n)
    try: s = raw.decode("utf-8")
    except UnicodeDecodeError: raise ValueError("invalid UTF-8 tag")
    if any(ord(c) > 127 for c in s): raise ValueError("tag must be ASCII")
    return s, o
def dec_fc(tag, expected, b, o):
    n, o = dec_u16(b, o)
    if n != expected:
        raise ValueError(f"tag '{tag}' must declare {expected} fields")
    return o
def dec_ident(b, o):  # declared length bounded 1..240 BEFORE remaining/copy
    n, o = dec_u32(b, o)
    if not 1 <= n <= 240: raise ValueError(IDENT_LEN_ERR)
    if len(b) - o < n: raise ValueError("string length exceeds remaining")
    raw, o = b[o:o + n], o + n
    try: s = raw.decode("utf-8")
    except UnicodeDecodeError: raise ValueError("invalid UTF-8")
    if unicodedata.normalize("NFC", s) != s: raise ValueError(NFC_ERR)
    for c in s:
        if unicodedata.category(c) == "Cc":
            raise ValueError("source name component must not contain a Cc code point")
        if c == "»":
            raise ValueError("source name component must not contain closing guillemet")
    return s, o
TYPE_FC = {"Type.Bool": 0, "Type.UInt": 1, "Type.Int": 1, "Type.Principal": 0,
           "Type.Unit": 0, "Type.Named": 1, "Type.Array": 2, "Type.Map": 2,
           "Type.Option": 1, "Type.Bytes": 1, "Type.Field": 1}
def dec_type(depth, nodes, b, o):
    # priority: tag read -> unknown -> fieldCount -> depth -> node -> wire fields
    tag, o = dec_tag(b, o)
    if tag not in TYPE_FC: raise ValueError(f"unknown type tag '{tag}'")
    o = dec_fc(tag, TYPE_FC[tag], b, o)
    if depth < 1: raise ValueError("depth budget exhausted")
    if nodes < 1: raise ValueError("node budget exhausted")
    nodes -= 1
    if tag == "Type.Bool": return ("Bool",), nodes, o
    if tag == "Type.Principal": return ("Principal",), nodes, o
    if tag == "Type.Unit": return ("Unit",), nodes, o
    if tag in ("Type.UInt", "Type.Int"):
        w, o = dec_u16(b, o)
        if w not in WIDTHS: raise ValueError(WIDTH_ERR)
        return (tag[5:], w), nodes, o
    if tag == "Type.Named":
        s, o = dec_ident(b, o); return ("Named", s), nodes, o
    if tag == "Type.Field":
        s, o = dec_ident(b, o)
        if s != "bn254_fr": raise ValueError("field id must be bn254_fr")
        return ("Field", s), nodes, o
    if tag == "Type.Bytes":
        n, o = dec_u32(b, o)
        if n > 4096: raise ValueError("bytes length must be 0..4096")
        return ("Bytes", n), nodes, o
    if tag == "Type.Option":
        el, nodes, o = dec_type(depth - 1, nodes, b, o)
        return ("Option", el), nodes, o
    if tag == "Type.Array":  # element fully decoded before length is read/checked
        el, nodes, o = dec_type(depth - 1, nodes, b, o)
        n, o = dec_u32(b, o)
        if n > 4096: raise ValueError("array length must be 0..4096")
        return ("Array", el, n), nodes, o
    k, nodes, o = dec_type(depth - 1, nodes, b, o)  # Type.Map: key then value
    v, nodes, o = dec_type(depth - 1, nodes, b, o)
    return ("Map", k, v), nodes, o
def enc_type(v):
    k = v[0]
    if k in ("Bool", "Principal", "Unit"): return enc_tag("Type." + k, [])
    if k in ("UInt", "Int"): return enc_tag("Type." + k, [u16le(v[1])])
    if k == "Named": return enc_tag("Type.Named", [u32le(len(v[1].encode())) + v[1].encode()])
    if k == "Field": return enc_tag("Type.Field", [u32le(len(v[1].encode())) + v[1].encode()])
    if k == "Bytes": return enc_tag("Type.Bytes", [u32le(v[1])])
    if k == "Option": return enc_tag("Type.Option", [enc_type(v[1])])
    if k == "Array": return enc_tag("Type.Array", [enc_type(v[1]), u32le(v[2])])
    return enc_tag("Type.Map", [enc_type(v[1]), enc_type(v[2])])
# checked-in goldens (PA95-verbatim); never computed by this oracle
G = (
("09000000547970652e426f6f6c0000", ("Bool",), 1),
("0e000000547970652e5072696e636970616c0000", ("Principal",), 1),
("09000000547970652e556e69740000", ("Unit",), 1),
("09000000547970652e55496e7401000800", ("UInt", 8), 1),
("09000000547970652e55496e7401001000", ("UInt", 16), 1),
("09000000547970652e55496e7401002000", ("UInt", 32), 1),
("09000000547970652e55496e7401004000", ("UInt", 64), 1),
("09000000547970652e55496e7401008000", ("UInt", 128), 1),
("09000000547970652e55496e7401000001", ("UInt", 256), 1),
("08000000547970652e496e7401000800", ("Int", 8), 1),
("08000000547970652e496e7401001000", ("Int", 16), 1),
("08000000547970652e496e7401002000", ("Int", 32), 1),
("08000000547970652e496e7401004000", ("Int", 64), 1),
("08000000547970652e496e7401008000", ("Int", 128), 1),
("08000000547970652e496e7401000001", ("Int", 256), 1),
("0a000000547970652e4e616d6564010007000000666f6f2d626172", ("Named", "foo-bar"), 1),
("08000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000",
 ("Map", ("Bool",), ("Unit",)), 3),
("0a000000547970652e4279746573010000000000", ("Bytes", 0), 1),
("0a000000547970652e4279746573010000100000", ("Bytes", 4096), 1),
("0a000000547970652e4172726179020009000000547970652e426f6f6c000000000000",
 ("Array", ("Bool",), 0), 2),
("0a000000547970652e4172726179020009000000547970652e426f6f6c000000100000",
 ("Array", ("Bool",), 4096), 2),
("0a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000",
 ("Array", ("Option", ("Bytes", 0)), 0), 3),
("0b000000547970652e4f7074696f6e01000a000000547970652e4279746573010000000000",
 ("Option", ("Bytes", 0)), 2),
("0a000000547970652e4669656c64010008000000626e3235345f6672", ("Field", "bn254_fr"), 1),
)
def expect_err(want, fn):
    try: fn()
    except ValueError as e:
        if str(e) != want: raise SystemExit(f"want {want!r} got {str(e)!r}")
        return
    raise SystemExit(f"want {want!r}: unexpectedly ok")
def run(hexs, depth, nodes):
    return dec_type(depth, nodes, bytes.fromhex(hexs), 0)
def self_check():
    npos = nfc = nbnd = 0
    for hexs, val, spend in G:  # 24 positives: exact value, re-encode, finish, node spend
        raw = bytes.fromhex(hexs)
        got, res, off = dec_type(256, 100000, raw, 0)
        if got != val: raise SystemExit(f"{val}: got {got}")
        if off != len(raw): raise SystemExit(f"{val}: not exact consume")
        if enc_type(got) != raw: raise SystemExit(f"{val}: re-encode mismatch")
        if res != 100000 - spend: raise SystemExit(f"{val}: node spend {100000 - res}")
        npos += 1
    rep = {}  # 19 exhaustive field-count negatives: one representative per tag
    for hexs, val, _ in G:
        rep.setdefault("Type." + val[0], hexs)
    for tag, expected in TYPE_FC.items():
        raw = bytes.fromhex(rep[tag]); off = 4 + raw[0]
        cases = (1,) if expected == 0 else ((0, 2) if expected == 1 else (1, 3))
        for fc in cases:
            bad = raw[:off] + u16le(fc) + raw[off + 2:]
            expect_err(f"tag '{tag}' must declare {expected} fields",
                       lambda bad=bad: dec_type(0, 0, bad, 0)); nfc += 1
    # 24 boundaries
    lit_bool = "0c0000004c69746572616c2e426f6f6c010000"
    expect_err("unknown type tag 'Literal.Bool'",  # 1 wrong family, no fc, zero budgets
               lambda: dec_type(0, 0, bytes.fromhex(lit_bool)[:16], 0)); nbnd += 1
    bad = bytes.fromhex(G[0][0]); off = 4 + bad[0]
    bad = bad[:off] + b"\x01\x00" + bad[off + 2:]
    expect_err("tag 'Type.Bool' must declare 0 fields",  # 2 known wrong fc beats budgets
               lambda: dec_type(0, 0, bad, 0)); nbnd += 1
    expect_err("depth budget exhausted",  # 3 depth beats node at (0,0)
               lambda: run(G[0][0], 0, 0)); nbnd += 1
    uint_hdr = "09000000547970652e55496e740100"  # UInt tag+fc, width bytes absent
    expect_err("depth budget exhausted",  # 4 depth before payload read
               lambda: run(uint_hdr, 0, 5)); nbnd += 1
    expect_err("node budget exhausted",  # 5 node before payload read
               lambda: run(uint_hdr, 1, 0)); nbnd += 1
    bad = bytearray(bytes.fromhex(G[3][0])); bad[-2] = 24; bad[-1] = 0
    expect_err(WIDTH_ERR, lambda: dec_type(1, 1, bytes(bad), 0)); nbnd += 1  # 6 UInt24
    bad = bytearray(bytes.fromhex(G[9][0])); bad[-2] = 0; bad[-1] = 0
    expect_err(WIDTH_ERR, lambda: dec_type(1, 1, bytes(bad), 0)); nbnd += 1  # 7 Int0
    bad = bytes.fromhex(G[20][0])[:-4] + u32le(4097)
    expect_err("array length must be 0..4096",  # 8 Array4097
               lambda: dec_type(2, 2, bad, 0)); nbnd += 1
    bad = bytes.fromhex(G[18][0])[:-4] + u32le(4097)
    expect_err("bytes length must be 0..4096",  # 9 Bytes4097
               lambda: dec_type(1, 1, bad, 0)); nbnd += 1
    bad = "0a000000547970652e4669656c6401000c000000626c7331325f3338315f6672"
    expect_err("field id must be bn254_fr",  # 10 wrong Field id
               lambda: run(bad, 1, 1)); nbnd += 1
    expect_err("truncated", lambda: run("09000000547970652e426f6f6c", 1, 1))  # 11 no fc
    nbnd += 1
    expect_err("truncated",  # 12 truncated width
               lambda: run("09000000547970652e55496e74010008", 1, 1)); nbnd += 1
    expect_err("truncated",  # 13 truncated Array child
               lambda: run("0a000000547970652e4172726179020009000000547970652e", 3, 3))
    nbnd += 1
    raw = bytes.fromhex(G[0][0]) + b"\x00"  # 14 trailing via finish only
    expect_err("trailing bytes", lambda: finish(raw, dec_type(1, 1, raw, 0)[2])); nbnd += 1
    got, res, off = run(G[0][0], 1, 1)  # 15 Bool exact (depth=1,nodes=1)
    if got != ("Bool",) or res != 0: raise SystemExit("bool exact budget")
    nbnd += 1
    optb = enc_tag("Type.Option", [bytes.fromhex(G[0][0])])
    got, res, off = dec_type(2, 2, optb, 0)  # 16 Option(Bool) exact pass
    if got != ("Option", ("Bool",)) or res != 0: raise SystemExit("option exact budget")
    nbnd += 1
    expect_err("depth budget exhausted",  # 17 Option(Bool) depth-short
               lambda: dec_type(1, 2, optb, 0)); nbnd += 1
    expect_err("node budget exhausted",  # 18 Map(Bool,Unit) nodes=2 fails at value
               lambda: run(G[16][0], 2, 2)); nbnd += 1
    got, res, off = run(G[16][0], 2, 3)  # 19 Map(Bool,Unit) nodes=3 pass
    if res != 0: raise SystemExit("map nodes=3 residual")
    nbnd += 1
    bad = "0a000000547970652e41727261790200" + lit_bool + "01100000"
    expect_err("unknown type tag 'Literal.Bool'",  # 20 Array bad-element beats len4097
               lambda: run(bad, 3, 5)); nbnd += 1
    bad = "08000000547970652e4d61700200" + lit_bool + G[0][0]
    expect_err("unknown type tag 'Literal.Bool'",  # 21 Map bad-key beats hostile value
               lambda: run(bad, 3, 6)); nbnd += 1
    deep = bytes.fromhex(G[0][0])
    for _ in range(255): deep = enc_tag("Type.Option", [deep])
    got, res, off = dec_type(256, 256, deep, 0)  # 22 Option^255(Bool) = 256 nodes pass
    if res != 0: raise SystemExit("option^255 residual")
    nbnd += 1
    deep = enc_tag("Type.Option", [deep])
    expect_err("depth budget exhausted",  # 23 Option^256(Bool) at depth=256
               lambda: dec_type(256, 257, deep, 0)); nbnd += 1
    expect_err(IDENT_LEN_ERR,  # 24 Named declared len 241 before remaining/copy
               lambda: run("0a000000547970652e4e616d65640100f1000000", 1, 1)); nbnd += 1
    if (npos, nfc, nbnd) != (24, 19, 24):
        raise SystemExit(f"inventory drift: {npos} {nfc} {nbnd}")
    print("reference_source_ast_type_decode_v1: ok 24 19 24")
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_type_decode_v1.py --self-check")

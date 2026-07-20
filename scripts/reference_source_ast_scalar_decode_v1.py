#!/usr/bin/env python3
"""Independent SPEC-SOURCE-WIRE-001 scalar tagged-value decode oracle (no Lean/ProofForge)."""
import sys, unicodedata
NFC_ERR = "string must already be NFC under Unicode 17.0.0"
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
def dec_u256(b, o):
    d, o = take(b, o, 32); return int.from_bytes(d, "little"), o
def dec_bool(b, o):
    d, o = take(b, o, 1)
    if d[0] == 0: return False, o
    if d[0] == 1: return True, o
    raise ValueError("invalid bool marker")
def dec_str(b, o):
    n, o = dec_u32(b, o)
    if len(b) - o < n: raise ValueError("string length exceeds remaining")
    raw, o = take(b, o, n)
    try: s = raw.decode("utf-8")
    except UnicodeDecodeError: raise ValueError("invalid UTF-8")
    if unicodedata.normalize("NFC", s) != s: raise ValueError(NFC_ERR)
    return s, o
def finish(b, o):
    if o != len(b): raise ValueError("trailing bytes")
# bounded tag reader: range check before any read/copy, then remaining, UTF-8, ASCII
def dec_tag(b, o):
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
VIS = (("Visibility.Public", "public_"), ("Visibility.Private", "private_"),
       ("Visibility.Commitment", "commitment"))
UN = (("UnaryOp.Neg", "neg"), ("UnaryOp.Not", "not"), ("UnaryOp.BitNot", "bitNot"))
BIN = tuple(("BinaryOp." + t, v) for t, v in (
    ("Add", "add"), ("Sub", "sub"), ("Mul", "mul"), ("Div", "div"), ("Mod", "mod"),
    ("Eq", "eq"), ("Ne", "ne"), ("Lt", "lt"), ("Le", "le"), ("Gt", "gt"), ("Ge", "ge"),
    ("And", "logicalAnd"), ("Or", "logicalOr"), ("BitAnd", "bitAnd"), ("BitOr", "bitOr"),
    ("BitXor", "bitXor"), ("Shl", "shl"), ("Shr", "shr")))
LIT = ("Literal.Bool", "Literal.Integer", "Literal.String")
VAL2TAG = {v: t for t, v in VIS + UN + BIN}
LIT_TAG = {"bool": "Literal.Bool", "integer": "Literal.Integer", "string": "Literal.String"}
def dec_nullary(table, fam, b, o):
    tag, o = dec_tag(b, o)
    for t, v in table:
        if t == tag: return v, dec_fc(tag, 0, b, o)
    raise ValueError(f"unknown {fam} tag '{tag}'")
def dec_vis(b, o): return dec_nullary(VIS, "visibility", b, o)
def dec_un(b, o): return dec_nullary(UN, "unary-op", b, o)
def dec_bin(b, o): return dec_nullary(BIN, "binary-op", b, o)
def dec_lit(b, o):
    tag, o = dec_tag(b, o)
    if tag not in LIT: raise ValueError(f"unknown literal tag '{tag}'")
    o = dec_fc(tag, 1, b, o)
    if tag == "Literal.Bool":
        v, o = dec_bool(b, o); return ("bool", v), o
    if tag == "Literal.Integer":
        v, o = dec_u256(b, o); return ("integer", v), o
    v, o = dec_str(b, o); return ("string", v), o
DEC = {"visibility": dec_vis, "literal": dec_lit, "unary-op": dec_un, "binary-op": dec_bin}
def enc_value(v):
    if isinstance(v, str): return enc_tag(VAL2TAG[v], [])
    kind = v[0]
    if kind == "bool": return enc_tag("Literal.Bool", [b"\x01" if v[1] else b"\x00"])
    if kind == "integer": return enc_tag("Literal.Integer", [v[1].to_bytes(32, "little")])
    raw = v[1].encode("utf-8")
    if unicodedata.normalize("NFC", v[1]) != v[1]: raise ValueError(NFC_ERR)
    return enc_tag("Literal.String", [u32le(len(raw)) + raw])
# checked-in goldens (PA95/RED-verbatim, one per tag); never computed by this oracle
G = (
("110000005669736962696c6974792e5075626c69630000", "visibility", "public_"),
("120000005669736962696c6974792e507269766174650000", "visibility", "private_"),
("150000005669736962696c6974792e436f6d6d69746d656e740000", "visibility", "commitment"),
("0c0000004c69746572616c2e426f6f6c010000", "literal", ("bool", False)),
("0f0000004c69746572616c2e496e74656765720100" + "00" * 32, "literal", ("integer", 0)),
("0e0000004c69746572616c2e537472696e670100020000006869", "literal", ("string", "hi")),
("0b000000556e6172794f702e4e65670000", "unary-op", "neg"),
("0b000000556e6172794f702e4e6f740000", "unary-op", "not"),
("0e000000556e6172794f702e4269744e6f740000", "unary-op", "bitNot"),
("0c00000042696e6172794f702e4164640000", "binary-op", "add"),
("0c00000042696e6172794f702e5375620000", "binary-op", "sub"),
("0c00000042696e6172794f702e4d756c0000", "binary-op", "mul"),
("0c00000042696e6172794f702e4469760000", "binary-op", "div"),
("0c00000042696e6172794f702e4d6f640000", "binary-op", "mod"),
("0b00000042696e6172794f702e45710000", "binary-op", "eq"),
("0b00000042696e6172794f702e4e650000", "binary-op", "ne"),
("0b00000042696e6172794f702e4c740000", "binary-op", "lt"),
("0b00000042696e6172794f702e4c650000", "binary-op", "le"),
("0b00000042696e6172794f702e47740000", "binary-op", "gt"),
("0b00000042696e6172794f702e47650000", "binary-op", "ge"),
("0c00000042696e6172794f702e416e640000", "binary-op", "logicalAnd"),
("0b00000042696e6172794f702e4f720000", "binary-op", "logicalOr"),
("0f00000042696e6172794f702e426974416e640000", "binary-op", "bitAnd"),
("0e00000042696e6172794f702e4269744f720000", "binary-op", "bitOr"),
("0f00000042696e6172794f702e426974586f720000", "binary-op", "bitXor"),
("0c00000042696e6172794f702e53686c0000", "binary-op", "shl"),
("0c00000042696e6172794f702e5368720000", "binary-op", "shr"),
)
def expect_err(want, fn):
    try: fn()
    except ValueError as e:
        if str(e) != want: raise SystemExit(f"want {want!r} got {str(e)!r}")
        return
    raise SystemExit(f"want {want!r}: unexpectedly ok")
def self_check():
    npos = nfc = nbnd = 0
    for hexs, fam, val in G:  # 27 positives: decode exact value, re-encode same bytes, finish
        raw = bytes.fromhex(hexs)
        got, off = DEC[fam](raw, 0)
        if got != val: raise SystemExit(f"{fam}/{val}: got {got}")
        if off != len(raw): raise SystemExit(f"{fam}/{val}: not exact consume")
        if enc_value(got) != raw: raise SystemExit(f"{fam}/{val}: re-encode mismatch")
        npos += 1
    for hexs, fam, val in G:  # 30 field-count negatives before any child decode
        raw = bytes.fromhex(hexs)
        if isinstance(val, str):
            tag = VAL2TAG[val]; bad = raw[:-2] + b"\x01\x00"
            expect_err(f"tag '{tag}' must declare 0 fields",
                       lambda bad=bad, fam=fam: DEC[fam](bad, 0)); nfc += 1
        else:
            tag = LIT_TAG[val[0]]; off = 4 + raw[0]
            for fc in (0, 2):
                bad = raw[:off] + u16le(fc) + raw[off + 2:]
                expect_err(f"tag '{tag}' must declare 1 fields",
                           lambda bad=bad: DEC[fam](bad, 0)); nfc += 1
    # 14 boundaries: 10 tag/child/trailing + 4 family unknown-before-count (inside 14)
    expect_err("tag length must be 1..21 bytes",  # empty: declared length 0
               lambda: dec_tag(bytes(4), 0)); nbnd += 1
    expect_err("tag length must be 1..21 bytes",  # 22-byte tag
               lambda: dec_tag(u32le(22) + b"A" * 22, 0)); nbnd += 1
    expect_err("truncated", lambda: dec_tag(u32le(5) + b"A", 0)); nbnd += 1
    expect_err("invalid UTF-8 tag", lambda: dec_tag(u32le(1) + b"\xff", 0)); nbnd += 1
    expect_err("tag must be ASCII",
               lambda: dec_tag(u32le(2) + b"\xc2\xa9", 0)); nbnd += 1
    expect_err("invalid bool marker",
               lambda: dec_lit(bytes.fromhex("0c0000004c69746572616c2e426f6f6c010002"), 0))
    nbnd += 1
    expect_err("truncated",
               lambda: dec_lit(bytes.fromhex("0f0000004c69746572616c2e496e74656765720100"), 0))
    nbnd += 1
    expect_err("string length exceeds remaining",
               lambda: dec_lit(bytes.fromhex("0e0000004c69746572616c2e537472696e6701000500000068"), 0))
    nbnd += 1
    # NFD e+combining acute is 3 UTF-8 bytes; length field must be 3
    expect_err(NFC_ERR,
               lambda: dec_lit(bytes.fromhex(
                   "0e0000004c69746572616c2e537472696e6701000300000065cc81"), 0))
    nbnd += 1
    raw = bytes.fromhex(G[0][0]) + b"\x00"  # trailing byte via finish only
    expect_err("trailing bytes", lambda: finish(raw, dec_vis(raw, 0)[1])); nbnd += 1
    # four-family nonalias: sibling tag, fieldCount omitted, wrong family
    expect_err("unknown unary-op tag 'Visibility.Public'",
               lambda: dec_un(bytes.fromhex(G[0][0])[:-2], 0)); nbnd += 1
    expect_err("unknown binary-op tag 'UnaryOp.Neg'",
               lambda: dec_bin(bytes.fromhex(G[6][0])[:-2], 0)); nbnd += 1
    expect_err("unknown literal tag 'BinaryOp.Add'",
               lambda: dec_lit(bytes.fromhex(G[9][0])[:-2], 0)); nbnd += 1
    expect_err("unknown visibility tag 'Literal.Bool'",
               lambda: dec_vis(bytes.fromhex(G[3][0])[:16], 0)); nbnd += 1
    if not ("public_" != "private_" and "neg" != "not" and "logicalOr" != "bitOr"
            and ("bool", True) != ("bool", False)): raise SystemExit("value alias")
    if enc_value("logicalOr") == enc_value("bitOr"): raise SystemExit("logicalOr==bitOr")
    if (npos, nfc, nbnd) != (27, 30, 14):
        raise SystemExit(f"inventory drift: {npos} {nfc} {nbnd}")
    print("reference_source_ast_scalar_decode_v1: ok 27 30 14")
if __name__ == "__main__":
    if "--self-check" in sys.argv: self_check()
    else: print("usage: reference_source_ast_scalar_decode_v1.py --self-check")

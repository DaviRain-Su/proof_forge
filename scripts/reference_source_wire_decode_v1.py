#!/usr/bin/env python3
"""Independent PA92 cursor decoder oracle (no Lean/ProofForge)."""
from __future__ import annotations
import sys, unicodedata
CAP = "array count exceeds caller limit"

class Cursor:
    __slots__ = ("b", "i")
    def __init__(self, b, i=0): self.b, self.i = b, i
    def rem(self): return len(self.b) - self.i
    def take(self, n):
        if self.rem() < n: raise ValueError("truncated")
        s = self.i; self.i += n; return self.b[s:self.i]

def start(b): return Cursor(bytes(b))
def finish(c):
    if c.rem(): raise ValueError("trailing")
def u8(c): return c.take(1)[0]
def u16(c):
    x = c.take(2); return x[0] | (x[1] << 8)
def u32(c):
    x = c.take(4); return x[0] | (x[1] << 8) | (x[2] << 16) | (x[3] << 24)
def u256(c): return int.from_bytes(c.take(32), "little")
def dbool(c):
    m = u8(c)
    if m > 1: raise ValueError("bool")
    return bool(m)
def dopt(dec, c):
    m = u8(c)
    if m == 0: return None
    if m != 1: raise ValueError("option")
    return dec(c)
def darr(mx, dec, c):
    n = u32(c)
    if n > mx: raise ValueError(CAP)
    return [dec(c) for _ in range(n)]
def dstr(c):
    n = u32(c)
    if c.rem() < n: raise ValueError("str-len")
    raw = c.take(n)
    try: s = raw.decode("utf-8")
    except UnicodeDecodeError as e: raise ValueError("utf8") from e
    if unicodedata.normalize("NFC", s) != s: raise ValueError("nfd")
    return s

def run(h, fn):
    c = start(bytes.fromhex(h)); v = fn(c); finish(c); return v

def fail_child(_c): raise ValueError("child-must-not-run")
def err_child(_c): raise ValueError("child-failed")

def must_fail(lab, fn, want=None):
    try: fn(); raise SystemExit(f"NEGATIVE {lab}: ok")
    except ValueError as e:
        if want is not None and str(e) != want: raise SystemExit(f"{lab}: {e}")

def self_check():
    assert run("00", u8) == 0 and run("ff", u8) == 255
    assert run("0201", u16) == 0x0102 and run("04030201", u32) == 0x01020304
    assert run("01020304" + "00" * 24 + "05060708", u256) == 0x04030201 + (0x08070605 << 224)
    assert run("ff" * 32, u256) == (1 << 256) - 1
    assert run("00", dbool) is False and run("01", dbool) is True
    assert run("00", lambda c: dopt(u8, c)) is None
    assert run("0107", lambda c: dopt(u8, c)) == 7
    assert run("00000000", lambda c: darr(8, u8, c)) == []
    assert run("020000000102", lambda c: darr(8, u8, c)) == [1, 2]
    assert run("020000006869", dstr) == "hi"
    assert run("05000000636166c3a9", dstr) == "café"
    must_fail("t_u8", lambda: u8(start(b"")))
    must_fail("t_u16", lambda: u16(start(b"\x01")))
    must_fail("t_u32", lambda: u32(start(b"\x01\x02\x03")))
    must_fail("t_u256", lambda: u256(start(b"\x00" * 31)))
    must_fail("bool2", lambda: dbool(start(b"\x02")))
    must_fail("opt2", lambda: dopt(u8, start(b"\x02")))
    must_fail("cap", lambda: darr(0, fail_child, start(bytes.fromhex("01000000"))), CAP)
    must_fail("child", lambda: darr(8, err_child, start(bytes.fromhex("0100000001"))))
    must_fail("t_child", lambda: darr(8, u8, start(bytes.fromhex("01000000"))))
    must_fail("str_over", lambda: dstr(start(bytes.fromhex("050000006869"))))
    must_fail("utf8", lambda: dstr(start(bytes.fromhex("01000000ff"))))
    must_fail("nfd", lambda: dstr(start(bytes.fromhex("03000000") + "e\u0301".encode())))
    c = start(b"\x00\x00"); u8(c); must_fail("trail", lambda: finish(c))
    print("reference_source_wire_decode_v1: ok")

if __name__ == "__main__":
    if sys.argv[1:] == ["--self-check"]: self_check()
    else:
        sys.stderr.write("usage: reference_source_wire_decode_v1.py --self-check\n"); sys.exit(2)

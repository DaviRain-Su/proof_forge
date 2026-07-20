#!/usr/bin/env python3
"""Independent D1-PA-110 PatternV1 decoder oracle (no Lean/ProofForge imports)."""
import sys, unicodedata
def u16(n): return n.to_bytes(2, "little")
def u32(n): return n.to_bytes(4, "little")
def tag(t, fs): return u32(len(t)) + t.encode() + u16(len(fs)) + b"".join(fs)
def ident(s): return u32(len(s.encode())) + s.encode()
def qid(xs): return u32(len(xs)) + b"".join(ident(x) for x in xs)
def w(): return tag("Pattern.Wildcard", [])
def b(s): return tag("Pattern.Bind", [ident(s)])
def lb(v): return tag("Literal.Bool", [bytes([v])])
def li(v): return tag("Literal.Integer", [v.to_bytes(32,"little")])
def ls(v): return tag("Literal.String", [ident(v)])
def l(v): return tag("Pattern.Literal", [v])
def c(q, xs): return tag("Pattern.Constructor", [qid(q), u32(len(xs))+b"".join(xs)])
G = [
("100000005061747465726e2e57696c64636172640000", ("W",), 1),
("0c0000005061747465726e2e42696e6401000100000078", ("B","x"), 1),
("0c0000005061747465726e2e42696e64010007000000666f6f2d626172", ("B","foo-bar"), 1),
("0f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010000", ("L",("Bool",False)), 1),
("0f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001", ("L",("Bool",True)), 1),
("0f0000005061747465726e2e4c69746572616c01000f0000004c69746572616c2e496e74656765720100"+"00"*8+"01"+"00"*23, ("L",("Int",1<<64)), 1),
("0f0000005061747465726e2e4c69746572616c01000e0000004c69746572616c2e537472696e67010005000000636166c3a9", ("L",("Str","café")), 1),
("130000005061747465726e2e436f6e7374727563746f72020002000000060000004f7074696f6e040000006e6f6e6500000000", ("C",("Option","none"),()), 1),
("130000005061747465726e2e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d6501000000100000005061747465726e2e57696c64636172640000", ("C",("Option","some"),(('W',),)), 2),
("130000005061747465726e2e436f6e7374727563746f720200020000000400000044656d6f0400000050616972020000000c0000005061747465726e2e42696e64010001000000780f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001", ("C",("Demo","Pair"),(('B','x'),('L',('Bool',True)))), 3),
("130000005061747465726e2e436f6e7374727563746f720200020000000400000044656d6f0400000050616972020000000f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c0100010c0000005061747465726e2e42696e6401000100000078", ("C",("Demo","Pair"),(('L',('Bool',True)),('B','x'))), 3),
("130000005061747465726e2e436f6e7374727563746f720200020000000100000041010000004202000000130000005061747465726e2e436f6e7374727563746f720200020000000100000043010000004401000000100000005061747465726e2e57696c646361726400000c0000005061747465726e2e42696e6401000100000079", ("C",("A","B"),(('C',('C','D'),(('W',),)),('B','y'))), 4),]
def take(raw,o,n):
    if len(raw)-o<n: raise ValueError("truncated")
    return raw[o:o+n],o+n
def num(raw,o,n): d,o=take(raw,o,n); return int.from_bytes(d,"little"),o
def dec_tag(raw,o):
    n,o=num(raw,o,4)
    if not 1<=n<=21: raise ValueError("tag length must be 1..21 bytes")
    d,o=take(raw,o,n)
    try: s=d.decode()
    except UnicodeDecodeError: raise ValueError("invalid UTF-8 tag")
    if not s.isascii(): raise ValueError("tag must be ASCII")
    return s,o
def dec_ident(raw,o):
    n,o=num(raw,o,4)
    if not 1<=n<=240: raise ValueError("source name component must contain 1..240 UTF-8 bytes")
    if len(raw)-o<n: raise ValueError("string length exceeds remaining")
    d,o=take(raw,o,n)
    try:s=d.decode()
    except UnicodeDecodeError: raise ValueError("invalid UTF-8")
    if unicodedata.normalize("NFC",s)!=s: raise ValueError("string must already be NFC under Unicode 17.0.0")
    for ch in s:
        category = unicodedata.category(ch)
        if category == "Cc": raise ValueError("source name component must not contain a Cc code point")
        if ch == "»": raise ValueError("source name component must not contain closing guillemet")
    return s,o
def dec_string(raw,o):
    n,o=num(raw,o,4)
    if len(raw)-o<n: raise ValueError("string length exceeds remaining")
    d,o=take(raw,o,n)
    try:s=d.decode()
    except UnicodeDecodeError: raise ValueError("invalid UTF-8")
    if unicodedata.normalize("NFC",s)!=s: raise ValueError("string must already be NFC under Unicode 17.0.0")
    return s,o
def dec_qid(raw,o):
    n,o=num(raw,o,4)
    if not 2<=n<=256: raise ValueError("source qualified id must contain 2..256 components")
    out=[]
    for _ in range(n): x,o=dec_ident(raw,o); out.append(x)
    return tuple(out),o
FC={"Pattern.Wildcard":0,"Pattern.Bind":1,"Pattern.Literal":1,"Pattern.Constructor":2}
def literal(raw,o):
    t,o=dec_tag(raw,o); fs={"Literal.Bool":1,"Literal.Integer":1,"Literal.String":1}
    if t not in fs: raise ValueError(f"unknown literal tag '{t}'")
    n,o=num(raw,o,2)
    if n!=1: raise ValueError(f"tag '{t}' must declare 1 fields")
    if t=="Literal.Bool":
        n,o=num(raw,o,1)
        if n not in (0,1): raise ValueError("invalid bool marker")
        return ("Bool",bool(n)),o
    if t=="Literal.Integer": n,o=num(raw,o,32); return ("Int",n),o
    s,o=dec_string(raw,o); return ("Str",s),o
def dec(depth,nodes,raw,o=0):
    t,o=dec_tag(raw,o)
    if t not in FC: raise ValueError(f"unknown pattern tag '{t}'")
    n,o=num(raw,o,2)
    if n!=FC[t]: raise ValueError(f"tag '{t}' must declare {FC[t]} fields")
    if depth<1: raise ValueError("depth budget exhausted")
    if nodes<1: raise ValueError("node budget exhausted")
    nodes-=1
    if t=="Pattern.Wildcard": return ("W",),nodes,o
    if t=="Pattern.Bind": x,o=dec_ident(raw,o); return ("B",x),nodes,o
    if t=="Pattern.Literal": x,o=literal(raw,o); return ("L",x),nodes,o
    q,o=dec_qid(raw,o); count,o=num(raw,o,4)
    if count>nodes: raise ValueError("array count exceeds caller limit")
    xs=[]
    for _ in range(count): x,nodes,o=dec(depth-1,nodes,raw,o); xs.append(x)
    return ("C",q,tuple(xs)),nodes,o
def enc(v):
    if v[0]=="W": return w()
    if v[0]=="B": return b(v[1])
    if v[0]=="L":
        x=v[1]; z=lb(x[1]) if x[0]=="Bool" else li(x[1]) if x[0]=="Int" else ls(x[1]); return l(z)
    return c(v[1],[enc(x) for x in v[2]])
def err(want,fn):
    try: fn()
    except ValueError as e:
        if str(e)!=want: raise SystemExit(f"want {want!r}, got {str(e)!r}")
        return
    raise SystemExit(f"want {want!r}: unexpectedly ok")
def self_check():
    for hs,want,spent in G:
        raw=bytes.fromhex(hs); got,res,o=dec(256,300,raw)
        if got!=want or enc(got)!=raw or o!=len(raw) or res!=300-spent:
            raise SystemExit("positive mismatch")
    nf=0
    for i,t,e,bads in [(0,"Pattern.Wildcard",0,[1]),(1,"Pattern.Bind",1,[0,2]),(3,"Pattern.Literal",1,[0,2]),(7,"Pattern.Constructor",2,[1,3])]:
        raw=bytes.fromhex(G[i][0]); off=4+raw[0]
        for bad in bads: err(f"tag '{t}' must declare {e} fields",lambda r=raw[:off]+u16(bad)+raw[off+2:]:dec(0,0,r)); nf+=1
    nb=0; W=bytes.fromhex(G[0][0]); CW=bytes.fromhex(G[8][0]); CE=bytes.fromhex(G[7][0])
    empty_bind=bytes.fromhex("0c0000005061747465726e2e42696e64010000000000")
    cases=[("unknown pattern tag 'Literal.Bool'",lambda:dec(0,0,bytes.fromhex("0c0000004c69746572616c2e426f6f6c"))),
      ("depth budget exhausted",lambda:dec(0,0,W)),("node budget exhausted",lambda:dec(1,0,empty_bind)),
      ("truncated",lambda:dec(2,2,W[:-2])),("invalid bool marker",lambda:dec(1,1,bytes.fromhex(G[3][0])[:-1]+b'\x02')),
      ("depth budget exhausted",lambda:dec(1,2,CW)),("array count exceeds caller limit",lambda:dec(2,1,CW)),
      ("array count exceeds caller limit",lambda:dec(2,1,CE[:-4]+u32(1))),
      ("truncated",lambda:dec(2,2,CE[:-4])),("source qualified id must contain 2..256 components",lambda:dec(2,2,CE[:27]+u32(1)))]
    for want,fn in cases: err(want,fn); nb+=1
    got,res,o=dec(1,1,CE); assert res==0 and o==len(CE); nb+=1
    raw=W+b'\0'; got,res,o=dec(1,1,raw); err("trailing bytes",lambda: (_ for _ in ()).throw(ValueError("trailing bytes")) if o!=len(raw) else None); nb+=1
    prefix=CE[:-4]; pair=prefix+u32(2)+bytes.fromhex(G[1][0])+W
    got,res,o=dec(2,3,pair); assert got[2][0][0]=="B" and got[2][1][0]=="W" and res==0; nb+=1
    err("node budget exhausted",lambda:dec(3,3,prefix+u32(2)+c(("A","B"),[W])+W)); nb+=1
    deep=W
    for _ in range(255): deep=c(("A","B"),[deep])
    got,res,o=dec(256,256,deep); assert res==0 and o==len(deep); nb+=1
    err("depth budget exhausted",lambda:dec(256,257,c(("A","B"),[deep]))); nb+=1
    err("array count exceeds caller limit",lambda:dec(256,255,deep)); nb+=1
    # Additional exact priority/truncation/count boundaries.
    for want,fn in [("tag 'Pattern.Wildcard' must declare 0 fields",lambda:dec(0,0,W[:-2]+u16(1))),
      ("source name component must contain 1..240 UTF-8 bytes",lambda:dec(1,1,empty_bind)),
      ("array count exceeds caller limit",lambda:dec(2,2,prefix+u32(3))),
      ("truncated",lambda:dec(2,2,W[:6]))]: err(want,fn); nb+=1
    empty_string=l(tag("Literal.String",[u32(0)]))
    got,res,o=dec(1,1,empty_string); assert got==("L",("Str","")) and res==0 and o==len(empty_string); nb+=1
    for bad,want in (("a\x00","source name component must not contain a Cc code point"),
                     ("»","source name component must not contain closing guillemet")):
        err(want,lambda bad=bad:dec(1,1,b(bad))); nb+=1
    if (len(G),nf,nb)!=(12,7,24): raise SystemExit(f"inventory drift {len(G)} {nf} {nb}")
    print("reference_source_ast_pattern_decode_v1: ok 12 7 24")
if __name__=="__main__":
    if "--self-check" in sys.argv:self_check()
    else: print("usage: reference_source_ast_pattern_decode_v1.py --self-check")

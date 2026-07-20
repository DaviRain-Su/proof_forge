#!/usr/bin/env python3
"""Independent PA113 Place/Expr decode oracle (stdlib only; assert-free)."""
import sys, unicodedata
DEPTH,NODE,COUNT="depth budget exhausted","node budget exhausted","array count exceeds caller limit"
EMPTY="expr match arms must be nonempty"
QID_ERR="source qualified id must contain 2..256 components"
class E(Exception): pass
def u16(n): return bytes((n&255,(n>>8)&255))
def u32(n): return bytes((n&255,(n>>8)&255,(n>>16)&255,(n>>24)&255))
def ru16(b,o):
    if len(b)-o<2: raise E("truncated")
    return b[o]|(b[o+1]<<8),o+2
def ru32(b,o):
    if len(b)-o<4: raise E("truncated")
    return b[o]|(b[o+1]<<8)|(b[o+2]<<16)|(b[o+3]<<24),o+4
def take(b,o,n):
    if len(b)-o<n: raise E("truncated")
    return b[o:o+n],o+n
def estr(s):
    if unicodedata.normalize("NFC",s)!=s: raise E("non-NFC")
    r=s.encode("utf-8"); return u32(len(r))+r
def eident(s):
    r=s.encode("utf-8")
    if not 1<=len(r)<=240: raise E("source name component must contain 1..240 UTF-8 bytes")
    if "»" in s or any(ord(c)<=0x1F or 0x7F<=ord(c)<=0x9F for c in s): raise E("Cc")
    if unicodedata.normalize("NFC",s)!=s: raise E("non-NFC")
    return estr(s)
def etag(tag,fs):
    tb=tag.encode("ascii"); return u32(len(tb))+tb+u16(len(fs))+b"".join(fs)
def earr(xs): return u32(len(xs))+b"".join(xs)
def null(t): return etag(t,[])
def eqid(ps): return earr([eident(p) for p in ps])
def elit(v):
    k=v[0]
    if k=="bool": return etag("Literal.Bool",[bytes([1 if v[1] else 0])])
    if k=="int": return etag("Literal.Integer",[int(v[1]).to_bytes(32,"little")])
    r=v[1].encode("utf-8"); return etag("Literal.String",[u32(len(r))+r])
def epat(p):
    k=p[0]
    if k=="wild": return null("Pattern.Wildcard")
    if k=="bind": return etag("Pattern.Bind",[eident(p[1])])
    if k=="plit": return etag("Pattern.Literal",[elit(p[1])])
    return etag("Pattern.Constructor",[eqid(p[1]),earr([epat(a) for a in p[2]])])
def eplace(p):
    k=p[0]
    if k=="pname": return etag("Place.Name",[eident(p[1])])
    if k=="pfield": return etag("Place.Field",[eplace(p[1]),eident(p[2])])
    return etag("Place.Index",[eplace(p[1]),eexpr(p[2])])
def eexpr(e):
    k=e[0]
    if k=="elit": return etag("Expr.Literal",[elit(e[1])])
    if k=="eplace": return etag("Expr.Place",[eplace(e[1])])
    if k=="ector": return etag("Expr.Constructor",[eqid(e[1]),earr([eexpr(a) for a in e[2]])])
    if k=="eun": return etag("Expr.Unary",[null("UnaryOp."+{"neg":"Neg","not":"Not","bitNot":"BitNot"}[e[1]]),eexpr(e[2])])
    if k=="ebin":
        op={"add":"Add","sub":"Sub","mul":"Mul","div":"Div","mod":"Mod","eq":"Eq","ne":"Ne","lt":"Lt","le":"Le","gt":"Gt","ge":"Ge","and":"And","or":"Or","bitAnd":"BitAnd","bitOr":"BitOr","bitXor":"BitXor","shl":"Shl","shr":"Shr"}[e[1]]
        return etag("Expr.Binary",[null("BinaryOp."+op),eexpr(e[2]),eexpr(e[3])])
    if k=="eloc": return etag("Expr.LocalCall",[eident(e[1]),earr([eexpr(a) for a in e[2]])])
    return etag("Expr.Match",[eexpr(e[1]),earr([earm(a) for a in e[2]])])
def earm(a): return etag("ExprMatchArm",[epat(a[1]),eexpr(a[2])])
def eext(x): return etag("ExternalCallExpr",[eqid(x[1]),earr([eexpr(a) for a in x[2]])])
ENC={"place":eplace,"expr":eexpr,"arm":earm,"ext":eext}
# --- decode ---
def dtag(b,o):
    n,o=ru32(b,o)
    if not 1<=n<=21: raise E("tag length must be 1..21 bytes")
    raw,o=take(b,o,n)
    try: tag=raw.decode("utf-8")
    except UnicodeDecodeError: raise E("invalid UTF-8 tag")
    if any(ord(c)>127 for c in tag): raise E("tag must be ASCII")
    return tag,o
def dfc(b,o,tag,exp):
    n,o=ru16(b,o)
    if n!=exp: raise E(f"tag '{tag}' must declare {exp} fields")
    return o
def charge(d,n):
    if d<1: raise E(DEPTH)
    if n<1: raise E(NODE)
    return d-1,n-1
def dident(b,o):
    n,o=ru32(b,o)
    if not 1<=n<=240: raise E("source name component must contain 1..240 UTF-8 bytes")
    if len(b)-o<n: raise E("string length exceeds remaining")
    raw,o=take(b,o,n)
    try: s=raw.decode("utf-8")
    except UnicodeDecodeError: raise E("invalid UTF-8")
    if unicodedata.normalize("NFC",s)!=s: raise E("string must already be NFC under Unicode 17.0.0")
    if any(ord(c)<=0x1F or 0x7F<=ord(c)<=0x9F for c in s) or "»" in s: raise E("Cc")
    return s,o
def dqid(b,o):
    n,o=ru32(b,o)
    if not 2<=n<=256: raise E(QID_ERR)
    ps=[]
    for _ in range(n):
        p,o=dident(b,o); ps.append(p)
    return tuple(ps),o
def dlit(b,o):
    tag,o=dtag(b,o)
    if tag=="Literal.Bool":
        o=dfc(b,o,tag,1); m,o=take(b,o,1)
        if m[0] not in (0,1): raise E("invalid bool marker")
        return ("bool",m[0]==1),o
    if tag=="Literal.Integer":
        o=dfc(b,o,tag,1); raw,o=take(b,o,32)
        return ("int",int.from_bytes(raw,"little")),o
    if tag=="Literal.String":
        o=dfc(b,o,tag,1); n,o=ru32(b,o)
        if len(b)-o<n: raise E("string length exceeds remaining")
        raw,o=take(b,o,n)
        try: s=raw.decode("utf-8")
        except UnicodeDecodeError: raise E("invalid UTF-8")
        if unicodedata.normalize("NFC",s)!=s: raise E("string must already be NFC under Unicode 17.0.0")
        return ("str",s),o
    raise E(f"unknown literal tag '{tag}'")
def dun(b,o):
    tag,o=dtag(b,o)
    m={"UnaryOp.Neg":"neg","UnaryOp.Not":"not","UnaryOp.BitNot":"bitNot"}
    if tag not in m: raise E(f"unknown unary-op tag '{tag}'")
    o=dfc(b,o,tag,0); return m[tag],o
def dbin(b,o):
    tag,o=dtag(b,o)
    m={"BinaryOp.Add":"add","BinaryOp.Sub":"sub","BinaryOp.Mul":"mul","BinaryOp.Div":"div","BinaryOp.Mod":"mod",
       "BinaryOp.Eq":"eq","BinaryOp.Ne":"ne","BinaryOp.Lt":"lt","BinaryOp.Le":"le","BinaryOp.Gt":"gt","BinaryOp.Ge":"ge",
       "BinaryOp.And":"and","BinaryOp.Or":"or","BinaryOp.BitAnd":"bitAnd","BinaryOp.BitOr":"bitOr","BinaryOp.BitXor":"bitXor",
       "BinaryOp.Shl":"shl","BinaryOp.Shr":"shr"}
    if tag not in m: raise E(f"unknown binary-op tag '{tag}'")
    o=dfc(b,o,tag,0); return m[tag],o
def dpat(d,n,b,o):
    tag,o=dtag(b,o)
    fc={"Pattern.Wildcard":0,"Pattern.Bind":1,"Pattern.Literal":1,"Pattern.Constructor":2}
    if tag not in fc: raise E(f"unknown pattern tag '{tag}'")
    o=dfc(b,o,tag,fc[tag]); d,n=charge(d,n)
    if tag=="Pattern.Wildcard": return ("wild",),n,o
    if tag=="Pattern.Bind":
        x,o=dident(b,o); return ("bind",x),n,o
    if tag=="Pattern.Literal":
        v,o=dlit(b,o); return ("plit",v),n,o
    q,o=dqid(b,o); cnt,o=ru32(b,o)
    if cnt>n: raise E(COUNT)
    args=[]
    for _ in range(cnt):
        a,n,o=dpat(d,n,b,o); args.append(a)
    return ("pctor",q,tuple(args)),n,o
PFC={"Place.Name":1,"Place.Field":2,"Place.Index":2}
EFC={"Expr.Literal":1,"Expr.Place":1,"Expr.Constructor":2,"Expr.Unary":2,"Expr.Binary":3,"Expr.LocalCall":2,"Expr.Match":2}
def dplace(d,n,b,o):
    tag,o=dtag(b,o)
    if tag not in PFC: raise E(f"unknown place tag '{tag}'")
    o=dfc(b,o,tag,PFC[tag]); d,n=charge(d,n)
    if tag=="Place.Name":
        x,o=dident(b,o); return ("pname",x),n,o
    if tag=="Place.Field":
        base,n,o=dplace(d,n,b,o); f,o=dident(b,o); return ("pfield",base,f),n,o
    base,n,o=dplace(d,n,b,o); ix,n,o=dexpr(d,n,b,o); return ("pindex",base,ix),n,o
def dexpr(d,n,b,o):
    tag,o=dtag(b,o)
    if tag not in EFC: raise E(f"unknown expr tag '{tag}'")
    o=dfc(b,o,tag,EFC[tag]); d,n=charge(d,n)
    if tag=="Expr.Literal":
        v,o=dlit(b,o); return ("elit",v),n,o
    if tag=="Expr.Place":
        p,n,o=dplace(d,n,b,o); return ("eplace",p),n,o
    if tag=="Expr.Constructor":
        q,o=dqid(b,o); cnt,o=ru32(b,o)
        if cnt>n: raise E(COUNT)
        args=[]
        for _ in range(cnt):
            a,n,o=dexpr(d,n,b,o); args.append(a)
        return ("ector",q,tuple(args)),n,o
    if tag=="Expr.Unary":
        op,o=dun(b,o); e,n,o=dexpr(d,n,b,o); return ("eun",op,e),n,o
    if tag=="Expr.Binary":
        op,o=dbin(b,o); l,n,o=dexpr(d,n,b,o); r,n,o=dexpr(d,n,b,o); return ("ebin",op,l,r),n,o
    if tag=="Expr.LocalCall":
        cal,o=dident(b,o); cnt,o=ru32(b,o)
        if cnt>n: raise E(COUNT)
        args=[]
        for _ in range(cnt):
            a,n,o=dexpr(d,n,b,o); args.append(a)
        return ("eloc",cal,tuple(args)),n,o
    sc,n,o=dexpr(d,n,b,o); cnt,o=ru32(b,o)
    if cnt==0: raise E(EMPTY)
    if cnt>n: raise E(COUNT)
    arms=[]
    for _ in range(cnt):
        a,n,o=darm(d,n,b,o); arms.append(a)
    return ("ematch",sc,tuple(arms)),n,o
def darm(d,n,b,o):
    tag,o=dtag(b,o)
    if tag!="ExprMatchArm": raise E(f"unknown expr-match-arm tag '{tag}'")
    o=dfc(b,o,tag,2); d,n=charge(d,n)
    p,n,o=dpat(d,n,b,o); v,n,o=dexpr(d,n,b,o); return ("arm",p,v),n,o
def dext(d,n,b,o):
    tag,o=dtag(b,o)
    if tag!="ExternalCallExpr": raise E(f"unknown external-call tag '{tag}'")
    o=dfc(b,o,tag,2); d,n=charge(d,n)
    q,o=dqid(b,o); cnt,o=ru32(b,o)
    if cnt>n: raise E(COUNT)
    args=[]
    for _ in range(cnt):
        a,n,o=dexpr(d,n,b,o); args.append(a)
    return ("ext",q,tuple(args)),n,o
DEC={"place":dplace,"expr":dexpr,"arm":darm,"ext":dext}
# independent expected tuples (not derived by decoding)
WANT={
  "place_name": ("pname","x"),
  "place_field": ("pfield",("pname","s"),"total"),
  "place_index": ("pindex",("pname","arr"),("elit",("int",1))),
  "expr_lit_2_64": ("elit",("int",1<<64)),
  "expr_place": ("eplace",("pname","x")),
  "expr_ctor_some": ("ector",("Option","some"),(("elit",("bool",True)),)),
  "expr_ctor_none": ("ector",("Option","none"),()),
  "nonalias_ctor_12": ("ector",("Option","some"),(("elit",("int",1)),("elit",("int",2)))),
  "nonalias_ctor_21": ("ector",("Option","some"),(("elit",("int",2)),("elit",("int",1)))),
  "expr_unary": ("eun","neg",("elit",("int",1))),
  "expr_binary": ("ebin","add",("elit",("int",1)),("elit",("int",2))),
  "expr_local": ("eloc","helper",( ("elit",("int",1)),)),
  "expr_match": ("ematch",("elit",("int",1)),(
      ("arm",("bind","x"),("elit",("int",1))),
      ("arm",("wild",),("elit",("int",2))))),
  "expr_arm": ("arm",("bind","x"),("elit",("int",1))),
  "ext_empty": ("ext",("Math","add"),()),
}
GOLD={
  'place_name': bytes.fromhex('0a000000506c6163652e4e616d6501000100000078'),
  'place_field': bytes.fromhex('0b000000506c6163652e4669656c6402000a000000506c6163652e4e616d650100010000007305000000746f74616c'),
  'place_index': bytes.fromhex('0b000000506c6163652e496e64657802000a000000506c6163652e4e616d650100030000006172720c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000'),
  'expr_lit_2_64': bytes.fromhex('0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000010000000000000000000000000000000000000000000000'),
  'expr_place': bytes.fromhex('0a000000457870722e506c61636501000a000000506c6163652e4e616d6501000100000078'),
  'expr_ctor_some': bytes.fromhex('10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d65010000000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001'),
  'expr_ctor_none': bytes.fromhex('10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e040000006e6f6e6500000000'),
  'expr_unary': bytes.fromhex('0a000000457870722e556e61727902000b000000556e6172794f702e4e656700000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000'),
  'expr_binary': bytes.fromhex('0b000000457870722e42696e61727903000c00000042696e6172794f702e41646400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000'),
  'expr_local': bytes.fromhex('0e000000457870722e4c6f63616c43616c6c02000600000068656c706572010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000'),
  'expr_match': bytes.fromhex('0a000000457870722e4d6174636802000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000020000000c000000457870724d6174636841726d02000c0000005061747465726e2e42696e64010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870724d6174636841726d0200100000005061747465726e2e57696c646361726400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000'),
  'expr_arm': bytes.fromhex('0c000000457870724d6174636841726d02000c0000005061747465726e2e42696e64010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000'),
  'ext_empty': bytes.fromhex('1000000045787465726e616c43616c6c45787072020002000000040000004d6174680300000061646400000000'),
  'nonalias_ctor_12': bytes.fromhex('10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d65020000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000'),
  'nonalias_ctor_21': bytes.fromhex('10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d65020000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010002000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000'),
}
SPENT={
  "place_name":(1,"place"),"place_field":(2,"place"),"place_index":(3,"place"),
  "expr_lit_2_64":(1,"expr"),"expr_place":(2,"expr"),"expr_ctor_some":(2,"expr"),"expr_ctor_none":(1,"expr"),
  "nonalias_ctor_12":(3,"expr"),"nonalias_ctor_21":(3,"expr"),
  "expr_unary":(2,"expr"),"expr_binary":(3,"expr"),"expr_local":(2,"expr"),"expr_match":(8,"expr"),
  "expr_arm":(3,"arm"),"ext_empty":(1,"ext"),
}
def setfc(raw,fc):
    o=4+raw[0]; return raw[:o]+u16(fc)+raw[o+2:]
def nofc(raw): return raw[:4+raw[0]]
def etag0(tag): return etag(tag,[])
def expect(want,fn):
    try: fn(); raise SystemExit(f"unexpectedly ok want={want!r}")
    except E as e:
        if str(e)!=want: raise SystemExit(f"want {want!r} got {e!r}")
def self_check():
    npos=nfc=nb=0
    for name,(spent,kind) in SPENT.items():
        raw=GOLD[name]; want=WANT[name]
        v,nodes,o=DEC[kind](256,100,raw,0)
        if v!=want: raise SystemExit(f"value {name}: {v!r}!={want!r}")
        if nodes!=100-spent or o!=len(raw): raise SystemExit(f"pos {name} nodes={nodes} o={o}")
        if ENC[kind](v)!=raw: raise SystemExit(f"reenc {name}")
        npos+=1
    if npos!=15: raise SystemExit(f"npos {npos}")
    if GOLD["nonalias_ctor_12"]==GOLD["nonalias_ctor_21"] or WANT["nonalias_ctor_12"]==WANT["nonalias_ctor_21"]:
        raise SystemExit("ctor alias")
    fcs=[
      ("place",GOLD["place_name"],"Place.Name",1),("place",GOLD["place_field"],"Place.Field",2),
      ("place",GOLD["place_index"],"Place.Index",2),("expr",GOLD["expr_lit_2_64"],"Expr.Literal",1),
      ("expr",GOLD["expr_place"],"Expr.Place",1),("expr",GOLD["expr_ctor_none"],"Expr.Constructor",2),
      ("expr",GOLD["expr_unary"],"Expr.Unary",2),("expr",GOLD["expr_binary"],"Expr.Binary",3),
      ("expr",GOLD["expr_local"],"Expr.LocalCall",2),("expr",GOLD["expr_match"],"Expr.Match",2),
      ("arm",GOLD["expr_arm"],"ExprMatchArm",2),("ext",GOLD["ext_empty"],"ExternalCallExpr",2),
    ]
    for kind,raw,tag,exp in fcs:
        for bad in (exp-1,exp+1):
            expect(f"tag '{tag}' must declare {exp} fields", lambda k=kind,r=raw,f=bad: DEC[k](0,0,setfc(r,f),0)); nfc+=1
    for dec,tag,msg in [
        ("place","Expr.Literal","unknown place tag 'Expr.Literal'"),
        ("place","Expr.Place","unknown place tag 'Expr.Place'"),
        ("place","Expr.Binary","unknown place tag 'Expr.Binary'"),
        ("expr","Place.Name","unknown expr tag 'Place.Name'"),
        ("expr","ExprMatchArm","unknown expr tag 'ExprMatchArm'"),
        ("expr","ExternalCallExpr","unknown expr tag 'ExternalCallExpr'"),
        ("arm","Place.Field","unknown expr-match-arm tag 'Place.Field'"),
        ("arm","Expr.Match","unknown expr-match-arm tag 'Expr.Match'"),
        ("ext","Place.Index","unknown external-call tag 'Place.Index'"),
        ("ext","Expr.Unary","unknown external-call tag 'Expr.Unary'"),
    ]:
        expect(msg, lambda k=dec,t=tag: DEC[k](0,0,nofc(etag0(t)),0)); nb+=1
    expect(DEPTH, lambda: dplace(0,0,GOLD["place_name"],0)); nb+=1
    for kind,raw in [("place",etag("Place.Name",[b""])),("expr",etag("Expr.Literal",[b""])),
                     ("arm",etag("ExprMatchArm",[b"",b""])),("ext",etag("ExternalCallExpr",[b"",b""]))]:
        expect(NODE, lambda k=kind,r=raw: DEC[k](1,0,r,0)); nb+=1
    expect("unknown place tag 'BogusBase'", lambda: dplace(4,8,etag("Place.Index",[etag0("BogusBase"),etag0("BogusIndex")]),0)); nb+=1
    expect("unknown expr tag 'BogusIndex'", lambda: dplace(4,8,etag("Place.Index",[etag("Place.Name",[estr("arr")]),etag0("BogusIndex")]),0)); nb+=1
    expect("unknown place tag 'BogusBase'", lambda: dplace(4,8,etag("Place.Field",[etag0("BogusBase"),u32(0)]),0)); nb+=1
    expect("unknown expr tag 'BogusLhs'", lambda: dexpr(4,8,etag("Expr.Binary",[null("BinaryOp.Add"),etag0("BogusLhs"),etag0("BogusRhs")]),0)); nb+=1
    expect("unknown binary-op tag 'Visibility.Public'", lambda: dexpr(4,8,etag("Expr.Binary",[null("Visibility.Public"),etag0("BogusLhs"),etag0("BogusRhs")]),0)); nb+=1
    expect("unknown unary-op tag 'BinaryOp.Add'", lambda: dexpr(4,8,etag("Expr.Unary",[null("BinaryOp.Add"),etag0("BogusOpnd")]),0)); nb+=1
    expect("unknown expr tag 'BogusScrutinee'", lambda: dexpr(4,8,etag("Expr.Match",[etag0("BogusScrutinee"),u32(0)]),0)); nb+=1
    expect(QID_ERR, lambda: dexpr(4,8,etag("Expr.Constructor",[u32(1)+estr("Only"),u32(0xffffffff)]),0)); nb+=1
    expect(QID_ERR, lambda: dext(4,8,etag("ExternalCallExpr",[u32(1)+estr("Only"),u32(0xffffffff)]),0)); nb+=1
    expect("source name component must contain 1..240 UTF-8 bytes", lambda: dexpr(4,8,etag("Expr.LocalCall",[u32(241)+(b"a"*241),u32(0xffffffff)]),0)); nb+=1
    expect("unknown pattern tag 'BogusPattern'", lambda: darm(4,8,etag("ExprMatchArm",[etag0("BogusPattern"),etag0("BogusValue")]),0)); nb+=1
    qidSome=eqid(("Option","some"))
    expect("unknown expr tag 'BogusArg0'", lambda: dexpr(4,8,etag("Expr.Constructor",[qidSome,u32(2)+etag0("BogusArg0")+etag0("BogusArg1")]),0)); nb+=1
    expect(NODE, lambda: dexpr(2,2,GOLD["expr_binary"],0)); nb+=1
    qidMath=eqid(("Math","add"))
    expect(COUNT, lambda: dexpr(4,2,etag("Expr.Constructor",[qidSome,u32(2)]),0)); nb+=1
    expect(COUNT, lambda: dexpr(4,2,etag("Expr.LocalCall",[estr("helper"),u32(2)]),0)); nb+=1
    expect(COUNT, lambda: dext(4,2,etag("ExternalCallExpr",[qidMath,u32(2)]),0)); nb+=1
    expect(COUNT, lambda: dexpr(4,3,etag("Expr.Match",[GOLD["expr_lit_2_64"],u32(2)]),0)); nb+=1
    expect(EMPTY, lambda: dexpr(4,8,etag("Expr.Match",[GOLD["expr_lit_2_64"],u32(0)]),0)); nb+=1
    ext2=eext(("ext",("Math","add"),(("elit",("int",1)),("elit",("int",2)))))
    v,nodes,o=dext(2,3,ext2,0)
    if v!=("ext",("Math","add"),(("elit",("int",1)),("elit",("int",2)))) or nodes or o!=len(ext2):
        raise SystemExit("ext2")
    nb+=1
    expect("invalid bool marker", lambda: dexpr(2,2,etag("Expr.Literal",[etag("Literal.Bool",[bytes([2])])]),0)); nb+=1
    def wrap(n,inner):
        for _ in range(n): inner=etag("Expr.Unary",[null("UnaryOp.Neg"),inner])
        return inner
    deep=wrap(255,eexpr(("elit",("int",0))))
    v,nodes,o=dexpr(256,256,deep,0)
    if nodes or o!=len(deep): raise SystemExit("deep255")
    nb+=1
    expect(DEPTH, lambda: dexpr(256,257,wrap(256,eexpr(("elit",("int",0)))),0)); nb+=1
    expect(NODE, lambda: dexpr(256,255,deep,0)); nb+=1
    raw=GOLD["place_name"]+b"\x00"
    v,nodes,o=dplace(2,2,raw,0)
    if v!=WANT["place_name"] or o!=len(GOLD["place_name"]) or o==len(raw): raise SystemExit("trail")
    nb+=1
    v,nodes,o=dexpr(2,3,GOLD["nonalias_ctor_12"],0)
    if v!=WANT["nonalias_ctor_12"] or nodes or o!=len(GOLD["nonalias_ctor_12"]): raise SystemExit("c12")
    nb+=1
    wantLoc2=("eloc","helper",( ("elit",("int",1)),("elit",("int",2)) ))
    loc2=eexpr(wantLoc2)
    v,nodes,o=dexpr(2,3,loc2,0)
    if v!=wantLoc2 or eexpr(v)!=loc2 or nodes or o!=len(loc2): raise SystemExit("loc2")
    nb+=1
    if (npos,nfc,nb)!=(15,24,41): raise SystemExit(f"inventory {npos} {nfc} {nb}")
    print("reference_source_ast_spine_place_expr_decode_v1: ok 15 24 41")
if __name__=="__main__":
    if sys.argv[1:]!=["--self-check"]:
        print("usage: reference_source_ast_spine_place_expr_decode_v1.py --self-check", file=sys.stderr)
        raise SystemExit(2)
    self_check()

#!/usr/bin/env python3
"""Independent PA114 Stmt/Block/StmtMatchArm decode oracle (stdlib only; assert-free)."""
import sys, unicodedata
DEPTH,NODE,COUNT="depth budget exhausted","node budget exhausted","array count exceeds caller limit"
BLK_E,SMA_E,FOR_E="block statements must be nonempty","stmt match arms must be nonempty","for bound must be 0..4096"
ID_E="source name component must contain 1..240 UTF-8 bytes"
QID_E="source qualified id must contain 2..256 components"
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
    if not 1<=len(r)<=240: raise E(ID_E)
    if "»" in s or any(ord(c)<=0x1F or 0x7F<=ord(c)<=0x9F for c in s): raise E("Cc")
    if unicodedata.normalize("NFC",s)!=s: raise E("non-NFC")
    return estr(s)
def etag(tag,fs):
    tb=tag.encode("ascii"); return u32(len(tb))+tb+u16(len(fs))+b"".join(fs)
def head(tag,fc,payload=b""):
    tb=tag.encode("ascii"); return u32(len(tb))+tb+u16(fc)+payload
def earr(xs): return u32(len(xs))+b"".join(xs)
def null(t): return etag(t,[])
def eqid(ps): return earr([eident(p) for p in ps])
def eopt(x): return b"\x00" if x is None else b"\x01"+x
def elit(v):
    k=v[0]
    if k=="bool": return etag("Literal.Bool",[bytes([1 if v[1] else 0])])
    if k=="int": return etag("Literal.Integer",[int(v[1]).to_bytes(32,"little")])
    r=v[1].encode("utf-8"); return etag("Literal.String",[u32(len(r))+r])
def ety(t):
    if t[0]=="bool": return null("Type.Bool")
    if t[0]=="unit": return null("Type.Unit")
    if t[0]=="named": return etag("Type.Named",[eident(t[1])])
    raise E("ty")
def epat(p):
    if p[0]=="wild": return null("Pattern.Wildcard")
    if p[0]=="bind": return etag("Pattern.Bind",[eident(p[1])])
    raise E("pat")
def eplace(p):
    if p[0]=="pname": return etag("Place.Name",[eident(p[1])])
    raise E("place")
def eexpr(e):
    if e[0]=="elit": return etag("Expr.Literal",[elit(e[1])])
    if e[0]=="eplace": return etag("Expr.Place",[eplace(e[1])])
    raise E("expr")
def eext(x): return etag("ExternalCallExpr",[eqid(x[1]),earr([eexpr(a) for a in x[2]])])
def estmt(s):
    k=s[0]
    if k=="let": return etag("Stmt.Let",[eident(s[1]),eopt(None if s[2] is None else ety(s[2])),eexpr(s[3])])
    if k=="assign": return etag("Stmt.Assign",[eplace(s[1]),eexpr(s[2])])
    if k=="if": return etag("Stmt.If",[eexpr(s[1]),eblock(s[2]),eopt(None if s[3] is None else eblock(s[3]))])
    if k=="match":
        if not s[2]: raise E(SMA_E)
        return etag("Stmt.Match",[eexpr(s[1]),earr([earm(a) for a in s[2]])])
    if k=="for":
        if s[4]>4096: raise E(FOR_E)
        return etag("Stmt.For",[eident(s[1]),eexpr(s[2]),eexpr(s[3]),u32(s[4]),eblock(s[5])])
    if k=="assert": return etag("Stmt.Assert",[eexpr(s[1]),eopt(None if s[2] is None else eident(s[2]))])
    if k=="revert": return etag("Stmt.Revert",[eident(s[1]),earr([eexpr(a) for a in s[2]])])
    if k=="emit": return etag("Stmt.Emit",[eident(s[1]),earr([eexpr(a) for a in s[2]])])
    if k=="return": return etag("Stmt.Return",[eopt(None if s[1] is None else eexpr(s[1]))])
    if k=="call": return etag("Stmt.Call",[eext(s[1])])
    if k=="sched": return etag("Stmt.Schedule",[eext(s[1])])
    raise E("stmt")
def eblock(b):
    if not b[1]: raise E(BLK_E)
    return etag("Block",[earr([estmt(s) for s in b[1]])])
def earm(a): return etag("StmtMatchArm",[epat(a[1]),eblock(a[2])])
ENC={"stmt":estmt,"block":eblock,"arm":earm}
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
def finish(b,o):
    if o!=len(b): raise E("trailing bytes")
def dident(b,o):
    n,o=ru32(b,o)
    if not 1<=n<=240: raise E(ID_E)
    if len(b)-o<n: raise E("string length exceeds remaining")
    raw,o=take(b,o,n)
    try: s=raw.decode("utf-8")
    except UnicodeDecodeError: raise E("invalid UTF-8")
    if unicodedata.normalize("NFC",s)!=s: raise E("string must already be NFC under Unicode 17.0.0")
    if any(ord(c)<=0x1F or 0x7F<=ord(c)<=0x9F for c in s) or "»" in s: raise E("Cc")
    return s,o
def dqid(b,o):
    n,o=ru32(b,o)
    if not 2<=n<=256: raise E(QID_E)
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
def dty(d,n,b,o):
    tag,o=dtag(b,o)
    fc={"Type.Bool":0,"Type.Principal":0,"Type.Unit":0,"Type.UInt":1,"Type.Int":1,"Type.Named":1,
        "Type.Option":1,"Type.Bytes":1,"Type.Field":1,"Type.Array":2,"Type.Map":2}
    if tag not in fc: raise E(f"unknown type tag '{tag}'")
    o=dfc(b,o,tag,fc[tag]); d,n=charge(d,n)
    if tag=="Type.Bool": return ("bool",),n,o
    if tag=="Type.Unit": return ("unit",),n,o
    if tag=="Type.Named":
        x,o=dident(b,o); return ("named",x),n,o
    raise E(f"unsupported type decode surface '{tag}'")
def dpat(d,n,b,o):
    tag,o=dtag(b,o)
    fc={"Pattern.Wildcard":0,"Pattern.Bind":1,"Pattern.Literal":1,"Pattern.Constructor":2}
    if tag not in fc: raise E(f"unknown pattern tag '{tag}'")
    o=dfc(b,o,tag,fc[tag]); d,n=charge(d,n)
    if tag=="Pattern.Wildcard": return ("wild",),n,o
    if tag=="Pattern.Bind":
        x,o=dident(b,o); return ("bind",x),n,o
    raise E(f"unsupported pattern decode surface '{tag}'")
def dplace(d,n,b,o):
    tag,o=dtag(b,o)
    fc={"Place.Name":1,"Place.Field":2,"Place.Index":2}
    if tag not in fc: raise E(f"unknown place tag '{tag}'")
    o=dfc(b,o,tag,fc[tag]); d,n=charge(d,n)
    if tag=="Place.Name":
        x,o=dident(b,o); return ("pname",x),n,o
    raise E(f"unsupported place decode surface '{tag}'")
def dexpr(d,n,b,o):
    tag,o=dtag(b,o)
    fc={"Expr.Literal":1,"Expr.Place":1,"Expr.Constructor":2,"Expr.Unary":2,"Expr.Binary":3,"Expr.LocalCall":2,"Expr.Match":2}
    if tag not in fc: raise E(f"unknown expr tag '{tag}'")
    o=dfc(b,o,tag,fc[tag]); d,n=charge(d,n)
    if tag=="Expr.Literal":
        v,o=dlit(b,o); return ("elit",v),n,o
    if tag=="Expr.Place":
        p,n,o=dplace(d,n,b,o); return ("eplace",p),n,o
    raise E(f"unsupported expr decode surface '{tag}'")
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
SFC={"Stmt.Let":3,"Stmt.Assign":2,"Stmt.If":3,"Stmt.Match":2,"Stmt.For":5,"Stmt.Assert":2,
     "Stmt.Revert":2,"Stmt.Emit":2,"Stmt.Return":1,"Stmt.Call":1,"Stmt.Schedule":1}
def dstmt(d,n,b,o):
    tag,o=dtag(b,o)
    if tag not in SFC: raise E(f"unknown stmt tag '{tag}'")
    o=dfc(b,o,tag,SFC[tag]); d,n=charge(d,n)
    if tag=="Stmt.Let":
        name,o=dident(b,o); m,o=take(b,o,1)
        if m[0]==0: ty=None
        elif m[0]==1:
            ty,n,o=dty(d,n,b,o)
        else: raise E("invalid option marker")
        v,n,o=dexpr(d,n,b,o); return ("let",name,ty,v),n,o
    if tag=="Stmt.Assign":
        t,n,o=dplace(d,n,b,o); v,n,o=dexpr(d,n,b,o); return ("assign",t,v),n,o
    if tag=="Stmt.If":
        c,n,o=dexpr(d,n,b,o); th,n,o=dblock(d,n,b,o); m,o=take(b,o,1)
        if m[0]==0: el=None
        elif m[0]==1: el,n,o=dblock(d,n,b,o)
        else: raise E("invalid option marker")
        return ("if",c,th,el),n,o
    if tag=="Stmt.Match":
        sc,n,o=dexpr(d,n,b,o); cnt,o=ru32(b,o)
        if cnt==0: raise E(SMA_E)
        if cnt>n: raise E(COUNT)
        arms=[]
        for _ in range(cnt):
            a,n,o=darm(d,n,b,o); arms.append(a)
        return ("match",sc,tuple(arms)),n,o
    if tag=="Stmt.For":
        binder,o=dident(b,o); st,n,o=dexpr(d,n,b,o); en,n,o=dexpr(d,n,b,o)
        bd,o=ru32(b,o)
        if bd>4096: raise E(FOR_E)
        body,n,o=dblock(d,n,b,o); return ("for",binder,st,en,bd,body),n,o
    if tag=="Stmt.Assert":
        c,n,o=dexpr(d,n,b,o); m,o=take(b,o,1)
        if m[0]==0: err=None
        elif m[0]==1: err,o=dident(b,o)
        else: raise E("invalid option marker")
        return ("assert",c,err),n,o
    if tag=="Stmt.Revert":
        err,o=dident(b,o); cnt,o=ru32(b,o)
        if cnt>n: raise E(COUNT)
        args=[]
        for _ in range(cnt):
            a,n,o=dexpr(d,n,b,o); args.append(a)
        return ("revert",err,tuple(args)),n,o
    if tag=="Stmt.Emit":
        ev,o=dident(b,o); cnt,o=ru32(b,o)
        if cnt>n: raise E(COUNT)
        args=[]
        for _ in range(cnt):
            a,n,o=dexpr(d,n,b,o); args.append(a)
        return ("emit",ev,tuple(args)),n,o
    if tag=="Stmt.Return":
        m,o=take(b,o,1)
        if m[0]==0: v=None
        elif m[0]==1: v,n,o=dexpr(d,n,b,o)
        else: raise E("invalid option marker")
        return ("return",v),n,o
    if tag=="Stmt.Call":
        x,n,o=dext(d,n,b,o); return ("call",x),n,o
    x,n,o=dext(d,n,b,o); return ("sched",x),n,o
def dblock(d,n,b,o):
    tag,o=dtag(b,o)
    if tag!="Block": raise E(f"unknown block tag '{tag}'")
    o=dfc(b,o,tag,1); d,n=charge(d,n)
    cnt,o=ru32(b,o)
    if cnt==0: raise E(BLK_E)
    if cnt>n: raise E(COUNT)
    sts=[]
    for _ in range(cnt):
        s,n,o=dstmt(d,n,b,o); sts.append(s)
    return ("block",tuple(sts)),n,o
def darm(d,n,b,o):
    tag,o=dtag(b,o)
    if tag!="StmtMatchArm": raise E(f"unknown stmt-match-arm tag '{tag}'")
    o=dfc(b,o,tag,2); d,n=charge(d,n)
    p,n,o=dpat(d,n,b,o); body,n,o=dblock(d,n,b,o); return ("arm",p,body),n,o
DEC={"stmt":dstmt,"block":dblock,"arm":darm}
L0=("elit",("int",0)); L1=("elit",("int",1)); L4096=("elit",("int",4096)); LT=("elit",("bool",True))
PN=("pname","x"); RET0=("return",None); RET1=("return",L1)
BLK1=("block",(RET0,)); BLK1R=("block",(RET1,)); EMIT=("emit","Ping",())
BLK2=("block",(RET0,EMIT)); BLKR=("block",(EMIT,RET0))
ARM=("arm",("wild",),BLK1)
EXT0=("ext",("Math","add"),()); EXT1=("ext",("Math","add"),(L1,))
WANT={
  "stmt_let_none":("let","x",None,L1),"stmt_let_some":("let","y",("bool",),LT),
  "stmt_assign":("assign",PN,L1),"stmt_if_none":("if",LT,BLK1,None),
  "stmt_if_some":("if",LT,BLK1,BLK1R),"stmt_match":("match",L1,(ARM,)),
  "stmt_for_0":("for","i",L0,L4096,0,BLK1),"stmt_for_4096":("for","i",L0,L4096,4096,BLK1),
  "stmt_assert_none":("assert",LT,None),"stmt_assert_some":("assert",LT,"Denied"),
  "stmt_revert_empty":("revert","Denied",()),"stmt_revert_one":("revert","Denied",(L1,)),
  "stmt_emit":EMIT,"stmt_return_none":RET0,"stmt_return_1":RET1,
  "stmt_call":("call",EXT0),"stmt_sched":("sched",EXT1),"block_single":BLK1,
  "block_multi":BLK2,"stmt_arm":ARM,"nonalias_blk_er":BLKR,
}
SPENT={
  "stmt_let_none":(2,"stmt"),"stmt_let_some":(3,"stmt"),"stmt_assign":(3,"stmt"),
  "stmt_if_none":(4,"stmt"),"stmt_if_some":(7,"stmt"),"stmt_match":(6,"stmt"),
  "stmt_for_0":(5,"stmt"),"stmt_for_4096":(5,"stmt"),"stmt_assert_none":(2,"stmt"),
  "stmt_assert_some":(2,"stmt"),"stmt_revert_empty":(1,"stmt"),"stmt_revert_one":(2,"stmt"),
  "stmt_emit":(1,"stmt"),"stmt_return_none":(1,"stmt"),"stmt_return_1":(2,"stmt"),
  "stmt_call":(2,"stmt"),"stmt_sched":(3,"stmt"),"block_single":(2,"block"),
  "block_multi":(3,"block"),"stmt_arm":(4,"arm"),"nonalias_blk_er":(3,"block"),
}
GOLD={
"stmt_let_none":bytes.fromhex("0800000053746d742e4c657403000100000078000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"),
"stmt_let_some":bytes.fromhex("0800000053746d742e4c6574030001000000790109000000547970652e426f6f6c00000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001"),
"stmt_assign":bytes.fromhex("0b00000053746d742e41737369676e02000a000000506c6163652e4e616d65010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"),
"stmt_if_none":bytes.fromhex("0700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e01000000"),
"stmt_if_some":bytes.fromhex("0700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e0100000105000000426c6f636b0100010000000b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"),
"stmt_match":bytes.fromhex("0a00000053746d742e4d6174636802000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000010000000c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"),
"stmt_for_0":bytes.fromhex("0800000053746d742e466f72050001000000690c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000000000000000000000000000000000000000000000000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"),
"stmt_for_4096":bytes.fromhex("0800000053746d742e466f72050001000000690c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000000000000000000000000000000000000000000010000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"),
"stmt_assert_none":bytes.fromhex("0b00000053746d742e41737365727402000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000100"),
"stmt_assert_some":bytes.fromhex("0b00000053746d742e41737365727402000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001010600000044656e696564"),
"stmt_revert_empty":bytes.fromhex("0b00000053746d742e52657665727402000600000044656e69656400000000"),
"stmt_revert_one":bytes.fromhex("0b00000053746d742e52657665727402000600000044656e696564010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"),
"stmt_emit":bytes.fromhex("0900000053746d742e456d697402000400000050696e6700000000"),
"stmt_return_none":bytes.fromhex("0b00000053746d742e52657475726e010000"),
"stmt_return_1":bytes.fromhex("0b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"),
"stmt_call":bytes.fromhex("0900000053746d742e43616c6c01001000000045787465726e616c43616c6c45787072020002000000040000004d6174680300000061646400000000"),
"stmt_sched":bytes.fromhex("0d00000053746d742e5363686564756c6501001000000045787465726e616c43616c6c45787072020002000000040000004d61746803000000616464010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"),
"block_single":bytes.fromhex("05000000426c6f636b0100010000000b00000053746d742e52657475726e010000"),
"block_multi":bytes.fromhex("05000000426c6f636b0100020000000b00000053746d742e52657475726e0100000900000053746d742e456d697402000400000050696e6700000000"),
"nonalias_blk_er":bytes.fromhex("05000000426c6f636b0100020000000900000053746d742e456d697402000400000050696e67000000000b00000053746d742e52657475726e010000"),
"stmt_arm":bytes.fromhex("0c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"),
}
def setfc(raw,fc):
    o=4+raw[0]; return raw[:o]+u16(fc)+raw[o+2:]
def bad(tag): return u32(len(tag))+tag.encode("ascii")
def ident0(): return u32(0)
def expect(want,fn):
    try: fn(); raise SystemExit(f"unexpectedly ok want={want!r}")
    except E as e:
        if str(e)!=want: raise SystemExit(f"want {want!r} got {e!r}")
def nest_if(n, base):
    cur=base
    for _ in range(n): cur=("if",LT,("block",(cur,)),None)
    return cur
def self_check():
    npos=nfc=nb=0
    order=["stmt_let_none","stmt_let_some","stmt_assign","stmt_if_none","stmt_if_some","stmt_match",
           "stmt_for_0","stmt_for_4096","stmt_assert_none","stmt_assert_some","stmt_revert_empty",
           "stmt_revert_one","stmt_emit","stmt_return_none","stmt_return_1","stmt_call","stmt_sched",
           "block_single","block_multi","stmt_arm","nonalias_blk_er"]
    for name in order:
        spent,kind=SPENT[name]; raw=GOLD[name]; want=WANT[name]
        v,nodes,o=DEC[kind](256,100,raw,0)
        if v!=want: raise SystemExit(f"value {name}: {v!r}!={want!r}")
        if nodes!=100-spent: raise SystemExit(f"pos {name} nodes={nodes}")
        finish(raw,o)
        if ENC[kind](v)!=raw: raise SystemExit(f"reenc {name}")
        npos+=1
    if npos!=21: raise SystemExit(f"npos {npos}")
    if GOLD["block_multi"]==GOLD["nonalias_blk_er"] or WANT["block_multi"]==WANT["nonalias_blk_er"]:
        raise SystemExit("block alias")
    fcs=[
      ("stmt",GOLD["stmt_let_none"],"Stmt.Let",3),("stmt",GOLD["stmt_assign"],"Stmt.Assign",2),
      ("stmt",GOLD["stmt_if_none"],"Stmt.If",3),("stmt",GOLD["stmt_match"],"Stmt.Match",2),
      ("stmt",GOLD["stmt_for_0"],"Stmt.For",5),("stmt",GOLD["stmt_assert_none"],"Stmt.Assert",2),
      ("stmt",GOLD["stmt_revert_empty"],"Stmt.Revert",2),("stmt",GOLD["stmt_emit"],"Stmt.Emit",2),
      ("stmt",GOLD["stmt_return_none"],"Stmt.Return",1),("stmt",GOLD["stmt_call"],"Stmt.Call",1),
      ("stmt",GOLD["stmt_sched"],"Stmt.Schedule",1),("block",GOLD["block_single"],"Block",1),
      ("arm",GOLD["stmt_arm"],"StmtMatchArm",2),
    ]
    for kind,raw,tag,exp in fcs:
        for badfc in (exp-1,exp+1):
            expect(f"tag '{tag}' must declare {exp} fields",
                   lambda k=kind,r=raw,f=badfc: DEC[k](0,0,setfc(r,f),0)); nfc+=1
    if nfc!=26: raise SystemExit(f"nfc {nfc}")
    # PA100 checked-in boundary carriers; never regenerate decoder inputs here.
    E_L0=bytes.fromhex("0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000")
    E_L1=bytes.fromhex("0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000")
    E_LT=bytes.fromhex("0c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001")
    E_LK=bytes.fromhex("0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000")
    PL=bytes.fromhex("0a000000506c6163652e4e616d6501000100000078")
    BLK=bytes.fromhex("05000000426c6f636b0100010000000b00000053746d742e52657475726e010000")
    SA=bytes.fromhex("0c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000")
    PW=bytes.fromhex("100000005061747465726e2e57696c64636172640000")
    # 1-7 unknown/budget
    expect("unknown stmt tag 'Block'", lambda: dstmt(0,0,bad("Block"),0)); nb+=1
    expect("unknown block tag 'Stmt.Return'", lambda: dblock(0,0,bad("Stmt.Return"),0)); nb+=1
    expect("unknown stmt-match-arm tag 'Stmt.Let'", lambda: darm(0,0,bad("Stmt.Let"),0)); nb+=1
    expect(DEPTH, lambda: dstmt(0,0,head("Stmt.Return",1),0)); nb+=1
    expect(NODE, lambda: dstmt(1,0,head("Stmt.Let",3,ident0()),0)); nb+=1
    expect(NODE, lambda: dblock(1,0,head("Block",1,u32(0)),0)); nb+=1
    expect(NODE, lambda: darm(1,0,head("StmtMatchArm",2,bad("BogusPattern")+bad("BogusBody")),0)); nb+=1
    # 8-13 Let/Assign
    expect(ID_E, lambda: dstmt(3,8,etag("Stmt.Let",[ident0(),bytes([2]),bad("BogusValue")]),0)); nb+=1
    expect("invalid option marker", lambda: dstmt(3,8,etag("Stmt.Let",[eident("x"),bytes([2]),bad("BogusValue")]),0)); nb+=1
    expect("unknown type tag 'Expr.Literal'", lambda: dstmt(3,8,etag("Stmt.Let",[eident("x"),bytes([1])+bad("Expr.Literal"),bad("BogusValue")]),0)); nb+=1
    expect(NODE, lambda: dstmt(2,2,GOLD["stmt_let_some"],0)); nb+=1
    expect("unknown place tag 'BogusTarget'", lambda: dstmt(3,8,etag("Stmt.Assign",[bad("BogusTarget"),bad("BogusValue")]),0)); nb+=1
    expect("unknown expr tag 'BogusValue'", lambda: dstmt(3,8,etag("Stmt.Assign",[PL,bad("BogusValue")]),0)); nb+=1
    # 14-22 If/Match
    expect("unknown expr tag 'BogusCondition'", lambda: dstmt(4,16,etag("Stmt.If",[bad("BogusCondition"),bad("BogusThen"),bytes([2])]),0)); nb+=1
    expect("unknown block tag 'BogusThen'", lambda: dstmt(4,16,etag("Stmt.If",[E_LT,bad("BogusThen"),bytes([2])]),0)); nb+=1
    expect("invalid option marker", lambda: dstmt(4,16,etag("Stmt.If",[E_LT,BLK,bytes([2])]),0)); nb+=1
    expect(NODE, lambda: dstmt(3,4,etag("Stmt.If",[E_LT,BLK,bytes([1])+BLK]),0)); nb+=1
    expect("unknown expr tag 'BogusScrutinee'", lambda: dstmt(4,16,etag("Stmt.Match",[bad("BogusScrutinee"),u32(0)]),0)); nb+=1
    expect(SMA_E, lambda: dstmt(4,16,etag("Stmt.Match",[E_L1,u32(0)]),0)); nb+=1
    expect(COUNT, lambda: dstmt(4,3,etag("Stmt.Match",[E_L1,u32(2)]),0)); nb+=1
    expect("unknown stmt-match-arm tag 'BogusArm'", lambda: dstmt(4,16,etag("Stmt.Match",[E_L1,u32(1)+bad("BogusArm")]),0)); nb+=1
    expect(NODE, lambda: dstmt(4,6,etag("Stmt.Match",[E_L1,u32(2)+SA+SA]),0)); nb+=1
    # 23-27 For
    expect(ID_E, lambda: dstmt(4,16,etag("Stmt.For",[ident0(),bad("BogusStart"),bad("BogusEnd"),u32(4097),bad("BogusBody")]),0)); nb+=1
    expect("unknown expr tag 'BogusStart'", lambda: dstmt(4,16,etag("Stmt.For",[eident("i"),bad("BogusStart"),bad("BogusEnd"),u32(4097),bad("BogusBody")]),0)); nb+=1
    expect("unknown expr tag 'BogusEnd'", lambda: dstmt(4,16,etag("Stmt.For",[eident("i"),E_L0,bad("BogusEnd"),u32(4097),bad("BogusBody")]),0)); nb+=1
    expect(FOR_E, lambda: dstmt(4,16,etag("Stmt.For",[eident("i"),E_L0,E_LK,u32(4097),bad("BogusBody")]),0)); nb+=1
    expect(NODE, lambda: dstmt(2,2,etag("Stmt.For",[eident("i"),E_L0,E_LK,u32(0),BLK]),0)); nb+=1
    # 28-40 Assert/Revert/Emit/Return/Call/Sched
    expect("unknown expr tag 'BogusCondition'", lambda: dstmt(3,8,etag("Stmt.Assert",[bad("BogusCondition"),bytes([2])]),0)); nb+=1
    expect("invalid option marker", lambda: dstmt(3,8,etag("Stmt.Assert",[E_LT,bytes([2])]),0)); nb+=1
    expect(ID_E, lambda: dstmt(3,8,etag("Stmt.Assert",[E_LT,bytes([1])+ident0()]),0)); nb+=1
    expect(ID_E, lambda: dstmt(2,8,etag("Stmt.Revert",[ident0(),u32(0xffffffff)]),0)); nb+=1
    expect(COUNT, lambda: dstmt(2,2,etag("Stmt.Revert",[eident("Denied"),u32(2)]),0)); nb+=1
    expect("unknown expr tag 'BogusArg'", lambda: dstmt(2,2,etag("Stmt.Revert",[eident("Denied"),u32(1)+bad("BogusArg")]),0)); nb+=1
    expect(ID_E, lambda: dstmt(2,8,etag("Stmt.Emit",[ident0(),u32(0xffffffff)]),0)); nb+=1
    expect(COUNT, lambda: dstmt(2,2,etag("Stmt.Emit",[eident("Ping"),u32(2)]),0)); nb+=1
    expect("unknown expr tag 'BogusArg'", lambda: dstmt(2,2,etag("Stmt.Emit",[eident("Ping"),u32(1)+bad("BogusArg")]),0)); nb+=1
    expect("invalid option marker", lambda: dstmt(2,8,etag("Stmt.Return",[bytes([2])+bad("BogusValue")]),0)); nb+=1
    expect(NODE, lambda: dstmt(2,1,etag("Stmt.Return",[bytes([1])+E_L1]),0)); nb+=1
    expect("unknown external-call tag 'BogusExternal'", lambda: dstmt(2,8,etag("Stmt.Call",[bad("BogusExternal")]),0)); nb+=1
    expect("unknown external-call tag 'BogusExternal'", lambda: dstmt(2,8,etag("Stmt.Schedule",[bad("BogusExternal")]),0)); nb+=1
    # 41-48 Block/arm
    expect(BLK_E, lambda: dblock(2,8,etag("Block",[u32(0)+bad("BogusStmt")]),0)); nb+=1
    expect(COUNT, lambda: dblock(2,2,etag("Block",[u32(2)]),0)); nb+=1
    expect("unknown stmt tag 'BogusStmt'", lambda: dblock(2,8,etag("Block",[u32(1)+bad("BogusStmt")]),0)); nb+=1
    expect(NODE, lambda: dblock(3,3,etag("Block",[u32(2)+estmt(RET1)+estmt(RET0)]),0)); nb+=1
    # 45 success Emit/Revert order
    want45=("block",(EMIT,("revert","Denied",())))
    raw45=eblock(want45)
    v,nodes,o=dblock(2,3,raw45,0)
    if v!=want45 or nodes or eblock(v)!=raw45: raise SystemExit("b45")
    finish(raw45,o)
    nb+=1
    expect("unknown pattern tag 'BogusPattern'", lambda: darm(3,8,etag("StmtMatchArm",[bad("BogusPattern"),bad("BogusBody")]),0)); nb+=1
    expect("unknown block tag 'BogusBody'", lambda: darm(3,8,etag("StmtMatchArm",[PW,bad("BogusBody")]),0)); nb+=1
    expect(NODE, lambda: darm(2,2,etag("StmtMatchArm",[PW,BLK]),0)); nb+=1
    # 49 trail
    raw=GOLD["stmt_return_none"]+b"\x00"
    v,nodes,o=dstmt(2,2,raw,0)
    if v!=RET0 or o!=len(GOLD["stmt_return_none"]): raise SystemExit("trail")
    expect("trailing bytes",lambda:finish(raw,o))
    nb+=1
    # 50-52 deep nest
    deep50=nest_if(127,("return",L0)); raw50=estmt(deep50)
    v,nodes,o=dstmt(256,383,raw50,0)
    if v!=deep50 or nodes or estmt(v)!=raw50: raise SystemExit("deep50")
    finish(raw50,o)
    nb+=1
    deep51=nest_if(128,RET0)
    expect(DEPTH, lambda: dstmt(256,385,estmt(deep51),0)); nb+=1
    expect(NODE, lambda: dstmt(256,382,raw50,0)); nb+=1
    if (npos,nfc,nb)!=(21,26,52): raise SystemExit(f"inventory {npos} {nfc} {nb}")
    print("reference_source_ast_spine_stmt_decode_v1: ok 21 26 52")
if __name__=="__main__":
    if sys.argv[1:]!=["--self-check"]:
        print("usage: reference_source_ast_spine_stmt_decode_v1.py --self-check", file=sys.stderr)
        raise SystemExit(2)
    self_check()

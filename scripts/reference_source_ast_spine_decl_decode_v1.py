#!/usr/bin/env python3
"""Independent PA115 spine-decl decode oracle (stdlib only; assert-free)."""
import sys, unicodedata
DEPTH,NODE,COUNT="depth budget exhausted","node budget exhausted","array count exceeds caller limit"
BLK_E="block statements must be nonempty"
ID_E="source name component must contain 1..240 UTF-8 bytes"
W_ERR="integer width must be one of 8,16,32,64,128,256"
FIELD_ERR="field id must be bn254_fr"
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
def finish(b,o):
    if o!=len(b): raise E("trailing bytes")
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
def earr(xs): return u32(len(xs))+b"".join(xs)
def null(t): return etag(t,[])
def eopt(x): return b"\x00" if x is None else b"\x01"+x
def vis(v): return null(f"Visibility.{v}")
def ety(t):
    k=t[0]
    if k=="bool": return null("Type.Bool")
    if k=="unit": return null("Type.Unit")
    if k=="principal": return null("Type.Principal")
    if k=="uint":
        w=t[1]
        if w not in (8,16,32,64,128,256): raise E(W_ERR)
        return etag("Type.UInt",[u16(w)])
    if k=="bytes":
        n=t[1]
        if not 0<=n<=4096: raise E("bytes length must be 0..4096")
        return etag("Type.Bytes",[u32(n)])
    if k=="field":
        if t[1]!="bn254_fr": raise E(FIELD_ERR)
        return etag("Type.Field",[eident(t[1])])
    raise E("ty")
def elit(v):
    if v[0]=="bool": return etag("Literal.Bool",[bytes([1 if v[1] else 0])])
    if v[0]=="int": return etag("Literal.Integer",[int(v[1]).to_bytes(32,"little")])
    raise E("lit")
def eplace(p):
    if p[0]=="pname": return etag("Place.Name",[eident(p[1])])
    raise E("place")
def eexpr(e):
    k=e[0]
    if k=="elit": return etag("Expr.Literal",[elit(e[1])])
    if k=="eplace": return etag("Expr.Place",[eplace(e[1])])
    if k=="ebin":
        op={"lt":"Lt","add":"Add"}[e[1]]
        return etag("Expr.Binary",[null("BinaryOp."+op),eexpr(e[2]),eexpr(e[3])])
    raise E("expr")
def eparam(p): return etag("Param",[vis(p[1]),eident(p[2]),ety(p[3])])
def estmt(s):
    k=s[0]
    if k=="assign": return etag("Stmt.Assign",[eplace(s[1]),eexpr(s[2])])
    if k=="return": return etag("Stmt.Return",[eopt(None if s[1] is None else eexpr(s[1]))])
    if k=="if": return etag("Stmt.If",[eexpr(s[1]),eblock(s[2]),eopt(None if s[3] is None else eblock(s[3]))])
    raise E("stmt")
def eblock(b):
    if not b[1]: raise E(BLK_E)
    return etag("Block",[earr([estmt(s) for s in b[1]])])
def econst(c): return etag("ConstDecl",[eident(c[1]),ety(c[2]),eexpr(c[3])])
def einv(i): return etag("InvariantDecl",[eident(i[1]),eexpr(i[2])])
def einit(i): return etag("InitDecl",[earr([eparam(p) for p in i[1]]),eblock(i[2])])
def eentry(x): return etag("EntryDecl",[eident(x[1]),earr([eparam(p) for p in x[2]]),ety(x[3]),eblock(x[4])])
def eview(x): return etag("ViewDecl",[eident(x[1]),earr([eparam(p) for p in x[2]]),ety(x[3]),eblock(x[4])])
def efn(x): return etag("FnDecl",[eident(x[1]),earr([eparam(p) for p in x[2]]),ety(x[3]),eblock(x[4])])
ENC={"const":econst,"inv":einv,"init":einit,"entry":eentry,"view":eview,"fn":efn}
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
    if not 1<=n<=240: raise E(ID_E)
    if len(b)-o<n: raise E("string length exceeds remaining")
    raw,o=take(b,o,n)
    try: s=raw.decode("utf-8")
    except UnicodeDecodeError: raise E("invalid UTF-8")
    if unicodedata.normalize("NFC",s)!=s: raise E("string must already be NFC under Unicode 17.0.0")
    if any(ord(c)<=0x1F or 0x7F<=ord(c)<=0x9F for c in s) or "»" in s: raise E("Cc")
    return s,o
def dlit(b,o):
    tag,o=dtag(b,o)
    if tag=="Literal.Bool":
        o=dfc(b,o,tag,1); m,o=take(b,o,1)
        if m[0] not in (0,1): raise E("invalid bool marker")
        return ("bool",m[0]==1),o
    if tag=="Literal.Integer":
        o=dfc(b,o,tag,1); raw,o=take(b,o,32)
        return ("int",int.from_bytes(raw,"little")),o
    raise E(f"unknown literal tag '{tag}'")
def dvis(b,o):
    tag,o=dtag(b,o)
    m={"Visibility.Public":"Public","Visibility.Private":"Private","Visibility.Commitment":"Commitment"}
    if tag not in m: raise E(f"unknown visibility tag '{tag}'")
    o=dfc(b,o,tag,0); return m[tag],o
def dty(d,n,b,o):
    tag,o=dtag(b,o)
    fc={"Type.Bool":0,"Type.Principal":0,"Type.Unit":0,"Type.UInt":1,"Type.Int":1,"Type.Named":1,
        "Type.Option":1,"Type.Bytes":1,"Type.Field":1,"Type.Array":2,"Type.Map":2}
    if tag not in fc: raise E(f"unknown type tag '{tag}'")
    o=dfc(b,o,tag,fc[tag]); d,n=charge(d,n)
    if tag=="Type.Bool": return ("bool",),n,o
    if tag=="Type.Unit": return ("unit",),n,o
    if tag=="Type.Principal": return ("principal",),n,o
    if tag=="Type.UInt":
        w,o=ru16(b,o)
        if w not in (8,16,32,64,128,256): raise E(W_ERR)
        return ("uint",w),n,o
    if tag=="Type.Bytes":
        ln,o=ru32(b,o)
        if not 0<=ln<=4096: raise E("bytes length must be 0..4096")
        return ("bytes",ln),n,o
    if tag=="Type.Field":
        i,o=dident(b,o)
        if i!="bn254_fr": raise E(FIELD_ERR)
        return ("field",i),n,o
    raise E(f"unsupported type '{tag}'")
def dplace(d,n,b,o):
    tag,o=dtag(b,o)
    fc={"Place.Name":1,"Place.Field":2,"Place.Index":2}
    if tag not in fc: raise E(f"unknown place tag '{tag}'")
    o=dfc(b,o,tag,fc[tag]); d,n=charge(d,n)
    if tag=="Place.Name":
        x,o=dident(b,o); return ("pname",x),n,o
    raise E(f"unsupported place '{tag}'")
def dexpr(d,n,b,o):
    tag,o=dtag(b,o)
    fc={"Expr.Literal":1,"Expr.Place":1,"Expr.Constructor":2,"Expr.Unary":2,"Expr.Binary":3,"Expr.LocalCall":2,"Expr.Match":2}
    if tag not in fc: raise E(f"unknown expr tag '{tag}'")
    o=dfc(b,o,tag,fc[tag]); d,n=charge(d,n)
    if tag=="Expr.Literal":
        v,o=dlit(b,o); return ("elit",v),n,o
    if tag=="Expr.Place":
        p,n,o=dplace(d,n,b,o); return ("eplace",p),n,o
    if tag=="Expr.Binary":
        ot,o=dtag(b,o)
        bm={"BinaryOp.Lt":"lt","BinaryOp.Add":"add"}
        if ot not in bm: raise E(f"unknown binary-op tag '{ot}'")
        o=dfc(b,o,ot,0); op=bm[ot]
        l,n,o=dexpr(d,n,b,o); r,n,o=dexpr(d,n,b,o)
        return ("ebin",op,l,r),n,o
    raise E(f"unsupported expr '{tag}'")
def dparam(d,n,b,o):
    tag,o=dtag(b,o)
    if tag!="Param": raise E(f"unknown param tag '{tag}'")
    o=dfc(b,o,tag,3); d,n=charge(d,n)
    v,o=dvis(b,o); name,o=dident(b,o); ty,n,o=dty(d,n,b,o)
    return ("param",v,name,ty),n,o
def dparams(d,n,b,o):
    cnt,o=ru32(b,o)
    if cnt>n: raise E(COUNT)
    ps=[]
    for _ in range(cnt):
        p,n,o=dparam(d,n,b,o); ps.append(p)
    return tuple(ps),n,o
def dstmt(d,n,b,o):
    tag,o=dtag(b,o)
    sfc={"Stmt.Assign":2,"Stmt.Return":1,"Stmt.If":3,"Stmt.Let":3,"Stmt.Match":2,"Stmt.For":5,
         "Stmt.Assert":2,"Stmt.Revert":2,"Stmt.Emit":2,"Stmt.Call":1,"Stmt.Schedule":1}
    if tag not in sfc: raise E(f"unknown stmt tag '{tag}'")
    o=dfc(b,o,tag,sfc[tag]); d,n=charge(d,n)
    if tag=="Stmt.Assign":
        t,n,o=dplace(d,n,b,o); v,n,o=dexpr(d,n,b,o); return ("assign",t,v),n,o
    if tag=="Stmt.Return":
        m,o=take(b,o,1)
        if m[0]==0: v=None
        elif m[0]==1: v,n,o=dexpr(d,n,b,o)
        else: raise E("invalid option marker")
        return ("return",v),n,o
    if tag=="Stmt.If":
        c,n,o=dexpr(d,n,b,o); th,n,o=dblock(d,n,b,o); m,o=take(b,o,1)
        if m[0]==0: el=None
        elif m[0]==1: el,n,o=dblock(d,n,b,o)
        else: raise E("invalid option marker")
        return ("if",c,th,el),n,o
    raise E(f"unsupported stmt '{tag}'")
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
def head(exp,fc,fam,d,n,b,o):
    tag,o=dtag(b,o)
    if tag!=exp: raise E(f"unknown {fam} tag '{tag}'")
    o=dfc(b,o,tag,fc)
    d,n=charge(d,n)
    return d,n,o
def dconst(d,n,b,o):
    d,n,o=head("ConstDecl",3,"const-decl",d,n,b,o)
    name,o=dident(b,o); ty,n,o=dty(d,n,b,o); v,n,o=dexpr(d,n,b,o)
    return ("const",name,ty,v),n,o
def dinv(d,n,b,o):
    d,n,o=head("InvariantDecl",2,"invariant-decl",d,n,b,o)
    name,o=dident(b,o); p,n,o=dexpr(d,n,b,o)
    return ("inv",name,p),n,o
def dinit(d,n,b,o):
    d,n,o=head("InitDecl",2,"init-decl",d,n,b,o)
    ps,n,o=dparams(d,n,b,o); body,n,o=dblock(d,n,b,o)
    return ("init",ps,body),n,o
def dentry(d,n,b,o):
    d,n,o=head("EntryDecl",4,"entry-decl",d,n,b,o)
    name,o=dident(b,o); ps,n,o=dparams(d,n,b,o); ty,n,o=dty(d,n,b,o); body,n,o=dblock(d,n,b,o)
    return ("entry",name,ps,ty,body),n,o
def dview(d,n,b,o):
    d,n,o=head("ViewDecl",4,"view-decl",d,n,b,o)
    name,o=dident(b,o); ps,n,o=dparams(d,n,b,o); ty,n,o=dty(d,n,b,o); body,n,o=dblock(d,n,b,o)
    return ("view",name,ps,ty,body),n,o
def dfn(d,n,b,o):
    d,n,o=head("FnDecl",4,"fn-decl",d,n,b,o)
    name,o=dident(b,o); ps,n,o=dparams(d,n,b,o); ty,n,o=dty(d,n,b,o); body,n,o=dblock(d,n,b,o)
    return ("fn",name,ps,ty,body),n,o
DEC={"const":dconst,"inv":dinv,"init":dinit,"entry":dentry,"view":dview,"fn":dfn}
# values
L0=("elit",("int",0)); L1=("elit",("int",1)); L4096=("elit",("int",4096)); LT=("elit",("bool",True))
PN=("pname","count"); EPC=("eplace",PN); ELT=("ebin","lt",EPC,L4096)
P_START=("param","Public","start",("uint",64))
P_SECRET=("param","Private","secret",("field","bn254_fr"))
P_TO=("param","Public","to",("principal",))
P_AMOUNT=("param","Private","amount",("uint",64))
P_NOTE=("param","Commitment","note",("bytes",0))
P_X=("param","Public","x",("uint",64))
BLK_ASSIGN=("block",( ("assign",PN,L1), ))
BLK_RET_PLC=("block",( ("return",EPC), ))
BLK_RET_0=("block",( ("return",L0), ))
BLK_RET_NONE=("block",( ("return",None), ))
BLK_IF=("block",( ("if",LT,BLK_RET_NONE,None), ))
WANT={
  "const_max":("const","max",("uint",256),L4096),
  "invariant_bounded":("inv","bounded",ELT),
  "init_two_params":("init",(P_START,P_SECRET),BLK_ASSIGN),
  "entry_run":("entry","run",(P_TO,P_AMOUNT,P_NOTE),("uint",64),BLK_RET_PLC),
  "entry_swapped":("entry","run",(P_AMOUNT,P_TO,P_NOTE),("uint",64),BLK_RET_PLC),
  "view_get_empty":("view","get",(),("uint",64),BLK_RET_0),
  "fn_helper2":("fn","helper2",(P_X,),("unit",),BLK_IF),
}
KIND={"const_max":"const","invariant_bounded":"inv","init_two_params":"init",
      "entry_run":"entry","entry_swapped":"entry","view_get_empty":"view","fn_helper2":"fn"}
BUDGET={"const_max":(2,3),"invariant_bounded":(4,5),"init_two_params":(4,9),
        "entry_run":(5,12),"entry_swapped":(5,12),"view_get_empty":(4,5),"fn_helper2":(5,9)}
GOLD={
"const_max":bytes.fromhex("09000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"),
"invariant_bounded":bytes.fromhex("0d000000496e76617269616e744465636c020007000000626f756e6465640b000000457870722e42696e61727903000b00000042696e6172794f702e4c7400000a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e740c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"),
"init_two_params":bytes.fromhex("08000000496e69744465636c02000200000005000000506172616d0300110000005669736962696c6974792e5075626c6963000005000000737461727409000000547970652e55496e740100400005000000506172616d0300120000005669736962696c6974792e507269766174650000060000007365637265740a000000547970652e4669656c64010008000000626e3235345f667205000000426c6f636b0100010000000b00000053746d742e41737369676e02000a000000506c6163652e4e616d65010005000000636f756e740c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"),
"entry_run":bytes.fromhex("09000000456e7472794465636c04000300000072756e0300000005000000506172616d0300110000005669736962696c6974792e5075626c6963000002000000746f0e000000547970652e5072696e636970616c000005000000506172616d0300120000005669736962696c6974792e50726976617465000006000000616d6f756e7409000000547970652e55496e740100400005000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000040000006e6f74650a000000547970652e427974657301000000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e74"),
"entry_swapped":bytes.fromhex("09000000456e7472794465636c04000300000072756e0300000005000000506172616d0300120000005669736962696c6974792e50726976617465000006000000616d6f756e7409000000547970652e55496e740100400005000000506172616d0300110000005669736962696c6974792e5075626c6963000002000000746f0e000000547970652e5072696e636970616c000005000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000040000006e6f74650a000000547970652e427974657301000000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e74"),
"view_get_empty":bytes.fromhex("08000000566965774465636c0400030000006765740000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000"),
"fn_helper2":bytes.fromhex("06000000466e4465636c04000700000068656c706572320100000005000000506172616d0300110000005669736962696c6974792e5075626c69630000010000007809000000547970652e55496e740100400009000000547970652e556e6974000005000000426c6f636b0100010000000700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e01000000"),
}
# verify reencoder matches PA101
for k,w in WANT.items():
    got=ENC[KIND[k]](w)
    if got!=GOLD[k]: raise SystemExit(f"reenc mismatch {k}\n{got.hex()}\n{GOLD[k].hex()}")
P_START_B=eparam(P_START); TU64=ety(("uint",64)); TU256=ety(("uint",256)); TUNIT=ety(("unit",))
BLK_ASSIGN_B=eblock(BLK_ASSIGN); BLK_RET_0_B=eblock(BLK_RET_0)
def setfc(raw,fc):
    o=4+raw[0]; return raw[:o]+u16(fc)+raw[o+2:]
def bad(tag): return u32(len(tag))+tag.encode("ascii")
def mkhead(tag,fc): return u32(len(tag))+tag.encode("ascii")+u16(fc)
def ident0(): return u32(0)
def empty_blk(): return etag("Block",[u32(0)])
def expect(want,fn):
    try: fn(); raise SystemExit(f"unexpectedly ok want={want!r}")
    except E as e:
        if str(e)!=want: raise SystemExit(f"want {want!r} got {e!r}")
def self_check():
    npos=nfc=nb=0
    order=["const_max","invariant_bounded","init_two_params","entry_run","entry_swapped","view_get_empty","fn_helper2"]
    for name in order:
        d,n=BUDGET[name]; raw=GOLD[name]; want=WANT[name]; kind=KIND[name]
        v,nodes,o=DEC[kind](d,n,raw,0)
        if v!=want: raise SystemExit(f"value {name}: {v!r}")
        if nodes!=0: raise SystemExit(f"pos {name} nodes={nodes}")
        finish(raw,o)
        if ENC[kind](v)!=raw: raise SystemExit(f"reenc {name}")
        npos+=1
    if npos!=7: raise SystemExit(f"npos {npos}")
    if GOLD["entry_run"]==GOLD["entry_swapped"] or WANT["entry_run"]==WANT["entry_swapped"]:
        raise SystemExit("entry alias")
    # tag nonalias Entry vs View same fields control (not 8th positive)
    view_same=etag("ViewDecl",[eident("run"),earr([eparam(P_TO),eparam(P_AMOUNT),eparam(P_NOTE)]),TU64,eblock(BLK_RET_PLC)])
    if view_same==GOLD["entry_run"]: raise SystemExit("entry/view alias")
    fcs=[
      ("const",GOLD["const_max"],"ConstDecl",3),("inv",GOLD["invariant_bounded"],"InvariantDecl",2),
      ("init",GOLD["init_two_params"],"InitDecl",2),("entry",GOLD["entry_run"],"EntryDecl",4),
      ("view",GOLD["view_get_empty"],"ViewDecl",4),("fn",GOLD["fn_helper2"],"FnDecl",4),
    ]
    for kind,raw,tag,exp in fcs:
        for badfc in (exp-1,exp+1):
            expect(f"tag '{tag}' must declare {exp} fields",
                   lambda k=kind,r=raw,f=badfc: DEC[k](0,0,setfc(r,f),0)); nfc+=1
    if nfc!=12: raise SystemExit(f"nfc {nfc}")
    # 1-6 unknown
    for kind,tag,fam in [
        ("const","StateDecl","const-decl"),("inv","ConstDecl","invariant-decl"),
        ("init","EntryDecl","init-decl"),("entry","ViewDecl","entry-decl"),
        ("view","FnDecl","view-decl"),("fn","EntryDecl","fn-decl")]:
        expect(f"unknown {fam} tag '{tag}'", lambda k=kind,t=tag: DEC[k](0,0,bad(t),0)); nb+=1
    # 7-12 depth heads
    for kind,tag,fc in [("const","ConstDecl",3),("inv","InvariantDecl",2),("init","InitDecl",2),
                        ("entry","EntryDecl",4),("view","ViewDecl",4),("fn","FnDecl",4)]:
        expect(DEPTH, lambda k=kind,t=tag,f=fc: DEC[k](0,0,mkhead(t,f),0)); nb+=1
    # 13-18 node heads
    for kind,tag,fc in [("const","ConstDecl",3),("inv","InvariantDecl",2),("init","InitDecl",2),
                        ("entry","EntryDecl",4),("view","ViewDecl",4),("fn","FnDecl",4)]:
        expect(NODE, lambda k=kind,t=tag,f=fc: DEC[k](1,0,mkhead(t,f),0)); nb+=1
    # 19-22 const
    expect(ID_E, lambda: dconst(3,8,etag("ConstDecl",[ident0(),bad("BogusType"),bad("BogusValue")]),0)); nb+=1
    expect("unknown type tag 'BogusType'", lambda: dconst(3,8,etag("ConstDecl",[eident("max"),bad("BogusType"),bad("BogusValue")]),0)); nb+=1
    expect("unknown expr tag 'BogusValue'", lambda: dconst(3,8,etag("ConstDecl",[eident("max"),TU256,bad("BogusValue")]),0)); nb+=1
    expect(NODE, lambda: dconst(2,2,GOLD["const_max"],0)); nb+=1
    # 23-24 inv
    expect(ID_E, lambda: dinv(3,8,etag("InvariantDecl",[ident0(),bad("BogusPred")]),0)); nb+=1
    expect("unknown expr tag 'BogusPred'", lambda: dinv(3,8,etag("InvariantDecl",[eident("bounded"),bad("BogusPred")]),0)); nb+=1
    # 25-29 init
    expect(COUNT, lambda: dinit(2,2,etag("InitDecl",[u32(2),empty_blk()]),0)); nb+=1
    expect("unknown param tag 'BogusParam'", lambda: dinit(3,8,etag("InitDecl",[u32(1)+bad("BogusParam"),bad("BogusBody")]),0)); nb+=1
    expect(BLK_E, lambda: dinit(4,16,etag("InitDecl",[u32(1)+P_START_B,empty_blk()]),0)); nb+=1
    expect(NODE, lambda: dinit(3,3,GOLD["init_two_params"],0)); nb+=1
    expect(NODE, lambda: dinit(3,3,etag("InitDecl",[u32(1)+P_START_B,BLK_ASSIGN_B]),0)); nb+=1
    # 30-35 entry
    expect(ID_E, lambda: dentry(4,8,etag("EntryDecl",[ident0(),u32(0),bad("BogusResult"),bad("BogusBody")]),0)); nb+=1
    expect(COUNT, lambda: dentry(3,2,etag("EntryDecl",[eident("run"),u32(2),bad("BogusResult"),bad("BogusBody")]),0)); nb+=1
    expect("unknown param tag 'BogusParam'", lambda: dentry(4,8,etag("EntryDecl",[eident("run"),u32(1)+bad("BogusParam"),bad("BogusResult"),bad("BogusBody")]),0)); nb+=1
    expect("unknown type tag 'BogusResult'", lambda: dentry(4,8,etag("EntryDecl",[eident("run"),u32(0),bad("BogusResult"),bad("BogusBody")]),0)); nb+=1
    expect("unknown block tag 'BogusBody'", lambda: dentry(4,8,etag("EntryDecl",[eident("run"),u32(0),TU64,bad("BogusBody")]),0)); nb+=1
    expect(NODE, lambda: dentry(4,2,etag("EntryDecl",[eident("run"),u32(0),TU64,BLK_RET_0_B]),0)); nb+=1
    # 36-40 view
    expect(ID_E, lambda: dview(4,8,etag("ViewDecl",[ident0(),u32(0),bad("BogusResult"),bad("BogusBody")]),0)); nb+=1
    expect(COUNT, lambda: dview(3,2,etag("ViewDecl",[eident("get"),u32(2),bad("BogusResult"),bad("BogusBody")]),0)); nb+=1
    expect("unknown param tag 'BogusParam'", lambda: dview(4,8,etag("ViewDecl",[eident("get"),u32(1)+bad("BogusParam"),bad("BogusResult"),bad("BogusBody")]),0)); nb+=1
    expect(W_ERR, lambda: dview(4,8,etag("ViewDecl",[eident("get"),u32(0),etag("Type.UInt",[u16(24)]),bad("BogusBody")]),0)); nb+=1
    expect(BLK_E, lambda: dview(4,8,etag("ViewDecl",[eident("get"),u32(0),TU64,empty_blk()]),0)); nb+=1
    # 41-45 fn
    expect(ID_E, lambda: dfn(4,8,etag("FnDecl",[ident0(),u32(0),bad("BogusResult"),bad("BogusBody")]),0)); nb+=1
    expect(COUNT, lambda: dfn(3,2,etag("FnDecl",[eident("helper2"),u32(2),bad("BogusResult"),bad("BogusBody")]),0)); nb+=1
    expect(W_ERR, lambda: dfn(4,8,etag("FnDecl",[eident("helper2"),u32(0),etag("Type.UInt",[u16(24)]),bad("BogusBody")]),0)); nb+=1
    expect(BLK_E, lambda: dfn(4,8,etag("FnDecl",[eident("helper2"),u32(0),TUNIT,empty_blk()]),0)); nb+=1
    expect(DEPTH, lambda: dfn(4,9,GOLD["fn_helper2"],0)); nb+=1
    # 46 trail
    raw=GOLD["const_max"]+b"\x00"
    v,nodes,o=dconst(2,3,raw,0)
    if v!=WANT["const_max"] or o!=len(GOLD["const_max"]) or o==len(raw): raise SystemExit("trail")
    expect("trailing bytes", lambda: finish(raw,o))
    nb+=1
    if (npos,nfc,nb)!=(7,12,46): raise SystemExit(f"inventory {npos} {nfc} {nb}")
    print("reference_source_ast_spine_decl_decode_v1: ok 7 12 46")
if __name__=="__main__":
    if sys.argv[1:]!=["--self-check"]:
        print("usage: reference_source_ast_spine_decl_decode_v1.py --self-check", file=sys.stderr)
        raise SystemExit(2)
    self_check()

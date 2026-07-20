#!/usr/bin/env python3
"""Independent PA112 declaration decode oracle (stdlib only)."""
import sys, unicodedata
WERR="integer width must be one of 8,16,32,64,128,256"
QID_ERR="source qualified id must contain 2..256 components"
VER_ERR="extension version must use canonical exact SemVer"
DIG_ERR="extension digest must use canonical sha256 spelling"
DEPTH,NODE,COUNT="depth budget exhausted","node budget exhausted","array count exceeds caller limit"
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
def vis(v): return null(f"Visibility.{v}")
def tbool(): return null("Type.Bool")
def tunit(): return null("Type.Unit")
def tprin(): return null("Type.Principal")
def tuint(w):
    if w not in (8,16,32,64,128,256): raise E(WERR)
    return etag("Type.UInt",[u16(w)])
def tbytes(n): return etag("Type.Bytes",[u32(n)])
def topt(el): return etag("Type.Option",[el])
def tarr(el,n): return etag("Type.Array",[el,u32(n)])
def tmap(k,v): return etag("Type.Map",[k,v])
def eparam(v,n,t): return etag("Param",[vis(v),eident(n),t])
def efield(n,t): return etag("FieldDecl",[eident(n),t])
def evar(n,ts): return etag("EnumVariant",[eident(n),earr(ts)])
def eqid(ps):
    if not 2<=len(ps)<=256: raise E(QID_ERR)
    return earr([eident(p) for p in ps])
def _adig(c): return "0"<=c<="9"
def _aid(c): return _adig(c) or "a"<=c<="z" or "A"<=c<="Z" or c=="-"
def ok_ver(s):
    # Common splitOnce: '+' first, then '-' on the left; ASCII-only predicates
    if s.startswith("v"): raise E(VER_ERR)
    if "+" in s:
        main, build = s.split("+", 1)
        if not build: raise E(VER_ERR)
    else:
        main, build = s, None
    if "-" in main:
        core, pre = main.split("-", 1)
        if not pre: raise E(VER_ERR)
    else:
        core, pre = main, None
    nums = core.split(".")
    if len(nums) != 3: raise E(VER_ERR)
    u64m = "18446744073709551615"
    for n in nums:
        if not n or not all(_adig(c) for c in n) or (len(n) > 1 and n[0] == "0"): raise E(VER_ERR)
        if len(n) > 20 or (len(n) == 20 and n > u64m): raise E(VER_ERR)  # Common UInt64 max
    def ids(value, lead0):
        for i in value.split("."):
            if not i or not all(_aid(c) for c in i): raise E(VER_ERR)
            if not lead0 and all(_adig(c) for c in i) and len(i) > 1 and i[0] == "0": raise E(VER_ERR)
    if pre is not None: ids(pre, False)
    if build is not None: ids(build, True)
def ok_dig(s):
    if not (s.startswith("sha256:") and len(s)==71 and all(c in "0123456789abcdef" for c in s[7:])): raise E(DIG_ERR)
def estate(v,n,t): return etag("StateDecl",[vis(v),eident(n),t])
def estruct(n,fs):
    if not fs: raise E("struct fields must be nonempty")
    return etag("StructDecl",[eident(n),earr(fs)])
def eenum(n,vs):
    if not vs: raise E("enum variants must be nonempty")
    return etag("EnumDecl",[eident(n),earr(vs)])
def eevent(n,ps): return etag("EventDecl",[eident(n),earr(ps)])
def eerror(n,ps): return etag("ErrorDecl",[eident(n),earr(ps)])
def eext(i,v,d):
    ib=eqid(i); ok_ver(v); ok_dig(d); return etag("ExtensionReq",[ib,estr(v),estr(d)])
def eproof(inv,th): return etag("ProofDecl",[eident(inv),eqid(th)])
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
def head(b,o,exp,fam,fc):
    tag,o=dtag(b,o)
    if tag!=exp: raise E(f"unknown {fam} tag '{tag}'")
    return dfc(b,o,tag,fc)
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
def dstr(b,o):
    n,o=ru32(b,o)
    if len(b)-o<n: raise E("string length exceeds remaining")
    raw,o=take(b,o,n)
    try: s=raw.decode("utf-8")
    except UnicodeDecodeError: raise E("invalid UTF-8")
    if unicodedata.normalize("NFC",s)!=s: raise E("string must already be NFC under Unicode 17.0.0")
    return s,o
def dqid(b,o):
    n,o=ru32(b,o)
    if not 2<=n<=256: raise E(QID_ERR)
    ps=[]
    for _ in range(n):
        p,o=dident(b,o); ps.append(p)
    return tuple(ps),o
def dvis(b,o):
    tag,o=dtag(b,o); m={"Visibility.Public":"Public","Visibility.Private":"Private","Visibility.Commitment":"Commitment"}
    if tag not in m: raise E(f"unknown visibility tag '{tag}'")
    o=dfc(b,o,tag,0); return m[tag],o
def dtype(d,n,b,o):
    tag,o=dtag(b,o)
    fc={"Type.Bool":0,"Type.Principal":0,"Type.Unit":0,"Type.UInt":1,"Type.Int":1,"Type.Named":1,"Type.Bytes":1,"Type.Field":1,"Type.Option":1,"Type.Array":2,"Type.Map":2}
    if tag not in fc: raise E(f"unknown type tag '{tag}'")
    o=dfc(b,o,tag,fc[tag]); cd,n=charge(d,n)
    if tag=="Type.Bool": return ("bool",),n,o
    if tag=="Type.Principal": return ("principal",),n,o
    if tag=="Type.Unit": return ("unit",),n,o
    if tag in ("Type.UInt","Type.Int"):
        w,o=ru16(b,o)
        if w not in (8,16,32,64,128,256): raise E(WERR)
        return (tag.split(".")[1].lower(),w),n,o
    if tag=="Type.Named":
        x,o=dident(b,o); return ("named",x),n,o
    if tag=="Type.Bytes":
        x,o=ru32(b,o)
        if x>4096: raise E("bytes length must be 0..4096")
        return ("bytes",x),n,o
    if tag=="Type.Field":
        x,o=dident(b,o)
        if x!="bn254_fr": raise E("field id must be bn254_fr")
        return ("field",x),n,o
    if tag=="Type.Option":
        el,n,o=dtype(cd,n,b,o); return ("option",el),n,o
    if tag=="Type.Array":
        el,n,o=dtype(cd,n,b,o); x,o=ru32(b,o)
        if x>4096: raise E("array length must be 0..4096")
        return ("array",el,x),n,o
    k,n,o=dtype(cd,n,b,o); v,n,o=dtype(cd,n,b,o); return ("map",k,v),n,o
def dparam(d,n,b,o):
    o=head(b,o,"Param","param",3); cd,n=charge(d,n); v,o=dvis(b,o); nm,o=dident(b,o); t,n,o=dtype(cd,n,b,o); return ("param",v,nm,t),n,o
def dfield(d,n,b,o):
    o=head(b,o,"FieldDecl","field-decl",2); cd,n=charge(d,n); nm,o=dident(b,o); t,n,o=dtype(cd,n,b,o); return ("field",nm,t),n,o
def dvar(d,n,b,o):
    o=head(b,o,"EnumVariant","enum-variant",2); cd,n=charge(d,n); nm,o=dident(b,o); cnt,o=ru32(b,o)
    if cnt>n: raise E(COUNT)
    ts=[]
    for _ in range(cnt):
        t,n,o=dtype(cd,n,b,o); ts.append(t)
    return ("variant",nm,tuple(ts)),n,o
def darr(d,n,b,o,child,empty=None):
    cnt,o=ru32(b,o)
    if empty is not None and cnt==0: raise E(empty)
    if cnt>n: raise E(COUNT)
    out=[]
    for _ in range(cnt):
        x,n,o=child(d,n,b,o); out.append(x)
    return out,n,o
def dstate(d,n,b,o):
    o=head(b,o,"StateDecl","state-decl",3); cd,n=charge(d,n); v,o=dvis(b,o); nm,o=dident(b,o); t,n,o=dtype(cd,n,b,o); return ("state",v,nm,t),n,o
def dstruct(d,n,b,o):
    o=head(b,o,"StructDecl","struct-decl",2); cd,n=charge(d,n); nm,o=dident(b,o)
    fs,n,o=darr(cd,n,b,o,dfield,"struct fields must be nonempty"); return ("struct",nm,tuple(fs)),n,o
def denum(d,n,b,o):
    o=head(b,o,"EnumDecl","enum-decl",2); cd,n=charge(d,n); nm,o=dident(b,o)
    vs,n,o=darr(cd,n,b,o,dvar,"enum variants must be nonempty"); return ("enum",nm,tuple(vs)),n,o
def devent(d,n,b,o):
    o=head(b,o,"EventDecl","event-decl",2); cd,n=charge(d,n); nm,o=dident(b,o)
    ps,n,o=darr(cd,n,b,o,dparam); return ("event",nm,tuple(ps)),n,o
def derror(d,n,b,o):
    o=head(b,o,"ErrorDecl","error-decl",2); cd,n=charge(d,n); nm,o=dident(b,o)
    ps,n,o=darr(cd,n,b,o,dparam); return ("error",nm,tuple(ps)),n,o
def dext(d,n,b,o):
    o=head(b,o,"ExtensionReq","extension-req",3); _,n=charge(d,n)
    i,o=dqid(b,o); v,o=dstr(b,o); ok_ver(v); dg,o=dstr(b,o); ok_dig(dg); return ("ext",i,v,dg),n,o
def dproof(d,n,b,o):
    o=head(b,o,"ProofDecl","proof-decl",2); _,n=charge(d,n)
    inv,o=dident(b,o); th,o=dqid(b,o); return ("proof",inv,th),n,o
DIG00="sha256:"+"0"*64; DIGAB="sha256:"+"ab"*32
def ety(t):
    k=t[0]
    return {"bool":tbool,"unit":tunit,"principal":tprin}[k]() if k in ("bool","unit","principal") else \
        tuint(t[1]) if k=="uint" else tbytes(t[1]) if k=="bytes" else topt(ety(t[1])) if k=="option" else \
        tarr(ety(t[1]),t[2]) if k=="array" else tmap(ety(t[1]),ety(t[2]))
G=[
 ("state",estate("Public","enabled",tbool()),("state","Public","enabled",("bool",)),2),
 ("state",estate("Private","count",tuint(64)),("state","Private","count",("uint",64)),2),
 ("state",estate("Commitment","secret",tarr(topt(tbytes(0)),0)),("state","Commitment","secret",("array",("option",("bytes",0)),0)),4),
 ("struct",estruct("Store",[efield("count",tuint(256)),efield("items",tmap(tbool(),tunit()))]),
  ("struct","Store",( ("field","count",("uint",256)),("field","items",("map",("bool",),("unit",))) )),7),
 ("struct",estruct("Store",[efield("count",tuint(256))]),("struct","Store",( ("field","count",("uint",256)), )),3),
 ("struct",estruct("Store",[efield("items",tmap(tbool(),tunit())),efield("count",tuint(256))]),
  ("struct","Store",( ("field","items",("map",("bool",),("unit",))),("field","count",("uint",256)) )),7),
 ("enum",eenum("Choice",[evar("None",[]),evar("Some",[tbool(),tprin()])]),
  ("enum","Choice",( ("variant","None",()),("variant","Some",( ("bool",),("principal",) )) )),5),
 ("event",eevent("Ping",[]),("event","Ping",()),1),
 ("event",eevent("Transfer",[eparam("Public","from",tprin()),eparam("Private","amount",tuint(64)),eparam("Commitment","note",tbytes(0))]),
  ("event","Transfer",( ("param","Public","from",("principal",)),("param","Private","amount",("uint",64)),("param","Commitment","note",("bytes",0)) )),7),
 ("error",eerror("Empty",[]),("error","Empty",()),1),
 ("error",eerror("Denied",[eparam("Public","reason",tbool())]),("error","Denied",( ("param","Public","reason",("bool",)), )),3),
 ("ext",eext(["Demo","Feature"],"1.0.0",DIG00),("ext",("Demo","Feature"),"1.0.0",DIG00),1),
 ("ext",eext(["Demo","Advanced"],"1.2.3-alpha.1+build.5",DIGAB),("ext",("Demo","Advanced"),"1.2.3-alpha.1+build.5",DIGAB),1),
 ("proof",eproof("safe",["Proofs","safe"]),("proof","safe",("Proofs","safe")),1),
]
FIXED_HEX="0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000|0900000053746174654465636c0300120000005669736962696c6974792e50726976617465000005000000636f756e7409000000547970652e55496e7401004000|0900000053746174654465636c0300150000005669736962696c6974792e436f6d6d69746d656e740000060000007365637265740a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000|0a0000005374727563744465636c02000500000053746f726502000000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001090000004669656c644465636c0200050000006974656d7308000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000|0a0000005374727563744465636c02000500000053746f726501000000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001|0a0000005374727563744465636c02000500000053746f726502000000090000004669656c644465636c0200050000006974656d7308000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001|08000000456e756d4465636c02000600000043686f696365020000000b000000456e756d56617269616e740200040000004e6f6e65000000000b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000|090000004576656e744465636c02000400000050696e6700000000|090000004576656e744465636c0200080000005472616e736665720300000005000000506172616d0300110000005669736962696c6974792e5075626c696300000400000066726f6d0e000000547970652e5072696e636970616c000005000000506172616d0300120000005669736962696c6974792e50726976617465000006000000616d6f756e7409000000547970652e55496e740100400005000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000040000006e6f74650a000000547970652e4279746573010000000000|090000004572726f724465636c020005000000456d70747900000000|090000004572726f724465636c02000600000044656e6965640100000005000000506172616d0300110000005669736962696c6974792e5075626c6963000006000000726561736f6e09000000547970652e426f6f6c0000|0c000000457874656e73696f6e5265710300020000000400000044656d6f070000004665617475726505000000312e302e30470000007368613235363a30303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030|0c000000457874656e73696f6e5265710300020000000400000044656d6f08000000416476616e63656415000000312e322e332d616c7068612e312b6275696c642e35470000007368613235363a61626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162|0900000050726f6f664465636c02000400000073616665020000000600000050726f6f66730400000073616665".split("|")
DEC={"state":dstate,"struct":dstruct,"enum":denum,"event":devent,"error":derror,"ext":dext,"proof":dproof}
def reenc(v):
    k=v[0]
    if k=="state": return estate(v[1],v[2],ety(v[3]))
    if k=="struct": return estruct(v[1],[efield(f[1],ety(f[2])) for f in v[2]])
    if k=="enum": return eenum(v[1],[evar(x[1],[ety(t) for t in x[2]]) for x in v[2]])
    if k=="event": return eevent(v[1],[eparam(p[1],p[2],ety(p[3])) for p in v[2]])
    if k=="error": return eerror(v[1],[eparam(p[1],p[2],ety(p[3])) for p in v[2]])
    if k=="ext": return eext(list(v[1]),v[2],v[3])
    return eproof(v[1],list(v[2]))
def setfc(raw,fc):
    o=4+raw[0]; return raw[:o]+u16(fc)+raw[o+2:]
def nofc(raw): return raw[:4+raw[0]]
def expect(want,fn):
    try: fn(); raise SystemExit(f"unexpectedly ok want={want!r}")
    except E as e:
        if str(e)!=want: raise SystemExit(f"want {want!r} got {e!r}")
def self_check():
    npos=nfc=nb=0
    for i,(kind,raw,val,spent) in enumerate(G):
        if raw.hex()!=FIXED_HEX[i]: raise SystemExit(f"fixed wire {i}")
        v,nodes,o=DEC[kind](256,100,raw,0)
        if v!=val or nodes!=100-spent or o!=len(raw): raise SystemExit(f"pos {kind}")
        if reenc(v)!=raw: raise SystemExit(f"reenc {kind}")
        npos+=1
    for kind,raw,tag,exp,bads in [
        ("state",G[0][1],"StateDecl",3,(2,4)),("struct",G[4][1],"StructDecl",2,(1,3)),
        ("enum",G[6][1],"EnumDecl",2,(1,3)),("event",G[7][1],"EventDecl",2,(1,3)),
        ("error",G[9][1],"ErrorDecl",2,(1,3)),("ext",G[11][1],"ExtensionReq",3,(2,4)),
        ("proof",G[13][1],"ProofDecl",2,(1,3))]:
        for bad in bads:
            expect(f"tag '{tag}' must declare {exp} fields", lambda k=kind,r=raw,f=bad: DEC[k](0,0,setfc(r,f),0)); nfc+=1
    # seven distinct declaration sibling tags (not StateDecl reused)
    for kind,bad,fam in [
        ("state","StructDecl","state-decl"),("struct","EnumDecl","struct-decl"),
        ("enum","EventDecl","enum-decl"),("event","ErrorDecl","event-decl"),
        ("error","ExtensionReq","error-decl"),("ext","ProofDecl","extension-req"),
        ("proof","StateDecl","proof-decl")]:
        expect(f"unknown {fam} tag '{bad}'", lambda k=kind,t=bad: DEC[k](0,0,nofc(etag(t,[])),0)); nb+=1
    expect(DEPTH, lambda: dstate(0,0,G[0][1],0)); nb+=1
    for kind,raw in [("state",etag("StateDecl",[b"",b"",b""])),("struct",etag("StructDecl",[b"",b""])),
        ("enum",etag("EnumDecl",[b"",b""])),("event",etag("EventDecl",[b"",b""])),
        ("error",etag("ErrorDecl",[b"",b""])),("ext",etag("ExtensionReq",[b"",b"",b""])),
        ("proof",etag("ProofDecl",[b"",b""]))]:
        expect(NODE, lambda k=kind,r=raw: DEC[k](1,0,r,0)); nb+=1
    expect("unknown visibility tag 'Type.Bool'", lambda: dstate(3,8,etag("StateDecl",[tbool(),u32(0),etag("Bogus",[])]),0)); nb+=1
    expect("source name component must contain 1..240 UTF-8 bytes", lambda: dstate(3,8,etag("StateDecl",[vis("Public"),u32(0),etag("Bogus",[])]),0)); nb+=1
    badu=etag("Type.UInt",[u16(24)])
    expect(WERR, lambda: dstate(3,4,etag("StateDecl",[vis("Public"),eident("x"),badu]),0)); nb+=1
    expect("source name component must contain 1..240 UTF-8 bytes", lambda: dstruct(3,8,etag("StructDecl",[u32(0),u32(99)]),0)); nb+=1
    expect("struct fields must be nonempty", lambda: dstruct(2,4,etag("StructDecl",[eident("Store"),u32(0)]),0)); nb+=1
    expect(COUNT, lambda: dstruct(3,2,etag("StructDecl",[eident("Store"),earr([efield("a",tbool()),efield("b",tbool())])]),0)); nb+=1
    expect(WERR, lambda: dstruct(3,8,etag("StructDecl",[eident("Store"),earr([efield("c",badu)])]),0)); nb+=1
    expect(NODE, lambda: dstruct(4,4,etag("StructDecl",[eident("Store"),earr([efield("a",topt(tbool())),efield("b",tunit())])]),0)); nb+=1
    expect("source name component must contain 1..240 UTF-8 bytes", lambda: denum(3,8,etag("EnumDecl",[u32(0),u32(99)]),0)); nb+=1
    expect("enum variants must be nonempty", lambda: denum(2,4,etag("EnumDecl",[eident("Choice"),u32(0)]),0)); nb+=1
    expect(COUNT, lambda: denum(3,2,etag("EnumDecl",[eident("Choice"),earr([evar("A",[]),evar("B",[])])]),0)); nb+=1
    expect("unknown type tag 'Visibility.Public'", lambda: denum(3,8,etag("EnumDecl",[eident("Choice"),earr([evar("X",[nofc(vis("Public"))])])]),0)); nb+=1
    expect(NODE, lambda: denum(3,3,etag("EnumDecl",[eident("Choice"),earr([evar("A",[tbool()]),evar("B",[tunit()])])]),0)); nb+=1
    expect("source name component must contain 1..240 UTF-8 bytes", lambda: devent(3,8,etag("EventDecl",[u32(0),u32(99)]),0)); nb+=1
    expect(COUNT, lambda: devent(3,2,etag("EventDecl",[eident("Ping"),earr([eparam("Public","a",tbool()),eparam("Public","b",tunit())])]),0)); nb+=1
    expect("unknown visibility tag 'Type.Bool'", lambda: devent(3,8,etag("EventDecl",[eident("Ping"),earr([etag("Param",[tbool(),eident("x"),tunit()])])]),0)); nb+=1
    expect(NODE, lambda: devent(4,4,etag("EventDecl",[eident("Ping"),earr([eparam("Public","a",topt(tbool())),eparam("Public","b",tunit())])]),0)); nb+=1
    expect("source name component must contain 1..240 UTF-8 bytes", lambda: derror(3,8,etag("ErrorDecl",[u32(0),u32(99)]),0)); nb+=1
    expect(COUNT, lambda: derror(3,2,etag("ErrorDecl",[eident("Empty"),earr([eparam("Public","a",tbool()),eparam("Public","b",tunit())])]),0)); nb+=1
    expect("unknown visibility tag 'Type.Bool'", lambda: derror(3,8,etag("ErrorDecl",[eident("Empty"),earr([etag("Param",[tbool(),eident("x"),tunit()])])]),0)); nb+=1
    expect(NODE, lambda: derror(4,4,etag("ErrorDecl",[eident("Empty"),earr([eparam("Public","a",topt(tbool())),eparam("Public","b",tunit())])]),0)); nb+=1
    expect(QID_ERR, lambda: dext(2,4,etag("ExtensionReq",[earr([eident("Only")]),estr("not-a-semver"),estr("bad")]),0)); nb+=1
    expect(VER_ERR, lambda: dext(2,4,etag("ExtensionReq",[eqid(["Demo","Feature"]),estr("01.0.0"),estr("bad")]),0)); nb+=1
    expect(DIG_ERR, lambda: dext(2,4,etag("ExtensionReq",[eqid(["Demo","Feature"]),estr("1.0.0"),estr("sha256:ZZ")]),0)); nb+=1
    expect("source name component must contain 1..240 UTF-8 bytes", lambda: dproof(2,4,etag("ProofDecl",[u32(0),earr([eident("Only")])]),0)); nb+=1
    expect(QID_ERR, lambda: dproof(2,4,etag("ProofDecl",[eident("safe"),earr([eident("Only")])]),0)); nb+=1
    raw=G[0][1]+b"\x00"; v,nodes,o=dstate(3,4,raw,0)
    if v[0]!="state" or o!=len(G[0][1]) or nodes!=2 or o==len(raw): raise SystemExit("trail")
    nb+=1
    if (npos,nfc,nb)!=(14,14,42): raise SystemExit(f"inventory {npos} {nfc} {nb}")
    print("reference_source_ast_decl_decode_v1: ok 14 14 42")
if __name__=="__main__":
    if sys.argv[1:]!=["--self-check"]:
        print("usage: reference_source_ast_decl_decode_v1.py --self-check", file=sys.stderr); raise SystemExit(2)
    self_check()

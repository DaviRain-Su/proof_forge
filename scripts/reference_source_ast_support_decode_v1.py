#!/usr/bin/env python3
"""Independent D1-PA-111 support-record decoder oracle (no project imports)."""
import sys, unicodedata
def u16(n): return n.to_bytes(2,"little")
def u32(n): return n.to_bytes(4,"little")
def tag(t,fs): return u32(len(t))+t.encode()+u16(len(fs))+b"".join(fs)
def ident(s): return u32(len(s.encode()))+s.encode()
def typ(t,fs=[]): return tag("Type."+t,fs)
def param(v,n,t): return tag("Param",[tag("Visibility."+v,[]),ident(n),t])
def field(n,t): return tag("FieldDecl",[ident(n),t])
def variant(n,ts): return tag("EnumVariant",[ident(n),u32(len(ts))+b"".join(ts)])
B=typ("Bool"); U=typ("Unit"); P=typ("Principal")
G=[
("05000000506172616d0300110000005669736962696c6974792e5075626c69630000010000007809000000547970652e426f6f6c0000",("P","Public","x",("Bool",)),2),
("05000000506172616d0300120000005669736962696c6974792e507269766174650000010000007909000000547970652e556e69740000",("P","Private","y",("Unit",)),2),
("05000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000010000007a09000000547970652e55496e7401004000",("P","Commitment","z",("UInt",64)),2),
("05000000506172616d0300110000005669736962696c6974792e5075626c69630000030000006172720a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000",("P","Public","arr",("Array",("Option",("Bytes",0)),0)),4),
("05000000506172616d0300110000005669736962696c6974792e5075626c6963000007000000666f6f2d62617209000000547970652e426f6f6c0000",("P","Public","foo-bar",("Bool",)),2),
("090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001",("F","count",("UInt",256)),2),
("090000004669656c644465636c0200050000006974656d7308000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000",("F","items",("Map",("Bool",),("Unit",))),4),
("0b000000456e756d56617269616e740200040000004e6f6e6500000000",("V","None",()),1),
("0b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000",("V","Some",(("Bool",),("Principal",))),3),
("0b000000456e756d56617269616e7402000400000057726170010000000b000000547970652e4f7074696f6e010009000000547970652e556e69740000",("V","Wrap",(("Option",("Unit",)),)),3)]
def take(b,o,n):
 if len(b)-o<n: raise ValueError("truncated")
 return b[o:o+n],o+n
def num(b,o,n): d,o=take(b,o,n); return int.from_bytes(d,"little"),o
def dtag(b,o):
 n,o=num(b,o,4)
 if not 1<=n<=21: raise ValueError("tag length must be 1..21 bytes")
 d,o=take(b,o,n)
 try:s=d.decode()
 except UnicodeDecodeError: raise ValueError("invalid UTF-8 tag")
 if not s.isascii(): raise ValueError("tag must be ASCII")
 return s,o
def fc(t,n,b,o):
 x,o=num(b,o,2)
 if x!=n: raise ValueError(f"tag '{t}' must declare {n} fields")
 return o
def did(b,o):
 n,o=num(b,o,4)
 if not 1<=n<=240: raise ValueError("source name component must contain 1..240 UTF-8 bytes")
 if len(b)-o<n: raise ValueError("string length exceeds remaining")
 d,o=take(b,o,n)
 try:s=d.decode()
 except UnicodeDecodeError: raise ValueError("invalid UTF-8")
 if unicodedata.normalize("NFC",s)!=s: raise ValueError("string must already be NFC under Unicode 17.0.0")
 for c in s:
  if unicodedata.category(c)=="Cc": raise ValueError("source name component must not contain a Cc code point")
  if c=="»": raise ValueError("source name component must not contain closing guillemet")
 return s,o
TFC={"Type.Bool":0,"Type.Principal":0,"Type.Unit":0,"Type.UInt":1,"Type.Int":1,"Type.Named":1,"Type.Array":2,"Type.Map":2,"Type.Option":1,"Type.Bytes":1,"Type.Field":1}
def dtype(d,n,b,o):
 t,o=dtag(b,o)
 if t not in TFC: raise ValueError(f"unknown type tag '{t}'")
 o=fc(t,TFC[t],b,o)
 if d<1: raise ValueError("depth budget exhausted")
 if n<1: raise ValueError("node budget exhausted")
 n-=1; k=t[5:]
 if k in ("Bool","Principal","Unit"): return (k,),n,o
 if k in ("UInt","Int"):
  w,o=num(b,o,2)
  if w not in (8,16,32,64,128,256): raise ValueError("integer width must be one of 8,16,32,64,128,256")
  return (k,w),n,o
 if k in ("Named","Field"):
  x,o=did(b,o)
  if k=="Field" and x!="bn254_fr": raise ValueError("field id must be bn254_fr")
  return (k,x),n,o
 if k=="Bytes":
  x,o=num(b,o,4)
  if x>4096: raise ValueError("bytes length must be 0..4096")
  return (k,x),n,o
 a,n,o=dtype(d-1,n,b,o)
 if k=="Option": return (k,a),n,o
 if k=="Array":
  x,o=num(b,o,4)
  if x>4096: raise ValueError("array length must be 0..4096")
  return (k,a,x),n,o
 z,n,o=dtype(d-1,n,b,o); return (k,a,z),n,o
def vis(b,o):
 t,o=dtag(b,o)
 vs={"Visibility.Public":"Public","Visibility.Private":"Private","Visibility.Commitment":"Commitment"}
 if t not in vs: raise ValueError(f"unknown visibility tag '{t}'")
 o=fc(t,0,b,o); return vs[t],o
def dec(kind,d,n,b,o=0):
 t,o=dtag(b,o); names={"P":("Param",3),"F":("FieldDecl",2),"V":("EnumVariant",2)}; want,c=names[kind]
 if t!=want: raise ValueError(f"unknown {'param' if kind=='P' else 'field-decl' if kind=='F' else 'enum-variant'} tag '{t}'")
 o=fc(t,c,b,o)
 if d<1: raise ValueError("depth budget exhausted")
 if n<1: raise ValueError("node budget exhausted")
 n-=1
 if kind=="P": v,o=vis(b,o); x,o=did(b,o); y,n,o=dtype(d-1,n,b,o); return ("P",v,x,y),n,o
 x,o=did(b,o)
 if kind=="F": y,n,o=dtype(d-1,n,b,o); return ("F",x,y),n,o
 c,o=num(b,o,4)
 if c>n: raise ValueError("array count exceeds caller limit")
 ys=[]
 for _ in range(c): y,n,o=dtype(d-1,n,b,o); ys.append(y)
 return ("V",x,tuple(ys)),n,o
def enc(v):
 def et(x):
  k=x[0]
  if k in ("Bool","Unit","Principal"): return typ(k)
  if k in ("UInt","Int"): return typ(k,[u16(x[1])])
  if k in ("Bytes",): return typ(k,[u32(x[1])])
  if k=="Option": return typ(k,[et(x[1])])
  if k=="Array": return typ(k,[et(x[1]),u32(x[2])])
  if k=="Map": return typ(k,[et(x[1]),et(x[2])])
  return typ(k,[ident(x[1])])
 return param(v[1],v[2],et(v[3])) if v[0]=="P" else field(v[1],et(v[2])) if v[0]=="F" else variant(v[1],[et(x) for x in v[2]])
def err(w,fn):
 try:fn()
 except ValueError as e:
  if str(e)!=w: raise SystemExit(f"want {w!r}, got {str(e)!r}")
  return
 raise SystemExit(f"want {w!r}: unexpectedly ok")
def self_check():
 for i,(h,v,s) in enumerate(G):
  k="P" if i<5 else "F" if i<7 else "V"; raw=bytes.fromhex(h); got,r,o=dec(k,256,100,raw)
  if got!=v or enc(got)!=raw or o!=len(raw) or r!=100-s: raise SystemExit("positive mismatch")
 nf=0
 for i,k,c,bads in [(0,"P",3,(2,4)),(5,"F",2,(1,3)),(7,"V",2,(1,3))]:
  raw=bytes.fromhex(G[i][0]); off=4+raw[0]
  for x in bads: err(f"tag '{('Param','FieldDecl','EnumVariant')['PFV'.index(k)]}' must declare {c} fields",lambda x=x:dec(k,0,0,raw[:off]+u16(x)+raw[off+2:])); nf+=1
 nb=0
 def E(w,f):
  nonlocal nb; err(w,f); nb+=1
 wrong=tag("FieldDecl",[])[:-2]
 for k,fam in (("P","param"),("F","field-decl"),("V","enum-variant")): E(f"unknown {fam} tag 'FieldDecl'" if k!="F" else "unknown field-decl tag 'Param'",lambda k=k:dec(k,0,0,wrong if k!="F" else tag("Param",[])[:-2]))
 raw=[bytes.fromhex(G[i][0]) for i in (0,5,7)]
 E("depth budget exhausted",lambda:dec("P",0,0,raw[0])); E("node budget exhausted",lambda:dec("P",1,0,raw[0][:11]))
 E("node budget exhausted",lambda:dec("F",1,0,raw[1][:15])); E("node budget exhausted",lambda:dec("V",1,0,raw[2][:17]))
 badid=u32(0); vh=tag("Visibility.Public",[])
 E("unknown visibility tag 'Type.Bool'",lambda:dec("P",2,5,tag("Param",[B,badid,B])))
 E("source name component must contain 1..240 UTF-8 bytes",lambda:dec("P",2,5,tag("Param",[vh,badid,tag("Bogus",[])])))
 E("source name component must contain 1..240 UTF-8 bytes",lambda:dec("F",2,5,tag("FieldDecl",[badid,tag("Bogus",[])])))
 E("source name component must contain 1..240 UTF-8 bytes",lambda:dec("V",2,5,tag("EnumVariant",[badid,u32(99)])))
 E("array count exceeds caller limit",lambda:dec("V",2,1,variant("X",[B])))
 got,r,o=dec("V",1,1,bytes.fromhex(G[7][0]))
 if got[2]!=() or r!=0 or o!=len(bytes.fromhex(G[7][0])): raise SystemExit("empty payload mismatch")
 nb+=1
 E("node budget exhausted",lambda:dec("V",3,3,variant("X",[typ("Option",[B]),U])))
 ordered=variant("X",[B,U]); got,r,o=dec("V",2,3,ordered)
 if got[2]!=(("Bool",),("Unit",)) or r!=0 or o!=len(ordered): raise SystemExit("source order mismatch")
 nb+=1
 E("integer width must be one of 8,16,32,64,128,256",lambda:dec("P",2,3,param("Public","x",typ("UInt",[u16(24)]))))
 E("unknown type tag 'Visibility.Public'",lambda:dec("F",2,3,field("x",vh[:-2])))
 E("depth budget exhausted",lambda:dec("P",1,5,param("Public","x",B)))
 E("depth budget exhausted",lambda:dec("V",1,3,variant("X",[B])))
 deep=B
 for _ in range(255): deep=typ("Option",[deep])
 deep_field=field("x",deep); got,r,o=dec("F",257,257,deep_field)
 if r!=0 or o!=len(deep_field): raise SystemExit("deep exact boundary mismatch")
 nb+=1
 E("depth budget exhausted",lambda:dec("F",256,257,field("x",deep)))
 E("node budget exhausted",lambda:dec("F",257,256,field("x",deep)))
 rr=bytes.fromhex(G[0][0])+b"\0"; got,r,o=dec("P",3,5,rr); E("trailing bytes",lambda: (_ for _ in ()).throw(ValueError("trailing bytes")) if o!=len(rr) else None)
 if (len(G),nf,nb)!=(10,6,23): raise SystemExit(f"inventory drift {len(G)} {nf} {nb}")
 print("reference_source_ast_support_decode_v1: ok 10 6 23")
if __name__=="__main__":
 if sys.argv[1:] != ["--self-check"]:
  print("usage: reference_source_ast_support_decode_v1.py --self-check", file=sys.stderr)
  raise SystemExit(2)
 self_check()

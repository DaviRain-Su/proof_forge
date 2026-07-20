import ProofForgeV2.Source.AstSupportCodecV1
import ProofForgeV2.Source.AstSupportDecodeV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceAstSupportDecodeV1
open ProofForgeV2.Source.AstSupportCodecV1
open ProofForgeV2.Source.AstSupportDecodeV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireDecodeV1

private def expect (c : Bool) (m : String) : IO Unit := unless c do throw <| IO.userError m
private def lift (lab : String) (r : Except String α) : IO α :=
  match r with | .ok v => pure v | .error e => throw <| IO.userError s!"{lab}: {e}"
private def err (lab want : String) (r : Except String α) : IO Unit :=
  match r with
  | .error e => expect (e == want) s!"{lab}: want {want}, got {e}"
  | .ok _ => throw <| IO.userError s!"{lab}: unexpectedly ok"
private def hv (c : Char) : Nat := if c ≤ '9' then c.toNat-'0'.toNat else c.toNat-'a'.toNat+10
private def hex (s : String) : ByteArray := Id.run do
  let cs := s.toList.toArray; let mut b := ByteArray.empty; let mut i := 0
  while i+1 < cs.size do b := b.push (UInt8.ofNat (hv cs[i]!*16+hv cs[i+1]!)); i := i+2
  pure b
private def hx (b : ByteArray) : String := b.foldl (fun s x =>
  let d (n : Nat) := Char.ofNat (if n<10 then '0'.toNat+n else 'a'.toNat+n-10)
  (s.push (d (x.toNat/16))).push (d (x.toNat%16))) ""
private def u16 (n : Nat) := ByteArray.mk #[UInt8.ofNat n, UInt8.ofNat (n/256)]
private def u32 (n : Nat) := ByteArray.mk #[UInt8.ofNat n, UInt8.ofNat (n/256), UInt8.ofNat (n/65536), UInt8.ofNat (n/16777216)]
private def str (s : String) := u32 s.utf8ByteSize ++ s.toUTF8
private def tg (s : String) (fs : Array ByteArray) := str s ++ u16 fs.size ++ fs.foldl (·++·) ByteArray.empty
private def ident := str
private def ty (s : String) (fs := #[]) := tg ("Type."++s) fs
private def vis (s : String) := tg ("Visibility."++s) #[]
private def pw (v n : String) (t : ByteArray) := tg "Param" #[vis v, ident n, t]
private def fw (n : String) (t : ByteArray) := tg "FieldDecl" #[ident n, t]
private def vw (n : String) (ts : Array ByteArray) := tg "EnumVariant" #[ident n, u32 ts.size ++ ts.foldl (·++·) ByteArray.empty]
private def bud (n : Nat) : DecodeBudgetV1 := { remainingNodes := n }
private def setFc (b : ByteArray) (n : Nat) : ByteArray :=
  let o := 4+(b.get! 0).toNat; (b.set! o (UInt8.ofNat n)).set! (o+1) (UInt8.ofNat (n/256))
private def noFc (b : ByteArray) := b.extract 0 (b.size-2)
private def nm (s : String) : IO SourceNameComponentV1 := lift "name" (parseSourceNameComponentV1 s)
private def dp (d n : Nat) (b : ByteArray) := decodeParamV1 d (bud n) (start b)
private def df (d n : Nat) (b : ByteArray) := decodeFieldDeclV1 d (bud n) (start b)
private def dv (d n : Nat) (b : ByteArray) := decodeEnumVariantV1 d (bud n) (start b)
private def rtP (h : String) (w : ParamV1) (spent : Nat) : IO Unit := do
  let ((g,r),c) ← lift "param" (dp 256 100 (hex h)); expect (g==w && r.remainingNodes==100-spent) "param value/nodes"
  lift "param finish" (finish c); expect (hx (← lift "param encode" (encodeParamV1 g))==h) "param wire"
private def rtF (h : String) (w : FieldDeclV1) (spent : Nat) : IO Unit := do
  let ((g,r),c) ← lift "field" (df 256 100 (hex h)); expect (g==w && r.remainingNodes==100-spent) "field value/nodes"
  lift "field finish" (finish c); expect (hx (← lift "field encode" (encodeFieldDeclV1 g))==h) "field wire"
private def rtV (h : String) (w : EnumVariantV1) (spent : Nat) : IO Unit := do
  let ((g,r),c) ← lift "variant" (dv 256 100 (hex h)); expect (g==w && r.remainingNodes==100-spent) "variant value/nodes"
  lift "variant finish" (finish c); expect (hx (← lift "variant encode" (encodeEnumVariantV1 g))==h) "variant wire"
private def optN : Nat → ByteArray → ByteArray | 0,b => b | n+1,b => ty "Option" #[optN n b]

/-- Frozen D1-PA-111: ten PA96 literals, six field counts, and 26 boundaries. -/
def run : IO Unit := do
  let x←nm "x"; let y←nm "y"; let z←nm "z"; let arr←nm "arr"; let fb←nm "foo-bar"
  let count←nm "count"; let items←nm "items"; let none←nm "None"; let some←nm "Some"; let wrap←nm "Wrap"
  let hp := "05000000506172616d0300110000005669736962696c6974792e5075626c69630000010000007809000000547970652e426f6f6c0000"
  let hf := "090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001"
  let hv0 := "0b000000456e756d56617269616e740200040000004e6f6e6500000000"
  rtP hp {visibility:=.public_,name:=x,type_:=.bool} 2
  rtP "05000000506172616d0300120000005669736962696c6974792e507269766174650000010000007909000000547970652e556e69740000" {visibility:=.private_,name:=y,type_:=.unit} 2
  rtP "05000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000010000007a09000000547970652e55496e7401004000" {visibility:=.commitment,name:=z,type_:=.uint 64} 2
  rtP "05000000506172616d0300110000005669736962696c6974792e5075626c69630000030000006172720a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000" {visibility:=.public_,name:=arr,type_:=.array (.option (.bytes 0)) 0} 4
  rtP "05000000506172616d0300110000005669736962696c6974792e5075626c6963000007000000666f6f2d62617209000000547970652e426f6f6c0000" {visibility:=.public_,name:=fb,type_:=.bool} 2
  rtF hf {name:=count,type_:=.uint 256} 2
  rtF "090000004669656c644465636c0200050000006974656d7308000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000" {name:=items,type_:=.map .bool .unit} 4
  rtV hv0 {name:=none,payloadTypes:=#[]} 1
  rtV "0b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000" {name:=some,payloadTypes:=#[.bool,.principal]} 3
  rtV "0b000000456e756d56617269616e7402000400000057726170010000000b000000547970652e4f7074696f6e010009000000547970652e556e69740000" {name:=wrap,payloadTypes:=#[.option .unit]} 3
  for (raw,k,w,bads) in [(hex hp,0,3,[2,4]),(hex hf,1,2,[1,3]),(hex hv0,2,2,[1,3])] do
    for bad in bads do
      let msg := s!"tag '{if k=0 then "Param" else if k=1 then "FieldDecl" else "EnumVariant"}' must declare {w} fields"
      if k=0 then err "fc" msg (dp 0 0 (setFc raw bad)) else if k=1 then err "fc" msg (df 0 0 (setFc raw bad)) else err "fc" msg (dv 0 0 (setFc raw bad))
  -- wrong-family without fieldCount beats zero budgets; wrong count likewise beats budgets
  err "wp" "unknown param tag 'FieldDecl'" (dp 0 0 (noFc (tg "FieldDecl" #[])))
  err "wf" "unknown field-decl tag 'Param'" (df 0 0 (noFc (tg "Param" #[])))
  err "wv" "unknown enum-variant tag 'FieldDecl'" (dv 0 0 (noFc (tg "FieldDecl" #[])))
  err "depth-node" "depth budget exhausted" (dp 0 0 (hex hp))
  -- record node charge precedes malformed first field for every API
  err "pn" "node budget exhausted" (dp 1 0 (tg "Param" #[ByteArray.empty,ByteArray.empty,ByteArray.empty]))
  err "fn" "node budget exhausted" (df 1 0 (tg "FieldDecl" #[ByteArray.empty,ByteArray.empty]))
  err "vn" "node budget exhausted" (dv 1 0 (tg "EnumVariant" #[ByteArray.empty,ByteArray.empty]))
  -- ordered primitive fields and exact child errors are not remapped
  err "vis-first" "unknown visibility tag 'Type.Bool'" (dp 2 5 (tg "Param" #[ty "Bool",u32 0,tg "Bogus" #[]]))
  err "p-name" "source name component must contain 1..240 UTF-8 bytes" (dp 2 5 (tg "Param" #[vis "Public",u32 0,tg "Bogus" #[]]))
  err "f-name" "source name component must contain 1..240 UTF-8 bytes" (df 2 5 (tg "FieldDecl" #[u32 0,tg "Bogus" #[]]))
  err "v-name" "source name component must contain 1..240 UTF-8 bytes" (dv 2 5 (tg "EnumVariant" #[u32 0,u32 99]))
  err "p-type" "integer width must be one of 8,16,32,64,128,256" (dp 2 3 (pw "Public" "x" (ty "UInt" #[u16 24])))
  err "f-type" "unknown type tag 'Visibility.Public'" (df 2 3 (fw "x" (noFc (vis "Public"))))
  err "v-type" "unknown type tag 'Visibility.Public'" (dv 2 3 (vw "X" #[noFc (vis "Public")]))
  -- count uses post-record residual; empty is valid; siblings retain source order/residual
  err "count" "array count exceeds caller limit" (dv 2 1 (vw "X" #[ty "Bool"]))
  let ((ev,er),ec)←lift "empty" (dv 1 1 (hex hv0)); expect (ev.payloadTypes.isEmpty && er.remainingNodes=0) "empty"; lift "empty-f" (finish ec)
  err "sibling" "node budget exhausted" (dv 3 3 (vw "X" #[ty "Option" #[ty "Bool"],ty "Unit"]))
  let ((ord,rr),oc)←lift "order" (dv 2 3 (vw "X" #[ty "Bool",ty "Unit"])); expect (ord.payloadTypes=#[.bool,.unit] && rr.remainingNodes=0) "order"; lift "order-f" (finish oc)
  err "child-depth" "depth budget exhausted" (dp 1 5 (pw "Public" "x" (ty "Bool")))
  err "variant-depth" "depth budget exhausted" (dv 1 3 (vw "X" #[ty "Bool"]))
  let deep := optN 255 (ty "Bool"); let ((_,dr),dc)←lift "deep" (df 257 257 (fw "x" deep)); expect (dr.remainingNodes=0) "deep nodes"; lift "deep-f" (finish dc)
  err "deep-depth" "depth budget exhausted" (df 256 257 (fw "x" deep))
  err "deep-node" "node budget exhausted" (df 257 256 (fw "x" deep))
  err "trailing" "trailing bytes" (do let ((_,_),c)←dp 2 2 (hex (hp++"00")); finish c)

end Tests.Language.SourceAstSupportDecodeV1

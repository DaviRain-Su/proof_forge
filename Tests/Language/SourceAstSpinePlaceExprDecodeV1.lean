import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstSpineCodecV1
import ProofForgeV2.Source.AstSpineDecodeV1
import ProofForgeV2.Source.AstSpineEqV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireCodecV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceAstSpinePlaceExprDecodeV1

set_option maxRecDepth 4096

open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstSpineCodecV1
open ProofForgeV2.Source.AstSpineDecodeV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireCodecV1
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
  let cs:=s.toList.toArray; let mut b:=ByteArray.empty; let mut i:=0
  while i+1<cs.size do
    b:=b.push (UInt8.ofNat (hv cs[i]!*16+hv cs[i+1]!))
    i:=i+2
  pure b
private def hx (b : ByteArray) : String := b.foldl (fun s x =>
  let d (n:Nat):=Char.ofNat (if n<10 then '0'.toNat+n else 'a'.toNat+n-10)
  (s.push (d (x.toNat/16))).push (d (x.toNat%16))) ""
private def u16 (n:Nat):=ByteArray.mk #[UInt8.ofNat n, UInt8.ofNat (n/256)]
private def u32 (n:Nat):=ByteArray.mk #[UInt8.ofNat n,UInt8.ofNat (n/256),UInt8.ofNat (n/65536),UInt8.ofNat (n/16777216)]
private def sbytes (s:String):=u32 s.utf8ByteSize ++ s.toUTF8
private def tg (s:String) (fs:Array ByteArray):=sbytes s ++ u16 fs.size ++ fs.foldl (·++·) ByteArray.empty
private def mkTag (s:String):=sbytes s
private def noFc (b:ByteArray):=b.extract 0 (4+(b.get! 0).toNat)
private def setFc (b:ByteArray) (n:Nat):ByteArray :=
  let o:=4+(b.get! 0).toNat; (b.set! o (UInt8.ofNat n)).set! (o+1) (UInt8.ofNat (n/256))
private def bud (n:Nat):DecodeBudgetV1:={remainingNodes:=n}
private def nm (s:String):IO SourceNameComponentV1:=lift "n" (parseSourceNameComponentV1 s)
private def qn (ps:Array String):IO SourceQualifiedNameV1:=lift "q" (parseSourceQualifiedNameV1 ps)
private def dP (d n:Nat) (b:ByteArray):=decodePlaceV1 d (bud n) (start b)
private def dE (d n:Nat) (b:ByteArray):=decodeExprV1 d (bud n) (start b)
private def dA (d n:Nat) (b:ByteArray):=decodeExprMatchArmV1 d (bud n) (start b)
private def dX (d n:Nat) (b:ByteArray):=decodeExternalCallExprV1 d (bud n) (start b)
private def litI (n:Nat):ExprV1:=.literal (.integer n)
private def litB (b:Bool):ExprV1:=.literal (.bool b)
private def wrapUn (n:Nat) (e:ExprV1):ExprV1 := match n with | 0 => e | k+1 => .unary .neg (wrapUn k e)

/-- Frozen D1-PA-113: 15 positives, 24 FC, 41 boundaries. -/
def run : IO Unit := do
  let x←nm "x"; let s←nm "s"; let total←nm "total"; let arr←nm "arr"; let helper←nm "helper"
  let optSome←qn #["Option","some"]; let optNone←qn #["Option","none"]; let mathAdd←qn #["Math","add"]
  let L0:ExprV1:=litI 0; let L1:ExprV1:=litI 1; let L2:ExprV1:=litI 2; let L2_64:ExprV1:=litI (2^64)
  let LT:ExprV1:=litB true
  let pName:PlaceV1:=.name x
  let pField:PlaceV1:=.field (.name s) total
  let pIndex:PlaceV1:=.index (.name arr) L1
  let ePlace:ExprV1:=.place pName
  let eCtorSome:ExprV1:=.constructor optSome #[LT]
  let eCtorNone:ExprV1:=.constructor optNone #[]
  let eCtor12:ExprV1:=.constructor optSome #[L1,L2]
  let eCtor21:ExprV1:=.constructor optSome #[L2,L1]
  let eNeg:ExprV1:=.unary .neg L1
  let eAdd:ExprV1:=.binary .add L1 L2
  let eLocal:ExprV1:=.localCall helper #[L1]
  let eArmB:ExprMatchArmV1:={pattern:=.bind x, value:=L1}
  let eArmW:ExprMatchArmV1:={pattern:=.wildcard, value:=L2}
  let eMatch:ExprV1:=.match_ L1 #[eArmB,eArmW]
  let ext0:ExternalCallExprV1:={callee:=mathAdd, args:=#[]}
  let ext2:ExternalCallExprV1:={callee:=mathAdd, args:=#[L1,L2]}
  -- 15 positives

  let ((g,r),c)←lift "place_name" (dP 256 100 (hex "0a000000506c6163652e4e616d6501000100000078"))
  expect (decide (g = pName) && r.remainingNodes == 100 - 1) "place_name"
  lift "place_namef" (finish c); expect (hx (← lift "place_namee" (encodePlaceV1 g)) == "0a000000506c6163652e4e616d6501000100000078") "place_name wire"
  let ((g,r),c)←lift "place_field" (dP 256 100 (hex "0b000000506c6163652e4669656c6402000a000000506c6163652e4e616d650100010000007305000000746f74616c"))
  expect (decide (g = pField) && r.remainingNodes == 100 - 2) "place_field"
  lift "place_fieldf" (finish c); expect (hx (← lift "place_fielde" (encodePlaceV1 g)) == "0b000000506c6163652e4669656c6402000a000000506c6163652e4e616d650100010000007305000000746f74616c") "place_field wire"
  let ((g,r),c)←lift "place_index" (dP 256 100 (hex "0b000000506c6163652e496e64657802000a000000506c6163652e4e616d650100030000006172720c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = pIndex) && r.remainingNodes == 100 - 3) "place_index"
  lift "place_indexf" (finish c); expect (hx (← lift "place_indexe" (encodePlaceV1 g)) == "0b000000506c6163652e496e64657802000a000000506c6163652e4e616d650100030000006172720c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "place_index wire"
  let ((g,r),c)←lift "expr_lit_2_64" (dE 256 100 (hex "0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000010000000000000000000000000000000000000000000000"))
  expect (decide (g = L2_64) && r.remainingNodes == 100 - 1) "expr_lit_2_64"
  lift "expr_lit_2_64f" (finish c); expect (hx (← lift "expr_lit_2_64e" (encodeExprV1 g)) == "0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000010000000000000000000000000000000000000000000000") "expr_lit_2_64 wire"
  let ((g,r),c)←lift "expr_place" (dE 256 100 (hex "0a000000457870722e506c61636501000a000000506c6163652e4e616d6501000100000078"))
  expect (decide (g = ePlace) && r.remainingNodes == 100 - 2) "expr_place"
  lift "expr_placef" (finish c); expect (hx (← lift "expr_placee" (encodeExprV1 g)) == "0a000000457870722e506c61636501000a000000506c6163652e4e616d6501000100000078") "expr_place wire"
  let ((g,r),c)←lift "expr_ctor_some" (dE 256 100 (hex "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d65010000000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001"))
  expect (decide (g = eCtorSome) && r.remainingNodes == 100 - 2) "expr_ctor_some"
  lift "expr_ctor_somef" (finish c); expect (hx (← lift "expr_ctor_somee" (encodeExprV1 g)) == "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d65010000000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001") "expr_ctor_some wire"
  let ((g,r),c)←lift "expr_ctor_none" (dE 256 100 (hex "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e040000006e6f6e6500000000"))
  expect (decide (g = eCtorNone) && r.remainingNodes == 100 - 1) "expr_ctor_none"
  lift "expr_ctor_nonef" (finish c); expect (hx (← lift "expr_ctor_nonee" (encodeExprV1 g)) == "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e040000006e6f6e6500000000") "expr_ctor_none wire"
  let ((g,r),c)←lift "nonalias_ctor_12" (dE 256 100 (hex "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d65020000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = eCtor12) && r.remainingNodes == 100 - 3) "nonalias_ctor_12"
  lift "nonalias_ctor_12f" (finish c); expect (hx (← lift "nonalias_ctor_12e" (encodeExprV1 g)) == "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d65020000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000") "nonalias_ctor_12 wire"
  let ((g,r),c)←lift "nonalias_ctor_21" (dE 256 100 (hex "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d65020000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010002000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = eCtor21) && r.remainingNodes == 100 - 3) "nonalias_ctor_21"
  lift "nonalias_ctor_21f" (finish c); expect (hx (← lift "nonalias_ctor_21e" (encodeExprV1 g)) == "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d65020000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010002000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "nonalias_ctor_21 wire"
  let ((g,r),c)←lift "expr_unary" (dE 256 100 (hex "0a000000457870722e556e61727902000b000000556e6172794f702e4e656700000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = eNeg) && r.remainingNodes == 100 - 2) "expr_unary"
  lift "expr_unaryf" (finish c); expect (hx (← lift "expr_unarye" (encodeExprV1 g)) == "0a000000457870722e556e61727902000b000000556e6172794f702e4e656700000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "expr_unary wire"
  let ((g,r),c)←lift "expr_binary" (dE 256 100 (hex "0b000000457870722e42696e61727903000c00000042696e6172794f702e41646400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = eAdd) && r.remainingNodes == 100 - 3) "expr_binary"
  lift "expr_binaryf" (finish c); expect (hx (← lift "expr_binarye" (encodeExprV1 g)) == "0b000000457870722e42696e61727903000c00000042696e6172794f702e41646400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000") "expr_binary wire"
  let ((g,r),c)←lift "expr_local" (dE 256 100 (hex "0e000000457870722e4c6f63616c43616c6c02000600000068656c706572010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = eLocal) && r.remainingNodes == 100 - 2) "expr_local"
  lift "expr_localf" (finish c); expect (hx (← lift "expr_locale" (encodeExprV1 g)) == "0e000000457870722e4c6f63616c43616c6c02000600000068656c706572010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "expr_local wire"
  let ((g,r),c)←lift "expr_match" (dE 256 100 (hex "0a000000457870722e4d6174636802000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000020000000c000000457870724d6174636841726d02000c0000005061747465726e2e42696e64010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870724d6174636841726d0200100000005061747465726e2e57696c646361726400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = eMatch) && r.remainingNodes == 100 - 8) "expr_match"
  lift "expr_matchf" (finish c); expect (hx (← lift "expr_matche" (encodeExprV1 g)) == "0a000000457870722e4d6174636802000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000020000000c000000457870724d6174636841726d02000c0000005061747465726e2e42696e64010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870724d6174636841726d0200100000005061747465726e2e57696c646361726400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000") "expr_match wire"
  let ((g,r),c)←lift "expr_arm" (dA 256 100 (hex "0c000000457870724d6174636841726d02000c0000005061747465726e2e42696e64010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = eArmB) && r.remainingNodes == 100 - 3) "expr_arm"
  lift "expr_armf" (finish c); expect (hx (← lift "expr_arme" (encodeExprMatchArmV1 g)) == "0c000000457870724d6174636841726d02000c0000005061747465726e2e42696e64010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "expr_arm wire"
  let ((g,r),c)←lift "ext_empty" (dX 256 100 (hex "1000000045787465726e616c43616c6c45787072020002000000040000004d6174680300000061646400000000"))
  expect (decide (g = ext0) && r.remainingNodes == 100 - 1) "ext_empty"
  lift "ext_emptyf" (finish c); expect (hx (← lift "ext_emptye" (encodeExternalCallExprV1 g)) == "1000000045787465726e616c43616c6c45787072020002000000040000004d6174680300000061646400000000") "ext_empty wire"
  expect (decide (eCtor12 ≠ eCtor21)) "ctor nonalias val"
  expect ((← lift "c12" (encodeExprV1 eCtor12)) ≠ (← lift "c21" (encodeExprV1 eCtor21))) "ctor nonalias bytes"
  -- 24 FC at zero budgets
  err "fc_Place.Name_0" "tag 'Place.Name' must declare 1 fields" (dP 0 0 (setFc (hex "0a000000506c6163652e4e616d6501000100000078") 0))
  err "fc_Place.Name_2" "tag 'Place.Name' must declare 1 fields" (dP 0 0 (setFc (hex "0a000000506c6163652e4e616d6501000100000078") 2))
  err "fc_Place.Field_1" "tag 'Place.Field' must declare 2 fields" (dP 0 0 (setFc (hex "0b000000506c6163652e4669656c6402000a000000506c6163652e4e616d650100010000007305000000746f74616c") 1))
  err "fc_Place.Field_3" "tag 'Place.Field' must declare 2 fields" (dP 0 0 (setFc (hex "0b000000506c6163652e4669656c6402000a000000506c6163652e4e616d650100010000007305000000746f74616c") 3))
  err "fc_Place.Index_1" "tag 'Place.Index' must declare 2 fields" (dP 0 0 (setFc (hex "0b000000506c6163652e496e64657802000a000000506c6163652e4e616d650100030000006172720c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 1))
  err "fc_Place.Index_3" "tag 'Place.Index' must declare 2 fields" (dP 0 0 (setFc (hex "0b000000506c6163652e496e64657802000a000000506c6163652e4e616d650100030000006172720c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 3))
  err "fc_Expr.Literal_0" "tag 'Expr.Literal' must declare 1 fields" (dE 0 0 (setFc (hex "0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000010000000000000000000000000000000000000000000000") 0))
  err "fc_Expr.Literal_2" "tag 'Expr.Literal' must declare 1 fields" (dE 0 0 (setFc (hex "0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000010000000000000000000000000000000000000000000000") 2))
  err "fc_Expr.Place_0" "tag 'Expr.Place' must declare 1 fields" (dE 0 0 (setFc (hex "0a000000457870722e506c61636501000a000000506c6163652e4e616d6501000100000078") 0))
  err "fc_Expr.Place_2" "tag 'Expr.Place' must declare 1 fields" (dE 0 0 (setFc (hex "0a000000457870722e506c61636501000a000000506c6163652e4e616d6501000100000078") 2))
  err "fc_Expr.Constructor_1" "tag 'Expr.Constructor' must declare 2 fields" (dE 0 0 (setFc (hex "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e040000006e6f6e6500000000") 1))
  err "fc_Expr.Constructor_3" "tag 'Expr.Constructor' must declare 2 fields" (dE 0 0 (setFc (hex "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e040000006e6f6e6500000000") 3))
  err "fc_Expr.Unary_1" "tag 'Expr.Unary' must declare 2 fields" (dE 0 0 (setFc (hex "0a000000457870722e556e61727902000b000000556e6172794f702e4e656700000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 1))
  err "fc_Expr.Unary_3" "tag 'Expr.Unary' must declare 2 fields" (dE 0 0 (setFc (hex "0a000000457870722e556e61727902000b000000556e6172794f702e4e656700000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 3))
  err "fc_Expr.Binary_2" "tag 'Expr.Binary' must declare 3 fields" (dE 0 0 (setFc (hex "0b000000457870722e42696e61727903000c00000042696e6172794f702e41646400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000") 2))
  err "fc_Expr.Binary_4" "tag 'Expr.Binary' must declare 3 fields" (dE 0 0 (setFc (hex "0b000000457870722e42696e61727903000c00000042696e6172794f702e41646400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000") 4))
  err "fc_Expr.LocalCall_1" "tag 'Expr.LocalCall' must declare 2 fields" (dE 0 0 (setFc (hex "0e000000457870722e4c6f63616c43616c6c02000600000068656c706572010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 1))
  err "fc_Expr.LocalCall_3" "tag 'Expr.LocalCall' must declare 2 fields" (dE 0 0 (setFc (hex "0e000000457870722e4c6f63616c43616c6c02000600000068656c706572010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 3))
  err "fc_Expr.Match_1" "tag 'Expr.Match' must declare 2 fields" (dE 0 0 (setFc (hex "0a000000457870722e4d6174636802000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000020000000c000000457870724d6174636841726d02000c0000005061747465726e2e42696e64010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870724d6174636841726d0200100000005061747465726e2e57696c646361726400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000") 1))
  err "fc_Expr.Match_3" "tag 'Expr.Match' must declare 2 fields" (dE 0 0 (setFc (hex "0a000000457870722e4d6174636802000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000020000000c000000457870724d6174636841726d02000c0000005061747465726e2e42696e64010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870724d6174636841726d0200100000005061747465726e2e57696c646361726400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000") 3))
  err "fc_ExprMatchArm_1" "tag 'ExprMatchArm' must declare 2 fields" (dA 0 0 (setFc (hex "0c000000457870724d6174636841726d02000c0000005061747465726e2e42696e64010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 1))
  err "fc_ExprMatchArm_3" "tag 'ExprMatchArm' must declare 2 fields" (dA 0 0 (setFc (hex "0c000000457870724d6174636841726d02000c0000005061747465726e2e42696e64010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 3))
  err "fc_ExternalCallExpr_1" "tag 'ExternalCallExpr' must declare 2 fields" (dX 0 0 (setFc (hex "1000000045787465726e616c43616c6c45787072020002000000040000004d6174680300000061646400000000") 1))
  err "fc_ExternalCallExpr_3" "tag 'ExternalCallExpr' must declare 2 fields" (dX 0 0 (setFc (hex "1000000045787465726e616c43616c6c45787072020002000000040000004d6174680300000061646400000000") 3))
  -- 41 boundaries
  err "wf0" "unknown place tag 'Expr.Literal'" (dP 0 0 (noFc (tg "Expr.Literal" #[])))
  err "wf1" "unknown place tag 'Expr.Place'" (dP 0 0 (noFc (tg "Expr.Place" #[])))
  err "wf2" "unknown place tag 'Expr.Binary'" (dP 0 0 (noFc (tg "Expr.Binary" #[])))
  err "wf3" "unknown expr tag 'Place.Name'" (dE 0 0 (noFc (tg "Place.Name" #[])))
  err "wf4" "unknown expr tag 'ExprMatchArm'" (dE 0 0 (noFc (tg "ExprMatchArm" #[])))
  err "wf5" "unknown expr tag 'ExternalCallExpr'" (dE 0 0 (noFc (tg "ExternalCallExpr" #[])))
  err "wf6" "unknown expr-match-arm tag 'Place.Field'" (dA 0 0 (noFc (tg "Place.Field" #[])))
  err "wf7" "unknown expr-match-arm tag 'Expr.Match'" (dA 0 0 (noFc (tg "Expr.Match" #[])))
  err "wf8" "unknown external-call tag 'Place.Index'" (dX 0 0 (noFc (tg "Place.Index" #[])))
  err "wf9" "unknown external-call tag 'Expr.Unary'" (dX 0 0 (noFc (tg "Expr.Unary" #[])))
  err "depth" "depth budget exhausted" (dP 0 0 (hex "0a000000506c6163652e4e616d6501000100000078"))
  err "nP" "node budget exhausted" (dP 1 0 (tg "Place.Name" #[ByteArray.empty]))
  err "nE" "node budget exhausted" (dE 1 0 (tg "Expr.Literal" #[ByteArray.empty]))
  err "nA" "node budget exhausted" (dA 1 0 (tg "ExprMatchArm" #[ByteArray.empty, ByteArray.empty]))
  err "nX" "node budget exhausted" (dX 1 0 (tg "ExternalCallExpr" #[ByteArray.empty, ByteArray.empty]))
  err "idx-base" "unknown place tag 'BogusBase'" (dP 4 8 (tg "Place.Index" #[tg "BogusBase" #[], tg "BogusIndex" #[]]))
  err "idx-ix" "unknown expr tag 'BogusIndex'" (dP 4 8 (tg "Place.Index" #[tg "Place.Name" #[sbytes "arr"], tg "BogusIndex" #[]]))
  err "fld-base" "unknown place tag 'BogusBase'" (dP 4 8 (tg "Place.Field" #[tg "BogusBase" #[], u32 0]))
  err "bin-lhs" "unknown expr tag 'BogusLhs'" (dE 4 8 (tg "Expr.Binary" #[tg "BinaryOp.Add" #[], tg "BogusLhs" #[], tg "BogusRhs" #[]]))
  err "bin-op" "unknown binary-op tag 'Visibility.Public'" (dE 4 8 (tg "Expr.Binary" #[tg "Visibility.Public" #[], tg "BogusLhs" #[], tg "BogusRhs" #[]]))
  err "un-op" "unknown unary-op tag 'BinaryOp.Add'" (dE 4 8 (tg "Expr.Unary" #[tg "BinaryOp.Add" #[], tg "BogusOpnd" #[]]))
  err "m-scrut" "unknown expr tag 'BogusScrutinee'" (dE 4 8 (tg "Expr.Match" #[tg "BogusScrutinee" #[], u32 0]))
  err "c-qid" "source qualified id must contain 2..256 components" (dE 4 8 (tg "Expr.Constructor" #[u32 1 ++ sbytes "Only", u32 0xffffffff]))
  err "x-qid" "source qualified id must contain 2..256 components" (dX 4 8 (tg "ExternalCallExpr" #[u32 1 ++ sbytes "Only", u32 0xffffffff]))
  let id241 := String.ofList (List.replicate 241 'a')
  err "l-id" "source name component must contain 1..240 UTF-8 bytes" (dE 4 8 (tg "Expr.LocalCall" #[u32 241 ++ id241.toUTF8, u32 0xffffffff]))
  err "a-pat" "unknown pattern tag 'BogusPattern'" (dA 4 8 (tg "ExprMatchArm" #[tg "BogusPattern" #[], tg "BogusValue" #[]]))
  let qidSome := u32 2 ++ sbytes "Option" ++ sbytes "some"
  err "c-a0" "unknown expr tag 'BogusArg0'" (dE 4 8 (tg "Expr.Constructor" #[qidSome, u32 2 ++ tg "BogusArg0" #[] ++ tg "BogusArg1" #[]]))
  err "bin-rhs" "node budget exhausted" (dE 2 2 (hex "0b000000457870722e42696e61727903000c00000042696e6172794f702e41646400000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000"))
  let qidMath := u32 2 ++ sbytes "Math" ++ sbytes "add"
  err "cap-c" "array count exceeds caller limit" (dE 4 2 (tg "Expr.Constructor" #[qidSome, u32 2]))
  err "cap-l" "array count exceeds caller limit" (dE 4 2 (tg "Expr.LocalCall" #[sbytes "helper", u32 2]))
  err "cap-x" "array count exceeds caller limit" (dX 4 2 (tg "ExternalCallExpr" #[qidMath, u32 2]))
  let scrutLit ← lift "sl" (encodeExprV1 L1)
  err "cap-m" "array count exceeds caller limit" (dE 4 3 (tg "Expr.Match" #[scrutLit, u32 2]))
  err "empty-arms" "expr match arms must be nonempty" (dE 4 8 (tg "Expr.Match" #[scrutLit, u32 0]))
  let ((gx,rx),cx)←lift "ext2" (dX 2 3 (← lift "ex" (encodeExternalCallExprV1 ext2)))
  expect (decide (gx = ext2) && rx.remainingNodes == 0) "ext2"; lift "ext2f" (finish cx)
  err "bool2" "invalid bool marker" (dE 2 2 (tg "Expr.Literal" #[tg "Literal.Bool" #[ByteArray.mk #[2]]]))
  let deep255 := wrapUn 255 L0
  let ((gd,rd),cd)←lift "d255" (dE 256 256 (← lift "ed" (encodeExprV1 deep255)))
  expect (decide (gd = deep255) && rd.remainingNodes == 0) "d255"; lift "d255f" (finish cd)
  err "d256" "depth budget exhausted" (dE 256 257 (← lift "e256" (encodeExprV1 (wrapUn 256 L0))))
  err "n255" "node budget exhausted" (dE 256 255 (← lift "e255b" (encodeExprV1 deep255)))
  err "trail" "trailing bytes" (do let ((_,_),c)←dP 2 2 (hex ("0a000000506c6163652e4e616d6501000100000078" ++ "00")); finish c)
  let ((gc,rc),cc)←lift "c12ok" (dE 2 3 (hex "10000000457870722e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d65020000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010001000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000200000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (gc = eCtor12) && rc.remainingNodes == 0) "c12ok"; lift "c12f" (finish cc)
  let eLocal2:ExprV1:=.localCall helper #[L1,L2]
  let ((gl,rl),cl)←lift "l2ok" (dE 2 3 (← lift "el2" (encodeExprV1 eLocal2)))
  expect (decide (gl = eLocal2) && rl.remainingNodes == 0) "l2ok"; lift "l2f" (finish cl)

end Tests.Language.SourceAstSpinePlaceExprDecodeV1

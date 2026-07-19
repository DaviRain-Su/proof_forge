import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.AstScalarDecodeV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceAstScalarDecodeV1
open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.AstScalarDecodeV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.WireDecodeV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m
private def lift (label : String) (r : Except String α) : IO α :=
  match r with | .ok v => pure v | .error e => throw <| IO.userError s!"{label}: {e}"
private def expectErrExact (label want : String) (r : Except String α) : IO Unit :=
  match r with
  | .error e => expect (e == want) s!"{label}: got {e}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly ok"
private def hexVal (c : Char) : Nat :=
  if '0' ≤ c && c ≤ '9' then c.toNat - '0'.toNat
  else if 'a' ≤ c && c ≤ 'f' then c.toNat - 'a'.toNat + 10
  else if 'A' ≤ c && c ≤ 'F' then c.toNat - 'A'.toNat + 10 else 0
private def fromHex (s : String) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  let cs := s.toList.toArray
  let mut i := 0
  while i + 1 < cs.size do
    out := out.push (UInt8.ofNat (hexVal cs[i]! * 16 + hexVal cs[i + 1]!))
    i := i + 2
  pure out
private def bytesHex (b : ByteArray) : String :=
  b.foldl (fun o x =>
    let v := x.toNat
    let d (n : Nat) := if n < 10 then Char.ofNat ('0'.toNat + n)
      else Char.ofNat ('a'.toNat + n - 10)
    (o.push (d (v / 16))).push (d (v % 16))) ""
private def setU16le (b : ByteArray) (off fc : Nat) : ByteArray := Id.run do
  let mut o := b
  o := o.set! off (UInt8.ofNat (fc % 256))
  o := o.set! (off + 1) (UInt8.ofNat (fc / 256))
  pure o
private def nullaryFc1 (hex : String) : ByteArray :=
  let b := fromHex hex; setU16le b (b.size - 2) 1
private def litFc (hex : String) (fc : Nat) : ByteArray :=
  let b := fromHex hex; setU16le b (4 + (b.get! 0).toNat) fc
private def stripFc (hex : String) : ByteArray :=
  let b := fromHex hex; b.extract 0 (b.size - 2)
private def rtVis (hex : String) (v : VisibilityV1) : IO Unit := do
  let (v', c) ← lift "v" (decodeVisibilityV1 (start (fromHex hex)))
  expect (decide (v' = v)) "v"; lift "vf" (finish c)
  expect (bytesHex (← lift "ve" (encodeVisibilityV1 v')) == hex) "vr"
private def rtUn (hex : String) (v : UnaryOpV1) : IO Unit := do
  let (v', c) ← lift "u" (decodeUnaryOpV1 (start (fromHex hex)))
  expect (decide (v' = v)) "u"; lift "uf" (finish c)
  expect (bytesHex (← lift "ue" (encodeUnaryOpV1 v')) == hex) "ur"
private def rtBin (hex : String) (v : BinaryOpV1) : IO Unit := do
  let (v', c) ← lift "b" (decodeBinaryOpV1 (start (fromHex hex)))
  expect (decide (v' = v)) "b"; lift "bf" (finish c)
  expect (bytesHex (← lift "be" (encodeBinaryOpV1 v')) == hex) "br"
private def rtLit (hex : String) (v : LiteralV1) : IO Unit := do
  let (v', c) ← lift "l" (decodeLiteralV1 (start (fromHex hex)))
  expect (decide (v' = v)) "l"; lift "lf" (finish c)
  expect (bytesHex (← lift "le" (encodeLiteralV1 v')) == hex) "lr"

def run : IO Unit := do
  rtVis "110000005669736962696c6974792e5075626c69630000" .public_
  rtVis "120000005669736962696c6974792e507269766174650000" .private_
  rtVis "150000005669736962696c6974792e436f6d6d69746d656e740000" .commitment
  rtLit "0c0000004c69746572616c2e426f6f6c010000" (.bool false)
  rtLit "0f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000" (.integer 0)
  rtLit "0e0000004c69746572616c2e537472696e670100020000006869" (.string "hi")
  rtUn "0b000000556e6172794f702e4e65670000" .neg
  rtUn "0b000000556e6172794f702e4e6f740000" .not
  rtUn "0e000000556e6172794f702e4269744e6f740000" .bitNot
  rtBin "0c00000042696e6172794f702e4164640000" .add
  rtBin "0c00000042696e6172794f702e5375620000" .sub
  rtBin "0c00000042696e6172794f702e4d756c0000" .mul
  rtBin "0c00000042696e6172794f702e4469760000" .div
  rtBin "0c00000042696e6172794f702e4d6f640000" .mod
  rtBin "0b00000042696e6172794f702e45710000" .eq
  rtBin "0b00000042696e6172794f702e4e650000" .ne
  rtBin "0b00000042696e6172794f702e4c740000" .lt
  rtBin "0b00000042696e6172794f702e4c650000" .le
  rtBin "0b00000042696e6172794f702e47740000" .gt
  rtBin "0b00000042696e6172794f702e47650000" .ge
  rtBin "0c00000042696e6172794f702e416e640000" .logicalAnd
  rtBin "0b00000042696e6172794f702e4f720000" .logicalOr
  rtBin "0f00000042696e6172794f702e426974416e640000" .bitAnd
  rtBin "0e00000042696e6172794f702e4269744f720000" .bitOr
  rtBin "0f00000042696e6172794f702e426974586f720000" .bitXor
  rtBin "0c00000042696e6172794f702e53686c0000" .shl
  rtBin "0c00000042696e6172794f702e5368720000" .shr
  expectErrExact "fc1_Visibility.Public" "tag 'Visibility.Public' must declare 0 fields"
    (decodeVisibilityV1 (start (nullaryFc1 "110000005669736962696c6974792e5075626c69630000")))
  expectErrExact "fc1_Visibility.Private" "tag 'Visibility.Private' must declare 0 fields"
    (decodeVisibilityV1 (start (nullaryFc1 "120000005669736962696c6974792e507269766174650000")))
  expectErrExact "fc1_Visibility.Commitment" "tag 'Visibility.Commitment' must declare 0 fields"
    (decodeVisibilityV1 (start (nullaryFc1 "150000005669736962696c6974792e436f6d6d69746d656e740000")))
  expectErrExact "fc1_UnaryOp.Neg" "tag 'UnaryOp.Neg' must declare 0 fields"
    (decodeUnaryOpV1 (start (nullaryFc1 "0b000000556e6172794f702e4e65670000")))
  expectErrExact "fc1_UnaryOp.Not" "tag 'UnaryOp.Not' must declare 0 fields"
    (decodeUnaryOpV1 (start (nullaryFc1 "0b000000556e6172794f702e4e6f740000")))
  expectErrExact "fc1_UnaryOp.BitNot" "tag 'UnaryOp.BitNot' must declare 0 fields"
    (decodeUnaryOpV1 (start (nullaryFc1 "0e000000556e6172794f702e4269744e6f740000")))
  expectErrExact "fc1_BinaryOp.Add" "tag 'BinaryOp.Add' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0c00000042696e6172794f702e4164640000")))
  expectErrExact "fc1_BinaryOp.Sub" "tag 'BinaryOp.Sub' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0c00000042696e6172794f702e5375620000")))
  expectErrExact "fc1_BinaryOp.Mul" "tag 'BinaryOp.Mul' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0c00000042696e6172794f702e4d756c0000")))
  expectErrExact "fc1_BinaryOp.Div" "tag 'BinaryOp.Div' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0c00000042696e6172794f702e4469760000")))
  expectErrExact "fc1_BinaryOp.Mod" "tag 'BinaryOp.Mod' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0c00000042696e6172794f702e4d6f640000")))
  expectErrExact "fc1_BinaryOp.Eq" "tag 'BinaryOp.Eq' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0b00000042696e6172794f702e45710000")))
  expectErrExact "fc1_BinaryOp.Ne" "tag 'BinaryOp.Ne' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0b00000042696e6172794f702e4e650000")))
  expectErrExact "fc1_BinaryOp.Lt" "tag 'BinaryOp.Lt' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0b00000042696e6172794f702e4c740000")))
  expectErrExact "fc1_BinaryOp.Le" "tag 'BinaryOp.Le' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0b00000042696e6172794f702e4c650000")))
  expectErrExact "fc1_BinaryOp.Gt" "tag 'BinaryOp.Gt' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0b00000042696e6172794f702e47740000")))
  expectErrExact "fc1_BinaryOp.Ge" "tag 'BinaryOp.Ge' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0b00000042696e6172794f702e47650000")))
  expectErrExact "fc1_BinaryOp.And" "tag 'BinaryOp.And' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0c00000042696e6172794f702e416e640000")))
  expectErrExact "fc1_BinaryOp.Or" "tag 'BinaryOp.Or' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0b00000042696e6172794f702e4f720000")))
  expectErrExact "fc1_BinaryOp.BitAnd" "tag 'BinaryOp.BitAnd' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0f00000042696e6172794f702e426974416e640000")))
  expectErrExact "fc1_BinaryOp.BitOr" "tag 'BinaryOp.BitOr' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0e00000042696e6172794f702e4269744f720000")))
  expectErrExact "fc1_BinaryOp.BitXor" "tag 'BinaryOp.BitXor' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0f00000042696e6172794f702e426974586f720000")))
  expectErrExact "fc1_BinaryOp.Shl" "tag 'BinaryOp.Shl' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0c00000042696e6172794f702e53686c0000")))
  expectErrExact "fc1_BinaryOp.Shr" "tag 'BinaryOp.Shr' must declare 0 fields"
    (decodeBinaryOpV1 (start (nullaryFc1 "0c00000042696e6172794f702e5368720000")))
  expectErrExact "fc0_Literal.Bool" "tag 'Literal.Bool' must declare 1 fields"
    (decodeLiteralV1 (start (litFc "0c0000004c69746572616c2e426f6f6c010000" 0)))
  expectErrExact "fc2_Literal.Bool" "tag 'Literal.Bool' must declare 1 fields"
    (decodeLiteralV1 (start (litFc "0c0000004c69746572616c2e426f6f6c010000" 2)))
  expectErrExact "fc0_Literal.Integer" "tag 'Literal.Integer' must declare 1 fields"
    (decodeLiteralV1 (start (litFc "0f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000" 0)))
  expectErrExact "fc2_Literal.Integer" "tag 'Literal.Integer' must declare 1 fields"
    (decodeLiteralV1 (start (litFc "0f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000" 2)))
  expectErrExact "fc0_Literal.String" "tag 'Literal.String' must declare 1 fields"
    (decodeLiteralV1 (start (litFc "0e0000004c69746572616c2e537472696e670100020000006869" 0)))
  expectErrExact "fc2_Literal.String" "tag 'Literal.String' must declare 1 fields"
    (decodeLiteralV1 (start (litFc "0e0000004c69746572616c2e537472696e670100020000006869" 2)))
  expectErrExact "fam_vis_as_un" "unknown unary-op tag 'Visibility.Public'"
    (decodeUnaryOpV1 (start (stripFc "110000005669736962696c6974792e5075626c69630000")))
  expectErrExact "fam_un_as_bin" "unknown binary-op tag 'UnaryOp.Neg'"
    (decodeBinaryOpV1 (start (stripFc "0b000000556e6172794f702e4e65670000")))
  expectErrExact "fam_bin_as_lit" "unknown literal tag 'BinaryOp.Add'"
    (decodeLiteralV1 (start (stripFc "0c00000042696e6172794f702e4164640000")))
  -- sibling literal tag only (no fieldCount/payload) into visibility family
  expectErrExact "fam_lit_as_vis" "unknown visibility tag 'Literal.Bool'"
    (decodeVisibilityV1 (start ((fromHex "0c0000004c69746572616c2e426f6f6c010000").extract 0 16)))
  -- remaining 10 of 14 boundaries (4 family cases above are four-family nonalias)
  expectErrExact "b_empty" "tag length must be 1..21 bytes"
    (decodeTagV1 (start (ByteArray.mk #[0,0,0,0])))
  let mut t22 := ByteArray.mk #[22,0,0,0]
  for _ in [:22] do t22 := t22.push 65
  expectErrExact "b_len22" "tag length must be 1..21 bytes" (decodeTagV1 (start t22))
  expectErrExact "b_trunc" "truncated"
    (decodeTagV1 (start (ByteArray.mk #[5,0,0,0,65])))
  expectErrExact "b_utf8" "invalid UTF-8 tag"
    (decodeTagV1 (start (ByteArray.mk #[1,0,0,0,0xff])))
  expectErrExact "b_ascii" "tag must be ASCII"
    (decodeTagV1 (start (ByteArray.mk #[2,0,0,0,0xc2,0xa9])))
  expectErrExact "b_bool2" "invalid bool marker"
    (decodeLiteralV1 (start (fromHex "0c0000004c69746572616c2e426f6f6c010002")))
  expectErrExact "b_u256" "truncated"
    (decodeLiteralV1 (start (fromHex "0f0000004c69746572616c2e496e74656765720100")))
  expectErrExact "b_str_rem" "string length exceeds remaining"
    (decodeLiteralV1 (start (fromHex "0e0000004c69746572616c2e537472696e6701000500000068")))
  expectErrExact "b_nfd" "string must already be NFC under Unicode 17.0.0"
    (decodeLiteralV1 (start (fromHex "0e0000004c69746572616c2e537472696e6701000300000065cc81")))
  expectErrExact "b_trail" "trailing bytes"
    (do
      let (_v, c) ← decodeVisibilityV1 (start (fromHex "110000005669736962696c6974792e5075626c6963000000"))
      finish c)
  -- LogicalOr vs BitOr value+bytes nonalias (freeze; covered by 27 positives + explicit)
  expect (decide (BinaryOpV1.logicalOr ≠ .bitOr)) "na_or_val"
  let orB ← lift "or" (encodeBinaryOpV1 .logicalOr)
  let borB ← lift "bor" (encodeBinaryOpV1 .bitOr)
  expect (bytesHex orB ≠ bytesHex borB) "na_or_bytes"

end Tests.Language.SourceAstScalarDecodeV1

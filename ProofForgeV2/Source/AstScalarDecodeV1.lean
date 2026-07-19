import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstScalarDecodeV1

open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α :=
  .error detail

def decodeVisibilityV1 : DecoderV1 VisibilityV1 := fun c => do
  let (tag, c) ← decodeTagV1 c
  let value ← match tag with
    | "Visibility.Public" => pure VisibilityV1.public_
    | "Visibility.Private" => pure VisibilityV1.private_
    | "Visibility.Commitment" => pure VisibilityV1.commitment
    | _ => fail s!"unknown visibility tag '{tag}'"
  let ((), c) ← decodeFieldCountV1 tag 0 c
  pure (value, c)

def decodeLiteralV1 : DecoderV1 LiteralV1 := fun c => do
  let (tag, c) ← decodeTagV1 c
  match tag with
  | "Literal.Bool" => do
      let ((), c) ← decodeFieldCountV1 tag 1 c
      let (value, c) ← decodeBool c
      pure (LiteralV1.bool value, c)
  | "Literal.Integer" => do
      let ((), c) ← decodeFieldCountV1 tag 1 c
      let (value, c) ← decodeU256le c
      pure (LiteralV1.integer value, c)
  | "Literal.String" => do
      let ((), c) ← decodeFieldCountV1 tag 1 c
      let (value, c) ← decodeString c
      pure (LiteralV1.string value, c)
  | _ => fail s!"unknown literal tag '{tag}'"

def decodeUnaryOpV1 : DecoderV1 UnaryOpV1 := fun c => do
  let (tag, c) ← decodeTagV1 c
  let value ← match tag with
    | "UnaryOp.Neg" => pure UnaryOpV1.neg
    | "UnaryOp.Not" => pure UnaryOpV1.not
    | "UnaryOp.BitNot" => pure UnaryOpV1.bitNot
    | _ => fail s!"unknown unary-op tag '{tag}'"
  let ((), c) ← decodeFieldCountV1 tag 0 c
  pure (value, c)

def decodeBinaryOpV1 : DecoderV1 BinaryOpV1 := fun c => do
  let (tag, c) ← decodeTagV1 c
  let value ← match tag with
    | "BinaryOp.Add" => pure BinaryOpV1.add
    | "BinaryOp.Sub" => pure BinaryOpV1.sub
    | "BinaryOp.Mul" => pure BinaryOpV1.mul
    | "BinaryOp.Div" => pure BinaryOpV1.div
    | "BinaryOp.Mod" => pure BinaryOpV1.mod
    | "BinaryOp.Eq" => pure BinaryOpV1.eq
    | "BinaryOp.Ne" => pure BinaryOpV1.ne
    | "BinaryOp.Lt" => pure BinaryOpV1.lt
    | "BinaryOp.Le" => pure BinaryOpV1.le
    | "BinaryOp.Gt" => pure BinaryOpV1.gt
    | "BinaryOp.Ge" => pure BinaryOpV1.ge
    | "BinaryOp.And" => pure BinaryOpV1.logicalAnd
    | "BinaryOp.Or" => pure BinaryOpV1.logicalOr
    | "BinaryOp.BitAnd" => pure BinaryOpV1.bitAnd
    | "BinaryOp.BitOr" => pure BinaryOpV1.bitOr
    | "BinaryOp.BitXor" => pure BinaryOpV1.bitXor
    | "BinaryOp.Shl" => pure BinaryOpV1.shl
    | "BinaryOp.Shr" => pure BinaryOpV1.shr
    | _ => fail s!"unknown binary-op tag '{tag}'"
  let ((), c) ← decodeFieldCountV1 tag 0 c
  pure (value, c)

end ProofForgeV2.Source.AstScalarDecodeV1

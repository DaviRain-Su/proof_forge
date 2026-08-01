import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireCodecV1

namespace ProofForgeV2.Source.AstCodecV1

open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireCodecV1

private def fail (detail : String) : Except String α :=
  .error detail

private def nullary (tag : String) : Except String ByteArray :=
  encodeTagged tag #[]

private def allowedWidth (width : UInt16) : Bool :=
  width == 8 || width == 16 || width == 32 ||
  width == 64 || width == 128 || width == 256

private def requireWidth (width : UInt16) : Except String Unit := do
  unless allowedWidth width do
    return ← fail "integer width must be one of 8,16,32,64,128,256"

private def requireLen (kind : String) (length : UInt32) : Except String Unit := do
  unless length.toNat ≤ 4096 do
    return ← fail s!"{kind} length must be 0..4096"

def encodeVisibilityV1 : VisibilityV1 → Except String ByteArray
  | .public_ => nullary "Visibility.Public"
  | .private_ => nullary "Visibility.Private"
  | .commitment => nullary "Visibility.Commitment"

def encodeTypeV1 : TypeV1 → Except String ByteArray
  | .bool => nullary "Type.Bool"
  | .uint width => do
      requireWidth width
      encodeTagged "Type.UInt" #[encodeU16le width]
  | .int width => do
      requireWidth width
      encodeTagged "Type.Int" #[encodeU16le width]
  | .principal => nullary "Type.Principal"
  | .unit => nullary "Type.Unit"
  | .string => nullary "Type.String"
  | .named name => do
      let payload ← encodeSourceNameComponentV1 name
      encodeTagged "Type.Named" #[payload]
  | .array element length => do
      requireLen "array" length
      let el ← encodeTypeV1 element
      encodeTagged "Type.Array" #[el, encodeU32le length]
  | .map key value => do
      let k ← encodeTypeV1 key
      let v ← encodeTypeV1 value
      encodeTagged "Type.Map" #[k, v]
  | .option element => do
      let el ← encodeTypeV1 element
      encodeTagged "Type.Option" #[el]
  | .bytes length => do
      requireLen "bytes" length
      encodeTagged "Type.Bytes" #[encodeU32le length]
  | .field id => do
      unless id.raw == "bn254_fr" do
        return ← fail "field id must be bn254_fr"
      let payload ← encodeSourceNameComponentV1 id
      encodeTagged "Type.Field" #[payload]

def encodeLiteralV1 : LiteralV1 → Except String ByteArray
  | .bool value =>
      encodeTagged "Literal.Bool" #[encodeBool value]
  | .integer magnitude => do
      let payload ← encodeU256le magnitude
      encodeTagged "Literal.Integer" #[payload]
  | .string value => do
      let payload ← encodeString value
      encodeTagged "Literal.String" #[payload]

def encodeUnaryOpV1 : UnaryOpV1 → Except String ByteArray
  | .neg => nullary "UnaryOp.Neg"
  | .not => nullary "UnaryOp.Not"
  | .bitNot => nullary "UnaryOp.BitNot"

def encodeBinaryOpV1 : BinaryOpV1 → Except String ByteArray
  | .add => nullary "BinaryOp.Add"
  | .sub => nullary "BinaryOp.Sub"
  | .mul => nullary "BinaryOp.Mul"
  | .div => nullary "BinaryOp.Div"
  | .mod => nullary "BinaryOp.Mod"
  | .eq => nullary "BinaryOp.Eq"
  | .ne => nullary "BinaryOp.Ne"
  | .lt => nullary "BinaryOp.Lt"
  | .le => nullary "BinaryOp.Le"
  | .gt => nullary "BinaryOp.Gt"
  | .ge => nullary "BinaryOp.Ge"
  | .logicalAnd => nullary "BinaryOp.And"
  | .logicalOr => nullary "BinaryOp.Or"
  | .bitAnd => nullary "BinaryOp.BitAnd"
  | .bitOr => nullary "BinaryOp.BitOr"
  | .bitXor => nullary "BinaryOp.BitXor"
  | .shl => nullary "BinaryOp.Shl"
  | .shr => nullary "BinaryOp.Shr"

end ProofForgeV2.Source.AstCodecV1

import ProofForgeV2.Source.NameComponentV1

namespace ProofForgeV2.Source.AstV1

open ProofForgeV2.Source.NameComponentV1

/-- Portable source visibility labels (SPEC-SOURCE-WIRE-001). -/
inductive VisibilityV1 where
  | public_
  | private_
  | commitment
  deriving DecidableEq, Repr

/-- Portable source type constructors (leaf + nested container). -/
inductive TypeV1 where
  | bool
  | uint (width : UInt16)
  | int (width : UInt16)
  | principal
  | unit
  /-- Variable-length NFC UTF-8 string (N4). Source keyword `String`; maps to
      Semantic `TypeShapeV1.string`. -/
  | string
  | named (name : SourceNameComponentV1)
  | array (element : TypeV1) (length : UInt32)
  | map (key value : TypeV1)
  | option (element : TypeV1)
  | bytes (length : UInt32)
  | field (id : SourceNameComponentV1)
  deriving DecidableEq, Repr

/-- Portable source literals (wire leaf values). -/
inductive LiteralV1 where
  | bool (value : Bool)
  | integer (magnitude : Nat)
  | string (value : String)
  deriving DecidableEq, Repr

/-- Portable unary operators. -/
inductive UnaryOpV1 where
  | neg
  | not
  | bitNot
  deriving DecidableEq, Repr

/-- Portable binary operators (18 unique; logical Or ≠ BitOr). -/
inductive BinaryOpV1 where
  | add
  | sub
  | mul
  | div
  | mod
  | eq
  | ne
  | lt
  | le
  | gt
  | ge
  | logicalAnd
  | logicalOr
  | bitAnd
  | bitOr
  | bitXor
  | shl
  | shr
  deriving DecidableEq, Repr

end ProofForgeV2.Source.AstV1

import ProofForge.IR.Core

/-! # Surface AST — Independent Type System

Surface-owned types for the independent authoring front-end. These do NOT
alias `IR.ValueType` or any backend/target AST. The normalizer resolves
Surface types to `CoreType` using a declaration-order type-id map.
-/

namespace ProofForge.Frontend.Surface

/-- Surface-level types. Independent of `IR.ValueType` and any target AST. -/
inductive SurfaceType
  | unit
  | bool
  | u8
  | u32
  | u64
  | u128
  | address
  | bytes
  | string
  | hash
  | fixedArray (element : SurfaceType) (length : Nat)
  | array (element : SurfaceType)
  | structType (name : String)
  deriving BEq, Repr

end ProofForge.Frontend.Surface
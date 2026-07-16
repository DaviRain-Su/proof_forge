import ProofForge.IR.Core

/-! # Authored AST — Independent Type System

Authored-owned types for the independent authoring front-end. These do NOT
alias `IR.ValueType` or any backend/target AST. The normalizer resolves
Authored types to `CoreType` using a declaration-order type-id map.
-/

namespace ProofForge.Frontend.Authored

/-- Authored-level types. Independent of `IR.ValueType` and any target AST. -/
inductive AuthoredType
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
  | fixedArray (element : AuthoredType) (length : Nat)
  | array (element : AuthoredType)
  | memoryRef (element : AuthoredType)
  | structType (name : String)
  deriving BEq, Repr

end ProofForge.Frontend.Authored

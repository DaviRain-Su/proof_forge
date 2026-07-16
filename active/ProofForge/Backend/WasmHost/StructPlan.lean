import ProofForge.IR.ValueType

/-! Target-owned aggregate layout used by Wasm-host plans. -/

namespace ProofForge.Backend.WasmHost.StructPlan

open ProofForge.IR

structure Field where
  id : String
  type : ValueType
  isPublic : Bool := false
  isRef : Bool := false
  deriving Repr, BEq

structure Struct where
  name : String
  fields : Array Field
  deriveStorage : Bool := false
  isPublic : Bool := false
  isRecord : Bool := false
  deriving Repr, BEq

end ProofForge.Backend.WasmHost.StructPlan

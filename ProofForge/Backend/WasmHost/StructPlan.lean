import ProofForge.IR.Contract

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

def ofIR (declaration : StructDecl) : Struct := {
  name := declaration.name
  fields := declaration.fields.map fun field => {
    id := field.id
    type := field.type
    isPublic := field.isPublic
    isRef := field.isRef
  }
  deriveStorage := declaration.deriveStorage
  isPublic := declaration.isPublic
  isRecord := declaration.isRecord
}

def toIR (plan : Struct) : StructDecl := {
  name := plan.name
  fields := plan.fields.map fun field => {
    id := field.id
    type := field.type
    isPublic := field.isPublic
    isRef := field.isRef
  }
  deriveStorage := plan.deriveStorage
  isPublic := plan.isPublic
  isRecord := plan.isRecord
}

end ProofForge.Backend.WasmHost.StructPlan

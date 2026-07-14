import ProofForge.Backend.WasmHost.StructPlan
import ProofForge.IR.Contract

namespace ProofForge.Backend.WasmHost.StructPlan.Legacy

open ProofForge.IR

def ofIR (declaration : StructDecl) : StructPlan.Struct := {
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

end ProofForge.Backend.WasmHost.StructPlan.Legacy

import ProofForge.IR.Core
import ProofForge.Compiler.Wasm.AST

namespace ProofForge.Backend.WasmHost.CorePlan

open ProofForge.IR.Core
open ProofForge.Compiler

structure MemoryPlan where
  stateOffset : Nat
  stateSize : Nat

structure FunctionPlan where
  name : String
  params : List (String × CoreType)
  retTy : CoreType
  body : List Wasm.Insn

structure WasmCorePlan where
  moduleName : String
  memory : MemoryPlan
  functions : List FunctionPlan
  imports : List Wasm.Import

def buildWasmCorePlan (m : CoreModule) : WasmCorePlan :=
  { moduleName := m.name
  , memory := { stateOffset := 0, stateSize := m.state.length * 8 }
  , functions := m.entrypoints.map fun e =>
      { name := e.name, params := e.params, retTy := e.retTy, body := [] }
  , imports := []
  }

end ProofForge.Backend.WasmHost.CorePlan

import ProofForge.IR.Core
import ProofForge.Backend.WasmHost.CorePlan
import ProofForge.Backend.WasmHost.CoreLower

open ProofForge.IR.Core
open ProofForge.Backend.WasmHost.CorePlan
open ProofForge.Backend.WasmHost.CoreLower

def main : IO UInt32 := do
  let m : CoreModule :=
    { name := "Counter"
    , structs := []
    , state := [ { name := "count", ty := .u64, initializer := .some (.literal (.u64Lit (0 : UInt64))) } ]
    , entrypoints := [ { name := "increment", params := [], retTy := .unit, body := [] } ]
    , events := []
    }
  let plan := buildWasmCorePlan m
  let wasm := lowerWasmCorePlan plan
  if wasm.funcs.size > 0 then
    IO.println "WasmHostCoreSmoke OK"
    return 0
  else
    IO.println "WasmHostCoreSmoke FAIL"
    return 1

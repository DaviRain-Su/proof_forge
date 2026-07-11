import ProofForge.IR.Core
import ProofForge.Backend.Evm.CorePlan
import ProofForge.Backend.Evm.CoreLower
import ProofForge.Compiler.Yul.Printer

open ProofForge.IR.Core
open ProofForge.Backend.Evm.CorePlan
open ProofForge.Backend.Evm.CoreLower

def counterModule : CoreModule :=
  { name := "Counter"
  , structs := []
  , state := [ { name := "count", ty := .u64, initializer := .some (.literal (.u64Lit 0)) } ]
  , entrypoints := [ { name := "increment", params := [], retTy := .unit, body := [] } ]
  , events := []
  }

def main : IO UInt32 := do
  let plan := buildEvmCorePlan counterModule
  let yul := lowerEvmCorePlan plan
  let rendered := Lean.Compiler.Yul.Printer.render yul
  if rendered.contains "Counter" then
    IO.println "EvmCoreSmoke OK"
    return 0
  else
    IO.println "EvmCoreSmoke FAIL"
    return 1

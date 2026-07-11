import ProofForge.IR.Core
import ProofForge.IR.Core.Validate

open ProofForge.IR.Core
open ProofForge.IR.Core.Validate

def counterCoreModule : CoreModule :=
  { name := "Counter"
  , structs := []
  , state := [ { name := "count", ty := .u64, initializer := .some (.literal (.u64Lit 0)) } ]
  , entrypoints :=
      [ { name := "increment", params := [], retTy := .unit
        , body := [ .effect (.storageWrite (.scalar 0) (.binary .add (.literal (.u64Lit 1)) (.local "count"))) ]
        }
      ]
  , events := []
  }

def main : IO UInt32 := do
  match validateModule counterCoreModule with
  | .ok () =>
    IO.println "CoreIRSmoke OK"
    return 0
  | .error e =>
    IO.println s!"CoreIRSmoke FAIL: {repr e}"
    return 1

import ProofForge.IR.Legacy.Core
import ProofForge.IR.Legacy.Validate

open ProofForge.IR.Legacy.Core
open ProofForge.IR.Legacy.Validate

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

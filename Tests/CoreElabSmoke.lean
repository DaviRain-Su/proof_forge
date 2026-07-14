import ProofForge.IR.Contract
import TestFixtures.Legacy.Elaborate

open ProofForge.IR
open TestFixtures.Legacy.Elaborate

def counterSurfaceModule : Module :=
  { name := "Counter"
  , state := #[ { id := "count", kind := .scalar, type := .u64 } ]
  , entrypoints := #[
      { name := "increment"
      , params := #[]
      , returns := .unit
      , body := #[
          .effect (.storageScalarWrite "count"
            (.add (.literal (.u64 1)) (.effect (.storageScalarRead "count"))))
        ]
      }
    , { name := "get"
      , params := #[]
      , returns := .u64
      , body := #[ .return (.effect (.storageScalarRead "count")) ]
      }
    ]
  }

def main : IO UInt32 := do
  match elaborateModule counterSurfaceModule with
  | .ok core =>
    IO.println s!"CoreElabSmoke OK: {core.name}"
    return 0
  | .error e =>
    IO.println s!"CoreElabSmoke FAIL: {repr e}"
    return 1

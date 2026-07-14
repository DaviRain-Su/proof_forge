import ProofForge.IR.Contract
import TestFixtures.Legacy.Elaborate

open ProofForge.IR
open TestFixtures.Legacy.Elaborate

/-- A module whose only state variable is "count", but the entrypoint reads an
undeclared "owner" state variable. Elaboration must fail with
`ElabError.unknownState "owner"`. -/
def unknownStateSurfaceModule : Module :=
  { name := "UnknownState"
  , state := #[ { id := "count", kind := .scalar, type := .u64 } ]
  , entrypoints := #[
      { name := "getOwner"
      , params := #[]
      , returns := .u64
      , body := #[ .return (.effect (.storageScalarRead "owner")) ]
      }
    ]
  }

def main : IO UInt32 := do
  match elaborateModule unknownStateSurfaceModule with
  | .ok core =>
    IO.println s!"CoreElabNegativeSmoke FAIL: elaboration succeeded unexpectedly: {core.name}"
    return 1
  | .error (.unknownState "owner") =>
    IO.println "CoreElabNegativeSmoke OK: unknown state rejected"
    return 0
  | .error e =>
    IO.println s!"CoreElabNegativeSmoke FAIL: expected unknownState owner, got {repr e}"
    return 1

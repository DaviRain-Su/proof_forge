import ProofForge.IR.Examples.StructProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.StructModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.StructProbe.emitWatStorageModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module StructProbeModel",
        "var current_x: int",
        "var current_y: int",
        "action storage_lifecycle",
        "current_x' = 7",
        "current_y' = 19"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.StructModel

def main : IO UInt32 := Tests.Quint.StructModel.main
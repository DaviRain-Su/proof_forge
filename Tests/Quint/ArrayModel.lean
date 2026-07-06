import ProofForge.IR.Examples.ArrayProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.ArrayModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.ArrayProbe.emitWatStorageModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module ArrayProbeModel",
        "var values: List[int]",
        "action storage_lifecycle",
        "values' =",
        "7",
        "13"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.ArrayModel

def main : IO UInt32 := Tests.Quint.ArrayModel.main
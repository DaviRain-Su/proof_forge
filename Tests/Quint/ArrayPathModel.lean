import ProofForge.IR.Examples.EvmStorageArrayProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.ArrayPathModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.EvmStorageArrayProbe.emitQuintPathModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module EvmStorageArrayProbeModel",
        "var values: List[int]",
        "action path_lifecycle",
        "values' =",
        "21",
        "22",
        "action path_assign_lifecycle",
        "10][2] + 5"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.ArrayPathModel

def main : IO UInt32 := Tests.Quint.ArrayPathModel.main
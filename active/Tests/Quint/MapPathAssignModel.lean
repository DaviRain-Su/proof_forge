import ProofForge.IR.Examples.MapProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.MapPathAssignModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.MapProbe.emitQuintPathAssignModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module MapProbeModel",
        "var scores: str -> int",
        "action path_assign_lifecycle",
        "u64:3003",
        "+ 5",
        "action nested_path_assign_lifecycle",
        "{u64:4004}{u64:5005}",
        "+ 7"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.MapPathAssignModel

def main : IO UInt32 := Tests.Quint.MapPathAssignModel.main
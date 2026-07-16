import ProofForge.IR.Examples.MapProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.MapHashPathAssignModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.MapProbe.emitQuintHashPathAssignModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module MapProbeModel",
        "var balances: str -> str",
        "action hash_path_assign_lifecycle",
        "hash:2002:0:0:0",
        "hash:99:88:77:66"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      if source.contains " + " then
        IO.eprintln "FAIL hash map assignOp must replace, not add strings"
        return 1
      IO.println "PASS"
      return 0

end Tests.Quint.MapHashPathAssignModel

def main : IO UInt32 := Tests.Quint.MapHashPathAssignModel.main
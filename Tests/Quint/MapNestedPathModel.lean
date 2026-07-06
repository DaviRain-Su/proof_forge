import ProofForge.IR.Examples.MapProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.MapNestedPathModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.MapProbe.emitQuintNestedPathModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module MapProbeModel",
        "action nested_path_lifecycle",
        "balances' = balances.put(",
        "{hash:4004:0:0:0}{hash:5005:0:0:0}",
        "hash:88:99:111:112"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.MapNestedPathModel

def main : IO UInt32 := Tests.Quint.MapNestedPathModel.main
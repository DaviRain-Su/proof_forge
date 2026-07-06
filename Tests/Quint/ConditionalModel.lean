import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.ConditionalModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 5, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.ConditionalProbe.module scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module ConditionalProbeModel",
        "var count: int",
        "action conditional_lifecycle",
        "count' = if ((if (1 == 1) 4 else 99) < 2)",
        "== 10"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.ConditionalModel

def main : IO UInt32 := Tests.Quint.ConditionalModel.main

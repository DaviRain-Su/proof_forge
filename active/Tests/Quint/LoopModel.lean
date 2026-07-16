import ProofForge.IR.Examples.LoopProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.LoopModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 5, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.LoopProbe.module scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module LoopProbeModel",
        "var count: int",
        "action count_to_three",
        "count' = 0 + 1 + 1 + 1"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.LoopModel

def main : IO UInt32 := Tests.Quint.LoopModel.main

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
        "count' = count + 1"
      ]
      let countPlusOne := (source.splitOn "count' = count + 1").length - 1
      if countPlusOne != 3 then
        IO.eprintln s!"FAIL expected 3 loop unrolls, got {countPlusOne}"
        return 1
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.LoopModel

def main : IO UInt32 := Tests.Quint.LoopModel.main

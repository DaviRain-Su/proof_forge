import ProofForge.IR.Examples.WhileProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.WhileModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 5, users := #["alice"] }

/-- Default maxLoopUnroll=10 previously produced ~689KB of nested ites. -/
def maxSourceBytes : Nat := 8192

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.WhileProbe.module scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      if source.length > maxSourceBytes then
        IO.eprintln s!"FAIL source too large: {source.length} bytes (max {maxSourceBytes})"
        return 1
      let expected := [
        "module WhileProbeModel",
        "var count: int",
        "action count_to_three",
        "pure def __while_count_0",
        "pure def __while_count_10",
        "count' = __while_count_10"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.WhileModel

def main : IO UInt32 := Tests.Quint.WhileModel.main
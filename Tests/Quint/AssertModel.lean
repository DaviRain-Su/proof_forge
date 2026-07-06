import ProofForge.IR.Examples.AssertProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.AssertModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 20, users := #["alice"], indexFromZero := true }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.AssertProbe.module scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module AssertProbeModel",
        "action checked_sum",
        "nondet a",
        "nondet b",
        "(true)",
        "a + b == 12",
        "a + b == a + b"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.AssertModel

def main : IO UInt32 := Tests.Quint.AssertModel.main
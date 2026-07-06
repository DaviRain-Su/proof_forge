import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.CrosscallModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 20, users := #["alice"], indexFromZero := true }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.CrosscallProbe.module scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module CrosscallProbeModel",
        "action call_remote",
        "action call_with_args",
        "nondet target",
        "nondet method",
        "nondet amount",
        "nondet fee",
        "target + method",
        "target + method + amount + fee"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      if source.contains "crosscallCreate" || source.contains "not supported in Quint lowering" then
        IO.eprintln "FAIL lowering must support crosscallInvoke stub"
        return 1
      IO.println "PASS"
      return 0

end Tests.Quint.CrosscallModel

def main : IO UInt32 := Tests.Quint.CrosscallModel.main
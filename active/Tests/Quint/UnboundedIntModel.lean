import ProofForge.Backend.Quint.Lower
import ProofForge.IR.Examples.UnboundedIntProbe

namespace Tests.Quint.UnboundedIntModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := {
  maxUint := 3,
  users := #["alice"],
  indexFromZero := true,
  unboundedIntegers := true
}

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.UnboundedIntProbe.module scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module UnboundedIntProbeModel",
        "action write_large",
        "action add_amount",
        "1000000",
        "0.to(MAX_UINT)"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.UnboundedIntModel

def main : IO UInt32 := Tests.Quint.UnboundedIntModel.main
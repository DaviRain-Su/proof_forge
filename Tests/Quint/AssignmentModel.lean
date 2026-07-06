import ProofForge.IR.Examples.AssignmentProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.AssignmentModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 20, users := #["alice"], indexFromZero := true }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.AssignmentProbe.module scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module AssignmentProbeModel",
        "action reassignment",
        "nondet seed",
        "0.to(MAX_UINT)",
        "== 12"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      if source.contains "local assignment not supported" then
        IO.eprintln "FAIL lowering must support local assignment"
        return 1
      IO.println "PASS"
      return 0

end Tests.Quint.AssignmentModel

def main : IO UInt32 := Tests.Quint.AssignmentModel.main
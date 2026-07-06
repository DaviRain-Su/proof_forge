import ProofForge.IR.Examples.MapProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.MapNestedDynamicPathModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.MapProbe.emitQuintNestedDynamicPathModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module MapProbeModel",
        "action nested_dynamic_path_lifecycle",
        "nondet inner",
        "{hash:4004:0:0:0}",
        "inner == \"hash:1001:0:0:0\"",
        "{hash:4004:0:0:0}{hash:1001:0:0:0}",
        "hash:77:88:99:111"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.MapNestedDynamicPathModel

def main : IO UInt32 := Tests.Quint.MapNestedDynamicPathModel.main
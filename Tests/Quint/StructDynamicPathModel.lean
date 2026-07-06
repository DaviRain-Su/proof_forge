import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.StructDynamicPathModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 1, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.EvmStorageStructProbe.emitQuintDynamicStructPathModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module EvmStorageStructProbeModel",
        "action dynamic_array_path_lifecycle",
        "points_0_x",
        "points_1_x",
        "index == 0",
        "index == 1",
        "+ 3"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.StructDynamicPathModel

def main : IO UInt32 := Tests.Quint.StructDynamicPathModel.main
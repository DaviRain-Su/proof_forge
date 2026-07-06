import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.StructPathModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.EvmStorageStructProbe.emitQuintPathModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module EvmStorageStructProbeModel",
        "var current_x: int",
        "var current_y: int",
        "var points_0_x: int",
        "var points_0_y: int",
        "var points_1_x: int",
        "var points_1_y: int",
        "action path_lifecycle",
        "current_x' = 21 + 5",
        "current_y' = 22",
        "action array_path_lifecycle",
        "points_1_x' = 13 + 2",
        "points_0_y' = 8"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.StructPathModel

def main : IO UInt32 := Tests.Quint.StructPathModel.main
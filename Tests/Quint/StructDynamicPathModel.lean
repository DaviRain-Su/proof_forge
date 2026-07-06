import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.GuardAst

namespace Tests.Quint.StructDynamicPathModel

open ProofForge.Backend.Quint
open ProofForge.Backend.Quint.GuardAst

def scenario : Scenario.Config := { maxUint := 1, users := #["alice"], indexFromZero := true }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.EvmStorageStructProbe.emitQuintDynamicStructPathModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module EvmStorageStructProbeModel",
        "action dynamic_array_path_lifecycle",
        "points_0_x'",
        "points_1_x'",
        "0.to(MAX_UINT)"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      match validateRenderedDynamicPathGuard source with
      | some err =>
          IO.eprintln s!"FAIL guard render: {err}"
          return 1
      | none =>
          IO.println "PASS"
          return 0

end Tests.Quint.StructDynamicPathModel

def main : IO UInt32 := Tests.Quint.StructDynamicPathModel.main
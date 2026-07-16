import ProofForge.IR.Examples.StorageNestedAggregateProbe
import ProofForge.Backend.Quint.Lower

namespace Tests.Quint.NestedStructRefModel

open ProofForge.Backend.Quint

def scenario : Scenario.Config := { maxUint := 10, users := #["alice"] }

def main : IO UInt32 := do
  match Lower.renderModule ProofForge.IR.Examples.StorageNestedAggregateProbe.emitQuintNestedStructRefModule scenario with
  | .error e =>
      IO.eprintln s!"FAIL lower: {e.message}"
      return 1
  | .ok source =>
      let expected := [
        "module StorageNestedAggregateProbeModel",
        "var person_profile_age: int",
        "var person_profile_level: int",
        "var person_profile_rank: int",
        "var person_score: int",
        "var people_0_profile_age: int",
        "var people_1_profile_age: int",
        "var people_1_score: int",
        "action nested_ref_lifecycle",
        "person_profile_age' = 21 + 2",
        "person_profile_level' = 4",
        "person_profile_rank' = 5",
        "person_score' = 50",
        "people_1_profile_age' = 31"
      ]
      for s in expected do
        if !source.contains s then
          IO.eprintln s!"FAIL missing substring: {s}"
          return 1
      IO.println "PASS"
      return 0

end Tests.Quint.NestedStructRefModel

def main : IO UInt32 := Tests.Quint.NestedStructRefModel.main
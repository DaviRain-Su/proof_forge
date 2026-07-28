/-
  Isolated residual-only characterization fixture (not product evidence).

  S6 closed public Residual.planFromAlpha / lowerPlan / filesFromIR.
  Product IR for capability-supported programs uses production
  `irFromCapability` / `buildFromCapability` only.

  This module retains solely the PrivateSum4 RelationIR fixture (S1 dual-carrier
  cannot express privateWitness). NearHostModel / NoirRelationModel / Targets
  must not depend on local Plan→IR lowers.
-/
import ProofForgeV2.Targets.Noir

namespace Tests.Materialization.TargetIrFixtures

open ProofForgeV2

/-- Isolated PrivateSum4 host-model RelationIR fixture (residual-only; not product emit).

  S1/Normalize + dual-carrier cannot express privateWitness PrivateSum4.
  This hand-built RelationIR preserves host accept/reject coverage without any
  shipped public residual plan/lower/emit helper or production IR path.
-/
def privateSum4RelationIR : Targets.Noir.RelationIR :=
  let relation : Targets.Noir.Relation := {
    index := 0
    name := "sum"
    artifactStem := "r0-sum"
    mode := .mutate
    params := #[
      { sourceId := 0, name := "a", inputIndex := 0, visibility := .witness },
      { sourceId := 1, name := "b", inputIndex := 1, visibility := .witness },
      { sourceId := 2, name := "c", inputIndex := 2, visibility := .witness },
      { sourceId := 3, name := "d", inputIndex := 3, visibility := .witness }
    ]
    inputs := #[
      {
        name := "arg_p0", sourceName := "a", type := .u64
        visibility := .witness, role := .parameter 0
      },
      {
        name := "arg_p1", sourceName := "b", type := .u64
        visibility := .witness, role := .parameter 1
      },
      {
        name := "arg_p2", sourceName := "c", type := .u64
        visibility := .witness, role := .parameter 2
      },
      {
        name := "arg_p3", sourceName := "d", type := .u64
        visibility := .witness, role := .parameter 3
      },
      {
        name := "result", sourceName := "result", type := .u64
        visibility := .verifier, role := .result
      }
    ]
    body := #[
      .returnValue (
        .checkedAdd
          (.checkedAdd
            (.checkedAdd (.param 0) (.param 1))
            (.param 2))
          (.param 3))
    ]
  }
  {
    sourceRelation := relation
    tempCount := 3
    operations := #[
      .checkedAdd 0 (.input 0) (.input 1),
      .checkedAdd 1 (.temp 0) (.input 2),
      .checkedAdd 2 (.temp 1) (.input 3),
      .assertEqual (.input 4) (.temp 2)
    ]
  }

end Tests.Materialization.TargetIrFixtures

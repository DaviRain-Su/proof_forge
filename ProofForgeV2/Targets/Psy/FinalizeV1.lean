import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Psy.FinalizeV1

open ProofForgeV2
open System

/-- Psy DPN finalization is deliberately zero-tool and non-deployable. -/
def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (_artifacts : MaterializedArtifactsV1)
    (_stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 :=
  pure {
    deployable := false
    extraFiles := #[]
    evidenceNote :=
      "Psy materialization emits only the versioned DPN package; product finalization performs no source compilation, VM execution, proof, UPS, or deployment"
  }

end ProofForgeV2.Targets.Psy.FinalizeV1

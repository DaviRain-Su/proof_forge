import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Aleo.FinalizeV1

open ProofForgeV2
open System

/-- Aleo Instructions finalization is deliberately zero-tool and non-deployable. -/
def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (_artifacts : MaterializedArtifactsV1)
    (_stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 :=
  pure {
    deployable := false
    extraFiles := #[]
    evidenceNote :=
      "Aleo materialization emits canonical Aleo Instructions plus its network-state query descriptor; product finalization performs no compilation, VM execution, proof, deployment, or network query"
  }

end ProofForgeV2.Targets.Aleo.FinalizeV1

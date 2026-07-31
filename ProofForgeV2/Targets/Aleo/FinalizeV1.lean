/-
  Aleo engineering finalization adapter (D3/S7b).

  Zero tools; exact non-deployable note. Leo 4.0.2 source is emitted without a
  digest-pinned `leo` compiler, so no build/execute/proof/deploy evidence is
  claimed. Separate from pure `Targets.Aleo` Plan/IR core.
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Aleo.FinalizeV1

open ProofForgeV2
open System

/-- Exact Aleo zero-tool finalization: no extras, fixed non-deployable note. -/
def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (_artifacts : MaterializedArtifactsV1)
    (_stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 :=
  pure {
    deployable := false
    extraFiles := #[]
    evidenceNote :=
      "no approved and digest-pinned Leo compiler/proving backend is configured; Leo source was emitted without leo build, execution, proof, or deployment evidence"
  }

end ProofForgeV2.Targets.Aleo.FinalizeV1

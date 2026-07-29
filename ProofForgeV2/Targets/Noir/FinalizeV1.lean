/-
  Noir engineering finalization adapter (D3/S7b).

  Zero tools; exact non-deployable note formerly in CLI.Emit.finalize (.noir).
  Separate from pure `Targets.Noir` Plan/IR core.
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Noir.FinalizeV1

open ProofForgeV2
open System

/-- Exact Noir zero-tool finalization: no extras, fixed non-deployable note. -/
def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (_artifacts : MaterializedArtifactsV1)
    (_stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 :=
  pure {
    deployable := false
    extraFiles := #[]
    evidenceNote :=
      "no approved and digest-pinned Noir compiler/proving backend is configured; relation source/schema were emitted without ACIR, witness execution, proof, or verification"
  }

end ProofForgeV2.Targets.Noir.FinalizeV1

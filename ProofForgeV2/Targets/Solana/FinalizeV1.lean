/-
  Solana engineering finalization adapter (D3/S7b).

  Zero tools; exact non-deployable note formerly in CLI.Emit.finalize (.solana).
  Separate from pure `Targets.Solana` Plan/IR core.
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Solana.FinalizeV1

open ProofForgeV2
open System

/-- Exact Solana zero-tool finalization: no extras, fixed non-deployable note. -/
def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (_artifacts : MaterializedArtifactsV1)
    (_stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 :=
  pure {
    deployable := false
    extraFiles := #[]
    evidenceNote :=
      "no pinned/approved sBPF assembler is configured; typed plan and IDL artifacts are non-executable"
  }

end ProofForgeV2.Targets.Solana.FinalizeV1

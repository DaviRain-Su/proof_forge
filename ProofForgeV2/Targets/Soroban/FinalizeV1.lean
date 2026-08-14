/-
  Soroban engineering finalization adapter (D3/S7b).

  Zero tools; exact non-deployable note. Product finalization does not invoke
  soroban-cli, stellar-cli, or Wasm toolchain, so no compile/test/deploy/
  settlement evidence is claimed.
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Soroban.FinalizeV1

open ProofForgeV2
open System

def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (_artifacts : MaterializedArtifactsV1)
    (_stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 :=
  pure {
    deployable := false
    extraFiles := #[]
    evidenceNote :=
      "no soroban-cli, stellar-cli, or Wasm toolchain was invoked; emitted Soroban Rust source carries no compile, test, deploy, or settlement evidence"
  }

end ProofForgeV2.Targets.Soroban.FinalizeV1

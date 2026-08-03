/-
  Quint engineering finalization adapter (D3/S7b).

  Zero tools; exact non-deployable note. Product finalization does not invoke
  the Quint CLI, Apalache, TLC, or Java, so no parse/typecheck/run/test/verify/
  ITF/MBT/proof/deploy/settlement evidence is claimed.
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Quint.FinalizeV1

open ProofForgeV2
open System

/-- Exact Quint zero-tool finalization: no extras, fixed non-deployable note. -/
def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (_artifacts : MaterializedArtifactsV1)
    (_stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 :=
  pure {
    deployable := false
    extraFiles := #[]
    evidenceNote :=
      "no Quint CLI, Apalache, TLC, or Java toolchain was invoked; emitted Quint source carries no parse, typecheck, run, test, verify, ITF, MBT, proof, deploy, or settlement evidence"
  }

end ProofForgeV2.Targets.Quint.FinalizeV1

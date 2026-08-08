/-
  Psy engineering finalization adapter (D3/S7b).

  Zero tools; exact non-deployable note. Product finalize does **not** invoke
  dargo / psy_vm: materialize may dual-write `{name}.dpn.json` (DPN package
  authority, PSY-DPN-7) plus transitional `{name}.psy` when DPN lower succeeds
  (R-HARD: residual allowlist empty; any DPN failure fails materialize);
  neither artifact is compiled, executed, or proven on the product path.

  Separate host-heavy engineering lane (external to this finalize adapter):
  `scripts/psy_runtime_test.sh` / `just psy-runtime` may exercise locked
  official dargo v0.1.0 local VM/base proof under
  `PROOF_FORGE_TOOL_ROOT` (profile label `psy-dargo-0.1.0-local-proof-v1`)
  when a materialized locked tool root is present. That lane is **not**
  product finalization, not ordinary ci, and not formal/hermetic/deploy.

  Separate from pure `Targets.Psy` Plan/IR core.
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Psy.FinalizeV1

open ProofForgeV2
open System

/-- Exact Psy zero-tool finalization: no extras, fixed non-deployable note. -/
def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (_artifacts : MaterializedArtifactsV1)
    (_stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 :=
  pure {
    deployable := false
    extraFiles := #[]
    evidenceNote :=
      "no approved and digest-pinned Dargo/psy_vm toolchain is configured on the product finalize path; PSY-DPN-7 dual-write may emit DPN package JSON (primary) and transitional .psy when DPN lower succeeds (R-HARD: residual allowlist empty; any DPN lower failure fails materialize with PSY-DPN-G5-HARD) without dargo/psy_vm build, execution, proof, UPS, or deployment evidence (optional host-heavy locked dargo local-VM lane is external: scripts/psy_runtime_test.sh)"
  }

end ProofForgeV2.Targets.Psy.FinalizeV1

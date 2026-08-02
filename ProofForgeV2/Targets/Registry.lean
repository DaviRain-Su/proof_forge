import ProofForgeV2.Targets.Evm
import ProofForgeV2.Targets.Evm.PlanSchemaV1
import ProofForgeV2.Targets.Solana.PlanSchemaV1
import ProofForgeV2.Targets.Near.PlanSchemaV1
import ProofForgeV2.Targets.Noir.PlanSchemaV1
import ProofForgeV2.Targets.EngineeringBuildIdentityV1
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Near
import ProofForgeV2.Targets.Noir
import ProofForgeV2.Targets.Psy
import ProofForgeV2.Targets.Psy.FinalizeV1
import ProofForgeV2.Targets.Aleo
import ProofForgeV2.Targets.Aleo.FinalizeV1
import ProofForgeV2.Targets.Evm.FinalizeV1
import ProofForgeV2.Targets.Near.FinalizeV1
import ProofForgeV2.Targets.Solana.FinalizeV1
import ProofForgeV2.Targets.Noir.FinalizeV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EngineeringBuildIdentityV1
open ProofForgeV2.Core.Common
open System

/-- All static registrations in canonical TargetId storage order (product seed). -/
def allRegistrations : CompileResult (Array TargetRegistrationDataV1) :=
  productRegistrations

def maturityLabel (target : TargetId) : CompileResult (Option String) := do
  let reg? ← registration? target
  return reg?.map (·.maturityLabel)

/-- Engineering descriptor for an implemented kind (shared DescriptorDataV1). -/
def descriptorForKind? : TargetKind → Option TargetDescriptor :=
  DescriptorDataV1.descriptorForKind?

/-- Engineering descriptor join via the product registration seed. -/
def descriptor? (target : TargetId) : CompileResult (Option TargetDescriptor) := do
  let reg? ← registration? target
  match reg? with
  | none => return none
  | some reg =>
      if reg.implemented then
        return descriptorForKind? reg.kind
      else
        return none

/-- M4/T9d: bind engineering Plan digest into identity.
    EVM/Solana/NEAR/Noir recompute target Plan schema digests; design-only
    targets bind `engineeringAbsentPlanDigestV1`. -/
private def planDigestForCapabilityV1
    (capability : ResolvedEngineeringBuildV1) : CompileResult Digest := do
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  match selection.kind with
  | .evm =>
      let plan ← Evm.planFromCapability capability
      match Evm.engineeringEvmPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: EVM plan digest failed: {e}"
  | .solana =>
      let plan ← Solana.planFromCapability capability
      match Solana.engineeringSolanaPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: Solana plan digest failed: {e}"
  | .near =>
      let plan ← Near.planFromCapability capability
      match Near.engineeringNearPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: NEAR plan digest failed: {e}"
  | .noir =>
      let plan ← Noir.planFromCapability capability
      match Noir.engineeringNoirPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: Noir plan digest failed: {e}"
  | _ =>
      match engineeringAbsentPlanDigestV1
          selection.targetId selection.codegenProfile with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: absent plan digest failed: {e}"

/-- Aggregate materialization consumes only the private engineering capability.
    Support was decided at `resolveEngineeringRequirementsV1`. All six target
    Plan bodies construct their plans from retained `SemanticProgramV1`;
    compiler, resolver, and artifact identity consume the same non-alpha
    `CompiledSemanticV1` source/semantic digests and program name.
    Target-owned Plan/IR/emit algorithms remain capability-gated; the aggregate
    product carrier is private-ctor `MaterializedArtifactsV1` (sole mint via
    `mintMaterializedArtifactsV1` after emit). M4 binds planDigest into identity.
    No residual Common resolve, no public makePlan, no public OutputSet/makeOutput
    product surface. Formal SupportClaim / OutputSetV1 remain pending. -/
def materializeResult (capability : ResolvedEngineeringBuildV1) :
    CompileResult MaterializedArtifactsV1 := do
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  let planDigest ← planDigestForCapabilityV1 capability
  match selection.kind with
  | .evm =>
      let files ← Evm.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Evm.descriptor files planDigest
  | .solana =>
      let files ← Solana.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Solana.descriptor files planDigest
  | .near =>
      let files ← Near.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Near.descriptor files planDigest
  | .noir =>
      let files ← Noir.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Noir.descriptor files planDigest
  | .aleo =>
      let files ← Aleo.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Aleo.descriptor files planDigest
  | .psy =>
      let files ← Psy.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Psy.descriptor files planDigest
  | other => .error <| .targetNotImplemented other

def materialize (capability : ResolvedEngineeringBuildV1) :
    IO MaterializedArtifactsV1 :=
  match materializeResult capability with
  | .ok output => pure output
  | .error error => throw <| IO.userError error.render

/-- Sole runtime finalization dispatch (D3/S7b).

    1. Pure capability↔artifacts identity bind (provisional empty-extra mint)
       before any target-owned tool IO — mismatched pairs fail closed without
       running solc/wat2wasm or writing staging extras.
    2. TargetKind → target-owned engineering IO adapters (may write extras).
    3. Second sole mint with tool-produced draft (extra path uniqueness).

    Callers (CLI publisher) must write pure base files from
    `MaterializedArtifactsV1` into `stagingDir` first. Pure `materializeResult`
    base-file contract is unchanged. Not formal OutputSetV1 / ToolchainIdentity. -/
def finalizeMaterializedArtifactsV1
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO FinalizedArtifactsV1 := do
  -- Pre-IO identity bind: share exact target/profile/kind/program/digest gates
  -- with empty extras so tool side-effects never run on mismatched pairs.
  let precheckDraft : EngineeringFinalizationDraftV1 := {
    deployable := false
    extraFiles := #[]
    evidenceNote := ""
  }
  match mintFinalizedArtifactsV1 capability artifacts precheckDraft with
  | .error error => throw <| IO.userError error.render
  | .ok _ => pure ()
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  let draft ← match selection.kind with
    | .evm =>
        Evm.FinalizeV1.finalize capability artifacts stagingDir
    | .near =>
        Near.FinalizeV1.finalize capability artifacts stagingDir
    | .solana =>
        Solana.FinalizeV1.finalize capability artifacts stagingDir
    | .noir =>
        Noir.FinalizeV1.finalize capability artifacts stagingDir
    | .aleo =>
        Aleo.FinalizeV1.finalize capability artifacts stagingDir
    | .psy =>
        Psy.FinalizeV1.finalize capability artifacts stagingDir
    | other =>
        pure ({
          deployable := false
          extraFiles := #[]
          evidenceNote := s!"{other} is research-only and has no V2 materializer"
        } : EngineeringFinalizationDraftV1)
  match mintFinalizedArtifactsV1 capability artifacts draft with
  | .ok finalized => pure finalized
  | .error error => throw <| IO.userError error.render

end ProofForgeV2.Targets

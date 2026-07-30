import ProofForgeV2.Targets.Evm
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Near
import ProofForgeV2.Targets.Noir
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

/-- Aggregate materialization consumes only the private engineering capability.
    Support was decided at `resolveEngineeringRequirementsV1`. All four target
    Plan bodies construct their S1 plans from retained `SemanticProgramV1`;
    compiler, resolver, and artifact identity consume the same non-alpha
    `CompiledSemanticV1` source/semantic digests and program name.
    Target-owned Plan/IR/emit algorithms remain capability-gated; the aggregate
    product carrier is private-ctor `MaterializedArtifactsV1` (sole mint via
    `mintMaterializedArtifactsV1` after emit). No residual Common resolve, no
    public makePlan, no public OutputSet/makeOutput product surface. Formal
    SupportClaim / OutputSetV1 and complete SemanticProgramV1-native lowering
    remain pending. -/
def materializeResult (capability : ResolvedEngineeringBuildV1) :
    CompileResult MaterializedArtifactsV1 := do
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  match selection.kind with
  | .evm =>
      let files ← Evm.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Evm.descriptor files
  | .solana =>
      let files ← Solana.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Solana.descriptor files
  | .near =>
      let files ← Near.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Near.descriptor files
  | .noir =>
      let files ← Noir.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Noir.descriptor files
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

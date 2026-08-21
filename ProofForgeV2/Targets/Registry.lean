import ProofForgeV2.Targets.Evm
import ProofForgeV2.Targets.Evm.PlanSchemaV1
import ProofForgeV2.Targets.Solana.PlanSchemaV1
import ProofForgeV2.Targets.Near.PlanSchemaV1
import ProofForgeV2.Targets.Noir.PlanSchemaV1
import ProofForgeV2.Targets.CosmWasm.PlanSchemaV1
import ProofForgeV2.Targets.Quint.PlanSchemaV1
import ProofForgeV2.Targets.Ton.PlanSchemaV1
import ProofForgeV2.Targets.Aleo.PlanSchemaV1
import ProofForgeV2.Targets.Soroban.PlanSchemaV1
import ProofForgeV2.Targets.Icp.PlanSchemaV1
import ProofForgeV2.Targets.OpenVM.PlanSchemaV1
import ProofForgeV2.Targets.Xrpl.PlanSchemaV1
import ProofForgeV2.Targets.EngineeringBuildIdentityV1
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Near
import ProofForgeV2.Targets.Noir
import ProofForgeV2.Targets.CosmWasm
import ProofForgeV2.Targets.Quint
import ProofForgeV2.Targets.Ton
import ProofForgeV2.Targets.Soroban
import ProofForgeV2.Targets.Icp
import ProofForgeV2.Targets.Psy
import ProofForgeV2.Targets.Psy.FinalizeV1
import ProofForgeV2.Targets.Aleo
import ProofForgeV2.Targets.Aleo.FinalizeV1
import ProofForgeV2.Targets.Soroban.FinalizeV1
import ProofForgeV2.Targets.Icp.FinalizeV1
import ProofForgeV2.Targets.OpenVM
import ProofForgeV2.Targets.OpenVM.FinalizeV1
import ProofForgeV2.Targets.Xrpl
import ProofForgeV2.Targets.Xrpl.FinalizeV1
import ProofForgeV2.Targets.Evm.FinalizeV1
import ProofForgeV2.Targets.Near.FinalizeV1
import ProofForgeV2.Targets.Solana.FinalizeV1
import ProofForgeV2.Targets.Noir.FinalizeV1
import ProofForgeV2.Targets.CosmWasm.FinalizeV1
import ProofForgeV2.Targets.Quint.FinalizeV1
import ProofForgeV2.Targets.Ton.FinalizeV1
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

def engineeringValidationLabel (target : TargetId) : CompileResult (Option String) := do
  let reg? ← registration? target
  return reg?.map (·.engineeringValidationLabel)

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

/-- M4/T9d/ALEO-I1: bind engineering Plan digest into identity.
    EVM/Solana/NEAR/Noir/CosmWasm/Quint/TON/Aleo/Soroban/ICP/OpenVM recompute
    target Plan schema digests from capability; Psy (and any residual
    design-only targets) bind `engineeringAbsentPlanDigestV1`. -/
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
      -- #125: tagged Plan sum — legacy schema digest vs CPI carrier digest.
      -- CPI must not re-enter the legacy Plan schema encoder / gate.
      let plan ← Solana.planFromCapability capability
      match Solana.engineeringSolanaMaterializationPlanDigestV1 plan with
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
  | .cosmwasm =>
      let plan ← CosmWasm.planFromCapability capability
      match CosmWasm.engineeringCosmWasmPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: CosmWasm plan digest failed: {e}"
  | .quint =>
      let plan ← Quint.planFromCapability capability
      match Quint.engineeringQuintPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: Quint plan digest failed: {e}"
  | .ton =>
      let plan ← Ton.planFromCapability capability
      match Ton.engineeringTonPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: Ton plan digest failed: {e}"
  | .aleo =>
      let plan ← Aleo.planFromCapability capability
      match Aleo.engineeringAleoPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: Aleo plan digest failed: {e}"
  | .soroban =>
      let plan ← Soroban.planFromCapability capability
      match Soroban.engineeringSorobanPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: Soroban plan digest failed: {e}"
  | .icp =>
      let plan ← Icp.planFromCapability capability
      match Icp.engineeringIcpPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: ICP plan digest failed: {e}"
  | .openvm =>
      let plan ← OpenVM.planFromCapability capability
      match OpenVM.engineeringOpenVmPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: OpenVM plan digest failed: {e}"
  | .xrpl =>
      let plan ← Xrpl.planFromCapability capability
      match Xrpl.engineeringXrplPlanDigestV1 plan with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: XRPL plan digest failed: {e}"
  | _ =>
      match engineeringAbsentPlanDigestV1
          selection.targetId selection.codegenProfile with
      | .ok d => pure (d : Digest)
      | .error e =>
          throw <| .invalidProgram s!"materialize: absent plan digest failed: {e}"

/-- Aggregate materialization consumes only the private engineering capability.
    Support was decided at `resolveEngineeringRequirementsV1`. All twelve target
    Plan bodies construct their plans from retained `SemanticProgramV1`;
    compiler, resolver, and artifact identity consume the same non-alpha
    `CompiledSemanticV1` source/semantic digests and program name.
    Target-owned Plan/IR/emit algorithms remain capability-gated; the aggregate
    product carrier is private-ctor `MaterializedArtifactsV1` (sole mint via
    `mintMaterializedArtifactsV1` after emit). M4 binds planDigest into identity.
    No residual Common resolve, no public makePlan, no public OutputSet/makeOutput
    product surface. Formal SupportClaim / OutputSetV1 remain pending.

    Pure materialize. Aleo emits Instructions plus its query descriptor; Psy
    emits DPN JSON. Neither target has a source-language debug lane. -/
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
  | .cosmwasm =>
      let files ← CosmWasm.buildFromCapability capability
      mintMaterializedArtifactsV1 capability CosmWasm.descriptor files planDigest
  | .quint =>
      let files ← Quint.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Quint.descriptor files planDigest
  | .ton =>
      let files ← Ton.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Ton.descriptor files planDigest
  | .aleo =>
      let files ← Aleo.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Aleo.descriptor files planDigest
  | .soroban =>
      let files ← Soroban.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Soroban.descriptor files planDigest
  | .icp =>
      let files ← Icp.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Icp.descriptor files planDigest
  | .psy =>
      let files ← Psy.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Psy.descriptor files planDigest
  | .openvm =>
      let files ← OpenVM.buildFromCapability capability
      mintMaterializedArtifactsV1 capability OpenVM.descriptor files planDigest
  | .xrpl =>
      let files ← Xrpl.buildFromCapability capability
      mintMaterializedArtifactsV1 capability Xrpl.descriptor files planDigest

/-- IO wrapper over the sole pure materializer. -/
def materialize (capability : ResolvedEngineeringBuildV1) :
    IO MaterializedArtifactsV1 := do
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
    | .cosmwasm =>
        CosmWasm.FinalizeV1.finalize capability artifacts stagingDir
    | .quint =>
        Quint.FinalizeV1.finalize capability artifacts stagingDir
    | .ton =>
        Ton.FinalizeV1.finalize capability artifacts stagingDir
    | .aleo =>
        Aleo.FinalizeV1.finalize capability artifacts stagingDir
    | .soroban =>
        Soroban.FinalizeV1.finalize capability artifacts stagingDir
    | .icp =>
        Icp.FinalizeV1.finalize capability artifacts stagingDir
    | .psy =>
        Psy.FinalizeV1.finalize capability artifacts stagingDir
    | .openvm =>
        OpenVM.FinalizeV1.finalize capability artifacts stagingDir
    | .xrpl =>
        Xrpl.FinalizeV1.finalize capability artifacts stagingDir
  match mintFinalizedArtifactsV1 capability artifacts draft with
  | .ok finalized => pure finalized
  | .error error => throw <| IO.userError error.render

end ProofForgeV2.Targets

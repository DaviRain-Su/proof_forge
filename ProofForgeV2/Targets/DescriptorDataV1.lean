/-
  Shared engineering TargetDescriptor data for the six implemented targets.

  Registry-owned `semanticsAxesOfKindV1` is the sole six-axis seed. This module
  adds only materializer/profile metadata and exposes the exact descriptor ↔
  registration join used before capability/artifact identity and inspection.
  Requirement support is intentionally absent: the engineering resolver index
  remains the sole current authority, while formal SupportClaim is pending.
-/
import ProofForgeV2.Materialization.Protocol
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Targets.TargetRegistryV1

namespace ProofForgeV2.Targets.DescriptorDataV1

open ProofForgeV2
open ProofForgeV2.Targets.TargetRegistryV1

private def descriptorFromRegistryAxes
    (kind : TargetKind)
    (artifactEncoding : ArtifactEncoding)
    (codegenProfile : CodegenProfileId) : TargetDescriptor :=
  let semantics := semanticsAxesOfKindV1 kind
  {
    targetId := semantics.targetId
    artifactEncoding
    executionHost := semantics.executionHost
    commitModel := semantics.commitModel
    stateBinding := semantics.stateBinding
    callModel := semantics.callModel
    proofModel := semantics.proofModel
    settlementModel := semantics.settlementModel
    codegenProfile
  }

def evm : TargetDescriptor :=
  descriptorFromRegistryAxes .evm .evmYul CodegenProfileId.evmYulSolc0834V1

def solana : TargetDescriptor :=
  -- Residual descriptor binds the default plan profile. The explicit ELF
  -- profile (`solana-sbpf-elf-v1`) is accepted by `acceptsCodegenProfile`
  -- without inventing a second TargetDescriptor table.
  descriptorFromRegistryAxes .solana .sbpfPlanText CodegenProfileId.solanaSbpfPlanV1

/-- Residual descriptor profile acceptance for multi-profile targets.
    `TargetDescriptor.codegenProfile` is the default encoding profile.
    Additional registered profiles for the same target are accepted here so
    capability mint and artifact identity can bind them without a second row. -/
def acceptsCodegenProfile (descriptor : TargetDescriptor) (profile : CodegenProfileId) : Bool :=
  descriptor.codegenProfile == profile ||
    (descriptor.targetId == TargetId.solana && profile == CodegenProfileId.solanaSbpfElfV1)

def near : TargetDescriptor :=
  descriptorFromRegistryAxes .near .wasmText CodegenProfileId.nearWasmRawU64V1

def noir : TargetDescriptor :=
  descriptorFromRegistryAxes .noir .noirSource CodegenProfileId.noirSourceU64RelationsV1

def aleo : TargetDescriptor :=
  descriptorFromRegistryAxes .aleo .leoSource CodegenProfileId.aleoLeoU64V1

def psy : TargetDescriptor :=
  descriptorFromRegistryAxes .psy .psySource CodegenProfileId.psyDargoU64V1

/-- Engineering descriptor for an implemented kind. Design-only kinds → none. -/
def descriptorForKind? : TargetKind → Option TargetDescriptor
  | .evm => some evm
  | .solana => some solana
  | .near => some near
  | .noir => some noir
  | .aleo => some aleo
  | .psy => some psy
  | _ => none

/-- Exact registry-owned six-axis join for an implemented descriptor.

    ArtifactEncoding is deliberately excluded: it belongs to target/profile
    materialization metadata, not TargetSemanticsAxesV1. Profile membership is
    checked separately by selection/`acceptsCodegenProfile`. -/
def validateDescriptorAxesJoinV1
    (registration : TargetRegistrationDataV1)
    (descriptor : TargetDescriptor) : CompileResult Unit := do
  unless registration.implemented do
    throw <| .registryInvalid
      s!"descriptor axes join requires implemented target '{registration.targetId}'"
  unless descriptor.targetId == registration.targetId &&
      descriptor.targetId == registration.semantics.targetId do
    throw <| .registryInvalid
      s!"descriptor target identity diverges from registry axes for '{registration.targetId}'"
  unless descriptor.executionHost == registration.semantics.executionHost do
    throw <| .registryInvalid
      s!"descriptor executionHost diverges from registry for '{registration.targetId}'"
  unless descriptor.commitModel == registration.semantics.commitModel do
    throw <| .registryInvalid
      s!"descriptor commitModel diverges from registry for '{registration.targetId}'"
  unless descriptor.stateBinding == registration.semantics.stateBinding do
    throw <| .registryInvalid
      s!"descriptor stateBinding diverges from registry for '{registration.targetId}'"
  unless descriptor.callModel == registration.semantics.callModel do
    throw <| .registryInvalid
      s!"descriptor callModel diverges from registry for '{registration.targetId}'"
  unless descriptor.proofModel == registration.semantics.proofModel do
    throw <| .registryInvalid
      s!"descriptor proofModel diverges from registry for '{registration.targetId}'"
  unless descriptor.settlementModel == registration.semantics.settlementModel do
    throw <| .registryInvalid
      s!"descriptor settlementModel diverges from registry for '{registration.targetId}'"

end ProofForgeV2.Targets.DescriptorDataV1

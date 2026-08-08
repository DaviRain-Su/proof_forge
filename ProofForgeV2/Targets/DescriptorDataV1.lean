/-
  Shared engineering TargetDescriptor data for nine registry-implemented entries.

  Registry-owned `semanticsAxesOfKindV1` is the sole six-axis seed. This module
  adds profile/artifact-encoding metadata and exposes the exact descriptor ↔
  registration join used before capability/artifact identity and inspection.
  All nine entries have target-owned materializers. Requirement support is
  intentionally absent: the engineering resolver index remains the sole current
  authority, while formal SupportClaim is pending.
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
  -- Residual descriptor binds the default legacy solc profile. The explicit
  -- Cancun profile (`evm-yul-solc-0.8.34-cancun-v1`) is accepted by
  -- `acceptsCodegenProfile` without inventing a second TargetDescriptor table.
  descriptorFromRegistryAxes .evm .evmYul CodegenProfileId.evmYulSolc0834V1

def solana : TargetDescriptor :=
  -- ADR-0032 U1: sole residual descriptor binds `solana-sbpf-cpi-elf-v1` only.
  -- plan-v1 / elf-v1 shims deleted (not accepted).
  descriptorFromRegistryAxes .solana .sbpfPlanText CodegenProfileId.solanaSbpfCpiElfV1

/-- Residual descriptor profile acceptance for multi-profile targets.
    `TargetDescriptor.codegenProfile` is the default encoding profile.
    Additional registered profiles for the same target are accepted here so
    capability mint and artifact identity can bind them without a second row.
    Solana: sole cpi-elf; EVM: default + Cancun; Aleo: default source + compile;
    Noir: default source + nargo ACIR dual-write; Psy: historical default +
    explicit locked-dargo VM profile. -/
def acceptsCodegenProfile (descriptor : TargetDescriptor) (profile : CodegenProfileId) : Bool :=
  descriptor.codegenProfile == profile ||
    (descriptor.targetId == TargetId.evm &&
      profile == CodegenProfileId.evmYulSolc0834CancunV1) ||
    (descriptor.targetId == TargetId.aleo &&
      profile == CodegenProfileId.aleoLeoU64CompileV1) ||
    (descriptor.targetId == TargetId.noir &&
      profile == CodegenProfileId.noirNargoAcirV1) ||
    (descriptor.targetId == TargetId.psy &&
      profile == CodegenProfileId.psyDargo010VmV1)

def near : TargetDescriptor :=
  descriptorFromRegistryAxes .near .wasmText CodegenProfileId.nearWasmRawU64V1

def noir : TargetDescriptor :=
  descriptorFromRegistryAxes .noir .noirSource CodegenProfileId.noirSourceU64RelationsV1

/-- Residual Aleo descriptor binds the default source profile
    (`aleo-leo-4.0.2-u64-v1`). The compile profile is accepted via
    `acceptsCodegenProfile` without inventing a second TargetDescriptor. -/
def aleo : TargetDescriptor :=
  descriptorFromRegistryAxes .aleo .leoSource CodegenProfileId.aleoLeoU64V1

def psy : TargetDescriptor :=
  descriptorFromRegistryAxes .psy .psySource CodegenProfileId.psyDargoU64V1

/-- Quint is a source-only executable state-model target. Product finalization
    emits `.qnt` but does not run Quint, Apalache, TLC, or a JVM. -/
def quint : TargetDescriptor :=
  descriptorFromRegistryAxes .quint .quintSource CodegenProfileId.quintSourceU64ModelV1

/-- CosmWasm descriptor for its target-owned Plan/IR/WAT materializer.
    It may share only deterministic Wasm encoding per ADR-0007; host/runtime
    semantics remain CosmWasm-owned and must not reuse the NEAR Plan. -/
def cosmwasm : TargetDescriptor :=
  descriptorFromRegistryAxes .cosmwasm .wasmText CodegenProfileId.cosmwasmWasmU64V1

/-- TON emits Tolk source compiled by the locked `tolk` to Fift/BoC
    (`ton-tolk-boc-v1`). Pure-async actor model: synchronous external calls
    fail closed; schedule maps to raw async out-messages. Plan/IR/state cell
    layout are TON-owned (family-tvm-stack-account; no Wasm/EVM Plan sharing). -/
def ton : TargetDescriptor :=
  descriptorFromRegistryAxes .ton .tolkSource CodegenProfileId.tonTolkBocV1

/-- Engineering descriptor for an implemented kind. Design-only kinds → none. -/
def descriptorForKind? : TargetKind → Option TargetDescriptor
  | .evm => some evm
  | .solana => some solana
  | .near => some near
  | .noir => some noir
  | .aleo => some aleo
  | .psy => some psy
  | .quint => some quint
  | .cosmwasm => some cosmwasm
  | .ton => some ton
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

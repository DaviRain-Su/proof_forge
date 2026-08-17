/-
  Shared engineering TargetDescriptor data for thirteen registry-implemented entries.

  Registry-owned `semanticsAxesOfKindV1` is the sole six-axis seed. This module
  adds profile/artifact-encoding metadata and exposes the exact descriptor ↔
  registration join used before capability/artifact identity and inspection.
  All thirteen entries have target-owned materializers. Requirement support is
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
  -- Residual descriptor tracks the product default (v1, hashed Map). Cancun
  -- is accepted via `acceptsCodegenProfile` without a second descriptor table.
  descriptorFromRegistryAxes .evm .evmYul CodegenProfileId.evmYulSolc0834V1

def solana : TargetDescriptor :=
  -- ADR-0032 U1: sole residual descriptor binds `solana-sbpf-cpi-elf-v1` only.
  -- plan-v1 / elf-v1 shims deleted (not accepted).
  descriptorFromRegistryAxes .solana .sbpfPlanText CodegenProfileId.solanaSbpfCpiElfV1

/-- Residual descriptor profile acceptance for multi-profile targets.
    `TargetDescriptor.codegenProfile` is the default encoding profile.
    EVM additionally admits Cancun; Noir admits the nargo ACIR profile; OpenVM
    admits the elf profile (ADR-0046 O1). -/
def acceptsCodegenProfile (descriptor : TargetDescriptor) (profile : CodegenProfileId) : Bool :=
  descriptor.codegenProfile == profile ||
    (descriptor.targetId == TargetId.evm &&
      profile == CodegenProfileId.evmYulSolc0834CancunV1) ||
    (descriptor.targetId == TargetId.noir &&
      profile == CodegenProfileId.noirNargoAcirV1) ||
    (descriptor.targetId == TargetId.openvm &&
      profile == CodegenProfileId.openvmGuestElfV1)

def near : TargetDescriptor :=
  descriptorFromRegistryAxes .near .wasmText CodegenProfileId.nearWasmRawU64V1

def noir : TargetDescriptor :=
  descriptorFromRegistryAxes .noir .noirSource CodegenProfileId.noirSourceU64RelationsV1

def aleo : TargetDescriptor :=
  descriptorFromRegistryAxes .aleo .aleoInstructions CodegenProfileId.aleoInstructionsV1

def psy : TargetDescriptor :=
  descriptorFromRegistryAxes .psy .psyDpn CodegenProfileId.psyDpnV1

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

/-- Soroban S0 (ADR-0044): source-only Soroban Rust dialect `.rs`. Zero-tool
    finalize; deployable=false. Must not reuse NEAR/CosmWasm Plan or claim Wasm. -/
def soroban : TargetDescriptor :=
  descriptorFromRegistryAxes .soroban .sorobanSource CodegenProfileId.sorobanSourceU64V1

/-- ICP canister descriptor (ADR-0047). Sole profile `icp-wasm-candid-u64-v1`.
    Actor/await commit semantics and Candid ABI are ICP-owned; may share only
    deterministic Wasm encoding with other Wasm hosts (ADR-0007). Sync call and
    portable emit stay fail closed; async is advertised at the resolver only. -/
def icp : TargetDescriptor :=
  descriptorFromRegistryAxes .icp .icpWasmCandid CodegenProfileId.icpWasmCandidU64V1

/-- OpenVM O0/O1: controlled Rust guest source template + catalog JSON.
    Default finalize zero-tool; elf profile may build via cargo-openvm (ADR-0045/0046). -/
def openvm : TargetDescriptor :=
  descriptorFromRegistryAxes .openvm .openvmGuestSource
    CodegenProfileId.openvmGuestSourceV1

/-- XRPL Q0/Q1 (ADR-0049/0050): Bedrock-shaped Rust dialect `.rs`.
    Default finalize zero-tool; wasm profile may build via ambient rustc.
    Must not reuse OpenVM/NEAR/Soroban Plan or claim AlphaNet / mainnet. -/
def xrpl : TargetDescriptor :=
  descriptorFromRegistryAxes .xrpl .xrplBedrockSource
    CodegenProfileId.xrplBedrockSourceU64V1

/-- Engineering descriptor for an implemented kind. -/
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
  | .soroban => some soroban
  | .icp => some icp
  | .openvm => some openvm
  | .xrpl => some xrpl

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

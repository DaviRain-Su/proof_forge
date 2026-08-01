/-
  Shared engineering TargetDescriptor data for the four implemented targets.

  Cycle-free leaf: Protocol + TargetIdentity only. Target Plan modules re-export
  the same values; there is no second source of truth. Requirement support is
  intentionally absent: the engineering resolver index is the sole current
  authority, while formal SupportClaim remains pending.
-/
import ProofForgeV2.Materialization.Protocol
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets.DescriptorDataV1

open ProofForgeV2

def evm : TargetDescriptor := {
  targetId := TargetId.evm
  artifactEncoding := .evmYul
  executionHost := .evm
  commitModel := .transactionAtomic
  stateBinding := .contractStorage
  callModel := .synchronous
  proofModel := .none
  settlementModel := .ethereum
  codegenProfile := CodegenProfileId.evmYulSolc0834V1
}

def solana : TargetDescriptor := {
  targetId := TargetId.solana
  artifactEncoding := .sbpfPlanText
  executionHost := .solanaRuntime
  commitModel := .instructionAtomic
  stateBinding := .explicitAccounts
  callModel := .cpi
  proofModel := .none
  settlementModel := .solana
  -- Residual descriptor binds the default plan profile. The explicit ELF
  -- profile (`solana-sbpf-elf-v1`) is accepted by `acceptsCodegenProfile`
  -- without inventing a second TargetDescriptor table.
  codegenProfile := CodegenProfileId.solanaSbpfPlanV1
}

/-- Residual descriptor profile acceptance for multi-profile targets.
    Residual `TargetDescriptor.codegenProfile` is the default encoding profile
    (describe-join / default selection). Additional registered profiles for the
    same target must be accepted here so capability mint and artifact identity
    can bind them without a second descriptor row. -/
def acceptsCodegenProfile (descriptor : TargetDescriptor) (profile : CodegenProfileId) : Bool :=
  descriptor.codegenProfile == profile ||
    (descriptor.targetId == TargetId.solana && profile == CodegenProfileId.solanaSbpfElfV1)

def near : TargetDescriptor := {
  targetId := TargetId.near
  artifactEncoding := .wasmText
  executionHost := .nearRuntime
  commitModel := .receiptLocal
  stateBinding := .hostKeyValue
  callModel := .asynchronousReceipt
  proofModel := .none
  settlementModel := .near
  codegenProfile := CodegenProfileId.nearWasmRawU64V1
}

def noir : TargetDescriptor := {
  targetId := TargetId.noir
  artifactEncoding := .noirSource
  executionHost := .circuit
  commitModel := .externalStateTransition
  stateBinding := .proofInputs
  callModel := .none
  proofModel := .circuitProof
  settlementModel := .externalVerifier
  codegenProfile := CodegenProfileId.noirSourceU64RelationsV1
}

def aleo : TargetDescriptor := {
  targetId := TargetId.aleo
  artifactEncoding := .leoSource
  executionHost := .zkApplicationChain
  commitModel := .transactionAtomic
  stateBinding := .recordsAndMappings
  callModel := .none
  proofModel := .applicationProof
  settlementModel := .aleo
  codegenProfile := CodegenProfileId.aleoLeoU64V1
}

/-- Psy descriptor: .psy source for the official dargo toolchain; user-partitioned
    state trees with local proving and network aggregation (ZK application chain). -/
def psy : TargetDescriptor := {
  targetId := TargetId.psy
  artifactEncoding := .psySource
  executionHost := .zkApplicationChain
  commitModel := .transactionAtomic
  stateBinding := .userPartitionedState
  callModel := .synchronous
  proofModel := .applicationProof
  settlementModel := .psy
  codegenProfile := CodegenProfileId.psyDargoU64V1
}

/-- Engineering descriptor for an implemented kind. Design-only kinds → none. -/
def descriptorForKind? : TargetKind → Option TargetDescriptor
  | .evm => some evm
  | .solana => some solana
  | .near => some near
  | .noir => some noir
  | .aleo => some aleo
  | .psy => some psy
  | _ => none

end ProofForgeV2.Targets.DescriptorDataV1

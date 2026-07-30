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
  codegenProfile := CodegenProfileId.solanaSbpfPlanV1
}

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

/-- Engineering descriptor for an implemented kind. Design-only kinds → none. -/
def descriptorForKind? : TargetKind → Option TargetDescriptor
  | .evm => some evm
  | .solana => some solana
  | .near => some near
  | .noir => some noir
  | _ => none

end ProofForgeV2.Targets.DescriptorDataV1

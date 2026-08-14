import ProofForgeV2.Targets.Solana.HandlerSemanticsV1
import ProofForgeV2.Targets.Solana.SbpfExecutionV1

/-!
# Solana SbpfHandlerJoinV1

Kernel-checkable join contracts between the bounded production `HandlerIR`
evaluator and execution of an identity-bound production `.s` artifact in the
pinned `SbpfSemantics` provider.

This module does not lower `HandlerIR` to sBPF and does not define another
business transition. `ExecutedHandlerSbpfJoinV1` requires equations for both
existing evaluators. The StateCell `get` path now has a complete 55-step sparse
provider certificate, but its lookup/read/store assumptions are not yet derived
from the identity-bound artifact and encoded Loader input. Until that binding
is closed, an engineering `#eval` observation is not an execution theorem.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Exact current production StateCell `.s` identity. This value is consumed by
    the strict source-byte identity gate; it is not an identity for a separately
    generated proof program. -/
def stateCellProductionSbpfSha256V1 : String :=
  "c93b1448aa782550b7643ccced44209c57df604a866c236552dadc5ac6a159c1"

/-- Exact part of the Loader V3 invocation visible to the bounded HandlerIR
    evaluator. Account key, lamports, and executable status are deliberately
    absent: `InvocationObservationV1` does not observe them. -/
def LoaderV3SingleAccountInvocationRelV1
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1) : Prop :=
  handlerInvocation = {
    accounts := #[{
      isDuplicate := false
      ownerCurrentProgram := loaderInvocation.owner == loaderInvocation.programId
      isSigner := loaderInvocation.isSigner
      isWritable := loaderInvocation.isWritable
      data := ⟨loaderInvocation.accountData⟩
    }]
    instructionData := ⟨loaderInvocation.instructionData⟩
  }

/-- The production StateCell single-account layout constants. Keeping this
    calculation in the kernel avoids a second handwritten offset table in the
    HandlerIR↔provider join. -/
theorem stateCellSingleAccountInputLayoutV1 :
    computeInputLayoutV1 16 = {
      exactDataLen := 16
      rentEpoch := 10352
      instructionDataLen := 10360
      instructionData := 10368
      acc1Header := none
    } := by
  rfl

/-- The canonical HandlerIR view invocation and Loader invocation expose the
    same account flags, bytes, and instruction data when owner and program id
    are identical. -/
theorem loaderV3SingleAccountInvocationRelV1_nullaryUInt64View
    (accountKey programId : Array UInt8)
    (accountData : ByteArray)
    (lamports discriminatorValue : UInt64) :
    LoaderV3SingleAccountInvocationRelV1
      (nullaryUInt64ViewInvocationV1 accountData discriminatorValue)
      {
        accountKey
        owner := programId
        programId
        lamports
        accountData := accountData.data
        instructionData := (encodeU64le discriminatorValue).data
      } := by
  simp [LoaderV3SingleAccountInvocationRelV1,
    nullaryUInt64ViewInvocationV1]

/-- The canonical HandlerIR unary invocation and Loader invocation expose the
    same account flags, bytes, and instruction data when owner and program id
    are identical. -/
theorem loaderV3SingleAccountInvocationRelV1_unaryUInt64
    (accountKey programId : Array UInt8)
    (accountData : ByteArray)
    (lamports discriminatorValue argument : UInt64)
    (isSigner isWritable : Bool) :
    LoaderV3SingleAccountInvocationRelV1
      (unaryUInt64InvocationV1 accountData discriminatorValue argument
        isSigner isWritable)
      {
        accountKey
        owner := programId
        programId
        lamports
        accountData := accountData.data
        instructionData :=
          ((encodeU64le discriminatorValue).append
            (encodeU64le argument)).data
        isSigner
        isWritable
      } := by
  simp [LoaderV3SingleAccountInvocationRelV1, unaryUInt64InvocationV1]
  apply ByteArray.ext
  rfl

/-- Exact observation agreement for the StateCell outcomes shared by the two
    existing evaluators. Success maps to sBPF status zero. Handler arithmetic
    overflow maps to the emitted nonzero status. Other Handler traps are not
    admitted by this first join contract.

    The final account-data window is compared with the Handler evaluator's
    committed/rolled-back post-account observation. -/
def HandlerSbpfObservationRelV1
    (expectedArtifactSha256 : String)
    (handler : HandlerObservationV1)
    (sbpf : SbpfExecutionObservationV1) : Prop :=
  sbpf.artifactSha256 = expectedArtifactSha256 ∧
  sbpf.finalAccountData = handler.postAccounts[0]?.map (·.data.data) ∧
  match handler.outcome with
  | .returned returnData =>
      sbpf.provider.outcome = .halted (BitVec.ofNat 64 0) ∧
      sbpf.provider.r0 = BitVec.ofNat 64 0 ∧
      sbpf.provider.returnData = (returnData.getD {}).data
  | .trapped (.arithmeticOverflow errorCode) =>
      sbpf.provider.outcome = .halted (BitVec.ofNat 64 errorCode) ∧
      sbpf.provider.r0 = BitVec.ofNat 64 errorCode ∧
      sbpf.provider.returnData = #[]
  | .trapped _ => False

theorem handlerSbpfObservationRelV1_returned_iff
    (expectedArtifactSha256 : String)
    (handler : HandlerObservationV1)
    (sbpf : SbpfExecutionObservationV1)
    (returnData : Option ByteArray)
    (houtcome : handler.outcome = .returned returnData) :
    HandlerSbpfObservationRelV1 expectedArtifactSha256 handler sbpf ↔
      sbpf.artifactSha256 = expectedArtifactSha256 ∧
      sbpf.finalAccountData = handler.postAccounts[0]?.map (·.data.data) ∧
      sbpf.provider.outcome = .halted (BitVec.ofNat 64 0) ∧
      sbpf.provider.r0 = BitVec.ofNat 64 0 ∧
      sbpf.provider.returnData = (returnData.getD {}).data := by
  simp [HandlerSbpfObservationRelV1, houtcome]

theorem handlerSbpfObservationRelV1_arithmeticOverflow_iff
    (expectedArtifactSha256 : String)
    (handler : HandlerObservationV1)
    (sbpf : SbpfExecutionObservationV1)
    (errorCode : Nat)
    (houtcome : handler.outcome = .trapped (.arithmeticOverflow errorCode)) :
    HandlerSbpfObservationRelV1 expectedArtifactSha256 handler sbpf ↔
      sbpf.artifactSha256 = expectedArtifactSha256 ∧
      sbpf.finalAccountData = handler.postAccounts[0]?.map (·.data.data) ∧
      sbpf.provider.outcome = .halted (BitVec.ofNat 64 errorCode) ∧
      sbpf.provider.r0 = BitVec.ofNat 64 errorCode ∧
      sbpf.provider.returnData = #[] := by
  simp [HandlerSbpfObservationRelV1, houtcome]

/-- A carrier can be minted only with equations for the actual bounded
    HandlerIR evaluator and the actual identity-bound provider execution API.
    It does not treat an executable engineering observation as a theorem. -/
structure ExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (fuel : Nat)
    (expectedArtifactSha256 : String) where
  invocationRel :
    LoaderV3SingleAccountInvocationRelV1 handlerInvocation loaderInvocation
  handlerObservation : HandlerObservationV1
  handlerExecution :
    observeHandlerIRV1 handlerIR handlerInvocation = handlerObservation
  sbpfObservation : SbpfExecutionObservationV1
  sbpfExecution :
    executeLoaderV3SingleAccountV1 bound loaderInvocation fuel =
      .ok sbpfObservation
  observationRel :
    HandlerSbpfObservationRelV1 expectedArtifactSha256 handlerObservation
      sbpfObservation

/-- StateCell specialization of the generic executed join carrier. -/
abbrev StateCellExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (fuel : Nat) :=
  ExecutedHandlerSbpfJoinV1 bound handlerIR handlerInvocation loaderInvocation
    fuel stateCellProductionSbpfSha256V1

/-- Composition boundary for the already-proved UInt64 Reference→HandlerIR
    success relation and the HandlerIR→provider observation relation. -/
structure UInt64ReferenceHandlerSbpfJoinV1
    (data : SemanticProgramDataV1)
    (typeId : TypeIdV1)
    (pre : LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (valueBytes : ByteArray)
    (handler : HandlerObservationV1)
    (expectedArtifactSha256 : String)
    (sbpf : SbpfExecutionObservationV1) : Prop where
  referenceHandler :
    UInt64ReturnedHandlerObservationRelV1 data typeId pre referenceOutcome
      valueBytes handler
  handlerSbpf :
    HandlerSbpfObservationRelV1 expectedArtifactSha256 handler sbpf

/-- The two joins compose without another state/effect evaluator: the provider
    return bytes equal the sole Reference return bytes, and its final account
    window equals the Handler invocation's unchanged view account. -/
theorem UInt64ReferenceHandlerSbpfJoinV1.provider_projection
    {data : SemanticProgramDataV1}
    {typeId : TypeIdV1}
    {pre : LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {valueBytes : ByteArray}
    {handler : HandlerObservationV1}
    {expectedArtifactSha256 : String}
    {sbpf : SbpfExecutionObservationV1}
    (join : UInt64ReferenceHandlerSbpfJoinV1 data typeId pre referenceOutcome
      valueBytes handler expectedArtifactSha256 sbpf) :
    referenceOutcome = .returned pre (some { typeId, valueBytes }) #[] ∧
    sbpf.artifactSha256 = expectedArtifactSha256 ∧
    sbpf.provider.outcome = .halted (BitVec.ofNat 64 0) ∧
    sbpf.provider.r0 = BitVec.ofNat 64 0 ∧
    ⟨sbpf.provider.returnData⟩ = valueBytes ∧
    sbpf.finalAccountData = handler.invocation.accounts[0]?.map (·.data.data) := by
  rcases join.referenceHandler with
    ⟨_, _, hreference, hhandlerOutcome, hpostAccounts⟩
  rcases join.handlerSbpf with ⟨hartifact, hfinal, hprovider⟩
  simp [hhandlerOutcome] at hprovider
  refine ⟨hreference, hartifact, hprovider.1, hprovider.2.1, ?_, ?_⟩
  · apply ByteArray.ext
    simpa [hhandlerOutcome] using hprovider.2.2
  · simpa [hpostAccounts] using hfinal

end ProofForgeV2.Targets.Solana

import ProofForgeV2.Targets.Solana.HandlerSemanticsV1
import ProofForgeV2.Targets.Solana.ProductionProviderV1
import ProofForgeV2.Targets.Solana.SbpfExecutionV1
import ProofForgeV2.Targets.Solana.SbpfStateCellGetV1
import ProofForgeV2.Targets.Solana.SbpfStateCellInitializeV1
import ProofForgeV2.Targets.Solana.SbpfStateCellIncrementV1
import ProofForgeV2.Targets.Solana.SbpfStateCellIncrementOverflowV1

/-!
# Solana SbpfHandlerJoinV1

Kernel-checkable join contracts between the bounded production `HandlerIR`
evaluator and execution of an identity-bound production `.s` artifact in the
pinned `SbpfSemantics` provider.

This module does not lower `HandlerIR` to sBPF and does not define another
business transition. `ExecutedHandlerSbpfJoinV1` requires equations for both
existing evaluators. The StateCell `get` path now has a complete 55-step sparse
provider certificate, executable artifact/input checks, and a proof-bearing
provider store derivation behind one sound trace gate. A second sound gate now
projects the real encoder and `executeLoaderV3SingleAccountV1` equation. The
certified join gate additionally checks invocation/observation agreement and its
soundness mints the executed carrier with provider witnesses. The remaining
production boundary is to discharge that gate in a kernel proof and apply the
existing Reference→Handler proof; an engineering success alone is not that
unconditional refinement theorem.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

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

instance (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1) :
    Decidable
      (LoaderV3SingleAccountInvocationRelV1 handlerInvocation loaderInvocation) := by
  unfold LoaderV3SingleAccountInvocationRelV1
  infer_instance

def checkLoaderV3SingleAccountInvocationRelV1
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1) : Bool :=
  decide (LoaderV3SingleAccountInvocationRelV1 handlerInvocation loaderInvocation)

theorem checkLoaderV3SingleAccountInvocationRelV1_eq_true_iff
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1) :
    checkLoaderV3SingleAccountInvocationRelV1 handlerInvocation loaderInvocation = true ↔
      LoaderV3SingleAccountInvocationRelV1 handlerInvocation loaderInvocation := by
  simp [checkLoaderV3SingleAccountInvocationRelV1]

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

instance (expectedArtifactSha256 : String)
    (handler : HandlerObservationV1)
    (sbpf : SbpfExecutionObservationV1) :
    Decidable
      (HandlerSbpfObservationRelV1 expectedArtifactSha256 handler sbpf) := by
  unfold HandlerSbpfObservationRelV1
  cases handler.outcome with
  | returned returnData => infer_instance
  | trapped error => cases error <;> infer_instance

def checkHandlerSbpfObservationRelV1
    (expectedArtifactSha256 : String)
    (handler : HandlerObservationV1)
    (sbpf : SbpfExecutionObservationV1) : Bool :=
  decide (HandlerSbpfObservationRelV1 expectedArtifactSha256 handler sbpf)

theorem checkHandlerSbpfObservationRelV1_eq_true_iff
    (expectedArtifactSha256 : String)
    (handler : HandlerObservationV1)
    (sbpf : SbpfExecutionObservationV1) :
    checkHandlerSbpfObservationRelV1 expectedArtifactSha256 handler sbpf = true ↔
      HandlerSbpfObservationRelV1 expectedArtifactSha256 handler sbpf := by
  simp [checkHandlerSbpfObservationRelV1]

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

/-- Executable gate for the generic StateCell HandlerIR/provider join.
    This does not retain a sparse provider certificate; the `get` path keeps
    its dedicated 55-step checker below. -/
def checkStateCellExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (fuel : Nat := defaultSbpfExecutionFuelV1) : Bool :=
  let handlerObservation := observeHandlerIRV1 handlerIR handlerInvocation
  checkLoaderV3SingleAccountInvocationRelV1 handlerInvocation loaderInvocation &&
    match executeLoaderV3SingleAccountV1 bound loaderInvocation fuel with
    | .error _ => false
    | .ok sbpfObservation =>
        checkHandlerSbpfObservationRelV1 stateCellProductionSbpfSha256V1
          handlerObservation sbpfObservation

theorem checkStateCellExecutedHandlerSbpfJoinV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (fuel : Nat)
    (checked : checkStateCellExecutedHandlerSbpfJoinV1 bound handlerIR
      handlerInvocation loaderInvocation fuel = true) :
    Nonempty (StateCellExecutedHandlerSbpfJoinV1 bound handlerIR
      handlerInvocation loaderInvocation fuel) := by
  unfold checkStateCellExecutedHandlerSbpfJoinV1 at checked
  cases hexecution :
      executeLoaderV3SingleAccountV1 bound loaderInvocation fuel with
  | error error => simp [hexecution] at checked
  | ok sbpfObservation =>
      rw [hexecution] at checked
      simp only [Bool.and_eq_true] at checked
      rcases checked with ⟨hinvocation, hobservation⟩
      exact ⟨{
        invocationRel :=
          (checkLoaderV3SingleAccountInvocationRelV1_eq_true_iff
            handlerInvocation loaderInvocation).mp hinvocation
        handlerObservation := observeHandlerIRV1 handlerIR handlerInvocation
        handlerExecution := rfl
        sbpfObservation
        sbpfExecution := hexecution
        observationRel :=
          (checkHandlerSbpfObservationRelV1_eq_true_iff
            stateCellProductionSbpfSha256V1
            (observeHandlerIRV1 handlerIR handlerInvocation)
            sbpfObservation).mp hobservation
      }⟩

/-- StateCell `get` join retaining the provider certificate witnesses in
addition to the generic executed observation join. -/
structure CertifiedStateCellGetExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (returnBytes : Array UInt8)
    (value : SbpfSemantics.Word) where
  input : Array UInt8
  machine : SbpfSemantics.Machine
  execution : CertifiedSolanaProductionProviderExecutionV1 bound
    loaderInvocation 55 0 accountDataOffsetV1 16 input machine
  sourceIdentity :
    (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256 =
      stateCellProductionSbpfSha256V1
  providerReturned : StateCellGetReturnedV1 input returnBytes machine
  executed :
    StateCellExecutedHandlerSbpfJoinV1 bound handlerIR handlerInvocation
      loaderInvocation 55

namespace CertifiedStateCellGetExecutedHandlerSbpfJoinV1

def encodedInput
    (join : CertifiedStateCellGetExecutedHandlerSbpfJoinV1 bound handlerIR
      handlerInvocation loaderInvocation returnBytes value) :
    encodeLoaderV3SingleAccountInputV1 bound loaderInvocation = .ok join.input :=
  join.execution.encodedInput

def providerExecution
    (join : CertifiedStateCellGetExecutedHandlerSbpfJoinV1 bound handlerIR
      handlerInvocation loaderInvocation returnBytes value) :
    executeLoaderV3SingleAccountV1 bound loaderInvocation 55 = .ok {
      artifactSha256 :=
        (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256
      provider := SbpfSemantics.observe join.machine (.halted 0)
      finalAccountData := join.machine.mem.readBytes
        (SbpfSemantics.inputStart +
          BitVec.ofNat 64 accountDataOffsetV1) 16
    } :=
  join.execution.providerExecution

end CertifiedStateCellGetExecutedHandlerSbpfJoinV1

/-- Executable gate for the complete StateCell `get` HandlerIR/provider join.
    It requires the certified provider execution gate as well as exact
    invocation and observation agreement. -/
def checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (returnBytes : Array UInt8)
    (value : SbpfSemantics.Word) : Bool :=
  let handlerObservation := observeHandlerIRV1 handlerIR handlerInvocation
  checkLoaderV3SingleAccountInvocationRelV1 handlerInvocation loaderInvocation &&
    (checkStateCellGetExecutionV1 bound loaderInvocation returnBytes value &&
      match executeLoaderV3SingleAccountV1 bound loaderInvocation 55 with
      | .error _ => false
      | .ok sbpfObservation =>
          checkHandlerSbpfObservationRelV1 stateCellProductionSbpfSha256V1
            handlerObservation sbpfObservation)

/-- Soundness of the complete executed-join gate. Successful checking mints the
generic join carrier while retaining the exact identity, encoder, and returned
provider-machine witnesses from the 55-step certificate. -/
theorem checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (returnBytes : Array UInt8)
    (value : SbpfSemantics.Word)
    (checked : checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1 bound
      handlerIR handlerInvocation loaderInvocation returnBytes value = true) :
    Nonempty (CertifiedStateCellGetExecutedHandlerSbpfJoinV1 bound handlerIR
      handlerInvocation loaderInvocation returnBytes value) := by
  unfold checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1 at checked
  cases hexecution :
      executeLoaderV3SingleAccountV1 bound loaderInvocation 55 with
  | error error => simp [hexecution] at checked
  | ok sbpfObservation =>
      rw [hexecution] at checked
      simp only [Bool.and_eq_true] at checked
      rcases checked with ⟨hinvocation, hprovider, hobservation⟩
      have invocationRel :=
        (checkLoaderV3SingleAccountInvocationRelV1_eq_true_iff
          handlerInvocation loaderInvocation).mp hinvocation
      have observationRel :=
        (checkHandlerSbpfObservationRelV1_eq_true_iff
          stateCellProductionSbpfSha256V1
          (observeHandlerIRV1 handlerIR handlerInvocation) sbpfObservation).mp
            hobservation
      rcases checkStateCellGetExecutionV1_sound bound loaderInvocation
          returnBytes value hprovider with
        ⟨hidentity, input, machine, hencoded, hcertifiedExecution,
          machineReturned⟩
      exact ⟨{
        input
        machine
        execution := {
          encodedInput := hencoded
          providerExecution := hcertifiedExecution
        }
        sourceIdentity := hidentity
        providerReturned := machineReturned
        executed := {
          invocationRel
          handlerObservation := observeHandlerIRV1 handlerIR handlerInvocation
          handlerExecution := rfl
          sbpfObservation
          sbpfExecution := hexecution
          observationRel
        }
      }⟩

/-- StateCell `initialize` join retaining the exact 55-step provider
    certificate in addition to the generic executed observation join. -/
structure CertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (argument : SbpfSemantics.Word) where
  provider :
    CertifiedStateCellInitializeExecutionV1 bound loaderInvocation argument
  executed :
    StateCellExecutedHandlerSbpfJoinV1 bound handlerIR handlerInvocation
      loaderInvocation 55

/-- Executable gate combining the initialize sparse provider certificate with
    exact HandlerIR invocation and observation agreement. -/
def checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (argument : SbpfSemantics.Word) : Bool :=
  let handlerObservation := observeHandlerIRV1 handlerIR handlerInvocation
  checkLoaderV3SingleAccountInvocationRelV1 handlerInvocation loaderInvocation &&
    (checkStateCellInitializeExecutionV1 bound loaderInvocation argument &&
      match executeLoaderV3SingleAccountV1 bound loaderInvocation 55 with
      | .error _ => false
      | .ok sbpfObservation =>
          checkHandlerSbpfObservationRelV1 stateCellProductionSbpfSha256V1
            handlerObservation sbpfObservation)

/-- Soundness of the certified initialize HandlerIR/provider join. -/
theorem checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (argument : SbpfSemantics.Word)
    (checked : checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
      bound handlerIR handlerInvocation loaderInvocation argument = true) :
    Nonempty (CertifiedStateCellInitializeExecutedHandlerSbpfJoinV1 bound
      handlerIR handlerInvocation loaderInvocation argument) := by
  unfold checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1 at checked
  cases hexecution :
      executeLoaderV3SingleAccountV1 bound loaderInvocation 55 with
  | error error => simp [hexecution] at checked
  | ok sbpfObservation =>
      rw [hexecution] at checked
      simp only [Bool.and_eq_true] at checked
      rcases checked with ⟨hinvocation, hprovider, hobservation⟩
      rcases checkStateCellInitializeExecutionV1_sound bound loaderInvocation
          argument hprovider with ⟨provider⟩
      have hinjected :
          sbpfObservation = {
            artifactSha256 :=
              (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256
            provider := SbpfSemantics.observe provider.certificate.machine
              (.halted 0)
            finalAccountData := provider.certificate.machine.mem.readBytes
              (SbpfSemantics.inputStart +
                BitVec.ofNat 64 accountDataOffsetV1) 16
          } := by
        exact Except.ok.inj (hexecution.symm.trans provider.providerExecution)
      subst sbpfObservation
      exact ⟨{
        provider
        executed := {
          invocationRel :=
            (checkLoaderV3SingleAccountInvocationRelV1_eq_true_iff
              handlerInvocation loaderInvocation).mp hinvocation
          handlerObservation := observeHandlerIRV1 handlerIR handlerInvocation
          handlerExecution := rfl
          sbpfObservation := {
            artifactSha256 :=
              (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256
            provider := SbpfSemantics.observe provider.certificate.machine
              (.halted 0)
            finalAccountData := provider.certificate.machine.mem.readBytes
              (SbpfSemantics.inputStart +
                BitVec.ofNat 64 accountDataOffsetV1) 16
          }
          sbpfExecution := provider.providerExecution
          observationRel :=
            (checkHandlerSbpfObservationRelV1_eq_true_iff
              stateCellProductionSbpfSha256V1
              (observeHandlerIRV1 handlerIR handlerInvocation) _).mp
                hobservation
        }
      }⟩

/-- StateCell successful `increment` join retaining the exact 70-step provider
    certificate in addition to the generic executed observation join. -/
structure CertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (before argument : SbpfSemantics.Word) where
  provider :
    CertifiedStateCellIncrementExecutionV1 bound loaderInvocation before
      argument
  executed :
    StateCellExecutedHandlerSbpfJoinV1 bound handlerIR handlerInvocation
      loaderInvocation 70

/-- Executable gate combining the increment-success sparse provider
    certificate with exact HandlerIR invocation and observation agreement. -/
def checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (before argument : SbpfSemantics.Word) : Bool :=
  let handlerObservation := observeHandlerIRV1 handlerIR handlerInvocation
  checkLoaderV3SingleAccountInvocationRelV1 handlerInvocation loaderInvocation &&
    (checkStateCellIncrementExecutionV1 bound loaderInvocation before argument &&
      match executeLoaderV3SingleAccountV1 bound loaderInvocation 70 with
      | .error _ => false
      | .ok sbpfObservation =>
          checkHandlerSbpfObservationRelV1 stateCellProductionSbpfSha256V1
            handlerObservation sbpfObservation)

/-- Soundness of the certified increment-success HandlerIR/provider join. -/
theorem checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (before argument : SbpfSemantics.Word)
    (checked : checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
      bound handlerIR handlerInvocation loaderInvocation before argument =
        true) :
    Nonempty (CertifiedStateCellIncrementExecutedHandlerSbpfJoinV1 bound
      handlerIR handlerInvocation loaderInvocation before argument) := by
  unfold checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1 at checked
  cases hexecution :
      executeLoaderV3SingleAccountV1 bound loaderInvocation 70 with
  | error error => simp [hexecution] at checked
  | ok sbpfObservation =>
      rw [hexecution] at checked
      simp only [Bool.and_eq_true] at checked
      rcases checked with ⟨hinvocation, hprovider, hobservation⟩
      rcases checkStateCellIncrementExecutionV1_sound bound loaderInvocation
          before argument hprovider with ⟨provider⟩
      have hinjected :
          sbpfObservation = {
            artifactSha256 :=
              (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256
            provider := SbpfSemantics.observe provider.certificate.machine
              (.halted 0)
            finalAccountData := provider.certificate.machine.mem.readBytes
              (SbpfSemantics.inputStart +
                BitVec.ofNat 64 accountDataOffsetV1) 16
          } := by
        exact Except.ok.inj (hexecution.symm.trans provider.providerExecution)
      subst sbpfObservation
      exact ⟨{
        provider
        executed := {
          invocationRel :=
            (checkLoaderV3SingleAccountInvocationRelV1_eq_true_iff
              handlerInvocation loaderInvocation).mp hinvocation
          handlerObservation := observeHandlerIRV1 handlerIR handlerInvocation
          handlerExecution := rfl
          sbpfObservation := {
            artifactSha256 :=
              (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256
            provider := SbpfSemantics.observe provider.certificate.machine
              (.halted 0)
            finalAccountData := provider.certificate.machine.mem.readBytes
              (SbpfSemantics.inputStart +
                BitVec.ofNat 64 accountDataOffsetV1) 16
          }
          sbpfExecution := provider.providerExecution
          observationRel :=
            (checkHandlerSbpfObservationRelV1_eq_true_iff
              stateCellProductionSbpfSha256V1
              (observeHandlerIRV1 handlerIR handlerInvocation) _).mp
                hobservation
        }
      }⟩

/-- StateCell `increment` overflow join retaining the exact 56-step provider
    certificate in addition to the generic executed observation join. -/
structure CertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (before argument : SbpfSemantics.Word) where
  provider :
    CertifiedStateCellIncrementOverflowExecutionV1 bound loaderInvocation
      before argument
  executed :
    StateCellExecutedHandlerSbpfJoinV1 bound handlerIR handlerInvocation
      loaderInvocation 56

/-- Executable gate combining the increment-overflow sparse provider
    certificate with exact HandlerIR invocation and observation agreement. -/
def checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (before argument : SbpfSemantics.Word) : Bool :=
  let handlerObservation := observeHandlerIRV1 handlerIR handlerInvocation
  checkLoaderV3SingleAccountInvocationRelV1 handlerInvocation loaderInvocation &&
    (checkStateCellIncrementOverflowExecutionV1 bound loaderInvocation before
      argument &&
      match executeLoaderV3SingleAccountV1 bound loaderInvocation 56 with
      | .error _ => false
      | .ok sbpfObservation =>
          checkHandlerSbpfObservationRelV1 stateCellProductionSbpfSha256V1
            handlerObservation sbpfObservation)

/-- Soundness of the certified increment-overflow HandlerIR/provider join. -/
theorem checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1_sound
    (bound : BoundResolvedSbpfArtifactV1)
    (handlerIR : HandlerIR)
    (handlerInvocation : InvocationObservationV1)
    (loaderInvocation : LoaderV3SingleAccountInvocationV1)
    (before argument : SbpfSemantics.Word)
    (checked : checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
      bound handlerIR handlerInvocation loaderInvocation before argument =
        true) :
    Nonempty (CertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
      bound handlerIR handlerInvocation loaderInvocation before argument) := by
  unfold checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1 at checked
  cases hexecution :
      executeLoaderV3SingleAccountV1 bound loaderInvocation 56 with
  | error error => simp [hexecution] at checked
  | ok sbpfObservation =>
      rw [hexecution] at checked
      simp only [Bool.and_eq_true] at checked
      rcases checked with ⟨hinvocation, hprovider, hobservation⟩
      rcases checkStateCellIncrementOverflowExecutionV1_sound bound
          loaderInvocation before argument hprovider with ⟨provider⟩
      have hinjected :
          sbpfObservation = {
            artifactSha256 :=
              (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256
            provider := SbpfSemantics.observe provider.certificate.machine
              (.halted stateCellIncrementOverflowStatusV1)
            finalAccountData := provider.certificate.machine.mem.readBytes
              (SbpfSemantics.inputStart +
                BitVec.ofNat 64 accountDataOffsetV1) 16
          } := by
        exact Except.ok.inj (hexecution.symm.trans provider.providerExecution)
      subst sbpfObservation
      exact ⟨{
        provider
        executed := {
          invocationRel :=
            (checkLoaderV3SingleAccountInvocationRelV1_eq_true_iff
              handlerInvocation loaderInvocation).mp hinvocation
          handlerObservation := observeHandlerIRV1 handlerIR handlerInvocation
          handlerExecution := rfl
          sbpfObservation := {
            artifactSha256 :=
              (BoundResolvedSbpfArtifactV1.resolvedOf bound).sourceSha256
            provider := SbpfSemantics.observe provider.certificate.machine
              (.halted stateCellIncrementOverflowStatusV1)
            finalAccountData := provider.certificate.machine.mem.readBytes
              (SbpfSemantics.inputStart +
                BitVec.ofNat 64 accountDataOffsetV1) 16
          }
          sbpfExecution := provider.providerExecution
          observationRel :=
            (checkHandlerSbpfObservationRelV1_eq_true_iff
              stateCellProductionSbpfSha256V1
              (observeHandlerIRV1 handlerIR handlerInvocation) _).mp
                hobservation
        }
      }⟩

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

/-- Compose a certified StateCell provider join with any existing UInt64
Reference→Handler observation proof. No additional evaluator or transition is
introduced at this boundary. -/
theorem CertifiedStateCellGetExecutedHandlerSbpfJoinV1.referenceJoin
    {bound : BoundResolvedSbpfArtifactV1}
    {handlerIR : HandlerIR}
    {handlerInvocation : InvocationObservationV1}
    {loaderInvocation : LoaderV3SingleAccountInvocationV1}
    {returnBytes : Array UInt8}
    {value : SbpfSemantics.Word}
    {data : SemanticProgramDataV1}
    {typeId : TypeIdV1}
    {pre : LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {valueBytes : ByteArray}
    (certified : CertifiedStateCellGetExecutedHandlerSbpfJoinV1 bound handlerIR
      handlerInvocation loaderInvocation returnBytes value)
    (referenceHandler : UInt64ReturnedHandlerObservationRelV1 data typeId pre
      referenceOutcome valueBytes certified.executed.handlerObservation) :
    UInt64ReferenceHandlerSbpfJoinV1 data typeId pre referenceOutcome valueBytes
      certified.executed.handlerObservation stateCellProductionSbpfSha256V1
      certified.executed.sbpfObservation :=
  ⟨referenceHandler, certified.executed.observationRel⟩

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

/-- End-to-end composition carrier for the one-field UInt64 initializer. It
    stores the existing Reference→HandlerIR relation beside the certified
    HandlerIR→provider relation; it does not execute either layer again. -/
structure UInt64InitializerReferenceHandlerSbpfJoinV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (post : LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (postData : ByteArray)
    (argument : UInt64)
    (handler : HandlerObservationV1)
    (expectedArtifactSha256 : String)
    (sbpf : SbpfExecutionObservationV1) : Prop where
  referenceHandler :
    UInt64InitializerReturnedHandlerObservationRelV1 data plan binding post
      referenceOutcome postData argument handler
  handlerSbpf :
    HandlerSbpfObservationRelV1 expectedArtifactSha256 handler sbpf

/-- Compose the exact certified initialize provider execution with an existing
    Reference→HandlerIR initializer proof. -/
theorem CertifiedStateCellInitializeExecutedHandlerSbpfJoinV1.referenceJoin
    {bound : BoundResolvedSbpfArtifactV1}
    {handlerIR : HandlerIR}
    {handlerInvocation : InvocationObservationV1}
    {loaderInvocation : LoaderV3SingleAccountInvocationV1}
    {argumentWord : SbpfSemantics.Word}
    {data : SemanticProgramDataV1}
    {plan : Plan}
    {binding : UInt64StateAccountBindingV1}
    {post : LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {postData : ByteArray}
    {argument : UInt64}
    (certified : CertifiedStateCellInitializeExecutedHandlerSbpfJoinV1 bound
      handlerIR handlerInvocation loaderInvocation argumentWord)
    (referenceHandler : UInt64InitializerReturnedHandlerObservationRelV1 data
      plan binding post referenceOutcome postData argument
      certified.executed.handlerObservation) :
    UInt64InitializerReferenceHandlerSbpfJoinV1 data plan binding post
      referenceOutcome postData argument certified.executed.handlerObservation
      stateCellProductionSbpfSha256V1 certified.executed.sbpfObservation :=
  ⟨referenceHandler, certified.executed.observationRel⟩

/-- Observable initializer consequences of the composed proof: the provider
    halts successfully, publishes no return data, and commits exactly the bytes
    related to the sole Reference post-state. -/
theorem UInt64InitializerReferenceHandlerSbpfJoinV1.provider_projection
    {data : SemanticProgramDataV1}
    {plan : Plan}
    {binding : UInt64StateAccountBindingV1}
    {post : LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {postData : ByteArray}
    {argument : UInt64}
    {handler : HandlerObservationV1}
    {expectedArtifactSha256 : String}
    {sbpf : SbpfExecutionObservationV1}
    (join : UInt64InitializerReferenceHandlerSbpfJoinV1 data plan binding post
      referenceOutcome postData argument handler expectedArtifactSha256 sbpf) :
    referenceOutcome = .returned post none #[] ∧
    sbpf.artifactSha256 = expectedArtifactSha256 ∧
    sbpf.provider.outcome = .halted (BitVec.ofNat 64 0) ∧
    sbpf.provider.r0 = BitVec.ofNat 64 0 ∧
    sbpf.provider.returnData = #[] ∧
    sbpf.finalAccountData = some postData.data ∧
    UInt64LogicalStateAccountRelV1 data plan binding post postData argument := by
  rcases join.referenceHandler with
    ⟨hreference, hhandlerOutcome, hpostAccount, hstate⟩
  rcases (handlerSbpfObservationRelV1_returned_iff
      expectedArtifactSha256 handler sbpf none hhandlerOutcome).mp
      join.handlerSbpf with
    ⟨hartifact, hfinal, houtcome, hr0, hreturn⟩
  have hpostBytes := congrArg (Option.map ByteArray.data) hpostAccount
  refine ⟨hreference, hartifact, houtcome, hr0, ?_, ?_, hstate⟩
  · simpa using hreturn
  · exact hfinal.trans (by
      simpa [Option.map_map] using hpostBytes)

/-- End-to-end composition carrier for successful one-field UInt64 checked
    addition. -/
structure UInt64CheckedAddReferenceHandlerSbpfJoinV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (post : LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (postData : ByteArray)
    (before argument : UInt64)
    (handler : HandlerObservationV1)
    (expectedArtifactSha256 : String)
    (sbpf : SbpfExecutionObservationV1) : Prop where
  referenceHandler :
    UInt64CheckedAddReturnedHandlerObservationRelV1 data plan binding post
      referenceOutcome postData before argument handler
  handlerSbpf :
    HandlerSbpfObservationRelV1 expectedArtifactSha256 handler sbpf

/-- Compose the exact certified increment-success provider execution with an
    existing Reference→HandlerIR checked-add proof. -/
theorem CertifiedStateCellIncrementExecutedHandlerSbpfJoinV1.referenceJoin
    {bound : BoundResolvedSbpfArtifactV1}
    {handlerIR : HandlerIR}
    {handlerInvocation : InvocationObservationV1}
    {loaderInvocation : LoaderV3SingleAccountInvocationV1}
    {beforeWord argumentWord : SbpfSemantics.Word}
    {data : SemanticProgramDataV1}
    {plan : Plan}
    {binding : UInt64StateAccountBindingV1}
    {post : LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {postData : ByteArray}
    {before argument : UInt64}
    (certified : CertifiedStateCellIncrementExecutedHandlerSbpfJoinV1 bound
      handlerIR handlerInvocation loaderInvocation beforeWord argumentWord)
    (referenceHandler : UInt64CheckedAddReturnedHandlerObservationRelV1 data
      plan binding post referenceOutcome postData before argument
      certified.executed.handlerObservation) :
    UInt64CheckedAddReferenceHandlerSbpfJoinV1 data plan binding post
      referenceOutcome postData before argument
      certified.executed.handlerObservation stateCellProductionSbpfSha256V1
      certified.executed.sbpfObservation :=
  ⟨referenceHandler, certified.executed.observationRel⟩

/-- Observable successful-increment consequences of the composed proof. -/
theorem UInt64CheckedAddReferenceHandlerSbpfJoinV1.provider_projection
    {data : SemanticProgramDataV1}
    {plan : Plan}
    {binding : UInt64StateAccountBindingV1}
    {post : LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {postData : ByteArray}
    {before argument : UInt64}
    {handler : HandlerObservationV1}
    {expectedArtifactSha256 : String}
    {sbpf : SbpfExecutionObservationV1}
    (join : UInt64CheckedAddReferenceHandlerSbpfJoinV1 data plan binding post
      referenceOutcome postData before argument handler
      expectedArtifactSha256 sbpf) :
    referenceOutcome = .returned post (some {
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le (before + argument)
    }) #[] ∧
    sbpf.artifactSha256 = expectedArtifactSha256 ∧
    sbpf.provider.outcome = .halted (BitVec.ofNat 64 0) ∧
    sbpf.provider.r0 = BitVec.ofNat 64 0 ∧
    sbpf.provider.returnData = (encodeU64le (before + argument)).data ∧
    sbpf.finalAccountData = some postData.data ∧
    UInt64LogicalStateAccountRelV1 data plan binding post postData
      (before + argument) := by
  rcases join.referenceHandler with
    ⟨hreference, hhandlerOutcome, hpostAccount, hstate⟩
  rcases (handlerSbpfObservationRelV1_returned_iff
      expectedArtifactSha256 handler sbpf
      (some (encodeU64le (before + argument))) hhandlerOutcome).mp
      join.handlerSbpf with
    ⟨hartifact, hfinal, houtcome, hr0, hreturn⟩
  have hpostBytes := congrArg (Option.map ByteArray.data) hpostAccount
  refine ⟨hreference, hartifact, houtcome, hr0, ?_, ?_, hstate⟩
  · simpa using hreturn
  · exact hfinal.trans (by
      simpa [Option.map_map] using hpostBytes)

/-- End-to-end composition carrier for one-field UInt64 checked-add overflow. -/
structure UInt64CheckedAddOverflowReferenceHandlerSbpfJoinV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (pre : LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (accountData : ByteArray)
    (before : UInt64)
    (handler : HandlerObservationV1)
    (expectedArtifactSha256 : String)
    (sbpf : SbpfExecutionObservationV1) : Prop where
  referenceHandler :
    UInt64CheckedAddOverflowHandlerObservationRelV1 data plan binding pre
      referenceOutcome accountData before handler
  handlerSbpf :
    HandlerSbpfObservationRelV1 expectedArtifactSha256 handler sbpf

/-- Compose the exact certified increment-overflow provider execution with an
    existing Reference→HandlerIR checked-add overflow proof. -/
theorem CertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1.referenceJoin
    {bound : BoundResolvedSbpfArtifactV1}
    {handlerIR : HandlerIR}
    {handlerInvocation : InvocationObservationV1}
    {loaderInvocation : LoaderV3SingleAccountInvocationV1}
    {beforeWord argumentWord : SbpfSemantics.Word}
    {data : SemanticProgramDataV1}
    {plan : Plan}
    {binding : UInt64StateAccountBindingV1}
    {pre : LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {accountData : ByteArray}
    {before : UInt64}
    (certified : CertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
      bound handlerIR handlerInvocation loaderInvocation beforeWord argumentWord)
    (referenceHandler : UInt64CheckedAddOverflowHandlerObservationRelV1 data
      plan binding pre referenceOutcome accountData before
      certified.executed.handlerObservation) :
    UInt64CheckedAddOverflowReferenceHandlerSbpfJoinV1 data plan binding pre
      referenceOutcome accountData before certified.executed.handlerObservation
      stateCellProductionSbpfSha256V1 certified.executed.sbpfObservation :=
  ⟨referenceHandler, certified.executed.observationRel⟩

/-- Observable overflow consequences of the composed proof: the Reference
    reverts to `pre`, and the provider emits `0x1001` while retaining the exact
    account snapshot and empty return data. -/
theorem UInt64CheckedAddOverflowReferenceHandlerSbpfJoinV1.provider_projection
    {data : SemanticProgramDataV1}
    {plan : Plan}
    {binding : UInt64StateAccountBindingV1}
    {pre : LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {accountData : ByteArray}
    {before : UInt64}
    {handler : HandlerObservationV1}
    {expectedArtifactSha256 : String}
    {sbpf : SbpfExecutionObservationV1}
    (join : UInt64CheckedAddOverflowReferenceHandlerSbpfJoinV1 data plan binding
      pre referenceOutcome accountData before handler expectedArtifactSha256
      sbpf) :
    referenceOutcome = .reverted (.standard .arithmeticOverflow) pre ∧
    sbpf.artifactSha256 = expectedArtifactSha256 ∧
    sbpf.provider.outcome =
      .halted (BitVec.ofNat 64 arithmeticOverflowError) ∧
    sbpf.provider.r0 = BitVec.ofNat 64 arithmeticOverflowError ∧
    sbpf.provider.returnData = #[] ∧
    sbpf.finalAccountData = some accountData.data ∧
    UInt64LogicalStateAccountRelV1 data plan binding pre accountData before := by
  rcases join.referenceHandler with
    ⟨hreference, hhandlerOutcome, hpostAccounts, hinvocationAccount, hstate⟩
  rcases (handlerSbpfObservationRelV1_arithmeticOverflow_iff
      expectedArtifactSha256 handler sbpf arithmeticOverflowError
      hhandlerOutcome).mp join.handlerSbpf with
    ⟨hartifact, hfinal, houtcome, hr0, hreturn⟩
  have hpostAccount : handler.postAccounts[0]?.map (·.data) =
      some accountData := by
    rw [hpostAccounts]
    exact hinvocationAccount
  have hpostBytes := congrArg (Option.map ByteArray.data) hpostAccount
  refine ⟨hreference, hartifact, houtcome, hr0, hreturn, ?_, hstate⟩
  exact hfinal.trans (by
    simpa [Option.map_map] using hpostBytes)

end ProofForgeV2.Targets.Solana

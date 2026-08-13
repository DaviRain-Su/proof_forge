import ProofForgeV2.Targets.Solana.StaticAlignmentV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1

/-!
# Solana HandlerSemanticsV1

One bounded evaluator for the production nullary UInt64 view recipe. This is a
target-IR refinement object, not a second interpreter for ProofForge DSL
callables. It models the selected Solana account/header/input/return boundary;
all unsupported checks and operations fail closed.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Semantic
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Minimal immutable account observation needed by the first Solana slice. -/
structure AccountObservationV1 where
  /-- True means this serialized account row aliases an earlier account. -/
  isDuplicate : Bool
  ownerCurrentProgram : Bool
  isSigner : Bool
  isWritable : Bool
  data : ByteArray
  deriving BEq, Repr

/-- Complete invocation observation for the selected handler recipe. The
    discriminator is the first eight instruction-data bytes. -/
structure InvocationObservationV1 where
  accounts : Array AccountObservationV1
  instructionData : ByteArray
  deriving BEq, Repr

inductive HandlerExecutionErrorV1 where
  | unsupportedDiscriminator
  | discriminatorMismatch
  | unsupportedOperation
  | accountShape
  | duplicateAccount
  | inputLength
  | ownerMismatch
  | dataLength
  | signerRequired
  | writableRequired
  | headerMismatch
  | memoryBounds
  | localOutOfBounds
  deriving BEq, Repr

private structure HandlerMachineV1 where
  locals : Array UInt64 := #[]
  returnData : Option ByteArray := none

/-- Exact bounded little-endian load used by header checks and `loadState`.
    The unsigned interpretation is the Reference machine's existing byte
    interpretation, not a Solana-owned scalar codec. -/
def readUInt64LEV1 (bytes : ByteArray) (offset : Nat) : Option UInt64 :=
  if offset + 8 ≤ bytes.size then
    some <| UInt64.ofNat <|
      leBytesToNatV1 (bytes.extract offset (offset + 8))
  else
    none

/-- The production dispatcher parses the retained 16-hex-character handler
    discriminator exactly as the sBPF emitter and compares it with the first
    eight instruction-data bytes before entering a handler. -/
private def runDispatchV1
    (handlerIR : HandlerIR)
    (invocation : InvocationObservationV1) :
    Except HandlerExecutionErrorV1 Unit :=
  match (discriminatorToLeU64V1 handlerIR.discriminator).toOption with
  | none => .error .unsupportedDiscriminator
  | some expected =>
      match readUInt64LEV1 invocation.instructionData 0 with
      | none => .error .inputLength
      | some observed =>
          if observed == expected then .ok () else .error .discriminatorMismatch

private def setLocalV1
    (machine : HandlerMachineV1)
    (index : Nat)
    (value : UInt64) : Except HandlerExecutionErrorV1 HandlerMachineV1 :=
  if index < machine.locals.size then
    .ok { machine with locals := machine.locals.set! index value }
  else if index == machine.locals.size then
    .ok { machine with locals := machine.locals.push value }
  else
    .error .localOutOfBounds

private def runCheckV1
    (invocation : InvocationObservationV1) :
    Check → Except HandlerExecutionErrorV1 Unit
  | .numAccounts count =>
      if invocation.accounts.size == count then .ok () else .error .accountShape
  | .accountNonDuplicate index =>
      match invocation.accounts[index]? with
      | some account =>
          if account.isDuplicate then .error .duplicateAccount else .ok ()
      | none => .error .accountShape
  | .instructionDataLen bytes =>
      if invocation.instructionData.size == bytes then .ok () else .error .inputLength
  | .ownerCurrentProgram index =>
      match invocation.accounts[index]? with
      | some account =>
          if account.ownerCurrentProgram then .ok () else .error .ownerMismatch
      | none => .error .accountShape
  | .accountDataLen index bytes =>
      match invocation.accounts[index]? with
      | some account =>
          if account.data.size == bytes then .ok () else .error .dataLength
      | none => .error .accountShape
  | .signer index =>
      match invocation.accounts[index]? with
      | some account =>
          if account.isSigner then .ok () else .error .signerRequired
      | none => .error .accountShape
  | .writable index =>
      match invocation.accounts[index]? with
      | some account =>
          if account.isWritable then .ok () else .error .writableRequired
      | none => .error .accountShape
  | .headerEquals index offset value =>
      match invocation.accounts[index]? with
      | some account =>
          match readUInt64LEV1 account.data offset with
          | some observed =>
              if observed == value then .ok () else .error .headerMismatch
          | none => .error .memoryBounds
      | none => .error .accountShape

private def runChecksV1
    (checks : List Check)
    (invocation : InvocationObservationV1) :
    Except HandlerExecutionErrorV1 Unit :=
  match checks with
  | [] => .ok ()
  | check :: rest => do
      runCheckV1 invocation check
      runChecksV1 rest invocation

private def runOperationV1
    (invocation : InvocationObservationV1)
    (machine : HandlerMachineV1) :
    Operation → Except HandlerExecutionErrorV1 HandlerMachineV1
  | .loadState destination accountIndex byteOffset =>
      match invocation.accounts[accountIndex]? with
      | some account =>
          match readUInt64LEV1 account.data byteOffset with
          | some value => setLocalV1 machine destination value
          | none => .error .memoryBounds
      | none => .error .accountShape
  | .setReturnData 8 source =>
      match machine.locals[source]? with
      | some value => .ok { machine with returnData := some (encodeU64le value) }
      | none => .error .localOutOfBounds
  | _ => .error .unsupportedOperation

private def runOperationsV1
    (operations : List Operation)
    (invocation : InvocationObservationV1)
    (machine : HandlerMachineV1 := {}) :
    Except HandlerExecutionErrorV1 HandlerMachineV1 :=
  match operations with
  | [] => .ok machine
  | operation :: rest => do
      let next ← runOperationV1 invocation machine operation
      runOperationsV1 rest invocation next

/-- Atomic target outcome. A trapped invocation returns no mutable account
    state because this first slice is read-only. -/
inductive HandlerExecutionOutcomeV1 where
  | returned (returnData : Option ByteArray)
  | trapped (error : HandlerExecutionErrorV1)
  deriving BEq, Repr

/-- The only evaluator for this bounded Solana handler recipe. -/
def executeHandlerIRV1
    (handlerIR : HandlerIR)
    (invocation : InvocationObservationV1) : HandlerExecutionOutcomeV1 :=
  match runDispatchV1 handlerIR invocation with
  | .error error => .trapped error
  | .ok _ =>
      match runChecksV1 handlerIR.checks.toList invocation with
      | .error error => .trapped error
      | .ok _ =>
          match runOperationsV1 handlerIR.operations.toList invocation with
          | .error error => .trapped error
          | .ok machine => .returned machine.returnData

/-- Read-only target observation derived from the bounded handler evaluator.
    `postAccounts` is explicit so the refinement relation states, rather than
    merely assumes, that this selected view recipe cannot commit account data. -/
structure HandlerObservationV1 where
  invocation : InvocationObservationV1
  outcome : HandlerExecutionOutcomeV1
  postAccounts : Array AccountObservationV1
  deriving BEq, Repr

/-- Observe one bounded HandlerIR execution. The selected recipe is read-only,
    so the only post-account observation is the supplied immutable snapshot. -/
def observeHandlerIRV1
    (handlerIR : HandlerIR)
    (invocation : InvocationObservationV1) : HandlerObservationV1 := {
  invocation
  outcome := executeHandlerIRV1 handlerIR invocation
  postAccounts := invocation.accounts
}

/-- Canonical account bytes for the production one-field UInt64 layout:
    8-byte initialized marker followed by the 8-byte state field. -/
def oneFieldUInt64AccountDataV1
    (initializedMarker value : UInt64) : ByteArray :=
  (encodeU64le initializedMarker).append (encodeU64le value)

/-- Canonical successful invocation observation for the selected production
    view. The instruction data contains exactly its 8-byte discriminator. -/
def nullaryUInt64ViewInvocationV1
    (accountData : ByteArray)
    (discriminatorValue : UInt64)
    (ownerCurrentProgram : Bool := true)
    (isDuplicate : Bool := false) : InvocationObservationV1 := {
  accounts := #[{
    isDuplicate
    ownerCurrentProgram
    isSigner := false
    isWritable := false
    data := accountData
  }]
  instructionData := encodeU64le discriminatorValue
}

/-- Representation relation joining the logical-state overlay selected by the
    sole Reference ready gate to the production single-account bytes consumed
    by the bounded Solana evaluator. -/
def InitializedUInt64AccountRelV1
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (overlay : Array ByteArray)
    (loadedBytes accountData : ByteArray)
    (value : UInt64) : Prop :=
  overlay[binding.semanticStateId.toNat]? = some loadedBytes ∧
  loadedBytes = encodeU64le value ∧
  accountData.size = plan.stateAccount.exactDataLen ∧
  readUInt64LEV1 accountData plan.stateAccount.headerOffset =
    some plan.stateAccount.initializedMarker ∧
  readUInt64LEV1 accountData binding.byteOffset = some value

/-- Exact successful-observation relation for the first Solana target slice.
    It exposes the sole Reference result, the target return, and unchanged
    account observations without defining another DSL state/effect machine. -/
def UInt64ReturnedHandlerObservationRelV1
    (data : SemanticProgramDataV1)
    (typeId : TypeIdV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (valueBytes : ByteArray)
    (observed : HandlerObservationV1) : Prop :=
  validateValueBytesV1 data.types typeId valueBytes = .ok () ∧
  valueBytes.size = 8 ∧
  referenceOutcome = .returned pre (some { typeId, valueBytes }) #[] ∧
  observed.outcome = .returned (some valueBytes) ∧
  observed.postAccounts = observed.invocation.accounts

/-- Production wire encoding is recovered by the bounded target load. -/
theorem readUInt64LEV1_encodeU64le
    (value : UInt64) :
    readUInt64LEV1 (encodeU64le value) 0 = some value := by
  rw [readUInt64LEV1]
  have hbound : 0 + 8 ≤ (encodeU64le value).size := by
    simp [encodeU64le_size]
  rw [if_pos hbound]
  have hextract : (encodeU64le value).extract 0 (0 + 8) =
      encodeU64le value := by
    simpa [encodeU64le_size] using
      (ByteArray.extract_zero_size (b := encodeU64le value))
  rw [hextract, leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat]

theorem oneFieldUInt64AccountDataV1_size
    (initializedMarker value : UInt64) :
    (oneFieldUInt64AccountDataV1 initializedMarker value).size = 16 := by
  simp [oneFieldUInt64AccountDataV1, encodeU64le_size]

theorem readUInt64LEV1_oneFieldUInt64AccountDataV1_header
    (initializedMarker value : UInt64) :
    readUInt64LEV1 (oneFieldUInt64AccountDataV1 initializedMarker value) 0 =
      some initializedMarker := by
  simp only [readUInt64LEV1, oneFieldUInt64AccountDataV1_size]
  have hbound : 0 + 8 ≤ 16 := by decide
  rw [if_pos hbound]
  have hextract :
      (oneFieldUInt64AccountDataV1 initializedMarker value).extract 0 8 =
        encodeU64le initializedMarker := by
    apply ByteArray.extract_append_eq_left
    simp [encodeU64le_size]
  rw [hextract, leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat]

theorem readUInt64LEV1_oneFieldUInt64AccountDataV1_field
    (initializedMarker value : UInt64) :
    readUInt64LEV1 (oneFieldUInt64AccountDataV1 initializedMarker value) 8 =
      some value := by
  simp only [readUInt64LEV1, oneFieldUInt64AccountDataV1_size]
  have hbound : 8 + 8 ≤ 16 := by decide
  rw [if_pos hbound]
  have hextract :
      (oneFieldUInt64AccountDataV1 initializedMarker value).extract 8 16 =
        encodeU64le value := by
    apply ByteArray.extract_append_eq_right
    · simp [encodeU64le_size]
    · simp [encodeU64le_size]
  rw [hextract, leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat]

/-- Exact execution of the statically aligned production view recipe. -/
theorem executeHandlerIRV1_of_nullaryUInt64ViewStaticAlignment
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (viewName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData : ByteArray)
    (discriminatorValue : UInt64)
    (value : UInt64)
    (halignment : NullaryUInt64ViewStaticAlignmentV1 data plan binding
      viewName discriminator handler handlerIR)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue)
    (hdataLength : accountData.size = plan.stateAccount.exactDataLen)
    (hheader : readUInt64LEV1 accountData plan.stateAccount.headerOffset =
      some plan.stateAccount.initializedMarker)
    (hfield : readUInt64LEV1 accountData binding.byteOffset = some value) :
    executeHandlerIRV1 handlerIR
      (nullaryUInt64ViewInvocationV1 accountData discriminatorValue) =
        .returned (some (encodeU64le value)) := by
  rw [halignment.handlerIRExact]
  simp [executeHandlerIRV1, runDispatchV1, runChecksV1, runCheckV1,
    runOperationsV1, runOperationV1, nullaryUInt64ViewInvocationV1,
    halignment.accountZero, hdiscriminator, readUInt64LEV1_encodeU64le,
    encodeU64le_size, hdataLength, hheader, hfield, setLocalV1,
    Except.toOption, Bind.bind, Except.bind]

/-- Wrong-width instruction data traps before the account load. -/
theorem executeHandlerIRV1_of_nullaryUInt64ViewStaticAlignment_wrong_input
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (viewName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData : ByteArray)
    (discriminatorValue : UInt64)
    (halignment : NullaryUInt64ViewStaticAlignmentV1 data plan binding
      viewName discriminator handler handlerIR)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue) :
    executeHandlerIRV1 handlerIR
      { (nullaryUInt64ViewInvocationV1 accountData discriminatorValue) with
        instructionData := ByteArray.empty } =
        .trapped .inputLength := by
  rw [halignment.handlerIRExact]
  simp [executeHandlerIRV1, runDispatchV1, readUInt64LEV1,
    hdiscriminator, Except.toOption]

/-- A different 8-byte discriminator fails in the dispatcher before checks
    or account-state loads. -/
theorem executeHandlerIRV1_of_nullaryUInt64ViewStaticAlignment_wrong_discriminator
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (viewName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData : ByteArray)
    (discriminatorValue otherDiscriminator : UInt64)
    (halignment : NullaryUInt64ViewStaticAlignmentV1 data plan binding
      viewName discriminator handler handlerIR)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue)
    (hne : otherDiscriminator ≠ discriminatorValue) :
    executeHandlerIRV1 handlerIR
      (nullaryUInt64ViewInvocationV1 accountData otherDiscriminator) =
        .trapped .discriminatorMismatch := by
  rw [halignment.handlerIRExact]
  simp [executeHandlerIRV1, runDispatchV1, nullaryUInt64ViewInvocationV1,
    hdiscriminator, readUInt64LEV1_encodeU64le, hne, Except.toOption]

/-- The Solana duplicate-account marker is checked, not approximated by array
    bounds. -/
theorem executeHandlerIRV1_of_nullaryUInt64ViewStaticAlignment_duplicate
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (viewName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData : ByteArray)
    (discriminatorValue : UInt64)
    (halignment : NullaryUInt64ViewStaticAlignmentV1 data plan binding
      viewName discriminator handler handlerIR)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue) :
    executeHandlerIRV1 handlerIR
      (nullaryUInt64ViewInvocationV1 accountData discriminatorValue true true) =
        .trapped .duplicateAccount := by
  rw [halignment.handlerIRExact]
  simp [executeHandlerIRV1, runDispatchV1, runChecksV1, runCheckV1,
    nullaryUInt64ViewInvocationV1, halignment.accountZero, hdiscriminator,
    readUInt64LEV1_encodeU64le, Except.toOption,
    Bind.bind, Except.bind]

/-- Owner mismatch fails before account-data/header observation. -/
theorem executeHandlerIRV1_of_nullaryUInt64ViewStaticAlignment_wrong_owner
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (viewName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData : ByteArray)
    (discriminatorValue : UInt64)
    (halignment : NullaryUInt64ViewStaticAlignmentV1 data plan binding
      viewName discriminator handler handlerIR)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue) :
    executeHandlerIRV1 handlerIR
      (nullaryUInt64ViewInvocationV1 accountData discriminatorValue false) =
        .trapped .ownerMismatch := by
  rw [halignment.handlerIRExact]
  simp [executeHandlerIRV1, runDispatchV1, runChecksV1, runCheckV1,
    nullaryUInt64ViewInvocationV1, halignment.accountZero, hdiscriminator,
    readUInt64LEV1_encodeU64le, encodeU64le_size, Except.toOption,
    Bind.bind, Except.bind]

/-- First kernel-checkable Reference→Solana HandlerIR refinement theorem.
    The target return and account stutter are derived from the bounded target
    evaluator; the Reference result comes from the sole Reference machine.

    This theorem does not cover the assembly emitter, sBPF ISA, ELF, loader,
    or Solana runtime. -/
theorem uint64ReturnedHandlerObservationRelV1_of_readyViewLoad_and_execution
    (admitted : AdmittedReferenceSliceV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (overlay : Array ByteArray)
    (loadedBytes : ByteArray)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (viewName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (callableId : CallableIdV1)
    (context : Array ContextInputV1)
    (vault : ReferenceVaultSeedV1)
    (accountData : ByteArray)
    (discriminatorValue value : UInt64)
    (halignment : NullaryUInt64ViewStaticAlignmentV1 data plan binding
      viewName discriminator handler handlerIR)
    (hadmittedData : admitted.data = data)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .view
          name := some viewName
          params := #[]
          result := {
            typeId := binding.semanticTypeId
            visibility := .public_
          }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[{
              result := some {
                valueId := 0
                typeId := binding.semanticTypeId
              }
              op := .stateLoad binding.semanticStateId
            }]
            terminator := .return_ (some 0)
          }]
          loopBounds := #[]
          invariantSteps := none
        } overlay context false)
    (haccount : InitializedUInt64AccountRelV1 plan binding overlay loadedBytes
      accountData value)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue) :
    UInt64ReturnedHandlerObservationRelV1 data binding.semanticTypeId pre
      (stepReferenceSliceV1 admitted pre invocation #[] vault)
      loadedBytes
      (observeHandlerIRV1 handlerIR
        (nullaryUInt64ViewInvocationV1 accountData discriminatorValue)) := by
  have hsize : loadedBytes.size = 8 := by
    rw [haccount.2.1]
    exact encodeU64le_size value
  have hcanonical :
      validateValueBytesV1 data.types binding.semanticTypeId loadedBytes =
        .ok () := by
    apply validateValueBytesV1_uint64_of_size data.types binding.semanticTypeId
      {
        id := binding.semanticTypeId
        name := none
        shape := .uint 64
      }
    · exact halignment.bindingRel.1
    · rfl
    · exact hsize
  have hreference :
      stepReferenceSliceV1 admitted pre invocation #[] vault =
        .returned pre (some {
          typeId := binding.semanticTypeId
          valueBytes := loadedBytes
        }) #[] :=
    stepReferenceSliceV1_ready_viewLoad_returned_exact_of_solana_alignment
      admitted pre invocation data overlay loadedBytes plan binding viewName
      discriminator handler handlerIR callableId context #[] vault halignment
      hadmittedData haccount.1 rfl hgate
  have htarget :
      executeHandlerIRV1 handlerIR
        (nullaryUInt64ViewInvocationV1 accountData discriminatorValue) =
          .returned (some (encodeU64le value)) :=
    executeHandlerIRV1_of_nullaryUInt64ViewStaticAlignment data plan binding
      viewName discriminator handler handlerIR accountData discriminatorValue
      value halignment hdiscriminator haccount.2.2.1 haccount.2.2.2.1
      haccount.2.2.2.2
  refine ⟨hcanonical, hsize, hreference, ?_, rfl⟩
  simpa [observeHandlerIRV1, haccount.2.1] using htarget

end ProofForgeV2.Targets.Solana

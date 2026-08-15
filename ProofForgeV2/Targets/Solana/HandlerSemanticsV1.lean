import ProofForgeV2.Targets.Solana.StaticAlignmentV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1

/-!
# Solana HandlerSemanticsV1

One bounded evaluator for the admitted production UInt64 and aggregate-return
handler recipes. This is a target-IR refinement object, not a second
interpreter for ProofForge DSL callables. It models the selected Solana
account/header/input/state/return boundary; all unsupported checks and
operations fail closed.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Semantic
open ProofForgeV2.Semantic.InvariantABI
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
  deriving BEq, DecidableEq, Repr

/-- Complete invocation observation for the selected handler recipe. The
    discriminator is the first eight instruction-data bytes. -/
structure InvocationObservationV1 where
  accounts : Array AccountObservationV1
  instructionData : ByteArray
  deriving BEq, DecidableEq, Repr

inductive HandlerExecutionErrorV1 where
  | unsupportedDiscriminator
  | discriminatorMismatch
  | unsupportedHandlerShape
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
  | arithmeticOverflow (errorCode : Nat)
  | missingReturnData
  deriving BEq, DecidableEq, Repr

private structure HandlerMachineV1 where
  accounts : Array AccountObservationV1
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

/-- Exact bounded little-endian store used by the selected production state
    recipes. Bytes outside the selected word are preserved. -/
def writeUInt64LEV1 (bytes : ByteArray) (offset : Nat) (value : UInt64) :
    Option ByteArray :=
  if offset + 8 ≤ bytes.size then
    some <| Id.run do
      let mut result := bytes
      for index in [0:8] do
        result := result.set! (offset + index)
          (UInt64.shiftRight value (UInt64.ofNat (8 * index))).toUInt8
      return result
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

private def getLocalV1
    (machine : HandlerMachineV1)
    (index : Nat) : Except HandlerExecutionErrorV1 UInt64 :=
  match machine.locals[index]? with
  | some value => .ok value
  | none => .error .localOutOfBounds

private def writeAccountUInt64LEV1
    (machine : HandlerMachineV1)
    (accountIndex byteOffset : Nat)
    (value : UInt64) : Except HandlerExecutionErrorV1 HandlerMachineV1 := do
  let some account := machine.accounts[accountIndex]? | throw .accountShape
  let some data := writeUInt64LEV1 account.data byteOffset value |
    throw .memoryBounds
  pure {
    machine with
    accounts := machine.accounts.set! accountIndex { account with data }
  }

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
  | .literal destination value => setLocalV1 machine destination value
  | .zeroState accountIndex byteOffset =>
      writeAccountUInt64LEV1 machine accountIndex byteOffset 0
  | .loadParam destination dataOffset =>
      match readUInt64LEV1 invocation.instructionData dataOffset with
      | some value => setLocalV1 machine destination value
      | none => .error .memoryBounds
  | .loadState destination accountIndex byteOffset =>
      match machine.accounts[accountIndex]? with
      | some account =>
          match readUInt64LEV1 account.data byteOffset with
          | some value => setLocalV1 machine destination value
          | none => .error .memoryBounds
      | none => .error .accountShape
  | .checkedAdd destination lhs rhs errorCode => do
      let lhsValue ← getLocalV1 machine lhs
      let rhsValue ← getLocalV1 machine rhs
      if lhsValue ≤ (0xffffffffffffffff : UInt64) - rhsValue then
        setLocalV1 machine destination (lhsValue + rhsValue)
      else
        .error (.arithmeticOverflow errorCode)
  | .storeState accountIndex byteOffset source => do
      let value ← getLocalV1 machine source
      writeAccountUInt64LEV1 machine accountIndex byteOffset value
  | .setHeader accountIndex byteOffset value =>
      writeAccountUInt64LEV1 machine accountIndex byteOffset value
  | .setReturnData 8 source =>
      match getLocalV1 machine source with
      | .ok value => .ok { machine with returnData := some (encodeU64le value) }
      | .error error => .error error
  | .setReturnDataMulti sources => do
      let mut bytes := ByteArray.empty
      for source in sources do
        let value ← getLocalV1 machine source
        bytes := bytes.append (encodeU64le value)
      pure { machine with returnData := some bytes }
  | .returnNone => .ok machine
  | _ => .error .unsupportedOperation

/-- Execute a selected switch branch through the same operation evaluator. The
    supported switch recipe forbids nested regions, so encountering one here
    fails closed through `runOperationV1`. -/
private def runSwitchBranchOperationsV1
    (operations : List Operation)
    (invocation : InvocationObservationV1)
    (machine : HandlerMachineV1) :
    Except HandlerExecutionErrorV1 HandlerMachineV1 :=
  match operations with
  | [] => .ok machine
  | .returnNone :: _ => .ok machine
  | operation :: rest => do
      let next ← runOperationV1 invocation machine operation
      runSwitchBranchOperationsV1 rest invocation next

private def runOperationsV1
    (operations : List Operation)
    (invocation : InvocationObservationV1)
    (machine : HandlerMachineV1) :
    Except HandlerExecutionErrorV1 HandlerMachineV1 :=
  match operations with
  | [] => .ok machine
  | operation :: rest => do
      let next ←
        match operation with
        | .switchRegion scrutinee cases defaultOps => do
            let value ← getLocalV1 machine scrutinee
            let branch :=
              match cases.find? (fun candidate => candidate.1 == value) with
              | some candidate => candidate.2
              | none => defaultOps
            runSwitchBranchOperationsV1 branch.toList invocation machine
        | _ => runOperationV1 invocation machine operation
      runOperationsV1 rest invocation next

/-- Atomic target outcome. Mutable account observations are carried separately
    so existing return-data refinement statements remain stable. -/
inductive HandlerExecutionOutcomeV1 where
  | returned (returnData : Option ByteArray)
  | trapped (error : HandlerExecutionErrorV1)
  deriving BEq, DecidableEq, Repr

private def executeHandlerIRWithAccountsV1
    (handlerIR : HandlerIR)
    (invocation : InvocationObservationV1) :
    HandlerExecutionOutcomeV1 × Array AccountObservationV1 :=
  if !isSupportedBoundedHandlerIRV1 handlerIR then
    (.trapped .unsupportedHandlerShape, invocation.accounts)
  else match runDispatchV1 handlerIR invocation with
  | .error error => (.trapped error, invocation.accounts)
  | .ok _ =>
      match runChecksV1 handlerIR.checks.toList invocation with
      | .error error => (.trapped error, invocation.accounts)
      | .ok _ =>
          match runOperationsV1 handlerIR.operations.toList invocation
              { accounts := invocation.accounts } with
          | .error error => (.trapped error, invocation.accounts)
          | .ok machine =>
              if handlerIR.mode != .initialize && machine.returnData.isNone then
                (.trapped .missingReturnData, invocation.accounts)
              else
                (.returned machine.returnData, machine.accounts)

/-- The only evaluator for these bounded Solana production handler recipes. -/
def executeHandlerIRV1
    (handlerIR : HandlerIR)
    (invocation : InvocationObservationV1) : HandlerExecutionOutcomeV1 :=
  if !isSupportedBoundedHandlerIRV1 handlerIR then
    .trapped .unsupportedHandlerShape
  else match runDispatchV1 handlerIR invocation with
  | .error error => .trapped error
  | .ok _ =>
      match runChecksV1 handlerIR.checks.toList invocation with
      | .error error => .trapped error
      | .ok _ =>
          match runOperationsV1 handlerIR.operations.toList invocation
              { accounts := invocation.accounts } with
          | .error error => .trapped error
          | .ok machine =>
              if handlerIR.mode != .initialize && machine.returnData.isNone then
                .trapped .missingReturnData
              else
                .returned machine.returnData

/-- Target observation derived from the bounded handler evaluator. Successful
    mutating recipes expose committed account bytes; every trap exposes the
    original account snapshot (Solana instruction atomicity). -/
structure HandlerObservationV1 where
  invocation : InvocationObservationV1
  outcome : HandlerExecutionOutcomeV1
  postAccounts : Array AccountObservationV1
  deriving BEq, DecidableEq, Repr

/-- Observe one bounded HandlerIR execution, including atomic post accounts. -/
def observeHandlerIRV1
    (handlerIR : HandlerIR)
    (invocation : InvocationObservationV1) : HandlerObservationV1 :=
  let result := executeHandlerIRWithAccountsV1 handlerIR invocation
  {
    invocation
    outcome := executeHandlerIRV1 handlerIR invocation
    postAccounts := if handlerIR.mode == .view then invocation.accounts else result.2
  }

/-- Canonical account bytes for the production one-field UInt64 layout:
    8-byte initialized marker followed by the 8-byte state field. -/
def oneFieldUInt64AccountDataV1
    (initializedMarker value : UInt64) : ByteArray :=
  (encodeU64le initializedMarker).append (encodeU64le value)

/-- Canonical sole-Reference value bytes for `Option UInt64`. -/
def encodeOptionUInt64ValueV1 : Option UInt64 → ByteArray
  | none => ByteArray.mk #[0]
  | some value => (ByteArray.mk #[1]).append (encodeU64le value)

/-- Physical tag word used by the production two-field account layout. -/
def optionUInt64TagV1 : Option UInt64 → UInt64
  | none => 0
  | some _ => 1

/-- Physical payload word; canonical `none` zeroes stale payload bytes. -/
def optionUInt64PayloadV1 : Option UInt64 → UInt64
  | none => 0
  | some value => value

/-- Canonical production account bytes for one `Option UInt64` state row:
    initialized marker, tag word, then payload word. -/
def optionUInt64AccountDataV1
    (initializedMarker : UInt64) (value : Option UInt64) : ByteArray :=
  ((encodeU64le initializedMarker).append
    (encodeU64le (optionUInt64TagV1 value))).append
    (encodeU64le (optionUInt64PayloadV1 value))

/-- Target aggregate-return bytes for `Option UInt64`: tag then payload. This
    is distinct from the canonical Reference value bytes above. -/
def optionUInt64AggregateReturnDataV1 (value : Option UInt64) : ByteArray :=
  (encodeU64le (optionUInt64TagV1 value)).append
    (encodeU64le (optionUInt64PayloadV1 value))

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

/-- Canonical invocation observation for the selected production initializer
    and checked-add entry recipes. -/
def unaryUInt64InvocationV1
    (accountData : ByteArray)
    (discriminatorValue argument : UInt64)
    (isSigner isWritable : Bool)
    (ownerCurrentProgram : Bool := true)
    (isDuplicate : Bool := false) : InvocationObservationV1 := {
  accounts := #[{
    isDuplicate
    ownerCurrentProgram
    isSigner
    isWritable
    data := accountData
  }]
  instructionData := (encodeU64le discriminatorValue).append (encodeU64le argument)
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

/-- Representation relation for a committed logical state and the production
    one-account UInt64 layout. This relates encodings only; business execution
    remains owned by `ReferenceMachineV1`. -/
def UInt64LogicalStateAccountRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (logicalState : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (accountData : ByteArray)
    (value : UInt64) : Prop :=
  logicalState.initialized = true ∧
  decodeLogicalStateValuesV1 data logicalState = .ok #[encodeU64le value] ∧
  accountData.size = plan.stateAccount.exactDataLen ∧
  readUInt64LEV1 accountData plan.stateAccount.headerOffset =
    some plan.stateAccount.initializedMarker ∧
  readUInt64LEV1 accountData binding.byteOffset = some value

/-- Encoding relation between one sole-Reference `Option UInt64` state value
    and the production Solana tag/payload account bytes. The Option transition
    remains owned by `ReferenceMachineV1`; this relation only joins encodings. -/
def OptionUInt64LogicalStateAccountRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : OptionUInt64StateAccountBindingV1)
    (logicalState : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (accountData : ByteArray)
    (value : Option UInt64) : Prop :=
  OptionUInt64StateAccountBindingRelV1 data plan binding ∧
  logicalState.initialized = true ∧
  decodeLogicalStateValuesV1 data logicalState =
    .ok #[encodeOptionUInt64ValueV1 value] ∧
  accountData.size = plan.stateAccount.exactDataLen ∧
  readUInt64LEV1 accountData plan.stateAccount.headerOffset =
    some plan.stateAccount.initializedMarker ∧
  readUInt64LEV1 accountData binding.tagByteOffset =
    some (optionUInt64TagV1 value) ∧
  readUInt64LEV1 accountData binding.payloadByteOffset =
    some (optionUInt64PayloadV1 value)

private def checkDecodedOptionUInt64LogicalStateV1
    (result : Except SemanticWireErrorV1 (Array ByteArray))
    (value : Option UInt64) : Bool :=
  match result with
  | .ok actual => decide (actual = #[encodeOptionUInt64ValueV1 value])
  | .error _ => false

private theorem checkDecodedOptionUInt64LogicalStateV1_eq_true_iff
    (result : Except SemanticWireErrorV1 (Array ByteArray))
    (value : Option UInt64) :
    checkDecodedOptionUInt64LogicalStateV1 result value = true ↔
      result = .ok #[encodeOptionUInt64ValueV1 value] := by
  cases result <;> simp [checkDecodedOptionUInt64LogicalStateV1]

/-- Executable checker for the contract-independent `Option UInt64` logical
    state/physical Solana account representation relation. -/
def checkOptionUInt64LogicalStateAccountRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : OptionUInt64StateAccountBindingV1)
    (logicalState : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (accountData : ByteArray)
    (value : Option UInt64) : Bool :=
  checkOptionUInt64StateAccountBindingRelV1 data plan binding &&
  logicalState.initialized &&
  checkDecodedOptionUInt64LogicalStateV1
    (decodeLogicalStateValuesV1 data logicalState) value &&
  decide (accountData.size = plan.stateAccount.exactDataLen) &&
  decide (readUInt64LEV1 accountData plan.stateAccount.headerOffset =
    some plan.stateAccount.initializedMarker) &&
  decide (readUInt64LEV1 accountData binding.tagByteOffset =
    some (optionUInt64TagV1 value)) &&
  decide (readUInt64LEV1 accountData binding.payloadByteOffset =
    some (optionUInt64PayloadV1 value))

theorem checkOptionUInt64LogicalStateAccountRelV1_eq_true_iff
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : OptionUInt64StateAccountBindingV1)
    (logicalState : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (accountData : ByteArray)
    (value : Option UInt64) :
    checkOptionUInt64LogicalStateAccountRelV1 data plan binding logicalState
        accountData value = true ↔
      OptionUInt64LogicalStateAccountRelV1 data plan binding logicalState
        accountData value := by
  simp only [checkOptionUInt64LogicalStateAccountRelV1, Bool.and_eq_true,
    decide_eq_true_eq, checkOptionUInt64StateAccountBindingRelV1_eq_true_iff,
    checkDecodedOptionUInt64LogicalStateV1_eq_true_iff,
    OptionUInt64LogicalStateAccountRelV1]
  simp only [and_assoc]

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

/-- Generic typed Reference→HandlerIR return boundary when canonical Reference
    value bytes and target ABI return bytes differ. The caller supplies both
    encodings; this relation checks the actual Reference and Handler outcomes
    without interpreting an aggregate or defining another transition. -/
def TypedReturnedHandlerObservationRelV1
    (data : SemanticProgramDataV1)
    (typeId : TypeIdV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (referenceValueBytes targetReturnBytes : ByteArray)
    (observed : HandlerObservationV1) : Prop :=
  validateValueBytesV1 data.types typeId referenceValueBytes = .ok () ∧
  referenceOutcome = .returned pre (some {
    typeId
    valueBytes := referenceValueBytes
  }) #[] ∧
  observed.outcome = .returned (some targetReturnBytes) ∧
  observed.postAccounts = observed.invocation.accounts

/-- Exact Reference→HandlerIR relation for the one-field UInt64 initializer
    slice. The sole Reference outcome and the Handler post-account observation
    share the same committed value through the existing account codec relation;
    this predicate defines no transition of its own. -/
def UInt64InitializerReturnedHandlerObservationRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (postData : ByteArray)
    (argument : UInt64)
    (observed : HandlerObservationV1) : Prop :=
  referenceOutcome = .returned post none #[] ∧
  observed.outcome = .returned none ∧
  observed.postAccounts[0]?.map (·.data) = some postData ∧
  UInt64LogicalStateAccountRelV1 data plan binding post postData argument

private def checkLogicalStateEqV1
    (left right : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1) : Bool :=
  decide (left.initialized = right.initialized) &&
    decide (left.canonicalValues = right.canonicalValues)

private theorem checkLogicalStateEqV1_eq_true_iff
    (left right : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1) :
    checkLogicalStateEqV1 left right = true ↔ left = right := by
  cases left
  cases right
  simp [checkLogicalStateEqV1]

private def checkInitializerReferenceOutcomeV1
    (outcome : OutcomeV1)
    (post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1) : Bool :=
  match outcome with
  | .returned actualPost none effects =>
      checkLogicalStateEqV1 actualPost post && effects.isEmpty
  | _ => false

private theorem checkInitializerReferenceOutcomeV1_eq_true_iff
    (outcome : OutcomeV1)
    (post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1) :
    checkInitializerReferenceOutcomeV1 outcome post = true ↔
      outcome = .returned post none #[] := by
  cases outcome with
  | returned actual value effects =>
      cases value <;>
        simp [checkInitializerReferenceOutcomeV1,
          checkLogicalStateEqV1_eq_true_iff, Array.isEmpty_iff]
  | reverted => simp [checkInitializerReferenceOutcomeV1]
  | trapped => simp [checkInitializerReferenceOutcomeV1]

private def checkDecodedUInt64LogicalStateV1
    (result : Except SemanticWireErrorV1 (Array ByteArray))
    (value : UInt64) : Bool :=
  match result with
  | .ok actual => decide (actual = #[encodeU64le value])
  | .error _ => false

private theorem checkDecodedUInt64LogicalStateV1_eq_true_iff
    (result : Except SemanticWireErrorV1 (Array ByteArray))
    (value : UInt64) :
    checkDecodedUInt64LogicalStateV1 result value = true ↔
      result = .ok #[encodeU64le value] := by
  cases result <;> simp [checkDecodedUInt64LogicalStateV1]

private def checkUInt64LogicalStateAccountRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (logicalState : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (accountData : ByteArray)
    (value : UInt64) : Bool :=
  logicalState.initialized &&
  checkDecodedUInt64LogicalStateV1
    (decodeLogicalStateValuesV1 data logicalState) value &&
  decide (accountData.size = plan.stateAccount.exactDataLen) &&
  decide (readUInt64LEV1 accountData plan.stateAccount.headerOffset =
    some plan.stateAccount.initializedMarker) &&
  decide (readUInt64LEV1 accountData binding.byteOffset = some value)

private theorem checkUInt64LogicalStateAccountRelV1_eq_true_iff
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (logicalState : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (accountData : ByteArray)
    (value : UInt64) :
    checkUInt64LogicalStateAccountRelV1 data plan binding logicalState
        accountData value = true ↔
      UInt64LogicalStateAccountRelV1 data plan binding logicalState accountData
        value := by
  simp only [checkUInt64LogicalStateAccountRelV1, Bool.and_eq_true,
    decide_eq_true_eq, checkDecodedUInt64LogicalStateV1_eq_true_iff,
    UInt64LogicalStateAccountRelV1]
  simp only [and_assoc]

/-- Executable, proof-producing form of the initializer observation relation.
    It compares the Reference outcome structurally rather than relying on the
    non-lawful derived `BEq` for semantic outcomes. -/
def checkUInt64InitializerReturnedHandlerObservationRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (postData : ByteArray)
    (argument : UInt64)
    (observed : HandlerObservationV1) : Bool :=
  checkInitializerReferenceOutcomeV1 referenceOutcome post &&
  decide (observed.outcome = .returned none) &&
  decide (observed.postAccounts[0]?.map (·.data) = some postData) &&
  checkUInt64LogicalStateAccountRelV1 data plan binding post postData argument

theorem checkUInt64InitializerReturnedHandlerObservationRelV1_eq_true_iff
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (postData : ByteArray)
    (argument : UInt64)
    (observed : HandlerObservationV1) :
    checkUInt64InitializerReturnedHandlerObservationRelV1 data plan binding post
        referenceOutcome postData argument observed = true ↔
      UInt64InitializerReturnedHandlerObservationRelV1 data plan binding post
        referenceOutcome postData argument observed := by
  simp only [checkUInt64InitializerReturnedHandlerObservationRelV1,
    Bool.and_eq_true, decide_eq_true_eq,
    checkInitializerReferenceOutcomeV1_eq_true_iff,
    checkUInt64LogicalStateAccountRelV1_eq_true_iff,
    UInt64InitializerReturnedHandlerObservationRelV1]
  simp only [and_assoc]

/-- Exact Reference→HandlerIR relation for successful one-field UInt64
    checked addition. The Reference result, Handler return bytes, committed
    account bytes, and codec relation all share the same checked sum. -/
def UInt64CheckedAddReturnedHandlerObservationRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (postData : ByteArray)
    (before argument : UInt64)
    (observed : HandlerObservationV1) : Prop :=
  referenceOutcome = .returned post (some {
    typeId := binding.semanticTypeId
    valueBytes := encodeU64le (before + argument)
  }) #[] ∧
  observed.outcome = .returned (some (encodeU64le (before + argument))) ∧
  observed.postAccounts[0]?.map (·.data) = some postData ∧
  UInt64LogicalStateAccountRelV1 data plan binding post postData
    (before + argument)

private def checkTypedReturnedReferenceOutcomeV1
    (outcome : OutcomeV1)
    (post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (typeId : TypeIdV1)
    (valueBytes : ByteArray) : Bool :=
  match outcome with
  | .returned actualPost (some actualValue) effects =>
      checkLogicalStateEqV1 actualPost post &&
      decide (actualValue.typeId = typeId) &&
      decide (actualValue.valueBytes = valueBytes) &&
      effects.isEmpty
  | _ => false

private theorem checkTypedReturnedReferenceOutcomeV1_eq_true_iff
    (outcome : OutcomeV1)
    (post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (typeId : TypeIdV1)
    (valueBytes : ByteArray) :
    checkTypedReturnedReferenceOutcomeV1 outcome post typeId valueBytes = true ↔
      outcome = .returned post (some { typeId, valueBytes }) #[] := by
  cases outcome with
  | returned actualPost value effects =>
      cases value with
      | none => simp [checkTypedReturnedReferenceOutcomeV1]
      | some actualValue =>
          cases actualValue
          simp [checkTypedReturnedReferenceOutcomeV1,
            checkLogicalStateEqV1_eq_true_iff, Array.isEmpty_iff, and_assoc]
  | reverted => simp [checkTypedReturnedReferenceOutcomeV1]
  | trapped => simp [checkTypedReturnedReferenceOutcomeV1]

private def checkValueBytesCanonicalV1
    (data : SemanticProgramDataV1)
    (typeId : TypeIdV1)
    (valueBytes : ByteArray) : Bool :=
  match validateValueBytesV1 data.types typeId valueBytes with
  | .ok _ => true
  | .error _ => false

private theorem checkValueBytesCanonicalV1_eq_true_iff
    (data : SemanticProgramDataV1)
    (typeId : TypeIdV1)
    (valueBytes : ByteArray) :
    checkValueBytesCanonicalV1 data typeId valueBytes = true ↔
      validateValueBytesV1 data.types typeId valueBytes = .ok () := by
  unfold checkValueBytesCanonicalV1
  cases hvalidate : validateValueBytesV1 data.types typeId valueBytes with
  | error error => simp
  | ok result =>
      cases result
      simp

/-- Executable, proof-producing form of the generic typed return boundary. -/
def checkTypedReturnedHandlerObservationRelV1
    (data : SemanticProgramDataV1)
    (typeId : TypeIdV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (referenceValueBytes targetReturnBytes : ByteArray)
    (observed : HandlerObservationV1) : Bool :=
  checkValueBytesCanonicalV1 data typeId referenceValueBytes &&
  checkTypedReturnedReferenceOutcomeV1 referenceOutcome pre typeId
    referenceValueBytes &&
  decide (observed.outcome = .returned (some targetReturnBytes)) &&
  decide (observed.postAccounts = observed.invocation.accounts)

theorem checkTypedReturnedHandlerObservationRelV1_eq_true_iff
    (data : SemanticProgramDataV1)
    (typeId : TypeIdV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (referenceValueBytes targetReturnBytes : ByteArray)
    (observed : HandlerObservationV1) :
    checkTypedReturnedHandlerObservationRelV1 data typeId pre referenceOutcome
        referenceValueBytes targetReturnBytes observed = true ↔
      TypedReturnedHandlerObservationRelV1 data typeId pre referenceOutcome
        referenceValueBytes targetReturnBytes observed := by
  simp only [checkTypedReturnedHandlerObservationRelV1, Bool.and_eq_true,
    checkValueBytesCanonicalV1_eq_true_iff,
    checkTypedReturnedReferenceOutcomeV1_eq_true_iff, decide_eq_true_eq,
    TypedReturnedHandlerObservationRelV1]
  simp only [and_assoc]

/-- Executable, proof-producing form of the read-only UInt64 observation
    relation. It checks the already-computed sole Reference outcome and actual
    production HandlerIR observation; it does not execute another transition. -/
def checkUInt64ReturnedHandlerObservationRelV1
    (data : SemanticProgramDataV1)
    (typeId : TypeIdV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (valueBytes : ByteArray)
    (observed : HandlerObservationV1) : Bool :=
  checkValueBytesCanonicalV1 data typeId valueBytes &&
  decide (valueBytes.size = 8) &&
  checkTypedReturnedReferenceOutcomeV1 referenceOutcome pre typeId valueBytes &&
  decide (observed.outcome = .returned (some valueBytes)) &&
  decide (observed.postAccounts = observed.invocation.accounts)

theorem checkUInt64ReturnedHandlerObservationRelV1_eq_true_iff
    (data : SemanticProgramDataV1)
    (typeId : TypeIdV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (valueBytes : ByteArray)
    (observed : HandlerObservationV1) :
    checkUInt64ReturnedHandlerObservationRelV1 data typeId pre referenceOutcome
        valueBytes observed = true ↔
      UInt64ReturnedHandlerObservationRelV1 data typeId pre referenceOutcome
        valueBytes observed := by
  simp only [checkUInt64ReturnedHandlerObservationRelV1, Bool.and_eq_true,
    checkValueBytesCanonicalV1_eq_true_iff, decide_eq_true_eq,
    checkTypedReturnedReferenceOutcomeV1_eq_true_iff,
    UInt64ReturnedHandlerObservationRelV1]
  simp only [and_assoc]

/-- Executable, proof-producing form of the successful checked-add observation
    relation. It consumes an already-computed sole Reference outcome and the
    actual production HandlerIR observation. -/
def checkUInt64CheckedAddReturnedHandlerObservationRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (postData : ByteArray)
    (before argument : UInt64)
    (observed : HandlerObservationV1) : Bool :=
  checkTypedReturnedReferenceOutcomeV1 referenceOutcome post
    binding.semanticTypeId (encodeU64le (before + argument)) &&
  decide (observed.outcome =
    .returned (some (encodeU64le (before + argument)))) &&
  decide (observed.postAccounts[0]?.map (·.data) = some postData) &&
  checkUInt64LogicalStateAccountRelV1 data plan binding post postData
    (before + argument)

theorem checkUInt64CheckedAddReturnedHandlerObservationRelV1_eq_true_iff
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (postData : ByteArray)
    (before argument : UInt64)
    (observed : HandlerObservationV1) :
    checkUInt64CheckedAddReturnedHandlerObservationRelV1 data plan binding post
        referenceOutcome postData before argument observed = true ↔
      UInt64CheckedAddReturnedHandlerObservationRelV1 data plan binding post
        referenceOutcome postData before argument observed := by
  simp only [checkUInt64CheckedAddReturnedHandlerObservationRelV1,
    Bool.and_eq_true, decide_eq_true_eq,
    checkTypedReturnedReferenceOutcomeV1_eq_true_iff,
    checkUInt64LogicalStateAccountRelV1_eq_true_iff,
    UInt64CheckedAddReturnedHandlerObservationRelV1]
  simp only [and_assoc]

/-- Exact Reference→HandlerIR relation for one-field UInt64 checked-add
    overflow. Both layers retain the same pre-state/account snapshot, while the
    established target error code represents the Reference standard revert. -/
def UInt64CheckedAddOverflowHandlerObservationRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (accountData : ByteArray)
    (before : UInt64)
    (observed : HandlerObservationV1) : Prop :=
  referenceOutcome = .reverted (.standard .arithmeticOverflow) pre ∧
  observed.outcome = .trapped (.arithmeticOverflow arithmeticOverflowError) ∧
  observed.postAccounts = observed.invocation.accounts ∧
  observed.invocation.accounts[0]?.map (·.data) = some accountData ∧
  UInt64LogicalStateAccountRelV1 data plan binding pre accountData before

private def checkArithmeticOverflowReferenceOutcomeV1
    (outcome : OutcomeV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1) : Bool :=
  match outcome with
  | .reverted (.standard .arithmeticOverflow) actualPre =>
      checkLogicalStateEqV1 actualPre pre
  | _ => false

private theorem checkArithmeticOverflowReferenceOutcomeV1_eq_true_iff
    (outcome : OutcomeV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1) :
    checkArithmeticOverflowReferenceOutcomeV1 outcome pre = true ↔
      outcome = .reverted (.standard .arithmeticOverflow) pre := by
  cases outcome with
  | returned => simp [checkArithmeticOverflowReferenceOutcomeV1]
  | trapped => simp [checkArithmeticOverflowReferenceOutcomeV1]
  | reverted reason actualPre =>
      cases reason with
      | declared => simp [checkArithmeticOverflowReferenceOutcomeV1]
      | externalCallReverted =>
          simp [checkArithmeticOverflowReferenceOutcomeV1]
      | standard code =>
          cases code <;>
            simp [checkArithmeticOverflowReferenceOutcomeV1,
              checkLogicalStateEqV1_eq_true_iff]

/-- Executable, proof-producing form of the checked-add overflow relation. It
    consumes the sole Reference outcome and the actual production HandlerIR
    observation without introducing another transition. -/
def checkUInt64CheckedAddOverflowHandlerObservationRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (accountData : ByteArray)
    (before : UInt64)
    (observed : HandlerObservationV1) : Bool :=
  checkArithmeticOverflowReferenceOutcomeV1 referenceOutcome pre &&
  decide (observed.outcome =
    .trapped (.arithmeticOverflow arithmeticOverflowError)) &&
  decide (observed.postAccounts = observed.invocation.accounts) &&
  decide (observed.invocation.accounts[0]?.map (·.data) = some accountData) &&
  checkUInt64LogicalStateAccountRelV1 data plan binding pre accountData before

theorem checkUInt64CheckedAddOverflowHandlerObservationRelV1_eq_true_iff
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (referenceOutcome : OutcomeV1)
    (accountData : ByteArray)
    (before : UInt64)
    (observed : HandlerObservationV1) :
    checkUInt64CheckedAddOverflowHandlerObservationRelV1 data plan binding pre
        referenceOutcome accountData before observed = true ↔
      UInt64CheckedAddOverflowHandlerObservationRelV1 data plan binding pre
        referenceOutcome accountData before observed := by
  simp only [checkUInt64CheckedAddOverflowHandlerObservationRelV1,
    Bool.and_eq_true, decide_eq_true_eq,
    checkArithmeticOverflowReferenceOutcomeV1_eq_true_iff,
    checkUInt64LogicalStateAccountRelV1_eq_true_iff,
    UInt64CheckedAddOverflowHandlerObservationRelV1]
  simp only [and_assoc]

/-- Package the exact output of
    `unaryUInt64Initializer_reference_handlerIR_join` as the relation consumed
    by the Reference→provider composition boundary. -/
theorem uint64InitializerReturnedHandlerObservationRelV1_of_join
    {data : SemanticProgramDataV1}
    {plan : Plan}
    {binding : UInt64StateAccountBindingV1}
    {post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {postData accountData : ByteArray}
    {argument discriminatorValue : UInt64}
    {handlerIR : HandlerIR}
    (hjoin :
      referenceOutcome = .returned post none #[] ∧
      observeHandlerIRV1 handlerIR
          (unaryUInt64InvocationV1 accountData discriminatorValue argument true
            true) = {
        invocation := unaryUInt64InvocationV1 accountData discriminatorValue
          argument true true
        outcome := .returned none
        postAccounts := #[{
          isDuplicate := false
          ownerCurrentProgram := true
          isSigner := true
          isWritable := true
          data := postData
        }]
      } ∧
      UInt64LogicalStateAccountRelV1 data plan binding post postData argument) :
    UInt64InitializerReturnedHandlerObservationRelV1 data plan binding post
      referenceOutcome postData argument
      (observeHandlerIRV1 handlerIR
        (unaryUInt64InvocationV1 accountData discriminatorValue argument true
          true)) := by
  rcases hjoin with ⟨hreference, hobserved, hstate⟩
  refine ⟨hreference, ?_, ?_, hstate⟩
  · rw [hobserved]
  · rw [hobserved]
    rfl

/-- Package the successful checked-add Reference→HandlerIR theorem output for
    direct composition with the certified provider join. -/
theorem uint64CheckedAddReturnedHandlerObservationRelV1_of_join
    {data : SemanticProgramDataV1}
    {plan : Plan}
    {binding : UInt64StateAccountBindingV1}
    {post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {postData accountData : ByteArray}
    {before argument discriminatorValue : UInt64}
    {handlerIR : HandlerIR}
    (hjoin :
      referenceOutcome = .returned post (some {
        typeId := binding.semanticTypeId
        valueBytes := encodeU64le (before + argument)
      }) #[] ∧
      observeHandlerIRV1 handlerIR
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true) = {
        invocation := unaryUInt64InvocationV1 accountData discriminatorValue
          argument false true
        outcome := .returned (some (encodeU64le (before + argument)))
        postAccounts := #[{
          isDuplicate := false
          ownerCurrentProgram := true
          isSigner := false
          isWritable := true
          data := postData
        }]
      } ∧
      UInt64LogicalStateAccountRelV1 data plan binding post postData
        (before + argument)) :
    UInt64CheckedAddReturnedHandlerObservationRelV1 data plan binding post
      referenceOutcome postData before argument
      (observeHandlerIRV1 handlerIR
        (unaryUInt64InvocationV1 accountData discriminatorValue argument false
          true)) := by
  rcases hjoin with ⟨hreference, hobserved, hstate⟩
  refine ⟨hreference, ?_, ?_, hstate⟩
  · rw [hobserved]
  · rw [hobserved]
    rfl

/-- Package the checked-add overflow Reference→HandlerIR theorem output for
    direct composition with the certified provider join. -/
theorem uint64CheckedAddOverflowHandlerObservationRelV1_of_join
    {data : SemanticProgramDataV1}
    {plan : Plan}
    {binding : UInt64StateAccountBindingV1}
    {pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1}
    {referenceOutcome : OutcomeV1}
    {accountData : ByteArray}
    {before argument discriminatorValue : UInt64}
    {handlerIR : HandlerIR}
    (hjoin :
      referenceOutcome = .reverted (.standard .arithmeticOverflow) pre ∧
      observeHandlerIRV1 handlerIR
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true) = {
        invocation := unaryUInt64InvocationV1 accountData discriminatorValue
          argument false true
        outcome := .trapped (.arithmeticOverflow arithmeticOverflowError)
        postAccounts :=
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true).accounts
      } ∧
      UInt64LogicalStateAccountRelV1 data plan binding pre accountData before) :
    UInt64CheckedAddOverflowHandlerObservationRelV1 data plan binding pre
      referenceOutcome accountData before
      (observeHandlerIRV1 handlerIR
        (unaryUInt64InvocationV1 accountData discriminatorValue argument false
          true)) := by
  rcases hjoin with ⟨hreference, hobserved, hstate⟩
  refine ⟨hreference, ?_, ?_, ?_, hstate⟩
  · rw [hobserved]
  · rw [hobserved]
  · change
      (unaryUInt64InvocationV1 accountData discriminatorValue argument false
          true).accounts[0]?.map (·.data) = some accountData
    rfl

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

/-- A successful production logical-state encoding and matching account reads
    establish the committed representation relation. -/
theorem uint64LogicalStateAccountRelV1_of_encode
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (logicalState : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (accountData : ByteArray)
    (value : UInt64)
    (hencode : encodeLogicalStateValuesV1 data true #[encodeU64le value] =
      .ok logicalState)
    (hdataLength : accountData.size = plan.stateAccount.exactDataLen)
    (hheader : readUInt64LEV1 accountData plan.stateAccount.headerOffset =
      some plan.stateAccount.initializedMarker)
    (hfield : readUInt64LEV1 accountData binding.byteOffset = some value) :
    UInt64LogicalStateAccountRelV1 data plan binding logicalState accountData
      value := by
  refine ⟨
    logicalState.initialized_of_encodeLogicalStateValuesV1 data true _ hencode,
    decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1 data true _
      logicalState hencode,
    hdataLength,
    hheader,
    hfield
  ⟩

/-- The production unary invocation constructor supplies the exact
    discriminator bytes consumed by the sole dispatcher. -/
private theorem runDispatchV1_unaryUInt64InvocationV1
    (handlerIR : HandlerIR)
    (accountData : ByteArray)
    (discriminatorValue argument : UInt64)
    (isSigner : Bool)
    (hdiscriminator :
      discriminatorToLeU64V1 handlerIR.discriminator = .ok discriminatorValue) :
    runDispatchV1 handlerIR
      (unaryUInt64InvocationV1 accountData discriminatorValue argument isSigner
        true) = .ok () := by
  unfold runDispatchV1
  rw [hdiscriminator]
  simp only [Except.toOption, unaryUInt64InvocationV1]
  have hread :
      readUInt64LEV1
          ((encodeU64le discriminatorValue).append (encodeU64le argument)) 0 =
        some discriminatorValue := by
    simpa [oneFieldUInt64AccountDataV1] using
      readUInt64LEV1_oneFieldUInt64AccountDataV1_header discriminatorValue
        argument
  rw [hread]
  simp

private theorem readUInt64LEV1_unaryUInt64InvocationV1_argument
    (accountData : ByteArray)
    (discriminatorValue argument : UInt64)
    (isSigner isWritable : Bool) :
    readUInt64LEV1
        (unaryUInt64InvocationV1 accountData discriminatorValue argument isSigner
          isWritable).instructionData 8 = some argument := by
  unfold unaryUInt64InvocationV1
  change readUInt64LEV1
      ((encodeU64le discriminatorValue).append (encodeU64le argument)) 8 =
    some argument
  simpa [oneFieldUInt64AccountDataV1] using
    readUInt64LEV1_oneFieldUInt64AccountDataV1_field discriminatorValue argument

/-- The production checked-add guard and the Reference machine's mathematical
    UInt64 bound classify exactly the same inputs. -/
private theorem checkedAddGuardV1_iff_toNat_sum_fits
    (before argument : UInt64) :
    (before ≤ (0xffffffffffffffff : UInt64) - argument) ↔
      before.toNat + argument.toNat < 2 ^ 64 := by
  have hmaxNat :
      (0xffffffffffffffff : UInt64).toNat = 2 ^ 64 - 1 := by
    decide
  have hargumentLt := argument.toNat_lt
  have hargumentMax :
      argument ≤ (0xffffffffffffffff : UInt64) := by
    rw [UInt64.le_iff_toNat_le, hmaxNat]
    omega
  rw [UInt64.le_iff_toNat_le,
    UInt64.toNat_sub_of_le (0xffffffffffffffff : UInt64) argument hargumentMax,
    hmaxNat]
  omega

/-- Exact successful execution and committed account observation for a
    statically aligned production initializer. The three write equations are
    facts about the one target representation helper, not a second state
    transition relation. -/
theorem observeHandlerIRV1_of_unaryUInt64InitializerStaticAlignment
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (unitTypeId : TypeIdV1)
    (parameterValueId : ValueIdV1)
    (parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData zeroedData storedData postData : ByteArray)
    (discriminatorValue argument : UInt64)
    (halignment : UnaryUInt64InitializerStaticAlignmentV1 data plan binding
      callableId unitTypeId parameterValueId parameterName discriminator
      handler handlerIR)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue)
    (hdataLength : accountData.size = plan.stateAccount.exactDataLen)
    (hheader : readUInt64LEV1 accountData plan.stateAccount.headerOffset =
      some 0)
    (hzero : writeUInt64LEV1 accountData binding.byteOffset 0 =
      some zeroedData)
    (hstore : writeUInt64LEV1 zeroedData binding.byteOffset argument =
      some storedData)
    (hmarker : writeUInt64LEV1 storedData plan.stateAccount.headerOffset
      plan.stateAccount.initializedMarker = some postData) :
    observeHandlerIRV1 handlerIR
      (unaryUInt64InvocationV1 accountData discriminatorValue argument true
        true) = {
      invocation := unaryUInt64InvocationV1 accountData discriminatorValue
        argument true true
      outcome := .returned none
      postAccounts := #[{
        isDuplicate := false
        ownerCurrentProgram := true
        isSigner := true
        isWritable := true
        data := postData
      }]
    } := by
  have hsupported : isSupportedOneFieldUInt64HandlerIRV1 handlerIR = true := by
    simp [isSupportedOneFieldUInt64HandlerIRV1,
      isSupportedUnaryUInt64InitializerHandlerIRV1_of_alignment data plan
        binding callableId unitTypeId parameterValueId parameterName
        discriminator handler handlerIR halignment]
  have hhandlerDiscriminator :
      discriminatorToLeU64V1 handlerIR.discriminator = .ok discriminatorValue :=
    by simpa [halignment.handlerIRExact] using hdiscriminator
  have hchecks :
      runChecksV1 handlerIR.checks.toList
          (unaryUInt64InvocationV1 accountData discriminatorValue argument true
            true) = .ok () := by
    rw [halignment.handlerIRExact]
    simp [runChecksV1, runCheckV1, unaryUInt64InvocationV1, encodeU64le_size,
      halignment.accountZero, hdataLength, hheader, Bind.bind, Except.bind]
  have hoperations :
      runOperationsV1 handlerIR.operations.toList
          (unaryUInt64InvocationV1 accountData discriminatorValue argument true
            true)
          { accounts :=
              (unaryUInt64InvocationV1 accountData discriminatorValue argument
                true true).accounts } =
        .ok {
          accounts := #[{
            isDuplicate := false
            ownerCurrentProgram := true
            isSigner := true
            isWritable := true
            data := postData
          }]
          locals := #[argument]
        } := by
    rw [halignment.handlerIRExact]
    simp only [runOperationsV1, runOperationV1, halignment.accountZero]
    rw [readUInt64LEV1_unaryUInt64InvocationV1_argument]
    simp [unaryUInt64InvocationV1, setLocalV1, getLocalV1,
      writeAccountUInt64LEV1, hzero, hstore, hmarker, Pure.pure, Except.pure,
      Bind.bind, Except.bind]
  have houtcome :
      executeHandlerIRV1 handlerIR
          (unaryUInt64InvocationV1 accountData discriminatorValue argument true
            true) = .returned none := by
    simp only [executeHandlerIRV1, isSupportedBoundedHandlerIRV1,
      isSupportedBoundedUInt64HandlerIRV1, hsupported, Bool.true_or,
      Bool.not_true]
    rw [runDispatchV1_unaryUInt64InvocationV1 _ _ _ _ true
      hhandlerDiscriminator]
    rw [hchecks, hoperations]
    rw [halignment.handlerIRExact]
    rfl
  have haccounts :
      executeHandlerIRWithAccountsV1 handlerIR
          (unaryUInt64InvocationV1 accountData discriminatorValue argument true
            true) =
        (.returned none, #[{
          isDuplicate := false
          ownerCurrentProgram := true
          isSigner := true
          isWritable := true
          data := postData
        }]) := by
    simp only [executeHandlerIRWithAccountsV1, isSupportedBoundedHandlerIRV1,
      isSupportedBoundedUInt64HandlerIRV1, hsupported, Bool.true_or,
      Bool.not_true]
    rw [runDispatchV1_unaryUInt64InvocationV1 _ _ _ _ true
      hhandlerDiscriminator]
    rw [hchecks, hoperations]
    rw [halignment.handlerIRExact]
    rfl
  unfold observeHandlerIRV1
  rw [houtcome, haccounts, halignment.handlerIRExact]
  rfl

/-- Kernel-checked Reference→Solana join for the production StateCell
    initializer. The first conjunct is the sole Reference business step; the
    second is exact HandlerIR execution; the third is their committed encoding
    relation. This does not cover emitted sBPF or the Solana runtime. -/
theorem unaryUInt64Initializer_reference_handlerIR_join
    (admitted : AdmittedReferenceSliceV1)
    (pre post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (unitTypeId : TypeIdV1)
    (parameterValueId : ValueIdV1)
    (parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (beforeBytes accountData zeroedData storedData postData : ByteArray)
    (invocationContext context : Array ContextInputV1)
    (vault : ReferenceVaultSeedV1)
    (discriminatorValue argument : UInt64)
    (halignment : UnaryUInt64InitializerStaticAlignmentV1 data plan binding
      callableId unitTypeId parameterValueId parameterName discriminator
      handler handlerIR)
    (hadmittedData : admitted.data = data)
    (hgate :
      gateInvocation admitted pre {
          callableId
          args := #[{
            typeId := binding.semanticTypeId
            valueBytes := encodeU64le argument
          }]
          context := invocationContext
        } =
        .ready {
          id := callableId
          kind := .initializer
          name := none
          params := #[{
            valueId := parameterValueId
            name := parameterName
            typeId := binding.semanticTypeId
            visibility := .public_
          }]
          result := { typeId := unitTypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[{
              result := none
              op := .stateStore binding.semanticStateId parameterValueId
            }]
            terminator := .return_ none
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[beforeBytes] context true)
    (hencode : encodeLogicalStateValuesV1 data true
      #[encodeU64le argument] = .ok post)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue)
    (hdataLength : accountData.size = plan.stateAccount.exactDataLen)
    (hheader : readUInt64LEV1 accountData plan.stateAccount.headerOffset =
      some 0)
    (hzero : writeUInt64LEV1 accountData binding.byteOffset 0 =
      some zeroedData)
    (hstore : writeUInt64LEV1 zeroedData binding.byteOffset argument =
      some storedData)
    (hmarker : writeUInt64LEV1 storedData plan.stateAccount.headerOffset
      plan.stateAccount.initializedMarker = some postData)
    (hpostDataLength : postData.size = plan.stateAccount.exactDataLen)
    (hpostHeader : readUInt64LEV1 postData plan.stateAccount.headerOffset =
      some plan.stateAccount.initializedMarker)
    (hpostField : readUInt64LEV1 postData binding.byteOffset = some argument) :
    stepReferenceSliceV1 admitted pre {
        callableId
        args := #[{
          typeId := binding.semanticTypeId
          valueBytes := encodeU64le argument
        }]
        context := invocationContext
      } #[] vault = .returned post none #[] ∧
    observeHandlerIRV1 handlerIR
      (unaryUInt64InvocationV1 accountData discriminatorValue argument true
        true) = {
      invocation := unaryUInt64InvocationV1 accountData discriminatorValue
        argument true true
      outcome := .returned none
      postAccounts := #[{
        isDuplicate := false
        ownerCurrentProgram := true
        isSigner := true
        isWritable := true
        data := postData
      }]
    } ∧
    UInt64LogicalStateAccountRelV1 data plan binding post postData argument := by
  have hcanonical :
      validateValueBytesV1 data.types binding.semanticTypeId
        (encodeU64le argument) = .ok () := by
    apply validateValueBytesV1_uint64_of_size data.types binding.semanticTypeId
      {
        id := binding.semanticTypeId
        name := none
        shape := .uint 64
      }
    · exact halignment.bindingRel.1
    · rfl
    · exact encodeU64le_size argument
  have hstate : data.logicalState[0]? = some {
      id := 0
      name := binding.stateName
      typeId := binding.semanticTypeId
      visibility := .public_
    } := by
    simpa [halignment.stateZero] using halignment.bindingRel.2.1
  have hreference :=
    stepReferenceSliceV1_ready_initializer_store_parameter_one_returned
      admitted pre post data beforeBytes (encodeU64le argument)
      binding.semanticTypeId unitTypeId binding.stateName parameterName
      callableId invocationContext context vault hadmittedData
      halignment.unitType hstate hcanonical hencode (by
        simpa [halignment.stateZero, halignment.parameterZero] using hgate)
  have htarget :=
    observeHandlerIRV1_of_unaryUInt64InitializerStaticAlignment data plan
      binding callableId unitTypeId parameterValueId parameterName discriminator
      handler handlerIR accountData zeroedData storedData postData
      discriminatorValue argument halignment hdiscriminator hdataLength hheader
      hzero hstore hmarker
  exact ⟨
    hreference,
    htarget,
    uint64LogicalStateAccountRelV1_of_encode data plan binding post postData
      argument hencode hpostDataLength hpostHeader hpostField
  ⟩

private theorem runChecksV1_of_unaryUInt64CheckedAddStaticAlignment
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (parameterValueId : ValueIdV1)
    (entryName parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData : ByteArray)
    (discriminatorValue argument : UInt64)
    (halignment : UnaryUInt64CheckedAddStaticAlignmentV1 data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR)
    (hdataLength : accountData.size = plan.stateAccount.exactDataLen)
    (hheader : readUInt64LEV1 accountData plan.stateAccount.headerOffset =
      some plan.stateAccount.initializedMarker) :
    runChecksV1 handlerIR.checks.toList
        (unaryUInt64InvocationV1 accountData discriminatorValue argument false
          true) = .ok () := by
  rw [halignment.handlerIRExact]
  simp [runChecksV1, runCheckV1, unaryUInt64InvocationV1, encodeU64le_size,
    halignment.accountZero, hdataLength, hheader, Bind.bind, Except.bind]

private def checkedAddMachineV1
    (accountData : ByteArray)
    (locals : Array UInt64 := #[])
    (returnData : Option ByteArray := none) : HandlerMachineV1 := {
  accounts := #[{
    isDuplicate := false
    ownerCurrentProgram := true
    isSigner := false
    isWritable := true
    data := accountData
  }]
  locals
  returnData
}

private theorem runOperationV1_checkedAdd_loadInitialState
    (accountData : ByteArray)
    (discriminatorValue argument before : UInt64)
    (accountIndex byteOffset : Nat)
    (haccount : accountIndex = 0)
    (hfield : readUInt64LEV1 accountData byteOffset = some before) :
    runOperationV1
        (unaryUInt64InvocationV1 accountData discriminatorValue argument false
          true)
        (checkedAddMachineV1 accountData)
        (.loadState 0 accountIndex byteOffset) =
      .ok (checkedAddMachineV1 accountData #[before]) := by
  subst accountIndex
  simp [runOperationV1, checkedAddMachineV1, setLocalV1, hfield]

private theorem runOperationV1_checkedAdd_loadArgument
    (accountData : ByteArray)
    (discriminatorValue before argument : UInt64) :
    runOperationV1
        (unaryUInt64InvocationV1 accountData discriminatorValue argument false
          true)
        (checkedAddMachineV1 accountData #[before]) (.loadParam 1 8) =
      .ok (checkedAddMachineV1 accountData #[before, argument]) := by
  simp only [runOperationV1]
  rw [readUInt64LEV1_unaryUInt64InvocationV1_argument]
  simp [checkedAddMachineV1, setLocalV1]

private theorem runOperationV1_checkedAdd_add
    (invocation : InvocationObservationV1)
    (accountData : ByteArray)
    (before argument : UInt64)
    (hnoOverflow : before ≤ (0xffffffffffffffff : UInt64) - argument) :
    runOperationV1 invocation
        (checkedAddMachineV1 accountData #[before, argument])
        (.checkedAdd 2 0 1 arithmeticOverflowError) =
      .ok (checkedAddMachineV1 accountData
        #[before, argument, before + argument]) := by
  have hgetBefore :
      getLocalV1 (checkedAddMachineV1 accountData #[before, argument]) 0 =
        .ok before := by rfl
  have hgetArgument :
      getLocalV1 (checkedAddMachineV1 accountData #[before, argument]) 1 =
        .ok argument := by rfl
  simp only [runOperationV1]
  rw [hgetBefore]
  simp only [Bind.bind, Except.bind]
  rw [hgetArgument]
  simp only
  rw [if_pos hnoOverflow]
  rfl

private theorem runOperationV1_checkedAdd_overflow
    (invocation : InvocationObservationV1)
    (accountData : ByteArray)
    (before argument : UInt64)
    (hoverflow : ¬ before ≤ (0xffffffffffffffff : UInt64) - argument) :
    runOperationV1 invocation
        (checkedAddMachineV1 accountData #[before, argument])
        (.checkedAdd 2 0 1 arithmeticOverflowError) =
      .error (.arithmeticOverflow arithmeticOverflowError) := by
  have hgetBefore :
      getLocalV1 (checkedAddMachineV1 accountData #[before, argument]) 0 =
        .ok before := by rfl
  have hgetArgument :
      getLocalV1 (checkedAddMachineV1 accountData #[before, argument]) 1 =
        .ok argument := by rfl
  simp only [runOperationV1]
  rw [hgetBefore]
  simp only [Bind.bind, Except.bind]
  rw [hgetArgument]
  simp only
  rw [if_neg hoverflow]

private theorem runOperationV1_checkedAdd_store
    (invocation : InvocationObservationV1)
    (accountData postData : ByteArray)
    (before argument : UInt64)
    (accountIndex byteOffset : Nat)
    (haccount : accountIndex = 0)
    (hstore : writeUInt64LEV1 accountData byteOffset (before + argument) =
      some postData) :
    runOperationV1 invocation
        (checkedAddMachineV1 accountData
          #[before, argument, before + argument])
        (.storeState accountIndex byteOffset 2) =
      .ok (checkedAddMachineV1 postData
        #[before, argument, before + argument]) := by
  subst accountIndex
  simp [runOperationV1, checkedAddMachineV1, getLocalV1,
    writeAccountUInt64LEV1, hstore, Pure.pure, Except.pure, Bind.bind,
    Except.bind]

private theorem runOperationV1_checkedAdd_loadPostState
    (invocation : InvocationObservationV1)
    (postData : ByteArray)
    (before argument : UInt64)
    (accountIndex byteOffset : Nat)
    (haccount : accountIndex = 0)
    (hpostField : readUInt64LEV1 postData byteOffset =
      some (before + argument)) :
    runOperationV1 invocation
        (checkedAddMachineV1 postData
          #[before, argument, before + argument])
        (.loadState 0 accountIndex byteOffset) =
      .ok (checkedAddMachineV1 postData
        #[before + argument, argument, before + argument]) := by
  subst accountIndex
  simp [runOperationV1, checkedAddMachineV1, setLocalV1, hpostField]

private theorem runOperationV1_checkedAdd_setReturnData
    (invocation : InvocationObservationV1)
    (postData : ByteArray)
    (before argument : UInt64) :
    runOperationV1 invocation
        (checkedAddMachineV1 postData
          #[before + argument, argument, before + argument])
        (.setReturnData 8 0) =
      .ok (checkedAddMachineV1 postData
        #[before + argument, argument, before + argument]
        (some (encodeU64le (before + argument)))) := by
  simp [runOperationV1, checkedAddMachineV1, getLocalV1]

private theorem runOperationsV1_of_unaryUInt64CheckedAddStaticAlignment
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (parameterValueId : ValueIdV1)
    (entryName parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData postData : ByteArray)
    (discriminatorValue before argument : UInt64)
    (halignment : UnaryUInt64CheckedAddStaticAlignmentV1 data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR)
    (hfield : readUInt64LEV1 accountData binding.byteOffset = some before)
    (hnoOverflow : before ≤ (0xffffffffffffffff : UInt64) - argument)
    (hstore : writeUInt64LEV1 accountData binding.byteOffset
      (before + argument) = some postData)
    (hpostField : readUInt64LEV1 postData binding.byteOffset =
      some (before + argument)) :
    runOperationsV1 handlerIR.operations.toList
        (unaryUInt64InvocationV1 accountData discriminatorValue argument false
          true)
        { accounts :=
            (unaryUInt64InvocationV1 accountData discriminatorValue argument
              false true).accounts } =
      .ok {
        accounts := #[{
          isDuplicate := false
          ownerCurrentProgram := true
          isSigner := false
          isWritable := true
          data := postData
        }]
        locals := #[before + argument, argument, before + argument]
        returnData := some (encodeU64le (before + argument))
      } := by
  rw [halignment.handlerIRExact]
  change runOperationsV1
      [.loadState 0 binding.accountIndex binding.byteOffset, .loadParam 1 8,
        .checkedAdd 2 0 1 arithmeticOverflowError,
        .storeState binding.accountIndex binding.byteOffset 2,
        .loadState 0 binding.accountIndex binding.byteOffset,
        .setReturnData 8 0]
      (unaryUInt64InvocationV1 accountData discriminatorValue argument false true)
      (checkedAddMachineV1 accountData) =
    .ok (checkedAddMachineV1 postData
      #[before + argument, argument, before + argument]
      (some (encodeU64le (before + argument))))
  simp only [runOperationsV1]
  rw [runOperationV1_checkedAdd_loadInitialState _ _ _ _ _ _
    halignment.accountZero hfield]
  simp only [Bind.bind, Except.bind]
  rw [runOperationV1_checkedAdd_loadArgument]
  simp only
  rw [runOperationV1_checkedAdd_add _ _ _ _ hnoOverflow]
  simp only
  rw [runOperationV1_checkedAdd_store _ _ _ _ _ _ _ halignment.accountZero
    hstore]
  simp only
  rw [runOperationV1_checkedAdd_loadPostState _ _ _ _ _ _
    halignment.accountZero hpostField]
  simp only
  rw [runOperationV1_checkedAdd_setReturnData]

private theorem runOperationsV1_of_unaryUInt64CheckedAddStaticAlignment_overflow
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (parameterValueId : ValueIdV1)
    (entryName parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData : ByteArray)
    (discriminatorValue before argument : UInt64)
    (halignment : UnaryUInt64CheckedAddStaticAlignmentV1 data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR)
    (hfield : readUInt64LEV1 accountData binding.byteOffset = some before)
    (hoverflow : ¬ before ≤ (0xffffffffffffffff : UInt64) - argument) :
    runOperationsV1 handlerIR.operations.toList
        (unaryUInt64InvocationV1 accountData discriminatorValue argument false
          true)
        { accounts :=
            (unaryUInt64InvocationV1 accountData discriminatorValue argument
              false true).accounts } =
      .error (.arithmeticOverflow arithmeticOverflowError) := by
  rw [halignment.handlerIRExact]
  change runOperationsV1
      [.loadState 0 binding.accountIndex binding.byteOffset, .loadParam 1 8,
        .checkedAdd 2 0 1 arithmeticOverflowError,
        .storeState binding.accountIndex binding.byteOffset 2,
        .loadState 0 binding.accountIndex binding.byteOffset,
        .setReturnData 8 0]
      (unaryUInt64InvocationV1 accountData discriminatorValue argument false true)
      (checkedAddMachineV1 accountData) =
    .error (.arithmeticOverflow arithmeticOverflowError)
  simp only [runOperationsV1]
  rw [runOperationV1_checkedAdd_loadInitialState _ _ _ _ _ _
    halignment.accountZero hfield]
  simp only [Bind.bind, Except.bind]
  rw [runOperationV1_checkedAdd_loadArgument]
  simp only
  rw [runOperationV1_checkedAdd_overflow _ _ _ _ hoverflow]

/-- Exact successful execution and committed account observation for a
    statically aligned production checked-add entry. -/
theorem observeHandlerIRV1_of_unaryUInt64CheckedAddStaticAlignment
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (parameterValueId : ValueIdV1)
    (entryName parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData postData : ByteArray)
    (discriminatorValue before argument : UInt64)
    (halignment : UnaryUInt64CheckedAddStaticAlignmentV1 data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue)
    (hdataLength : accountData.size = plan.stateAccount.exactDataLen)
    (hheader : readUInt64LEV1 accountData plan.stateAccount.headerOffset =
      some plan.stateAccount.initializedMarker)
    (hfield : readUInt64LEV1 accountData binding.byteOffset = some before)
    (hnoOverflow :
      before ≤ (0xffffffffffffffff : UInt64) - argument)
    (hstore : writeUInt64LEV1 accountData binding.byteOffset
      (before + argument) = some postData)
    (hpostField : readUInt64LEV1 postData binding.byteOffset =
      some (before + argument)) :
    observeHandlerIRV1 handlerIR
      (unaryUInt64InvocationV1 accountData discriminatorValue argument false
        true) = {
      invocation := unaryUInt64InvocationV1 accountData discriminatorValue
        argument false true
      outcome := .returned (some (encodeU64le (before + argument)))
      postAccounts := #[{
        isDuplicate := false
        ownerCurrentProgram := true
        isSigner := false
        isWritable := true
        data := postData
      }]
    } := by
  have hsupported : isSupportedOneFieldUInt64HandlerIRV1 handlerIR = true := by
    simp [isSupportedOneFieldUInt64HandlerIRV1,
      isSupportedUnaryUInt64CheckedAddHandlerIRV1_of_alignment data plan binding
        callableId parameterValueId entryName parameterName discriminator
        handler handlerIR halignment]
  have hhandlerDiscriminator :
      discriminatorToLeU64V1 handlerIR.discriminator = .ok discriminatorValue :=
    by simpa [halignment.handlerIRExact] using hdiscriminator
  have hchecks :
      runChecksV1 handlerIR.checks.toList
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true) = .ok () := by
    exact runChecksV1_of_unaryUInt64CheckedAddStaticAlignment data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR accountData discriminatorValue argument halignment hdataLength
      hheader
  have hoperations :
      runOperationsV1 handlerIR.operations.toList
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true)
          { accounts :=
              (unaryUInt64InvocationV1 accountData discriminatorValue argument
                false true).accounts } =
        .ok {
          accounts := #[{
            isDuplicate := false
            ownerCurrentProgram := true
            isSigner := false
            isWritable := true
            data := postData
          }]
          locals := #[before + argument, argument, before + argument]
          returnData := some (encodeU64le (before + argument))
        } := by
    exact runOperationsV1_of_unaryUInt64CheckedAddStaticAlignment data plan
      binding callableId parameterValueId entryName parameterName discriminator
      handler handlerIR accountData postData discriminatorValue before argument
      halignment hfield hnoOverflow hstore hpostField
  have houtcome :
      executeHandlerIRV1 handlerIR
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true) =
        .returned (some (encodeU64le (before + argument))) := by
    simp only [executeHandlerIRV1, isSupportedBoundedHandlerIRV1,
      isSupportedBoundedUInt64HandlerIRV1, hsupported, Bool.true_or,
      Bool.not_true]
    rw [runDispatchV1_unaryUInt64InvocationV1 _ _ _ _ false
      hhandlerDiscriminator]
    rw [hchecks, hoperations, halignment.handlerIRExact]
    rfl
  have haccounts :
      executeHandlerIRWithAccountsV1 handlerIR
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true) =
        (.returned (some (encodeU64le (before + argument))), #[{
          isDuplicate := false
          ownerCurrentProgram := true
          isSigner := false
          isWritable := true
          data := postData
        }]) := by
    simp only [executeHandlerIRWithAccountsV1, isSupportedBoundedHandlerIRV1,
      isSupportedBoundedUInt64HandlerIRV1, hsupported, Bool.true_or,
      Bool.not_true]
    rw [runDispatchV1_unaryUInt64InvocationV1 _ _ _ _ false
      hhandlerDiscriminator]
    rw [hchecks, hoperations, halignment.handlerIRExact]
    rfl
  unfold observeHandlerIRV1
  rw [houtcome, haccounts, halignment.handlerIRExact]
  rfl

/-- Checked-add overflow traps before every write and therefore exposes the
    original account snapshot. -/
theorem observeHandlerIRV1_of_unaryUInt64CheckedAddStaticAlignment_overflow
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (parameterValueId : ValueIdV1)
    (entryName parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData : ByteArray)
    (discriminatorValue before argument : UInt64)
    (halignment : UnaryUInt64CheckedAddStaticAlignmentV1 data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue)
    (hdataLength : accountData.size = plan.stateAccount.exactDataLen)
    (hheader : readUInt64LEV1 accountData plan.stateAccount.headerOffset =
      some plan.stateAccount.initializedMarker)
    (hfield : readUInt64LEV1 accountData binding.byteOffset = some before)
    (hoverflow :
      ¬ before ≤ (0xffffffffffffffff : UInt64) - argument) :
    observeHandlerIRV1 handlerIR
      (unaryUInt64InvocationV1 accountData discriminatorValue argument false
        true) = {
      invocation := unaryUInt64InvocationV1 accountData discriminatorValue
        argument false true
      outcome := .trapped (.arithmeticOverflow arithmeticOverflowError)
      postAccounts :=
        (unaryUInt64InvocationV1 accountData discriminatorValue argument false
          true).accounts
    } := by
  have hsupported : isSupportedOneFieldUInt64HandlerIRV1 handlerIR = true := by
    simp [isSupportedOneFieldUInt64HandlerIRV1,
      isSupportedUnaryUInt64CheckedAddHandlerIRV1_of_alignment data plan binding
        callableId parameterValueId entryName parameterName discriminator
        handler handlerIR halignment]
  have hhandlerDiscriminator :
      discriminatorToLeU64V1 handlerIR.discriminator = .ok discriminatorValue :=
    by simpa [halignment.handlerIRExact] using hdiscriminator
  have hchecks :
      runChecksV1 handlerIR.checks.toList
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true) = .ok () := by
    exact runChecksV1_of_unaryUInt64CheckedAddStaticAlignment data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR accountData discriminatorValue argument halignment hdataLength
      hheader
  have hoperations :
      runOperationsV1 handlerIR.operations.toList
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true)
          { accounts :=
              (unaryUInt64InvocationV1 accountData discriminatorValue argument
                false true).accounts } =
        .error (.arithmeticOverflow arithmeticOverflowError) := by
    exact
      runOperationsV1_of_unaryUInt64CheckedAddStaticAlignment_overflow data plan
        binding callableId parameterValueId entryName parameterName discriminator
        handler handlerIR accountData discriminatorValue before argument
        halignment hfield hoverflow
  have houtcome :
      executeHandlerIRV1 handlerIR
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true) =
        .trapped (.arithmeticOverflow arithmeticOverflowError) := by
    simp only [executeHandlerIRV1, isSupportedBoundedHandlerIRV1,
      isSupportedBoundedUInt64HandlerIRV1, hsupported, Bool.true_or,
      Bool.not_true]
    rw [runDispatchV1_unaryUInt64InvocationV1 _ _ _ _ false
      hhandlerDiscriminator]
    rw [hchecks, hoperations]
    rfl
  have haccounts :
      executeHandlerIRWithAccountsV1 handlerIR
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true) =
        (.trapped (.arithmeticOverflow arithmeticOverflowError),
          (unaryUInt64InvocationV1 accountData discriminatorValue argument false
            true).accounts) := by
    simp only [executeHandlerIRWithAccountsV1, isSupportedBoundedHandlerIRV1,
      isSupportedBoundedUInt64HandlerIRV1, hsupported, Bool.true_or,
      Bool.not_true]
    rw [runDispatchV1_unaryUInt64InvocationV1 _ _ _ _ false
      hhandlerDiscriminator]
    rw [hchecks, hoperations]
    rfl
  unfold observeHandlerIRV1
  rw [houtcome, haccounts, halignment.handlerIRExact]
  rfl

/-- Kernel-checked Reference→Solana join for the successful production
    StateCell checked-add entry. Both executions consume the same retained
    Semantic callable and the same UInt64 inputs; the final conjunct relates
    the committed logical state to the production account bytes. This theorem
    stops at HandlerIR and does not cover emitted sBPF or the Solana runtime. -/
theorem unaryUInt64CheckedAdd_reference_handlerIR_join
    (admitted : AdmittedReferenceSliceV1)
    (pre post : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (parameterValueId : ValueIdV1)
    (entryName parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData postData : ByteArray)
    (invocationContext context : Array ContextInputV1)
    (vault : ReferenceVaultSeedV1)
    (discriminatorValue before argument : UInt64)
    (halignment : UnaryUInt64CheckedAddStaticAlignmentV1 data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR)
    (hadmittedData : admitted.data = data)
    (hgate :
      gateInvocation admitted pre {
          callableId
          args := #[{
            typeId := binding.semanticTypeId
            valueBytes := encodeU64le argument
          }]
          context := invocationContext
        } =
        .ready {
          id := callableId
          kind := .entry
          name := some entryName
          params := #[{
            valueId := parameterValueId
            name := parameterName
            typeId := binding.semanticTypeId
            visibility := .public_
          }]
          result := {
            typeId := binding.semanticTypeId
            visibility := .public_
          }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[
              {
                result := some {
                  valueId := 1
                  typeId := binding.semanticTypeId
                }
                op := .stateLoad binding.semanticStateId
              },
              {
                result := some {
                  valueId := 2
                  typeId := binding.semanticTypeId
                }
                op := .binary .add 1 parameterValueId
              },
              {
                result := none
                op := .stateStore binding.semanticStateId 2
              },
              {
                result := some {
                  valueId := 3
                  typeId := binding.semanticTypeId
                }
                op := .stateLoad binding.semanticStateId
              }
            ]
            terminator := .return_ (some 3)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[encodeU64le before] context false)
    (haccount : UInt64LogicalStateAccountRelV1 data plan binding pre accountData
      before)
    (hencode : encodeLogicalStateValuesV1 data true
      #[encodeU64le (before + argument)] = .ok post)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue)
    (hnoOverflow : before.toNat + argument.toNat < 2 ^ 64)
    (hstore : writeUInt64LEV1 accountData binding.byteOffset
      (before + argument) = some postData)
    (hpostDataLength : postData.size = plan.stateAccount.exactDataLen)
    (hpostHeader : readUInt64LEV1 postData plan.stateAccount.headerOffset =
      some plan.stateAccount.initializedMarker)
    (hpostField : readUInt64LEV1 postData binding.byteOffset =
      some (before + argument)) :
    stepReferenceSliceV1 admitted pre {
        callableId
        args := #[{
          typeId := binding.semanticTypeId
          valueBytes := encodeU64le argument
        }]
        context := invocationContext
      } #[] vault = .returned post (some {
        typeId := binding.semanticTypeId
        valueBytes := encodeU64le (before + argument)
      }) #[] ∧
    observeHandlerIRV1 handlerIR
      (unaryUInt64InvocationV1 accountData discriminatorValue argument false
        true) = {
      invocation := unaryUInt64InvocationV1 accountData discriminatorValue
        argument false true
      outcome := .returned (some (encodeU64le (before + argument)))
      postAccounts := #[{
        isDuplicate := false
        ownerCurrentProgram := true
        isSigner := false
        isWritable := true
        data := postData
      }]
    } ∧
    UInt64LogicalStateAccountRelV1 data plan binding post postData
      (before + argument) := by
  have hcanonicalBefore :
      validateValueBytesV1 data.types binding.semanticTypeId
        (encodeU64le before) = .ok () := by
    apply validateValueBytesV1_uint64_of_size data.types binding.semanticTypeId
      {
        id := binding.semanticTypeId
        name := none
        shape := .uint 64
      }
    · exact halignment.bindingRel.1
    · rfl
    · exact encodeU64le_size before
  have hcanonicalArgument :
      validateValueBytesV1 data.types binding.semanticTypeId
        (encodeU64le argument) = .ok () := by
    apply validateValueBytesV1_uint64_of_size data.types binding.semanticTypeId
      {
        id := binding.semanticTypeId
        name := none
        shape := .uint 64
      }
    · exact halignment.bindingRel.1
    · rfl
    · exact encodeU64le_size argument
  have hstate : data.logicalState[0]? = some {
      id := 0
      name := binding.stateName
      typeId := binding.semanticTypeId
      visibility := .public_
    } := by
    simpa [halignment.stateZero] using halignment.bindingRel.2.1
  have hsumBytes :
      natToLeBytesV1 (before.toNat + argument.toNat) 8 =
        encodeU64le (before + argument) := by
    rw [← natToLeBytesV1_uint64_eq_encodeU64le (before + argument),
      UInt64.toNat_add, Nat.mod_eq_of_lt hnoOverflow]
  have hreferenceEncode :
      encodeLogicalStateValuesV1 data true #[natToLeBytesV1
        (leBytesToNatV1 (encodeU64le before) +
          leBytesToNatV1 (encodeU64le argument)) 8] = .ok post := by
    simpa only [leBytesToNatV1_encodeU64le, hsumBytes] using hencode
  have hreference :=
    stepReferenceSliceV1_ready_add_parameter_one_returned admitted pre post data
      (encodeU64le before) (encodeU64le argument) binding.semanticTypeId
      binding.stateName parameterName callableId (some entryName)
      invocationContext context vault hadmittedData halignment.bindingRel.1 hstate
      hcanonicalBefore hcanonicalArgument (by
        simpa only [leBytesToNatV1_encodeU64le] using hnoOverflow)
      hreferenceEncode (by
        simpa [halignment.stateZero, halignment.parameterZero] using hgate)
  have htargetGuard :
      before ≤ (0xffffffffffffffff : UInt64) - argument :=
    (checkedAddGuardV1_iff_toNat_sum_fits before argument).2 hnoOverflow
  have htarget :=
    observeHandlerIRV1_of_unaryUInt64CheckedAddStaticAlignment data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR accountData postData discriminatorValue before argument
      halignment hdiscriminator haccount.2.2.1 haccount.2.2.2.1
      haccount.2.2.2.2 htargetGuard hstore hpostField
  refine ⟨?_, htarget, ?_⟩
  · simpa only [leBytesToNatV1_encodeU64le, hsumBytes] using hreference
  · exact uint64LogicalStateAccountRelV1_of_encode data plan binding post postData
      (before + argument) hencode hpostDataLength hpostHeader hpostField

/-- Kernel-checked Reference→Solana join for checked-add overflow. The
    Reference outcome carries the exact pre-state, while the target observation
    carries the exact pre-invocation account snapshot; no state write occurs on
    either side. This theorem stops at HandlerIR. -/
theorem unaryUInt64CheckedAddOverflow_reference_handlerIR_join
    (admitted : AdmittedReferenceSliceV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (parameterValueId : ValueIdV1)
    (entryName parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (accountData : ByteArray)
    (invocationContext context : Array ContextInputV1)
    (vault : ReferenceVaultSeedV1)
    (discriminatorValue before argument : UInt64)
    (halignment : UnaryUInt64CheckedAddStaticAlignmentV1 data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR)
    (hadmittedData : admitted.data = data)
    (hgate :
      gateInvocation admitted pre {
          callableId
          args := #[{
            typeId := binding.semanticTypeId
            valueBytes := encodeU64le argument
          }]
          context := invocationContext
        } =
        .ready {
          id := callableId
          kind := .entry
          name := some entryName
          params := #[{
            valueId := parameterValueId
            name := parameterName
            typeId := binding.semanticTypeId
            visibility := .public_
          }]
          result := {
            typeId := binding.semanticTypeId
            visibility := .public_
          }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[
              {
                result := some {
                  valueId := 1
                  typeId := binding.semanticTypeId
                }
                op := .stateLoad binding.semanticStateId
              },
              {
                result := some {
                  valueId := 2
                  typeId := binding.semanticTypeId
                }
                op := .binary .add 1 parameterValueId
              },
              {
                result := none
                op := .stateStore binding.semanticStateId 2
              },
              {
                result := some {
                  valueId := 3
                  typeId := binding.semanticTypeId
                }
                op := .stateLoad binding.semanticStateId
              }
            ]
            terminator := .return_ (some 3)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[encodeU64le before] context false)
    (haccount : UInt64LogicalStateAccountRelV1 data plan binding pre accountData
      before)
    (hdiscriminator :
      discriminatorToLeU64V1 discriminator = .ok discriminatorValue)
    (hoverflow :
      ¬ before.toNat + argument.toNat < 2 ^ 64) :
    stepReferenceSliceV1 admitted pre {
        callableId
        args := #[{
          typeId := binding.semanticTypeId
          valueBytes := encodeU64le argument
        }]
        context := invocationContext
      } #[] vault =
        .reverted (.standard .arithmeticOverflow) pre ∧
    observeHandlerIRV1 handlerIR
      (unaryUInt64InvocationV1 accountData discriminatorValue argument false
        true) = {
      invocation := unaryUInt64InvocationV1 accountData discriminatorValue
        argument false true
      outcome := .trapped (.arithmeticOverflow arithmeticOverflowError)
      postAccounts :=
        (unaryUInt64InvocationV1 accountData discriminatorValue argument false
          true).accounts
    } ∧
    UInt64LogicalStateAccountRelV1 data plan binding pre accountData before := by
  have hcanonicalBefore :
      validateValueBytesV1 data.types binding.semanticTypeId
        (encodeU64le before) = .ok () := by
    apply validateValueBytesV1_uint64_of_size data.types binding.semanticTypeId
      {
        id := binding.semanticTypeId
        name := none
        shape := .uint 64
      }
    · exact halignment.bindingRel.1
    · rfl
    · exact encodeU64le_size before
  have hcanonicalArgument :
      validateValueBytesV1 data.types binding.semanticTypeId
        (encodeU64le argument) = .ok () := by
    apply validateValueBytesV1_uint64_of_size data.types binding.semanticTypeId
      {
        id := binding.semanticTypeId
        name := none
        shape := .uint 64
      }
    · exact halignment.bindingRel.1
    · rfl
    · exact encodeU64le_size argument
  have hstate : data.logicalState[0]? = some {
      id := 0
      name := binding.stateName
      typeId := binding.semanticTypeId
      visibility := .public_
    } := by
    simpa [halignment.stateZero] using halignment.bindingRel.2.1
  have hreference :=
    stepReferenceSliceV1_ready_add_parameter_one_overflow_reverted admitted pre
      data (encodeU64le before) (encodeU64le argument) binding.semanticTypeId
      binding.stateName parameterName callableId (some entryName)
      invocationContext context vault hadmittedData halignment.bindingRel.1 hstate
      hcanonicalBefore hcanonicalArgument (by
        simpa only [leBytesToNatV1_encodeU64le] using hoverflow)
      (by simpa [halignment.stateZero, halignment.parameterZero] using hgate)
  have htargetOverflow :
      ¬ before ≤ (0xffffffffffffffff : UInt64) - argument :=
    (not_congr (checkedAddGuardV1_iff_toNat_sum_fits before argument)).2
      hoverflow
  have htarget :=
    observeHandlerIRV1_of_unaryUInt64CheckedAddStaticAlignment_overflow data plan
      binding callableId parameterValueId entryName parameterName discriminator
      handler handlerIR accountData discriminatorValue before argument halignment
      hdiscriminator haccount.2.2.1 haccount.2.2.2.1 haccount.2.2.2.2
      htargetOverflow
  exact ⟨hreference, htarget, haccount⟩

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
  simp [executeHandlerIRV1, isSupportedBoundedHandlerIRV1,
    isSupportedBoundedUInt64HandlerIRV1,
    isSupportedOneFieldUInt64HandlerIRV1,
    isSupportedNullaryUInt64ViewHandlerIRV1,
    recognizeNullaryUInt64ViewHandlerIRV1, runDispatchV1, runChecksV1, runCheckV1,
    runOperationsV1, runOperationV1, nullaryUInt64ViewInvocationV1,
    halignment.accountZero, hdiscriminator, readUInt64LEV1_encodeU64le,
    encodeU64le_size, hdataLength, hheader, hfield, setLocalV1, getLocalV1,
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
  simp [executeHandlerIRV1, isSupportedBoundedHandlerIRV1,
    isSupportedBoundedUInt64HandlerIRV1,
    isSupportedOneFieldUInt64HandlerIRV1,
    isSupportedNullaryUInt64ViewHandlerIRV1,
    recognizeNullaryUInt64ViewHandlerIRV1, halignment.accountZero, runDispatchV1,
    readUInt64LEV1, hdiscriminator, Except.toOption]

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
  simp [executeHandlerIRV1, isSupportedBoundedHandlerIRV1,
    isSupportedBoundedUInt64HandlerIRV1,
    isSupportedOneFieldUInt64HandlerIRV1,
    isSupportedNullaryUInt64ViewHandlerIRV1,
    recognizeNullaryUInt64ViewHandlerIRV1, halignment.accountZero, runDispatchV1,
    nullaryUInt64ViewInvocationV1, hdiscriminator,
    readUInt64LEV1_encodeU64le, hne, Except.toOption]

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
  simp [executeHandlerIRV1, isSupportedBoundedHandlerIRV1,
    isSupportedBoundedUInt64HandlerIRV1,
    isSupportedOneFieldUInt64HandlerIRV1,
    isSupportedNullaryUInt64ViewHandlerIRV1,
    recognizeNullaryUInt64ViewHandlerIRV1, runDispatchV1, runChecksV1, runCheckV1,
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
  have hsupported : isSupportedBoundedHandlerIRV1 handlerIR = true := by
    rw [halignment.handlerIRExact]
    simp [isSupportedBoundedHandlerIRV1,
      isSupportedBoundedUInt64HandlerIRV1,
      isSupportedOneFieldUInt64HandlerIRV1,
      isSupportedNullaryUInt64ViewHandlerIRV1,
      recognizeNullaryUInt64ViewHandlerIRV1, halignment.accountZero]
  simp only [executeHandlerIRV1, hsupported, Bool.not_true]
  rw [halignment.handlerIRExact]
  simp [runDispatchV1, runChecksV1, runCheckV1,
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
  refine ⟨hcanonical, hsize, hreference, ?_, ?_⟩
  simpa [observeHandlerIRV1, haccount.2.1] using htarget
  rw [halignment.handlerIRExact]
  rfl

end ProofForgeV2.Targets.Solana

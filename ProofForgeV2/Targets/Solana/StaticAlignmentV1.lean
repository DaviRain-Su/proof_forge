import ProofForgeV2.Semantic.ReferenceMachineV1
import ProofForgeV2.Targets.Solana.EmitIRV1

/-!
# Solana StaticAlignmentV1

This module starts the Solana Reference→target refinement track with bounded,
target-owned recipes over the production single-state-account layout. The
admitted set includes UInt64 handlers and structurally recognized multiword
aggregate views.

The relations below classify existing public `Plan` / `HandlerIR` syntax. They
do not construct a second Plan, lower Semantic IR, execute sBPF, or define a
second DSL/business state machine. Unsupported handler shapes fail closed.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Semantic
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- One public UInt64 logical-state row and its exact Solana account field. -/
structure UInt64StateAccountBindingV1 where
  semanticStateId : StateIdV1
  semanticTypeId : TypeIdV1
  stateName : String
  physicalFieldIndex : Nat
  accountIndex : Nat
  byteOffset : Nat
  deriving Repr

/-- Representation relation between retained Semantic state and the sole
    production Solana account-layout row selected by a binding. -/
def UInt64StateAccountBindingRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1) : Prop :=
  data.types[binding.semanticTypeId.toNat]? = some {
    id := binding.semanticTypeId
    name := none
    shape := .uint 64
  } ∧
  data.logicalState[binding.semanticStateId.toNat]? = some {
    id := binding.semanticStateId
    name := binding.stateName
    typeId := binding.semanticTypeId
    visibility := .public_
  } ∧
  plan.stateAccount.fields[binding.physicalFieldIndex]? = some {
    sourceId := binding.semanticStateId.toNat
    name := binding.stateName
    accountIndex := binding.accountIndex
    byteOffset := binding.byteOffset
    byteWidth := 8
    endianness := .little
    isInt := false
  } ∧
  plan.stateAccount.stateLeaves[binding.semanticStateId.toNat]? =
    some #[binding.physicalFieldIndex]

/-- One public `Option UInt64` logical-state row and its exact two-word Solana
    tag/payload fields. This carrier is contract-independent; state and field
    names, indices, accounts, and offsets remain explicit. -/
structure OptionUInt64StateAccountBindingV1 where
  semanticStateId : StateIdV1
  optionTypeId : TypeIdV1
  elementTypeId : TypeIdV1
  stateName : String
  tagPhysicalFieldIndex : Nat
  payloadPhysicalFieldIndex : Nat
  accountIndex : Nat
  tagByteOffset : Nat
  payloadByteOffset : Nat
  deriving Repr

/-- Representation relation between a retained `Option UInt64` Semantic state
    row and the production Solana tag/payload layout. It classifies encodings
    only and does not define Option operations or a business transition. -/
def OptionUInt64StateAccountBindingRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : OptionUInt64StateAccountBindingV1) : Prop :=
  data.types[binding.elementTypeId.toNat]? = some {
    id := binding.elementTypeId
    name := none
    shape := .uint 64
  } ∧
  data.types[binding.optionTypeId.toNat]? = some {
    id := binding.optionTypeId
    name := none
    shape := .option binding.elementTypeId
  } ∧
  data.logicalState[binding.semanticStateId.toNat]? = some {
    id := binding.semanticStateId
    name := binding.stateName
    typeId := binding.optionTypeId
    visibility := .public_
  } ∧
  plan.stateAccount.fields[binding.tagPhysicalFieldIndex]? = some {
    sourceId := binding.semanticStateId.toNat
    name := s!"{binding.stateName}_tag"
    accountIndex := binding.accountIndex
    byteOffset := binding.tagByteOffset
    byteWidth := 8
    endianness := .little
    isInt := false
  } ∧
  plan.stateAccount.fields[binding.payloadPhysicalFieldIndex]? = some {
    sourceId := binding.semanticStateId.toNat
    name := s!"{binding.stateName}_p0"
    accountIndex := binding.accountIndex
    byteOffset := binding.payloadByteOffset
    byteWidth := 8
    endianness := .little
    isInt := false
  } ∧
  plan.stateAccount.stateLeaves[binding.semanticStateId.toNat]? = some
    #[binding.tagPhysicalFieldIndex, binding.payloadPhysicalFieldIndex] ∧
  plan.stateAccount.index = binding.accountIndex ∧
  binding.accountIndex = 0 ∧
  plan.stateAccount.headerWidth = 8 ∧
  plan.stateAccount.headerOffset ≠ binding.tagByteOffset ∧
  plan.stateAccount.headerOffset ≠ binding.payloadByteOffset ∧
  binding.tagByteOffset ≠ binding.payloadByteOffset

private def checkOptionUInt64ElementTypeDeclV1
    (decl : Option TypeDeclV1)
    (binding : OptionUInt64StateAccountBindingV1) : Bool :=
  match decl with
  | some { id, name := none, shape := .uint width } =>
      id == binding.elementTypeId && width == 64
  | _ => false

private theorem checkOptionUInt64ElementTypeDeclV1_eq_true_iff
    (decl : Option TypeDeclV1)
    (binding : OptionUInt64StateAccountBindingV1) :
    checkOptionUInt64ElementTypeDeclV1 decl binding = true ↔
      decl = some {
        id := binding.elementTypeId
        name := none
        shape := .uint 64
      } := by
  cases decl with
  | none => simp [checkOptionUInt64ElementTypeDeclV1]
  | some decl =>
      cases decl with
      | mk id name shape =>
          cases name <;> cases shape <;>
            simp [checkOptionUInt64ElementTypeDeclV1]

private def checkOptionUInt64OptionTypeDeclV1
    (decl : Option TypeDeclV1)
    (binding : OptionUInt64StateAccountBindingV1) : Bool :=
  match decl with
  | some { id, name := none, shape := .option elementTypeId } =>
      id == binding.optionTypeId && elementTypeId == binding.elementTypeId
  | _ => false

private theorem checkOptionUInt64OptionTypeDeclV1_eq_true_iff
    (decl : Option TypeDeclV1)
    (binding : OptionUInt64StateAccountBindingV1) :
    checkOptionUInt64OptionTypeDeclV1 decl binding = true ↔
      decl = some {
        id := binding.optionTypeId
        name := none
        shape := .option binding.elementTypeId
      } := by
  cases decl with
  | none => simp [checkOptionUInt64OptionTypeDeclV1]
  | some decl =>
      cases decl with
      | mk id name shape =>
          cases name <;> cases shape <;>
            simp [checkOptionUInt64OptionTypeDeclV1]

private def checkOptionUInt64StateDeclV1
    (decl : Option StateDeclV1)
    (binding : OptionUInt64StateAccountBindingV1) : Bool :=
  match decl with
  | some { id, name, typeId, visibility := .public_ } =>
      id == binding.semanticStateId && name == binding.stateName &&
        typeId == binding.optionTypeId
  | _ => false

private theorem checkOptionUInt64StateDeclV1_eq_true_iff
    (decl : Option StateDeclV1)
    (binding : OptionUInt64StateAccountBindingV1) :
    checkOptionUInt64StateDeclV1 decl binding = true ↔
      decl = some {
        id := binding.semanticStateId
        name := binding.stateName
        typeId := binding.optionTypeId
        visibility := .public_
      } := by
  cases decl with
  | none => simp [checkOptionUInt64StateDeclV1]
  | some decl =>
      cases decl with
      | mk id name typeId visibility =>
          cases visibility <;>
            simp [checkOptionUInt64StateDeclV1, and_assoc]

private def checkOptionUInt64StateFieldV1
    (field : Option StateField)
    (binding : OptionUInt64StateAccountBindingV1)
    (name : String)
    (byteOffset : Nat) : Bool :=
  match field with
  | some field =>
      field.sourceId == binding.semanticStateId.toNat &&
        field.name == name && field.accountIndex == binding.accountIndex &&
        field.byteOffset == byteOffset && field.byteWidth == 8 &&
        !field.isInt
  | none => false

private theorem checkOptionUInt64StateFieldV1_eq_true_iff
    (field : Option StateField)
    (binding : OptionUInt64StateAccountBindingV1)
    (name : String)
    (byteOffset : Nat) :
    checkOptionUInt64StateFieldV1 field binding name byteOffset = true ↔
      field = some {
        sourceId := binding.semanticStateId.toNat
        name
        accountIndex := binding.accountIndex
        byteOffset
        byteWidth := 8
        endianness := .little
        isInt := false
      } := by
  cases field with
  | none => simp [checkOptionUInt64StateFieldV1]
  | some field =>
      cases field with
      | mk sourceId actualName accountIndex actualOffset byteWidth endianness isInt =>
          cases endianness <;> cases isInt <;>
            simp [checkOptionUInt64StateFieldV1, and_assoc]

/-- Executable classifier for the exact production `Option UInt64`
    tag/payload binding. -/
def checkOptionUInt64StateAccountBindingRelV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : OptionUInt64StateAccountBindingV1) : Bool :=
  checkOptionUInt64ElementTypeDeclV1
      data.types[binding.elementTypeId.toNat]? binding &&
  checkOptionUInt64OptionTypeDeclV1
      data.types[binding.optionTypeId.toNat]? binding &&
  checkOptionUInt64StateDeclV1
      data.logicalState[binding.semanticStateId.toNat]? binding &&
  checkOptionUInt64StateFieldV1
      plan.stateAccount.fields[binding.tagPhysicalFieldIndex]? binding
      s!"{binding.stateName}_tag" binding.tagByteOffset &&
  checkOptionUInt64StateFieldV1
      plan.stateAccount.fields[binding.payloadPhysicalFieldIndex]? binding
      s!"{binding.stateName}_p0" binding.payloadByteOffset &&
  decide (plan.stateAccount.stateLeaves[binding.semanticStateId.toNat]? = some
    #[binding.tagPhysicalFieldIndex, binding.payloadPhysicalFieldIndex]) &&
  decide (plan.stateAccount.index = binding.accountIndex) &&
  decide (binding.accountIndex = 0) &&
  decide (plan.stateAccount.headerWidth = 8) &&
  decide (plan.stateAccount.headerOffset ≠ binding.tagByteOffset) &&
  decide (plan.stateAccount.headerOffset ≠ binding.payloadByteOffset) &&
  decide (binding.tagByteOffset ≠ binding.payloadByteOffset)

theorem checkOptionUInt64StateAccountBindingRelV1_eq_true_iff
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : OptionUInt64StateAccountBindingV1) :
    checkOptionUInt64StateAccountBindingRelV1 data plan binding = true ↔
      OptionUInt64StateAccountBindingRelV1 data plan binding := by
  simp only [checkOptionUInt64StateAccountBindingRelV1, Bool.and_eq_true,
    checkOptionUInt64ElementTypeDeclV1_eq_true_iff,
    checkOptionUInt64OptionTypeDeclV1_eq_true_iff,
    checkOptionUInt64StateDeclV1_eq_true_iff,
    checkOptionUInt64StateFieldV1_eq_true_iff, decide_eq_true_eq,
    OptionUInt64StateAccountBindingRelV1]
  simp only [and_assoc]

/-- Public syntax recovered from a nullary UInt64 view `Handler`. The access
    account and body-load account remain separate fields so recognition alone
    cannot silently assert their equality. Static alignment joins them. -/
structure NullaryUInt64ViewHandlerShapeV1 where
  viewName : String
  discriminator : String
  accessAccountIndex : Nat
  exactDataLen : Nat
  bodyAccountIndex : Nat
  fieldOffset : Nat
  deriving Repr

/-- Recognize exactly one nullary, read-only UInt64 account load and return. -/
def recognizeNullaryUInt64ViewHandlerV1
    (handler : Handler) : Option NullaryUInt64ViewHandlerShapeV1 :=
  match handler.params.toList, handler.mode, handler.resultKind,
      handler.accountAccess.ownerPolicy, handler.accountAccess.signerRequired,
      handler.accountAccess.writableRequired,
      handler.accountAccess.initialization, handler.body.toList with
  | [], .view, .u64, .currentProgram, false, false, .mustBeInitialized,
      [.returnValue (.stateLoad bodyAccountIndex fieldOffset)] =>
    some {
      viewName := handler.name
      discriminator := handler.discriminator
      accessAccountIndex := handler.accountAccess.accountIndex
      exactDataLen := handler.accountAccess.exactDataLen
      bodyAccountIndex
      fieldOffset
    }
  | _, _, _, _, _, _, _, _ => none

/-- Successful source-handler recognition determines the complete handler. -/
theorem recognizeNullaryUInt64ViewHandlerV1_sound
    (handler : Handler)
    (shape : NullaryUInt64ViewHandlerShapeV1)
    (hrecognize : recognizeNullaryUInt64ViewHandlerV1 handler = some shape) :
    handler = {
      name := shape.viewName
      discriminator := shape.discriminator
      params := #[]
      mode := .view
      resultKind := .u64
      accountAccess := {
        accountIndex := shape.accessAccountIndex
        ownerPolicy := .currentProgram
        exactDataLen := shape.exactDataLen
        signerRequired := false
        writableRequired := false
        initialization := .mustBeInitialized
      }
      body := #[.returnValue
        (.stateLoad shape.bodyAccountIndex shape.fieldOffset)]
    } := by
  rcases handler with ⟨name, discriminator, params, mode, resultKind,
    accountAccess, body⟩
  rcases accountAccess with ⟨accountIndex, ownerPolicy, exactDataLen,
    signerRequired, writableRequired, initialization⟩
  simp only [recognizeNullaryUInt64ViewHandlerV1] at hrecognize
  split at hrecognize
  · cases hrecognize
    have hparams : params = #[] :=
      Array.toList_inj.mp (by assumption)
    have hbody : body = #[.returnValue (.stateLoad _ _)] :=
      Array.toList_inj.mp (by assumption)
    cases hparams
    cases hbody
    rfl
  · contradiction

/-- Public syntax recovered from the exact bounded `HandlerIR` recipe. Every
    repeated account occurrence is retained independently and joined only by
    the static-alignment relation. -/
structure NullaryUInt64ViewHandlerIRShapeV1 where
  viewName : String
  discriminator : String
  accessAccountIndex : Nat
  accessDataLen : Nat
  accountCount : Nat
  nonDuplicateAccountIndex : Nat
  inputLen : Nat
  ownerAccountIndex : Nat
  dataLenAccountIndex : Nat
  checkedDataLen : Nat
  headerAccountIndex : Nat
  headerOffset : Nat
  initializedMarker : UInt64
  loadAccountIndex : Nat
  fieldOffset : Nat
  deriving Repr

/-- Recognize the complete production check/load/return recipe for a nullary
    UInt64 view. Additional, missing, or reordered operations are rejected. -/
def recognizeNullaryUInt64ViewHandlerIRV1
    (handlerIR : HandlerIR) : Option NullaryUInt64ViewHandlerIRShapeV1 :=
  match handlerIR.params.toList, handlerIR.mode, handlerIR.resultKind,
      handlerIR.accountAccess.ownerPolicy,
      handlerIR.accountAccess.signerRequired,
      handlerIR.accountAccess.writableRequired,
      handlerIR.accountAccess.initialization,
      handlerIR.checks.toList, handlerIR.operations.toList with
  | [], .view, .u64, .currentProgram, false, false, .mustBeInitialized, [
      .numAccounts accountCount,
      .accountNonDuplicate nonDuplicateAccountIndex,
      .instructionDataLen inputLen,
      .ownerCurrentProgram ownerAccountIndex,
      .accountDataLen dataLenAccountIndex checkedDataLen,
      .headerEquals headerAccountIndex headerOffset initializedMarker
    ], [
      .loadState 0 loadAccountIndex fieldOffset,
      .setReturnData 8 0
    ] =>
    some {
      viewName := handlerIR.name
      discriminator := handlerIR.discriminator
      accessAccountIndex := handlerIR.accountAccess.accountIndex
      accessDataLen := handlerIR.accountAccess.exactDataLen
      accountCount
      nonDuplicateAccountIndex
      inputLen
      ownerAccountIndex
      dataLenAccountIndex
      checkedDataLen
      headerAccountIndex
      headerOffset
      initializedMarker
      loadAccountIndex
      fieldOffset
    }
  | _, _, _, _, _, _, _, _, _ => none

/-- Successful IR recognition determines every check and operation. -/
theorem recognizeNullaryUInt64ViewHandlerIRV1_sound
    (handlerIR : HandlerIR)
    (shape : NullaryUInt64ViewHandlerIRShapeV1)
    (hrecognize :
      recognizeNullaryUInt64ViewHandlerIRV1 handlerIR = some shape) :
    handlerIR = {
      name := shape.viewName
      discriminator := shape.discriminator
      params := #[]
      mode := .view
      resultKind := .u64
      accountAccess := {
        accountIndex := shape.accessAccountIndex
        ownerPolicy := .currentProgram
        exactDataLen := shape.accessDataLen
        signerRequired := false
        writableRequired := false
        initialization := .mustBeInitialized
      }
      checks := #[
        .numAccounts shape.accountCount,
        .accountNonDuplicate shape.nonDuplicateAccountIndex,
        .instructionDataLen shape.inputLen,
        .ownerCurrentProgram shape.ownerAccountIndex,
        .accountDataLen shape.dataLenAccountIndex shape.checkedDataLen,
        .headerEquals shape.headerAccountIndex shape.headerOffset
          shape.initializedMarker
      ]
      operations := #[
        .loadState 0 shape.loadAccountIndex shape.fieldOffset,
        .setReturnData 8 0
      ]
    } := by
  rcases handlerIR with ⟨name, discriminator, params, mode, resultKind,
    accountAccess, checks, operations⟩
  rcases accountAccess with ⟨accountIndex, ownerPolicy, exactDataLen,
    signerRequired, writableRequired, initialization⟩
  simp only [recognizeNullaryUInt64ViewHandlerIRV1] at hrecognize
  split at hrecognize
  · cases hrecognize
    have hparams : params = #[] :=
      Array.toList_inj.mp (by assumption)
    have hchecks : checks = #[
        .numAccounts _,
        .accountNonDuplicate _,
        .instructionDataLen _,
        .ownerCurrentProgram _,
        .accountDataLen _ _,
        .headerEquals _ _ _
      ] := Array.toList_inj.mp (by assumption)
    have hoperations : operations = #[
        .loadState 0 _ _,
        .setReturnData 8 0
      ] := Array.toList_inj.mp (by assumption)
    cases hparams
    cases hchecks
    cases hoperations
    rfl
  · contradiction

/-- Internal-consistency gate for the recognized nullary UInt64 view recipe.
    Recognition alone preserves repeated account fields independently; this
    predicate joins them and rejects a tampered production artifact. -/
def isSupportedNullaryUInt64ViewHandlerIRV1 (handlerIR : HandlerIR) : Bool :=
  match recognizeNullaryUInt64ViewHandlerIRV1 handlerIR with
  | some shape =>
      shape.accountCount == 1 && shape.accessAccountIndex == 0 &&
        shape.nonDuplicateAccountIndex == shape.accessAccountIndex &&
        shape.inputLen == 8 &&
        shape.ownerAccountIndex == shape.accessAccountIndex &&
        shape.dataLenAccountIndex == shape.accessAccountIndex &&
        shape.checkedDataLen == shape.accessDataLen &&
        shape.headerAccountIndex == shape.accessAccountIndex &&
        shape.loadAccountIndex == shape.accessAccountIndex
  | none => false

/-- Exact production unary UInt64 initializer gate. It admits only the
    generated zero/load/store/header sequence and joins every repeated account,
    parameter, field, and header occurrence. -/
def isSupportedUnaryUInt64InitializerHandlerIRV1
    (handlerIR : HandlerIR) : Bool :=
  match handlerIR.params.toList, handlerIR.mode, handlerIR.resultKind,
      handlerIR.accountAccess.ownerPolicy,
      handlerIR.accountAccess.signerRequired,
      handlerIR.accountAccess.writableRequired,
      handlerIR.accountAccess.initialization,
      handlerIR.checks.toList, handlerIR.operations.toList with
  | [{ dataOffset := paramOffset, byteWidth := 8, endianness := .little,
        isInt := false, .. }],
      .initialize, .u64, .currentProgram, true, true, .mustBeUninitialized, [
      .numAccounts accountCount,
      .accountNonDuplicate nonDuplicateAccountIndex,
      .instructionDataLen inputLen,
      .ownerCurrentProgram ownerAccountIndex,
      .accountDataLen dataLenAccountIndex checkedDataLen,
      .signer signerAccountIndex,
      .writable writableAccountIndex,
      .headerEquals headerAccountIndex headerOffset 0
    ], [
      .zeroState zeroAccountIndex fieldOffset,
      .loadParam 0 loadedParamOffset,
      .storeState storeAccountIndex storedFieldOffset 0,
      .setHeader setHeaderAccountIndex setHeaderOffset _
    ] =>
      let accountIndex := handlerIR.accountAccess.accountIndex
      accountCount == 1 && accountIndex == 0 &&
        nonDuplicateAccountIndex == accountIndex && inputLen == 16 &&
        ownerAccountIndex == accountIndex && dataLenAccountIndex == accountIndex &&
        checkedDataLen == handlerIR.accountAccess.exactDataLen &&
        signerAccountIndex == accountIndex && writableAccountIndex == accountIndex &&
        headerAccountIndex == accountIndex && zeroAccountIndex == accountIndex &&
        storeAccountIndex == accountIndex && setHeaderAccountIndex == accountIndex &&
        paramOffset == 8 && loadedParamOffset == paramOffset &&
        storedFieldOffset == fieldOffset && setHeaderOffset == headerOffset &&
        fieldOffset != headerOffset
  | _, _, _, _, _, _, _, _, _ => false

/-- Exact production unary UInt64 checked-add gate. Unknown, missing,
    additional, or inconsistent checks and operations are rejected. -/
def isSupportedUnaryUInt64CheckedAddHandlerIRV1
    (handlerIR : HandlerIR) : Bool :=
  match handlerIR.params.toList, handlerIR.mode, handlerIR.resultKind,
      handlerIR.accountAccess.ownerPolicy,
      handlerIR.accountAccess.signerRequired,
      handlerIR.accountAccess.writableRequired,
      handlerIR.accountAccess.initialization,
      handlerIR.checks.toList, handlerIR.operations.toList with
  | [{ dataOffset := paramOffset, byteWidth := 8, endianness := .little,
        isInt := false, .. }],
      .mutate, .u64, .currentProgram, false, true, .mustBeInitialized, [
      .numAccounts accountCount,
      .accountNonDuplicate nonDuplicateAccountIndex,
      .instructionDataLen inputLen,
      .ownerCurrentProgram ownerAccountIndex,
      .accountDataLen dataLenAccountIndex checkedDataLen,
      .writable writableAccountIndex,
      .headerEquals headerAccountIndex _ _
    ], [
      .loadState 0 loadAccountIndex fieldOffset,
      .loadParam 1 loadedParamOffset,
      .checkedAdd 2 0 1 errorCode,
      .storeState storeAccountIndex storedFieldOffset 2,
      .loadState 0 returnLoadAccountIndex returnFieldOffset,
      .setReturnData 8 0
    ] =>
      let accountIndex := handlerIR.accountAccess.accountIndex
      accountCount == 1 && accountIndex == 0 &&
        nonDuplicateAccountIndex == accountIndex && inputLen == 16 &&
        ownerAccountIndex == accountIndex && dataLenAccountIndex == accountIndex &&
        checkedDataLen == handlerIR.accountAccess.exactDataLen &&
        writableAccountIndex == accountIndex && headerAccountIndex == accountIndex &&
        loadAccountIndex == accountIndex && storeAccountIndex == accountIndex &&
        returnLoadAccountIndex == accountIndex && paramOffset == 8 &&
        loadedParamOffset == paramOffset && storedFieldOffset == fieldOffset &&
        returnFieldOffset == fieldOffset && errorCode == arithmeticOverflowError
  | _, _, _, _, _, _, _, _, _ => false

/-- A branch in the bounded UInt64 switch-view recipe must compute one UInt64
    from either an account word or a literal, publish it, and return. This is a
    HandlerIR shape check; it does not interpret an Option or any DSL pattern. -/
private def isSupportedUInt64SwitchReturnBranchV1
    (accountIndex : Nat) (operations : Array Operation) : Bool :=
  match operations.toList with
  | [.loadState destination loadedAccountIndex _,
      .setReturnData 8 returnedSource, .returnNone] =>
      loadedAccountIndex == accountIndex && returnedSource == destination
  | [.literal destination _, .setReturnData 8 returnedSource, .returnNone] =>
      returnedSource == destination
  | _ => false

/-- Bounded nullary UInt64 view with one production `switchRegion`. The
    scrutinee and branch bodies remain ordinary HandlerIR operations, so this
    admits Option/Enum-like target recipes without adding another DSL
    interpreter or naming a contract. Unknown checks, operations, account
    indices, or branch shapes remain rejected. -/
def isSupportedNullaryUInt64SwitchViewHandlerIRV1
    (handlerIR : HandlerIR) : Bool :=
  match handlerIR.params.toList, handlerIR.mode, handlerIR.resultKind,
      handlerIR.accountAccess.ownerPolicy,
      handlerIR.accountAccess.signerRequired,
      handlerIR.accountAccess.writableRequired,
      handlerIR.accountAccess.initialization,
      handlerIR.checks.toList, handlerIR.operations.toList with
  | [], .view, .u64, .currentProgram, false, false, .mustBeInitialized, [
      .numAccounts accountCount,
      .accountNonDuplicate nonDuplicateAccountIndex,
      .instructionDataLen inputLen,
      .ownerCurrentProgram ownerAccountIndex,
      .accountDataLen dataLenAccountIndex checkedDataLen,
      .headerEquals headerAccountIndex _ _
    ], [
      .loadState scrutinee loadAccountIndex _,
      .switchRegion switchScrutinee cases defaultOps
    ] =>
      let accountIndex := handlerIR.accountAccess.accountIndex
      accountCount == 1 && accountIndex == 0 &&
        nonDuplicateAccountIndex == accountIndex && inputLen == 8 &&
        ownerAccountIndex == accountIndex && dataLenAccountIndex == accountIndex &&
        checkedDataLen == handlerIR.accountAccess.exactDataLen &&
        headerAccountIndex == accountIndex && loadAccountIndex == accountIndex &&
        switchScrutinee == scrutinee && !cases.isEmpty &&
        cases.all (fun candidate =>
          isSupportedUInt64SwitchReturnBranchV1 accountIndex candidate.2) &&
        isSupportedUInt64SwitchReturnBranchV1 accountIndex defaultOps
  | _, _, _, _, _, _, _, _, _ => false

private def isSupportedAggregateReturnLoadsV1
    (operations : Array Operation)
    (values : Array Nat)
    (accountIndex leafCount : Nat) : Bool :=
  operations.size == leafCount + 1 && values.size == leafCount &&
    (List.range leafCount).all fun index =>
      match operations[index]?, values[index]? with
      | some (.loadState destination loadedAccountIndex _), some returnedSource =>
          loadedAccountIndex == accountIndex && returnedSource == destination &&
            (List.range index).all fun previous =>
              match values[previous]? with
              | some previousSource => previousSource != returnedSource
              | none => false
      | _, _ => false

/-- Contract-independent nullary aggregate view recipe. Every 8-byte result
    leaf must come from a production account load and the final operation must
    publish those exact locals through one `setReturnDataMulti`. -/
def isSupportedNullaryAggregateViewHandlerIRV1
    (handlerIR : HandlerIR) : Bool :=
  match handlerIR.params.toList, handlerIR.mode, handlerIR.resultKind,
      handlerIR.accountAccess.ownerPolicy,
      handlerIR.accountAccess.signerRequired,
      handlerIR.accountAccess.writableRequired,
      handlerIR.accountAccess.initialization,
      handlerIR.checks.toList with
  | [], .view, .aggregate leaves, .currentProgram, false, false,
      .mustBeInitialized, [
        .numAccounts accountCount,
        .accountNonDuplicate nonDuplicateAccountIndex,
        .instructionDataLen inputLen,
        .ownerCurrentProgram ownerAccountIndex,
        .accountDataLen dataLenAccountIndex checkedDataLen,
        .headerEquals headerAccountIndex _ _
      ] =>
      let accountIndex := handlerIR.accountAccess.accountIndex
      let leafCount := leaves.size
      accountCount == 1 && accountIndex == 0 &&
        nonDuplicateAccountIndex == accountIndex && inputLen == 8 &&
        ownerAccountIndex == accountIndex && dataLenAccountIndex == accountIndex &&
        checkedDataLen == handlerIR.accountAccess.exactDataLen &&
        headerAccountIndex == accountIndex && leafCount > 0 && leafCount ≤ 8 &&
        leaves.all (·.byteWidth == 8) &&
        match handlerIR.operations[leafCount]? with
        | some (.setReturnDataMulti values) =>
            isSupportedAggregateReturnLoadsV1 handlerIR.operations values
              accountIndex leafCount
        | _ => false
  | _, _, _, _, _, _, _, _ => false

/-- Compatibility entry point for the original one-field consumers. Its
    accepted set now also includes the bounded switch-view recipe below. -/
def isSupportedOneFieldUInt64HandlerIRV1 (handlerIR : HandlerIR) : Bool :=
  isSupportedNullaryUInt64ViewHandlerIRV1 handlerIR ||
    isSupportedUnaryUInt64InitializerHandlerIRV1 handlerIR ||
    isSupportedUnaryUInt64CheckedAddHandlerIRV1 handlerIR ||
    isSupportedNullaryUInt64SwitchViewHandlerIRV1 handlerIR

/-- Contract-independent name for the complete closed set of bounded
    UInt64-returning recipes interpreted by `HandlerSemanticsV1`. -/
def isSupportedBoundedUInt64HandlerIRV1 (handlerIR : HandlerIR) : Bool :=
  isSupportedOneFieldUInt64HandlerIRV1 handlerIR

/-- Complete contract-independent closed set interpreted by the bounded
    HandlerIR evaluator, including multiword aggregate views. -/
def isSupportedBoundedHandlerIRV1 (handlerIR : HandlerIR) : Bool :=
  isSupportedBoundedUInt64HandlerIRV1 handlerIR ||
    isSupportedNullaryAggregateViewHandlerIRV1 handlerIR

/-- Complete syntax recovered from the exact two-leaf aggregate recipe. The
    recognizer keeps repeated account and layout fields separate so callers
    must explicitly join them to a production Plan. -/
structure NullaryTwoLeafAggregateViewHandlerIRShapeV1 where
  viewName : String
  discriminator : String
  firstIsInt : Bool
  secondIsInt : Bool
  accessAccountIndex : Nat
  accessDataLen : Nat
  accountCount : Nat
  nonDuplicateAccountIndex : Nat
  inputLen : Nat
  ownerAccountIndex : Nat
  dataLenAccountIndex : Nat
  checkedDataLen : Nat
  headerAccountIndex : Nat
  headerOffset : Nat
  initializedMarker : UInt64
  firstLoadAccountIndex : Nat
  firstOffset : Nat
  secondLoadAccountIndex : Nat
  secondOffset : Nat
  returnSources : Array Nat
  deriving Repr

/-- Recognize exactly two ordered 8-byte account loads followed by one ordered
    aggregate return. Contract and method names are data, never dispatch keys. -/
def recognizeNullaryTwoLeafAggregateViewHandlerIRV1
    (handlerIR : HandlerIR) :
    Option NullaryTwoLeafAggregateViewHandlerIRShapeV1 :=
  match handlerIR.params.toList, handlerIR.mode, handlerIR.resultKind,
      handlerIR.accountAccess.ownerPolicy,
      handlerIR.accountAccess.signerRequired,
      handlerIR.accountAccess.writableRequired,
      handlerIR.accountAccess.initialization with
  | [], .view, .aggregate leaves, .currentProgram, false, false,
      .mustBeInitialized =>
    match leaves.toList, handlerIR.checks.toList,
        handlerIR.operations.toList with
    | [
        { isInt := firstIsInt, byteWidth := 8 },
        { isInt := secondIsInt, byteWidth := 8 }
      ], [
        .numAccounts accountCount,
        .accountNonDuplicate nonDuplicateAccountIndex,
        .instructionDataLen inputLen,
        .ownerCurrentProgram ownerAccountIndex,
        .accountDataLen dataLenAccountIndex checkedDataLen,
        .headerEquals headerAccountIndex headerOffset initializedMarker
      ], [
        .loadState 0 firstLoadAccountIndex firstOffset,
        .loadState 1 secondLoadAccountIndex secondOffset,
        .setReturnDataMulti returnSources
      ] => some {
        viewName := handlerIR.name
        discriminator := handlerIR.discriminator
        firstIsInt
        secondIsInt
        accessAccountIndex := handlerIR.accountAccess.accountIndex
        accessDataLen := handlerIR.accountAccess.exactDataLen
        accountCount
        nonDuplicateAccountIndex
        inputLen
        ownerAccountIndex
        dataLenAccountIndex
        checkedDataLen
        headerAccountIndex
        headerOffset
        initializedMarker
        firstLoadAccountIndex
        firstOffset
        secondLoadAccountIndex
        secondOffset
        returnSources
      }
    | _, _, _ => none
  | _, _, _, _, _, _, _ => none

/-- Successful recognition determines the complete two-leaf HandlerIR. -/
theorem recognizeNullaryTwoLeafAggregateViewHandlerIRV1_sound
    (handlerIR : HandlerIR)
    (shape : NullaryTwoLeafAggregateViewHandlerIRShapeV1)
    (hrecognize :
      recognizeNullaryTwoLeafAggregateViewHandlerIRV1 handlerIR = some shape) :
    handlerIR = {
      name := shape.viewName
      discriminator := shape.discriminator
      params := #[]
      mode := .view
      resultKind := .aggregate #[
        { isInt := shape.firstIsInt, byteWidth := 8 },
        { isInt := shape.secondIsInt, byteWidth := 8 }
      ]
      accountAccess := {
        accountIndex := shape.accessAccountIndex
        ownerPolicy := .currentProgram
        exactDataLen := shape.accessDataLen
        signerRequired := false
        writableRequired := false
        initialization := .mustBeInitialized
      }
      checks := #[
        .numAccounts shape.accountCount,
        .accountNonDuplicate shape.nonDuplicateAccountIndex,
        .instructionDataLen shape.inputLen,
        .ownerCurrentProgram shape.ownerAccountIndex,
        .accountDataLen shape.dataLenAccountIndex shape.checkedDataLen,
        .headerEquals shape.headerAccountIndex shape.headerOffset
          shape.initializedMarker
      ]
      operations := #[
        .loadState 0 shape.firstLoadAccountIndex shape.firstOffset,
        .loadState 1 shape.secondLoadAccountIndex shape.secondOffset,
        .setReturnDataMulti shape.returnSources
      ]
    } := by
  rcases handlerIR with ⟨name, discriminator, params, mode, resultKind,
    accountAccess, checks, operations⟩
  rcases accountAccess with ⟨accountIndex, ownerPolicy, exactDataLen,
    signerRequired, writableRequired, initialization⟩
  simp only [recognizeNullaryTwoLeafAggregateViewHandlerIRV1] at hrecognize
  split at hrecognize
  · split at hrecognize
    · cases hrecognize
      congr <;> exact Array.toList_inj.mp (by assumption)
    · contradiction
  · contradiction

/-- Proof-carrying result of the exact two-leaf syntax recognizer. -/
structure CertifiedNullaryTwoLeafAggregateViewHandlerIRV1
    (handlerIR : HandlerIR) where
  private mk ::
  shape : NullaryTwoLeafAggregateViewHandlerIRShapeV1
  recognition :
    recognizeNullaryTwoLeafAggregateViewHandlerIRV1 handlerIR = some shape

/-- Package successful recognition so downstream production resolvers retain
    its equation rather than running a second unchecked parse. -/
def certifyNullaryTwoLeafAggregateViewHandlerIRV1
    (handlerIR : HandlerIR) :
    Option (CertifiedNullaryTwoLeafAggregateViewHandlerIRV1 handlerIR) :=
  match hrecognize :
      recognizeNullaryTwoLeafAggregateViewHandlerIRV1 handlerIR with
  | some shape => some <|
      CertifiedNullaryTwoLeafAggregateViewHandlerIRV1.mk shape hrecognize
  | none => none

/-- Joins every independently recognized target field to one production Plan.
    Keeping this separate from recognition makes tampering in any repeated
    account, layout, or return-source occurrence observable. -/
def NullaryTwoLeafAggregateViewHandlerIRShapeRelV1
    (plan : Plan)
    (firstOffset secondOffset : Nat)
    (firstIsInt secondIsInt : Bool)
    (viewName discriminator : String)
    (shape : NullaryTwoLeafAggregateViewHandlerIRShapeV1) : Prop :=
  shape.viewName = viewName ∧
  shape.discriminator = discriminator ∧
  shape.firstIsInt = firstIsInt ∧
  shape.secondIsInt = secondIsInt ∧
  shape.accessAccountIndex = plan.stateAccount.index ∧
  shape.accessDataLen = plan.stateAccount.exactDataLen ∧
  shape.accountCount = 1 ∧
  shape.nonDuplicateAccountIndex = plan.stateAccount.index ∧
  shape.inputLen = 8 ∧
  shape.ownerAccountIndex = plan.stateAccount.index ∧
  shape.dataLenAccountIndex = plan.stateAccount.index ∧
  shape.checkedDataLen = plan.stateAccount.exactDataLen ∧
  shape.headerAccountIndex = plan.stateAccount.index ∧
  shape.headerOffset = plan.stateAccount.headerOffset ∧
  shape.initializedMarker = plan.stateAccount.initializedMarker ∧
  shape.firstLoadAccountIndex = plan.stateAccount.index ∧
  shape.firstOffset = firstOffset ∧
  shape.secondLoadAccountIndex = plan.stateAccount.index ∧
  shape.secondOffset = secondOffset ∧
  shape.returnSources = #[0, 1] ∧
  plan.stateAccount.index = 0 ∧
  plan.stateAccount.headerWidth = 8 ∧
  plan.stateAccount.headerOffset ≠ firstOffset ∧
  plan.stateAccount.headerOffset ≠ secondOffset ∧
  firstOffset ≠ secondOffset

/-- Executable form of the repeated-field join. All compared values are
    primitive target metadata; no HandlerIR or business semantics are hashed or
    reinterpreted here. -/
def checkNullaryTwoLeafAggregateViewHandlerIRShapeRelV1
    (plan : Plan)
    (firstOffset secondOffset : Nat)
    (firstIsInt secondIsInt : Bool)
    (viewName discriminator : String)
    (shape : NullaryTwoLeafAggregateViewHandlerIRShapeV1) : Bool :=
  shape.viewName == viewName &&
  shape.discriminator == discriminator &&
  shape.firstIsInt == firstIsInt &&
  shape.secondIsInt == secondIsInt &&
  shape.accessAccountIndex == plan.stateAccount.index &&
  shape.accessDataLen == plan.stateAccount.exactDataLen &&
  shape.accountCount == 1 &&
  shape.nonDuplicateAccountIndex == plan.stateAccount.index &&
  shape.inputLen == 8 &&
  shape.ownerAccountIndex == plan.stateAccount.index &&
  shape.dataLenAccountIndex == plan.stateAccount.index &&
  shape.checkedDataLen == plan.stateAccount.exactDataLen &&
  shape.headerAccountIndex == plan.stateAccount.index &&
  shape.headerOffset == plan.stateAccount.headerOffset &&
  shape.initializedMarker == plan.stateAccount.initializedMarker &&
  shape.firstLoadAccountIndex == plan.stateAccount.index &&
  shape.firstOffset == firstOffset &&
  shape.secondLoadAccountIndex == plan.stateAccount.index &&
  shape.secondOffset == secondOffset &&
  shape.returnSources == #[0, 1] &&
  plan.stateAccount.index == 0 &&
  plan.stateAccount.headerWidth == 8 &&
  decide (plan.stateAccount.headerOffset ≠ firstOffset) &&
  decide (plan.stateAccount.headerOffset ≠ secondOffset) &&
  decide (firstOffset ≠ secondOffset)

theorem checkNullaryTwoLeafAggregateViewHandlerIRShapeRelV1_eq_true_iff
    (plan : Plan)
    (firstOffset secondOffset : Nat)
    (firstIsInt secondIsInt : Bool)
    (viewName discriminator : String)
    (shape : NullaryTwoLeafAggregateViewHandlerIRShapeV1) :
    checkNullaryTwoLeafAggregateViewHandlerIRShapeRelV1 plan firstOffset
        secondOffset firstIsInt secondIsInt viewName discriminator shape = true ↔
      NullaryTwoLeafAggregateViewHandlerIRShapeRelV1 plan firstOffset
        secondOffset firstIsInt secondIsInt viewName discriminator shape := by
  simp [checkNullaryTwoLeafAggregateViewHandlerIRShapeRelV1,
    NullaryTwoLeafAggregateViewHandlerIRShapeRelV1]
  simp only [and_assoc]

/-- Exact target-owned alignment for a nullary two-word aggregate view. The
    leaf signedness bits remain parameters because UInt64 and Int64 share the
    same 8-byte little-endian target representation. No contract or method name
    is recognized here. -/
structure NullaryTwoLeafAggregateViewStaticAlignmentV1
    (plan : Plan)
    (firstOffset secondOffset : Nat)
    (firstIsInt secondIsInt : Bool)
    (viewName discriminator : String)
    (handlerIR : HandlerIR) : Prop where
  accountZero : plan.stateAccount.index = 0
  stateAccountOwner : plan.stateAccount.ownerPolicy = .currentProgram
  headerWidth : plan.stateAccount.headerWidth = 8
  headerFirstDistinct : plan.stateAccount.headerOffset ≠ firstOffset
  headerSecondDistinct : plan.stateAccount.headerOffset ≠ secondOffset
  leafOffsetsDistinct : firstOffset ≠ secondOffset
  handlerIRExact : handlerIR = {
    name := viewName
    discriminator
    params := #[]
    mode := .view
    resultKind := .aggregate #[
      { isInt := firstIsInt, byteWidth := 8 },
      { isInt := secondIsInt, byteWidth := 8 }
    ]
    accountAccess := {
      accountIndex := plan.stateAccount.index
      ownerPolicy := .currentProgram
      exactDataLen := plan.stateAccount.exactDataLen
      signerRequired := false
      writableRequired := false
      initialization := .mustBeInitialized
    }
    checks := #[
      .numAccounts 1,
      .accountNonDuplicate plan.stateAccount.index,
      .instructionDataLen 8,
      .ownerCurrentProgram plan.stateAccount.index,
      .accountDataLen plan.stateAccount.index
        plan.stateAccount.exactDataLen,
      .headerEquals plan.stateAccount.index plan.stateAccount.headerOffset
        plan.stateAccount.initializedMarker
    ]
    operations := #[
      .loadState 0 plan.stateAccount.index firstOffset,
      .loadState 1 plan.stateAccount.index secondOffset,
      .setReturnDataMulti #[0, 1]
    ]
  }

/-- Recognition plus explicit Plan joins constructs the proof consumed by the
    evaluator. This theorem is independent of any contract or method name. -/
theorem nullaryTwoLeafAggregateViewStaticAlignmentV1_of_recognized
    (plan : Plan)
    (firstOffset secondOffset : Nat)
    (firstIsInt secondIsInt : Bool)
    (viewName discriminator : String)
    (handlerIR : HandlerIR)
    (shape : NullaryTwoLeafAggregateViewHandlerIRShapeV1)
    (hrecognize :
      recognizeNullaryTwoLeafAggregateViewHandlerIRV1 handlerIR = some shape)
    (howner : plan.stateAccount.ownerPolicy = .currentProgram)
    (hshape : NullaryTwoLeafAggregateViewHandlerIRShapeRelV1 plan firstOffset
      secondOffset firstIsInt secondIsInt viewName discriminator shape) :
    NullaryTwoLeafAggregateViewStaticAlignmentV1 plan firstOffset secondOffset
      firstIsInt secondIsInt viewName discriminator handlerIR := by
  rcases hshape with ⟨hname, hdiscriminator, hfirstIsInt, hsecondIsInt,
    haccessAccount, haccessLen, haccountCount, hnonDuplicate, hinputLen,
    hownerAccount, hdataLenAccount, hcheckedLen, hheaderAccount, hheaderOffset,
    hmarker, hfirstAccount, hfirstOffset, hsecondAccount, hsecondOffset,
    hreturnSources, haccountZero, hheaderWidth, hheaderFirst,
    hheaderSecond, hoffsets⟩
  refine {
    accountZero := haccountZero
    stateAccountOwner := howner
    headerWidth := hheaderWidth
    headerFirstDistinct := hheaderFirst
    headerSecondDistinct := hheaderSecond
    leafOffsetsDistinct := hoffsets
    handlerIRExact := ?_
  }
  rw [recognizeNullaryTwoLeafAggregateViewHandlerIRV1_sound handlerIR shape
    hrecognize]
  simp_all

/-- Every exact two-leaf aggregate alignment is in the bounded evaluator's
    closed structural support set. -/
theorem isSupportedNullaryAggregateViewHandlerIRV1_of_twoLeafAlignment
    (halignment : NullaryTwoLeafAggregateViewStaticAlignmentV1 plan
      firstOffset secondOffset firstIsInt secondIsInt viewName discriminator
      handlerIR) :
    isSupportedNullaryAggregateViewHandlerIRV1 handlerIR = true := by
  rw [halignment.handlerIRExact]
  simp [isSupportedNullaryAggregateViewHandlerIRV1,
    isSupportedAggregateReturnLoadsV1, halignment.accountZero]
  intro index hindex
  have hcases : index = 0 ∨ index = 1 := by omega
  rcases hcases with rfl | rfl <;> simp

/-- Exact semantic/account/Plan/IR alignment for the first bounded Solana
    target slice. It is syntax and representation only; execution is defined
    once in `HandlerSemanticsV1`. -/
structure NullaryUInt64ViewStaticAlignmentV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (viewName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR) : Prop where
  bindingRel : UInt64StateAccountBindingRelV1 data plan binding
  stateAccountIndex : plan.stateAccount.index = binding.accountIndex
  accountZero : binding.accountIndex = 0
  stateAccountOwner : plan.stateAccount.ownerPolicy = .currentProgram
  headerWidth : plan.stateAccount.headerWidth = 8
  headerDistinct : plan.stateAccount.headerOffset ≠ binding.byteOffset
  handlerExact : handler = {
    name := viewName
    discriminator
    params := #[]
    mode := .view
    resultKind := .u64
    accountAccess := {
      accountIndex := binding.accountIndex
      ownerPolicy := .currentProgram
      exactDataLen := plan.stateAccount.exactDataLen
      signerRequired := false
      writableRequired := false
      initialization := .mustBeInitialized
    }
    body := #[.returnValue (.stateLoad binding.accountIndex binding.byteOffset)]
  }
  handlerIRExact : handlerIR = {
    name := viewName
    discriminator
    params := #[]
    mode := .view
    resultKind := .u64
    accountAccess := {
      accountIndex := binding.accountIndex
      ownerPolicy := .currentProgram
      exactDataLen := plan.stateAccount.exactDataLen
      signerRequired := false
      writableRequired := false
      initialization := .mustBeInitialized
    }
    checks := #[
      .numAccounts 1,
      .accountNonDuplicate binding.accountIndex,
      .instructionDataLen 8,
      .ownerCurrentProgram binding.accountIndex,
      .accountDataLen binding.accountIndex plan.stateAccount.exactDataLen,
      .headerEquals binding.accountIndex plan.stateAccount.headerOffset
        plan.stateAccount.initializedMarker
    ]
    operations := #[
      .loadState 0 binding.accountIndex binding.byteOffset,
      .setReturnData 8 0
    ]
  }

/-- Structural recognition plus semantic/account binding constructs the exact
    bounded static alignment. No private lowering is duplicated. -/
theorem nullaryUInt64ViewStaticAlignmentV1_of_recognized
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (viewName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (hbinding : UInt64StateAccountBindingRelV1 data plan binding)
    (haccount : plan.stateAccount.index = binding.accountIndex)
    (haccountZero : binding.accountIndex = 0)
    (howner : plan.stateAccount.ownerPolicy = .currentProgram)
    (hheaderWidth : plan.stateAccount.headerWidth = 8)
    (hdistinct : plan.stateAccount.headerOffset ≠ binding.byteOffset)
    (hhandler : recognizeNullaryUInt64ViewHandlerV1 handler = some {
      viewName
      discriminator
      accessAccountIndex := binding.accountIndex
      exactDataLen := plan.stateAccount.exactDataLen
      bodyAccountIndex := binding.accountIndex
      fieldOffset := binding.byteOffset
    })
    (hhandlerIR : recognizeNullaryUInt64ViewHandlerIRV1 handlerIR = some {
      viewName
      discriminator
      accessAccountIndex := binding.accountIndex
      accessDataLen := plan.stateAccount.exactDataLen
      accountCount := 1
      nonDuplicateAccountIndex := binding.accountIndex
      inputLen := 8
      ownerAccountIndex := binding.accountIndex
      dataLenAccountIndex := binding.accountIndex
      checkedDataLen := plan.stateAccount.exactDataLen
      headerAccountIndex := binding.accountIndex
      headerOffset := plan.stateAccount.headerOffset
      initializedMarker := plan.stateAccount.initializedMarker
      loadAccountIndex := binding.accountIndex
      fieldOffset := binding.byteOffset
    }) :
    NullaryUInt64ViewStaticAlignmentV1 data plan binding viewName discriminator
      handler handlerIR := by
  refine {
    bindingRel := hbinding
    stateAccountIndex := haccount
    accountZero := haccountZero
    stateAccountOwner := howner
    headerWidth := hheaderWidth
    headerDistinct := hdistinct
    handlerExact := ?_
    handlerIRExact := ?_
  }
  · exact recognizeNullaryUInt64ViewHandlerV1_sound handler _ hhandler
  · exact recognizeNullaryUInt64ViewHandlerIRV1_sound handlerIR _ hhandlerIR

/-- Production provenance for one selected source entry and full-body IR row.
    Both lookups are explicit because the Solana product rail also carries a
    separate CPI Plan/IR for account-role materialization. -/
structure ProductionNullaryUInt64ViewStaticAlignmentV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (entryIndex : Nat)
    (binding : UInt64StateAccountBindingV1)
    (viewName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR) : Prop where
  validatedProgram : validateSemanticProgramV1 program = .ok data
  validatedIR : validateIR ir = .ok ()
  sourcePlan : ir.sourcePlan = plan
  sourceEntry : plan.entries[entryIndex]? = some handler
  loweredHandler : ir.handlers[entryIndex + 1]? = some handlerIR
  staticAlignment : NullaryUInt64ViewStaticAlignmentV1 data plan binding
    viewName discriminator handler handlerIR

/-! ## Unary UInt64 initializer and checked-add entry alignment -/

/-- Exact semantic/account/Plan/HandlerIR alignment for the production
    one-field UInt64 initializer. This is a passive relation over existing
    artifacts; it neither lowers the callable nor executes another state
    machine. -/
structure UnaryUInt64InitializerStaticAlignmentV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (unitTypeId : TypeIdV1)
    (parameterValueId : ValueIdV1)
    (parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR) : Prop where
  bindingRel : UInt64StateAccountBindingRelV1 data plan binding
  stateZero : binding.semanticStateId = 0
  unitType : data.types[unitTypeId.toNat]? = some {
    id := unitTypeId
    name := none
    shape := .unit
  }
  callableExact : data.callables[callableId.toNat]? = some {
    id := callableId
    kind := .initializer
    name := none
    params := #[{
      valueId := parameterValueId
      name := parameterName
      typeId := binding.semanticTypeId
      visibility := .public_
    }]
    result := {
      typeId := unitTypeId
      visibility := .public_
    }
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
  }
  parameterZero : parameterValueId = 0
  stateAccountIndex : plan.stateAccount.index = binding.accountIndex
  accountZero : binding.accountIndex = 0
  stateAccountOwner : plan.stateAccount.ownerPolicy = .currentProgram
  headerWidth : plan.stateAccount.headerWidth = 8
  headerDistinct : plan.stateAccount.headerOffset ≠ binding.byteOffset
  handlerExact : handler = {
    name := "initialize"
    discriminator
    params := #[{
      sourceId := parameterValueId.toNat
      name := parameterName
      dataOffset := 8
      byteWidth := 8
      endianness := .little
      isInt := false
    }]
    mode := .initialize
    resultKind := .u64
    accountAccess := {
      accountIndex := binding.accountIndex
      ownerPolicy := .currentProgram
      exactDataLen := plan.stateAccount.exactDataLen
      signerRequired := true
      writableRequired := true
      initialization := .mustBeUninitialized
    }
    body := #[
      .store {
        accountIndex := binding.accountIndex
        byteOffset := binding.byteOffset
        value := .param 8
      },
      .returnNone
    ]
  }
  handlerIRExact : handlerIR = {
    name := "initialize"
    discriminator
    params := #[{
      sourceId := parameterValueId.toNat
      name := parameterName
      dataOffset := 8
      byteWidth := 8
      endianness := .little
      isInt := false
    }]
    mode := .initialize
    resultKind := .u64
    accountAccess := {
      accountIndex := binding.accountIndex
      ownerPolicy := .currentProgram
      exactDataLen := plan.stateAccount.exactDataLen
      signerRequired := true
      writableRequired := true
      initialization := .mustBeUninitialized
    }
    checks := #[
      .numAccounts 1,
      .accountNonDuplicate binding.accountIndex,
      .instructionDataLen 16,
      .ownerCurrentProgram binding.accountIndex,
      .accountDataLen binding.accountIndex plan.stateAccount.exactDataLen,
      .signer binding.accountIndex,
      .writable binding.accountIndex,
      .headerEquals binding.accountIndex plan.stateAccount.headerOffset 0
    ]
    operations := #[
      .zeroState binding.accountIndex binding.byteOffset,
      .loadParam 0 8,
      .storeState binding.accountIndex binding.byteOffset 0,
      .setHeader binding.accountIndex plan.stateAccount.headerOffset
        plan.stateAccount.initializedMarker
    ]
  }

/-- Exact semantic/account/Plan/HandlerIR alignment for the production unary
    UInt64 checked-add entry. Repeated account, field, parameter, local, and
    overflow-code uses are all fixed by complete artifact equality. -/
structure UnaryUInt64CheckedAddStaticAlignmentV1
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (parameterValueId : ValueIdV1)
    (entryName parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR) : Prop where
  bindingRel : UInt64StateAccountBindingRelV1 data plan binding
  stateZero : binding.semanticStateId = 0
  callableExact : data.callables[callableId.toNat]? = some {
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
  }
  parameterZero : parameterValueId = 0
  stateAccountIndex : plan.stateAccount.index = binding.accountIndex
  accountZero : binding.accountIndex = 0
  stateAccountOwner : plan.stateAccount.ownerPolicy = .currentProgram
  headerWidth : plan.stateAccount.headerWidth = 8
  headerDistinct : plan.stateAccount.headerOffset ≠ binding.byteOffset
  overflowCode : plan.arithmeticOverflowError = arithmeticOverflowError
  handlerExact : handler = {
    name := entryName
    discriminator
    params := #[{
      sourceId := parameterValueId.toNat
      name := parameterName
      dataOffset := 8
      byteWidth := 8
      endianness := .little
      isInt := false
    }]
    mode := .mutate
    resultKind := .u64
    accountAccess := {
      accountIndex := binding.accountIndex
      ownerPolicy := .currentProgram
      exactDataLen := plan.stateAccount.exactDataLen
      signerRequired := false
      writableRequired := true
      initialization := .mustBeInitialized
    }
    body := #[
      .store {
        accountIndex := binding.accountIndex
        byteOffset := binding.byteOffset
        value := .checkedAdd
          (.stateLoad binding.accountIndex binding.byteOffset) (.param 8)
      },
      .returnValue (.stateLoad binding.accountIndex binding.byteOffset)
    ]
  }
  handlerIRExact : handlerIR = {
    name := entryName
    discriminator
    params := #[{
      sourceId := parameterValueId.toNat
      name := parameterName
      dataOffset := 8
      byteWidth := 8
      endianness := .little
      isInt := false
    }]
    mode := .mutate
    resultKind := .u64
    accountAccess := {
      accountIndex := binding.accountIndex
      ownerPolicy := .currentProgram
      exactDataLen := plan.stateAccount.exactDataLen
      signerRequired := false
      writableRequired := true
      initialization := .mustBeInitialized
    }
    checks := #[
      .numAccounts 1,
      .accountNonDuplicate binding.accountIndex,
      .instructionDataLen 16,
      .ownerCurrentProgram binding.accountIndex,
      .accountDataLen binding.accountIndex plan.stateAccount.exactDataLen,
      .writable binding.accountIndex,
      .headerEquals binding.accountIndex plan.stateAccount.headerOffset
        plan.stateAccount.initializedMarker
    ]
    operations := #[
      .loadState 0 binding.accountIndex binding.byteOffset,
      .loadParam 1 8,
      .checkedAdd 2 0 1 arithmeticOverflowError,
      .storeState binding.accountIndex binding.byteOffset 2,
      .loadState 0 binding.accountIndex binding.byteOffset,
      .setReturnData 8 0
    ]
  }

/-- The complete initializer alignment is accepted by the evaluator's closed
    production recipe gate. -/
theorem isSupportedUnaryUInt64InitializerHandlerIRV1_of_alignment
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (unitTypeId : TypeIdV1)
    (parameterValueId : ValueIdV1)
    (parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (halignment : UnaryUInt64InitializerStaticAlignmentV1 data plan binding
      callableId unitTypeId parameterValueId parameterName discriminator
      handler handlerIR) :
    isSupportedUnaryUInt64InitializerHandlerIRV1 handlerIR = true := by
  rw [halignment.handlerIRExact]
  have hfieldDistinct :
      binding.byteOffset ≠ plan.stateAccount.headerOffset :=
    Ne.symm halignment.headerDistinct
  simp [isSupportedUnaryUInt64InitializerHandlerIRV1,
    halignment.accountZero, hfieldDistinct]

/-- The complete checked-add alignment is accepted by the evaluator's closed
    production recipe gate. -/
theorem isSupportedUnaryUInt64CheckedAddHandlerIRV1_of_alignment
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (parameterValueId : ValueIdV1)
    (entryName parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR)
    (halignment : UnaryUInt64CheckedAddStaticAlignmentV1 data plan binding
      callableId parameterValueId entryName parameterName discriminator handler
      handlerIR) :
    isSupportedUnaryUInt64CheckedAddHandlerIRV1 handlerIR = true := by
  rw [halignment.handlerIRExact]
  simp [isSupportedUnaryUInt64CheckedAddHandlerIRV1,
    halignment.accountZero]

/-- Production provenance for the selected initializer row. -/
structure ProductionUnaryUInt64InitializerStaticAlignmentV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (unitTypeId : TypeIdV1)
    (parameterValueId : ValueIdV1)
    (parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR) : Prop where
  validatedProgram : validateSemanticProgramV1 program = .ok data
  validatedIR : validateIR ir = .ok ()
  sourcePlan : ir.sourcePlan = plan
  sourceInitializer : plan.initializer = handler
  loweredHandler : ir.handlers[0]? = some handlerIR
  staticAlignment : UnaryUInt64InitializerStaticAlignmentV1 data plan binding
    callableId unitTypeId parameterValueId parameterName discriminator handler
    handlerIR

/-- Production provenance for one selected checked-add entry row. -/
structure ProductionUnaryUInt64CheckedAddStaticAlignmentV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (entryIndex : Nat)
    (binding : UInt64StateAccountBindingV1)
    (callableId : CallableIdV1)
    (parameterValueId : ValueIdV1)
    (entryName parameterName discriminator : String)
    (handler : Handler)
    (handlerIR : HandlerIR) : Prop where
  validatedProgram : validateSemanticProgramV1 program = .ok data
  validatedIR : validateIR ir = .ok ()
  sourcePlan : ir.sourcePlan = plan
  sourceEntry : plan.entries[entryIndex]? = some handler
  loweredHandler : ir.handlers[entryIndex + 1]? = some handlerIR
  staticAlignment : UnaryUInt64CheckedAddStaticAlignmentV1 data plan binding
    callableId parameterValueId entryName parameterName discriminator handler
    handlerIR

/-- The unique authoritative Reference machine returns the exact retained
    state bytes selected by a statically aligned Solana view. This theorem does
    not execute Solana target IR; `HandlerSemanticsV1` composes that separate
    target fact with this source-of-truth result. -/
theorem stepReferenceSliceV1_ready_viewLoad_returned_exact_of_solana_alignment
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
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (halignment : NullaryUInt64ViewStaticAlignmentV1 data plan binding
      viewName discriminator handler handlerIR)
    (hadmittedData : admitted.data = data)
    (hloaded : overlay[binding.semanticStateId.toNat]? = some loadedBytes)
    (hrespEmpty : responses.size = 0)
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
        } overlay context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned pre (some {
        typeId := binding.semanticTypeId
        valueBytes := loadedBytes
      }) #[] := by
  exact stepReferenceSliceV1_ready_viewLoad_returned_exact admitted pre
    invocation data overlay loadedBytes binding.semanticTypeId
    binding.semanticStateId binding.stateName callableId (some viewName)
    context responses vault hadmittedData halignment.bindingRel.1
    halignment.bindingRel.2.1 hloaded hrespEmpty hgate

end ProofForgeV2.Targets.Solana

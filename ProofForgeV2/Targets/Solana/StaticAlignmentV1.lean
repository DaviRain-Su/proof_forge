import ProofForgeV2.Semantic.ReferenceMachineV1
import ProofForgeV2.Targets.Solana.EmitIRV1

/-!
# Solana StaticAlignmentV1

This module starts the Solana Reference→target refinement track with one
bounded, target-owned slice: a nullary UInt64 view over the production
single-state-account layout.

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

/-- Closed set of HandlerIR recipes interpreted by `HandlerSemanticsV1`. -/
def isSupportedOneFieldUInt64HandlerIRV1 (handlerIR : HandlerIR) : Bool :=
  isSupportedNullaryUInt64ViewHandlerIRV1 handlerIR ||
    isSupportedUnaryUInt64InitializerHandlerIRV1 handlerIR ||
    isSupportedUnaryUInt64CheckedAddHandlerIRV1 handlerIR

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

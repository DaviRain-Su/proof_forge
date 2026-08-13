import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Targets.Near.EmitIRV1

/-!
# NEAR StaticAlignmentV1

Passive observation carriers and proposition-only representation relations for
the first Reference→NEAR refinement slice.

This module deliberately defines no target state transition, operation
interpreter, evaluator, rollback function, or `IR × input × storage → outcome`
function. Contract execution remains solely `SemanticProgramV1` plus
`ReferenceMachineV1`. The relations below can describe an externally obtained
NEAR observation and the exact static recipe that should be compared with it;
they do not claim that Wasm or NEAR executes that recipe correctly.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Passive snapshot of target KV observations. The function is supplied by an
    external runtime/formal-semantics boundary; this module never updates it. -/
structure StorageObservationV1 where
  lookup : String → Option ByteArray

/-- Passive call-boundary observation. `failureObserved` records only the
    external boundary result; it does not interpret a NEAR failure class. -/
structure CallObservationV1 where
  exportName : String
  input : ByteArray
  returnData : Option ByteArray
  failureObserved : Bool
  logs : Array ByteArray
  promises : Array ByteArray
  preStorage : StorageObservationV1
  postStorage : StorageObservationV1

/-- Explicit binding between one semantic UInt64 state declaration and one
    physical NEAR KV field. The first slice is intentionally scalar-only. -/
structure UInt64StateBindingV1 where
  semanticStateId : StateIdV1
  semanticTypeId : TypeIdV1
  semanticName : String
  physicalFieldIndex : Nat
  physicalKey : String
  deriving BEq, Repr

/-- A target storage row is the exact singleton, 8-byte little-endian
    realization of one public semantic UInt64 state declaration. -/
def UInt64StateBindingRelV1
    (data : SemanticProgramDataV1)
    (storage : StorageLayout)
    (binding : UInt64StateBindingV1) : Prop :=
  data.logicalState[binding.semanticStateId.toNat]? = some {
    id := binding.semanticStateId
    name := binding.semanticName
    typeId := binding.semanticTypeId
    visibility := .public_
  } ∧
  data.types[binding.semanticTypeId.toNat]? = some {
    id := binding.semanticTypeId
    name := none
    shape := .uint 64
  } ∧
  storage.stateLeaves[binding.semanticStateId.toNat]? =
    some #[binding.physicalFieldIndex] ∧
  storage.fields[binding.physicalFieldIndex]? = some {
    sourceId := binding.physicalFieldIndex
    name := binding.semanticName
    key := binding.physicalKey
    byteWidth := 8
    endianness := .little
  }

/-- One initialized logical UInt64 slot and its target KV observation agree.
    Logical bytes come only from the production state decoder; marker/field
    bytes are observations, not values computed by a target evaluator. -/
def InitializedUInt64StorageRelV1
    (data : SemanticProgramDataV1)
    (storage : StorageLayout)
    (binding : UInt64StateBindingV1)
    (logical : LogicalStateV1)
    (decodedValues : Array ByteArray)
    (valueBytes : ByteArray)
    (observed : StorageObservationV1) : Prop :=
  UInt64StateBindingRelV1 data storage binding ∧
  logical.initialized = true ∧
  decodeLogicalStateValuesV1 data logical = .ok decodedValues ∧
  decodedValues[binding.semanticStateId.toNat]? = some valueBytes ∧
  observed.lookup storage.markerKey = some (encodeU64le storage.markerValue) ∧
  observed.lookup binding.physicalKey = some valueBytes

/-- A fixed logical/storage observation determines one exact value for the
    bound owned key; the relation cannot choose arbitrary target bytes. -/
theorem initializedUInt64StorageRelV1_value_unique
    (data : SemanticProgramDataV1)
    (storage : StorageLayout)
    (binding : UInt64StateBindingV1)
    (logical : LogicalStateV1)
    (decodedValues : Array ByteArray)
    (left right : ByteArray)
    (observed : StorageObservationV1)
    (hleft : InitializedUInt64StorageRelV1 data storage binding logical
      decodedValues left observed)
    (hright : InitializedUInt64StorageRelV1 data storage binding logical
      decodedValues right observed) :
    left = right := by
  rcases hleft with ⟨_, _, _, _, _, hleftKey⟩
  rcases hright with ⟨_, _, _, _, _, hrightKey⟩
  exact Option.some.inj (hleftKey.symm.trans hrightKey)

/-- Exact empty-input ABI relation for a nullary public UInt64 NEAR view. -/
def NullaryUInt64ViewInputRelV1
    (callableId : CallableIdV1)
    (invocation : InvocationV1)
    (method : Method)
    (observed : CallObservationV1) : Prop :=
  invocation = {
    callableId
    args := #[]
    context := #[]
  } ∧
  method.name = observed.exportName ∧
  method.params = #[] ∧
  method.exactInputLen = 0 ∧
  method.mode = .view ∧
  method.depositPolicy = .queryOnly ∧
  method.resultKind = .uint64 ∧
  observed.input = ByteArray.empty

/-- Successful UInt64 view relation between one exact Reference outcome and a
    passive target observation. Both sides explicitly expose unchanged state,
    empty ordered effects/logs/promises, and the same canonical return bytes. -/
def UInt64ReturnedObservationRelV1
    (data : SemanticProgramDataV1)
    (typeId : TypeIdV1)
    (pre : LogicalStateV1)
    (outcome : OutcomeV1)
    (valueBytes : ByteArray)
    (observed : CallObservationV1) : Prop :=
  validateValueBytesV1 data.types typeId valueBytes = .ok () ∧
  valueBytes.size = 8 ∧
  outcome = .returned pre (some { typeId, valueBytes }) #[] ∧
  observed.failureObserved = false ∧
  observed.returnData = some valueBytes ∧
  observed.logs = #[] ∧
  observed.promises = #[] ∧
  observed.postStorage = observed.preStorage

/-- A production-ready nullary UInt64 state-load view discharges the complete
    Reference side of `UInt64ReturnedObservationRelV1`. Target success, return,
    log, promise, and storage facts remain explicit passive-observation
    hypotheses. This theorem does not execute MethodIR, WAT, Wasm, or NEAR. -/
theorem uint64ReturnedObservationRelV1_of_readyViewLoad
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (overlay : Array ByteArray)
    (loadedBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (context : Array ContextInputV1)
    (vault : ReferenceVaultSeedV1)
    (observed : CallObservationV1)
    (hadmittedData : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId
      name := none
      shape := .uint 64
    })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId
      name := stateName
      typeId := uint64TypeId
      visibility := .public_
    })
    (hloaded : overlay[stateId.toNat]? = some loadedBytes)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .view
          name := viewName
          params := #[]
          result := {
            typeId := uint64TypeId
            visibility := .public_
          }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[{
              result := some {
                valueId := 0
                typeId := uint64TypeId
              }
              op := .stateLoad stateId
            }]
            terminator := .return_ (some 0)
          }]
          loopBounds := #[]
          invariantSteps := none
        } overlay context false)
    (hfailure : observed.failureObserved = false)
    (hreturn : observed.returnData = some loadedBytes)
    (hlogs : observed.logs = #[])
    (hpromises : observed.promises = #[])
    (hstorage : observed.postStorage = observed.preStorage) :
    UInt64ReturnedObservationRelV1 data uint64TypeId pre
      (stepReferenceSliceV1 admitted pre invocation #[] vault)
      loadedBytes observed := by
  let callable : CallableV1 := {
    id := callableId
    kind := .view
    name := viewName
    params := #[]
    result := {
      typeId := uint64TypeId
      visibility := .public_
    }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some {
          valueId := 0
          typeId := uint64TypeId
        }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  have hdecodeAdmitted :
      decodeLogicalStateValuesV1 admitted.data pre = .ok overlay :=
    gateInvocation_ready_decodeV1 admitted pre invocation callable overlay
      context false (by simpa [callable] using hgate)
  have hdecode : decodeLogicalStateValuesV1 data pre = .ok overlay := by
    simpa [hadmittedData] using hdecodeAdmitted
  have hcanonical :
      validateValueBytesV1 data.types uint64TypeId loadedBytes = .ok () :=
    validateValueBytesV1_of_decodeLogicalStateValuesV1_getElem data pre
      overlay hdecode stateId.toNat
      {
        id := stateId
        name := stateName
        typeId := uint64TypeId
        visibility := .public_
      }
      loadedBytes hstate hloaded
  have hsize : loadedBytes.size = 8 :=
    validateValueBytesV1_uint64_size data.types uint64TypeId
      {
        id := uint64TypeId
        name := none
        shape := .uint 64
      }
      loadedBytes htypeU rfl hcanonical
  have hstep :=
    stepReferenceSliceV1_ready_viewLoad_returned_exact admitted pre invocation
      data overlay loadedBytes uint64TypeId stateId stateName callableId
      viewName context #[] vault hadmittedData htypeU hstate hloaded rfl hgate
  refine ⟨hcanonical, hsize, ?_, hfailure, hreturn, hlogs, hpromises, hstorage⟩
  simpa using hstep

/-- Failure/no-commit relation for an externally observed failed call. It
    accepts only Reference revert/trap outcomes that carry the exact pre-state,
    and requires the passive target snapshots to be identical. -/
def FailureNoCommitObservationRelV1
    (pre : LogicalStateV1)
    (outcome : OutcomeV1)
    (observed : CallObservationV1) : Prop :=
  (match outcome with
    | .returned _ _ _ => False
    | .reverted _ unchanged => unchanged = pre
    | .trapped _ unchanged => unchanged = pre) ∧
  observed.failureObserved = true ∧
  observed.returnData = none ∧
  observed.logs = #[] ∧
  observed.promises = #[] ∧
  observed.postStorage = observed.preStorage

/-- Public-syntax witness for the exact Method shape admitted by the first
    static alignment slice. This recognizes syntax only; it neither constructs
    a Method nor lowers or executes one. -/
structure NullaryUInt64ViewMethodShapeV1 where
  viewName : String
  physicalFieldIndex : Nat
  deriving Repr

/-- Proof-producing syntax recognizer for a nullary query-only UInt64 state
    view. Structural array patterns avoid relying on opaque derived `BEq`. -/
def recognizeNullaryUInt64ViewMethodV1
    (method : Method) : Option NullaryUInt64ViewMethodShapeV1 :=
  match method.params.toList, method.exactInputLen, method.mode,
      method.depositPolicy, method.resultKind, method.body.toList with
  | [], 0, .view, .queryOnly, .uint64,
      [.returnValue (.stateLoad physicalFieldIndex)] =>
    some { viewName := method.name, physicalFieldIndex }
  | _, _, _, _, _, _ => none

/-- A successful Method recognizer result is an exact structural equality. -/
theorem recognizeNullaryUInt64ViewMethodV1_sound
    (method : Method)
    (shape : NullaryUInt64ViewMethodShapeV1)
    (hrecognize : recognizeNullaryUInt64ViewMethodV1 method = some shape) :
    method = {
      name := shape.viewName
      params := #[]
      exactInputLen := 0
      mode := .view
      depositPolicy := .queryOnly
      resultKind := .uint64
      body := #[.returnValue (.stateLoad shape.physicalFieldIndex)]
    } := by
  rcases method with ⟨name, params, exactInputLen, mode, depositPolicy,
    resultKind, body⟩
  simp only [recognizeNullaryUInt64ViewMethodV1] at hrecognize
  split at hrecognize
  · cases hrecognize
    have hparams : params = #[] :=
      Array.toList_inj.mp (by assumption)
    have hbody : body = #[.returnValue (.stateLoad _)] :=
      Array.toList_inj.mp (by assumption)
    cases hparams
    cases hbody
    rfl
  · contradiction

/-- Public-syntax witness for the exact MethodIR recipe admitted by the first
    static alignment slice. The regions and marker value are read from the
    recipe; this witness does not assert that they are canonical Plan data. -/
structure NullaryUInt64ViewMethodIRShapeV1 where
  viewName : String
  markerRegion : KeyRegion
  markerValue : UInt64
  fieldRegion : KeyRegion
  deriving Repr

/-- Fieldwise equality helper for public key-region observations. -/
theorem keyRegion_eq_of_fields
    (left right : KeyRegion)
    (hkey : left.key = right.key)
    (hoffset : left.offset = right.offset)
    (hlength : left.length = right.length) :
    left = right := by
  cases left
  cases right
  simp_all

/-- Proof-producing syntax recognizer for the exact four-operation static
    recipe. It classifies public IR syntax and is not another lowering. -/
def recognizeNullaryUInt64ViewMethodIRV1
    (methodIR : MethodIR) : Option NullaryUInt64ViewMethodIRShapeV1 :=
  match methodIR.params.toList, methodIR.mode, methodIR.tempCount,
      methodIR.operations.toList with
  | [], .view, 1, [
      .checkInputLen 0,
      .requireLayout markerRegion markerValue,
      .loadState 0 fieldRegion,
      .setReturnData 8 0
    ] =>
    some { viewName := methodIR.name, markerRegion, markerValue, fieldRegion }
  | _, _, _, _ => none

/-- A successful MethodIR recognizer result is an exact structural equality. -/
theorem recognizeNullaryUInt64ViewMethodIRV1_sound
    (methodIR : MethodIR)
    (shape : NullaryUInt64ViewMethodIRShapeV1)
    (hrecognize : recognizeNullaryUInt64ViewMethodIRV1 methodIR = some shape) :
    methodIR = {
      name := shape.viewName
      params := #[]
      mode := .view
      tempCount := 1
      operations := #[
        .checkInputLen 0,
        .requireLayout shape.markerRegion shape.markerValue,
        .loadState 0 shape.fieldRegion,
        .setReturnData 8 0
      ]
    } := by
  rcases methodIR with ⟨name, params, mode, tempCount, operations⟩
  simp only [recognizeNullaryUInt64ViewMethodIRV1] at hrecognize
  split at hrecognize
  · cases hrecognize
    have hparams : params = #[] :=
      Array.toList_inj.mp (by assumption)
    have hoperations : operations = #[
        .checkInputLen 0,
        .requireLayout _ _,
        .loadState 0 _,
        .setReturnData 8 0
      ] := Array.toList_inj.mp (by assumption)
    cases hparams
    cases hoperations
    rfl
  · contradiction

/-- Exact static alignment for the scalar `stateLoad; return` view slice. The
    MethodIR clause is complete equality, so additional stores/effects/returns
    cannot satisfy the relation. This is recipe syntax, not recipe execution. -/
def NullaryUInt64ViewStaticAlignmentV1
    (data : SemanticProgramDataV1)
    (storage : StorageLayout)
    (binding : UInt64StateBindingV1)
    (viewName : String)
    (method : Method)
    (markerRegion fieldRegion : KeyRegion)
    (methodIR : MethodIR) : Prop :=
  UInt64StateBindingRelV1 data storage binding ∧
  markerRegion.key = storage.markerKey ∧
  markerRegion.length = storage.markerKey.toUTF8.size ∧
  fieldRegion.key = binding.physicalKey ∧
  fieldRegion.length = binding.physicalKey.toUTF8.size ∧
  method = {
    name := viewName
    params := #[]
    exactInputLen := 0
    mode := .view
    depositPolicy := .queryOnly
    resultKind := .uint64
    body := #[.returnValue (.stateLoad binding.physicalFieldIndex)]
  } ∧
  methodIR = {
    name := viewName
    params := #[]
    mode := .view
    tempCount := 1
    operations := #[
      .checkInputLen 0,
      .requireLayout markerRegion storage.markerValue,
      .loadState 0 fieldRegion,
      .setReturnData 8 0
    ]
  }

/-- The complete static alignment relation determines one exact MethodIR. -/
theorem nullaryUInt64ViewStaticAlignmentV1_methodIR_unique
    (data : SemanticProgramDataV1)
    (storage : StorageLayout)
    (binding : UInt64StateBindingV1)
    (viewName : String)
    (method : Method)
    (markerRegion fieldRegion : KeyRegion)
    (left right : MethodIR)
    (hleft : NullaryUInt64ViewStaticAlignmentV1 data storage binding viewName
      method markerRegion fieldRegion left)
    (hright : NullaryUInt64ViewStaticAlignmentV1 data storage binding viewName
      method markerRegion fieldRegion right) :
    left = right := by
  rcases hleft with ⟨_, _, _, _, _, _, hleftIR⟩
  rcases hright with ⟨_, _, _, _, _, _, hrightIR⟩
  exact hleftIR.trans hrightIR.symm

/-- Production provenance and the passive static relation carried together for
    one selected method. The validated semantic-data equation prevents callers
    from substituting unrelated data while retaining the same Plan/IR graphs.
    This packages existing proof graphs and recognized public syntax; it does
    not state or prove target execution behavior. -/
def ProductionNullaryUInt64ViewStaticAlignmentV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (keys : Array KeyRegion)
    (binding : UInt64StateBindingV1)
    (viewName : String)
    (method : Method)
    (markerRegion fieldRegion : KeyRegion)
    (methodIR : MethodIR) : Prop :=
  validateSemanticProgramV1 program = .ok data ∧
  KeyRegionsV1 plan keys ∧
  keys[0]? = some markerRegion ∧
  keys[binding.physicalFieldIndex + 1]? = some fieldRegion ∧
  MethodIRLoweringV1 plan keys method methodIR ∧
  NullaryUInt64ViewStaticAlignmentV1 data plan.storage binding viewName
    method markerRegion fieldRegion methodIR

/-- Successful structural recognition bridges existing production provenance
    to the complete passive static alignment relation. Semantic→storage binding
    and selected canonical-key facts remain explicit hypotheses; they do not
    follow merely from recognizing MethodIR syntax. -/
theorem productionNullaryUInt64ViewStaticAlignmentV1_of_recognized
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (keys : Array KeyRegion)
    (binding : UInt64StateBindingV1)
    (viewName : String)
    (method : Method)
    (markerRegion fieldRegion : KeyRegion)
    (methodIR : MethodIR)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hkeys : KeyRegionsV1 plan keys)
    (hmarkerLookup : keys[0]? = some markerRegion)
    (hfieldLookup :
      keys[binding.physicalFieldIndex + 1]? = some fieldRegion)
    (hlowering : MethodIRLoweringV1 plan keys method methodIR)
    (hbinding : UInt64StateBindingRelV1 data plan.storage binding)
    (hmarkerKey : markerRegion.key = plan.storage.markerKey)
    (hmarkerLength :
      markerRegion.length = plan.storage.markerKey.toUTF8.size)
    (hfieldKey : fieldRegion.key = binding.physicalKey)
    (hfieldLength :
      fieldRegion.length = binding.physicalKey.toUTF8.size)
    (hmethodShape :
      recognizeNullaryUInt64ViewMethodV1 method = some {
        viewName
        physicalFieldIndex := binding.physicalFieldIndex
      })
    (hmethodIRShape :
      recognizeNullaryUInt64ViewMethodIRV1 methodIR = some {
        viewName
        markerRegion
        markerValue := plan.storage.markerValue
        fieldRegion
      }) :
    ProductionNullaryUInt64ViewStaticAlignmentV1 program data plan keys binding
      viewName method markerRegion fieldRegion methodIR := by
  refine ⟨hvalidate, hkeys, hmarkerLookup, hfieldLookup, hlowering, hbinding,
    hmarkerKey, hmarkerLength, hfieldKey, hfieldLength, ?_, ?_⟩
  · exact recognizeNullaryUInt64ViewMethodV1_sound method _ hmethodShape
  · exact recognizeNullaryUInt64ViewMethodIRV1_sound methodIR _ hmethodIRShape

/-! ## Selected two-UInt64 initializer alignment -/

/-- Public-syntax witness for the exact nullary initializer Method admitted by
    this slice. The two physical field indices are recovered from the Method;
    this witness does not assert that they are canonical storage fields. -/
structure NullaryZeroTwoUInt64InitializerMethodShapeV1 where
  initializerName : String
  field0Index : Nat
  field1Index : Nat
  deriving Repr

/-- Proof-producing syntax recognizer for a nullary, zero-deposit initializer
    that writes UInt64 zero to exactly two fields and returns Unit. -/
def recognizeNullaryZeroTwoUInt64InitializerMethodV1
    (method : Method) :
    Option NullaryZeroTwoUInt64InitializerMethodShapeV1 :=
  match method.params.toList, method.exactInputLen, method.mode,
      method.depositPolicy, method.resultKind, method.body.toList with
  | [], 0, .initialize, .requireZero, .unit, [
      .store {
        fieldIndex := field0Index
        value := .literal 0
        byteWidth := 8
      },
      .store {
        fieldIndex := field1Index
        value := .literal 0
        byteWidth := 8
      },
      .returnNone
    ] =>
    some { initializerName := method.name, field0Index, field1Index }
  | _, _, _, _, _, _ => none

/-- A successful initializer Method recognizer is an exact structural
    equality, including operation count and order. -/
theorem recognizeNullaryZeroTwoUInt64InitializerMethodV1_sound
    (method : Method)
    (shape : NullaryZeroTwoUInt64InitializerMethodShapeV1)
    (hrecognize :
      recognizeNullaryZeroTwoUInt64InitializerMethodV1 method = some shape) :
    method = {
      name := shape.initializerName
      params := #[]
      exactInputLen := 0
      mode := .initialize
      depositPolicy := .requireZero
      resultKind := .unit
      body := #[
        .store {
          fieldIndex := shape.field0Index
          value := .literal 0
          byteWidth := 8
        },
        .store {
          fieldIndex := shape.field1Index
          value := .literal 0
          byteWidth := 8
        },
        .returnNone
      ]
    } := by
  rcases method with ⟨name, params, exactInputLen, mode, depositPolicy,
    resultKind, body⟩
  simp only [recognizeNullaryZeroTwoUInt64InitializerMethodV1] at hrecognize
  split at hrecognize
  · cases hrecognize
    have hparams : params = #[] :=
      Array.toList_inj.mp (by assumption)
    have hbody : body = #[
        .store {
          fieldIndex := _
          value := .literal 0
          byteWidth := 8
        },
        .store {
          fieldIndex := _
          value := .literal 0
          byteWidth := 8
        },
        .returnNone
      ] := Array.toList_inj.mp (by assumption)
    cases hparams
    cases hbody
    rfl
  · contradiction

/-- Public-syntax witness for the exact initializer MethodIR recipe. Regions
    and marker value are recovered from IR syntax and are related to canonical
    Plan data separately. -/
structure NullaryZeroTwoUInt64InitializerMethodIRShapeV1 where
  initializerName : String
  markerRegion : KeyRegion
  field0Region : KeyRegion
  field1Region : KeyRegion
  store0Region : KeyRegion
  store1Region : KeyRegion
  setMarkerRegion : KeyRegion
  markerValue : UInt64
  deriving Repr

/-- Proof-producing syntax recognizer for the exact ten-operation initializer
    recipe emitted by the production lowering. -/
def recognizeNullaryZeroTwoUInt64InitializerMethodIRV1
    (methodIR : MethodIR) :
    Option NullaryZeroTwoUInt64InitializerMethodIRShapeV1 :=
  match methodIR.params.toList, methodIR.mode, methodIR.tempCount,
      methodIR.operations.toList with
  | [], .initialize, 2, [
      .checkInputLen 0,
      .requireZeroAttachedDeposit,
      .requireLayoutAbsent markerRegion,
      .zeroState field0Region,
      .zeroState field1Region,
      .literal 0 0,
      .storeState store0Region 0,
      .literal 1 0,
      .storeState store1Region 1,
      .setLayout setMarkerRegion markerValue
    ] =>
    some {
      initializerName := methodIR.name
      markerRegion
      field0Region
      field1Region
      store0Region
      store1Region
      setMarkerRegion
      markerValue
    }
  | _, _, _, _ => none

/-- A successful initializer MethodIR recognizer is an exact structural
    equality, including every region occurrence, operation count, and order.
    The production bridge below additionally requires repeated regions to be
    identical to their canonical load/check regions. -/
theorem recognizeNullaryZeroTwoUInt64InitializerMethodIRV1_sound
    (methodIR : MethodIR)
    (shape : NullaryZeroTwoUInt64InitializerMethodIRShapeV1)
    (hrecognize :
      recognizeNullaryZeroTwoUInt64InitializerMethodIRV1 methodIR =
        some shape) :
    methodIR = {
      name := shape.initializerName
      params := #[]
      mode := .initialize
      tempCount := 2
      operations := #[
        .checkInputLen 0,
        .requireZeroAttachedDeposit,
        .requireLayoutAbsent shape.markerRegion,
        .zeroState shape.field0Region,
        .zeroState shape.field1Region,
        .literal 0 0,
        .storeState shape.store0Region 0,
        .literal 1 0,
        .storeState shape.store1Region 1,
        .setLayout shape.setMarkerRegion shape.markerValue
      ]
    } := by
  rcases methodIR with ⟨name, params, mode, tempCount, operations⟩
  simp only [recognizeNullaryZeroTwoUInt64InitializerMethodIRV1] at hrecognize
  split at hrecognize
  · cases hrecognize
    have hparams : params = #[] :=
      Array.toList_inj.mp (by assumption)
    have hoperations : operations = #[
        .checkInputLen 0,
        .requireZeroAttachedDeposit,
        .requireLayoutAbsent _,
        .zeroState _,
        .zeroState _,
        .literal 0 0,
        .storeState _ 0,
        .literal 1 0,
        .storeState _ 1,
        .setLayout _ _
      ] := Array.toList_inj.mp (by assumption)
    cases hparams
    cases hoperations
    rfl
  · contradiction

/-- Exact static alignment for the selected nullary initializer that writes
    zero to semantic state slots 0 and 1. Complete Method/MethodIR equalities
    make extra, missing, or reordered operations fail closed. -/
structure NullaryZeroTwoUInt64InitializerStaticAlignmentV1
    (data : SemanticProgramDataV1)
    (storage : StorageLayout)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR) : Prop where
  binding0Rel : UInt64StateBindingRelV1 data storage binding0
  binding1Rel : UInt64StateBindingRelV1 data storage binding1
  binding0State : binding0.semanticStateId = 0
  binding1State : binding1.semanticStateId = 1
  bindingTypes : binding0.semanticTypeId = binding1.semanticTypeId
  distinctFields : binding0.physicalFieldIndex ≠ binding1.physicalFieldIndex
  markerKey : markerRegion.key = storage.markerKey
  markerLength : markerRegion.length = storage.markerKey.toUTF8.size
  field0Key : field0Region.key = binding0.physicalKey
  field0Length : field0Region.length = binding0.physicalKey.toUTF8.size
  field1Key : field1Region.key = binding1.physicalKey
  field1Length : field1Region.length = binding1.physicalKey.toUTF8.size
  methodExact : method = {
    name := initializerName
    params := #[]
    exactInputLen := 0
    mode := .initialize
    depositPolicy := .requireZero
    resultKind := .unit
    body := #[
      .store {
        fieldIndex := binding0.physicalFieldIndex
        value := .literal 0
        byteWidth := 8
      },
      .store {
        fieldIndex := binding1.physicalFieldIndex
        value := .literal 0
        byteWidth := 8
      },
      .returnNone
    ]
  }
  methodIRExact : methodIR = {
    name := initializerName
    params := #[]
    mode := .initialize
    tempCount := 2
    operations := #[
      .checkInputLen 0,
      .requireZeroAttachedDeposit,
      .requireLayoutAbsent markerRegion,
      .zeroState field0Region,
      .zeroState field1Region,
      .literal 0 0,
      .storeState field0Region 0,
      .literal 1 0,
      .storeState field1Region 1,
      .setLayout markerRegion storage.markerValue
    ]
  }

/-- Production provenance for the selected initializer: validated semantic
    data, canonical key construction, actual production lowering, and the exact
    passive alignment are carried together. -/
structure ProductionNullaryZeroTwoUInt64InitializerStaticAlignmentV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (keys : Array KeyRegion)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR) : Prop where
  semanticValidation : validateSemanticProgramV1 program = .ok data
  keyRegions : KeyRegionsV1 plan keys
  markerLookup : keys[0]? = some markerRegion
  field0Lookup : keys[binding0.physicalFieldIndex + 1]? = some field0Region
  field1Lookup : keys[binding1.physicalFieldIndex + 1]? = some field1Region
  methodLowering : MethodIRLoweringV1 plan keys method methodIR
  staticAlignment :
    NullaryZeroTwoUInt64InitializerStaticAlignmentV1 data plan.storage binding0
      binding1 initializerName method markerRegion field0Region field1Region
        methodIR

/-- Successful structural recognition bridges existing production provenance
    to the complete selected initializer alignment. The semantic/storage
    bindings and canonical key facts remain explicit hypotheses. -/
theorem productionNullaryZeroTwoUInt64InitializerStaticAlignmentV1_of_recognized
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (keys : Array KeyRegion)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hkeys : KeyRegionsV1 plan keys)
    (hmarkerLookup : keys[0]? = some markerRegion)
    (hfield0Lookup :
      keys[binding0.physicalFieldIndex + 1]? = some field0Region)
    (hfield1Lookup :
      keys[binding1.physicalFieldIndex + 1]? = some field1Region)
    (hlowering : MethodIRLoweringV1 plan keys method methodIR)
    (hbinding0 : UInt64StateBindingRelV1 data plan.storage binding0)
    (hbinding1 : UInt64StateBindingRelV1 data plan.storage binding1)
    (hbinding0State : binding0.semanticStateId = 0)
    (hbinding1State : binding1.semanticStateId = 1)
    (hbindingTypes : binding0.semanticTypeId = binding1.semanticTypeId)
    (hdistinctFields :
      binding0.physicalFieldIndex ≠ binding1.physicalFieldIndex)
    (hmarkerKey : markerRegion.key = plan.storage.markerKey)
    (hmarkerLength :
      markerRegion.length = plan.storage.markerKey.toUTF8.size)
    (hfield0Key : field0Region.key = binding0.physicalKey)
    (hfield0Length :
      field0Region.length = binding0.physicalKey.toUTF8.size)
    (hfield1Key : field1Region.key = binding1.physicalKey)
    (hfield1Length :
      field1Region.length = binding1.physicalKey.toUTF8.size)
    (hmethodShape :
      recognizeNullaryZeroTwoUInt64InitializerMethodV1 method = some {
        initializerName
        field0Index := binding0.physicalFieldIndex
        field1Index := binding1.physicalFieldIndex
      })
    (hmethodIRShape :
      recognizeNullaryZeroTwoUInt64InitializerMethodIRV1 methodIR = some {
        initializerName
        markerRegion
        field0Region
        field1Region
        store0Region := field0Region
        store1Region := field1Region
        setMarkerRegion := markerRegion
        markerValue := plan.storage.markerValue
      }) :
    ProductionNullaryZeroTwoUInt64InitializerStaticAlignmentV1 program data plan
      keys binding0 binding1 initializerName method markerRegion field0Region
        field1Region methodIR := by
  refine {
    semanticValidation := hvalidate
    keyRegions := hkeys
    markerLookup := hmarkerLookup
    field0Lookup := hfield0Lookup
    field1Lookup := hfield1Lookup
    methodLowering := hlowering
    staticAlignment := {
      binding0Rel := hbinding0
      binding1Rel := hbinding1
      binding0State := hbinding0State
      binding1State := hbinding1State
      bindingTypes := hbindingTypes
      distinctFields := hdistinctFields
      markerKey := hmarkerKey
      markerLength := hmarkerLength
      field0Key := hfield0Key
      field0Length := hfield0Length
      field1Key := hfield1Key
      field1Length := hfield1Length
      methodExact := ?_
      methodIRExact := ?_
    }
  }
  · exact recognizeNullaryZeroTwoUInt64InitializerMethodV1_sound method _
      hmethodShape
  · exact recognizeNullaryZeroTwoUInt64InitializerMethodIRV1_sound methodIR _
      hmethodIRShape

/-! ## Selected unary checked-add two-UInt64 entry alignment -/

/-- Public-syntax witness for the exact unary checked-add entry used by the
    selected Vault deposit slice. The names and field indices are recovered
    from production syntax rather than fixed by this recognizer. -/
structure UnaryAddTwoUInt64DepositMethodShapeV1 where
  entryName : String
  parameterSourceId : Nat
  parameterName : String
  field0Index : Nat
  load0Index : Nat
  field1Index : Nat
  load1Index : Nat
  returnIndex : Nat
  deriving Repr

/-- Recognize one UInt64 parameter added, with checked arithmetic, to exactly
    two state fields before returning the second updated field. -/
def recognizeUnaryAddTwoUInt64DepositMethodV1
    (method : Method) : Option UnaryAddTwoUInt64DepositMethodShapeV1 :=
  match method.params.toList, method.exactInputLen, method.mode,
      method.depositPolicy, method.resultKind, method.body.toList with
  | [{
      sourceId := parameterSourceId
      name := parameterName
      inputOffset := 0
      byteWidth := 8
      endianness := .little
    }], 8, .mutate, .requireZero, .uint64, [
      .store {
        fieldIndex := field0Index
        value := .checkedAdd (.stateLoad load0Index) (.param 0)
        byteWidth := 8
      },
      .store {
        fieldIndex := field1Index
        value := .checkedAdd (.stateLoad load1Index) (.param 0)
        byteWidth := 8
      },
      .returnValue (.stateLoad returnIndex)
    ] => some {
      entryName := method.name
      parameterSourceId
      parameterName
      field0Index
      load0Index
      field1Index
      load1Index
      returnIndex
    }
  | _, _, _, _, _, _ => none

/-- Successful source-Method recognition gives the complete exact entry. -/
theorem recognizeUnaryAddTwoUInt64DepositMethodV1_sound
    (method : Method)
    (shape : UnaryAddTwoUInt64DepositMethodShapeV1)
    (hrecognize :
      recognizeUnaryAddTwoUInt64DepositMethodV1 method = some shape) :
    method = {
      name := shape.entryName
      params := #[{
        sourceId := shape.parameterSourceId
        name := shape.parameterName
        inputOffset := 0
        byteWidth := 8
        endianness := .little
      }]
      exactInputLen := 8
      mode := .mutate
      depositPolicy := .requireZero
      resultKind := .uint64
      body := #[
        .store {
          fieldIndex := shape.field0Index
          value := .checkedAdd (.stateLoad shape.load0Index) (.param 0)
          byteWidth := 8
        },
        .store {
          fieldIndex := shape.field1Index
          value := .checkedAdd (.stateLoad shape.load1Index) (.param 0)
          byteWidth := 8
        },
        .returnValue (.stateLoad shape.returnIndex)
      ]
    } := by
  rcases method with ⟨name, params, exactInputLen, mode, depositPolicy,
    resultKind, body⟩
  simp only [recognizeUnaryAddTwoUInt64DepositMethodV1] at hrecognize
  split at hrecognize
  · cases hrecognize
    have hparams : params = #[{
        sourceId := _
        name := _
        inputOffset := 0
        byteWidth := 8
        endianness := .little
      }] := Array.toList_inj.mp (by assumption)
    have hbody : body = #[
        .store {
          fieldIndex := _
          value := .checkedAdd (.stateLoad _) (.param 0)
          byteWidth := 8
        },
        .store {
          fieldIndex := _
          value := .checkedAdd (.stateLoad _) (.param 0)
          byteWidth := 8
        },
        .returnValue (.stateLoad _)
      ] := Array.toList_inj.mp (by assumption)
    cases hparams
    cases hbody
    rfl
  · contradiction

/-- Public-syntax witness for the exact thirteen-operation production
    MethodIR recipe. Repeated regions remain separate until the production
    bridge proves that every occurrence is canonical. -/
structure UnaryAddTwoUInt64DepositMethodIRShapeV1 where
  entryName : String
  parameterSourceId : Nat
  parameterName : String
  markerRegion : KeyRegion
  load0Region : KeyRegion
  store0Region : KeyRegion
  load1Region : KeyRegion
  store1Region : KeyRegion
  returnRegion : KeyRegion
  markerValue : UInt64
  deriving Repr

/-- Recognize the exact production MethodIR sequence for the selected unary
    two-field checked-add entry. -/
def recognizeUnaryAddTwoUInt64DepositMethodIRV1
    (methodIR : MethodIR) :
    Option UnaryAddTwoUInt64DepositMethodIRShapeV1 :=
  match methodIR.params.toList, methodIR.mode, methodIR.tempCount,
      methodIR.operations.toList with
  | [{
      sourceId := parameterSourceId
      name := parameterName
      inputOffset := 0
      byteWidth := 8
      endianness := .little
    }], .mutate, 7, [
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout markerRegion markerValue,
      .loadState 0 load0Region,
      .loadParam 1 0,
      .checkedAdd 2 0 1,
      .storeState store0Region 2,
      .loadState 3 load1Region,
      .loadParam 4 0,
      .checkedAdd 5 3 4,
      .storeState store1Region 5,
      .loadState 6 returnRegion,
      .setReturnData 8 6
    ] => some {
      entryName := methodIR.name
      parameterSourceId
      parameterName
      markerRegion
      load0Region
      store0Region
      load1Region
      store1Region
      returnRegion
      markerValue
    }
  | _, _, _, _ => none

/-- Successful MethodIR recognition gives the complete exact recipe. -/
theorem recognizeUnaryAddTwoUInt64DepositMethodIRV1_sound
    (methodIR : MethodIR)
    (shape : UnaryAddTwoUInt64DepositMethodIRShapeV1)
    (hrecognize :
      recognizeUnaryAddTwoUInt64DepositMethodIRV1 methodIR = some shape) :
    methodIR = {
      name := shape.entryName
      params := #[{
        sourceId := shape.parameterSourceId
        name := shape.parameterName
        inputOffset := 0
        byteWidth := 8
        endianness := .little
      }]
      mode := .mutate
      tempCount := 7
      operations := #[
        .checkInputLen 8,
        .requireZeroAttachedDeposit,
        .requireLayout shape.markerRegion shape.markerValue,
        .loadState 0 shape.load0Region,
        .loadParam 1 0,
        .checkedAdd 2 0 1,
        .storeState shape.store0Region 2,
        .loadState 3 shape.load1Region,
        .loadParam 4 0,
        .checkedAdd 5 3 4,
        .storeState shape.store1Region 5,
        .loadState 6 shape.returnRegion,
        .setReturnData 8 6
      ]
    } := by
  rcases methodIR with ⟨name, params, mode, tempCount, operations⟩
  simp only [recognizeUnaryAddTwoUInt64DepositMethodIRV1] at hrecognize
  split at hrecognize
  · cases hrecognize
    have hparams : params = #[{
        sourceId := _
        name := _
        inputOffset := 0
        byteWidth := 8
        endianness := .little
      }] := Array.toList_inj.mp (by assumption)
    have hoperations : operations = #[
        .checkInputLen 8,
        .requireZeroAttachedDeposit,
        .requireLayout _ _,
        .loadState 0 _,
        .loadParam 1 0,
        .checkedAdd 2 0 1,
        .storeState _ 2,
        .loadState 3 _,
        .loadParam 4 0,
        .checkedAdd 5 3 4,
        .storeState _ 5,
        .loadState 6 _,
        .setReturnData 8 6
      ] := Array.toList_inj.mp (by assumption)
    cases hparams
    cases hoperations
    rfl
  · contradiction

/-- Exact semantic/storage/MethodIR alignment for the selected checked-add
    entry. Complete equalities reject extra, missing, reordered, or
    non-canonical repeated region uses. -/
structure UnaryAddTwoUInt64DepositStaticAlignmentV1
    (data : SemanticProgramDataV1)
    (storage : StorageLayout)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR) : Prop where
  binding0Rel : UInt64StateBindingRelV1 data storage binding0
  binding1Rel : UInt64StateBindingRelV1 data storage binding1
  binding0State : binding0.semanticStateId = 0
  binding1State : binding1.semanticStateId = 1
  bindingTypes : binding0.semanticTypeId = binding1.semanticTypeId
  distinctFields : binding0.physicalFieldIndex ≠ binding1.physicalFieldIndex
  markerKey : markerRegion.key = storage.markerKey
  markerLength : markerRegion.length = storage.markerKey.toUTF8.size
  field0Key : field0Region.key = binding0.physicalKey
  field0Length : field0Region.length = binding0.physicalKey.toUTF8.size
  field1Key : field1Region.key = binding1.physicalKey
  field1Length : field1Region.length = binding1.physicalKey.toUTF8.size
  methodExact : method = {
    name := entryName
    params := #[{
      sourceId := parameterSourceId
      name := parameterName
      inputOffset := 0
      byteWidth := 8
      endianness := .little
    }]
    exactInputLen := 8
    mode := .mutate
    depositPolicy := .requireZero
    resultKind := .uint64
    body := #[
      .store {
        fieldIndex := binding0.physicalFieldIndex
        value := .checkedAdd
          (.stateLoad binding0.physicalFieldIndex) (.param 0)
        byteWidth := 8
      },
      .store {
        fieldIndex := binding1.physicalFieldIndex
        value := .checkedAdd
          (.stateLoad binding1.physicalFieldIndex) (.param 0)
        byteWidth := 8
      },
      .returnValue (.stateLoad binding1.physicalFieldIndex)
    ]
  }
  methodIRExact : methodIR = {
    name := entryName
    params := #[{
      sourceId := parameterSourceId
      name := parameterName
      inputOffset := 0
      byteWidth := 8
      endianness := .little
    }]
    mode := .mutate
    tempCount := 7
    operations := #[
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout markerRegion storage.markerValue,
      .loadState 0 field0Region,
      .loadParam 1 0,
      .checkedAdd 2 0 1,
      .storeState field0Region 2,
      .loadState 3 field1Region,
      .loadParam 4 0,
      .checkedAdd 5 3 4,
      .storeState field1Region 5,
      .loadState 6 field1Region,
      .setReturnData 8 6
    ]
  }

/-- Production provenance for the selected deposit entry. -/
structure ProductionUnaryAddTwoUInt64DepositStaticAlignmentV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (keys : Array KeyRegion)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR) : Prop where
  semanticValidation : validateSemanticProgramV1 program = .ok data
  keyRegions : KeyRegionsV1 plan keys
  markerLookup : keys[0]? = some markerRegion
  field0Lookup : keys[binding0.physicalFieldIndex + 1]? = some field0Region
  field1Lookup : keys[binding1.physicalFieldIndex + 1]? = some field1Region
  methodLowering : MethodIRLoweringV1 plan keys method methodIR
  staticAlignment :
    UnaryAddTwoUInt64DepositStaticAlignmentV1 data plan.storage binding0
      binding1 entryName parameterName parameterSourceId method markerRegion
        field0Region field1Region methodIR

/-- Structural recognition plus existing production provenance constructs the
    selected deposit alignment without another Plan→IR lowering. -/
theorem productionUnaryAddTwoUInt64DepositStaticAlignmentV1_of_recognized
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (keys : Array KeyRegion)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hkeys : KeyRegionsV1 plan keys)
    (hmarkerLookup : keys[0]? = some markerRegion)
    (hfield0Lookup :
      keys[binding0.physicalFieldIndex + 1]? = some field0Region)
    (hfield1Lookup :
      keys[binding1.physicalFieldIndex + 1]? = some field1Region)
    (hlowering : MethodIRLoweringV1 plan keys method methodIR)
    (hbinding0 : UInt64StateBindingRelV1 data plan.storage binding0)
    (hbinding1 : UInt64StateBindingRelV1 data plan.storage binding1)
    (hbinding0State : binding0.semanticStateId = 0)
    (hbinding1State : binding1.semanticStateId = 1)
    (hbindingTypes : binding0.semanticTypeId = binding1.semanticTypeId)
    (hdistinctFields :
      binding0.physicalFieldIndex ≠ binding1.physicalFieldIndex)
    (hmarkerKey : markerRegion.key = plan.storage.markerKey)
    (hmarkerLength :
      markerRegion.length = plan.storage.markerKey.toUTF8.size)
    (hfield0Key : field0Region.key = binding0.physicalKey)
    (hfield0Length :
      field0Region.length = binding0.physicalKey.toUTF8.size)
    (hfield1Key : field1Region.key = binding1.physicalKey)
    (hfield1Length :
      field1Region.length = binding1.physicalKey.toUTF8.size)
    (hmethodShape :
      recognizeUnaryAddTwoUInt64DepositMethodV1 method = some {
        entryName
        parameterSourceId
        parameterName
        field0Index := binding0.physicalFieldIndex
        load0Index := binding0.physicalFieldIndex
        field1Index := binding1.physicalFieldIndex
        load1Index := binding1.physicalFieldIndex
        returnIndex := binding1.physicalFieldIndex
      })
    (hmethodIRShape :
      recognizeUnaryAddTwoUInt64DepositMethodIRV1 methodIR = some {
        entryName
        parameterSourceId
        parameterName
        markerRegion
        load0Region := field0Region
        store0Region := field0Region
        load1Region := field1Region
        store1Region := field1Region
        returnRegion := field1Region
        markerValue := plan.storage.markerValue
      }) :
    ProductionUnaryAddTwoUInt64DepositStaticAlignmentV1 program data plan keys
      binding0 binding1 entryName parameterName parameterSourceId method
        markerRegion field0Region field1Region methodIR := by
  refine {
    semanticValidation := hvalidate
    keyRegions := hkeys
    markerLookup := hmarkerLookup
    field0Lookup := hfield0Lookup
    field1Lookup := hfield1Lookup
    methodLowering := hlowering
    staticAlignment := {
      binding0Rel := hbinding0
      binding1Rel := hbinding1
      binding0State := hbinding0State
      binding1State := hbinding1State
      bindingTypes := hbindingTypes
      distinctFields := hdistinctFields
      markerKey := hmarkerKey
      markerLength := hmarkerLength
      field0Key := hfield0Key
      field0Length := hfield0Length
      field1Key := hfield1Key
      field1Length := hfield1Length
      methodExact := ?_
      methodIRExact := ?_
    }
  }
  · exact recognizeUnaryAddTwoUInt64DepositMethodV1_sound method _ hmethodShape
  · exact recognizeUnaryAddTwoUInt64DepositMethodIRV1_sound methodIR _
      hmethodIRShape

/-! ## Selected guarded checked-sub two-UInt64 entry alignment -/

/-- Public syntax recovered from the selected withdraw Method. Repeated field
    uses remain explicit until the production bridge proves they all select
    the canonical two state bindings. -/
structure GuardedSubTwoUInt64WithdrawMethodShapeV1 where
  entryName : String
  parameterSourceId : Nat
  parameterName : String
  guard0Index : Nat
  guard1Index : Nat
  store0Index : Nat
  load0Index : Nat
  store1Index : Nat
  load1Index : Nat
  deriving Repr

/-- Recognize exactly two `amount ≤ state` assertions followed by checked
    subtraction from both fields and a Unit return. -/
def recognizeGuardedSubTwoUInt64WithdrawMethodV1
    (method : Method) : Option GuardedSubTwoUInt64WithdrawMethodShapeV1 :=
  match method.params.toList, method.exactInputLen, method.mode,
      method.depositPolicy, method.resultKind, method.body.toList with
  | [{
      sourceId := parameterSourceId
      name := parameterName
      inputOffset := 0
      byteWidth := 8
      endianness := .little
    }], 8, .mutate, .requireZero, .unit, [
      .assert (.compare .le (.param 0) (.stateLoad guard0Index)),
      .assert (.compare .le (.param 0) (.stateLoad guard1Index)),
      .store {
        fieldIndex := store0Index
        value := .checkedSub (.stateLoad load0Index) (.param 0)
        byteWidth := 8
      },
      .store {
        fieldIndex := store1Index
        value := .checkedSub (.stateLoad load1Index) (.param 0)
        byteWidth := 8
      },
      .returnNone
    ] => some {
      entryName := method.name
      parameterSourceId
      parameterName
      guard0Index
      guard1Index
      store0Index
      load0Index
      store1Index
      load1Index
    }
  | _, _, _, _, _, _ => none

/-- Successful source recognition determines the complete Method. -/
theorem recognizeGuardedSubTwoUInt64WithdrawMethodV1_sound
    (method : Method)
    (shape : GuardedSubTwoUInt64WithdrawMethodShapeV1)
    (hrecognize :
      recognizeGuardedSubTwoUInt64WithdrawMethodV1 method = some shape) :
    method = {
      name := shape.entryName
      params := #[{
        sourceId := shape.parameterSourceId
        name := shape.parameterName
        inputOffset := 0
        byteWidth := 8
        endianness := .little
      }]
      exactInputLen := 8
      mode := .mutate
      depositPolicy := .requireZero
      resultKind := .unit
      body := #[
        .assert (.compare .le (.param 0) (.stateLoad shape.guard0Index)),
        .assert (.compare .le (.param 0) (.stateLoad shape.guard1Index)),
        .store {
          fieldIndex := shape.store0Index
          value := .checkedSub (.stateLoad shape.load0Index) (.param 0)
          byteWidth := 8
        },
        .store {
          fieldIndex := shape.store1Index
          value := .checkedSub (.stateLoad shape.load1Index) (.param 0)
          byteWidth := 8
        },
        .returnNone
      ]
    } := by
  rcases method with ⟨name, params, exactInputLen, mode, depositPolicy,
    resultKind, body⟩
  simp only [recognizeGuardedSubTwoUInt64WithdrawMethodV1] at hrecognize
  split at hrecognize
  · cases hrecognize
    have hparams : params = #[{
        sourceId := _
        name := _
        inputOffset := 0
        byteWidth := 8
        endianness := .little
      }] := Array.toList_inj.mp (by assumption)
    have hbody : body = #[
        .assert (.compare .le (.param 0) (.stateLoad _)),
        .assert (.compare .le (.param 0) (.stateLoad _)),
        .store {
          fieldIndex := _
          value := .checkedSub (.stateLoad _) (.param 0)
          byteWidth := 8
        },
        .store {
          fieldIndex := _
          value := .checkedSub (.stateLoad _) (.param 0)
          byteWidth := 8
        },
        .returnNone
      ] := Array.toList_inj.mp (by assumption)
    cases hparams
    cases hbody
    rfl
  · contradiction

/-- Public syntax recovered from the exact 19-operation production MethodIR. -/
structure GuardedSubTwoUInt64WithdrawMethodIRShapeV1 where
  entryName : String
  parameterSourceId : Nat
  parameterName : String
  markerRegion : KeyRegion
  guard0Region : KeyRegion
  guard1Region : KeyRegion
  load0Region : KeyRegion
  store0Region : KeyRegion
  load1Region : KeyRegion
  store1Region : KeyRegion
  markerValue : UInt64
  deriving Repr

/-- Recognize the exact production sequence, including guard-before-write
    order, local indices, checked subtraction, and natural Unit fall-through. -/
def recognizeGuardedSubTwoUInt64WithdrawMethodIRV1
    (methodIR : MethodIR) :
    Option GuardedSubTwoUInt64WithdrawMethodIRShapeV1 :=
  match methodIR.params.toList, methodIR.mode, methodIR.tempCount,
      methodIR.operations.toList with
  | [{
      sourceId := parameterSourceId
      name := parameterName
      inputOffset := 0
      byteWidth := 8
      endianness := .little
    }], .mutate, 12, [
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout markerRegion markerValue,
      .loadParam 0 0,
      .loadState 1 guard0Region,
      .compare 2 0 1 .le,
      .assert 2,
      .loadParam 3 0,
      .loadState 4 guard1Region,
      .compare 5 3 4 .le,
      .assert 5,
      .loadState 6 load0Region,
      .loadParam 7 0,
      .checkedSub 8 6 7,
      .storeState store0Region 8,
      .loadState 9 load1Region,
      .loadParam 10 0,
      .checkedSub 11 9 10,
      .storeState store1Region 11
    ] => some {
      entryName := methodIR.name
      parameterSourceId
      parameterName
      markerRegion
      guard0Region
      guard1Region
      load0Region
      store0Region
      load1Region
      store1Region
      markerValue
    }
  | _, _, _, _ => none

/-- Successful MethodIR recognition determines every operation and temp. -/
theorem recognizeGuardedSubTwoUInt64WithdrawMethodIRV1_sound
    (methodIR : MethodIR)
    (shape : GuardedSubTwoUInt64WithdrawMethodIRShapeV1)
    (hrecognize :
      recognizeGuardedSubTwoUInt64WithdrawMethodIRV1 methodIR = some shape) :
    methodIR = {
      name := shape.entryName
      params := #[{
        sourceId := shape.parameterSourceId
        name := shape.parameterName
        inputOffset := 0
        byteWidth := 8
        endianness := .little
      }]
      mode := .mutate
      tempCount := 12
      operations := #[
        .checkInputLen 8,
        .requireZeroAttachedDeposit,
        .requireLayout shape.markerRegion shape.markerValue,
        .loadParam 0 0,
        .loadState 1 shape.guard0Region,
        .compare 2 0 1 .le,
        .assert 2,
        .loadParam 3 0,
        .loadState 4 shape.guard1Region,
        .compare 5 3 4 .le,
        .assert 5,
        .loadState 6 shape.load0Region,
        .loadParam 7 0,
        .checkedSub 8 6 7,
        .storeState shape.store0Region 8,
        .loadState 9 shape.load1Region,
        .loadParam 10 0,
        .checkedSub 11 9 10,
        .storeState shape.store1Region 11
      ]
    } := by
  rcases methodIR with ⟨name, params, mode, tempCount, operations⟩
  simp only [recognizeGuardedSubTwoUInt64WithdrawMethodIRV1] at hrecognize
  split at hrecognize
  · cases hrecognize
    have hparams : params = #[{
        sourceId := _
        name := _
        inputOffset := 0
        byteWidth := 8
        endianness := .little
      }] := Array.toList_inj.mp (by assumption)
    have hoperations : operations = #[
        .checkInputLen 8, .requireZeroAttachedDeposit, .requireLayout _ _,
        .loadParam 0 0, .loadState 1 _, .compare 2 0 1 .le, .assert 2,
        .loadParam 3 0, .loadState 4 _, .compare 5 3 4 .le, .assert 5,
        .loadState 6 _, .loadParam 7 0, .checkedSub 8 6 7,
        .storeState _ 8, .loadState 9 _, .loadParam 10 0,
        .checkedSub 11 9 10, .storeState _ 11
      ] := Array.toList_inj.mp (by assumption)
    cases hparams
    cases hoperations
    rfl
  · contradiction

/-- Exact semantic/storage/MethodIR alignment for the selected withdraw entry.
    Complete equalities reject reordered guards, early writes, unchecked
    subtraction, noncanonical fields, or a non-Unit result. -/
structure GuardedSubTwoUInt64WithdrawStaticAlignmentV1
    (data : SemanticProgramDataV1)
    (storage : StorageLayout)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR) : Prop where
  binding0Rel : UInt64StateBindingRelV1 data storage binding0
  binding1Rel : UInt64StateBindingRelV1 data storage binding1
  binding0State : binding0.semanticStateId = 0
  binding1State : binding1.semanticStateId = 1
  bindingTypes : binding0.semanticTypeId = binding1.semanticTypeId
  distinctFields : binding0.physicalFieldIndex ≠ binding1.physicalFieldIndex
  markerKey : markerRegion.key = storage.markerKey
  markerLength : markerRegion.length = storage.markerKey.toUTF8.size
  field0Key : field0Region.key = binding0.physicalKey
  field0Length : field0Region.length = binding0.physicalKey.toUTF8.size
  field1Key : field1Region.key = binding1.physicalKey
  field1Length : field1Region.length = binding1.physicalKey.toUTF8.size
  methodExact : method = {
    name := entryName
    params := #[{
      sourceId := parameterSourceId
      name := parameterName
      inputOffset := 0
      byteWidth := 8
      endianness := .little
    }]
    exactInputLen := 8
    mode := .mutate
    depositPolicy := .requireZero
    resultKind := .unit
    body := #[
      .assert (.compare .le (.param 0)
        (.stateLoad binding0.physicalFieldIndex)),
      .assert (.compare .le (.param 0)
        (.stateLoad binding1.physicalFieldIndex)),
      .store {
        fieldIndex := binding0.physicalFieldIndex
        value := .checkedSub
          (.stateLoad binding0.physicalFieldIndex) (.param 0)
        byteWidth := 8
      },
      .store {
        fieldIndex := binding1.physicalFieldIndex
        value := .checkedSub
          (.stateLoad binding1.physicalFieldIndex) (.param 0)
        byteWidth := 8
      },
      .returnNone
    ]
  }
  methodIRExact : methodIR = {
    name := entryName
    params := #[{
      sourceId := parameterSourceId
      name := parameterName
      inputOffset := 0
      byteWidth := 8
      endianness := .little
    }]
    mode := .mutate
    tempCount := 12
    operations := #[
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout markerRegion storage.markerValue,
      .loadParam 0 0,
      .loadState 1 field0Region,
      .compare 2 0 1 .le,
      .assert 2,
      .loadParam 3 0,
      .loadState 4 field1Region,
      .compare 5 3 4 .le,
      .assert 5,
      .loadState 6 field0Region,
      .loadParam 7 0,
      .checkedSub 8 6 7,
      .storeState field0Region 8,
      .loadState 9 field1Region,
      .loadParam 10 0,
      .checkedSub 11 9 10,
      .storeState field1Region 11
    ]
  }

/-- Production provenance for the selected withdraw entry. -/
structure ProductionGuardedSubTwoUInt64WithdrawStaticAlignmentV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (keys : Array KeyRegion)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR) : Prop where
  semanticValidation : validateSemanticProgramV1 program = .ok data
  keyRegions : KeyRegionsV1 plan keys
  markerLookup : keys[0]? = some markerRegion
  field0Lookup : keys[binding0.physicalFieldIndex + 1]? = some field0Region
  field1Lookup : keys[binding1.physicalFieldIndex + 1]? = some field1Region
  methodLowering : MethodIRLoweringV1 plan keys method methodIR
  staticAlignment :
    GuardedSubTwoUInt64WithdrawStaticAlignmentV1 data plan.storage binding0
      binding1 entryName parameterName parameterSourceId method markerRegion
        field0Region field1Region methodIR

/-- Structural recognition plus the existing production graph constructs the
    exact withdraw alignment without another Plan→IR lowering. -/
theorem productionGuardedSubTwoUInt64WithdrawStaticAlignmentV1_of_recognized
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (plan : Plan)
    (keys : Array KeyRegion)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hkeys : KeyRegionsV1 plan keys)
    (hmarkerLookup : keys[0]? = some markerRegion)
    (hfield0Lookup :
      keys[binding0.physicalFieldIndex + 1]? = some field0Region)
    (hfield1Lookup :
      keys[binding1.physicalFieldIndex + 1]? = some field1Region)
    (hlowering : MethodIRLoweringV1 plan keys method methodIR)
    (hbinding0 : UInt64StateBindingRelV1 data plan.storage binding0)
    (hbinding1 : UInt64StateBindingRelV1 data plan.storage binding1)
    (hbinding0State : binding0.semanticStateId = 0)
    (hbinding1State : binding1.semanticStateId = 1)
    (hbindingTypes : binding0.semanticTypeId = binding1.semanticTypeId)
    (hdistinctFields :
      binding0.physicalFieldIndex ≠ binding1.physicalFieldIndex)
    (hmarkerKey : markerRegion.key = plan.storage.markerKey)
    (hmarkerLength :
      markerRegion.length = plan.storage.markerKey.toUTF8.size)
    (hfield0Key : field0Region.key = binding0.physicalKey)
    (hfield0Length :
      field0Region.length = binding0.physicalKey.toUTF8.size)
    (hfield1Key : field1Region.key = binding1.physicalKey)
    (hfield1Length :
      field1Region.length = binding1.physicalKey.toUTF8.size)
    (hmethodShape :
      recognizeGuardedSubTwoUInt64WithdrawMethodV1 method = some {
        entryName
        parameterSourceId
        parameterName
        guard0Index := binding0.physicalFieldIndex
        guard1Index := binding1.physicalFieldIndex
        store0Index := binding0.physicalFieldIndex
        load0Index := binding0.physicalFieldIndex
        store1Index := binding1.physicalFieldIndex
        load1Index := binding1.physicalFieldIndex
      })
    (hmethodIRShape :
      recognizeGuardedSubTwoUInt64WithdrawMethodIRV1 methodIR = some {
        entryName
        parameterSourceId
        parameterName
        markerRegion
        guard0Region := field0Region
        guard1Region := field1Region
        load0Region := field0Region
        store0Region := field0Region
        load1Region := field1Region
        store1Region := field1Region
        markerValue := plan.storage.markerValue
      }) :
    ProductionGuardedSubTwoUInt64WithdrawStaticAlignmentV1 program data plan keys
      binding0 binding1 entryName parameterName parameterSourceId method
        markerRegion field0Region field1Region methodIR := by
  refine {
    semanticValidation := hvalidate
    keyRegions := hkeys
    markerLookup := hmarkerLookup
    field0Lookup := hfield0Lookup
    field1Lookup := hfield1Lookup
    methodLowering := hlowering
    staticAlignment := {
      binding0Rel := hbinding0
      binding1Rel := hbinding1
      binding0State := hbinding0State
      binding1State := hbinding1State
      bindingTypes := hbindingTypes
      distinctFields := hdistinctFields
      markerKey := hmarkerKey
      markerLength := hmarkerLength
      field0Key := hfield0Key
      field0Length := hfield0Length
      field1Key := hfield1Key
      field1Length := hfield1Length
      methodExact := ?_
      methodIRExact := ?_
    }
  }
  · exact recognizeGuardedSubTwoUInt64WithdrawMethodV1_sound method _
      hmethodShape
  · exact recognizeGuardedSubTwoUInt64WithdrawMethodIRV1_sound methodIR _
      hmethodIRShape

/-- Logical decoding and the three owned KV rows agree after successful
    initialization. This relation consumes target post-storage observations; it
    does not define another target transition. -/
def InitializedZeroTwoUInt64StorageRelV1
    (data : SemanticProgramDataV1)
    (storage : StorageLayout)
    (binding0 binding1 : UInt64StateBindingV1)
    (logical : LogicalStateV1)
    (observed : StorageObservationV1) : Prop :=
  UInt64StateBindingRelV1 data storage binding0 ∧
  UInt64StateBindingRelV1 data storage binding1 ∧
  binding0.semanticStateId = 0 ∧
  binding1.semanticStateId = 1 ∧
  logical.initialized = true ∧
  decodeLogicalStateValuesV1 data logical =
    .ok #[encodeU64le 0, encodeU64le 0] ∧
  observed.lookup storage.markerKey = some (encodeU64le storage.markerValue) ∧
  observed.lookup binding0.physicalKey = some (encodeU64le 0) ∧
  observed.lookup binding1.physicalKey = some (encodeU64le 0)

end ProofForgeV2.Targets.Near

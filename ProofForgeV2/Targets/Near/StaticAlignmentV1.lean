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

end ProofForgeV2.Targets.Near

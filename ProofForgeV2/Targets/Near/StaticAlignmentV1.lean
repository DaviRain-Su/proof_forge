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

end ProofForgeV2.Targets.Near

import ProofForgeV2.Targets.Near.StaticAlignmentV1

/-!
# NEAR MethodSemanticsV1

Target-level execution semantics for the first, deliberately small NEAR
`MethodIR` refinement slice.

Unlike the Reference machine, this module does not interpret a ProofForge
business program. It executes the public target recipe operations emitted for
one nullary UInt64 view. Every operation outside that exact read-only subset is
rejected. The resulting theorems therefore connect production `MethodIR` to
Reference observations without creating a second contract semantics.

This is not WAT, Wasm, or NEAR protocol semantics. Correctness of
`renderOperation`, locked `wat2wasm`, finalized bytes, and the NEAR host remains
outside this module's claim.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Fail-closed errors for the first target recipe execution subset. -/
inductive ReadOnlyMethodErrorV1 where
  | inputLengthMismatch
  | storageMissing
  | storageWidthMismatch
  | layoutMismatch
  | temporaryOutOfBounds
  | temporaryMissing
  | unsupportedOperation
  deriving BEq, Repr

/-- Machine state for the read-only `MethodIR` subset. Storage and input are
    immutable observations; only Wasm-like UInt64 locals and return data
    evolve. -/
structure ReadOnlyMethodMachineV1 where
  input : ByteArray
  storage : StorageObservationV1
  tempCount : Nat
  temps : Nat → Option UInt64
  returnData : Option ByteArray

private def initialReadOnlyMethodMachineV1
    (method : MethodIR)
    (input : ByteArray)
    (storage : StorageObservationV1) : ReadOnlyMethodMachineV1 := {
  input
  storage
  tempCount := method.tempCount
  temps := fun _ => none
  returnData := none
}

private def writeReadOnlyTempV1
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64) : Except ReadOnlyMethodErrorV1 ReadOnlyMethodMachineV1 :=
  if destination < machine.tempCount then
    .ok { machine with
      temps := fun index => if index = destination then some value else machine.temps index
    }
  else
    .error .temporaryOutOfBounds

private def readReadOnlyTempV1
    (machine : ReadOnlyMethodMachineV1)
    (source : Nat) : Except ReadOnlyMethodErrorV1 UInt64 :=
  if source < machine.tempCount then
    match machine.temps source with
    | some value => .ok value
    | none => .error .temporaryMissing
  else
    .error .temporaryOutOfBounds

/-- One target recipe step. The only admitted instructions are the four used
    by the production nullary UInt64 view recipe. -/
def stepReadOnlyMethodOperationV1
    (machine : ReadOnlyMethodMachineV1) :
    Operation → Except ReadOnlyMethodErrorV1 ReadOnlyMethodMachineV1
  | .checkInputLen expected =>
      if machine.input.size = expected then .ok machine
      else .error .inputLengthMismatch
  | .requireLayout marker expected =>
      match machine.storage.lookup marker.key with
      | none => .error .storageMissing
      | some bytes =>
          if bytes.size = 8 then
            if bytes = encodeU64le expected then .ok machine
            else .error .layoutMismatch
          else
            .error .storageWidthMismatch
  | .loadState destination field =>
      match machine.storage.lookup field.key with
      | none => .error .storageMissing
      | some bytes =>
          if bytes.size = 8 then
            writeReadOnlyTempV1 machine destination
              (UInt64.ofNat (leBytesToNatV1 bytes))
          else
            .error .storageWidthMismatch
  | .setReturnData byteLen source =>
      if byteLen = 8 then
        match readReadOnlyTempV1 machine source with
        | .ok value => .ok { machine with returnData := some (encodeU64le value) }
        | .error error => .error error
      else
        .error .unsupportedOperation
  | _ => .error .unsupportedOperation

/-- Big-step execution of the supported operation list. -/
def runReadOnlyMethodOperationsV1 :
    List Operation → ReadOnlyMethodMachineV1 →
      Except ReadOnlyMethodErrorV1 ReadOnlyMethodMachineV1
  | [], machine => .ok machine
  | operation :: remaining, machine => do
      let machine ← stepReadOnlyMethodOperationV1 machine operation
      runReadOnlyMethodOperationsV1 remaining machine

/-- Observable result of executing the admitted target recipe subset. -/
inductive ReadOnlyMethodOutcomeV1 where
  | returned (returnData : Option ByteArray)
  | trapped (error : ReadOnlyMethodErrorV1)
  deriving BEq, Repr

/-- Execute one production `MethodIR` in the first target semantics slice. -/
def executeReadOnlyMethodV1
    (method : MethodIR)
    (input : ByteArray)
    (storage : StorageObservationV1) : ReadOnlyMethodOutcomeV1 :=
  match runReadOnlyMethodOperationsV1 method.operations.toList
      (initialReadOnlyMethodMachineV1 method input storage) with
  | .ok machine => .returned machine.returnData
  | .error error => .trapped error

/-- Canonical call observation derived from target recipe execution. Storage
    is unchanged by construction and this subset has no logs or promises. -/
def observeReadOnlyMethodV1
    (method : MethodIR)
    (input : ByteArray)
    (storage : StorageObservationV1) : CallObservationV1 :=
  match executeReadOnlyMethodV1 method input storage with
  | .returned returnData => {
      exportName := method.name
      input
      returnData
      failureObserved := false
      logs := #[]
      promises := #[]
      preStorage := storage
      postStorage := storage
    }
  | .trapped _ => {
      exportName := method.name
      input
      returnData := none
      failureObserved := true
      logs := #[]
      promises := #[]
      preStorage := storage
      postStorage := storage
    }

/-- Exact execution theorem for the production four-operation UInt64 view
    recipe. The returned bytes are recovered through the shared canonical
    little-endian codec theorem, not a target-local scalar format. -/
theorem executeReadOnlyMethodV1_nullaryUInt64View
    (viewName : String)
    (markerRegion fieldRegion : KeyRegion)
    (markerValue : UInt64)
    (fieldBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup markerRegion.key = some (encodeU64le markerValue))
    (hfield : storage.lookup fieldRegion.key = some fieldBytes)
    (hfieldSize : fieldBytes.size = 8) :
    executeReadOnlyMethodV1 {
      name := viewName
      params := #[]
      mode := .view
      tempCount := 1
      operations := #[
        .checkInputLen 0,
        .requireLayout markerRegion markerValue,
        .loadState 0 fieldRegion,
        .setReturnData 8 0
      ]
    } ByteArray.empty storage = .returned (some fieldBytes) := by
  have hroundtrip :
      encodeU64le (UInt64.ofNat (leBytesToNatV1 fieldBytes)) = fieldBytes :=
    encodeU64le_uint64OfLeBytesToNatV1_of_size fieldBytes hfieldSize
  simp [executeReadOnlyMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1,
    writeReadOnlyTempV1, readReadOnlyTempV1, hmarker, hfield, hfieldSize,
    hroundtrip, encodeU64le_size, Bind.bind, Except.bind]

/-- Static alignment plus initialized storage representation is sufficient to
    execute the selected production MethodIR successfully. -/
theorem executeReadOnlyMethodV1_of_nullaryUInt64ViewStaticAlignment
    (data : SemanticProgramDataV1)
    (storageLayout : StorageLayout)
    (binding : UInt64StateBindingV1)
    (viewName : String)
    (method : Method)
    (markerRegion fieldRegion : KeyRegion)
    (methodIR : MethodIR)
    (logical : LogicalStateV1)
    (decodedValues : Array ByteArray)
    (valueBytes : ByteArray)
    (storage : StorageObservationV1)
    (halignment :
      NullaryUInt64ViewStaticAlignmentV1 data storageLayout binding viewName
        method markerRegion fieldRegion methodIR)
    (hstorage :
      InitializedUInt64StorageRelV1 data storageLayout binding logical
        decodedValues valueBytes storage)
    (hvalueSize : valueBytes.size = 8) :
    executeReadOnlyMethodV1 methodIR ByteArray.empty storage =
      .returned (some valueBytes) := by
  rcases halignment with
    ⟨_, hmarkerKey, _, hfieldKey, _, _, hmethodIR⟩
  rcases hstorage with ⟨_, _, _, _, hmarker, hfield⟩
  subst methodIR
  apply executeReadOnlyMethodV1_nullaryUInt64View
  · simpa [hmarkerKey] using hmarker
  · simpa [hfieldKey] using hfield
  · exact hvalueSize

/-- First kernel-checkable Reference→NEAR MethodIR refinement theorem. The
    target-side success/return/log/promise/storage facts are derived from the
    target recipe execution above rather than supplied as passive premises.

    This closes only the selected MethodIR slice; it does not prove the WAT
    renderer, Wasm binary, `wat2wasm`, or NEAR host implementation. -/
theorem uint64ReturnedObservationRelV1_of_readyViewLoad_and_methodExecution
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
    (viewName : String)
    (context : Array ContextInputV1)
    (vault : ReferenceVaultSeedV1)
    (storageLayout : StorageLayout)
    (binding : UInt64StateBindingV1)
    (method : Method)
    (markerRegion fieldRegion : KeyRegion)
    (methodIR : MethodIR)
    (targetStorage : StorageObservationV1)
    (hbindingStateId : binding.semanticStateId = stateId)
    (hbindingTypeId : binding.semanticTypeId = uint64TypeId)
    (hbindingStateName : binding.semanticName = stateName)
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
          name := some viewName
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
    (halignment :
      NullaryUInt64ViewStaticAlignmentV1 data storageLayout binding viewName
        method markerRegion fieldRegion methodIR)
    (hstorage :
      InitializedUInt64StorageRelV1 data storageLayout binding pre overlay
        loadedBytes targetStorage) :
    UInt64ReturnedObservationRelV1 data uint64TypeId pre
      (stepReferenceSliceV1 admitted pre invocation #[] vault)
      loadedBytes
      (observeReadOnlyMethodV1 methodIR ByteArray.empty targetStorage) := by
  subst stateId
  subst uint64TypeId
  subst stateName
  have hcanonical :
      validateValueBytesV1 data.types binding.semanticTypeId loadedBytes = .ok () :=
    validateValueBytesV1_of_decodeLogicalStateValuesV1_getElem data pre
      overlay hstorage.2.2.1 binding.semanticStateId.toNat
      {
        id := binding.semanticStateId
        name := binding.semanticName
        typeId := binding.semanticTypeId
        visibility := .public_
      }
      loadedBytes hstate hloaded
  have hsize : loadedBytes.size = 8 :=
    validateValueBytesV1_uint64_size data.types binding.semanticTypeId
      {
        id := binding.semanticTypeId
        name := none
        shape := .uint 64
      }
      loadedBytes htypeU rfl hcanonical
  have hexecute :
      executeReadOnlyMethodV1 methodIR ByteArray.empty targetStorage =
        .returned (some loadedBytes) :=
    executeReadOnlyMethodV1_of_nullaryUInt64ViewStaticAlignment data
      storageLayout binding viewName method markerRegion fieldRegion methodIR
      pre overlay loadedBytes targetStorage halignment hstorage hsize
  apply uint64ReturnedObservationRelV1_of_readyViewLoad admitted pre invocation
    data overlay loadedBytes binding.semanticTypeId binding.semanticStateId
      binding.semanticName callableId
      (some viewName) context vault
      (observeReadOnlyMethodV1 methodIR ByteArray.empty targetStorage)
      hadmittedData htypeU hstate hloaded hgate
  all_goals simp [observeReadOnlyMethodV1, hexecute]

end ProofForgeV2.Targets.Near

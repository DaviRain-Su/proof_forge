import ProofForgeV2.Targets.Near.MethodSemanticsV1

/-!
# NEAR WATSemanticsV1

Execution semantics for the typed WAT instruction subset that the production
renderer now uses for the nullary UInt64 view recipe.

This is intentionally bounded. Scratch memory is modeled as exact byte blocks
at the offsets touched by this recipe, while `storageRead` retains the
production `KeyRegion` data-segment annotation. It does not yet model arbitrary
Wasm linear-memory overlap, validation, binary decoding, `wat2wasm`, or the
complete NEAR host ABI.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Fail-closed errors for the first typed WAT execution subset. -/
inductive ReadOnlyWATErrorV1 where
  | trap
  | localOutOfBounds
  | localMissing
  | registerMissing
  | memoryMissing
  | memoryWidthMismatch
  | unsupportedReturnWidth
  deriving BEq, Repr

/-- Machine state for the typed read-only WAT subset. Registers and scratch
    memory are target-level host/Wasm state; input and storage are immutable
    environment observations. -/
structure ReadOnlyWATMachineV1 where
  input : ByteArray
  storage : StorageObservationV1
  localCount : Nat
  locals : Nat → Option UInt64
  registers : Nat → Option ByteArray
  memory : Nat → Option ByteArray
  returnData : Option ByteArray

private def initialReadOnlyWATMachineV1
    (localCount : Nat)
    (input : ByteArray)
    (storage : StorageObservationV1) : ReadOnlyWATMachineV1 := {
  input
  storage
  localCount
  locals := fun _ => none
  registers := fun _ => none
  memory := fun _ => none
  returnData := none
}

private def setReadOnlyWATRegisterV1
    (machine : ReadOnlyWATMachineV1)
    (register : Nat)
    (value : Option ByteArray) : ReadOnlyWATMachineV1 :=
  { machine with
    registers := fun index =>
      if index = register then value else machine.registers index
  }

private def setReadOnlyWATMemoryV1
    (machine : ReadOnlyWATMachineV1)
    (offset : Nat)
    (value : ByteArray) : ReadOnlyWATMachineV1 :=
  { machine with
    memory := fun index =>
      if index = offset then some value else machine.memory index
  }

private def setReadOnlyWATLocalV1
    (machine : ReadOnlyWATMachineV1)
    (index : Nat)
    (value : UInt64) : Except ReadOnlyWATErrorV1 ReadOnlyWATMachineV1 :=
  if index < machine.localCount then
    .ok { machine with
      locals := fun candidate =>
        if candidate = index then some value else machine.locals candidate
    }
  else
    .error .localOutOfBounds

/-- Evaluate one typed i64 expression. `storageRead` has the NEAR host-call
    side effect of filling or clearing the selected register and returns 1/0. -/
def evalReadOnlyWATI64ExprV1
    (machine : ReadOnlyWATMachineV1) :
    ReadOnlyWATI64ExprV1 →
      Except ReadOnlyWATErrorV1 (ReadOnlyWATMachineV1 × UInt64)
  | .i64Const value => .ok (machine, UInt64.ofNat value)
  | .localGet index =>
      if index < machine.localCount then
        match machine.locals index with
        | some value => .ok (machine, value)
        | none => .error .localMissing
      else
        .error .localOutOfBounds
  | .i64Load offset =>
      match machine.memory offset with
      | none => .error .memoryMissing
      | some bytes =>
          if bytes.size = 8 then
            .ok (machine, UInt64.ofNat (leBytesToNatV1 bytes))
          else
            .error .memoryWidthMismatch
  | .registerLen register =>
      match machine.registers register with
      | some bytes => .ok (machine, UInt64.ofNat bytes.size)
      | none => .ok (machine, UInt64.ofNat 18446744073709551615)
  | .storageRead field register =>
      match machine.storage.lookup field.key with
      | some bytes =>
          .ok (setReadOnlyWATRegisterV1 machine register (some bytes), 1)
      | none =>
          .ok (setReadOnlyWATRegisterV1 machine register none, 0)

/-- Execute one typed instruction from the bounded WAT subset. -/
def stepReadOnlyWATInstructionV1
    (machine : ReadOnlyWATMachineV1) :
    ReadOnlyWATInstructionV1 →
      Except ReadOnlyWATErrorV1 ReadOnlyWATMachineV1
  | .input register =>
      .ok (setReadOnlyWATRegisterV1 machine register (some machine.input))
  | .trapIfI64Ne left right => do
      let (machine, leftValue) ← evalReadOnlyWATI64ExprV1 machine left
      let (machine, rightValue) ← evalReadOnlyWATI64ExprV1 machine right
      if leftValue = rightValue then .ok machine else .error .trap
  | .readRegister register offset =>
      match machine.registers register with
      | some bytes => .ok (setReadOnlyWATMemoryV1 machine offset bytes)
      | none => .error .registerMissing
  | .localSet index value => do
      let (machine, value) ← evalReadOnlyWATI64ExprV1 machine value
      setReadOnlyWATLocalV1 machine index value
  | .i64Store offset value => do
      let (machine, value) ← evalReadOnlyWATI64ExprV1 machine value
      .ok (setReadOnlyWATMemoryV1 machine offset (encodeU64le value))
  | .valueReturn byteLen offset =>
      if byteLen = 8 then
        match machine.memory offset with
        | none => .error .memoryMissing
        | some bytes =>
            if bytes.size = 8 then
              .ok { machine with returnData := some bytes }
            else
              .error .memoryWidthMismatch
      else
        .error .unsupportedReturnWidth

/-- Big-step execution for a typed instruction list. -/
def runReadOnlyWATInstructionsV1 :
    List ReadOnlyWATInstructionV1 → ReadOnlyWATMachineV1 →
      Except ReadOnlyWATErrorV1 ReadOnlyWATMachineV1
  | [], machine => .ok machine
  | instruction :: remaining, machine => do
      let machine ← stepReadOnlyWATInstructionV1 machine instruction
      runReadOnlyWATInstructionsV1 remaining machine

/-- Observable result of the bounded typed WAT machine. -/
inductive ReadOnlyWATOutcomeV1 where
  | returned (returnData : Option ByteArray)
  | trapped (error : ReadOnlyWATErrorV1)
  deriving BEq, Repr

/-- Execute one bounded typed WAT method body. -/
def executeReadOnlyWATV1
    (localCount : Nat)
    (instructions : Array ReadOnlyWATInstructionV1)
    (input : ByteArray)
    (storage : StorageObservationV1) : ReadOnlyWATOutcomeV1 :=
  match runReadOnlyWATInstructionsV1 instructions.toList
      (initialReadOnlyWATMachineV1 localCount input storage) with
  | .ok machine => .returned machine.returnData
  | .error error => .trapped error

/-- Canonical call observation derived from bounded typed WAT execution. -/
def observeReadOnlyWATV1
    (exportName : String)
    (localCount : Nat)
    (instructions : Array ReadOnlyWATInstructionV1)
    (input : ByteArray)
    (storage : StorageObservationV1) : CallObservationV1 :=
  match executeReadOnlyWATV1 localCount instructions input storage with
  | .returned returnData => {
      exportName
      input
      returnData
      failureObserved := false
      logs := #[]
      promises := #[]
      preStorage := storage
      postStorage := storage
    }
  | .trapped _ => {
      exportName
      input
      returnData := none
      failureObserved := true
      logs := #[]
      promises := #[]
      preStorage := storage
      postStorage := storage
    }

/-- Exact execution of the typed WAT sequence emitted for a nullary UInt64
    view. -/
theorem executeReadOnlyWATV1_nullaryUInt64View
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field : KeyRegion)
    (markerValue : UInt64)
    (fieldBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield : storage.lookup field.key = some fieldBytes)
    (hfieldSize : fieldBytes.size = 8) :
    executeReadOnlyWATV1 1
      (nullaryUInt64ViewWATV1 registers memory marker markerValue field)
      ByteArray.empty storage = .returned (some fieldBytes) := by
  have hmarkerRoundtrip :
      UInt64.ofNat (leBytesToNatV1 (encodeU64le markerValue)) = markerValue := by
    rw [leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat]
  have hroundtrip :
      encodeU64le (UInt64.ofNat (leBytesToNatV1 fieldBytes)) = fieldBytes :=
    encodeU64le_uint64OfLeBytesToNatV1_of_size fieldBytes hfieldSize
  simp [executeReadOnlyWATV1, nullaryUInt64ViewWATV1,
    checkEmptyInputWATV1, requireLayoutWATV1, loadUInt64StateWATV1,
    returnUInt64WATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1, hmarker, hfield,
    hfieldSize, hmarkerRoundtrip, hroundtrip, encodeU64le_size, Bind.bind,
    Except.bind]

/-- The exact production MethodIR recipe and its typed WAT lowering return the
    same bytes under the same target storage observation. -/
theorem methodIR_and_WAT_nullaryUInt64View_return_same
    (viewName : String)
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field : KeyRegion)
    (markerValue : UInt64)
    (fieldBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield : storage.lookup field.key = some fieldBytes)
    (hfieldSize : fieldBytes.size = 8) :
    executeReadOnlyMethodV1 {
      name := viewName
      params := #[]
      mode := .view
      tempCount := 1
      operations := #[
        .checkInputLen 0,
        .requireLayout marker markerValue,
        .loadState 0 field,
        .setReturnData 8 0
      ]
    } ByteArray.empty storage = .returned (some fieldBytes) ∧
    executeReadOnlyWATV1 1
      (nullaryUInt64ViewWATV1 registers memory marker markerValue field)
      ByteArray.empty storage = .returned (some fieldBytes) := by
  exact ⟨
    executeReadOnlyMethodV1_nullaryUInt64View viewName marker field markerValue
      fieldBytes storage hmarker hfield hfieldSize,
    executeReadOnlyWATV1_nullaryUInt64View registers memory marker field
      markerValue fieldBytes storage hmarker hfield hfieldSize
  ⟩

/-- Static alignment plus initialized storage representation executes the
    typed WAT lowering selected by the production MethodIR. -/
theorem executeReadOnlyWATV1_of_nullaryUInt64ViewStaticAlignment
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (storageLayout : StorageLayout)
    (binding : UInt64StateBindingV1)
    (viewName : String)
    (method : Method)
    (marker field : KeyRegion)
    (methodIR : MethodIR)
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (logical : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (decodedValues : Array ByteArray)
    (valueBytes : ByteArray)
    (storage : StorageObservationV1)
    (halignment :
      NullaryUInt64ViewStaticAlignmentV1 data storageLayout binding viewName
        method marker field methodIR)
    (hstorage :
      InitializedUInt64StorageRelV1 data storageLayout binding logical
        decodedValues valueBytes storage)
    (hvalueSize : valueBytes.size = 8) :
    executeReadOnlyWATV1 1
      (nullaryUInt64ViewWATV1 registers memory marker
        storageLayout.markerValue field)
      ByteArray.empty storage = .returned (some valueBytes) := by
  rcases halignment with
    ⟨_, hmarkerKey, _, hfieldKey, _, _, _⟩
  rcases hstorage with ⟨_, _, _, _, hmarker, hfield⟩
  apply executeReadOnlyWATV1_nullaryUInt64View registers memory marker field
    storageLayout.markerValue valueBytes storage
  · simpa [hmarkerKey] using hmarker
  · simpa [hfieldKey] using hfield
  · exact hvalueSize

/-- Reference→typed-WAT composition for the first view slice. The proof reuses
    the existing Reference→MethodIR theorem and the production MethodIR→typed
    WAT execution equality; it introduces no additional business transition. -/
theorem uint64ReturnedObservationRelV1_of_readyViewLoad_and_WATExecution
    (admitted : AdmittedReferenceSliceV1)
    (pre : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (invocation : InvocationV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (overlay : Array ByteArray)
    (loadedBytes : ByteArray)
    (uint64TypeId : ProofForgeV2.Semantic.WireV1.TypeIdV1)
    (stateId : ProofForgeV2.Semantic.WireV1.StateIdV1)
    (stateName : String)
    (callableId : ProofForgeV2.Semantic.WireV1.CallableIdV1)
    (viewName : String)
    (context : Array ContextInputV1)
    (vault : ReferenceVaultSeedV1)
    (storageLayout : StorageLayout)
    (binding : UInt64StateBindingV1)
    (method : Method)
    (marker field : KeyRegion)
    (methodIR : MethodIR)
    (registers : RegisterLayout)
    (memory : MemoryLayout)
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
        method marker field methodIR)
    (hstorage :
      InitializedUInt64StorageRelV1 data storageLayout binding pre overlay
        loadedBytes targetStorage) :
    UInt64ReturnedObservationRelV1 data uint64TypeId pre
      (stepReferenceSliceV1 admitted pre invocation #[] vault)
      loadedBytes
      (observeReadOnlyWATV1 viewName 1
        (nullaryUInt64ViewWATV1 registers memory marker
          storageLayout.markerValue field)
        ByteArray.empty targetStorage) := by
  have hmethodRelation :=
    uint64ReturnedObservationRelV1_of_readyViewLoad_and_methodExecution
      admitted pre invocation data overlay loadedBytes uint64TypeId stateId
      stateName callableId viewName context vault storageLayout binding method
      marker field methodIR targetStorage hbindingStateId hbindingTypeId
      hbindingStateName hadmittedData htypeU hstate hloaded hgate halignment
      hstorage
  have hcanonical :
      ProofForgeV2.Semantic.WireV1.validateValueBytesV1 data.types
        binding.semanticTypeId loadedBytes = .ok () :=
    ProofForgeV2.Semantic.InvariantABI.validateValueBytesV1_of_decodeLogicalStateValuesV1_getElem
      data pre overlay hstorage.2.2.1 binding.semanticStateId.toNat
      {
        id := binding.semanticStateId
        name := binding.semanticName
        typeId := binding.semanticTypeId
        visibility := .public_
      }
      loadedBytes (by simpa [hbindingStateId, hbindingTypeId,
        hbindingStateName] using hstate) (by simpa [hbindingStateId] using hloaded)
  have hsize : loadedBytes.size = 8 :=
    ProofForgeV2.Semantic.WireV1.validateValueBytesV1_uint64_size
      data.types binding.semanticTypeId {
        id := binding.semanticTypeId
        name := none
        shape := .uint 64
      }
      loadedBytes (by simpa [hbindingTypeId] using htypeU) rfl hcanonical
  have hmethodExecution :
      executeReadOnlyMethodV1 methodIR ByteArray.empty targetStorage =
        .returned (some loadedBytes) :=
    executeReadOnlyMethodV1_of_nullaryUInt64ViewStaticAlignment data
      storageLayout binding viewName method marker field methodIR pre overlay
      loadedBytes targetStorage halignment hstorage hsize
  have hwatExecution :
      executeReadOnlyWATV1 1
        (nullaryUInt64ViewWATV1 registers memory marker
          storageLayout.markerValue field)
        ByteArray.empty targetStorage = .returned (some loadedBytes) :=
    executeReadOnlyWATV1_of_nullaryUInt64ViewStaticAlignment data
      storageLayout binding viewName method marker field methodIR registers
      memory pre overlay loadedBytes targetStorage halignment hstorage hsize
  have hmethodName : methodIR.name = viewName := by
    simpa using congrArg MethodIR.name halignment.2.2.2.2.2.2
  simpa [observeReadOnlyMethodV1, observeReadOnlyWATV1, hmethodExecution,
    hwatExecution, hmethodName] using hmethodRelation

end ProofForgeV2.Targets.Near

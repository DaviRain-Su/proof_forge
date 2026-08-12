import ProofForgeV2.Targets.Near.StaticAlignmentV1

/-!
# NEAR MethodSemanticsV1

Target-level execution semantics for the deliberately bounded NEAR `MethodIR`
refinement slice.

Unlike the Reference machine, this module does not interpret a ProofForge
business program. It executes the public target recipe operations admitted by
the selected view and initializer slices. Every operation outside that bounded
subset is rejected. The resulting theorems therefore connect production
`MethodIR` to Reference observations without creating a second contract
semantics.

This is not WAT, Wasm, or NEAR protocol semantics. Correctness of
`renderOperation`, locked `wat2wasm`, finalized bytes, and the NEAR host remains
outside this module's claim.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Fail-closed errors for the bounded target recipe execution subset. -/
inductive ReadOnlyMethodErrorV1 where
  | inputLengthMismatch
  | attachedDepositNotZero
  | storageMissing
  | storageAlreadyPresent
  | storageWidthMismatch
  | layoutMismatch
  | temporaryOutOfBounds
  | temporaryMissing
  | unsupportedOperation
  deriving BEq, Repr

/-- Machine state for the sole bounded `MethodIR` subset. Input and attached
    deposit are immutable host observations; storage, Wasm-like UInt64 locals,
    and return data evolve. -/
structure ReadOnlyMethodMachineV1 where
  input : ByteArray
  attachedDepositLow : UInt64
  attachedDepositHigh : UInt64
  storage : StorageObservationV1
  tempCount : Nat
  temps : Nat → Option UInt64
  returnData : Option ByteArray

private def initialReadOnlyMethodMachineV1
    (method : MethodIR)
    (input : ByteArray)
    (attachedDepositLow attachedDepositHigh : UInt64)
    (storage : StorageObservationV1) : ReadOnlyMethodMachineV1 := {
  input
  attachedDepositLow
  attachedDepositHigh
  storage
  tempCount := method.tempCount
  temps := fun _ => none
  returnData := none
}

/-- Functional update of one observed NEAR KV row. This is the sole physical
    storage update primitive shared by MethodIR and typed-WAT execution. -/
def writeStorageObservationV1
    (storage : StorageObservationV1)
    (key : String)
    (value : ByteArray) : StorageObservationV1 := {
  lookup := fun candidate =>
    if candidate = key then some value else storage.lookup candidate
}

private def writeReadOnlyMethodStorageV1
    (machine : ReadOnlyMethodMachineV1)
    (key : String)
    (value : ByteArray) : ReadOnlyMethodMachineV1 :=
  { machine with storage := writeStorageObservationV1 machine.storage key value }

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

/-- One target recipe step for the sole bounded MethodIR semantics. -/
def stepReadOnlyMethodOperationV1
    (machine : ReadOnlyMethodMachineV1) :
    Operation → Except ReadOnlyMethodErrorV1 ReadOnlyMethodMachineV1
  | .checkInputLen expected =>
      if machine.input.size = expected then .ok machine
      else .error .inputLengthMismatch
  | .requireZeroAttachedDeposit =>
      if machine.attachedDepositLow = 0 ∧ machine.attachedDepositHigh = 0 then
        .ok machine
      else
        .error .attachedDepositNotZero
  | .requireLayoutAbsent marker =>
      match machine.storage.lookup marker.key with
      | none => .ok machine
      | some _ => .error .storageAlreadyPresent
  | .requireLayout marker expected =>
      match machine.storage.lookup marker.key with
      | none => .error .storageMissing
      | some bytes =>
          if bytes.size = 8 then
            if bytes = encodeU64le expected then .ok machine
            else .error .layoutMismatch
          else
            .error .storageWidthMismatch
  | .zeroState field =>
      match machine.storage.lookup field.key with
      | none =>
          .ok (writeReadOnlyMethodStorageV1 machine field.key (encodeU64le 0))
      | some _ => .error .storageAlreadyPresent
  | .literal destination value =>
      writeReadOnlyTempV1 machine destination value
  | .loadState destination field =>
      match machine.storage.lookup field.key with
      | none => .error .storageMissing
      | some bytes =>
          if bytes.size = 8 then
            writeReadOnlyTempV1 machine destination
              (UInt64.ofNat (leBytesToNatV1 bytes))
          else
            .error .storageWidthMismatch
  | .storeState field source =>
      match machine.storage.lookup field.key with
      | none => .error .storageMissing
      | some oldBytes =>
          if oldBytes.size = 8 then
            match readReadOnlyTempV1 machine source with
            | .ok value =>
                .ok (writeReadOnlyMethodStorageV1 machine field.key
                  (encodeU64le value))
            | .error error => .error error
          else
            .error .storageWidthMismatch
  | .setLayout marker value =>
      match machine.storage.lookup marker.key with
      | none =>
          .ok (writeReadOnlyMethodStorageV1 machine marker.key
            (encodeU64le value))
      | some _ => .error .storageAlreadyPresent
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

/-- Successful bounded MethodIR execution includes the post-storage snapshot.
    Failure omits machine state, so callers necessarily observe transactional
    rollback to the supplied pre-storage snapshot. -/
inductive MethodExecutionOutcomeV1 where
  | returned (returnData : Option ByteArray) (postStorage : StorageObservationV1)
  | trapped (error : ReadOnlyMethodErrorV1)

/-- Execute one production `MethodIR` in the sole bounded target semantics. -/
def executeMethodV1
    (method : MethodIR)
    (input : ByteArray)
    (attachedDepositLow attachedDepositHigh : UInt64)
    (storage : StorageObservationV1) : MethodExecutionOutcomeV1 :=
  match runReadOnlyMethodOperationsV1 method.operations.toList
      (initialReadOnlyMethodMachineV1 method input attachedDepositLow
        attachedDepositHigh storage) with
  | .ok machine => .returned machine.returnData machine.storage
  | .error error => .trapped error

/-- Historical read-only projection. It uses a zero attached deposit and drops
    post-storage only after the shared evaluator has completed. -/
def executeReadOnlyMethodV1
    (method : MethodIR)
    (input : ByteArray)
    (storage : StorageObservationV1) : ReadOnlyMethodOutcomeV1 :=
  match executeMethodV1 method input 0 0 storage with
  | .returned returnData _ => .returned returnData
  | .trapped error => .trapped error

/-- Canonical call observation derived from bounded MethodIR execution. -/
def observeMethodV1
    (method : MethodIR)
    (input : ByteArray)
    (attachedDepositLow attachedDepositHigh : UInt64)
    (storage : StorageObservationV1) : CallObservationV1 :=
  match executeMethodV1 method input attachedDepositLow attachedDepositHigh
      storage with
  | .returned returnData postStorage => {
      exportName := method.name
      input
      returnData
      failureObserved := false
      logs := #[]
      promises := #[]
      preStorage := storage
      postStorage
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
  simp [executeReadOnlyMethodV1, executeMethodV1,
    runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1,
    writeReadOnlyTempV1, readReadOnlyTempV1, hmarker, hfield, hfieldSize,
    hroundtrip, encodeU64le_size, Bind.bind, Except.bind]

/-- Exact post-storage produced by the selected two-UInt64 initializer recipe.
    The repeated field writes are retained because they correspond exactly to
    the production zero-state prologue followed by the initializer body. -/
def zeroTwoUInt64InitializerPostStorageV1
    (storage : StorageObservationV1)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64) : StorageObservationV1 :=
  writeStorageObservationV1
    (writeStorageObservationV1
      (writeStorageObservationV1
        (writeStorageObservationV1
          (writeStorageObservationV1 storage field0.key (encodeU64le 0))
          field1.key (encodeU64le 0))
        field0.key (encodeU64le 0))
      field1.key (encodeU64le 0))
    marker.key (encodeU64le markerValue)

/-- Exact execution of the production MethodIR recipe for the selected
    nullary, two-UInt64 zero initializer. -/
theorem executeMethodV1_nullaryZeroTwoUInt64Initializer
    (initializerName : String)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = none)
    (hfield0 : storage.lookup field0.key = none)
    (hfield1 : storage.lookup field1.key = none)
    (hfield10 : field1.key ≠ field0.key)
    (hmarker0 : marker.key ≠ field0.key)
    (hmarker1 : marker.key ≠ field1.key) :
    executeMethodV1 {
      name := initializerName
      params := #[]
      mode := .initialize
      tempCount := 2
      operations := #[
        .checkInputLen 0,
        .requireZeroAttachedDeposit,
        .requireLayoutAbsent marker,
        .zeroState field0,
        .zeroState field1,
        .literal 0 0,
        .storeState field0 0,
        .literal 1 0,
        .storeState field1 1,
        .setLayout marker markerValue
      ]
    } ByteArray.empty 0 0 storage =
      .returned none
        (zeroTwoUInt64InitializerPostStorageV1 storage marker field0 field1
          markerValue) := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1,
    writeReadOnlyTempV1, readReadOnlyTempV1, writeReadOnlyMethodStorageV1,
    writeStorageObservationV1, zeroTwoUInt64InitializerPostStorageV1,
    hmarker, hfield0, hfield1, hfield10, hmarker0, hmarker1,
    encodeU64le_size, Bind.bind, Except.bind]

/-- Nonempty ABI input rejects initialization before deposit or storage is
    inspected. -/
theorem executeMethodV1_nullaryZeroTwoUInt64Initializer_nonempty_input
    (initializerName : String)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (input : ByteArray)
    (storage : StorageObservationV1)
    (hinput : input.size ≠ 0) :
    executeMethodV1 {
      name := initializerName
      params := #[]
      mode := .initialize
      tempCount := 2
      operations := #[
        .checkInputLen 0,
        .requireZeroAttachedDeposit,
        .requireLayoutAbsent marker,
        .zeroState field0,
        .zeroState field1,
        .literal 0 0,
        .storeState field0 0,
        .literal 1 0,
        .storeState field1 1,
        .setLayout marker markerValue
      ]
    } input 0 0 storage = .trapped .inputLengthMismatch := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hinput,
    Bind.bind, Except.bind]

/-- An existing layout marker rejects re-initialization before any write. -/
theorem executeMethodV1_nullaryZeroTwoUInt64Initializer_double_init
    (initializerName : String)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (markerBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some markerBytes) :
    executeMethodV1 {
      name := initializerName
      params := #[]
      mode := .initialize
      tempCount := 2
      operations := #[
        .checkInputLen 0,
        .requireZeroAttachedDeposit,
        .requireLayoutAbsent marker,
        .zeroState field0,
        .zeroState field1,
        .literal 0 0,
        .storeState field0 0,
        .literal 1 0,
        .storeState field1 1,
        .setLayout marker markerValue
      ]
    } ByteArray.empty 0 0 storage = .trapped .storageAlreadyPresent := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hmarker,
    Bind.bind, Except.bind]

/-- A nonzero low attached-deposit limb rejects initialization before storage
    is inspected or changed. -/
theorem executeMethodV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit
    (initializerName : String)
    (marker field0 field1 : KeyRegion)
    (markerValue depositLow : UInt64)
    (storage : StorageObservationV1)
    (hdeposit : depositLow ≠ 0) :
    executeMethodV1 {
      name := initializerName
      params := #[]
      mode := .initialize
      tempCount := 2
      operations := #[
        .checkInputLen 0,
        .requireZeroAttachedDeposit,
        .requireLayoutAbsent marker,
        .zeroState field0,
        .zeroState field1,
        .literal 0 0,
        .storeState field0 0,
        .literal 1 0,
        .storeState field1 1,
        .setLayout marker markerValue
      ]
    } ByteArray.empty depositLow 0 storage =
      .trapped .attachedDepositNotZero := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hdeposit,
    Bind.bind, Except.bind]

/-- A nonzero high attached-deposit limb is rejected by the same u128 deposit
    gate before storage is inspected or changed. -/
theorem executeMethodV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit_high
    (initializerName : String)
    (marker field0 field1 : KeyRegion)
    (markerValue depositHigh : UInt64)
    (storage : StorageObservationV1)
    (hdeposit : depositHigh ≠ 0) :
    executeMethodV1 {
      name := initializerName
      params := #[]
      mode := .initialize
      tempCount := 2
      operations := #[
        .checkInputLen 0,
        .requireZeroAttachedDeposit,
        .requireLayoutAbsent marker,
        .zeroState field0,
        .zeroState field1,
        .literal 0 0,
        .storeState field0 0,
        .literal 1 0,
        .storeState field1 1,
        .setLayout marker markerValue
      ]
    } ByteArray.empty 0 depositHigh storage =
      .trapped .attachedDepositNotZero := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hdeposit,
    Bind.bind, Except.bind]

/-- The selected initializer's final marker row is canonical. -/
theorem zeroTwoUInt64InitializerPostStorageV1_lookup_marker
    (storage : StorageObservationV1)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64) :
    (zeroTwoUInt64InitializerPostStorageV1 storage marker field0 field1
      markerValue).lookup marker.key = some (encodeU64le markerValue) := by
  simp [zeroTwoUInt64InitializerPostStorageV1, writeStorageObservationV1]

/-- The selected initializer's first field row is canonical UInt64 zero. -/
theorem zeroTwoUInt64InitializerPostStorageV1_lookup_field0
    (storage : StorageObservationV1)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (hfield10 : field1.key ≠ field0.key)
    (hmarker0 : marker.key ≠ field0.key) :
    (zeroTwoUInt64InitializerPostStorageV1 storage marker field0 field1
      markerValue).lookup field0.key = some (encodeU64le 0) := by
  simp [zeroTwoUInt64InitializerPostStorageV1, writeStorageObservationV1,
    hfield10.symm, hmarker0.symm]

/-- The selected initializer's second field row is canonical UInt64 zero. -/
theorem zeroTwoUInt64InitializerPostStorageV1_lookup_field1
    (storage : StorageObservationV1)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (hmarker1 : marker.key ≠ field1.key) :
    (zeroTwoUInt64InitializerPostStorageV1 storage marker field0 field1
      markerValue).lookup field1.key = some (encodeU64le 0) := by
  simp [zeroTwoUInt64InitializerPostStorageV1, writeStorageObservationV1,
    hmarker1.symm]

/-- Static alignment specializes the shared MethodIR evaluator to the exact
    production initializer recipe. -/
theorem executeMethodV1_of_nullaryZeroTwoUInt64InitializerStaticAlignment
    (data : SemanticProgramDataV1)
    (storageLayout : StorageLayout)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (marker field0 field1 : KeyRegion)
    (methodIR : MethodIR)
    (storage : StorageObservationV1)
    (halignment :
      NullaryZeroTwoUInt64InitializerStaticAlignmentV1 data storageLayout
        binding0 binding1 initializerName method marker field0 field1 methodIR)
    (hmarker : storage.lookup marker.key = none)
    (hfield0 : storage.lookup field0.key = none)
    (hfield1 : storage.lookup field1.key = none)
    (hfield10 : field1.key ≠ field0.key)
    (hmarker0 : marker.key ≠ field0.key)
    (hmarker1 : marker.key ≠ field1.key) :
    executeMethodV1 methodIR ByteArray.empty 0 0 storage =
      .returned none
        (zeroTwoUInt64InitializerPostStorageV1 storage marker field0 field1
          storageLayout.markerValue) := by
  rw [halignment.methodIRExact]
  exact executeMethodV1_nullaryZeroTwoUInt64Initializer initializerName marker
    field0 field1 storageLayout.markerValue storage hmarker hfield0 hfield1
    hfield10 hmarker0 hmarker1

/-- Join a Reference-produced canonical initializer post-state with exact
    production MethodIR execution and physical KV representation. The
    `hpostEncode` premise is discharged directly by
    `postEncode_of_readyInitializerStoreZeroTwoV1` for the selected Reference
    initializer; no target-local business transition is introduced. -/
theorem initializedZeroTwoUInt64StorageRelV1_of_postEncode_and_methodExecution
    (data : SemanticProgramDataV1)
    (storageLayout : StorageLayout)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (marker field0 field1 : KeyRegion)
    (methodIR : MethodIR)
    (preStorage : StorageObservationV1)
    (post : LogicalStateV1)
    (halignment :
      NullaryZeroTwoUInt64InitializerStaticAlignmentV1 data storageLayout
        binding0 binding1 initializerName method marker field0 field1 methodIR)
    (hpostEncode :
      encodeLogicalStateValuesV1 data true
        #[encodeU64le 0, encodeU64le 0] = .ok post)
    (hmarker : preStorage.lookup marker.key = none)
    (hfield0 : preStorage.lookup field0.key = none)
    (hfield1 : preStorage.lookup field1.key = none)
    (hfield10 : field1.key ≠ field0.key)
    (hmarker0 : marker.key ≠ field0.key)
    (hmarker1 : marker.key ≠ field1.key) :
    executeMethodV1 methodIR ByteArray.empty 0 0 preStorage =
        .returned none
          (zeroTwoUInt64InitializerPostStorageV1 preStorage marker field0 field1
            storageLayout.markerValue) ∧
      InitializedZeroTwoUInt64StorageRelV1 data storageLayout binding0 binding1
        post
        (zeroTwoUInt64InitializerPostStorageV1 preStorage marker field0 field1
          storageLayout.markerValue) := by
  refine ⟨
    executeMethodV1_of_nullaryZeroTwoUInt64InitializerStaticAlignment data
      storageLayout binding0 binding1 initializerName method marker field0
        field1 methodIR preStorage halignment hmarker hfield0 hfield1 hfield10
          hmarker0 hmarker1,
    halignment.binding0Rel,
    halignment.binding1Rel,
    halignment.binding0State,
    halignment.binding1State,
    post.initialized_of_encodeLogicalStateValuesV1 data true _ hpostEncode,
    decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1 data true _ post
      hpostEncode,
    ?_, ?_, ?_
  ⟩
  · simpa [halignment.markerKey] using
      zeroTwoUInt64InitializerPostStorageV1_lookup_marker preStorage marker
        field0 field1 storageLayout.markerValue
  · simpa [halignment.field0Key] using
      zeroTwoUInt64InitializerPostStorageV1_lookup_field0 preStorage marker
        field0 field1 storageLayout.markerValue hfield10 hmarker0
  · simpa [halignment.field1Key] using
      zeroTwoUInt64InitializerPostStorageV1_lookup_field1 preStorage marker
        field0 field1 storageLayout.markerValue hmarker1

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

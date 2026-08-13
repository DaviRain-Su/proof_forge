import ProofForgeV2.Targets.Near.MethodSemanticsV1

/-!
# NEAR WATSemanticsV1

Execution semantics for the typed WAT instruction subset that the production
renderer uses for the selected nullary UInt64 view and initializer recipes.

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
  | unsupportedStorageWidth
  | unsupportedReturnWidth
  deriving BEq, Repr

/-- Machine state for the sole bounded typed-WAT subset. Registers, scratch
    memory, and storage are target-level host/Wasm state; input and attached
    deposit limbs are immutable environment observations. -/
structure ReadOnlyWATMachineV1 where
  input : ByteArray
  attachedDepositLow : UInt64
  attachedDepositHigh : UInt64
  storage : StorageObservationV1
  localCount : Nat
  locals : Nat → Option UInt64
  registers : Nat → Option ByteArray
  memory : Nat → Option ByteArray
  returnData : Option ByteArray

private def initialReadOnlyWATMachineV1
    (localCount : Nat)
    (input : ByteArray)
    (attachedDepositLow attachedDepositHigh : UInt64)
    (storage : StorageObservationV1) : ReadOnlyWATMachineV1 := {
  input
  attachedDepositLow
  attachedDepositHigh
  storage
  localCount
  locals := fun _ => none
  registers := fun _ => none
  memory := fun _ => none
  returnData := none
}

private def writeReadOnlyWATStorageV1
    (machine : ReadOnlyWATMachineV1)
    (key : String)
    (value : ByteArray) : ReadOnlyWATMachineV1 :=
  { machine with storage := writeStorageObservationV1 machine.storage key value }

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
  | .i64Add left right => do
      let (machine, leftValue) ← evalReadOnlyWATI64ExprV1 machine left
      let (machine, rightValue) ← evalReadOnlyWATI64ExprV1 machine right
      .ok (machine, UInt64.ofNat (leftValue.toNat + rightValue.toNat))
  | .i64Sub left right => do
      let (machine, leftValue) ← evalReadOnlyWATI64ExprV1 machine left
      let (machine, rightValue) ← evalReadOnlyWATI64ExprV1 machine right
      .ok (machine, UInt64.ofNat (leftValue.toNat - rightValue.toNat))
  | .i64LeU left right => do
      let (machine, leftValue) ← evalReadOnlyWATI64ExprV1 machine left
      let (machine, rightValue) ← evalReadOnlyWATI64ExprV1 machine right
      .ok (machine, if leftValue.toNat ≤ rightValue.toNat then 1 else 0)
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
  | .storageWrite field byteLen offset register =>
      if byteLen = 8 then
        match machine.memory offset with
        | none => .error .memoryMissing
        | some bytes =>
            if bytes.size = 8 then
              let oldBytes := machine.storage.lookup field.key
              let machine := setReadOnlyWATRegisterV1 machine register oldBytes
              let machine := writeReadOnlyWATStorageV1 machine field.key bytes
              .ok (machine, if oldBytes.isSome then 1 else 0)
            else
              .error .memoryWidthMismatch
      else
        .error .unsupportedStorageWidth

/-- Execute one typed instruction from the bounded WAT subset. -/
def stepReadOnlyWATInstructionV1
    (machine : ReadOnlyWATMachineV1) :
    ReadOnlyWATInstructionV1 →
      Except ReadOnlyWATErrorV1 ReadOnlyWATMachineV1
  | .input register =>
      .ok (setReadOnlyWATRegisterV1 machine register (some machine.input))
  | .attachedDeposit offset =>
      .ok (setReadOnlyWATMemoryV1
        (setReadOnlyWATMemoryV1 machine offset
          (encodeU64le machine.attachedDepositLow))
        (offset + 8) (encodeU64le machine.attachedDepositHigh))
  | .trapIfI64Ne left right => do
      let (machine, leftValue) ← evalReadOnlyWATI64ExprV1 machine left
      let (machine, rightValue) ← evalReadOnlyWATI64ExprV1 machine right
      if leftValue = rightValue then .ok machine else .error .trap
  | .trapIfI64LtU left right => do
      let (machine, leftValue) ← evalReadOnlyWATI64ExprV1 machine left
      let (machine, rightValue) ← evalReadOnlyWATI64ExprV1 machine right
      if leftValue.toNat < rightValue.toNat then .error .trap else .ok machine
  | .trapIfI64Eqz value => do
      let (machine, value) ← evalReadOnlyWATI64ExprV1 machine value
      if value = 0 then .error .trap else .ok machine
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

@[simp] private theorem setReadOnlyWATRegisterV1_storage
    (machine : ReadOnlyWATMachineV1)
    (register : Nat)
    (value : Option ByteArray) :
    (setReadOnlyWATRegisterV1 machine register value).storage =
      machine.storage := rfl

@[simp] private theorem setReadOnlyWATMemoryV1_storage
    (machine : ReadOnlyWATMachineV1)
    (offset : Nat)
    (value : ByteArray) :
    (setReadOnlyWATMemoryV1 machine offset value).storage =
      machine.storage := rfl

@[simp] private theorem setReadOnlyWATLocalV1_storage_of_ok
    (machine next : ReadOnlyWATMachineV1)
    (index : Nat)
    (value : UInt64)
    (hset : setReadOnlyWATLocalV1 machine index value = .ok next) :
    next.storage = machine.storage := by
  simp [setReadOnlyWATLocalV1] at hset
  split at hset
  · cases hset
    rfl
  · contradiction

@[simp] private theorem writeReadOnlyWATStorageV1_storage
    (machine : ReadOnlyWATMachineV1)
    (key : String)
    (value : ByteArray) :
    (writeReadOnlyWATStorageV1 machine key value).storage =
      writeStorageObservationV1 machine.storage key value := rfl

/-- Sequencing law for the sole typed-WAT runner. -/
theorem runReadOnlyWATInstructionsV1_append
    (left right : List ReadOnlyWATInstructionV1)
    (machine : ReadOnlyWATMachineV1) :
    runReadOnlyWATInstructionsV1 (left ++ right) machine = (do
      let machine ← runReadOnlyWATInstructionsV1 left machine
      runReadOnlyWATInstructionsV1 right machine) := by
  induction left generalizing machine with
  | nil => rfl
  | cons instruction remaining ih =>
      simp only [List.cons_append, runReadOnlyWATInstructionsV1]
      cases hstep : stepReadOnlyWATInstructionV1 machine instruction with
      | error error => simp [Bind.bind, Except.bind]
      | ok next => simp [ih, Bind.bind, Except.bind]

/-- Execute operation-sized typed-WAT recipes in source order. This is a proof
    view of the existing instruction runner, not another instruction step. -/
def runMethodWATRecipesV1 :
    List (Array MethodWATInstructionV1) → ReadOnlyWATMachineV1 →
      Except ReadOnlyWATErrorV1 ReadOnlyWATMachineV1
  | [], machine => .ok machine
  | recipe :: remaining, machine => do
      let machine ← runReadOnlyWATInstructionsV1 recipe.toList machine
      runMethodWATRecipesV1 remaining machine

/-- Flattening operation-sized recipes and running instructions is exactly
    recipe-by-recipe execution through the same step relation. -/
theorem runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1
    (recipes : List (Array MethodWATInstructionV1))
    (machine : ReadOnlyWATMachineV1) :
    runReadOnlyWATInstructionsV1
      (concatMethodWATRecipesV1 recipes).toList machine =
      runMethodWATRecipesV1 recipes machine := by
  induction recipes generalizing machine with
  | nil => rfl
  | cons recipe remaining ih =>
      simp [concatMethodWATRecipesV1, Array.toList_append,
        runReadOnlyWATInstructionsV1_append, runMethodWATRecipesV1, ih,
        Bind.bind, Except.bind]

/-- Observable result of the bounded typed WAT machine. -/
inductive ReadOnlyWATOutcomeV1 where
  | returned (returnData : Option ByteArray)
  | trapped (error : ReadOnlyWATErrorV1)
  deriving BEq, Repr

/-- Successful bounded typed-WAT execution includes post-storage. A trap omits
    machine state, enforcing rollback at the observation boundary. -/
inductive MethodWATExecutionOutcomeV1 where
  | returned (returnData : Option ByteArray) (postStorage : StorageObservationV1)
  | trapped (error : ReadOnlyWATErrorV1)

/-- Execute one bounded typed-WAT method body with explicit u128 deposit limbs. -/
def executeMethodWATV1
    (localCount : Nat)
    (instructions : Array MethodWATInstructionV1)
    (input : ByteArray)
    (attachedDepositLow attachedDepositHigh : UInt64)
    (storage : StorageObservationV1) : MethodWATExecutionOutcomeV1 :=
  match runReadOnlyWATInstructionsV1 instructions.toList
      (initialReadOnlyWATMachineV1 localCount input attachedDepositLow
        attachedDepositHigh storage) with
  | .ok machine => .returned machine.returnData machine.storage
  | .error error => .trapped error

/-- Historical read-only projection over the same evaluator. -/
def executeReadOnlyWATV1
    (localCount : Nat)
    (instructions : Array ReadOnlyWATInstructionV1)
    (input : ByteArray)
    (storage : StorageObservationV1) : ReadOnlyWATOutcomeV1 :=
  match executeMethodWATV1 localCount instructions input 0 0 storage with
  | .returned returnData _ => .returned returnData
  | .trapped error => .trapped error

/-- Canonical call observation derived from bounded typed-WAT execution. -/
def observeMethodWATV1
    (exportName : String)
    (localCount : Nat)
    (instructions : Array MethodWATInstructionV1)
    (input : ByteArray)
    (attachedDepositLow attachedDepositHigh : UInt64)
    (storage : StorageObservationV1) : CallObservationV1 :=
  match executeMethodWATV1 localCount instructions input attachedDepositLow
      attachedDepositHigh storage with
  | .returned returnData postStorage => {
      exportName
      input
      returnData
      failureObserved := false
      logs := #[]
      promises := #[]
      preStorage := storage
      postStorage
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
  simp [executeReadOnlyWATV1, executeMethodWATV1,
    nullaryUInt64ViewWATV1, concatMethodWATRecipesV1,
    checkEmptyInputWATV1, requireLayoutWATV1, loadUInt64StateWATV1,
    returnUInt64WATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1, hmarker, hfield,
    hfieldSize, hmarkerRoundtrip, hroundtrip, encodeU64le_size, Bind.bind,
    Except.bind]

/-- Exact execution of the typed-WAT sequence selected by production lowering
    for the two-UInt64 zero initializer. -/
theorem executeMethodWATV1_nullaryZeroTwoUInt64Initializer
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = none)
    (hfield0 : storage.lookup field0.key = none)
    (hfield1 : storage.lookup field1.key = none)
    (hfield10 : field1.key ≠ field0.key)
    (hmarker0 : marker.key ≠ field0.key)
    (hmarker1 : marker.key ≠ field1.key) :
    executeMethodWATV1 2
      (nullaryZeroTwoUInt64InitializerWATV1 registers memory marker field0
        field1 markerValue)
      ByteArray.empty 0 0 storage =
      .returned none
        (zeroTwoUInt64InitializerPostStorageV1 storage marker field0 field1
          markerValue) := by
  unfold executeMethodWATV1
  simp only [nullaryZeroTwoUInt64InitializerWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkEmptyInputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutAbsentWATV1,
    zeroUInt64StateWATV1, uint64LiteralWATV1, storeUInt64StateWATV1,
    setLayoutWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1,
    writeReadOnlyWATStorageV1, writeStorageObservationV1,
    zeroTwoUInt64InitializerPostStorageV1, hmarker, hfield0, hfield1,
    hfield10, hmarker0, hmarker1, encodeU64le_size,
    leBytesToNatV1_encodeU64le, Bind.bind, Except.bind]

/-- Nonempty ABI input traps in typed WAT before deposit or storage is
    inspected. -/
theorem executeMethodWATV1_nullaryZeroTwoUInt64Initializer_nonempty_input
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (input : ByteArray)
    (storage : StorageObservationV1)
    (hinput : UInt64.ofNat input.size ≠ 0) :
    executeMethodWATV1 2
      (nullaryZeroTwoUInt64InitializerWATV1 registers memory marker field0
        field1 markerValue)
      input 0 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [nullaryZeroTwoUInt64InitializerWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkEmptyInputWATV1,
    runReadOnlyWATInstructionsV1, initialReadOnlyWATMachineV1,
    stepReadOnlyWATInstructionV1, evalReadOnlyWATI64ExprV1,
    setReadOnlyWATRegisterV1, hinput, Bind.bind, Except.bind]

/-- Existing layout storage rejects the typed-WAT initializer before any
    storage write can commit. -/
theorem executeMethodWATV1_nullaryZeroTwoUInt64Initializer_double_init
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (markerBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some markerBytes) :
    executeMethodWATV1 2
      (nullaryZeroTwoUInt64InitializerWATV1 registers memory marker field0
        field1 markerValue)
      ByteArray.empty 0 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [nullaryZeroTwoUInt64InitializerWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkEmptyInputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutAbsentWATV1,
    runReadOnlyWATInstructionsV1, initialReadOnlyWATMachineV1,
    stepReadOnlyWATInstructionV1, evalReadOnlyWATI64ExprV1,
    setReadOnlyWATRegisterV1, setReadOnlyWATMemoryV1, hmarker,
    encodeU64le_size, leBytesToNatV1_encodeU64le, Bind.bind, Except.bind]

/-- A nonzero low attached-deposit limb traps in typed WAT before storage is
    inspected or changed. -/
theorem executeMethodWATV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue depositLow : UInt64)
    (storage : StorageObservationV1)
    (hdeposit : depositLow ≠ 0) :
    executeMethodWATV1 2
      (nullaryZeroTwoUInt64InitializerWATV1 registers memory marker field0
        field1 markerValue)
      ByteArray.empty depositLow 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [nullaryZeroTwoUInt64InitializerWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkEmptyInputWATV1,
    requireZeroAttachedDepositWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, hdeposit, encodeU64le_size,
    leBytesToNatV1_encodeU64le, Bind.bind, Except.bind]

/-- A nonzero high attached-deposit limb traps at the second typed-WAT u128
    deposit check before storage is inspected or changed. -/
theorem executeMethodWATV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit_high
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue depositHigh : UInt64)
    (storage : StorageObservationV1)
    (hdeposit : depositHigh ≠ 0) :
    executeMethodWATV1 2
      (nullaryZeroTwoUInt64InitializerWATV1 registers memory marker field0
        field1 markerValue)
      ByteArray.empty 0 depositHigh storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [nullaryZeroTwoUInt64InitializerWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkEmptyInputWATV1,
    requireZeroAttachedDepositWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, hdeposit, encodeU64le_size,
    leBytesToNatV1_encodeU64le, Bind.bind, Except.bind]

/-! ## Selected unary checked-add two-UInt64 entry execution -/

/-- Exact typed-WAT execution for the selected production deposit recipe.
    Checked Wasm addition and its unsigned carry guard update both UInt64 rows
    and return the second updated row. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some (encodeU64le before1))
    (hfield10 : field1.key ≠ field0.key)
    (hinputValue : memory.inputOffset ≠ memory.valueOffset)
    (hinputDepositLow : memory.inputOffset ≠ memory.depositOffset)
    (hinputDepositHigh : memory.inputOffset ≠ memory.depositOffset + 8)
    (hadd0 : before0.toNat + amount.toNat < 2 ^ 64)
    (hadd1 : before1.toNat + amount.toNat < 2 ^ 64) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage =
      .returned (some (checkedAddUInt64BytesV1 before1 amount))
        (unaryAddTwoUInt64DepositPostStorageV1 storage field0 field1 before0
          before1 amount) := by
  have hsumValue0 :
      UInt64.ofNat (before0.toNat + amount.toNat) = before0 + amount := by
    rw [UInt64.ofNat_add, UInt64.ofNat_toNat, UInt64.ofNat_toNat]
  have hsumModValue0 :
      UInt64.ofNat ((before0.toNat + amount.toNat) % (2 ^ 64)) =
        before0 + amount := by
    rw [Nat.mod_eq_of_lt hadd0, hsumValue0]
  have hsum0 :
      ¬ (UInt64.ofNat (before0.toNat + amount.toNat)).toNat < before0.toNat := by
    rw [hsumValue0, UInt64.toNat_add, Nat.mod_eq_of_lt hadd0]
    omega
  have hcarry0 :
      ¬ (before0.toNat + amount.toNat) % (2 ^ 64) < before0.toNat := by
    rw [Nat.mod_eq_of_lt hadd0]
    omega
  have hsumValue1 :
      UInt64.ofNat (before1.toNat + amount.toNat) = before1 + amount := by
    rw [UInt64.ofNat_add, UInt64.ofNat_toNat, UInt64.ofNat_toNat]
  have hsumModValue1 :
      UInt64.ofNat ((before1.toNat + amount.toNat) % (2 ^ 64)) =
        before1 + amount := by
    rw [Nat.mod_eq_of_lt hadd1, hsumValue1]
  have hsum1 :
      ¬ (UInt64.ofNat (before1.toNat + amount.toNat)).toNat < before1.toNat := by
    rw [hsumValue1, UInt64.toNat_add, Nat.mod_eq_of_lt hadd1]
    omega
  have hcarry1 :
      ¬ (before1.toNat + amount.toNat) % (2 ^ 64) < before1.toNat := by
    rw [Nat.mod_eq_of_lt hadd1]
    omega
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, loadUInt64ParamWATV1, checkedAddUInt64WATV1,
    storeUInt64StateWATV1, returnUInt64WATV1,
    runReadOnlyWATInstructionsV1, initialReadOnlyWATMachineV1,
    stepReadOnlyWATInstructionV1, evalReadOnlyWATI64ExprV1,
    setReadOnlyWATRegisterV1, setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1,
    writeReadOnlyWATStorageV1, writeStorageObservationV1,
    checkedAddUInt64BytesV1, unaryAddTwoUInt64DepositPostStorageV1,
    hmarker, hfield0, hfield1, hfield10, hinputValue,
    hinputDepositLow, hinputDepositHigh, hsumValue0, hsumValue1,
    hsumModValue0, hsumModValue1, hsum0, hsum1, hcarry0, hcarry1,
    encodeU64le_size, leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat,
    hadd0, hadd1, Bind.bind, Except.bind]

/-- Wrong ABI width traps in typed WAT before deposit or storage inspection. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_wrong_input
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (input : ByteArray)
    (storage : StorageObservationV1)
    (hinput : UInt64.ofNat input.size ≠ 8) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      input 0 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    runReadOnlyWATInstructionsV1, initialReadOnlyWATMachineV1,
    stepReadOnlyWATInstructionV1, evalReadOnlyWATI64ExprV1,
    setReadOnlyWATRegisterV1, hinput, Bind.bind, Except.bind]

/-- A nonzero low attached-deposit limb traps before layout or state access. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_nonzero_deposit
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue depositLow amount : UInt64)
    (storage : StorageObservationV1)
    (hdeposit : depositLow ≠ 0) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) depositLow 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, hdeposit, encodeU64le_size,
    leBytesToNatV1_encodeU64le, Bind.bind, Except.bind]

/-- A nonzero high attached-deposit limb traps at the second u128 check. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_nonzero_deposit_high
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue depositHigh amount : UInt64)
    (storage : StorageObservationV1)
    (hdeposit : depositHigh ≠ 0) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 depositHigh storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, hdeposit, encodeU64le_size,
    leBytesToNatV1_encodeU64le, Bind.bind, Except.bind]

/-- A missing marker traps before either target state row is inspected. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_marker_missing
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = none) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    runReadOnlyWATInstructionsV1, initialReadOnlyWATMachineV1,
    stepReadOnlyWATInstructionV1, evalReadOnlyWATI64ExprV1,
    setReadOnlyWATRegisterV1, setReadOnlyWATMemoryV1, hmarker,
    encodeU64le_size, leBytesToNatV1_encodeU64le, Bind.bind, Except.bind]

/-- A noncanonical marker value traps before either state row is touched. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_marker_mismatch
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue amount : UInt64)
    (markerBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some markerBytes)
    (hmarkerSize : markerBytes.size = 8)
    (hmarkerValue : markerBytes ≠ encodeU64le markerValue) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  have hdecoded :
      UInt64.ofNat (leBytesToNatV1 markerBytes) ≠ markerValue := by
    intro heq
    apply hmarkerValue
    calc
      markerBytes = encodeU64le (UInt64.ofNat (leBytesToNatV1 markerBytes)) :=
        (encodeU64le_uint64OfLeBytesToNatV1_of_size markerBytes
          hmarkerSize).symm
      _ = encodeU64le markerValue := congrArg encodeU64le heq
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    runReadOnlyWATInstructionsV1, initialReadOnlyWATMachineV1,
    stepReadOnlyWATInstructionV1, evalReadOnlyWATI64ExprV1,
    setReadOnlyWATRegisterV1, setReadOnlyWATMemoryV1, hmarker, hmarkerSize,
    hdecoded, encodeU64le_size, leBytesToNatV1_encodeU64le, Bind.bind,
    Except.bind]

/-- A marker row with non-UInt64 width traps before state access. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_marker_wrong_width
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue amount : UInt64)
    (markerBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some markerBytes)
    (hmarkerSize : UInt64.ofNat markerBytes.size ≠ 8) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    runReadOnlyWATInstructionsV1, initialReadOnlyWATMachineV1,
    stepReadOnlyWATInstructionV1, evalReadOnlyWATI64ExprV1,
    setReadOnlyWATRegisterV1, setReadOnlyWATMemoryV1, hmarker, hmarkerSize,
    encodeU64le_size, leBytesToNatV1_encodeU64le, Bind.bind, Except.bind]

/-- A missing first state row traps before any target storage write. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_field0_missing
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = none) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, hmarker, hfield0, encodeU64le_size,
    leBytesToNatV1_encodeU64le, Bind.bind, Except.bind]

/-- A malformed first state row traps before any target storage write. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_field0_wrong_width
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue amount : UInt64)
    (fieldBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some fieldBytes)
    (hfield0Size : UInt64.ofNat fieldBytes.size ≠ 8) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, hmarker, hfield0, hfield0Size,
    encodeU64le_size, leBytesToNatV1_encodeU64le, Bind.bind, Except.bind]

/-- Overflow in the first typed-WAT checked add traps before any storage write. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_first_overflow
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hinputValue : memory.inputOffset ≠ memory.valueOffset)
    (hinputDepositLow : memory.inputOffset ≠ memory.depositOffset)
    (hinputDepositHigh : memory.inputOffset ≠ memory.depositOffset + 8)
    (hoverflow : ¬ before0.toNat + amount.toNat < 2 ^ 64) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  have hsumGe : 2 ^ 64 ≤ before0.toNat + amount.toNat := by omega
  have hsumSubLt :
      before0.toNat + amount.toNat - 2 ^ 64 < 2 ^ 64 := by
    have hbefore := before0.toNat_lt
    have hamount := amount.toNat_lt
    omega
  have hcarry :
      (before0.toNat + amount.toNat) % (2 ^ 64) < before0.toNat := by
    rw [Nat.mod_eq_sub_mod hsumGe, Nat.mod_eq_of_lt hsumSubLt]
    have hamount := amount.toNat_lt
    omega
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, loadUInt64ParamWATV1, checkedAddUInt64WATV1,
    runReadOnlyWATInstructionsV1, initialReadOnlyWATMachineV1,
    stepReadOnlyWATInstructionV1, evalReadOnlyWATI64ExprV1,
    setReadOnlyWATRegisterV1, setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1,
    hmarker, hfield0, hinputValue, hinputDepositLow, hinputDepositHigh,
    hcarry, encodeU64le_size, leBytesToNatV1_encodeU64le,
    UInt64.ofNat_toNat, Bind.bind, Except.bind]

/-- A missing second row traps after the first typed-WAT write; the failure
    outcome omits machine state, so the observable call rolls that write back. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_field1_missing
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = none)
    (hfield10 : field1.key ≠ field0.key)
    (hinputValue : memory.inputOffset ≠ memory.valueOffset)
    (hinputDepositLow : memory.inputOffset ≠ memory.depositOffset)
    (hinputDepositHigh : memory.inputOffset ≠ memory.depositOffset + 8)
    (hadd0 : before0.toNat + amount.toNat < 2 ^ 64) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  have hsumValue0 :
      UInt64.ofNat (before0.toNat + amount.toNat) = before0 + amount := by
    rw [UInt64.ofNat_add, UInt64.ofNat_toNat, UInt64.ofNat_toNat]
  have hcarry0 :
      ¬ (before0.toNat + amount.toNat) % (2 ^ 64) < before0.toNat := by
    rw [Nat.mod_eq_of_lt hadd0]
    omega
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, loadUInt64ParamWATV1, checkedAddUInt64WATV1,
    storeUInt64StateWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1,
    writeReadOnlyWATStorageV1, writeStorageObservationV1,
    hmarker, hfield0, hfield1, hfield10, hinputValue,
    hinputDepositLow, hinputDepositHigh, hsumValue0, hcarry0,
    encodeU64le_size, leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat,
    Bind.bind, Except.bind]

/-- A malformed second row also traps after the first typed-WAT write, with the
    same transactional rollback at the failure observation boundary. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_field1_wrong_width
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 amount : UInt64)
    (field1Bytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some field1Bytes)
    (hfield1Size : UInt64.ofNat field1Bytes.size ≠ 8)
    (hfield10 : field1.key ≠ field0.key)
    (hinputValue : memory.inputOffset ≠ memory.valueOffset)
    (hinputDepositLow : memory.inputOffset ≠ memory.depositOffset)
    (hinputDepositHigh : memory.inputOffset ≠ memory.depositOffset + 8)
    (hadd0 : before0.toNat + amount.toNat < 2 ^ 64) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  have hsumValue0 :
      UInt64.ofNat (before0.toNat + amount.toNat) = before0 + amount := by
    rw [UInt64.ofNat_add, UInt64.ofNat_toNat, UInt64.ofNat_toNat]
  have hcarry0 :
      ¬ (before0.toNat + amount.toNat) % (2 ^ 64) < before0.toNat := by
    rw [Nat.mod_eq_of_lt hadd0]
    omega
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, loadUInt64ParamWATV1, checkedAddUInt64WATV1,
    storeUInt64StateWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1,
    writeReadOnlyWATStorageV1, writeStorageObservationV1,
    hmarker, hfield0, hfield1, hfield1Size, hfield10, hinputValue,
    hinputDepositLow, hinputDepositHigh, hsumValue0, hcarry0,
    encodeU64le_size, leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat,
    Bind.bind, Except.bind]

/-- Overflow in the second typed-WAT add traps after the first write. No
    post-storage escapes the failure outcome, ruling out partial vault updates. -/
theorem executeMethodWATV1_unaryAddTwoUInt64Deposit_second_overflow
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some (encodeU64le before1))
    (hfield10 : field1.key ≠ field0.key)
    (hinputValue : memory.inputOffset ≠ memory.valueOffset)
    (hinputDepositLow : memory.inputOffset ≠ memory.depositOffset)
    (hinputDepositHigh : memory.inputOffset ≠ memory.depositOffset + 8)
    (hadd0 : before0.toNat + amount.toNat < 2 ^ 64)
    (hoverflow1 : ¬ before1.toNat + amount.toNat < 2 ^ 64) :
    executeMethodWATV1 7
      (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  have hsumValue0 :
      UInt64.ofNat (before0.toNat + amount.toNat) = before0 + amount := by
    rw [UInt64.ofNat_add, UInt64.ofNat_toNat, UInt64.ofNat_toNat]
  have hcarry0 :
      ¬ (before0.toNat + amount.toNat) % (2 ^ 64) < before0.toNat := by
    rw [Nat.mod_eq_of_lt hadd0]
    omega
  have hsumGe1 : 2 ^ 64 ≤ before1.toNat + amount.toNat := by omega
  have hsumSubLt1 :
      before1.toNat + amount.toNat - 2 ^ 64 < 2 ^ 64 := by
    have hbefore1 := before1.toNat_lt
    have hamount := amount.toNat_lt
    omega
  have hcarry1 :
      (before1.toNat + amount.toNat) % (2 ^ 64) < before1.toNat := by
    rw [Nat.mod_eq_sub_mod hsumGe1, Nat.mod_eq_of_lt hsumSubLt1]
    have hamount := amount.toNat_lt
    omega
  unfold executeMethodWATV1
  simp only [unaryAddTwoUInt64DepositWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, loadUInt64ParamWATV1, checkedAddUInt64WATV1,
    storeUInt64StateWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1,
    writeReadOnlyWATStorageV1, writeStorageObservationV1,
    hmarker, hfield0, hfield1, hfield10, hinputValue,
    hinputDepositLow, hinputDepositHigh, hsumValue0, hcarry0, hcarry1,
    encodeU64le_size, leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat,
    Bind.bind, Except.bind]

/-! ## Selected guarded checked-sub two-UInt64 entry execution -/

/-- Exact typed-WAT execution for the selected production withdraw recipe.
    Both unsigned guards complete before storage writes, the checked
    subtractions update both rows, and Unit falls through with no return data. -/
theorem executeMethodWATV1_guardedSubTwoUInt64Withdraw
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some (encodeU64le before1))
    (hfield10 : field1.key ≠ field0.key)
    (hinputValue : memory.inputOffset ≠ memory.valueOffset)
    (hinputDepositLow : memory.inputOffset ≠ memory.depositOffset)
    (hinputDepositHigh : memory.inputOffset ≠ memory.depositOffset + 8)
    (hguard0 : amount.toNat ≤ before0.toNat)
    (hguard1 : amount.toNat ≤ before1.toNat) :
    executeMethodWATV1 12
      (guardedSubTwoUInt64WithdrawWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage =
      .returned none
        (guardedSubTwoUInt64WithdrawPostStorageV1 storage field0 field1 before0
          before1 amount) := by
  have hnotUnderflow0 : ¬ before0.toNat < amount.toNat := by omega
  have hnotUnderflow1 : ¬ before1.toNat < amount.toNat := by omega
  unfold executeMethodWATV1
  simp only [guardedSubTwoUInt64WithdrawWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, loadUInt64ParamWATV1, compareUInt64LeWATV1,
    assertUInt64BoolWATV1, checkedSubUInt64WATV1,
    storeUInt64StateWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1,
    writeReadOnlyWATStorageV1, writeStorageObservationV1,
    checkedSubUInt64BytesV1, guardedSubTwoUInt64WithdrawPostStorageV1,
    hmarker, hfield0, hfield1, hfield10, hinputValue,
    hinputDepositLow, hinputDepositHigh, hguard0, hguard1,
    hnotUnderflow0, hnotUnderflow1, encodeU64le_size,
    leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat, Bind.bind, Except.bind]

/-- A false first withdraw guard traps in typed WAT before either storage
    write recipe is reached. -/
theorem executeMethodWATV1_guardedSubTwoUInt64Withdraw_first_guard_failure
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hinputValue : memory.inputOffset ≠ memory.valueOffset)
    (hinputDepositLow : memory.inputOffset ≠ memory.depositOffset)
    (hinputDepositHigh : memory.inputOffset ≠ memory.depositOffset + 8)
    (hguard0 : ¬ amount.toNat ≤ before0.toNat) :
    executeMethodWATV1 12
      (guardedSubTwoUInt64WithdrawWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [guardedSubTwoUInt64WithdrawWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, loadUInt64ParamWATV1, compareUInt64LeWATV1,
    assertUInt64BoolWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1,
    hmarker, hfield0, hinputValue, hinputDepositLow, hinputDepositHigh,
    hguard0, encodeU64le_size, leBytesToNatV1_encodeU64le,
    UInt64.ofNat_toNat, Bind.bind, Except.bind]

/-- A false second withdraw guard also traps before either typed-WAT storage
    write recipe is reached. -/
theorem executeMethodWATV1_guardedSubTwoUInt64Withdraw_second_guard_failure
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some (encodeU64le before1))
    (hinputValue : memory.inputOffset ≠ memory.valueOffset)
    (hinputDepositLow : memory.inputOffset ≠ memory.depositOffset)
    (hinputDepositHigh : memory.inputOffset ≠ memory.depositOffset + 8)
    (hguard0 : amount.toNat ≤ before0.toNat)
    (hguard1 : ¬ amount.toNat ≤ before1.toNat) :
    executeMethodWATV1 12
      (guardedSubTwoUInt64WithdrawWATV1 registers memory marker field0 field1
        markerValue)
      (encodeU64le amount) 0 0 storage = .trapped .trap := by
  unfold executeMethodWATV1
  simp only [guardedSubTwoUInt64WithdrawWATV1]
  rw [runReadOnlyWATInstructionsV1_concatMethodWATRecipesV1]
  simp [runMethodWATRecipesV1, checkUInt64InputWATV1,
    requireZeroAttachedDepositWATV1, requireLayoutWATV1,
    loadUInt64StateWATV1, loadUInt64ParamWATV1, compareUInt64LeWATV1,
    assertUInt64BoolWATV1, runReadOnlyWATInstructionsV1,
    initialReadOnlyWATMachineV1, stepReadOnlyWATInstructionV1,
    evalReadOnlyWATI64ExprV1, setReadOnlyWATRegisterV1,
    setReadOnlyWATMemoryV1, setReadOnlyWATLocalV1,
    hmarker, hfield0, hfield1, hinputValue, hinputDepositLow,
    hinputDepositHigh, hguard0, hguard1, encodeU64le_size,
    leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat, Bind.bind, Except.bind]

/-- MethodIR and its exact production typed-WAT lowering agree on successful
    deposit return bytes and post-storage. -/
theorem methodIR_and_WAT_unaryAddTwoUInt64Deposit_return_same
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some (encodeU64le before1))
    (hfield10 : field1.key ≠ field0.key)
    (hinputValue : memory.inputOffset ≠ memory.valueOffset)
    (hinputDepositLow : memory.inputOffset ≠ memory.depositOffset)
    (hinputDepositHigh : memory.inputOffset ≠ memory.depositOffset + 8)
    (hadd0 : before0.toNat + amount.toNat < 2 ^ 64)
    (hadd1 : before1.toNat + amount.toNat < 2 ^ 64) :
    executeMethodV1 {
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
        .checkInputLen 8, .requireZeroAttachedDeposit,
        .requireLayout marker markerValue, .loadState 0 field0,
        .loadParam 1 0, .checkedAdd 2 0 1, .storeState field0 2,
        .loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4,
        .storeState field1 5, .loadState 6 field1, .setReturnData 8 6
      ]
    } (encodeU64le amount) 0 0 storage =
        .returned (some (checkedAddUInt64BytesV1 before1 amount))
          (unaryAddTwoUInt64DepositPostStorageV1 storage field0 field1 before0
            before1 amount) ∧
      executeMethodWATV1 7
        (unaryAddTwoUInt64DepositWATV1 registers memory marker field0 field1
          markerValue)
        (encodeU64le amount) 0 0 storage =
          .returned (some (checkedAddUInt64BytesV1 before1 amount))
            (unaryAddTwoUInt64DepositPostStorageV1 storage field0 field1 before0
              before1 amount) := by
  exact ⟨
    executeMethodV1_unaryAddTwoUInt64Deposit entryName parameterName
      parameterSourceId marker field0 field1 markerValue before0 before1 amount
        storage hmarker hfield0 hfield1 hfield10 hadd0 hadd1,
    executeMethodWATV1_unaryAddTwoUInt64Deposit registers memory marker field0
      field1 markerValue before0 before1 amount storage hmarker hfield0 hfield1
        hfield10 hinputValue hinputDepositLow hinputDepositHigh hadd0 hadd1
  ⟩

/-- MethodIR and its exact production typed-WAT lowering agree on successful
    withdraw return data and post-storage. -/
theorem methodIR_and_WAT_guardedSubTwoUInt64Withdraw_return_same
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (registers : RegisterLayout)
    (memory : MemoryLayout)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some (encodeU64le before1))
    (hfield10 : field1.key ≠ field0.key)
    (hinputValue : memory.inputOffset ≠ memory.valueOffset)
    (hinputDepositLow : memory.inputOffset ≠ memory.depositOffset)
    (hinputDepositHigh : memory.inputOffset ≠ memory.depositOffset + 8)
    (hguard0 : amount.toNat ≤ before0.toNat)
    (hguard1 : amount.toNat ≤ before1.toNat) :
    executeMethodV1 {
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
        .checkInputLen 8, .requireZeroAttachedDeposit,
        .requireLayout marker markerValue, .loadParam 0 0,
        .loadState 1 field0, .compare 2 0 1 .le, .assert 2,
        .loadParam 3 0, .loadState 4 field1, .compare 5 3 4 .le,
        .assert 5, .loadState 6 field0, .loadParam 7 0,
        .checkedSub 8 6 7, .storeState field0 8, .loadState 9 field1,
        .loadParam 10 0, .checkedSub 11 9 10, .storeState field1 11
      ]
    } (encodeU64le amount) 0 0 storage =
        .returned none
          (guardedSubTwoUInt64WithdrawPostStorageV1 storage field0 field1
            before0 before1 amount) ∧
      executeMethodWATV1 12
        (guardedSubTwoUInt64WithdrawWATV1 registers memory marker field0 field1
          markerValue)
        (encodeU64le amount) 0 0 storage =
          .returned none
            (guardedSubTwoUInt64WithdrawPostStorageV1 storage field0 field1
              before0 before1 amount) := by
  exact ⟨
    executeMethodV1_guardedSubTwoUInt64Withdraw entryName parameterName
      parameterSourceId marker field0 field1 markerValue before0 before1 amount
        storage hmarker hfield0 hfield1 hfield10 hguard0 hguard1,
    executeMethodWATV1_guardedSubTwoUInt64Withdraw registers memory marker
      field0 field1 markerValue before0 before1 amount storage hmarker hfield0
        hfield1 hfield10 hinputValue hinputDepositLow hinputDepositHigh hguard0
        hguard1
  ⟩

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

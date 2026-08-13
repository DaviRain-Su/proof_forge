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
  | arithmeticOverflow
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

private def setReadOnlyTempValueV1
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64) : ReadOnlyMethodMachineV1 :=
  { machine with
    temps := fun index => if index = destination then some value else machine.temps index
  }

private def writeReadOnlyTempV1
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64) : Except ReadOnlyMethodErrorV1 ReadOnlyMethodMachineV1 :=
  if destination < machine.tempCount then
    .ok (setReadOnlyTempValueV1 machine destination value)
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

private def setReadOnlyMethodReturnDataV1
    (machine : ReadOnlyMethodMachineV1)
    (returnData : Option ByteArray) : ReadOnlyMethodMachineV1 :=
  { machine with returnData }

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
  | .loadParam destination inputOffset =>
      if inputOffset + 8 ≤ machine.input.size then
        let bytes := machine.input.extract inputOffset (inputOffset + 8)
        if bytes.size = 8 then
          writeReadOnlyTempV1 machine destination
            (UInt64.ofNat (leBytesToNatV1 bytes))
        else
          .error .inputLengthMismatch
      else
        .error .inputLengthMismatch
  | .loadState destination field =>
      match machine.storage.lookup field.key with
      | none => .error .storageMissing
      | some bytes =>
          if bytes.size = 8 then
            writeReadOnlyTempV1 machine destination
              (UInt64.ofNat (leBytesToNatV1 bytes))
          else
            .error .storageWidthMismatch
  | .checkedAdd destination lhs rhs =>
      match readReadOnlyTempV1 machine lhs, readReadOnlyTempV1 machine rhs with
      | .ok left, .ok right =>
          let sum := left.toNat + right.toNat
          if sum < 2 ^ 64 then
            writeReadOnlyTempV1 machine destination (UInt64.ofNat sum)
          else
            .error .arithmeticOverflow
      | .error error, _ => .error error
      | _, .error error => .error error
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
        | .ok value =>
            .ok (setReadOnlyMethodReturnDataV1 machine (some (encodeU64le value)))
        | .error error => .error error
      else
        .error .unsupportedOperation
  | _ => .error .unsupportedOperation

@[simp] private theorem setReadOnlyTempValueV1_tempCount
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64) :
    (setReadOnlyTempValueV1 machine destination value).tempCount =
      machine.tempCount := rfl

@[simp] private theorem setReadOnlyTempValueV1_input
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64) :
    (setReadOnlyTempValueV1 machine destination value).input =
      machine.input := rfl

@[simp] private theorem setReadOnlyTempValueV1_attachedDepositLow
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64) :
    (setReadOnlyTempValueV1 machine destination value).attachedDepositLow =
      machine.attachedDepositLow := rfl

@[simp] private theorem setReadOnlyTempValueV1_attachedDepositHigh
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64) :
    (setReadOnlyTempValueV1 machine destination value).attachedDepositHigh =
      machine.attachedDepositHigh := rfl

@[simp] private theorem setReadOnlyTempValueV1_storage
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64) :
    (setReadOnlyTempValueV1 machine destination value).storage =
      machine.storage := rfl

@[simp] private theorem setReadOnlyTempValueV1_returnData
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64) :
    (setReadOnlyTempValueV1 machine destination value).returnData =
      machine.returnData := rfl

@[simp] private theorem writeReadOnlyMethodStorageV1_tempCount
    (machine : ReadOnlyMethodMachineV1)
    (key : String)
    (value : ByteArray) :
    (writeReadOnlyMethodStorageV1 machine key value).tempCount =
      machine.tempCount := rfl

@[simp] private theorem writeReadOnlyMethodStorageV1_input
    (machine : ReadOnlyMethodMachineV1)
    (key : String)
    (value : ByteArray) :
    (writeReadOnlyMethodStorageV1 machine key value).input = machine.input := rfl

@[simp] private theorem writeReadOnlyMethodStorageV1_attachedDepositLow
    (machine : ReadOnlyMethodMachineV1)
    (key : String)
    (value : ByteArray) :
    (writeReadOnlyMethodStorageV1 machine key value).attachedDepositLow =
      machine.attachedDepositLow := rfl

@[simp] private theorem writeReadOnlyMethodStorageV1_attachedDepositHigh
    (machine : ReadOnlyMethodMachineV1)
    (key : String)
    (value : ByteArray) :
    (writeReadOnlyMethodStorageV1 machine key value).attachedDepositHigh =
      machine.attachedDepositHigh := rfl

@[simp] private theorem writeReadOnlyMethodStorageV1_storage
    (machine : ReadOnlyMethodMachineV1)
    (key : String)
    (value : ByteArray) :
    (writeReadOnlyMethodStorageV1 machine key value).storage =
      writeStorageObservationV1 machine.storage key value := rfl

@[simp] private theorem writeReadOnlyMethodStorageV1_temps
    (machine : ReadOnlyMethodMachineV1)
    (key : String)
    (value : ByteArray) :
    (writeReadOnlyMethodStorageV1 machine key value).temps = machine.temps := rfl

@[simp] private theorem writeReadOnlyMethodStorageV1_returnData
    (machine : ReadOnlyMethodMachineV1)
    (key : String)
    (value : ByteArray) :
    (writeReadOnlyMethodStorageV1 machine key value).returnData =
      machine.returnData := rfl

@[simp] private theorem setReadOnlyMethodReturnDataV1_storage
    (machine : ReadOnlyMethodMachineV1)
    (returnData : Option ByteArray) :
    (setReadOnlyMethodReturnDataV1 machine returnData).storage =
      machine.storage := rfl

@[simp] private theorem setReadOnlyMethodReturnDataV1_returnData
    (machine : ReadOnlyMethodMachineV1)
    (returnData : Option ByteArray) :
    (setReadOnlyMethodReturnDataV1 machine returnData).returnData =
      returnData := rfl

@[simp] private theorem readReadOnlyTempV1_set_self
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64)
    (hbound : destination < machine.tempCount) :
    readReadOnlyTempV1 (setReadOnlyTempValueV1 machine destination value)
      destination = .ok value := by
  simp [readReadOnlyTempV1, setReadOnlyTempValueV1, hbound]

@[simp] private theorem readReadOnlyTempV1_set_other
    (machine : ReadOnlyMethodMachineV1)
    (destination source : Nat)
    (value : UInt64)
    (hne : source ≠ destination) :
    readReadOnlyTempV1 (setReadOnlyTempValueV1 machine destination value)
      source = readReadOnlyTempV1 machine source := by
  simp [readReadOnlyTempV1, setReadOnlyTempValueV1, hne]

private theorem stepReadOnlyMethodOperationV1_checkInputLen
    (machine : ReadOnlyMethodMachineV1)
    (expected : Nat)
    (hsize : machine.input.size = expected) :
    stepReadOnlyMethodOperationV1 machine (.checkInputLen expected) =
      .ok machine := by
  simp [stepReadOnlyMethodOperationV1, hsize]

private theorem stepReadOnlyMethodOperationV1_requireZeroAttachedDeposit
    (machine : ReadOnlyMethodMachineV1)
    (hlow : machine.attachedDepositLow = 0)
    (hhigh : machine.attachedDepositHigh = 0) :
    stepReadOnlyMethodOperationV1 machine .requireZeroAttachedDeposit =
      .ok machine := by
  simp [stepReadOnlyMethodOperationV1, hlow, hhigh]

private theorem stepReadOnlyMethodOperationV1_requireLayout
    (machine : ReadOnlyMethodMachineV1)
    (marker : KeyRegion)
    (markerValue : UInt64)
    (hmarker :
      machine.storage.lookup marker.key = some (encodeU64le markerValue)) :
    stepReadOnlyMethodOperationV1 machine (.requireLayout marker markerValue) =
      .ok machine := by
  simp [stepReadOnlyMethodOperationV1, hmarker, encodeU64le_size]

private theorem stepReadOnlyMethodOperationV1_loadState_encode
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (field : KeyRegion)
    (value : UInt64)
    (hfield : machine.storage.lookup field.key = some (encodeU64le value))
    (hbound : destination < machine.tempCount) :
    stepReadOnlyMethodOperationV1 machine (.loadState destination field) =
      .ok (setReadOnlyTempValueV1 machine destination value) := by
  simp [stepReadOnlyMethodOperationV1, writeReadOnlyTempV1, hfield, hbound,
    encodeU64le_size, leBytesToNatV1_encodeU64le, UInt64.ofNat_toNat]

private theorem stepReadOnlyMethodOperationV1_loadParam_zero_encode
    (machine : ReadOnlyMethodMachineV1)
    (destination : Nat)
    (value : UInt64)
    (hinput : machine.input = encodeU64le value)
    (hbound : destination < machine.tempCount) :
    stepReadOnlyMethodOperationV1 machine (.loadParam destination 0) =
      .ok (setReadOnlyTempValueV1 machine destination value) := by
  have hextract : (encodeU64le value).extract 0 8 = encodeU64le value := by
    simpa [encodeU64le_size] using
      (ByteArray.extract_zero_size (b := encodeU64le value))
  simp [stepReadOnlyMethodOperationV1, writeReadOnlyTempV1, hinput, hbound,
    hextract, encodeU64le_size, leBytesToNatV1_encodeU64le,
    UInt64.ofNat_toNat]

private theorem stepReadOnlyMethodOperationV1_checkedAdd
    (machine : ReadOnlyMethodMachineV1)
    (destination lhs rhs : Nat)
    (left right : UInt64)
    (hleft : readReadOnlyTempV1 machine lhs = .ok left)
    (hright : readReadOnlyTempV1 machine rhs = .ok right)
    (hadd : left.toNat + right.toNat < 2 ^ 64)
    (hbound : destination < machine.tempCount) :
    stepReadOnlyMethodOperationV1 machine (.checkedAdd destination lhs rhs) =
      .ok (setReadOnlyTempValueV1 machine destination
        (UInt64.ofNat (left.toNat + right.toNat))) := by
  simp [stepReadOnlyMethodOperationV1, hleft, hright, hadd,
    writeReadOnlyTempV1, hbound]

private theorem stepReadOnlyMethodOperationV1_checkedAdd_overflow
    (machine : ReadOnlyMethodMachineV1)
    (destination lhs rhs : Nat)
    (left right : UInt64)
    (hleft : readReadOnlyTempV1 machine lhs = .ok left)
    (hright : readReadOnlyTempV1 machine rhs = .ok right)
    (hoverflow : ¬ left.toNat + right.toNat < 2 ^ 64) :
    stepReadOnlyMethodOperationV1 machine (.checkedAdd destination lhs rhs) =
      .error .arithmeticOverflow := by
  simp [stepReadOnlyMethodOperationV1, hleft, hright, hoverflow]

private theorem stepReadOnlyMethodOperationV1_storeState_encode
    (machine : ReadOnlyMethodMachineV1)
    (field : KeyRegion)
    (source : Nat)
    (oldValue value : UInt64)
    (hfield : machine.storage.lookup field.key = some (encodeU64le oldValue))
    (hsource : readReadOnlyTempV1 machine source = .ok value) :
    stepReadOnlyMethodOperationV1 machine (.storeState field source) =
      .ok (writeReadOnlyMethodStorageV1 machine field.key
        (encodeU64le value)) := by
  simp [stepReadOnlyMethodOperationV1, hfield, hsource, encodeU64le_size]

private theorem stepReadOnlyMethodOperationV1_setReturnData_encode
    (machine : ReadOnlyMethodMachineV1)
    (source : Nat)
    (value : UInt64)
    (hsource : readReadOnlyTempV1 machine source = .ok value) :
    stepReadOnlyMethodOperationV1 machine (.setReturnData 8 source) =
      .ok (setReadOnlyMethodReturnDataV1 machine
        (some (encodeU64le value))) := by
  simp [stepReadOnlyMethodOperationV1, hsource]

/-- Big-step execution of the supported operation list. -/
def runReadOnlyMethodOperationsV1 :
    List Operation → ReadOnlyMethodMachineV1 →
      Except ReadOnlyMethodErrorV1 ReadOnlyMethodMachineV1
  | [], machine => .ok machine
  | operation :: remaining, machine => do
      let machine ← stepReadOnlyMethodOperationV1 machine operation
      runReadOnlyMethodOperationsV1 remaining machine

private theorem runReadOnlyMethodOperationsV1_append
    (left right : List Operation)
    (machine : ReadOnlyMethodMachineV1) :
    runReadOnlyMethodOperationsV1 (left ++ right) machine = (do
      let machine ← runReadOnlyMethodOperationsV1 left machine
      runReadOnlyMethodOperationsV1 right machine) := by
  induction left generalizing machine with
  | nil => rfl
  | cons operation remaining ih =>
      simp only [List.cons_append, runReadOnlyMethodOperationsV1]
      cases hstep : stepReadOnlyMethodOperationV1 machine operation with
      | error error => simp [Bind.bind, Except.bind]
      | ok next => simp [ih, Bind.bind, Except.bind]

private def checkedAddStoreMethodMachineV1
    (machine : ReadOnlyMethodMachineV1)
    (field : KeyRegion)
    (before amount : UInt64)
    (loadDestination parameterDestination sumDestination : Nat) :
    ReadOnlyMethodMachineV1 :=
  let loaded := setReadOnlyTempValueV1 machine loadDestination before
  let parameter :=
    setReadOnlyTempValueV1 loaded parameterDestination amount
  let sum := UInt64.ofNat (before.toNat + amount.toNat)
  let added := setReadOnlyTempValueV1 parameter sumDestination sum
  writeReadOnlyMethodStorageV1 added field.key (encodeU64le sum)

private theorem runReadOnlyMethodOperationsV1_checkedAddStore
    (machine : ReadOnlyMethodMachineV1)
    (field : KeyRegion)
    (before amount : UInt64)
    (loadDestination parameterDestination sumDestination : Nat)
    (hfield : machine.storage.lookup field.key = some (encodeU64le before))
    (hinput : machine.input = encodeU64le amount)
    (hloadBound : loadDestination < machine.tempCount)
    (hparameterBound : parameterDestination < machine.tempCount)
    (hsumBound : sumDestination < machine.tempCount)
    (hloadParameter : loadDestination ≠ parameterDestination)
    (hadd : before.toNat + amount.toNat < 2 ^ 64) :
    runReadOnlyMethodOperationsV1 [
      .loadState loadDestination field,
      .loadParam parameterDestination 0,
      .checkedAdd sumDestination loadDestination parameterDestination,
      .storeState field sumDestination
    ] machine =
      .ok (checkedAddStoreMethodMachineV1 machine field before amount
        loadDestination parameterDestination sumDestination) := by
  let sum := UInt64.ofNat (before.toNat + amount.toNat)
  let m1 := setReadOnlyTempValueV1 machine loadDestination before
  let m2 := setReadOnlyTempValueV1 m1 parameterDestination amount
  let m3 := setReadOnlyTempValueV1 m2 sumDestination sum
  let m4 := writeReadOnlyMethodStorageV1 m3 field.key (encodeU64le sum)
  have step0 : stepReadOnlyMethodOperationV1 machine
      (.loadState loadDestination field) = .ok m1 := by
    simpa [m1] using stepReadOnlyMethodOperationV1_loadState_encode machine
      loadDestination field before hfield hloadBound
  have step1 : stepReadOnlyMethodOperationV1 m1
      (.loadParam parameterDestination 0) = .ok m2 := by
    simpa [m2] using stepReadOnlyMethodOperationV1_loadParam_zero_encode m1
      parameterDestination amount (by simpa [m1] using hinput)
        (by simpa [m1] using hparameterBound)
  have hreadLoad : readReadOnlyTempV1 m2 loadDestination = .ok before := by
    simp [m2, m1, hloadParameter, hloadBound]
  have hreadParameter :
      readReadOnlyTempV1 m2 parameterDestination = .ok amount := by
    simp [m2, m1, hparameterBound]
  have step2 : stepReadOnlyMethodOperationV1 m2
      (.checkedAdd sumDestination loadDestination parameterDestination) =
      .ok m3 := by
    simpa [m3, sum] using stepReadOnlyMethodOperationV1_checkedAdd m2
      sumDestination loadDestination parameterDestination before amount
        hreadLoad hreadParameter hadd (by simpa [m2, m1] using hsumBound)
  have hreadSum : readReadOnlyTempV1 m3 sumDestination = .ok sum := by
    simp [m3, m2, m1, hsumBound]
  have step3 : stepReadOnlyMethodOperationV1 m3
      (.storeState field sumDestination) = .ok m4 := by
    simpa [m4] using stepReadOnlyMethodOperationV1_storeState_encode m3 field
      sumDestination before sum (by simpa [m3, m2, m1] using hfield) hreadSum
  simp only [runReadOnlyMethodOperationsV1, step0, step1, step2, step3,
    Bind.bind, Except.bind]
  rfl

private theorem runReadOnlyMethodOperationsV1_checkedAddOverflow
    (machine : ReadOnlyMethodMachineV1)
    (field : KeyRegion)
    (before amount : UInt64)
    (loadDestination parameterDestination sumDestination : Nat)
    (hfield : machine.storage.lookup field.key = some (encodeU64le before))
    (hinput : machine.input = encodeU64le amount)
    (hloadBound : loadDestination < machine.tempCount)
    (hparameterBound : parameterDestination < machine.tempCount)
    (hloadParameter : loadDestination ≠ parameterDestination)
    (hoverflow : ¬ before.toNat + amount.toNat < 2 ^ 64) :
    runReadOnlyMethodOperationsV1 [
      .loadState loadDestination field,
      .loadParam parameterDestination 0,
      .checkedAdd sumDestination loadDestination parameterDestination
    ] machine = .error .arithmeticOverflow := by
  let loaded := setReadOnlyTempValueV1 machine loadDestination before
  let parameter :=
    setReadOnlyTempValueV1 loaded parameterDestination amount
  have step0 : stepReadOnlyMethodOperationV1 machine
      (.loadState loadDestination field) = .ok loaded := by
    simpa [loaded] using stepReadOnlyMethodOperationV1_loadState_encode machine
      loadDestination field before hfield hloadBound
  have step1 : stepReadOnlyMethodOperationV1 loaded
      (.loadParam parameterDestination 0) = .ok parameter := by
    simpa [parameter] using stepReadOnlyMethodOperationV1_loadParam_zero_encode
      loaded parameterDestination amount (by simpa [loaded] using hinput)
        (by simpa [loaded] using hparameterBound)
  have hreadLoad :
      readReadOnlyTempV1 parameter loadDestination = .ok before := by
    simp [parameter, loaded, hloadParameter, hloadBound]
  have hreadParameter :
      readReadOnlyTempV1 parameter parameterDestination = .ok amount := by
    simp [parameter, loaded, hparameterBound]
  have step2 : stepReadOnlyMethodOperationV1 parameter
      (.checkedAdd sumDestination loadDestination parameterDestination) =
      .error .arithmeticOverflow :=
    stepReadOnlyMethodOperationV1_checkedAdd_overflow parameter sumDestination
      loadDestination parameterDestination before amount hreadLoad
        hreadParameter hoverflow
  simp only [runReadOnlyMethodOperationsV1, step0, step1, step2, Bind.bind,
    Except.bind]

private theorem runReadOnlyMethodOperationsV1_depositGuards
    (machine : ReadOnlyMethodMachineV1)
    (marker : KeyRegion)
    (markerValue : UInt64)
    (hinput : machine.input.size = 8)
    (hlow : machine.attachedDepositLow = 0)
    (hhigh : machine.attachedDepositHigh = 0)
    (hmarker :
      machine.storage.lookup marker.key = some (encodeU64le markerValue)) :
    runReadOnlyMethodOperationsV1 [
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout marker markerValue
    ] machine = .ok machine := by
  have step0 := stepReadOnlyMethodOperationV1_checkInputLen machine 8 hinput
  have step1 := stepReadOnlyMethodOperationV1_requireZeroAttachedDeposit machine
    hlow hhigh
  have step2 := stepReadOnlyMethodOperationV1_requireLayout machine marker
    markerValue hmarker
  simp only [runReadOnlyMethodOperationsV1, step0, step1, step2, Bind.bind,
    Except.bind]

private theorem runReadOnlyMethodOperationsV1_loadAndReturn
    (machine : ReadOnlyMethodMachineV1)
    (field : KeyRegion)
    (value : UInt64)
    (destination : Nat)
    (hfield : machine.storage.lookup field.key = some (encodeU64le value))
    (hbound : destination < machine.tempCount) :
    runReadOnlyMethodOperationsV1 [
      .loadState destination field,
      .setReturnData 8 destination
    ] machine =
      .ok (setReadOnlyMethodReturnDataV1
        (setReadOnlyTempValueV1 machine destination value)
        (some (encodeU64le value))) := by
  let loaded := setReadOnlyTempValueV1 machine destination value
  let returned :=
    setReadOnlyMethodReturnDataV1 loaded (some (encodeU64le value))
  have step0 : stepReadOnlyMethodOperationV1 machine
      (.loadState destination field) = .ok loaded := by
    simpa [loaded] using stepReadOnlyMethodOperationV1_loadState_encode machine
      destination field value hfield hbound
  have hread : readReadOnlyTempV1 loaded destination = .ok value := by
    simp [loaded, hbound]
  have step1 : stepReadOnlyMethodOperationV1 loaded
      (.setReturnData 8 destination) = .ok returned := by
    simpa [returned] using stepReadOnlyMethodOperationV1_setReturnData_encode
      loaded destination value hread
  simp only [runReadOnlyMethodOperationsV1, step0, step1, Bind.bind,
    Except.bind]
  rfl

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
    writeReadOnlyTempV1, setReadOnlyTempValueV1, readReadOnlyTempV1,
    setReadOnlyMethodReturnDataV1, hmarker, hfield, hfieldSize, hroundtrip,
    encodeU64le_size, Bind.bind, Except.bind]

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
    writeReadOnlyTempV1, setReadOnlyTempValueV1, readReadOnlyTempV1,
    writeReadOnlyMethodStorageV1, writeStorageObservationV1,
    zeroTwoUInt64InitializerPostStorageV1,
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

/-! ## Selected unary checked-add two-UInt64 entry execution -/

/-- Canonical bytes produced by one successful checked UInt64 addition. -/
def checkedAddUInt64BytesV1 (left right : UInt64) : ByteArray :=
  encodeU64le (UInt64.ofNat (left.toNat + right.toNat))

/-- The target checked-add encoding is exactly the byte string used by the
    Reference machine for an in-range UInt64 sum. This is a codec bridge, not
    a second arithmetic or contract semantics. -/
theorem checkedAddUInt64BytesV1_eq_natToLeBytesV1
    (left right : UInt64)
    (hadd : left.toNat + right.toNat < 2 ^ 64) :
    checkedAddUInt64BytesV1 left right =
      natToLeBytesV1 (left.toNat + right.toNat) 8 := by
  calc
    checkedAddUInt64BytesV1 left right =
        natToLeBytesV1
          (UInt64.ofNat (left.toNat + right.toNat)).toNat 8 := by
      exact (natToLeBytesV1_uint64_eq_encodeU64le _).symm
    _ = natToLeBytesV1 (left.toNat + right.toNat) 8 := by
      rw [UInt64.toNat_ofNat', Nat.mod_eq_of_lt hadd]

/-- Exact physical post-storage for the selected deposit recipe. -/
def unaryAddTwoUInt64DepositPostStorageV1
    (storage : StorageObservationV1)
    (field0 field1 : KeyRegion)
    (before0 before1 amount : UInt64) : StorageObservationV1 :=
  writeStorageObservationV1
    (writeStorageObservationV1 storage field0.key
      (checkedAddUInt64BytesV1 before0 amount))
    field1.key (checkedAddUInt64BytesV1 before1 amount)

/-- Exact successful MethodIR execution for the selected unary two-field
    checked-add entry. Both arithmetic bounds are explicit; a trap carries no
    post-storage and therefore cannot expose the first partial write. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some (encodeU64le before1))
    (hfield10 : field1.key ≠ field0.key)
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
        .checkInputLen 8,
        .requireZeroAttachedDeposit,
        .requireLayout marker markerValue,
        .loadState 0 field0,
        .loadParam 1 0,
        .checkedAdd 2 0 1,
        .storeState field0 2,
        .loadState 3 field1,
        .loadParam 4 0,
        .checkedAdd 5 3 4,
        .storeState field1 5,
        .loadState 6 field1,
        .setReturnData 8 6
      ]
    } (encodeU64le amount) 0 0 storage =
      .returned (some (checkedAddUInt64BytesV1 before1 amount))
        (unaryAddTwoUInt64DepositPostStorageV1 storage field0 field1 before0
          before1 amount) := by
  let methodIR : MethodIR := {
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
  }
  let sum0 := UInt64.ofNat (before0.toNat + amount.toNat)
  let sum1 := UInt64.ofNat (before1.toNat + amount.toNat)
  let m0 := initialReadOnlyMethodMachineV1 methodIR (encodeU64le amount) 0 0
    storage
  let m4 := checkedAddStoreMethodMachineV1 m0 field0 before0 amount 0 1 2
  let m8 := checkedAddStoreMethodMachineV1 m4 field1 before1 amount 3 4 5
  let m10 := setReadOnlyMethodReturnDataV1
    (setReadOnlyTempValueV1 m8 6 sum1) (some (encodeU64le sum1))
  have hguards : runReadOnlyMethodOperationsV1 [
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout marker markerValue
    ] m0 = .ok m0 := by
    apply runReadOnlyMethodOperationsV1_depositGuards
    · simp [m0, initialReadOnlyMethodMachineV1, encodeU64le_size]
    · rfl
    · rfl
    · simpa [m0, initialReadOnlyMethodMachineV1] using hmarker
  have hfirst : runReadOnlyMethodOperationsV1 [
      .loadState 0 field0,
      .loadParam 1 0,
      .checkedAdd 2 0 1,
      .storeState field0 2
    ] m0 = .ok m4 := by
    simpa [m4] using runReadOnlyMethodOperationsV1_checkedAddStore m0 field0
      before0 amount 0 1 2
        (by simpa [m0, initialReadOnlyMethodMachineV1] using hfield0)
        (by rfl)
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by decide) hadd0
  have hfield14 :
      m4.storage.lookup field1.key = some (encodeU64le before1) := by
    simp [m4, checkedAddStoreMethodMachineV1, m0,
      initialReadOnlyMethodMachineV1, writeStorageObservationV1, hfield10,
      hfield1]
  have hsecond : runReadOnlyMethodOperationsV1 [
      .loadState 3 field1,
      .loadParam 4 0,
      .checkedAdd 5 3 4,
      .storeState field1 5
    ] m4 = .ok m8 := by
    simpa [m8] using runReadOnlyMethodOperationsV1_checkedAddStore m4 field1
      before1 amount 3 4 5 hfield14
        (by simp [m4, checkedAddStoreMethodMachineV1, m0,
          initialReadOnlyMethodMachineV1])
        (by simp [m4, checkedAddStoreMethodMachineV1, m0,
          initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m4, checkedAddStoreMethodMachineV1, m0,
          initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m4, checkedAddStoreMethodMachineV1, m0,
          initialReadOnlyMethodMachineV1, methodIR])
        (by decide) hadd1
  have hfield18 :
      m8.storage.lookup field1.key = some (encodeU64le sum1) := by
    simp [m8, checkedAddStoreMethodMachineV1, writeStorageObservationV1,
      sum1]
  have hreturnRun : runReadOnlyMethodOperationsV1 [
      .loadState 6 field1,
      .setReturnData 8 6
    ] m8 = .ok m10 := by
    simpa [m10] using runReadOnlyMethodOperationsV1_loadAndReturn m8 field1
      sum1 6 hfield18 (by simp [m8, checkedAddStoreMethodMachineV1, m4,
        m0, initialReadOnlyMethodMachineV1, methodIR])
  have hrun : runReadOnlyMethodOperationsV1 methodIR.operations.toList m0 =
      .ok m10 := by
    change runReadOnlyMethodOperationsV1
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] ++
        [.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
          .storeState field0 2] ++
        [.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4,
          .storeState field1 5] ++
        [.loadState 6 field1, .setReturnData 8 6]) m0 = .ok m10
    rw [show
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        [.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
          .storeState field0 2] ++
        [.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4,
          .storeState field1 5] ++
        [.loadState 6 field1, .setReturnData 8 6] =
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        ([.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
            .storeState field0 2] ++
          ([.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4,
              .storeState field1 5] ++
            [.loadState 6 field1, .setReturnData 8 6])) by
        simp only [List.append_assoc]]
    rw [runReadOnlyMethodOperationsV1_append, hguards]
    simp only [Bind.bind, Except.bind]
    rw [runReadOnlyMethodOperationsV1_append, hfirst]
    simp only [Bind.bind, Except.bind]
    rw [runReadOnlyMethodOperationsV1_append, hsecond]
    simp only [Bind.bind, Except.bind, hreturnRun]
  have hreturn :
      m10.returnData = some (checkedAddUInt64BytesV1 before1 amount) := by
    simp only [m10, setReadOnlyMethodReturnDataV1_returnData,
      checkedAddUInt64BytesV1, sum1]
  have hstorage :
      m10.storage = unaryAddTwoUInt64DepositPostStorageV1 storage field0 field1
        before0 before1 amount := by
    change m10.storage =
      writeStorageObservationV1
        (writeStorageObservationV1 storage field0.key (encodeU64le sum0))
        field1.key (encodeU64le sum1)
    simp only [m10, setReadOnlyMethodReturnDataV1_storage,
      setReadOnlyTempValueV1_storage, m8, checkedAddStoreMethodMachineV1,
      writeReadOnlyMethodStorageV1_storage, m4, m0,
      initialReadOnlyMethodMachineV1, sum0, sum1]
  change executeMethodV1 methodIR (encodeU64le amount) 0 0 storage = _
  unfold executeMethodV1
  rw [hrun]
  change MethodExecutionOutcomeV1.returned m10.returnData m10.storage = _
  rw [hreturn, hstorage]

/-- Wrong ABI width fails before deposit or storage inspection. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_wrong_input
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue : UInt64)
    (input : ByteArray)
    (storage : StorageObservationV1)
    (hinput : input.size ≠ 8) :
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
    } input 0 0 storage = .trapped .inputLengthMismatch := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hinput,
    Bind.bind, Except.bind]

/-- A nonzero low attached-deposit limb fails before layout or state access. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_nonzero_deposit
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue depositLow amount : UInt64)
    (storage : StorageObservationV1)
    (hdeposit : depositLow ≠ 0) :
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
    } (encodeU64le amount) depositLow 0 storage =
      .trapped .attachedDepositNotZero := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hdeposit,
    encodeU64le_size, Bind.bind, Except.bind]

/-- A nonzero high attached-deposit limb is rejected by the same u128 gate. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_nonzero_deposit_high
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue depositHigh amount : UInt64)
    (storage : StorageObservationV1)
    (hdeposit : depositHigh ≠ 0) :
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
    } (encodeU64le amount) 0 depositHigh storage =
      .trapped .attachedDepositNotZero := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hdeposit,
    encodeU64le_size, Bind.bind, Except.bind]

/-- A missing layout marker fails before either state row is read or written. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_marker_missing
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = none) :
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
    } (encodeU64le amount) 0 0 storage = .trapped .storageMissing := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hmarker,
    encodeU64le_size, Bind.bind, Except.bind]

/-- A noncanonical marker value fails before either state row is touched. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_marker_mismatch
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue amount : UInt64)
    (markerBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some markerBytes)
    (hmarkerSize : markerBytes.size = 8)
    (hmarkerValue : markerBytes ≠ encodeU64le markerValue) :
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
    } (encodeU64le amount) 0 0 storage = .trapped .layoutMismatch := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hmarker,
    hmarkerSize, hmarkerValue, encodeU64le_size, Bind.bind, Except.bind]

/-- A marker with the wrong storage width fails before either state row is
    touched. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_marker_wrong_width
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue amount : UInt64)
    (markerBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some markerBytes)
    (hmarkerSize : markerBytes.size ≠ 8) :
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
      .trapped .storageWidthMismatch := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hmarker,
    hmarkerSize, encodeU64le_size, Bind.bind, Except.bind]

/-- A missing first state row fails before any storage write. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_field0_missing
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = none) :
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
    } (encodeU64le amount) 0 0 storage = .trapped .storageMissing := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hmarker,
    hfield0, encodeU64le_size, Bind.bind, Except.bind]

/-- A malformed first state row fails before any storage write. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_field0_wrong_width
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue amount : UInt64)
    (fieldBytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker : storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some fieldBytes)
    (hfield0Size : fieldBytes.size ≠ 8) :
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
      .trapped .storageWidthMismatch := by
  simp [executeMethodV1, runReadOnlyMethodOperationsV1,
    initialReadOnlyMethodMachineV1, stepReadOnlyMethodOperationV1, hmarker,
    hfield0, hfield0Size, encodeU64le_size, Bind.bind, Except.bind]

/-- Overflow in the first checked add traps before any storage write. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_first_overflow
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hoverflow : ¬ before0.toNat + amount.toNat < 2 ^ 64) :
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
    } (encodeU64le amount) 0 0 storage = .trapped .arithmeticOverflow := by
  let methodIR : MethodIR := {
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
  }
  let m0 := initialReadOnlyMethodMachineV1 methodIR (encodeU64le amount) 0 0
    storage
  have hguards : runReadOnlyMethodOperationsV1 [
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout marker markerValue
    ] m0 = .ok m0 := by
    apply runReadOnlyMethodOperationsV1_depositGuards
    · simp [m0, initialReadOnlyMethodMachineV1, encodeU64le_size]
    · rfl
    · rfl
    · simpa [m0, initialReadOnlyMethodMachineV1] using hmarker
  have hoverflowRun : runReadOnlyMethodOperationsV1 [
      .loadState 0 field0,
      .loadParam 1 0,
      .checkedAdd 2 0 1
    ] m0 = .error .arithmeticOverflow := by
    exact runReadOnlyMethodOperationsV1_checkedAddOverflow m0 field0 before0
      amount 0 1 2
        (by simpa [m0, initialReadOnlyMethodMachineV1] using hfield0)
        (by rfl)
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by decide) hoverflow
  have hrun : runReadOnlyMethodOperationsV1 methodIR.operations.toList m0 =
      .error .arithmeticOverflow := by
    change runReadOnlyMethodOperationsV1
      (([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        [.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1] ++
        [.storeState field0 2, .loadState 3 field1, .loadParam 4 0,
          .checkedAdd 5 3 4, .storeState field1 5, .loadState 6 field1,
          .setReturnData 8 6]) m0 = .error .arithmeticOverflow
    rw [show
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        [.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1] ++
        [.storeState field0 2, .loadState 3 field1, .loadParam 4 0,
          .checkedAdd 5 3 4, .storeState field1 5, .loadState 6 field1,
          .setReturnData 8 6] =
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        ([.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1] ++
          [.storeState field0 2, .loadState 3 field1, .loadParam 4 0,
            .checkedAdd 5 3 4, .storeState field1 5, .loadState 6 field1,
            .setReturnData 8 6]) by simp only [List.append_assoc]]
    rw [runReadOnlyMethodOperationsV1_append, hguards]
    simp only [Bind.bind, Except.bind]
    rw [runReadOnlyMethodOperationsV1_append, hoverflowRun]
    simp only [Bind.bind, Except.bind]
  change executeMethodV1 methodIR (encodeU64le amount) 0 0 storage = _
  unfold executeMethodV1
  rw [hrun]

/-- A missing second state row traps after the first in-machine write, while the
    failure outcome exposes no post-storage and therefore rolls back the call. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_field1_missing
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = none)
    (hfield10 : field1.key ≠ field0.key)
    (hadd0 : before0.toNat + amount.toNat < 2 ^ 64) :
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
    } (encodeU64le amount) 0 0 storage = .trapped .storageMissing := by
  let methodIR : MethodIR := {
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
  }
  let m0 := initialReadOnlyMethodMachineV1 methodIR (encodeU64le amount) 0 0
    storage
  let m4 := checkedAddStoreMethodMachineV1 m0 field0 before0 amount 0 1 2
  have hguards : runReadOnlyMethodOperationsV1 [
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout marker markerValue
    ] m0 = .ok m0 := by
    apply runReadOnlyMethodOperationsV1_depositGuards
    · simp [m0, initialReadOnlyMethodMachineV1, encodeU64le_size]
    · rfl
    · rfl
    · simpa [m0, initialReadOnlyMethodMachineV1] using hmarker
  have hfirst : runReadOnlyMethodOperationsV1 [
      .loadState 0 field0,
      .loadParam 1 0,
      .checkedAdd 2 0 1,
      .storeState field0 2
    ] m0 = .ok m4 := by
    simpa [m4] using runReadOnlyMethodOperationsV1_checkedAddStore m0 field0
      before0 amount 0 1 2
        (by simpa [m0, initialReadOnlyMethodMachineV1] using hfield0)
        (by rfl)
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by decide) hadd0
  have hfield14 : m4.storage.lookup field1.key = none := by
    simp [m4, checkedAddStoreMethodMachineV1, m0,
      initialReadOnlyMethodMachineV1, writeStorageObservationV1, hfield10,
      hfield1]
  have hrun : runReadOnlyMethodOperationsV1 methodIR.operations.toList m0 =
      .error .storageMissing := by
    change runReadOnlyMethodOperationsV1
      (([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        [.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
          .storeState field0 2] ++
        [.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4,
          .storeState field1 5, .loadState 6 field1,
          .setReturnData 8 6]) m0 = .error .storageMissing
    rw [show
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        [.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
          .storeState field0 2] ++
        [.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4,
          .storeState field1 5, .loadState 6 field1,
          .setReturnData 8 6] =
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        ([.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
            .storeState field0 2] ++
          [.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4,
            .storeState field1 5, .loadState 6 field1,
            .setReturnData 8 6]) by simp only [List.append_assoc]]
    rw [runReadOnlyMethodOperationsV1_append, hguards]
    simp only [Bind.bind, Except.bind]
    rw [runReadOnlyMethodOperationsV1_append, hfirst]
    simp [runReadOnlyMethodOperationsV1, stepReadOnlyMethodOperationV1,
      hfield14, Bind.bind, Except.bind]
  change executeMethodV1 methodIR (encodeU64le amount) 0 0 storage = _
  unfold executeMethodV1
  rw [hrun]

/-- A malformed second state row also traps after the first in-machine write;
    the observable failure still rolls back to the supplied pre-storage. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_field1_wrong_width
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 amount : UInt64)
    (field1Bytes : ByteArray)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some field1Bytes)
    (hfield1Size : field1Bytes.size ≠ 8)
    (hfield10 : field1.key ≠ field0.key)
    (hadd0 : before0.toNat + amount.toNat < 2 ^ 64) :
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
      .trapped .storageWidthMismatch := by
  let methodIR : MethodIR := {
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
  }
  let m0 := initialReadOnlyMethodMachineV1 methodIR (encodeU64le amount) 0 0
    storage
  let m4 := checkedAddStoreMethodMachineV1 m0 field0 before0 amount 0 1 2
  have hguards : runReadOnlyMethodOperationsV1 [
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout marker markerValue
    ] m0 = .ok m0 := by
    apply runReadOnlyMethodOperationsV1_depositGuards
    · simp [m0, initialReadOnlyMethodMachineV1, encodeU64le_size]
    · rfl
    · rfl
    · simpa [m0, initialReadOnlyMethodMachineV1] using hmarker
  have hfirst : runReadOnlyMethodOperationsV1 [
      .loadState 0 field0,
      .loadParam 1 0,
      .checkedAdd 2 0 1,
      .storeState field0 2
    ] m0 = .ok m4 := by
    simpa [m4] using runReadOnlyMethodOperationsV1_checkedAddStore m0 field0
      before0 amount 0 1 2
        (by simpa [m0, initialReadOnlyMethodMachineV1] using hfield0)
        (by rfl)
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by decide) hadd0
  have hfield14 : m4.storage.lookup field1.key = some field1Bytes := by
    simp [m4, checkedAddStoreMethodMachineV1, m0,
      initialReadOnlyMethodMachineV1, writeStorageObservationV1, hfield10,
      hfield1]
  have hrun : runReadOnlyMethodOperationsV1 methodIR.operations.toList m0 =
      .error .storageWidthMismatch := by
    change runReadOnlyMethodOperationsV1
      (([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        [.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
          .storeState field0 2] ++
        [.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4,
          .storeState field1 5, .loadState 6 field1,
          .setReturnData 8 6]) m0 = .error .storageWidthMismatch
    rw [show
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        [.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
          .storeState field0 2] ++
        [.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4,
          .storeState field1 5, .loadState 6 field1,
          .setReturnData 8 6] =
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        ([.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
            .storeState field0 2] ++
          [.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4,
            .storeState field1 5, .loadState 6 field1,
            .setReturnData 8 6]) by simp only [List.append_assoc]]
    rw [runReadOnlyMethodOperationsV1_append, hguards]
    simp only [Bind.bind, Except.bind]
    rw [runReadOnlyMethodOperationsV1_append, hfirst]
    simp [runReadOnlyMethodOperationsV1, stepReadOnlyMethodOperationV1,
      hfield14, hfield1Size, Bind.bind, Except.bind]
  change executeMethodV1 methodIR (encodeU64le amount) 0 0 storage = _
  unfold executeMethodV1
  rw [hrun]

/-- Overflow in the second checked add traps after the first in-machine write.
    Since failures carry no post-storage, the call observation rolls that write
    back rather than exposing a partially updated vault. -/
theorem executeMethodV1_unaryAddTwoUInt64Deposit_second_overflow
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (marker field0 field1 : KeyRegion)
    (markerValue before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hmarker :
      storage.lookup marker.key = some (encodeU64le markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some (encodeU64le before1))
    (hfield10 : field1.key ≠ field0.key)
    (hadd0 : before0.toNat + amount.toNat < 2 ^ 64)
    (hoverflow1 : ¬ before1.toNat + amount.toNat < 2 ^ 64) :
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
    } (encodeU64le amount) 0 0 storage = .trapped .arithmeticOverflow := by
  let methodIR : MethodIR := {
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
  }
  let m0 := initialReadOnlyMethodMachineV1 methodIR (encodeU64le amount) 0 0
    storage
  let m4 := checkedAddStoreMethodMachineV1 m0 field0 before0 amount 0 1 2
  have hguards : runReadOnlyMethodOperationsV1 [
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout marker markerValue
    ] m0 = .ok m0 := by
    apply runReadOnlyMethodOperationsV1_depositGuards
    · simp [m0, initialReadOnlyMethodMachineV1, encodeU64le_size]
    · rfl
    · rfl
    · simpa [m0, initialReadOnlyMethodMachineV1] using hmarker
  have hfirst : runReadOnlyMethodOperationsV1 [
      .loadState 0 field0,
      .loadParam 1 0,
      .checkedAdd 2 0 1,
      .storeState field0 2
    ] m0 = .ok m4 := by
    simpa [m4] using runReadOnlyMethodOperationsV1_checkedAddStore m0 field0
      before0 amount 0 1 2
        (by simpa [m0, initialReadOnlyMethodMachineV1] using hfield0)
        (by rfl)
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m0, initialReadOnlyMethodMachineV1, methodIR])
        (by decide) hadd0
  have hfield14 :
      m4.storage.lookup field1.key = some (encodeU64le before1) := by
    simp [m4, checkedAddStoreMethodMachineV1, m0,
      initialReadOnlyMethodMachineV1, writeStorageObservationV1, hfield10,
      hfield1]
  have hoverflowRun : runReadOnlyMethodOperationsV1 [
      .loadState 3 field1,
      .loadParam 4 0,
      .checkedAdd 5 3 4
    ] m4 = .error .arithmeticOverflow := by
    exact runReadOnlyMethodOperationsV1_checkedAddOverflow m4 field1 before1
      amount 3 4 5 hfield14
        (by simp [m4, checkedAddStoreMethodMachineV1, m0,
          initialReadOnlyMethodMachineV1])
        (by simp [m4, checkedAddStoreMethodMachineV1, m0,
          initialReadOnlyMethodMachineV1, methodIR])
        (by simp [m4, checkedAddStoreMethodMachineV1, m0,
          initialReadOnlyMethodMachineV1, methodIR])
        (by decide) hoverflow1
  have hrun : runReadOnlyMethodOperationsV1 methodIR.operations.toList m0 =
      .error .arithmeticOverflow := by
    change runReadOnlyMethodOperationsV1
      (([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        [.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
          .storeState field0 2] ++
        [.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4] ++
        [.storeState field1 5, .loadState 6 field1,
          .setReturnData 8 6]) m0 = .error .arithmeticOverflow
    rw [show
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        [.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
          .storeState field0 2] ++
        [.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4] ++
        [.storeState field1 5, .loadState 6 field1,
          .setReturnData 8 6] =
      ([.checkInputLen 8, .requireZeroAttachedDeposit,
          .requireLayout marker markerValue] : List Operation) ++
        ([.loadState 0 field0, .loadParam 1 0, .checkedAdd 2 0 1,
            .storeState field0 2] ++
          ([.loadState 3 field1, .loadParam 4 0, .checkedAdd 5 3 4] ++
            [.storeState field1 5, .loadState 6 field1,
              .setReturnData 8 6])) by simp only [List.append_assoc]]
    rw [runReadOnlyMethodOperationsV1_append, hguards]
    simp only [Bind.bind, Except.bind]
    rw [runReadOnlyMethodOperationsV1_append, hfirst]
    simp only [Bind.bind, Except.bind]
    rw [runReadOnlyMethodOperationsV1_append, hoverflowRun]
    simp only [Bind.bind, Except.bind]
  change executeMethodV1 methodIR (encodeU64le amount) 0 0 storage = _
  unfold executeMethodV1
  rw [hrun]

/-- Static alignment specializes the one MethodIR evaluator to the exact
    production deposit recipe. -/
theorem executeMethodV1_of_unaryAddTwoUInt64DepositStaticAlignment
    (data : SemanticProgramDataV1)
    (storageLayout : StorageLayout)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (marker field0 field1 : KeyRegion)
    (methodIR : MethodIR)
    (before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (halignment :
      UnaryAddTwoUInt64DepositStaticAlignmentV1 data storageLayout binding0
        binding1 entryName parameterName parameterSourceId method marker field0
          field1 methodIR)
    (hmarker :
      storage.lookup marker.key =
        some (encodeU64le storageLayout.markerValue))
    (hfield0 : storage.lookup field0.key = some (encodeU64le before0))
    (hfield1 : storage.lookup field1.key = some (encodeU64le before1))
    (hfield10 : field1.key ≠ field0.key)
    (hadd0 : before0.toNat + amount.toNat < 2 ^ 64)
    (hadd1 : before1.toNat + amount.toNat < 2 ^ 64) :
    executeMethodV1 methodIR (encodeU64le amount) 0 0 storage =
      .returned (some (checkedAddUInt64BytesV1 before1 amount))
        (unaryAddTwoUInt64DepositPostStorageV1 storage field0 field1 before0
          before1 amount) := by
  rw [halignment.methodIRExact]
  exact executeMethodV1_unaryAddTwoUInt64Deposit entryName parameterName
    parameterSourceId marker field0 field1 storageLayout.markerValue before0
      before1 amount storage hmarker hfield0 hfield1 hfield10 hadd0 hadd1

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

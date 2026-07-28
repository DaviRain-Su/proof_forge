import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Near
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.NearHostModel

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1

/-- ProgramV1 Accumulator source (S1 dual-carrier compatible). -/
private def accumulatorSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Accumulator where\n" ++
  "  state total : UInt64\n\n" ++
  "  init(seed : UInt64) do\n" ++
  "    total := seed\n\n" ++
  "  entry add(amount : UInt64) : UInt64 do\n" ++
  "    total := total + amount\n" ++
  "    return total\n\n" ++
  "  view current() : UInt64 do\n" ++
  "    return total\n\n" ++
  "end ProofForgeV2.Examples\n"

private def accumulatorModuleNameV1 : String := "Examples.Accumulator"

private abbrev HostStorage := Array (String × ByteArray)
private abbrev U64 := _root_.UInt64

private structure Deposit where
  lowWord : U64
  highWord : U64

private structure Machine where
  storage : HostStorage
  temps : Array (Option U64)
  returned : Option U64 := none

private inductive Outcome where
  | success (storage : HostStorage) (returned : Option U64)
  | trapped (storage : HostStorage) (reason : String)

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def repeatedByte (count : Nat) (value : UInt8) : ByteArray :=
  ByteArray.mk (Array.replicate count value)

private def encodeUInt64LE (value : U64) : ByteArray :=
  ByteArray.mk #[
    value.toUInt8,
    (UInt64.shiftRight value 8).toUInt8,
    (UInt64.shiftRight value 16).toUInt8,
    (UInt64.shiftRight value 24).toUInt8,
    (UInt64.shiftRight value 32).toUInt8,
    (UInt64.shiftRight value 40).toUInt8,
    (UInt64.shiftRight value 48).toUInt8,
    (UInt64.shiftRight value 56).toUInt8
  ]

private def decodeUInt64LEAt (bytes : ByteArray) (offset : Nat) : Option U64 :=
  if offset + 8 > bytes.size then
    none
  else
    some <| Id.run do
      let mut value : U64 := 0
      for index in [0:8] do
        value := value |||
          UInt64.shiftLeft bytes[offset + index]!.toUInt64 (UInt64.ofNat (8 * index))
      return value

private def decodeUInt64LE (bytes : ByteArray) : Option U64 :=
  if bytes.size == 8 then decodeUInt64LEAt bytes 0 else none

private def storageLookup? (storage : HostStorage) (key : String) : Option ByteArray :=
  match storage.find? (fun item => item.1 == key) with
  | some item => some item.2
  | none => none

private def storagePut (storage : HostStorage) (key : String)
    (value : ByteArray) : HostStorage := Id.run do
  let mut result : HostStorage := #[]
  let mut replaced := false
  for item in storage do
    if item.1 == key then
      if !replaced then
        result := result.push (key, value)
      replaced := true
    else
      result := result.push item
  if !replaced then
    result := result.push (key, value)
  return result

private def storageRemove (storage : HostStorage) (key : String) : HostStorage := Id.run do
  let mut result : HostStorage := #[]
  for item in storage do
    unless item.1 == key do
      result := result.push item
  return result

private def modelError (message : String) : Except String α :=
  .error message

private def requireStorage (machine : Machine)
    (region : Targets.Near.KeyRegion) : Except String ByteArray :=
  match storageLookup? machine.storage region.key with
  | some value => .ok value
  | none => modelError s!"missing storage key '{region.key}'"

private def readTemp (machine : Machine) (index : Nat) : Except String U64 :=
  match machine.temps[index]? with
  | some (some value) => .ok value
  | _ => modelError s!"temporary {index} is unavailable"

private def writeTemp (machine : Machine) (index : Nat)
    (value : U64) : Except String Machine :=
  if index < machine.temps.size then
    .ok { machine with temps := machine.temps.set! index (some value) }
  else
    modelError s!"temporary {index} is outside the method frame"

private def step (input : ByteArray) (deposit : Deposit)
    (machine : Machine) : Targets.Near.Operation → Except String Machine
  | .checkInputLen expected =>
      if input.size == expected then .ok machine
      else modelError s!"input length {input.size} does not equal {expected}"
  | .requireZeroAttachedDeposit =>
      if deposit.lowWord == 0 && deposit.highWord == 0 then .ok machine
      else modelError "attached deposit is nonzero"
  | .requireLayoutAbsent marker =>
      if (storageLookup? machine.storage marker.key).isNone then .ok machine
      else modelError "layout marker is already present"
  | .requireLayout marker expected => do
      let encoded ← requireStorage machine marker
      let actual ← match decodeUInt64LE encoded with
        | some value => pure value
        | none => modelError "layout marker is not exactly eight bytes"
      if actual == expected then pure machine
      else modelError "layout marker does not match the Plan"
  | .zeroState field =>
      if (storageLookup? machine.storage field.key).isSome then
        modelError s!"state key '{field.key}' already exists during zero initialization"
      else
        .ok { machine with
          storage := storagePut machine.storage field.key (encodeUInt64LE 0) }
  | .literal destination value =>
      writeTemp machine destination value
  | .loadParam destination inputOffset => do
      let value ← match decodeUInt64LEAt input inputOffset with
        | some value => pure value
        | none => modelError "parameter read is outside the exact input"
      writeTemp machine destination value
  | .loadState destination field => do
      let encoded ← requireStorage machine field
      let value ← match decodeUInt64LE encoded with
        | some value => pure value
        | none => modelError s!"state key '{field.key}' is not exactly eight bytes"
      writeTemp machine destination value
  | .checkedAdd destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let sum := left.toNat + right.toNat
      if sum > 18446744073709551615 then
        modelError "UInt64 addition overflow"
      else
        writeTemp machine destination (UInt64.ofNat sum)
  | .storeState field source => do
      let previous ← requireStorage machine field
      unless previous.size == 8 do
        modelError s!"evicted state at '{field.key}' is not exactly eight bytes"
      let value ← readTemp machine source
      pure { machine with
        storage := storagePut machine.storage field.key (encodeUInt64LE value) }
  | .setLayout marker value =>
      if (storageLookup? machine.storage marker.key).isSome then
        modelError "layout marker unexpectedly exists before commit"
      else
        .ok { machine with
          storage := storagePut machine.storage marker.key (encodeUInt64LE value) }
  | .setReturnData source => do
      if machine.returned.isSome then
        modelError "return data was already set"
      let value ← readTemp machine source
      pure { machine with returned := some value }

private def runOperations (input : ByteArray) (deposit : Deposit) :
    List Targets.Near.Operation → Machine → Except String Machine
  | [], machine => .ok machine
  | operation :: remaining, machine =>
      match step input deposit machine operation with
      | .ok next => runOperations input deposit remaining next
      | .error reason => .error reason

/-- Pure deterministic model of the typed recipe. A trap restores the exact
pre-call storage snapshot, modeling NEAR's receipt-local rollback contract.
This is not a NEAR VM, sandbox, gas, or protocol-profile execution. -/
private def execute (method : Targets.Near.MethodIR) (storage : HostStorage)
    (input : ByteArray) (deposit : Deposit) : Outcome :=
  let initial : Machine := {
    storage
    temps := Array.replicate method.tempCount none
  }
  match runOperations input deposit method.operations.toList initial with
  | .ok result => .success result.storage result.returned
  | .error reason => .trapped storage reason

private def requireSuccess (label : String) : Outcome → IO (HostStorage × Option U64)
  | .success storage returned => pure (storage, returned)
  | .trapped _ reason => throw <| IO.userError s!"{label} trapped: {reason}"

private def expectTrap (label : String) (snapshot : HostStorage) : Outcome → IO Unit
  | .trapped storage _ =>
      expect (storage == snapshot) s!"{label} did not restore the pre-call storage snapshot"
  | .success .. => throw <| IO.userError s!"{label} unexpectedly succeeded"

private def findMethod (ir : Targets.Near.IR) (name : String) : IO Targets.Near.MethodIR :=
  match ir.methods.find? (fun method => method.name == name) with
  | some method => pure method
  | none => throw <| IO.userError s!"typed NEAR recipe is missing method '{name}'"

private def storedUInt64? (storage : HostStorage) (key : String) : Option U64 :=
  storageLookup? storage key >>= decodeUInt64LE

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    accumulatorSourceText "<near-host-accumulator>"
    accumulatorModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  -- S6 repair: production capability-gated IR inspection (not TargetIrFixtures).
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let initializer ← findMethod ir "init"
  let add ← findMethod ir "add"
  let current ← findMethod ir "current"
  let marker := ir.keys[0]!
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zeroDeposit : Deposit := { lowWord := 0, highWord := 0 }
  let lowDeposit : Deposit := { lowWord := 1, highWord := 0 }
  let highDeposit : Deposit := { lowWord := 0, highWord := 1 }

  expectTrap "entry before init" empty <|
    execute add empty (encodeUInt64LE 5) zeroDeposit
  expectTrap "seven-byte init input" empty <|
    execute initializer empty (repeatedByte 7 0) zeroDeposit
  expectTrap "nine-byte init input" empty <|
    execute initializer empty (repeatedByte 9 0) zeroDeposit
  expectTrap "init with low attached deposit" empty <|
    execute initializer empty (encodeUInt64LE 7) lowDeposit
  expectTrap "init with high attached deposit" empty <|
    execute initializer empty (encodeUInt64LE 7) highDeposit

  let (initialized, initReturn) ← requireSuccess "eight-byte init input" <|
    execute initializer empty (encodeUInt64LE 7) zeroDeposit
  expect (initReturn.isNone) "initializer must not set return data"
  expect (storedUInt64? initialized field.key == some 7)
    "initializer must materialize the seed in target-owned KV state"
  expect (storedUInt64? initialized marker.key == some plan.storage.markerValue)
    "initializer must commit the layout marker after state initialization"

  expectTrap "init twice" initialized <|
    execute initializer initialized (encodeUInt64LE 9) zeroDeposit
  expectTrap "mutate with low attached deposit" initialized <|
    execute add initialized (encodeUInt64LE 5) lowDeposit
  expectTrap "mutate with high attached deposit" initialized <|
    execute add initialized (encodeUInt64LE 5) highDeposit
  expectTrap "seven-byte mutate input" initialized <|
    execute add initialized (repeatedByte 7 0) zeroDeposit
  expectTrap "nine-byte mutate input" initialized <|
    execute add initialized (repeatedByte 9 0) zeroDeposit
  expectTrap "zero-parameter view with trailing input" initialized <|
    execute current initialized (repeatedByte 1 0) zeroDeposit

  let (_, initialViewReturn) ← requireSuccess "zero-parameter view" <|
    execute current initialized ByteArray.empty zeroDeposit
  expect (initialViewReturn == some 7)
    "zero-parameter view must read the initialized UInt64 value"

  let missingMarker := storageRemove initialized marker.key
  expectTrap "missing layout marker" missingMarker <|
    execute current missingMarker ByteArray.empty zeroDeposit
  let missingField := storageRemove initialized field.key
  expectTrap "missing state value" missingField <|
    execute current missingField ByteArray.empty zeroDeposit
  for size in (#[(0 : Nat), 7, 9] : Array Nat) do
    let corruptMarker := storagePut initialized marker.key (repeatedByte size 0)
    expectTrap s!"{size}-byte layout marker" corruptMarker <|
      execute current corruptMarker ByteArray.empty zeroDeposit
    let corruptField := storagePut initialized field.key (repeatedByte size 0)
    expectTrap s!"{size}-byte state value" corruptField <|
      execute current corruptField ByteArray.empty zeroDeposit
  let wrongMarkerValue := if plan.storage.markerValue == 1 then 2 else 1
  let oldLayout := storagePut initialized marker.key (encodeUInt64LE wrongMarkerValue)
  expectTrap "eight-byte mismatched layout marker" oldLayout <|
    execute current oldLayout ByteArray.empty zeroDeposit

  let (added, addReturn) ← requireSuccess "7 + 5 mutate" <|
    execute add initialized (encodeUInt64LE 5) zeroDeposit
  expect (addReturn == some 12 && storedUInt64? added field.key == some 12)
    "mutate must store 12 and its post-store state read must return 12"
  let (_, currentReturn) ← requireSuccess "view after mutate" <|
    execute current added ByteArray.empty zeroDeposit
  expect (currentReturn == some 12) "view must observe the committed mutate state"

  let maximum := UInt64.ofNat 18446744073709551615
  let (maximumState, _) ← requireSuccess "maximum UInt64 init" <|
    execute initializer empty (encodeUInt64LE maximum) zeroDeposit
  expectTrap "maximum UInt64 plus one" maximumState <|
    execute add maximumState (encodeUInt64LE 1) zeroDeposit

end Tests.Materialization.NearHostModel

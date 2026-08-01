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

/-- ProgramV1 Accumulator source for the retained-semantic public UInt64 envelope. -/
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
  halted : Bool := false
  logs : Array String := #[]
  eventNames : Array String := #[]
  errorNames : Array String := #[]
  fns : Array Targets.Near.FnIR := #[]
  callDepth : Nat := 0

private inductive Outcome where
  | success (storage : HostStorage) (returned : Option U64) (logs : Array String)
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

/-- Encode the low `byteWidth` bytes of `value` little-endian (1/2/4/8). -/
private def encodeUIntLE (value : U64) (byteWidth : Nat) : ByteArray :=
  match byteWidth with
  | 1 => ByteArray.mk #[value.toUInt8]
  | 2 => ByteArray.mk #[
      value.toUInt8,
      (UInt64.shiftRight value 8).toUInt8
    ]
  | 4 => ByteArray.mk #[
      value.toUInt8,
      (UInt64.shiftRight value 8).toUInt8,
      (UInt64.shiftRight value 16).toUInt8,
      (UInt64.shiftRight value 24).toUInt8
    ]
  | _ => encodeUInt64LE value

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

/-- Decode exactly `byteWidth` LE bytes at `offset`, zero-extending to U64. -/
private def decodeUIntLEAt (bytes : ByteArray) (offset byteWidth : Nat) : Option U64 :=
  if byteWidth == 0 || offset + byteWidth > bytes.size then
    none
  else
    some <| Id.run do
      let mut value : U64 := 0
      for index in [0:byteWidth] do
        value := value |||
          UInt64.shiftLeft bytes[offset + index]!.toUInt64 (UInt64.ofNat (8 * index))
      return value

private def decodeUInt64LE (bytes : ByteArray) : Option U64 :=
  if bytes.size == 8 then decodeUInt64LEAt bytes 0 else none

private def decodeUIntLE (bytes : ByteArray) (byteWidth : Nat) : Option U64 :=
  if bytes.size == byteWidth then decodeUIntLEAt bytes 0 byteWidth else none

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

/-- Lowercase 16-digit big-endian hex of one UInt64 word. -/
private def hex16 (value : U64) : String :=
  let raw := String.ofList (Nat.toDigits 16 value.toNat)
  String.ofList (List.replicate (16 - raw.length) '0') ++ raw

/-- Comma-separated hex16 encoding of interface arguments (`h0,h1,...`). -/
private def hexArgs (values : Array U64) : String :=
  if values.isEmpty then "" else
    String.intercalate "," (values.toList.map hex16)

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

mutual

private partial def step (input : ByteArray) (deposit : Deposit)
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
  | .narrowZeroState bitWidth field =>
      let bw := bitWidth / 8
      if !(bw == 1 || bw == 2 || bw == 4) then
        modelError s!"narrowZeroState bitWidth {bitWidth} is not admitted"
      else if (storageLookup? machine.storage field.key).isSome then
        modelError s!"state key '{field.key}' already exists during zero initialization"
      else
        .ok { machine with
          storage := storagePut machine.storage field.key (encodeUIntLE 0 bw) }
  | .literal destination value =>
      writeTemp machine destination value
  | .loadParam destination inputOffset => do
      let value ← match decodeUInt64LEAt input inputOffset with
        | some value => pure value
        | none => modelError "parameter read is outside the exact input"
      writeTemp machine destination value
  | .narrowLoadParam bitWidth destination inputOffset => do
      let bw := bitWidth / 8
      unless bw == 1 || bw == 2 || bw == 4 do
        modelError s!"narrowLoadParam bitWidth {bitWidth} is not admitted"
      let value ← match decodeUIntLEAt input inputOffset bw with
        | some value => pure value
        | none => modelError "narrow parameter read is outside the exact input"
      writeTemp machine destination value
  | .loadState destination field => do
      let encoded ← requireStorage machine field
      let value ← match decodeUInt64LE encoded with
        | some value => pure value
        | none => modelError s!"state key '{field.key}' is not exactly eight bytes"
      writeTemp machine destination value
  | .narrowLoadState bitWidth destination field => do
      let bw := bitWidth / 8
      unless bw == 1 || bw == 2 || bw == 4 do
        modelError s!"narrowLoadState bitWidth {bitWidth} is not admitted"
      let encoded ← requireStorage machine field
      let value ← match decodeUIntLE encoded bw with
        | some value => pure value
        | none =>
            modelError s!"state key '{field.key}' is not exactly {bw} bytes"
      writeTemp machine destination value
  | .checkedAdd destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let sum := left.toNat + right.toNat
      if sum > 18446744073709551615 then
        modelError "UInt64 addition overflow"
      else
        writeTemp machine destination (UInt64.ofNat sum)
  | .checkedSub destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      if left < right then
        modelError "UInt64 subtraction underflow"
      else
        writeTemp machine destination (left - right)
  | .checkedMul destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let product := left.toNat * right.toNat
      if product > 18446744073709551615 then
        modelError "native checked UInt64 multiplication overflow"
      else
        writeTemp machine destination (UInt64.ofNat product)
  | .checkedDiv destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      if right == 0 then
        modelError "division by zero"
      else
        writeTemp machine destination (left / right)
  | .checkedMod destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      if right == 0 then
        modelError "division by zero"
      else
        writeTemp machine destination (left % right)
  | .signedCheckedAdd destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let a := (Int.ofNat left.toNat) - (if left.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      let b := (Int.ofNat right.toNat) - (if right.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      let r := a + b
      if r < -9223372036854775808 || r > 9223372036854775807 then
        modelError "Int64 addition overflow"
      else
        let bits := if r < 0 then (r + 18446744073709551616).toNat else r.toNat
        writeTemp machine destination (UInt64.ofNat bits)
  | .signedCheckedSub destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let a := (Int.ofNat left.toNat) - (if left.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      let b := (Int.ofNat right.toNat) - (if right.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      let r := a - b
      if r < -9223372036854775808 || r > 9223372036854775807 then
        modelError "Int64 subtraction overflow"
      else
        let bits := if r < 0 then (r + 18446744073709551616).toNat else r.toNat
        writeTemp machine destination (UInt64.ofNat bits)
  | .signedCheckedMul destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let a := (Int.ofNat left.toNat) - (if left.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      let b := (Int.ofNat right.toNat) - (if right.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      let r := a * b
      if r < -9223372036854775808 || r > 9223372036854775807 then
        modelError "Int64 multiplication overflow"
      else
        let bits := if r < 0 then (r + 18446744073709551616).toNat else r.toNat
        writeTemp machine destination (UInt64.ofNat bits)
  | .signedCheckedDiv destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let a := (Int.ofNat left.toNat) - (if left.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      let b := (Int.ofNat right.toNat) - (if right.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      if b == 0 then modelError "division by zero"
      else if a == -9223372036854775808 && b == -1 then
        modelError "Int64 division overflow"
      else
        let r := a.tdiv b
        let bits := if r < 0 then (r + 18446744073709551616).toNat else r.toNat
        writeTemp machine destination (UInt64.ofNat bits)
  | .signedCheckedMod destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let a := (Int.ofNat left.toNat) - (if left.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      let b := (Int.ofNat right.toNat) - (if right.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      if b == 0 then modelError "division by zero"
      else
        let r := a.tmod b
        let bits := if r < 0 then (r + 18446744073709551616).toNat else r.toNat
        writeTemp machine destination (UInt64.ofNat bits)
  | .signedCompare destination lhs rhs op => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let a := (Int.ofNat left.toNat) - (if left.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      let b := (Int.ofNat right.toNat) - (if right.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
      let flag :=
        match op with
        | .eq => a == b | .ne => a != b
        | .lt => a < b | .le => a ≤ b
        | .gt => a > b | .ge => a ≥ b
      writeTemp machine destination (if flag then 1 else 0)
  | .checkedNeg destination source => do
      let value ← readTemp machine source
      if value.toNat == 9223372036854775808 then
        modelError "Int64 negation overflow"
      else
        let a := (Int.ofNat value.toNat) - (if value.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
        let r := -a
        let bits := if r < 0 then (r + 18446744073709551616).toNat else r.toNat
        writeTemp machine destination (UInt64.ofNat bits)
  | .sar destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let shift := right.toNat
      if shift ≥ 64 then modelError "invalid shift"
      else
        let a := (Int.ofNat left.toNat) - (if left.toNat ≥ 9223372036854775808 then 18446744073709551616 else 0)
        let r := a.ediv (Int.ofNat (Nat.pow 2 shift))
        let bits := if r < 0 then (r + 18446744073709551616).toNat else r.toNat
        writeTemp machine destination (UInt64.ofNat bits)
  | .bitAnd destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      writeTemp machine destination (left &&& right)
  | .bitOr destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      writeTemp machine destination (left ||| right)
  | .bitXor destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      writeTemp machine destination (left ^^^ right)
  | .shl destination lhs rhs => do
      -- Match ReferenceV1: count ≥ 64 → invalidShift; result ≥ 2^64 →
      -- arithmeticOverflow. Nat shift so overflow is exact (Wasm would mask).
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let shift := right.toNat
      if shift ≥ 64 then
        modelError "invalid shift"
      else
        let shifted := Nat.shiftLeft left.toNat shift
        if shifted > 18446744073709551615 then
          modelError "UInt64 shift overflow"
        else
          writeTemp machine destination (UInt64.ofNat shifted)
  | .shr destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let shift := right.toNat
      if shift ≥ 64 then
        modelError "invalid shift"
      else
        writeTemp machine destination
          (UInt64.ofNat (Nat.shiftRight left.toNat shift))
  | .bitNot destination source => do
      let value ← readTemp machine source
      writeTemp machine destination (value ^^^ UInt64.ofNat 18446744073709551615)
  | .narrowCheckedAdd bitWidth destination lhs rhs => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowCheckedAdd bitWidth {bitWidth} is not admitted"
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let sum := left.toNat + right.toNat
      let limit := Nat.pow 2 bitWidth
      if sum ≥ limit then
        modelError s!"UInt{bitWidth} addition overflow"
      else
        writeTemp machine destination (UInt64.ofNat sum)
  | .narrowCheckedSub bitWidth destination lhs rhs => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowCheckedSub bitWidth {bitWidth} is not admitted"
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      if left < right then
        modelError s!"UInt{bitWidth} subtraction underflow"
      else
        writeTemp machine destination (left - right)
  | .narrowCheckedMul bitWidth destination lhs rhs => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowCheckedMul bitWidth {bitWidth} is not admitted"
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let product := left.toNat * right.toNat
      let limit := Nat.pow 2 bitWidth
      if product ≥ limit then
        modelError s!"UInt{bitWidth} multiplication overflow"
      else
        writeTemp machine destination (UInt64.ofNat product)
  | .narrowCheckedDiv bitWidth destination lhs rhs => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowCheckedDiv bitWidth {bitWidth} is not admitted"
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      if right == 0 then
        modelError "division by zero"
      else
        writeTemp machine destination (left / right)
  | .narrowCheckedMod bitWidth destination lhs rhs => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowCheckedMod bitWidth {bitWidth} is not admitted"
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      if right == 0 then
        modelError "division by zero"
      else
        writeTemp machine destination (left % right)
  | .narrowBitAnd bitWidth destination lhs rhs => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowBitAnd bitWidth {bitWidth} is not admitted"
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      writeTemp machine destination (left &&& right)
  | .narrowBitOr bitWidth destination lhs rhs => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowBitOr bitWidth {bitWidth} is not admitted"
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      writeTemp machine destination (left ||| right)
  | .narrowBitXor bitWidth destination lhs rhs => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowBitXor bitWidth {bitWidth} is not admitted"
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      writeTemp machine destination (left ^^^ right)
  | .narrowBitNot bitWidth destination source => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowBitNot bitWidth {bitWidth} is not admitted"
      let value ← readTemp machine source
      let mask := UInt64.ofNat ((Nat.pow 2 bitWidth) - 1)
      writeTemp machine destination ((value ^^^ UInt64.ofNat 18446744073709551615) &&& mask)
  | .narrowShl bitWidth destination lhs rhs => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowShl bitWidth {bitWidth} is not admitted"
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let shift := right.toNat
      if shift ≥ 64 then
        modelError "invalid shift"
      else
        let shifted := Nat.shiftLeft left.toNat shift
        let limit := Nat.pow 2 bitWidth
        if shifted ≥ limit then
          modelError s!"UInt{bitWidth} shift overflow"
        else
          writeTemp machine destination (UInt64.ofNat shifted)
  | .narrowShr bitWidth destination lhs rhs => do
      unless bitWidth == 8 || bitWidth == 16 || bitWidth == 32 do
        modelError s!"narrowShr bitWidth {bitWidth} is not admitted"
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let shift := right.toNat
      if shift ≥ 64 then
        modelError "invalid shift"
      else
        writeTemp machine destination
          (UInt64.ofNat (Nat.shiftRight left.toNat shift))
  | .boolNot destination source => do
      let value ← readTemp machine source
      writeTemp machine destination (if value == 0 then 1 else 0)
  | .boolAnd destination lhs rhs => do
      -- Strict: both temps already materialised; bitwise == logical on 0/1.
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      writeTemp machine destination
        (if left != 0 && right != 0 then 1 else 0)
  | .boolOr destination lhs rhs => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      writeTemp machine destination
        (if left != 0 || right != 0 then 1 else 0)
  | .compare destination lhs rhs op => do
      let left ← readTemp machine lhs
      let right ← readTemp machine rhs
      let flag : Bool :=
        match op with
        | .eq => left == right
        | .ne => left != right
        | .lt => left < right
        | .le => left ≤ right
        | .gt => left > right
        | .ge => left ≥ right
      writeTemp machine destination (if flag then 1 else 0)
  | .assert condition => do
      let value ← readTemp machine condition
      if value != 0 then
        pure machine
      else
        modelError "assert condition is false"
  | .storeState field source => do
      let previous ← requireStorage machine field
      unless previous.size == 8 do
        modelError s!"evicted state at '{field.key}' is not exactly eight bytes"
      let value ← readTemp machine source
      pure { machine with
        storage := storagePut machine.storage field.key (encodeUInt64LE value) }
  | .narrowStoreState bitWidth field source => do
      let bw := bitWidth / 8
      unless bw == 1 || bw == 2 || bw == 4 do
        modelError s!"narrowStoreState bitWidth {bitWidth} is not admitted"
      let previous ← requireStorage machine field
      unless previous.size == bw do
        modelError s!"evicted state at '{field.key}' is not exactly {bw} bytes"
      let value ← readTemp machine source
      pure { machine with
        storage := storagePut machine.storage field.key (encodeUIntLE value bw) }
  | .setLayout marker value =>
      if (storageLookup? machine.storage marker.key).isSome then
        modelError "layout marker unexpectedly exists before commit"
      else
        .ok { machine with
          storage := storagePut machine.storage marker.key (encodeUInt64LE value) }
  | .setReturnData _byteLen source => do
      if machine.returned.isSome then
        modelError "return data was already set"
      let value ← readTemp machine source
      pure { machine with returned := some value }
  | .returnNone =>
      pure { machine with halted := true }
  | .returnValue source => do
      -- PureFn body return: halt the current frame with a value.
      let value ← readTemp machine source
      pure { machine with returned := some value, halted := true }
  | .callFn fnIndex destination args => do
      let some fnIR := machine.fns[fnIndex]? |
        modelError s!"callFn index {fnIndex} is outside the pureFn table"
      -- Acyclic pureFns: depth is bounded by the table size.
      if machine.callDepth >= machine.fns.size then
        modelError "pureFn call depth exceeds the pureFn table size"
      unless args.size == fnIR.paramCount do
        modelError s!"callFn arity mismatch for pureFn '{fnIR.name}'"
      let mut argValues : Array U64 := #[]
      for arg in args do
        argValues := argValues.push (← readTemp machine arg)
      let mut calleeTemps : Array (Option U64) :=
        Array.replicate fnIR.tempCount none
      for i in [0:argValues.size] do
        calleeTemps := calleeTemps.set! i (some argValues[i]!)
      let callee : Machine := {
        storage := machine.storage
        temps := calleeTemps
        returned := none
        halted := false
        logs := machine.logs
        eventNames := machine.eventNames
        errorNames := machine.errorNames
        fns := machine.fns
        callDepth := machine.callDepth + 1
      }
      match runOperations input deposit fnIR.operations.toList callee with
      | .ok result =>
          match result.returned with
          | some value =>
              writeTemp {
                machine with
                storage := result.storage
                logs := result.logs
              } destination value
          | none =>
              modelError s!"pureFn '{fnIR.name}' did not return a value"
      | .error reason => .error reason
  | .emitEvent eventIndex args => do
      let some name := machine.eventNames[eventIndex]? |
        modelError s!"event index {eventIndex} is outside the declared table"
      let mut values : Array U64 := #[]
      for arg in args do
        values := values.push (← readTemp machine arg)
      pure { machine with
        logs := machine.logs.push s!"pf-event:{name}:{hexArgs values}" }
  | .promiseAccount receiver method args => do
      -- Fire-and-forget: record the promise and continue. Args-hex is the
      -- concatenation of each UInt64 argument's 8-byte little-endian payload
      -- as 16 lowercase hex chars (matches the WAT i64.store LE serialization).
      let mut payloadHex := ""
      for arg in args do
        let value ← readTemp machine arg
        let le := encodeUInt64LE value
        for i in [0:8] do
          let b := le[i]!.toNat
          let hi := b / 16
          let lo := b % 16
          let digit (d : Nat) : Char :=
            if d < 10 then Char.ofNat (48 + d) else Char.ofNat (87 + d)
          payloadHex := payloadHex.push (digit hi) |>.push (digit lo)
      pure { machine with
        logs := machine.logs.push s!"pf-promise:{receiver}:{method}:{payloadHex}" }
  | .revertError errorIndex args => do
      let some name := machine.errorNames[errorIndex]? |
        modelError s!"error index {errorIndex} is outside the declared table"
      let mut values : Array U64 := #[]
      for arg in args do
        values := values.push (← readTemp machine arg)
      modelError s!"pf-error:{name}:{hexArgs values}"
  | .ifRegion condition thenOps elseOps => do
      let value ← readTemp machine condition
      if value != 0 then
        runOperations input deposit thenOps.toList machine
      else
        runOperations input deposit elseOps.toList machine
  | .switchRegion scrutinee cases defaultOps => do
      let scrut ← readTemp machine scrutinee
      let selected := cases.toList.findSome? fun (caseValue, ops) =>
        if caseValue == scrut then some ops else none
      match selected with
      | some ops => runOperations input deposit ops.toList machine
      | none => runOperations input deposit defaultOps.toList machine
  | .forRegion varTemp initial counterTemp maxIterations
        condOps condition bodyOps updateOps updateValue => do
      -- Seed induction from the initial expression temp and zero the bound
      -- counter. Bound is checked at the back edge after the body (reference
      -- noteBackEdge): body runs first; trap if completed ≥ N; then increment.
      -- A return/revert inside the body completes before the check. Latch
      -- update is unchecked i+1 (body only runs while i < end ≤ UInt64.max).
      let initVal ← readTemp machine initial
      let machine ← writeTemp machine varTemp initVal
      let machine ← writeTemp machine counterTemp 0
      runForRegion input deposit machine varTemp counterTemp maxIterations
        condOps condition bodyOps updateOps updateValue

private partial def runForRegion (input : ByteArray) (deposit : Deposit)
    (machine : Machine) (varTemp counterTemp maxIterations : Nat)
    (condOps : Array Targets.Near.Operation) (condition : Nat)
    (bodyOps : Array Targets.Near.Operation)
    (updateOps : Array Targets.Near.Operation) (updateValue : Nat) :
    Except String Machine := do
  let machine ← runOperations input deposit condOps.toList machine
  if machine.halted then pure machine
  else
    let condVal ← readTemp machine condition
    if condVal == 0 then
      pure machine
    else
      -- Body first (may return/revert/halt before the bound check).
      let machine ← runOperations input deposit bodyOps.toList machine
      if machine.halted then pure machine
      else
        let count ← readTemp machine counterTemp
        -- Back-edge placement: after the (N+1)-th completed body, trap.
        if count.toNat ≥ maxIterations then
          modelError "loop bound exceeded"
        else
          let machine ← writeTemp machine counterTemp (count + 1)
          let machine ← runOperations input deposit updateOps.toList machine
          if machine.halted then pure machine
          else
            let updated ← readTemp machine updateValue
            let machine ← writeTemp machine varTemp updated
            runForRegion input deposit machine varTemp counterTemp maxIterations
              condOps condition bodyOps updateOps updateValue

private partial def runOperations (input : ByteArray) (deposit : Deposit) :
    List Targets.Near.Operation → Machine → Except String Machine
  | [], machine => .ok machine
  | operation :: remaining, machine =>
      match step input deposit machine operation with
      | .ok next =>
          if next.halted then .ok next
          else runOperations input deposit remaining next
      | .error reason => .error reason

end

/-- Pure deterministic model of the typed recipe. A trap restores the exact
pre-call storage snapshot, modeling NEAR's receipt-local rollback contract.
This is not a NEAR VM, sandbox, gas, or protocol-profile execution. -/
private def execute (method : Targets.Near.MethodIR) (storage : HostStorage)
    (input : ByteArray) (deposit : Deposit)
    (eventNames errorNames : Array String := #[])
    (fns : Array Targets.Near.FnIR := #[]) : Outcome :=
  let initial : Machine := {
    storage
    temps := Array.replicate method.tempCount none
    eventNames := eventNames
    errorNames := errorNames
    fns := fns
  }
  match runOperations input deposit method.operations.toList initial with
  | .ok result => .success result.storage result.returned result.logs
  | .error reason => .trapped storage reason

private def requireSuccess (label : String) : Outcome → IO (HostStorage × Option U64 × Array String)
  | .success storage returned logs => pure (storage, returned, logs)
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

private def testCheckedSubModel : IO Unit := do
  let deposit : Deposit := { lowWord := 0, highWord := 0 }
  let machine : Machine := {
    storage := #[]
    temps := #[some 7, some 5, none]
  }
  let success ← match step ByteArray.empty deposit machine (.checkedSub 2 0 1) with
    | .ok value => pure value
    | .error reason => throw <| IO.userError s!"checked-sub model: {reason}"
  expect (success.temps[2]? == some (some 2))
    "checked-sub model must write the exact UInt64 difference"
  match step ByteArray.empty deposit machine (.checkedSub 2 1 0) with
  | .error reason =>
      expect (reason.contains "underflow")
        s!"checked-sub model must classify underflow, got {reason}"
  | .ok _ => throw <| IO.userError "checked-sub model accepted 5 - 7"

private def testCompareAssertModel : IO Unit := do
  let deposit : Deposit := { lowWord := 0, highWord := 0 }
  let machine : Machine := {
    storage := #[]
    temps := #[some 7, some 5, none]
  }
  let ops : Array (Targets.Near.ComparisonOp × (U64 → U64 → Bool)) := #[
    (.eq, fun a b => a == b),
    (.ne, fun a b => a != b),
    (.lt, fun a b => a < b),
    (.le, fun a b => a ≤ b),
    (.gt, fun a b => a > b),
    (.ge, fun a b => a ≥ b)
  ]
  for pair in ops do
    let (op, pred) := pair
    let success ← match step ByteArray.empty deposit machine (.compare 2 0 1 op) with
      | .ok value => pure value
      | .error reason => throw <| IO.userError s!"compare model {repr op}: {reason}"
    let expected : U64 := if pred 7 5 then 1 else 0
    expect (success.temps[2]? == some (some expected))
      s!"compare model {repr op} must write the exact UInt64 0/1 flag"
  let trueMachine ← match step ByteArray.empty deposit machine (.compare 2 0 1 .ge) with
    | .ok value => pure value
    | .error reason => throw <| IO.userError s!"compare model ge: {reason}"
  match step ByteArray.empty deposit trueMachine (.assert 2) with
  | .ok _ => pure ()
  | .error reason => throw <| IO.userError s!"assert model true: {reason}"
  let falseMachine ← match step ByteArray.empty deposit machine (.compare 2 1 0 .ge) with
    | .ok value => pure value
    | .error reason => throw <| IO.userError s!"compare model ge-false: {reason}"
  match step ByteArray.empty deposit falseMachine (.assert 2) with
  | .error reason =>
      expect (reason.contains "assert")
        s!"assert model must classify false condition, got {reason}"
  | .ok _ => throw <| IO.userError "assert model accepted a zero condition"

def runCheckedSubFast : IO Unit := do
  testCheckedSubModel
  testCompareAssertModel
  IO.println "Tests.Materialization.NearHostModel.checkedSub: ok"

def runCompareAssertFast : IO Unit := do
  testCompareAssertModel
  IO.println "Tests.Materialization.NearHostModel.compareAssert: ok"

/-- Guarded counter: assert count >= delta before checked subtraction. -/
private def guardedCounterSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Guarded where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(i : UInt64) do\n" ++
  "    count := i\n\n" ++
  "  entry decrement(delta : UInt64) : UInt64 do\n" ++
  "    assert count >= delta\n" ++
  "    count := count - delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private def guardedCounterModuleNameV1 : String := "Examples.Guarded"

private def operationKinds (operations : Array Targets.Near.Operation) :
    Array String :=
  operations.map fun op =>
    match op with
    | .checkInputLen _ => "checkInputLen"
    | .requireZeroAttachedDeposit => "requireZeroAttachedDeposit"
    | .requireLayoutAbsent _ => "requireLayoutAbsent"
    | .requireLayout _ _ => "requireLayout"
    | .zeroState _ => "zeroState"
    | .narrowZeroState _ _ => "narrowZeroState"
    | .literal _ _ => "literal"
    | .loadParam _ _ => "loadParam"
    | .narrowLoadParam _ _ _ => "narrowLoadParam"
    | .loadState _ _ => "loadState"
    | .narrowLoadState _ _ _ => "narrowLoadState"
    | .checkedAdd _ _ _ => "checkedAdd"
    | .checkedSub _ _ _ => "checkedSub"
    | .checkedMul _ _ _ => "checkedMul"
    | .checkedDiv _ _ _ => "checkedDiv"
    | .checkedMod _ _ _ => "checkedMod"
    | .signedCheckedAdd _ _ _ => "signedCheckedAdd"
    | .signedCheckedSub _ _ _ => "signedCheckedSub"
    | .signedCheckedMul _ _ _ => "signedCheckedMul"
    | .signedCheckedDiv _ _ _ => "signedCheckedDiv"
    | .signedCheckedMod _ _ _ => "signedCheckedMod"
    | .signedCompare _ _ _ _ => "signedCompare"
    | .checkedNeg _ _ => "checkedNeg"
    | .sar _ _ _ => "sar"
    | .bitAnd _ _ _ => "bitAnd"
    | .bitOr _ _ _ => "bitOr"
    | .bitXor _ _ _ => "bitXor"
    | .shl _ _ _ => "shl"
    | .shr _ _ _ => "shr"
    | .bitNot _ _ => "bitNot"
    | .narrowCheckedAdd _ _ _ _ => "narrowCheckedAdd"
    | .narrowCheckedSub _ _ _ _ => "narrowCheckedSub"
    | .narrowCheckedMul _ _ _ _ => "narrowCheckedMul"
    | .narrowCheckedDiv _ _ _ _ => "narrowCheckedDiv"
    | .narrowCheckedMod _ _ _ _ => "narrowCheckedMod"
    | .narrowBitAnd _ _ _ _ => "narrowBitAnd"
    | .narrowBitOr _ _ _ _ => "narrowBitOr"
    | .narrowBitXor _ _ _ _ => "narrowBitXor"
    | .narrowBitNot _ _ _ => "narrowBitNot"
    | .narrowShl _ _ _ _ => "narrowShl"
    | .narrowShr _ _ _ _ => "narrowShr"
    | .boolNot _ _ => "boolNot"
    | .boolAnd _ _ _ => "boolAnd"
    | .boolOr _ _ _ => "boolOr"
    | .storeState _ _ => "storeState"
    | .narrowStoreState _ _ _ => "narrowStoreState"
    | .setLayout _ _ => "setLayout"
    | .setReturnData _ _ => "setReturnData"
    | .compare _ _ _ op =>
        match op with
        | .eq => "compare.eq"
        | .ne => "compare.ne"
        | .lt => "compare.lt"
        | .le => "compare.le"
        | .gt => "compare.gt"
        | .ge => "compare.ge"
    | .assert _ => "assert"
    | .emitEvent .. => "emitEvent"
    | .promiseAccount .. => "promiseAccount"
    | .revertError .. => "revertError"
    | .returnNone => "returnNone"
    | .ifRegion .. => "ifRegion"
    | .switchRegion .. => "switchRegion"
    | .forRegion .. => "forRegion"
    | .callFn .. => "callFn"
    | .returnValue _ => "returnValue"

private def expectContains (haystack needle label : String) : IO Unit :=
  expect (haystack.contains needle) s!"{label}: missing WAT substring {needle}"

/-- If/else multi-block program for the NEAR region lanes. -/
private def ifFlowSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program IfFlow where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    if count > 0 then\n" ++
  "      count := count + delta\n" ++
  "    else\n" ++
  "      count := delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private unsafe def testIfFlowProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source ← liftResult (← session.selectProgramV1
    ifFlowSourceText "<near-if-flow>"
    "Examples.IfFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let bump := plan.entries[0]!
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0) (.literal 0))
        #[.store { fieldIndex := 0, value := .checkedAdd (.stateLoad 0) (.param 0) }]
        #[.store { fieldIndex := 0, value := .param 0 }],
      .returnValue (.stateLoad 0)])
    "IfFlow bump must lower the branch diamond then join return"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let ir2 ← liftResult <| Targets.Near.irFromCapability capability
  expect (ir == ir2) "IfFlow IR rebuild must be structure-identical"
  let bumpIR ← findMethod ir "bump"
  let regionOps := bumpIR.operations.filter fun op =>
    match op with | .ifRegion .. => true | _ => false
  expect (regionOps.size == 1)
    s!"IfFlow IR must contain exactly one if-region, got {regionOps.size}"
  -- Host-model execution: init(0) → bump(3) takes else (state 3), bump(2) takes then (5).
  let initializer ← findMethod ir "init"
  let get ← findMethod ir "get"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let (storage0, _, _) ← requireSuccess "if-flow init"
    (execute initializer empty (encodeUInt64LE 0) { lowWord := 0, highWord := 0 })
  let (storage1, ret1, _) ← requireSuccess "if-flow else"
    (execute bumpIR storage0 (encodeUInt64LE 3) { lowWord := 0, highWord := 0 })
  expect (ret1 == some 3 && storedUInt64? storage1 field.key == some 3)
    "if-flow else branch must store delta (3)"
  let (storage2, ret2, _) ← requireSuccess "if-flow then"
    (execute bumpIR storage1 (encodeUInt64LE 2) { lowWord := 0, highWord := 0 })
  expect (ret2 == some 5 && storedUInt64? storage2 field.key == some 5)
    "if-flow then branch must store count+delta (5)"
  let (_, retGet, _) ← requireSuccess "if-flow get"
    (execute get storage2 ByteArray.empty { lowWord := 0, highWord := 0 })
  expect (retGet == some 5) "if-flow view must return 5"
  -- WAT: nested if with i64 condition.
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "if-flow: missing .wat artifact"
  expectContains wat.contents "(if (local.get $t" "if-flow WAT if condition"
  expectContains wat.contents "(else" "if-flow WAT else"
  expectContains wat.contents "(i64.gt_u" "if-flow WAT gt comparison"
  expectContains wat.contents "(i64.add" "if-flow WAT then add"

/-- Match on UInt64 literals: host-model switch execution per case. -/
private unsafe def testMatchProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MatchUint where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry apply(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | 0 => do\n" ++
    "      return count\n" ++
    "    | 1 => do\n" ++
    "      count := count + 1\n" ++
    "    | _ => do\n" ++
    "      count := delta\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-match>" "Examples.MatchUint" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let applyIR ← findMethod ir "apply"
  let switchOps := applyIR.operations.filter fun op =>
    match op with | .switchRegion .. => true | _ => false
  expect (switchOps.size == 1)
    s!"MatchUint IR must contain exactly one switch-region, got {switchOps.size}"
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let (storage0, _, _) ← requireSuccess "match init"
    (execute initializer #[] (encodeUInt64LE 7) { lowWord := 0, highWord := 0 })
  let (storage1, ret1, _) ← requireSuccess "match case0"
    (execute applyIR storage0 (encodeUInt64LE 0) { lowWord := 0, highWord := 0 })
  expect (ret1 == some 7 && storedUInt64? storage1 field.key == some 7)
    "match case 0 must return count without writing"
  let (storage2, ret2, _) ← requireSuccess "match case1"
    (execute applyIR storage1 (encodeUInt64LE 1) { lowWord := 0, highWord := 0 })
  expect (ret2 == some 8 && storedUInt64? storage2 field.key == some 8)
    "match case 1 must increment"
  let (storage3, ret3, _) ← requireSuccess "match default"
    (execute applyIR storage2 (encodeUInt64LE 5) { lowWord := 0, highWord := 0 })
  expect (ret3 == some 5 && storedUInt64? storage3 field.key == some 5)
    "match default must store the scrutinee"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "match: missing .wat artifact"
  expectContains wat.contents "(if (i64.eq" "match WAT case comparison"
  expectContains wat.contents "(else" "match WAT else chain"

/-- Assert inside a branch traps only when that branch is taken. -/
private unsafe def testBranchAssertTrap
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BranchAssert where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry withdraw(delta : UInt64) : UInt64 do\n" ++
    "    if delta > 0 then\n" ++
    "      assert count >= delta\n" ++
    "      count := count - delta\n" ++
    "    else\n" ++
    "      count := 0\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-branch-assert>" "Examples.BranchAssert" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let withdraw ← findMethod ir "withdraw"
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let (storage0, _, _) ← requireSuccess "branch-assert init"
    (execute initializer #[] (encodeUInt64LE 5) { lowWord := 0, highWord := 0 })
  -- delta=3 → then branch, assert passes, state 2.
  let (storage1, ret1, _) ← requireSuccess "branch-assert pass"
    (execute withdraw storage0 (encodeUInt64LE 3) { lowWord := 0, highWord := 0 })
  expect (ret1 == some 2 && storedUInt64? storage1 field.key == some 2)
    "branch-assert: taken branch must apply the subtraction"
  -- delta=9 → then branch, assert fails → trap, storage rolled back.
  match execute withdraw storage0 (encodeUInt64LE 9) { lowWord := 0, highWord := 0 } with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some 5)
        s!"branch-assert: trap must roll back to pre-call storage, got {reason}"
  | .success _ _ _ =>
      throw <| IO.userError "branch-assert: underflowing branch must trap"
  -- delta=0 → else branch, no assert fires, state 0.
  let (storage3, ret3, _) ← requireSuccess "branch-assert else"
    (execute withdraw storage0 (encodeUInt64LE 0) { lowWord := 0, highWord := 0 })
  expect (ret3 == some 0 && storedUInt64? storage3 field.key == some 0)
    "branch-assert: else branch must not fire the assert"

private unsafe def testGuardedCounterProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source ← liftResult (← session.selectProgramV1
    guardedCounterSourceText "<near-host-guarded>"
    guardedCounterModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let ir2 ← liftResult <| Targets.Near.irFromCapability capability
  expect (ir == ir2) "guarded: irFromCapability must be byte-identical on rebuild"
  let initializer ← findMethod ir "init"
  let decrement ← findMethod ir "decrement"
  let get ← findMethod ir "get"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zeroDeposit : Deposit := { lowWord := 0, highWord := 0 }

  -- Pin method operations: compare.ge then assert before checkedSub.
  let kinds := operationKinds decrement.operations
  expect (kinds.contains "compare.ge")
    s!"guarded: decrement must lower comparison, got {kinds}"
  expect (kinds.contains "assert")
    s!"guarded: decrement must lower assert, got {kinds}"
  expect (kinds.contains "checkedSub")
    s!"guarded: decrement must lower checkedSub, got {kinds}"
  let some geIdx := kinds.findIdx? (· == "compare.ge") |
    throw <| IO.userError "guarded: missing compare.ge index"
  let some assertIdx := kinds.findIdx? (· == "assert") |
    throw <| IO.userError "guarded: missing assert index"
  let some subIdx := kinds.findIdx? (· == "checkedSub") |
    throw <| IO.userError "guarded: missing checkedSub index"
  expect (geIdx < assertIdx && assertIdx < subIdx)
    s!"guarded: expected compare→assert→sub order, got {geIdx}/{assertIdx}/{subIdx}"
  match decrement.operations[geIdx]? with
  | some (.compare destination lhs rhs .ge) =>
      expect (destination + 1 > destination)
        s!"guarded: compare destination must be a local slot, got {destination}/{lhs}/{rhs}"
  | other =>
      throw <| IO.userError s!"guarded: expected compare.ge at {geIdx}, got {repr other}"
  match decrement.operations[assertIdx]? with
  | some (.assert condition) =>
      match decrement.operations[geIdx]? with
      | some (.compare destination _ _ .ge) =>
          expect (condition == destination)
            s!"guarded: assert must consume compare destination, got {condition} vs {destination}"
      | _ => pure ()
  | other =>
      throw <| IO.userError s!"guarded: expected assert at {assertIdx}, got {repr other}"

  let (initialized, initReturn, _) ← requireSuccess "guarded init" <|
    execute initializer empty (encodeUInt64LE 10) zeroDeposit
  expect (initReturn.isNone) "guarded init must not set return data"
  expect (storedUInt64? initialized field.key == some 10)
    "guarded init must store seed 10"

  let (afterOk, decReturn, _) ← requireSuccess "guarded decrement success" <|
    execute decrement initialized (encodeUInt64LE 3) zeroDeposit
  expect (decReturn == some 7 && storedUInt64? afterOk field.key == some 7)
    "guarded: 10 - 3 must yield 7 under assert"

  let (_, getReturn, _) ← requireSuccess "guarded view" <|
    execute get afterOk ByteArray.empty zeroDeposit
  expect (getReturn == some 7) "guarded view must observe committed 7"

  -- Underflowing decrement is trapped by the assert (not checkedSub).
  match execute decrement afterOk (encodeUInt64LE 8) zeroDeposit with
  | .trapped storage reason =>
      expect (storage == afterOk)
        "guarded underflow trap must restore pre-call storage"
      expect (reason.contains "assert")
        s!"guarded underflow must classify as assert trap, got {reason}"
  | .success .. =>
      throw <| IO.userError "guarded underflow unexpectedly succeeded"

  -- WAT text substrings for comparison op and assert trap.
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some watFile := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "guarded: missing .wat artifact"
  expectContains watFile.contents "i64.ge_u" "guarded WAT ge"
  expectContains watFile.contents "i64.extend_i32_u" "guarded WAT extend"
  expectContains watFile.contents "(if (i64.eqz" "guarded WAT assert trap"
  expectContains watFile.contents "unreachable" "guarded WAT unreachable"
  -- Deterministic rebuild of files.
  let files2 ← liftResult <| Targets.Near.buildFromCapability capability
  expect (files.map (·.contents) == files2.map (·.contents))
    "guarded: buildFromCapability must be byte-identical on rebuild"
  -- Keep plan identity stable for comparison-free consumers.
  expect (plan.programName == "Guarded") "guarded plan program name"

private unsafe def testAllComparisonOpsWat
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- NEAR requires KV state + initializer; comparisons themselves are UInt64-only.
  let sourceText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program Compares where\n" ++
    "  state seed : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    seed := i\n\n" ++
    "  entry check(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    assert a == b\n" ++
    "    assert a != b\n" ++
    "    assert a < b\n" ++
    "    assert a <= b\n" ++
    "    assert a > b\n" ++
    "    assert a >= b\n" ++
    "    return a\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    sourceText "<near-host-compares>" "Examples.Compares" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let check ← findMethod ir "check"
  let kinds := operationKinds check.operations
  for expected in (#[
      "compare.eq", "compare.ne", "compare.lt",
      "compare.le", "compare.gt", "compare.ge"] : Array String) do
    expect (kinds.contains expected)
      s!"compares: missing {expected} in {kinds}"
  let assertCount := kinds.foldl (fun n k => if k == "assert" then n + 1 else n) 0
  expect (assertCount == 6)
    s!"compares: expected 6 asserts, got {assertCount}"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some watFile := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "compares: missing .wat artifact"
  for insn in (#[
      "i64.eq", "i64.ne", "i64.lt_u", "i64.le_u", "i64.gt_u", "i64.ge_u"] : Array String) do
    expectContains watFile.contents insn s!"compares WAT {insn}"

private unsafe def testAssertElseRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Assert-else is rejected at Normalize (before target). Confirm product path
  -- still fails closed and does not produce NEAR artifacts.
  let sourceText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program AssertElse where\n" ++
    "  entry f(x : UInt64) : UInt64 do\n" ++
    "    assert x > 0 else bad\n" ++
    "    return x\n" ++
    "  error bad()\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    sourceText "<near-host-assert-else>" "Examples.AssertElse" none)
  match Compiler.compileValidatedSourceV1 source with
  | .error _ => pure ()
  | .ok _ =>
      throw <| IO.userError "assert-else must fail product compile before NEAR materialization"

/-- Bool state/param remain outside the NEAR pilot; Bool results are accepted. -/
private unsafe def testBoolStateParamRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let cases : Array (String × String × String) := #[
    ("bool-state", "Examples.BoolState",
      "program BoolState where\n" ++
      "  state flag : Bool\n" ++
      "  entry ping(x : UInt64) : UInt64 do\n" ++
      "    return x\n"),
    ("bool-param", "Examples.BoolParam",
      "program BoolParam where\n" ++
      "  state count : UInt64\n" ++
      "  entry ping(flag : Bool) : UInt64 do\n" ++
      "    return count\n")
  ]
  for item in cases do
    let (label, moduleName, body) := item
    let sourceText :=
      "import ProofForgeV2\n\n" ++
      "namespace ProofForgeV2.Examples\n\n" ++
      "open ProofForgeV2.Language\n\n" ++
      body ++ "\nend ProofForgeV2.Examples\n"
    let source ← liftResult (← session.selectProgramV1
      sourceText s!"<near-host-{label}>" moduleName none)
    match Compiler.compileValidatedSourceV1 source with
    | .error _ => pure ()
    | .ok compiled =>
        -- If Normalize ever admits these, the NEAR type/signature gates must still fail closed.
        let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
        match Targets.resolveEngineeringRequirementsV1 selection compiled with
        | .error _ => pure ()
        | .ok capability =>
            match Targets.Near.planFromCapability capability with
            | .error _ => pure ()
            | .ok _ =>
                throw <| IO.userError
                  s!"{label}: Bool state/param must fail closed for NEAR"

/-- Result-kind mismatches fail closed (Typed/Normalize, or NEAR return-kind gate). -/
private unsafe def testBoolResultKindMismatchRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let cases : Array (String × String × String) := #[
    ("bool-method-returns-uint64", "Examples.BoolReturnU64",
      "program BoolReturnU64 where\n" ++
      "  state count : UInt64\n\n" ++
      "  init(i : UInt64) do\n" ++
      "    count := i\n\n" ++
      "  view positive() : Bool do\n" ++
      "    return count\n"),
    ("uint64-method-returns-bool", "Examples.U64ReturnBool",
      "program U64ReturnBool where\n" ++
      "  state count : UInt64\n\n" ++
      "  init(i : UInt64) do\n" ++
      "    count := i\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return count > 0\n")
  ]
  for item in cases do
    let (label, moduleName, body) := item
    let sourceText :=
      "import ProofForgeV2\n\n" ++
      "namespace ProofForgeV2.Examples\n\n" ++
      "open ProofForgeV2.Language\n\n" ++
      body ++ "\nend ProofForgeV2.Examples\n"
    let source ← liftResult (← session.selectProgramV1
      sourceText s!"<near-host-{label}>" moduleName none)
    match Compiler.compileValidatedSourceV1 source with
    | .error _ => pure ()
    | .ok compiled =>
        let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
        match Targets.resolveEngineeringRequirementsV1 selection compiled with
        | .error _ => pure ()
        | .ok capability =>
            match Targets.Near.planFromCapability capability with
            | .error _ => pure ()
            | .ok _ =>
                throw <| IO.userError
                  s!"{label}: result-kind mismatch must fail closed for NEAR"

/-- Wave-A bool-result defensive negative flipped to a positive plan accept. -/
private unsafe def testBoolResultAccepted
    (session : Language.Loader.ParserSession) : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoolResult where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  view positive() : Bool do\n" ++
    "    return count > 0\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    sourceText "<near-host-bool-result>" "Examples.BoolResult" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let positive ← match plan.entries.find? (·.name == "positive") with
    | some method => pure method
    | none => throw <| IO.userError "bool-result: missing positive method"
  expect (positive.resultKind == .bool && positive.mode == .view)
    "bool-result: positive must be a Bool view"
  expect (positive.body.any fun s => match s with
      | .returnValue (.compare .gt (.stateLoad 0) (.literal 0)) => true
      | _ => false)
    "bool-result: positive body must return the count > 0 compare"

/-- Full BoolPredicate product path: mixed UInt64 + Bool entry/view results. -/
private def boolPredicateSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program BoolPredicate where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(i : UInt64) do\n" ++
  "    count := i\n\n" ++
  "  entry add(amount : UInt64) : UInt64 do\n" ++
  "    count := count + amount\n" ++
  "    return count\n\n" ++
  "  view positive() : Bool do\n" ++
  "    return count > 0\n\n" ++
  "  entry equalsCount(d : UInt64) : Bool do\n" ++
  "    return count == d\n\n" ++
  "end ProofForgeV2.Examples\n"

private def boolPredicateModuleNameV1 : String := "Examples.BoolPredicate"

private def findPlanMethod (plan : Targets.Near.Plan) (name : String) :
    IO Targets.Near.Method :=
  match plan.entries.find? (fun method => method.name == name) with
  | some method => pure method
  | none =>
      if plan.initializer.name == name then pure plan.initializer
      else throw <| IO.userError s!"plan is missing method '{name}'"

private unsafe def testBoolPredicateProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source ← liftResult (← session.selectProgramV1
    boolPredicateSourceText "<near-host-bool-predicate>"
    boolPredicateModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let ir2 ← liftResult <| Targets.Near.irFromCapability capability
  expect (ir == ir2) "bool-predicate: irFromCapability must be byte-identical on rebuild"

  expect (plan.initializer.resultKind == .unit)
    "bool-predicate: init result kind must be unit"
  let addMethod ← findPlanMethod plan "add"
  let positiveMethod ← findPlanMethod plan "positive"
  let equalsMethod ← findPlanMethod plan "equalsCount"
  expect (addMethod.resultKind == .uint64 && addMethod.mode == .mutate)
    "bool-predicate: add must be UInt64 mutate"
  expect (positiveMethod.resultKind == .bool && positiveMethod.mode == .view)
    "bool-predicate: positive must be Bool view"
  expect (equalsMethod.resultKind == .bool && equalsMethod.mode == .mutate)
    "bool-predicate: equalsCount must be Bool entry"

  let initializer ← findMethod ir "init"
  let add ← findMethod ir "add"
  let positive ← findMethod ir "positive"
  let equalsCount ← findMethod ir "equalsCount"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zeroDeposit : Deposit := { lowWord := 0, highWord := 0 }

  -- Pin Bool method ops: compare temp feeds setReturnData (no assert).
  let positiveKinds := operationKinds positive.operations
  expect (positiveKinds.contains "compare.gt")
    s!"bool-predicate: positive must lower gt compare, got {positiveKinds}"
  expect (positiveKinds.contains "setReturnData")
    s!"bool-predicate: positive must set return data, got {positiveKinds}"
  expect (!positiveKinds.contains "assert")
    s!"bool-predicate: positive must not assert, got {positiveKinds}"
  let equalsKinds := operationKinds equalsCount.operations
  expect (equalsKinds.contains "compare.eq")
    s!"bool-predicate: equalsCount must lower eq compare, got {equalsKinds}"
  expect (equalsKinds.contains "setReturnData")
    s!"bool-predicate: equalsCount must set return data, got {equalsKinds}"

  let (initialized, initReturn, _) ← requireSuccess "bool-predicate init" <|
    execute initializer empty (encodeUInt64LE 0) zeroDeposit
  expect (initReturn.isNone) "bool-predicate init must not set return data"
  expect (storedUInt64? initialized field.key == some 0)
    "bool-predicate init must store seed 0"

  let (_, posFalse, _) ← requireSuccess "bool-predicate positive false" <|
    execute positive initialized ByteArray.empty zeroDeposit
  expect (posFalse == some 0)
    "bool-predicate: positive on count=0 must return Bool false as i64 0"

  let (afterAdd, addReturn, _) ← requireSuccess "bool-predicate add" <|
    execute add initialized (encodeUInt64LE 7) zeroDeposit
  expect (addReturn == some 7 && storedUInt64? afterAdd field.key == some 7)
    "bool-predicate: add must return UInt64 7 and store it"

  let (_, posTrue, _) ← requireSuccess "bool-predicate positive true" <|
    execute positive afterAdd ByteArray.empty zeroDeposit
  expect (posTrue == some 1)
    "bool-predicate: positive on count=7 must return Bool true as i64 1"

  let (_, eqTrue, _) ← requireSuccess "bool-predicate equals true" <|
    execute equalsCount afterAdd (encodeUInt64LE 7) zeroDeposit
  expect (eqTrue == some 1)
    "bool-predicate: equalsCount(7) on count=7 must return true"

  let (_, eqFalse, _) ← requireSuccess "bool-predicate equals false" <|
    execute equalsCount afterAdd (encodeUInt64LE 3) zeroDeposit
  expect (eqFalse == some 0)
    "bool-predicate: equalsCount(3) on count=7 must return false"

  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some watFile := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "bool-predicate: missing .wat artifact"
  let some abiFile := files.find? (fun f => f.path.endsWith ".near-abi.json") |
    throw <| IO.userError "bool-predicate: missing .near-abi.json artifact"
  expectContains watFile.contents "i64.gt_u" "bool-predicate WAT gt"
  expectContains watFile.contents "i64.eq" "bool-predicate WAT eq"
  expectContains watFile.contents "i64.extend_i32_u" "bool-predicate WAT extend"
  expectContains watFile.contents "export \"positive\"" "bool-predicate WAT positive export"
  expectContains watFile.contents "export \"equalsCount\"" "bool-predicate WAT equalsCount export"
  expectContains watFile.contents "pf_value_return" "bool-predicate WAT value_return"
  -- Bool methods return the compare temp via the same 8-byte LE convention.
  expectContains watFile.contents "(call $pf_value_return (i64.const 8)"
    "bool-predicate WAT return length"
  expectContains abiFile.contents "\"returns\":\"bool\""
    "bool-predicate ABI must mark Bool method results"
  expectContains abiFile.contents "\"returns\":\"u64-le\""
    "bool-predicate ABI must retain UInt64 method results"
  expectContains abiFile.contents "\"name\":\"positive\""
    "bool-predicate ABI must list positive"
  expectContains abiFile.contents "\"name\":\"add\""
    "bool-predicate ABI must list add"
  -- Deterministic rebuild of files.
  let files2 ← liftResult <| Targets.Near.buildFromCapability capability
  expect (files.map (·.contents) == files2.map (·.contents))
    "bool-predicate: buildFromCapability must be byte-identical on rebuild"
  expect (plan.programName == "BoolPredicate") "bool-predicate plan program name"

/-- Early valued return in the then arm with a trailing join (the mirror
    guard-clause shape): the trailing join folds after the region, and the
    closed arm gains a hard `return` after value_return so the early path
    does not fall through into the join. -/
private unsafe def testEarlyReturnJoinProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EarlyReturn where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry cap(limit : UInt64) : UInt64 do\n" ++
    "    if count > limit then\n" ++
    "      return limit\n" ++
    "    else\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-early-return>" "Examples.EarlyReturn" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let cap := plan.entries[0]!
  expect (cap.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0) (.param 0))
        #[.returnValue (.param 0)]
        #[.store { fieldIndex := 0, value := .checkedAdd (.stateLoad 0) (.literal 1) }],
      .returnValue (.stateLoad 0)])
    "EarlyReturn cap must fold the trailing join return after the region"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let capIR ← findMethod ir "cap"
  let some region := capIR.operations.find? (fun op => match op with
    | .ifRegion .. => true | _ => false) |
    throw <| IO.userError "EarlyReturn cap IR must contain the if-region"
  match region with
  | .ifRegion _ thenOps _ =>
      expect (thenOps.back? == some .returnNone)
        "EarlyReturn closed arm must gain a hard return after value_return"
  | _ => throw <| IO.userError "EarlyReturn cap IR must contain the if-region"
  -- Host-model execution: init(10) → cap(5) early-returns 5 (state stays 10);
  -- cap(20) falls through the join to 11.
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let (storage0, _, _) ← requireSuccess "early-return init"
    (execute initializer empty (encodeUInt64LE 10) zero)
  let (storage1, ret1, _) ← requireSuccess "early-return cap(5)"
    (execute capIR storage0 (encodeUInt64LE 5) zero)
  expect (ret1 == some 5 && storedUInt64? storage1 field.key == some 10)
    "early-return path must return the limit and leave state untouched"
  let (storage2, ret2, _) ← requireSuccess "early-return cap(20)"
    (execute capIR storage1 (encodeUInt64LE 20) zero)
  expect (ret2 == some 11 && storedUInt64? storage2 field.key == some 11)
    "fallthrough path must store and return count + 1"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "early-return: missing .wat artifact"
  expectContains wat.contents "(return)" "early-return WAT hard return"

/-- An early bare return inside an initializer branch arm fails closed: the
    layout-marking epilogue must run on every path. Normalize currently
    rejects explicit bare `return` at the source boundary; the Plan validator
    independently rejects an in-arm bare-return marker. -/
private unsafe def testInitEarlyBareReturnClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program InitEarlyReturn where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    if initial > 0 then\n" ++
    "      return\n" ++
    "    else\n" ++
    "      count := initial\n" ++
    "    count := 0\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  match ← session.selectProgramV1 text "<near-init-early-return>"
      "Examples.InitEarlyReturn" none with
  | .error e => throw <| IO.userError s!"InitEarlyReturn must load, got {e.render}"
  | .ok source =>
      match Compiler.compileValidatedSourceV1 source with
      | .error (.invalidProgram message) =>
          expect (message.contains "bare return")
            s!"InitEarlyReturn must fail closed at Normalize, got {message}"
      | .error e =>
          throw <| IO.userError
            s!"InitEarlyReturn must fail with invalidProgram, got {e.render}"
      | .ok _ =>
          throw <| IO.userError "InitEarlyReturn must not compile (bare return)"
  -- Validator level: an in-arm bare-return marker in the initializer body is
  -- rejected even though a final top-level marker is the canonical shape.
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 (←
    liftResult (← session.selectProgramV1 accumulatorSourceText
      "<near-early-return-plan>" accumulatorModuleNameV1 none))
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let earlyArm := {
    plan.initializer with
    body := #[
      .ifThenElse (.compare .ge (.param 0) (.literal 0))
        #[.returnNone]
        #[],
      .store { fieldIndex := 0, value := .param 0 },
      .returnNone
    ]
  }
  match Targets.Near.validatePlan { plan with initializer := earlyArm } with
  | .error (.planInvariant .near message) =>
      expect (message.contains "early bare return")
        s!"validatePlan must reject the in-arm bare return, got {message}"
  | .error e =>
      throw <| IO.userError s!"validatePlan must fail with planInvariant, got {e.render}"
  | .ok () => throw <| IO.userError "validatePlan must reject an in-arm bare return"

/-- Wave E: pureFn/localCall product path. double/quadruple fns + init/entry;
    pins Plan fn table, callFn expr, WAT `$fn_double` and call sites, and
    host-model execution init(3) → bump(2) = double(3)+quadruple(2) = 6+8 = 14. -/
private unsafe def testFnLocalCallProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program FnFlow where\n" ++
    "  state count : UInt64\n\n" ++
    "  fn double(x : UInt64) : UInt64 do\n" ++
    "    return x + x\n\n" ++
    "  fn quadruple(y : UInt64) : UInt64 do\n" ++
    "    return double(y) + double(y)\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := double(count) + quadruple(delta)\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-fn-flow>" "Examples.FnFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  -- Plan fn table: double then quadruple in source order.
  expect (plan.fns.size == 2)
    s!"fn-flow: expected two pureFns, got {plan.fns.size}"
  expect (plan.fns[0]!.name == "double" && !plan.fns[0]!.resultIsBool &&
      plan.fns[0]!.params.size == 1)
    "fn-flow: double must be UInt64 pureFn with one param"
  expect (plan.fns[1]!.name == "quadruple" && !plan.fns[1]!.resultIsBool &&
      plan.fns[1]!.params.size == 1)
    "fn-flow: quadruple must be UInt64 pureFn with one param"
  -- double body: return x + x
  expect (plan.fns[0]!.body == #[
      .returnValue (.checkedAdd (.param 0) (.param 0))])
    "fn-flow: double body must return param+param"
  -- quadruple body: return double(y) + double(y)
  expect (plan.fns[1]!.body == #[
      .returnValue (.checkedAdd
        (.callFn 0 #[.param 0])
        (.callFn 0 #[.param 0]))])
    "fn-flow: quadruple body must call double twice and add"
  -- bump: store double(count)+quadruple(delta), return count
  let bump := plan.entries[0]!
  expect (bump.body == #[
      .store {
        fieldIndex := 0
        value := .checkedAdd
          (.callFn 0 #[.stateLoad 0])
          (.callFn 1 #[.param 0])
      },
      .returnValue (.stateLoad 0)])
    "fn-flow: bump must store double(count)+quadruple(delta) then return"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let ir2 ← liftResult <| Targets.Near.irFromCapability capability
  expect (ir == ir2) "fn-flow: irFromCapability must be structure-identical on rebuild"
  expect (ir.fns.size == 2 && ir.fns[0]!.name == "double" &&
      ir.fns[1]!.name == "quadruple")
    "fn-flow: IR pureFn table must mirror the Plan"
  -- IR pureFn ops: returnValue (not setReturnData); nested callFn in quadruple.
  let doubleKinds := operationKinds ir.fns[0]!.operations
  expect (doubleKinds.contains "returnValue" && !doubleKinds.contains "setReturnData")
    s!"fn-flow: double IR must use returnValue, got {doubleKinds}"
  expect (doubleKinds.contains "checkedAdd")
    s!"fn-flow: double IR must lower checkedAdd, got {doubleKinds}"
  let quadKinds := operationKinds ir.fns[1]!.operations
  expect (quadKinds.contains "callFn" && quadKinds.contains "returnValue")
    s!"fn-flow: quadruple IR must callFn+returnValue, got {quadKinds}"
  let bumpIR ← findMethod ir "bump"
  let bumpKinds := operationKinds bumpIR.operations
  expect (bumpKinds.contains "callFn")
    s!"fn-flow: bump IR must lower callFn sites, got {bumpKinds}"
  -- Host-model: init(3) → bump(2) yields 14 = double(3)+quadruple(2) = 6+8.
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let (storage0, _, _) ← requireSuccess "fn-flow init"
    (execute initializer empty (encodeUInt64LE 3) zero #[] #[] ir.fns)
  expect (storedUInt64? storage0 field.key == some 3)
    "fn-flow init must store seed 3"
  let (storage1, ret1, _) ← requireSuccess "fn-flow bump"
    (execute bumpIR storage0 (encodeUInt64LE 2) zero #[] #[] ir.fns)
  expect (ret1 == some 14 && storedUInt64? storage1 field.key == some 14)
    "fn-flow: init(3)+bump(2) must yield double(3)+quadruple(2)=14"
  let get ← findMethod ir "get"
  let (_, retGet, _) ← requireSuccess "fn-flow get"
    (execute get storage1 ByteArray.empty zero #[] #[] ir.fns)
  expect (retGet == some 14) "fn-flow view must observe 14"
  -- WAT: pureFn definitions before exports, and call sites.
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "fn-flow: missing .wat artifact"
  expectContains wat.contents "(func $fn_double" "fn-flow WAT double func"
  expectContains wat.contents "(func $fn_quadruple" "fn-flow WAT quadruple func"
  expectContains wat.contents "(call $fn_double" "fn-flow WAT double call site"
  expectContains wat.contents "(call $fn_quadruple" "fn-flow WAT quadruple call site"
  expectContains wat.contents "(return (local.get $t" "fn-flow WAT pureFn return"
  expectContains wat.contents "export \"bump\"" "fn-flow WAT bump export"
  -- pureFn definitions are emitted before method exports.
  let beforeBump := (wat.contents.splitOn "export \"bump\"").head!
  expect (beforeBump.contains "(func $fn_double")
    "fn-flow WAT: $fn_double must appear before the bump export"
  let files2 ← liftResult <| Targets.Near.buildFromCapability capability
  expect (files.map (·.contents) == files2.map (·.contents))
    "fn-flow: buildFromCapability must be byte-identical on rebuild"
  expect (plan.programName == "FnFlow") "fn-flow plan program name"

/-- Declared event/error: emit logs the canonical pf-event message, revert
    traps with the pf-error message and rolls back. -/
private unsafe def testEmitRevertProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program EventFlow where\n" ++
    "  state count : UInt64\n\n" ++
    "  event Moved(src : UInt64, dst : UInt64)\n" ++
    "  error Cap(limit : UInt64)\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Moved(count, delta)\n" ++
    "    if count > delta then\n" ++
    "      revert Cap(delta)\n" ++
    "    else\n" ++
    "      count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-event-flow>" "Examples.EventFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  expect (plan.events.map (·.name) == #["Moved"] &&
      plan.errors.map (·.name) == #["Cap"])
    "EventFlow must carry the declared event/error bindings"
  let bump := plan.entries[0]!
  expect (bump.body == #[
      .emitEvent 0 #[.stateLoad 0, .param 0],
      .ifThenElse (.compare .gt (.stateLoad 0) (.param 0))
        #[.revertError 0 #[.param 0]]
        #[.store { fieldIndex := 0, value := .checkedAdd (.stateLoad 0) (.param 0) }],
      .returnValue (.stateLoad 0)])
    "EventFlow bump must lower emit, branch revert, join return"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let initializer ← findMethod ir "init"
  let bumpIR ← findMethod ir "bump"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let eventNames := plan.events.map (·.name)
  let errorNames := plan.errors.map (·.name)
  let (storage0, _, _) ← requireSuccess "event-flow init"
    (execute initializer empty (encodeUInt64LE 5) zero)
  -- count=5 > delta=3 → revert Cap(3): trap with the pf-error message and
  -- storage rolled back to the pre-call snapshot.
  match execute bumpIR storage0 (encodeUInt64LE 3) zero eventNames errorNames with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some 5)
        s!"event-flow revert must roll back storage, got {reason}"
      expect (reason == "pf-error:Cap:0000000000000003")
        s!"event-flow revert message must carry the declared error and arg, got {reason}"
  | .success _ _ _ =>
      throw <| IO.userError "event-flow: reverting branch must trap"
  -- count=5 < delta=7 → else: count=12, return 12, log Moved(5,7).
  let (storage1, ret1, logs1) ← requireSuccess "event-flow emit"
    (execute bumpIR storage0 (encodeUInt64LE 7) zero eventNames errorNames)
  expect (ret1 == some 12 && storedUInt64? storage1 field.key == some 12)
    "event-flow else branch must store and return count+delta"
  expect (logs1 == #["pf-event:Moved:0000000000000005,0000000000000007"])
    s!"event-flow must log the canonical pf-event message, got {logs1}"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "event-flow: missing .wat artifact"
  expectContains wat.contents "log_utf8" "event-flow WAT log import"
  expectContains wat.contents "panic_utf8" "event-flow WAT panic import"

/-- Wave F: mul/div/mod + unary bitNot product path. scale uses * / % +;
    bits returns ~x. Host-model: init(6)→scale(7,3)=14; scale(/0) traps;
    maxU64*2 traps; bits(0)=maxU64. WAT pins i64.mul/div_u/rem_u/xor. -/
private unsafe def testArithOpsProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArithOps where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry scale(factor : UInt64, divisor : UInt64) : UInt64 do\n" ++
    "    count := count * factor / divisor + count % divisor\n" ++
    "    return count\n\n" ++
    "  entry bits(x : UInt64) : UInt64 do\n" ++
    "    return ~x\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-host-arith-ops>" "Examples.ArithOps" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let some scale := plan.entries.find? (·.name == "scale") |
    throw <| IO.userError s!"arith-ops: missing scale entry, got {plan.entries.map (·.name)}"
  let some bits := plan.entries.find? (·.name == "bits") |
    throw <| IO.userError s!"arith-ops: missing bits entry, got {plan.entries.map (·.name)}"
  -- count := ((count * factor) / divisor) + (count % divisor); return count
  expect (scale.body == #[
      .store {
        fieldIndex := 0
        value := .checkedAdd
          (.checkedDiv
            (.checkedMul (.stateLoad 0) (.param 0))
            (.param 8))
          (.checkedMod (.stateLoad 0) (.param 8))
      },
      .returnValue (.stateLoad 0)])
    "arith-ops: scale must lower mul/div/mod/add store then return"
  expect (bits.body == #[.returnValue (.bitNot (.param 0))])
    "arith-ops: bits must return bitNot of param"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let ir2 ← liftResult <| Targets.Near.irFromCapability capability
  expect (ir == ir2) "arith-ops: IR rebuild must be structure-identical"
  let scaleIR ← findMethod ir "scale"
  let bitsIR ← findMethod ir "bits"
  let scaleKinds := operationKinds scaleIR.operations
  expect (scaleKinds.contains "checkedMul" && scaleKinds.contains "checkedDiv" &&
      scaleKinds.contains "checkedMod" && scaleKinds.contains "checkedAdd")
    s!"arith-ops: scale IR must lower mul/div/mod/add, got {scaleKinds}"
  let bitsKinds := operationKinds bitsIR.operations
  expect (bitsKinds.contains "bitNot")
    s!"arith-ops: bits IR must lower bitNot, got {bitsKinds}"
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let encodePair (a b : U64) : ByteArray :=
    encodeUInt64LE a ++ encodeUInt64LE b
  -- init(6) → scale(7,3) = 6*7/3 + 6%3 = 14 + 0 = 14
  let (storage0, _, _) ← requireSuccess "arith-ops init"
    (execute initializer empty (encodeUInt64LE 6) zero)
  expect (storedUInt64? storage0 field.key == some 6)
    "arith-ops init must store seed 6"
  let (storage1, ret1, _) ← requireSuccess "arith-ops scale"
    (execute scaleIR storage0 (encodePair 7 3) zero)
  expect (ret1 == some 14 && storedUInt64? storage1 field.key == some 14)
    "arith-ops: init(6)+scale(7,3) must yield 14"
  -- scale with divisor 0 traps division-by-zero and rolls back.
  match execute scaleIR storage1 (encodePair 1 0) zero with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some 14)
        "arith-ops: div-by-zero must roll back storage"
      expect (reason.contains "division by zero")
        s!"arith-ops: expected division by zero trap, got {reason}"
  | .success .. => throw <| IO.userError "arith-ops: scale(/0) must trap"
  -- maxU64 * 2 overflows.
  let maximum := UInt64.ofNat 18446744073709551615
  let (storageMax, _, _) ← requireSuccess "arith-ops max init"
    (execute initializer empty (encodeUInt64LE maximum) zero)
  match execute scaleIR storageMax (encodePair 2 1) zero with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some maximum)
        "arith-ops: mul overflow must roll back storage"
      expect (reason.contains "multiplication overflow")
        s!"arith-ops: expected mul overflow trap, got {reason}"
  | .success .. => throw <| IO.userError "arith-ops: maxU64*2 must trap"
  -- bits(0) = maxU64 (all ones)
  let (_, bitsRet, _) ← requireSuccess "arith-ops bits"
    (execute bitsIR storage1 (encodeUInt64LE 0) zero)
  expect (bitsRet == some maximum)
    s!"arith-ops: bits(0) must return maxU64, got {bitsRet}"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "arith-ops: missing .wat artifact"
  expectContains wat.contents "i64.mul" "arith-ops WAT mul"
  expectContains wat.contents "i64.div_u" "arith-ops WAT div_u"
  expectContains wat.contents "i64.rem_u" "arith-ops WAT rem_u"
  expectContains wat.contents "i64.xor" "arith-ops WAT xor"
  let files2 ← liftResult <| Targets.Near.buildFromCapability capability
  expect (files.map (·.contents) == files2.map (·.contents))
    "arith-ops: buildFromCapability must be byte-identical on rebuild"

/-- Wave G: bounded for-loop product path. addUp sums i over [n, n+4);
    scan is zero-trip; addUpTight (bounded 3 over 4 iters) traps at the
    back edge after the 4th body (reference noteBackEdge placement).
    Host: init(0)→addUp(1)=10; addUp(6)→40; scan leaves state; tight traps.
    Return-inside-body success is not pinned: Normalize bodies that close
    every path without a latch are fail-closed as degenerate one-shots.
    WAT pins loop/br_if/i64.lt_u (or ge_u)/i64.add. -/
private unsafe def testForLoopProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program LoopSum where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry addUp(n : UInt64) : UInt64 do\n" ++
    "    let limit : UInt64 := n + 4\n" ++
    "    for i in n ..< limit bounded 8 do\n" ++
    "      count := count + i\n" ++
    "    return count\n\n" ++
    "  entry scan(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n bounded 2 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n\n" ++
    "  entry addUpTight(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n + 4 bounded 3 do\n" ++
    "      count := count + i\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-host-for-loop>" "Examples.LoopSum" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let some addUp := plan.entries.find? (·.name == "addUp") |
    throw <| IO.userError s!"for-loop: missing addUp entry, got {plan.entries.map (·.name)}"
  let some scan := plan.entries.find? (·.name == "scan") |
    throw <| IO.userError s!"for-loop: missing scan entry, got {plan.entries.map (·.name)}"
  unless (plan.entries.find? (·.name == "addUpTight")).isSome do
    throw <| IO.userError s!"for-loop: missing addUpTight entry, got {plan.entries.map (·.name)}"
  -- Pin the addUp Plan shape: forLoop(var=0, init=n, cond=i<n+4, update=i+1, N=8,
  -- body=store count+i) then return count.
  expect (addUp.body == #[
      .forLoop 0
        (.param 0)
        (.compare .lt (.localTemp 0) (.checkedAdd (.param 0) (.literal 4)))
        (.checkedAdd (.localTemp 0) (.literal 1))
        8
        #[.store {
          fieldIndex := 0
          value := .checkedAdd (.stateLoad 0) (.localTemp 0)
        }],
      .returnValue (.stateLoad 0)])
    "for-loop: addUp must lower to forLoop + return"
  -- Zero-trip scan still lowers a forLoop (body may not run).
  match scan.body[0]? with
  | some (stmt : Targets.Near.Statement) =>
      match stmt with
      | .forLoop _ _ _ _ 2 _ => pure ()
      | other =>
          throw <| IO.userError s!"for-loop: scan must lower a forLoop bounded 2, got {repr other}"
  | none => throw <| IO.userError "for-loop: scan body is empty"
  expect (scan.body.size ≥ 1 && match scan.body.back? with
    | some (.returnValue (_ : Targets.Near.Expr)) => true
    | _ => false)
    "for-loop: scan must end in a return"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let ir2 ← liftResult <| Targets.Near.irFromCapability capability
  expect (ir == ir2) "for-loop: IR rebuild must be structure-identical"
  let addUpIR ← findMethod ir "addUp"
  let scanIR ← findMethod ir "scan"
  let tightIR ← findMethod ir "addUpTight"
  let addUpKinds := operationKinds addUpIR.operations
  expect (addUpKinds.contains "forRegion")
    s!"for-loop: addUp IR must contain forRegion, got {addUpKinds}"
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  -- init(0) → addUp(1) = 0+1+2+3+4 = 10
  let (storage0, _, _) ← requireSuccess "for-loop init"
    (execute initializer empty (encodeUInt64LE 0) zero)
  expect (storedUInt64? storage0 field.key == some 0)
    "for-loop init must store seed 0"
  let (storage1, ret1, _) ← requireSuccess "for-loop addUp(1)"
    (execute addUpIR storage0 (encodeUInt64LE 1) zero)
  expect (ret1 == some 10 && storedUInt64? storage1 field.key == some 10)
    s!"for-loop: init(0)+addUp(1) must yield 10, got ret={ret1} state={storedUInt64? storage1 field.key}"
  -- addUp(6) from 10 → 10+6+7+8+9 = 40
  let (storage2, ret2, _) ← requireSuccess "for-loop addUp(6)"
    (execute addUpIR storage1 (encodeUInt64LE 6) zero)
  expect (ret2 == some 40 && storedUInt64? storage2 field.key == some 40)
    s!"for-loop: addUp(6) from 10 must yield 40, got ret={ret2} state={storedUInt64? storage2 field.key}"
  -- scan(7) is zero-trip: state unchanged.
  let (storage3, ret3, _) ← requireSuccess "for-loop scan(7)"
    (execute scanIR storage2 (encodeUInt64LE 7) zero)
  expect (ret3 == some 40 && storedUInt64? storage3 field.key == some 40)
    s!"for-loop: scan(7) must leave state 40, got ret={ret3} state={storedUInt64? storage3 field.key}"
  -- addUpTight: range of 4 with bound 3 — 4th body runs then back-edge traps
  -- (completed count 0..2 pass; after body 4, count==3 ≥ 3). Rollback.
  match execute tightIR storage3 (encodeUInt64LE 1) zero with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some 40)
        "for-loop: bound trap must roll back storage"
      expect (reason.contains "loop bound exceeded")
        s!"for-loop: expected loop bound exceeded trap, got {reason}"
  | .success .. => throw <| IO.userError "for-loop: addUpTight must trap on bound"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "for-loop: missing .wat artifact"
  expectContains wat.contents "loop" "for-loop WAT loop"
  expectContains wat.contents "br_if" "for-loop WAT br_if"
  expect (wat.contents.contains "i64.lt_u" || wat.contents.contains "i64.ge_u")
    "for-loop WAT must contain i64.lt_u or i64.ge_u"
  expectContains wat.contents "i64.add" "for-loop WAT i64.add"
  let files2 ← liftResult <| Targets.Near.buildFromCapability capability
  expect (files.map (·.contents) == files2.map (·.contents))
    "for-loop: buildFromCapability must be byte-identical on rebuild"

/-- Wave H: shift/bitwise/strict-logical product path.
    shiftMask: `(x << 2) & 15 | (x >> 1) ^ 3` (precedence bit-and > bit-xor > bit-or);
    shl2: overflow on 2^63 << 2; bigShift: count ≥ 64 traps; both: strict &&;
    strictOr: left-true still evaluates the right (div-by-zero).
    Host: init(0)→shiftMask(20)=9; shl2(2^63) overflow; bigShift(1) invalid;
    both(1,1)=true; strictOr(1,0) traps division-by-zero.
    WAT pins i64.shl/shr_u/and/xor/or + ge_u count guard + unreachable. -/
private unsafe def testShiftBitwiseLogicalProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BitLogic where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry shiftMask(x : UInt64) : UInt64 do\n" ++
    "    count := (x << 2) & 15 | (x >> 1) ^ 3\n" ++
    "    return count\n\n" ++
    "  entry shl2(x : UInt64) : UInt64 do\n" ++
    "    return x << 2\n\n" ++
    "  entry bigShift(x : UInt64) : UInt64 do\n" ++
    "    return x >> (32 + 32)\n\n" ++
    "  entry both(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a > 0 && b > 0\n\n" ++
    "  entry strictOr(a : UInt64, b : UInt64) : Bool do\n" ++
    "    let one : UInt64 := 1\n" ++
    "    return a > 0 || (one / b) == one\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-host-bit-logic>" "Examples.BitLogic" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let some shiftMask := plan.entries.find? (·.name == "shiftMask") |
    throw <| IO.userError
      s!"bit-logic: missing shiftMask entry, got {plan.entries.map (·.name)}"
  let some strictOr := plan.entries.find? (·.name == "strictOr") |
    throw <| IO.userError
      s!"bit-logic: missing strictOr entry, got {plan.entries.map (·.name)}"
  unless (plan.entries.find? (·.name == "shl2")).isSome do
    throw <| IO.userError s!"bit-logic: missing shl2 entry, got {plan.entries.map (·.name)}"
  unless (plan.entries.find? (·.name == "bigShift")).isSome do
    throw <| IO.userError s!"bit-logic: missing bigShift entry, got {plan.entries.map (·.name)}"
  unless (plan.entries.find? (·.name == "both")).isSome do
    throw <| IO.userError s!"bit-logic: missing both entry, got {plan.entries.map (·.name)}"
  -- Pin shiftMask nesting: ((x << 2) & 15) | ((x >> 1) ^ 3)
  expect (shiftMask.body == #[
      .store {
        fieldIndex := 0
        value := .bitOr
          (.bitAnd
            (.shl (.param 0) (.literal 2))
            (.literal 15))
          (.bitXor
            (.shr (.param 0) (.literal 1))
            (.literal 3))
      },
      .returnValue (.stateLoad 0)])
    "bit-logic: shiftMask must lower shl/bitAnd/shr/bitXor/bitOr store then return"
  -- Pin strictOr: (a > 0) || ((1 / b) == 1) — both sides always present.
  expect (strictOr.body == #[
      .returnValue
        (.boolOr
          (.compare .gt (.param 0) (.literal 0))
          (.compare .eq
            (.checkedDiv (.literal 1) (.param 8))
            (.literal 1)))])
    "bit-logic: strictOr must lower gt / checkedDiv / eq / boolOr (no short-circuit)"
  let some bigShift := plan.entries.find? (·.name == "bigShift") |
    throw <| IO.userError "bit-logic: missing bigShift entry after plan"
  -- Computed count 32+32 = 64 reaches invalidShift at runtime (literal 64 is
  -- rejected by CheckV1 as a source-level constant bound).
  -- T8c: UInt32 count composition uses narrowCheckedAdd 32 (body multi-width).
  expect (bigShift.body == #[
      .returnValue
        (.shr (.param 0) (.narrowCheckedAdd 32 (.literal 32) (.literal 32)))])
    "bit-logic: bigShift must lower shr of param by narrowCheckedAdd 32 of UInt32 counts"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let ir2 ← liftResult <| Targets.Near.irFromCapability capability
  expect (ir == ir2) "bit-logic: IR rebuild must be structure-identical"
  let shiftMaskIR ← findMethod ir "shiftMask"
  let shl2IR ← findMethod ir "shl2"
  let bigShiftIR ← findMethod ir "bigShift"
  let bothIR ← findMethod ir "both"
  let strictOrIR ← findMethod ir "strictOr"
  let maskKinds := operationKinds shiftMaskIR.operations
  expect (maskKinds.contains "shl" && maskKinds.contains "shr" &&
      maskKinds.contains "bitAnd" && maskKinds.contains "bitXor" &&
      maskKinds.contains "bitOr")
    s!"bit-logic: shiftMask IR must lower shift/bitwise ops, got {maskKinds}"
  let strictKinds := operationKinds strictOrIR.operations
  expect (strictKinds.contains "boolOr" && strictKinds.contains "checkedDiv")
    s!"bit-logic: strictOr IR must lower boolOr + checkedDiv, got {strictKinds}"
  let bothKinds := operationKinds bothIR.operations
  expect (bothKinds.contains "boolAnd")
    s!"bit-logic: both IR must lower boolAnd, got {bothKinds}"
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let encodePair (a b : U64) : ByteArray :=
    encodeUInt64LE a ++ encodeUInt64LE b
  -- init(0) → shiftMask(20) = ((80 & 15) | (10 ^ 3)) = 0 | 9 = 9
  let (storage0, _, _) ← requireSuccess "bit-logic init"
    (execute initializer empty (encodeUInt64LE 0) zero)
  expect (storedUInt64? storage0 field.key == some 0)
    "bit-logic init must store seed 0"
  let (storage1, ret1, _) ← requireSuccess "bit-logic shiftMask(20)"
    (execute shiftMaskIR storage0 (encodeUInt64LE 20) zero)
  expect (ret1 == some 9 && storedUInt64? storage1 field.key == some 9)
    s!"bit-logic: shiftMask(20) must yield 9, got ret={ret1} state={storedUInt64? storage1 field.key}"
  -- shl2(2^63) overflows (2^65 ≥ 2^64).
  let highBit := UInt64.ofNat (1 <<< 63)
  match execute shl2IR storage1 (encodeUInt64LE highBit) zero with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some 9)
        "bit-logic: shl overflow must roll back storage"
      expect (reason.contains "shift overflow" || reason.contains "overflow")
        s!"bit-logic: expected shift overflow trap, got {reason}"
  | .success .. => throw <| IO.userError "bit-logic: shl2(2^63) must trap"
  -- bigShift: computed count 32+32 = 64 ≥ 64 → invalid shift.
  match execute bigShiftIR storage1 (encodeUInt64LE 1) zero with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some 9)
        "bit-logic: invalid shift must roll back storage"
      expect (reason.contains "invalid shift")
        s!"bit-logic: expected invalid shift trap, got {reason}"
  | .success .. =>
      throw <| IO.userError "bit-logic: bigShift (x >> (32+32)) must trap on count ≥ 64"
  -- both(1,1) → true; both(1,0) → false.
  let (_, bothT, _) ← requireSuccess "bit-logic both(1,1)"
    (execute bothIR storage1 (encodePair 1 1) zero)
  expect (bothT == some 1) s!"bit-logic: both(1,1) must be true, got {bothT}"
  let (_, bothF, _) ← requireSuccess "bit-logic both(1,0)"
    (execute bothIR storage1 (encodePair 1 0) zero)
  expect (bothF == some 0) s!"bit-logic: both(1,0) must be false, got {bothF}"
  -- strictOr(1, 0): left is true, but right still evaluates one/0 → div-by-zero.
  match execute strictOrIR storage1 (encodePair 1 0) zero with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some 9)
        "bit-logic: strictOr div-by-zero must roll back storage"
      expect (reason.contains "division by zero")
        s!"bit-logic: expected division by zero trap, got {reason}"
  | .success .. =>
      throw <| IO.userError
        "bit-logic: strictOr(1,0) must trap (no short-circuit)"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "bit-logic: missing .wat artifact"
  expectContains wat.contents "i64.shl" "bit-logic WAT i64.shl"
  expectContains wat.contents "i64.shr_u" "bit-logic WAT i64.shr_u"
  expectContains wat.contents "i64.and" "bit-logic WAT i64.and"
  expectContains wat.contents "i64.xor" "bit-logic WAT i64.xor"
  expectContains wat.contents "i64.or" "bit-logic WAT i64.or"
  expectContains wat.contents "i64.ge_u" "bit-logic WAT i64.ge_u count guard"
  expectContains wat.contents "unreachable" "bit-logic WAT unreachable"
  let files2 ← liftResult <| Targets.Near.buildFromCapability capability
  expect (files.map (·.contents) == files2.map (·.contents))
    "bit-logic: buildFromCapability must be byte-identical on rebuild"

/-- Wave I: schedule → native promise (fire-and-forget). later schedules
    `ledger.daily(count)` then returns count; bad uses uppercase Ledger (account-id
    gate); callSync uses `call` and is declined by the S2 resolver (NEAR has no
    sync cross-contract calls). Host: init(5)→later(1) returns 5 and logs the
    promise with receiver/method/LE-args-hex. WAT pins promise host names and
    the account-id string. Deposit/gas are explicit zero placeholders. -/
private unsafe def testScheduleProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let scheduleText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ScheduleFlow where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry later(delta : UInt64) : UInt64 do\n" ++
    "    schedule ledger.daily(count)\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    scheduleText "<near-schedule-flow>" "Examples.ScheduleFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  expect (plan.hostImports.contains .promiseBatchCreate &&
      plan.hostImports.contains .promiseBatchActionFunctionCall)
    "schedule Plan must extend the host allowlist with promise hosts"
  let some later := plan.entries.find? (·.name == "later") |
    throw <| IO.userError s!"schedule: missing later entry, got {plan.entries.map (·.name)}"
  expect (later.body == #[
      .promiseAccount "ledger.daily" "daily" #[.stateLoad 0],
      .returnValue (.stateLoad 0)])
    "schedule: later must lower promiseAccount(ledger.daily, daily, count) then return"
  liftResult <| Targets.Near.validatePlan plan
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  liftResult <| Targets.Near.validateIR ir
  let laterIR ← findMethod ir "later"
  let kinds := operationKinds laterIR.operations
  expect (kinds.contains "promiseAccount")
    s!"schedule: later IR must contain promiseAccount, got {kinds}"
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let (storage0, _, _) ← requireSuccess "schedule init"
    (execute initializer empty (encodeUInt64LE 5) zero)
  expect (storedUInt64? storage0 field.key == some 5)
    "schedule init must store seed 5"
  let (storage1, ret1, logs1) ← requireSuccess "schedule later"
    (execute laterIR storage0 (encodeUInt64LE 1) zero)
  expect (ret1 == some 5 && storedUInt64? storage1 field.key == some 5)
    "schedule: later must return count without mutating state"
  -- count=5 as LE bytes → hex 0500000000000000
  expect (logs1 == #["pf-promise:ledger.daily:daily:0500000000000000"])
    s!"schedule must log the fire-and-forget promise entry, got {logs1}"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "schedule: missing .wat artifact"
  expectContains wat.contents "promise_batch_create" "schedule WAT promise_batch_create"
  expectContains wat.contents "promise_batch_action_function_call"
    "schedule WAT promise_batch_action_function_call"
  expectContains wat.contents "ledger.daily" "schedule WAT account id"
  expectContains wat.contents "daily" "schedule WAT method name"
  -- Explicit zero deposit/gas placeholders in the action call.
  expectContains wat.contents "(i64.const 0) (i64.const 0) (i64.const 0))"
    "schedule WAT zero deposit/gas placeholders"
  let files2 ← liftResult <| Targets.Near.buildFromCapability capability
  expect (files.map (·.contents) == files2.map (·.contents))
    "schedule: buildFromCapability must be byte-identical on rebuild"

  -- Uppercase receiver must fail the account-id gate (never case-normalized).
  let badText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ScheduleBad where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bad(n : UInt64) : UInt64 do\n" ++
    "    schedule Ledger.daily(count)\n" ++
    "    return n\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let badSource ← liftResult (← session.selectProgramV1
    badText "<near-schedule-bad>" "Examples.ScheduleBad" none)
  let badCompiled ← liftResult <| Compiler.compileValidatedSourceV1 badSource
  let badCapability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection badCompiled
  match Targets.Near.planFromCapability badCapability with
  | .error (.planInvariant .near msg) =>
      expect (msg.contains "Ledger.daily" &&
          (msg.contains "account id" || msg.contains "NEAR account"))
        s!"schedule uppercase must fail account-id gate, got {msg}"
  | .error other =>
      throw <| IO.userError s!"schedule uppercase: expected planInvariant, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "schedule uppercase: expected planInvariant fail-closed"

  -- Sync call: compiles, but NEAR S2 resolver declines effect.synchronous-call.
  let callText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CallSync where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry poke(n : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(count)\n" ++
    "    return n\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let callSource ← liftResult (← session.selectProgramV1
    callText "<near-call-sync>" "Examples.CallSync" none)
  let callCompiled ← liftResult <| Compiler.compileValidatedSourceV1 callSource
  match Targets.resolveEngineeringRequirementsV1 selection callCompiled with
  | .error err =>
      expect (err.code == "PF-REQ-UNSUPPORTED" &&
          err.render.contains "effect.synchronous-call")
        s!"sync call must be PF-REQ-UNSUPPORTED for NEAR, got {err.code}: {err.render}"
  | .ok _ =>
      throw <| IO.userError
        "sync call: resolveEngineeringRequirementsV1 must fail for NEAR"

/-- Void entry `entry run() do` (no result / no return) fails closed on the
    product path. Primary gate today is Normalize
    (`S1 normalizer requires explicit return for entry/view`); bare `return`
    is also rejected. NEAR lowerer secondary defense (planInvariant
    `entry '…' does not return public UInt64 or Bool`) is therefore currently
    unreachable for this source shape. -/
private unsafe def testVoidEntryFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program VoidRun where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry run() do\n" ++
    "    count := count + 1\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-void-run>" "Examples.VoidRun" none)
  match Compiler.compileValidatedSourceV1 source with
  | .error err =>
      expect (err.render.contains "explicit return" ||
          err.render.contains "PF-SRC-INVALID")
        s!"void entry must fail closed at product compile, got {err.render}"
  | .ok compiled =>
      -- If Normalize ever admits Unit entries, the NEAR result-kind gate must
      -- still reject at plan materialize.
      let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
      let capability ← liftResult <|
        Targets.resolveEngineeringRequirementsV1 selection compiled
      match Targets.Near.planFromCapability capability with
      | .error (.planInvariant .near msg) =>
          expect (msg.contains "does not return public UInt64 or Bool")
            s!"void entry planInvariant must mention UInt64/Bool, got {msg}"
      | .error other =>
          throw <| IO.userError
            s!"void entry: expected planInvariant .near, got {other.render}"
      | .ok _ =>
          throw <| IO.userError
            "void entry must fail closed at NEAR plan materialize"

/-- Two declared events, both emitted: pins Plan table + host pf-event logs +
    WAT log_utf8. -/
private unsafe def testMultipleEventsProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MultiEvent where\n" ++
    "  state count : UInt64\n\n" ++
    "  event Ticked(value : UInt64)\n" ++
    "  event Moved(src : UInt64, dst : UInt64)\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry go(x : UInt64) : UInt64 do\n" ++
    "    emit Ticked(x)\n" ++
    "    emit Moved(count, x)\n" ++
    "    count := count + x\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-multi-event>" "Examples.MultiEvent" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  expect (plan.events.map (·.name) == #["Ticked", "Moved"] &&
      plan.events.map (·.fieldCount) == #[1, 2])
    "MultiEvent must carry both declared events in source order"
  let go := plan.entries[0]!
  expect (go.body == #[
      .emitEvent 0 #[.param 0],
      .emitEvent 1 #[.stateLoad 0, .param 0],
      .store { fieldIndex := 0, value := .checkedAdd (.stateLoad 0) (.param 0) },
      .returnValue (.stateLoad 0)])
    "MultiEvent go must lower both emits, store, return"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let initializer ← findMethod ir "init"
  let goIR ← findMethod ir "go"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let eventNames := plan.events.map (·.name)
  let (storage0, _, _) ← requireSuccess "multi-event init"
    (execute initializer empty (encodeUInt64LE 5) zero)
  let (storage1, ret1, logs1) ← requireSuccess "multi-event go"
    (execute goIR storage0 (encodeUInt64LE 3) zero eventNames #[] )
  expect (ret1 == some 8 && storedUInt64? storage1 field.key == some 8)
    "multi-event go must store and return count+x"
  expect (logs1 == #[
      "pf-event:Ticked:0000000000000003",
      "pf-event:Moved:0000000000000005,0000000000000003"])
    s!"multi-event must log both pf-event messages, got {logs1}"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "multi-event: missing .wat artifact"
  expectContains wat.contents "log_utf8" "multi-event WAT log import"

/-- Zero-argument error: `error Cap()` + `revert Cap` traps as pf-error:Cap:
    (empty hex payload) and rolls back. -/
private unsafe def testZeroArgRevertProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ZeroRevert where\n" ++
    "  state count : UInt64\n\n" ++
    "  error Cap()\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > delta then\n" ++
    "      revert Cap\n" ++
    "    else\n" ++
    "      count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-zero-revert>" "Examples.ZeroRevert" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  expect (plan.errors.map (·.name) == #["Cap"] &&
      plan.errors.map (·.fieldCount) == #[0])
    "ZeroRevert must carry zero-arg Cap error"
  let bump := plan.entries[0]!
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0) (.param 0))
        #[.revertError 0 #[]]
        #[.store { fieldIndex := 0, value := .checkedAdd (.stateLoad 0) (.param 0) }],
      .returnValue (.stateLoad 0)])
    "ZeroRevert bump must lower zero-arg revertError"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let initializer ← findMethod ir "init"
  let bumpIR ← findMethod ir "bump"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let errorNames := plan.errors.map (·.name)
  let (storage0, _, _) ← requireSuccess "zero-revert init"
    (execute initializer empty (encodeUInt64LE 5) zero)
  match execute bumpIR storage0 (encodeUInt64LE 3) zero #[] errorNames with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some 5)
        s!"zero-arg revert must roll back storage, got {reason}"
      expect (reason == "pf-error:Cap:")
        s!"zero-arg revert message must be pf-error:Cap: (empty args), got {reason}"
  | .success _ _ _ =>
      throw <| IO.userError "zero-arg revert branch must trap"
  let (storage1, ret1, _) ← requireSuccess "zero-revert else"
    (execute bumpIR storage0 (encodeUInt64LE 7) zero #[] errorNames)
  expect (ret1 == some 12 && storedUInt64? storage1 field.key == some 12)
    "zero-arg revert else branch must store and return count+delta"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "zero-revert: missing .wat artifact"
  expectContains wat.contents "panic_utf8" "zero-revert WAT panic import"

/-- Bool-result pureFn: `fn flag(a : UInt64) : Bool do return a > 0` called
    from an entry; pins Plan resultIsBool + host 0/1 return. -/
private unsafe def testBoolResultPureFnProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoolFn where\n" ++
    "  state count : UInt64\n\n" ++
    "  fn flag(a : UInt64) : Bool do\n" ++
    "    return a > 0\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry check(x : UInt64) : Bool do\n" ++
    "    return flag(x)\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-bool-fn>" "Examples.BoolFn" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  expect (plan.fns.size == 1 && plan.fns[0]!.name == "flag" &&
      plan.fns[0]!.resultIsBool && plan.fns[0]!.params.size == 1)
    "bool-fn: flag must be a Bool pureFn with one param"
  expect (plan.fns[0]!.body == #[
      .returnValue (.compare .gt (.param 0) (.literal 0))])
    "bool-fn: flag body must return a > 0"
  let some check := plan.entries.find? (·.name == "check") |
    throw <| IO.userError "bool-fn: missing check entry"
  expect (check.resultKind == .bool &&
      check.body == #[.returnValue (.callFn 0 #[.param 0])])
    "bool-fn: check must return callFn flag(x) as Bool"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let flagKinds := operationKinds ir.fns[0]!.operations
  expect (flagKinds.contains "compare.gt" && flagKinds.contains "returnValue")
    s!"bool-fn: flag IR must lower gt compare + returnValue, got {flagKinds}"
  let checkIR ← findMethod ir "check"
  let checkKinds := operationKinds checkIR.operations
  expect (checkKinds.contains "callFn")
    s!"bool-fn: check IR must lower callFn, got {checkKinds}"
  let initializer ← findMethod ir "init"
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let (storage0, _, _) ← requireSuccess "bool-fn init"
    (execute initializer empty (encodeUInt64LE 0) zero #[] #[] ir.fns)
  let (_, trueRet, _) ← requireSuccess "bool-fn check(5)"
    (execute checkIR storage0 (encodeUInt64LE 5) zero #[] #[] ir.fns)
  expect (trueRet == some 1) s!"bool-fn: flag(5) must be true, got {trueRet}"
  let (_, falseRet, _) ← requireSuccess "bool-fn check(0)"
    (execute checkIR storage0 (encodeUInt64LE 0) zero #[] #[] ir.fns)
  expect (falseRet == some 0) s!"bool-fn: flag(0) must be false, got {falseRet}"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "bool-fn: missing .wat artifact"
  expectContains wat.contents "(func $fn_flag" "bool-fn WAT flag func"
  expectContains wat.contents "(call $fn_flag" "bool-fn WAT flag call site"

/-- Omitted-type let: `let x := a + b` lowers identically to the annotated form
    (RHS expression tree, no residual annotation). Return uses the let binding
    directly (no intervening effect) so the ValueId stays in-segment. -/
private unsafe def testOmittedTypeLetProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OmitLet where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry sum(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    let x := a + b\n" ++
    "    return x\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-omit-let>" "Examples.OmitLet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let some sum := plan.entries.find? (·.name == "sum") |
    throw <| IO.userError "omit-let: missing sum entry"
  expect (sum.body == #[
      .returnValue (.checkedAdd (.param 0) (.param 8))])
    "omit-let: sum must lower let x := a+b into return checkedAdd(a,b)"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let sumIR ← findMethod ir "sum"
  let sumKinds := operationKinds sumIR.operations
  expect (sumKinds.contains "checkedAdd")
    s!"omit-let: sum IR must lower checkedAdd, got {sumKinds}"
  let initializer ← findMethod ir "init"
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let encodePair (a b : U64) : ByteArray :=
    encodeUInt64LE a ++ encodeUInt64LE b
  let (storage0, _, _) ← requireSuccess "omit-let init"
    (execute initializer empty (encodeUInt64LE 0) zero)
  let (_, ret1, _) ← requireSuccess "omit-let sum(3,4)"
    (execute sumIR storage0 (encodePair 3 4) zero)
  expect (ret1 == some 7)
    s!"omit-let: sum(3,4) must yield 7, got ret={ret1}"

/-- T8b-NEAR: public UInt8/16/32 state + params materialize with width-aware
    layout marker / ABI / WAT. Body multi-width arithmetic stays T8c — this
    program only assigns params into state and returns a UInt64 literal. -/
private unsafe def testNarrowAbiProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NarrowAbi where\n" ++
    "  state a : UInt8\n" ++
    "  state b : UInt16\n" ++
    "  state c : UInt32\n\n" ++
    "  init(x : UInt8, y : UInt16, z : UInt32) do\n" ++
    "    a := x\n" ++
    "    b := y\n" ++
    "    c := z\n\n" ++
    "  entry set8(x : UInt8) : UInt64 do\n" ++
    "    a := x\n" ++
    "    return 0\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-narrow-abi>" "Examples.NarrowAbi" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  expect (plan.storage.fields.size == 3)
    "narrow-abi: expected three state fields"
  expect (plan.storage.fields[0]!.byteWidth == 1 &&
      plan.storage.fields[1]!.byteWidth == 2 &&
      plan.storage.fields[2]!.byteWidth == 4)
    s!"narrow-abi: field byteWidths must be 1/2/4, got {[plan.storage.fields[0]!.byteWidth, plan.storage.fields[1]!.byteWidth, plan.storage.fields[2]!.byteWidth]}"
  let initParams := plan.initializer.params
  expect (initParams.size == 3 &&
      initParams[0]!.byteWidth == 1 && initParams[0]!.inputOffset == 0 &&
      initParams[1]!.byteWidth == 2 && initParams[1]!.inputOffset == 8 &&
      initParams[2]!.byteWidth == 4 && initParams[2]!.inputOffset == 16)
    "narrow-abi: init params must retain 8-byte slot pitch with narrow byteWidths"
  -- Layout marker must change when narrow widths appear (not pure u64-le).
  expect (plan.storage.markerValue != 0)
    "narrow-abi: layout marker must be nonzero"
  liftResult <| Targets.Near.validatePlan plan
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  liftResult <| Targets.Near.validateIR ir
  let initIR ← findMethod ir "init"
  let initKinds := operationKinds initIR.operations
  expect (initKinds.contains "narrowZeroState")
    s!"narrow-abi: init must narrow-zero fields, got {initKinds}"
  expect (initKinds.contains "narrowLoadParam")
    s!"narrow-abi: init must narrow-load params, got {initKinds}"
  expect (initKinds.contains "narrowStoreState")
    s!"narrow-abi: init must narrow-store state, got {initKinds}"
  let set8IR ← findMethod ir "set8"
  let set8Kinds := operationKinds set8IR.operations
  expect (set8Kinds.contains "narrowLoadParam" && set8Kinds.contains "narrowStoreState")
    s!"narrow-abi: set8 must narrow load/store, got {set8Kinds}"
  -- Host-model: init(1,2,3) → set8(9) stores 9 in UInt8 field a.
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let pack3 (x y z : U64) : ByteArray :=
    encodeUInt64LE x ++ encodeUInt64LE y ++ encodeUInt64LE z
  let (storage0, _, _) ← requireSuccess "narrow-abi init" <|
    execute initIR empty (pack3 1 2 3) zero
  let aKey := ir.keys[1]!
  let bKey := ir.keys[2]!
  let cKey := ir.keys[3]!
  expect (match storageLookup? storage0 aKey.key with
    | some bytes => bytes.size == 1 && bytes[0]!.toNat == 1
    | none => false)
    "narrow-abi: field a must be 1-byte LE 1 after init"
  expect (match storageLookup? storage0 bKey.key with
    | some bytes => bytes.size == 2 && decodeUIntLE bytes 2 == some 2
    | none => false)
    "narrow-abi: field b must be 2-byte LE 2 after init"
  expect (match storageLookup? storage0 cKey.key with
    | some bytes => bytes.size == 4 && decodeUIntLE bytes 4 == some 3
    | none => false)
    "narrow-abi: field c must be 4-byte LE 3 after init"
  let (storage1, ret, _) ← requireSuccess "narrow-abi set8" <|
    execute set8IR storage0 (encodeUInt64LE 9) zero
  expect (ret == some 0)
    "narrow-abi: set8 must return UInt64 0"
  expect (match storageLookup? storage1 aKey.key with
    | some bytes => bytes.size == 1 && bytes[0]!.toNat == 9
    | none => false)
    "narrow-abi: set8 must overwrite field a with 9"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some watFile := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "narrow-abi: missing .wat artifact"
  let some abiFile := files.find? (fun f => f.path.endsWith ".near-abi.json") |
    throw <| IO.userError "narrow-abi: missing .near-abi.json artifact"
  expectContains watFile.contents "i32.load8_u" "narrow-abi WAT load8_u"
  expectContains watFile.contents "i32.load16_u" "narrow-abi WAT load16_u"
  expectContains watFile.contents "i32.store8" "narrow-abi WAT store8"
  expectContains watFile.contents "i32.store16" "narrow-abi WAT store16"
  expectContains watFile.contents "(i64.const 1)" "narrow-abi WAT storage_write len 1"
  expectContains watFile.contents "(i64.const 2)" "narrow-abi WAT storage_write len 2"
  expectContains watFile.contents "(i64.const 4)" "narrow-abi WAT storage_write len 4"
  expectContains abiFile.contents "\"type\":\"u8-le\"" "narrow-abi ABI u8-le"
  expectContains abiFile.contents "\"type\":\"u16-le\"" "narrow-abi ABI u16-le"
  expectContains abiFile.contents "\"type\":\"u32-le\"" "narrow-abi ABI u32-le"
  -- Pure UInt64 Counter-style program must still render only u64-le on fields.
  let u64Text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program U64Only where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry add(amount : UInt64) : UInt64 do\n" ++
    "    count := count + amount\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let u64Source ← liftResult (← session.selectProgramV1
    u64Text "<near-u64-only>" "Examples.U64Only" none)
  let u64Compiled ← liftResult <| Compiler.compileValidatedSourceV1 u64Source
  let u64Cap ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection u64Compiled
  let u64Plan ← liftResult <| Targets.Near.planFromCapability u64Cap
  expect (u64Plan.storage.fields[0]!.byteWidth == 8)
    "u64-only: field byteWidth must remain 8"
  let u64Files ← liftResult <| Targets.Near.buildFromCapability u64Cap
  let some u64Abi := u64Files.find? (fun f => f.path.endsWith ".near-abi.json") |
    throw <| IO.userError "u64-only: missing abi"
  expect (u64Abi.contents.contains "\"type\":\"u64-le\"")
    "u64-only: ABI must keep u64-le"
  expect (!u64Abi.contents.contains "\"type\":\"u8-le\"")
    "u64-only: ABI must not introduce u8-le"

/-- T8c-NEAR: UInt8 state body multi-width add — success path + overflow trap;
    WAT evidence of high-bit `shr_u` guard after narrow add. -/
private unsafe def testNarrowBodyProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NarrowBody where\n" ++
    "  state a : UInt8\n\n" ++
    "  init(x : UInt8) do\n" ++
    "    a := x\n\n" ++
    "  entry bump(delta : UInt8) : UInt64 do\n" ++
    "    a := a + delta\n" ++
    "    return 0\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-narrow-body>" "Examples.NarrowBody" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let some bump := plan.entries.find? (·.name == "bump") |
    throw <| IO.userError "narrow-body: missing bump entry"
  -- Store narrowCheckedAdd of narrowStateLoad + narrowParam.
  let bumpOk :=
    match bump.body[0]? with
    | some (Targets.Near.Statement.store store) =>
        match store.value with
        | Targets.Near.Expr.narrowCheckedAdd 8
            (Targets.Near.Expr.narrowStateLoad 8 0)
            (Targets.Near.Expr.narrowParam 8 0) =>
              store.fieldIndex == 0 && store.byteWidth == 1
        | _ => false
    | _ => false
  expect bumpOk
    "narrow-body: bump must lower UInt8 add as narrowCheckedAdd 8"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  liftResult <| Targets.Near.validateIR ir
  let bumpIR ← findMethod ir "bump"
  let kinds := operationKinds bumpIR.operations
  expect (kinds.contains "narrowCheckedAdd" &&
      kinds.contains "narrowLoadState" && kinds.contains "narrowLoadParam" &&
      kinds.contains "narrowStoreState")
    s!"narrow-body: IR must lower narrow add/load/store, got {kinds}"
  let initIR ← findMethod ir "init"
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let (storage0, _, _) ← requireSuccess "narrow-body init" <|
    execute initIR empty (encodeUInt64LE 200) zero
  let aKey := ir.keys[1]!
  expect (match storageLookup? storage0 aKey.key with
    | some bytes => bytes.size == 1 && bytes[0]!.toNat == 200
    | none => false)
    "narrow-body: field a must be 200 after init"
  -- 200 + 50 = 250 fits UInt8.
  let (storage1, ret, _) ← requireSuccess "narrow-body bump(50)" <|
    execute bumpIR storage0 (encodeUInt64LE 50) zero
  expect (ret == some 0)
    "narrow-body: bump must return UInt64 0"
  expect (match storageLookup? storage1 aKey.key with
    | some bytes => bytes.size == 1 && bytes[0]!.toNat == 250
    | none => false)
    "narrow-body: bump(50) must store 250"
  -- 250 + 10 = 260 overflows UInt8 → trap + storage rollback.
  match execute bumpIR storage1 (encodeUInt64LE 10) zero with
  | .trapped rolled _ =>
      expect (match storageLookup? rolled aKey.key with
        | some bytes => bytes.size == 1 && bytes[0]!.toNat == 250
        | none => false)
        "narrow-body: UInt8 overflow must roll back storage"
  | .success .. =>
      throw <| IO.userError "narrow-body: 250+10 must trap on UInt8 overflow"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some watFile := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "narrow-body: missing .wat artifact"
  expectContains watFile.contents "i64.shr_u" "narrow-body WAT shr_u high-bit guard"
  expectContains watFile.contents "i64.add" "narrow-body WAT i64.add"
  expectContains watFile.contents "i32.store8" "narrow-body WAT store8"
  expectContains watFile.contents "i32.load8_u" "narrow-body WAT load8_u"

/-- T8b-NEAR negatives: UInt128 state, Int8 param, narrow entry result fail closed. -/
private unsafe def testNarrowAbiNegatives
    (session : Language.Loader.ParserSession) : IO Unit := do
  let cases : Array (String × String × String) := #[
    ("uint128-state", "Examples.U128State",
      "program U128State where\n" ++
      "  state big : UInt128\n\n" ++
      "  init(x : UInt64) do\n" ++
      "    big := 0\n\n" ++
      "  entry ping(x : UInt64) : UInt64 do\n" ++
      "    return x\n"),
    ("int8-param", "Examples.Int8Param",
      "program Int8Param where\n" ++
      "  state count : UInt64\n\n" ++
      "  init(i : UInt64) do\n" ++
      "    count := i\n\n" ++
      "  entry ping(x : Int8) : UInt64 do\n" ++
      "    return count\n"),
    ("uint128-result", "Examples.U128Result",
      "program U128Result where\n" ++
      "  state count : UInt64\n\n" ++
      "  init(i : UInt64) do\n" ++
      "    count := i\n\n" ++
      "  entry ping(x : UInt64) : UInt128 do\n" ++
      "    return 0\n")
  ]
  for item in cases do
    let (label, moduleName, body) := item
    let sourceText :=
      "import ProofForgeV2\n\n" ++
      "namespace ProofForgeV2.Examples\n\n" ++
      "open ProofForgeV2.Language\n\n" ++
      body ++ "\nend ProofForgeV2.Examples\n"
    let source ← liftResult (← session.selectProgramV1
      sourceText s!"<near-host-{label}>" moduleName none)
    match Compiler.compileValidatedSourceV1 source with
    | .error _ => pure ()
    | .ok compiled =>
        let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
        match Targets.resolveEngineeringRequirementsV1 selection compiled with
        | .error _ => pure ()
        | .ok capability =>
            match Targets.Near.planFromCapability capability with
            | .error _ => pure ()
            | .ok _ =>
                throw <| IO.userError
                  s!"{label}: must fail closed for NEAR T8b/T9a width bounds"

/-- T9a-NEAR: entry results UInt8/16/32 admitted; ABI + value_return lengths. -/
private unsafe def testNarrowResultProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NarrowResult where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry get8(x : UInt8) : UInt8 do\n" ++
    "    return x\n\n" ++
    "  entry get16(x : UInt16) : UInt16 do\n" ++
    "    return x\n\n" ++
    "  entry get32(x : UInt32) : UInt32 do\n" ++
    "    return x\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-narrow-result>" "Examples.NarrowResult" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  expect (plan.entries.map (·.resultKind) ==
      #[.uint8, .uint16, .uint32, .uint64])
    "T9a: NEAR resultKinds must be uint8/16/32/64"
  liftResult <| Targets.Near.validatePlan plan
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  liftResult <| Targets.Near.validateIR ir
  let get8IR ← findMethod ir "get8"
  expect (get8IR.operations.any fun
    | .setReturnData 1 _ => true
    | _ => false)
    "T9a: get8 must emit setReturnData byteLen=1"
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let (storage0, _, _) ← requireSuccess "narrow-result init" <|
    execute (← findMethod ir "init") empty (encodeUInt64LE 7) zero
  let (_, ret8, _) ← requireSuccess "narrow-result get8" <|
    execute get8IR storage0 (encodeUInt64LE 9) zero
  expect (ret8 == some 9)
    s!"T9a: get8 must return 9, got {ret8}"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some abiFile := files.find? (fun f => f.path.endsWith ".near-abi.json") |
    throw <| IO.userError "narrow-result: missing near-abi.json"
  expectContains abiFile.contents "\"u8-le\"" "narrow-result ABI u8-le"
  expectContains abiFile.contents "\"u16-le\"" "narrow-result ABI u16-le"
  expectContains abiFile.contents "\"u32-le\"" "narrow-result ABI u32-le"
  let some watFile := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "narrow-result: missing .wat"
  expectContains watFile.contents
    "(call $pf_value_return (i64.const 1)" "narrow-result WAT return len 1"
  expectContains watFile.contents
    "(call $pf_value_return (i64.const 2)" "narrow-result WAT return len 2"
  expectContains watFile.contents
    "(call $pf_value_return (i64.const 4)" "narrow-result WAT return len 4"

/-- Host-model Bool `!` execution pin (boolNot). Plan/WAT already lower `!`;
    this closes the host-model execution gap left by &&/||-only traces. -/
private unsafe def testBoolNotHostExecution
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BoolNot where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry negate(x : UInt64) : Bool do\n" ++
    "    return !(x > 0)\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-bool-not>" "Examples.BoolNot" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let some negate := plan.entries.find? (·.name == "negate") |
    throw <| IO.userError "bool-not: missing negate entry"
  expect (negate.resultKind == .bool &&
      negate.body == #[
        .returnValue (.boolNot (.compare .gt (.param 0) (.literal 0)))])
    "bool-not: negate must lower !(x > 0) to boolNot over gt"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let negateIR ← findMethod ir "negate"
  let kinds := operationKinds negateIR.operations
  expect (kinds.contains "boolNot" && kinds.contains "compare.gt")
    s!"bool-not: IR must lower boolNot + gt, got {kinds}"
  let initializer ← findMethod ir "init"
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let (storage0, _, _) ← requireSuccess "bool-not init"
    (execute initializer empty (encodeUInt64LE 0) zero)
  -- !(5 > 0) = false → 0; !(0 > 0) = true → 1.
  let (_, retPos, _) ← requireSuccess "bool-not negate(5)"
    (execute negateIR storage0 (encodeUInt64LE 5) zero)
  expect (retPos == some 0) s!"bool-not: !(5>0) must be false, got {retPos}"
  let (_, retZero, _) ← requireSuccess "bool-not negate(0)"
    (execute negateIR storage0 (encodeUInt64LE 0) zero)
  expect (retZero == some 1) s!"bool-not: !(0>0) must be true, got {retZero}"
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let some wat := files.find? (fun f => f.path.endsWith ".wat") |
    throw <| IO.userError "bool-not: missing .wat artifact"
  expectContains wat.contents "i64.eqz" "bool-not WAT i64.eqz for boolNot"


/-- Isolated mod-by-zero: a dedicated `%` entry traps "division by zero" on
    b=0 without any preceding division, and rolls storage back. -/
private unsafe def testIsolatedModZeroProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ModOnly where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry rem(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    return a % b\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-host-mod-only>" "Examples.ModOnly" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  let some rem := plan.entries.find? (·.name == "rem") |
    throw <| IO.userError s!"mod-only: missing rem entry, got {plan.entries.map (·.name)}"
  let remMods := rem.body.filter fun s =>
    match s with | .returnValue (.checkedMod ..) => true | _ => false
  expect (remMods.size == 1)
    "mod-only: rem must return a checkedMod"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let remIR ← findMethod ir "rem"
  let initializer ← findMethod ir "init"
  let field := ir.keys[1]!
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let encodePair (a b : U64) : ByteArray :=
    encodeUInt64LE a ++ encodeUInt64LE b
  let (storage0, _, _) ← requireSuccess "mod-only init"
    (execute initializer empty (encodeUInt64LE 6) zero)
  -- rem(7,3) = 1
  let (storage1, ret1, _) ← requireSuccess "mod-only rem 7,3"
    (execute remIR storage0 (encodePair 7 3) zero)
  expect (ret1 == some 1)
    "mod-only: rem(7,3) must yield 1"
  -- rem(5,0) traps the isolated mod-by-zero guard and rolls storage back.
  match execute remIR storage1 (encodePair 5 0) zero with
  | .trapped restored reason =>
      expect (storedUInt64? restored field.key == some 6)
        "mod-only: mod-by-zero must roll back storage"
      expect (reason.contains "division by zero")
        s!"mod-only: expected division by zero trap, got {reason}"
  | .success .. => throw <| IO.userError "mod-only: rem(/0) must trap"

/-- Multi-state host execution: both storage fields flow through init and a
    mutate entry, each under its own layout region. -/
private unsafe def testMultiStateHostExecution
    (session : Language.Loader.ParserSession) : IO Unit := do
  let text :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program TwoState where\n" ++
    "  state count : UInt64\n" ++
    "  state balance : UInt64\n\n" ++
    "  init(seed : UInt64) do\n" ++
    "    count := seed\n" ++
    "    balance := seed\n\n" ++
    "  entry go(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    balance := balance - delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    text "<near-host-two-state>" "Examples.TwoState" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  expect (plan.storage.fields.map (·.name) == #["count", "balance"])
    "two-state: plan must carry both state fields in source order"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  -- keys = [layout marker, count, balance].
  expect (ir.keys.size == 3)
    s!"two-state: IR must have marker + two storage regions, got {ir.keys.size}"
  let initializer ← findMethod ir "init"
  let go ← findMethod ir "go"
  let countKey := ir.keys[1]!.key
  let balanceKey := ir.keys[2]!.key
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let encodePair (a b : U64) : ByteArray :=
    encodeUInt64LE a ++ encodeUInt64LE b
  let (storage0, _, _) ← requireSuccess "two-state init"
    (execute initializer empty (encodeUInt64LE 10) zero)
  expect (storedUInt64? storage0 countKey == some 10 &&
      storedUInt64? storage0 balanceKey == some 10)
    "two-state: init must seed both fields"
  let (storage1, ret1, _) ← requireSuccess "two-state go"
    (execute go storage0 (encodeUInt64LE 3) zero)
  expect (ret1 == some 13)
    "two-state: go must return the updated count"
  expect (storedUInt64? storage1 countKey == some 13 &&
      storedUInt64? storage1 balanceKey == some 7)
    "two-state: go must update count and balance independently"

/-- T8b-NEAR: UInt8/16/32 state + params (assign-only; body multi-width is T8c).
    8-byte input slot pitch retained; KV values store exact ABI byteWidth. -/
private unsafe def testAbiMultiWidthStateParam (session : Language.Loader.ParserSession) :
    IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program AbiMw where\n" ++
    "  state flag : UInt8\n" ++
    "  state score : UInt16\n" ++
    "  state ticks : UInt32\n\n" ++
    "  init(f : UInt8, s : UInt16, t : UInt32) do\n" ++
    "    flag := f\n" ++
    "    score := s\n" ++
    "    ticks := t\n\n" ++
    "  entry setFlag(f : UInt8) : UInt64 do\n" ++
    "    flag := f\n" ++
    "    return 0\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    sourceText "<near-host-abi-mw>" "Examples.AbiMw" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Near.planFromCapability capability
  expect (plan.storage.fields.map (·.name) == #["flag", "score", "ticks"])
    "AbiMw storage names"
  expect (plan.storage.fields.map (·.byteWidth) == #[1, 2, 4])
    "AbiMw storage byteWidth UInt8/16/32 → 1/2/4"
  expect (plan.initializer.params.map (·.byteWidth) == #[1, 2, 4])
    "AbiMw init params byteWidth 1/2/4"
  expect (plan.initializer.params.map (·.inputOffset) == #[0, 8, 16])
    "AbiMw init params retain 8-byte slot pitch"
  let setFlag := plan.entries[0]!
  expect (setFlag.params.size == 1 && setFlag.params[0]!.byteWidth == 1)
    "AbiMw setFlag param is UInt8 (byteWidth 1)"
  let hasNarrowStore :=
    setFlag.body.any fun s =>
      match s with
      | .store st => st.byteWidth == 1 &&
          match st.value with
          | .narrowParam 8 0 => true
          | _ => false
      | _ => false
  expect hasNarrowStore
    "AbiMw plan must lower UInt8 param assign via narrowParam + byteWidth-1 store"
  let ir ← liftResult <| Targets.Near.irFromCapability capability
  let initializer ← findMethod ir "init"
  let setFlagIR ← findMethod ir "setFlag"
  expect (initializer.operations.any fun op =>
      match op with | .narrowZeroState 8 _ => true | _ => false)
    "AbiMw init must emit narrowZeroState 8 for UInt8 field"
  expect (initializer.operations.any fun op =>
      match op with | .narrowZeroState 16 _ => true | _ => false)
    "AbiMw init must emit narrowZeroState 16 for UInt16 field"
  expect (initializer.operations.any fun op =>
      match op with | .narrowZeroState 32 _ => true | _ => false)
    "AbiMw init must emit narrowZeroState 32 for UInt32 field"
  expect (setFlagIR.operations.any fun op =>
      match op with | .narrowLoadParam 8 _ _ => true | _ => false)
    "AbiMw setFlag IR must narrowLoadParam 8"
  expect (setFlagIR.operations.any fun op =>
      match op with | .narrowStoreState 8 _ _ => true | _ => false)
    "AbiMw setFlag IR must narrowStoreState 8"
  let output ← liftResult <|
    Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf output
  let abi ← match files.find? (·.path.endsWith ".near-abi.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "AbiMw missing near-abi.json"
  expect (abi.contains "\"type\":\"u8-le\"")
    "AbiMw ABI must expose u8-le for narrow field/param"
  expect (abi.contains "\"type\":\"u16-le\"" && abi.contains "\"type\":\"u32-le\"")
    "AbiMw ABI must expose u16-le/u32-le"
  -- Entry/view results stay UInt64 (JSON `returns` field, not a `type` key).
  expect (abi.contains "\"returns\":\"u64-le\"")
    "AbiMw ABI result remains u64-le"
  let wat ← match files.find? (·.path.endsWith ".wat") with
    | some f => pure f.contents
    | none => throw <| IO.userError "AbiMw missing wat"
  expectContains wat "i32.load8_u" "AbiMw WAT narrow param/state load8"
  expectContains wat "i32.store8" "AbiMw WAT narrow store8"
  expectContains wat "i32.load16_u" "AbiMw WAT narrow load16"
  expectContains wat "i32.store16" "AbiMw WAT narrow store16"
  expectContains wat "(i64.const 1)" "AbiMw WAT storage_write length 1 present"
  expectContains wat "(i64.const 2)" "AbiMw WAT storage_write length 2 present"
  expectContains wat "(i64.const 4)" "AbiMw WAT storage_write length 4 present"
  -- Host model: init packs three narrow params in 24-byte input (8-byte slots).
  let flagKey := ir.keys[1]!.key
  let scoreKey := ir.keys[2]!.key
  let ticksKey := ir.keys[3]!.key
  let empty : HostStorage := #[]
  let zero : Deposit := { lowWord := 0, highWord := 0 }
  let initInput :=
    encodeUIntLE 7 1 ++ repeatedByte 7 0 ++
    encodeUIntLE 300 2 ++ repeatedByte 6 0 ++
    encodeUIntLE 40000 4 ++ repeatedByte 4 0
  expect (initInput.size == 24) "AbiMw init input is 3×8 slots"
  let (storage0, _, _) ← requireSuccess "AbiMw init"
    (execute initializer empty initInput zero)
  let flag0 ← match storageLookup? storage0 flagKey with
    | some b => pure b
    | none => throw <| IO.userError "AbiMw init missing flag key"
  let score0 ← match storageLookup? storage0 scoreKey with
    | some b => pure b
    | none => throw <| IO.userError "AbiMw init missing score key"
  let ticks0 ← match storageLookup? storage0 ticksKey with
    | some b => pure b
    | none => throw <| IO.userError "AbiMw init missing ticks key"
  expect (decodeUIntLE flag0 1 == some 7) "AbiMw init stores UInt8 flag"
  expect (decodeUIntLE score0 2 == some 300) "AbiMw init stores UInt16 score"
  expect (decodeUIntLE ticks0 4 == some 40000) "AbiMw init stores UInt32 ticks"
  let setInput := encodeUIntLE 9 1 ++ repeatedByte 7 0
  let (storage1, ret1, _) ← requireSuccess "AbiMw setFlag"
    (execute setFlagIR storage0 setInput zero)
  expect (ret1 == some 0) "AbiMw setFlag returns 0"
  let flag1 ← match storageLookup? storage1 flagKey with
    | some b => pure b
    | none => throw <| IO.userError "AbiMw setFlag missing flag key"
  expect (decodeUIntLE flag1 1 == some 9) "AbiMw setFlag overwrites UInt8 flag"

/-- T8b-NEAR: UInt128 state remains fail-closed. -/
private unsafe def testUInt128StateRejected (session : Language.Loader.ParserSession) :
    IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program U128State where\n" ++
    "  state big : UInt128\n\n" ++
    "  init() do\n" ++
    "    big := 0\n\n" ++
    "  entry noop() : UInt64 do\n" ++
    "    return 0\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    sourceText "<near-host-u128>" "Examples.U128State" none)
  match Compiler.compileValidatedSourceV1 source with
  | .error _ => pure ()
  | .ok compiled =>
      let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
      match Targets.resolveEngineeringRequirementsV1 selection compiled with
      | .error _ => pure ()
      | .ok capability =>
          match Targets.Near.planFromCapability capability with
          | .error e =>
              expect (e.render.contains "UInt64" || e.render.contains "not public" ||
                  e.render.contains "unsupported")
                s!"UInt128 state must fail closed with planInvariant, got {e.render}"
          | .ok _ =>
              throw <| IO.userError "UInt128 state must fail closed at NEAR plan"

/-- T8b-NEAR: Int8 param remains fail-closed (narrow Int not on ABI surface). -/
private unsafe def testInt8ParamRejected (session : Language.Loader.ParserSession) :
    IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program Int8Param where\n" ++
    "  state count : UInt64\n\n" ++
    "  init() do\n" ++
    "    count := 0\n\n" ++
    "  entry set(x : Int8) : UInt64 do\n" ++
    "    return 0\n\n" ++
    "end ProofForgeV2.Examples\n"
  let source ← liftResult (← session.selectProgramV1
    sourceText "<near-host-i8>" "Examples.Int8Param" none)
  match Compiler.compileValidatedSourceV1 source with
  | .error _ => pure ()
  | .ok compiled =>
      let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
      match Targets.resolveEngineeringRequirementsV1 selection compiled with
      | .error _ => pure ()
      | .ok capability =>
          match Targets.Near.planFromCapability capability with
          | .error e =>
              expect (e.render.contains "UInt64" || e.render.contains "not public" ||
                  e.render.contains "unsupported")
                s!"Int8 param must fail closed, got {e.render}"
          | .ok _ =>
              throw <| IO.userError "Int8 param must fail closed at NEAR plan"

unsafe def run : IO Unit := do
  runCheckedSubFast
  runCompareAssertFast
  let session ← Tests.Language.ParserSession.shared
  testIfFlowProductPath session
  testMatchProductPath session
  testBranchAssertTrap session
  testEarlyReturnJoinProductPath session
  testInitEarlyBareReturnClosed session
  testFnLocalCallProductPath session
  testEmitRevertProductPath session
  testArithOpsProductPath session
  testIsolatedModZeroProductPath session
  testMultiStateHostExecution session
  testForLoopProductPath session
  testShiftBitwiseLogicalProductPath session
  testScheduleProductPath session
  testVoidEntryFailClosed session
  testMultipleEventsProductPath session
  testZeroArgRevertProductPath session
  testBoolResultPureFnProductPath session
  testOmittedTypeLetProductPath session
  testBoolNotHostExecution session
  testAbiMultiWidthStateParam session
  testUInt128StateRejected session
  testInt8ParamRejected session
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

  let (initialized, initReturn, _) ← requireSuccess "eight-byte init input" <|
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

  let (_, initialViewReturn, _) ← requireSuccess "zero-parameter view" <|
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

  let (added, addReturn, _) ← requireSuccess "7 + 5 mutate" <|
    execute add initialized (encodeUInt64LE 5) zeroDeposit
  expect (addReturn == some 12 && storedUInt64? added field.key == some 12)
    "mutate must store 12 and its post-store state read must return 12"
  let (_, currentReturn, _) ← requireSuccess "view after mutate" <|
    execute current added ByteArray.empty zeroDeposit
  expect (currentReturn == some 12) "view must observe the committed mutate state"

  let maximum := UInt64.ofNat 18446744073709551615
  let (maximumState, _, _) ← requireSuccess "maximum UInt64 init" <|
    execute initializer empty (encodeUInt64LE maximum) zeroDeposit
  expectTrap "maximum UInt64 plus one" maximumState <|
    execute add maximumState (encodeUInt64LE 1) zeroDeposit

  -- Comparison + assert envelope product paths.
  testGuardedCounterProductPath session
  testAllComparisonOpsWat session
  testAssertElseRejected session
  testBoolStateParamRejected session
  testBoolResultKindMismatchRejected session
  testBoolResultAccepted session
  testBoolPredicateProductPath session
  -- T8b-NEAR: state/param UInt{8,16,32} ABI multi-width.
  testNarrowAbiProductPath session
  testNarrowAbiNegatives session
  testNarrowResultProductPath session
  -- T8c-NEAR: body multi-width UInt8 add success + overflow.
  testNarrowBodyProductPath session
  IO.println "Tests.Materialization.NearHostModel: ok"

end Tests.Materialization.NearHostModel

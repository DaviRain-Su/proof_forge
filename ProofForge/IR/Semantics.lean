import ProofForge.IR.Contract
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.EvmAbiAggregateProbe
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmStorageStructProbe

namespace ProofForge.IR.Semantics

open ProofForge.IR

local instance instDecidableEqExcept {ε α : Type} [DecidableEq ε] [DecidableEq α] :
    DecidableEq (Except ε α) := by
  intro lhs rhs
  cases lhs with
  | error lhsError =>
      cases rhs with
      | error rhsError =>
          cases decEq lhsError rhsError with
          | isTrue equal =>
              exact isTrue (by cases equal; rfl)
          | isFalse notEqual =>
              exact isFalse (by intro equal; cases equal; exact notEqual rfl)
      | ok _ =>
          exact isFalse (by intro equal; cases equal)
  | ok lhsValue =>
      cases rhs with
      | error _ =>
          exact isFalse (by intro equal; cases equal)
      | ok rhsValue =>
          cases decEq lhsValue rhsValue with
          | isTrue equal =>
              exact isTrue (by cases equal; rfl)
          | isFalse notEqual =>
              exact isFalse (by intro equal; cases equal; exact notEqual rfl)

/-! A small executable semantics for the scalar IR subset.

This is the first formal anchor for proving the NEAR Wasm path: proofs can
state the intended IR behavior here, while later refinement lemmas relate
EmitWat output to these traces.
-/

inductive Value where
  | unit
  | bool (value : Bool)
  | u8 (value : Nat)
  | u128 (value : Nat)
  | u32 (value : Nat)
  | u64 (value : Nat)
  | address (value : Nat)
  | bytes (values : List Nat)
  | string (value : String)
  | hash (a b c d : Nat)
  | array (values : List Value)
  | struct (typeName : String) (fields : List (String × Value))
  deriving Repr, BEq

structure EventLog where
  name : String
  indexed : Array Value := #[]
  data : Array Value := #[]
  deriving Repr, BEq

def maxU32 : Nat := 4294967295

abbrev Bindings := List (String × Value)

def lookup (name : String) : Bindings → Option Value
  | [] => none
  | (key, value) :: rest =>
      if key == name then
        some value
      else
        lookup name rest

def insert (name : String) (value : Value) : Bindings → Bindings
  | [] => [(name, value)]
  | (key, oldValue) :: rest =>
      if key == name then
        (key, value) :: rest
      else
        (key, oldValue) :: insert name value rest

def listGet? {α : Type} : List α → Nat → Option α
  | [], _ => none
  | value :: _, 0 => some value
  | _ :: rest, index + 1 => listGet? rest index

structure State where
  storage : Bindings := []
  logs : Array EventLog := #[]
  deriving Repr, BEq

structure Frame where
  locals : Bindings := []
  structs : Array StructDecl := #[]
  deriving Repr

def State.empty : State := {}

def Frame.empty : Frame := {}

def State.read (state : State) (name : String) : Option Value :=
  lookup name state.storage

def fieldKey (base fieldName : String) : String :=
  s!"{base}.{fieldName}"

def arrayKey (base : String) (index : Nat) : String :=
  s!"{base}[{index}]"

def arrayFieldKey (base : String) (index : Nat) (fieldName : String) : String :=
  s!"{arrayKey base index}.{fieldName}"

def mapKey (base key : String) : String :=
  base ++ "{" ++ key ++ "}"

def mapPresentKey (base key : String) : String :=
  s!"{mapKey base key}.present"

partial def writeStructFields (storage : Bindings) (base : String) (fields : List (String × Value)) : Bindings :=
  fields.foldl (fun acc (fieldName, fieldValue) =>
    let acc := insert (fieldKey base fieldName) fieldValue acc
    match fieldValue with
    | .struct _ inner => writeStructFields acc (fieldKey base fieldName) inner
    | _ => acc) storage

def State.write (state : State) (name : String) (value : Value) : State :=
  let state := { state with storage := insert name value state.storage }
  match value with
  | .struct _ fields =>
      { state with storage := writeStructFields state.storage name fields }
  | _ => state

def State.recordEvent (state : State) (name : String)
    (indexed data : Array Value) : State :=
  { state with logs := state.logs.push { name, indexed, data } }

def State.readStructField (state : State) (stateId fieldName : String) : Option Value :=
  match state.read (fieldKey stateId fieldName) with
  | some value => some value
  | none =>
      match state.read stateId with
      | some (.struct _ fields) => lookup fieldName fields
      | _ => none

def Frame.read (frame : Frame) (name : String) : Option Value :=
  lookup name frame.locals

def Frame.write (frame : Frame) (name : String) (value : Value) : Frame :=
  { frame with locals := insert name value frame.locals }

def literalValue : Literal → Except String Value
  | .u8 value => .ok (.u8 value)
  | .u128 value => .ok (.u128 value)
  | .u32 value => .ok (.u32 value)
  | .u64 value => .ok (.u64 value)
  | .bool value => .ok (.bool value)
  | .hash4 a b c d => .ok (.hash a b c d)
  | .address value => .ok (.address value)

def valueMatchesType : ValueType → Value → Bool
  | .unit, .unit => true
  | .bool, .bool _ => true
  | .u8, .u8 _ => true
  | .u32, .u32 _ => true
  | .u128, .u128 _ => true
  | .u64, .u64 _ => true
  | .address, .address _ => true
  | .bytes, .bytes _ => true
  | .string, .string _ => true
  | .hash, .hash _ _ _ _ => true
  | .fixedArray element length, .array values =>
      values.length == length && values.all (valueMatchesType element)
  | .structType expected, .struct actual _ => expected == actual
  | _, _ => false

partial def zeroLike : Value → Value
  | .unit => .unit
  | .bool _ => .bool false
  | .u8 _ => .u8 0
  | .u32 _ => .u32 0
  | .u128 _ => .u128 0
  | .u64 _ => .u64 0
  | .address _ => .address 0
  | .bytes _ => .bytes []
  | .string _ => .string ""
  | .hash _ _ _ _ => .hash 0 0 0 0
  | .array values => .array (values.map zeroLike)
  | .struct typeName fields => .struct typeName (fields.map fun field => (field.fst, zeroLike field.snd))

partial def valueKey : Value → String
  | .unit => "unit"
  | .bool value => if value then "true" else "false"
  | .u8 value => s!"u8:{value}"
  | .u32 value => s!"u32:{value}"
  | .u128 value => s!"u128:{value}"
  | .u64 value => s!"u64:{value}"
  | .address value => s!"addr:{value}"
  | .bytes values => "bytes:" ++ String.intercalate "," (values.map toString)
  | .string value => s!"str:{value}"
  | .hash a b c d => s!"hash:{a}:{b}:{c}:{d}"
  | .array values =>
      "[" ++ String.intercalate "," (values.map valueKey) ++ "]"
  | .struct typeName fields =>
      let rendered :=
        fields.map fun field => s!"{field.fst}={valueKey field.snd}"
      typeName ++ "{" ++ String.intercalate "," rendered ++ "}"

def indexValue : Value → Except String Nat
  | .u8 value => .ok value
  | .u32 value => .ok value
  | .u128 value => .ok value
  | .u64 value => .ok value
  | _ => .error "array/storage index expects U8, U32, U64, or U128"

def arrayGetValue (value : Value) (index : Nat) : Except String Value :=
  match value with
  | .array values =>
      match listGet? values index with
      | some value => .ok value
      | none => .error s!"array index {index} out of bounds"
  | _ => .error "arrayGet expects an array value"

def structFieldValue (value : Value) (fieldName : String) : Except String Value :=
  match value with
  | .struct _ fields =>
      match lookup fieldName fields with
      | some value => .ok value
      | none => .error s!"unknown struct field `{fieldName}`"
  | _ => .error "field access expects a struct value"

def bindParams (params : Array (String × ValueType)) (args : Array Value)
    (structs : Array StructDecl := #[]) : Except String Frame := do
  if params.size != args.size then
    .error s!"entrypoint expected {params.size} argument(s), got {args.size}"
  let mut frame := { Frame.empty with structs := structs }
  for h : idx in [0:params.size] do
    let param := params[idx]
    let some arg := args[idx]?
      | .error s!"missing entrypoint argument {idx}"
    if valueMatchesType param.snd arg then
      frame := frame.write param.fst arg
    else
      .error s!"entrypoint argument `{param.fst}` does not match `{param.snd.name}`"
  .ok frame

def evalNumericBinary (opName : String) (op : Nat → Nat → Nat) (lhs rhs : Value) :
    Except String Value :=
  match lhs, rhs with
  | .u64 lhsValue, .u64 rhsValue => .ok (.u64 (op lhsValue rhsValue))
  | .u32 lhsValue, .u32 rhsValue => .ok (.u32 (op lhsValue rhsValue))
  | .u8 lhsValue, .u8 rhsValue => .ok (.u8 (op lhsValue rhsValue))
  | .u128 lhsValue, .u128 rhsValue => .ok (.u128 (op lhsValue rhsValue))
  | _, _ => .error s!"{opName} expects matching numeric operands"

def evalNumericPredicate (opName : String) (op : Nat → Nat → Bool) (lhs rhs : Value) :
    Except String Value :=
  match lhs, rhs with
  | .u64 lhsValue, .u64 rhsValue => .ok (.bool (op lhsValue rhsValue))
  | .u32 lhsValue, .u32 rhsValue => .ok (.bool (op lhsValue rhsValue))
  | .u8 lhsValue, .u8 rhsValue => .ok (.bool (op lhsValue rhsValue))
  | .u128 lhsValue, .u128 rhsValue => .ok (.bool (op lhsValue rhsValue))
  | _, _ => .error s!"{opName} expects matching numeric operands"

def evalEquality (lhs rhs : Value) : Except String Value :=
  match lhs, rhs with
  | .unit, .unit => .ok (.bool true)
  | .bool lhsValue, .bool rhsValue => .ok (.bool (lhsValue == rhsValue))
  | .u64 lhsValue, .u64 rhsValue => .ok (.bool (lhsValue == rhsValue))
  | .u32 lhsValue, .u32 rhsValue => .ok (.bool (lhsValue == rhsValue))
  | .u8 lhsValue, .u8 rhsValue => .ok (.bool (lhsValue == rhsValue))
  | .u128 lhsValue, .u128 rhsValue => .ok (.bool (lhsValue == rhsValue))
  | .hash a0 b0 c0 d0, .hash a1 b1 c1 d1 =>
      .ok (.bool (a0 == a1 && b0 == b1 && c0 == c1 && d0 == d1))
  | .address lhsValue, .address rhsValue => .ok (.bool (lhsValue == rhsValue))
  | .bytes lhsValues, .bytes rhsValues => .ok (.bool (lhsValues == rhsValues))
  | .string lhsValue, .string rhsValue => .ok (.bool (lhsValue == rhsValue))
  | .array lhsValues, .array rhsValues => .ok (.bool (lhsValues == rhsValues))
  | .struct lhsName lhsFields, .struct rhsName rhsFields =>
      .ok (.bool (lhsName == rhsName && lhsFields == rhsFields))
  | _, _ => .error "equality expects matching operands"

def evalBooleanBinary (opName : String) (op : Bool → Bool → Bool) (lhs rhs : Value) :
    Except String Value :=
  match lhs, rhs with
  | .bool lhsValue, .bool rhsValue => .ok (.bool (op lhsValue rhsValue))
  | _, _ => .error s!"{opName} expects Bool operands"

def castValue (value : Value) (targetType : ValueType) : Except String Value :=
  match value, targetType with
  | .bool value, .bool => .ok (.bool value)
  | .bool value, .u8 => .ok (.u8 (if value then 1 else 0))
  | .bool value, .u128 => .ok (.u128 (if value then 1 else 0))
  | .bool value, .u32 => .ok (.u32 (if value then 1 else 0))
  | .bool value, .u64 => .ok (.u64 (if value then 1 else 0))
  | .u32 value, .u32 => .ok (.u32 value)
  | .u32 value, .u64 => .ok (.u64 value)
  | .u32 0, .bool => .ok (.bool false)
  | .u32 1, .bool => .ok (.bool true)
  | .u32 _, .bool => .error "U32 to Bool cast expects canonical 0 or 1"
  | .u8 value, .u8 => .ok (.u8 value)
  | .u8 value, .u32 => .ok (.u32 value)
  | .u8 value, .u64 => .ok (.u64 value)
  | .u8 value, .u128 => .ok (.u128 value)
  | .u8 0, .bool => .ok (.bool false)
  | .u8 1, .bool => .ok (.bool true)
  | .u8 _, .bool => .error "U8 to Bool cast expects canonical 0 or 1"
  | .u64 value, .u64 => .ok (.u64 value)
  | .u64 value, .u32 =>
      if value <= maxU32 then
        .ok (.u32 value)
      else
        .error "U64 to U32 cast exceeds U32 range"
  | .u32 value, .u8 => .ok (.u8 value)
  | .u32 value, .u128 => .ok (.u128 value)
  | .u64 0, .bool => .ok (.bool false)
  | .u64 1, .bool => .ok (.bool true)
  | .u64 _, .bool => .error "U64 to Bool cast expects canonical 0 or 1"
  | .u64 value, .u8 => .ok (.u8 value)
  | .u64 value, .u128 => .ok (.u128 value)
  | .u128 value, .u128 => .ok (.u128 value)
  | .u128 value, .u64 => .ok (.u64 value)
  | .u128 value, .u32 => .ok (.u32 value)
  | .u128 value, .u8 => .ok (.u8 value)
  | .hash a b c d, .hash => .ok (.hash a b c d)
  | .address value, .address => .ok (.address value)
  | .u64 value, .address => .ok (.address value)
  | .address value, .u64 => .ok (.u64 value)
  | .bytes values, .bytes => .ok (.bytes values)
  | .string value, .string => .ok (.string value)
  | _, _ => .error s!"cast to `{targetType.name}` is not supported by the scalar semantics model"

def truthy : Value → Except String Bool
  | .bool value => .ok value
  | _ => .error "assertion condition expects Bool"

def evalAssignOp (op : AssignOp) (lhs rhs : Value) : Except String Value :=
  match op with
  | .add => evalNumericBinary "assignAdd" (· + ·) lhs rhs
  | .sub => evalNumericBinary "assignSub" (· - ·) lhs rhs
  | .mul => evalNumericBinary "assignMul" (· * ·) lhs rhs
  | .div => evalNumericBinary "assignDiv" (fun lhs rhs => if rhs == 0 then 0 else lhs / rhs) lhs rhs
  | .mod => evalNumericBinary "assignMod" (fun lhs rhs => if rhs == 0 then 0 else lhs % rhs) lhs rhs
  | .bitAnd => evalNumericBinary "assignBitAnd" Nat.land lhs rhs
  | .bitOr => evalNumericBinary "assignBitOr" Nat.lor lhs rhs
  | .bitXor => evalNumericBinary "assignBitXor" Nat.xor lhs rhs
  | .shiftLeft => evalNumericBinary "assignShiftLeft" (fun lhs rhs => lhs * (2 ^ rhs)) lhs rhs
  | .shiftRight => evalNumericBinary "assignShiftRight" (fun lhs rhs => lhs / (2 ^ rhs)) lhs rhs

abbrev ExprResult := State × Value

partial def crosscallArgToNat (value : Value) : Except String Nat :=
  match value with
  | .u64 n | .u32 n | .u8 n => pure n
  | .bool b => pure (if b then 1 else 0)
  | .hash a b c d => pure (a + b + c + d)
  | .struct _ fields => do
      let mut sum := 0
      for (_, fieldValue) in fields do
        sum := sum + (← crosscallArgToNat fieldValue)
      pure sum
  | .array values => do
      let mut sum := 0
      for elem in values do
        sum := sum + (← crosscallArgToNat elem)
      pure sum
  | _ => .error "crosscall argument expected scalar or aggregate"

def crosscallHashStubValue (sum : Nat) : Value :=
  match sum % 3 with
  | 0 => .hash 1001 0 0 0
  | 1 => .hash 2002 0 0 0
  | _ => .hash 3003 0 0 0

def crosscallStaticTag : Nat := 1000000
def crosscallDelegateTag : Nat := 2000000
def crosscallCreateTag : Nat := 3000000
def crosscallCreate2Tag : Nat := 4000000

def lookupStructDecl (structs : Array StructDecl) (name : String) : Option StructDecl :=
  structs.find? (fun s => s.name == name)

partial def crosscallCastReturnAt (sum offset : Nat) (returnType : ValueType) (structs : Array StructDecl) :
    Except String (Value × Nat) := do
  let atSum := sum + offset
  match returnType with
  | .u64 => pure (.u64 atSum, offset + 1)
  | .u32 => pure (.u32 (atSum % 4294967296), offset + 1)
  | .bool => pure (.bool (atSum % 2 == 1), offset + 1)
  | .hash => pure (crosscallHashStubValue atSum, offset + 1)
  | .structType typeName =>
      match lookupStructDecl structs typeName with
      | none => .error s!"unknown struct `{typeName}` for crosscall aggregate return"
      | some structDecl => do
          let mut off := offset
          let mut fields := []
          for field in structDecl.fields do
            let (fieldValue, nextOff) ← crosscallCastReturnAt sum off field.type structs
            fields := fields ++ [(field.id, fieldValue)]
            off := nextOff
          pure (.struct typeName fields, off)
  | .fixedArray elem length => do
    let rec go (i off : Nat) (acc : List Value) : Except String (Value × Nat) := do
      if i >= length then
        pure (.array acc, off)
      else
        let (elemValue, nextOff) ← crosscallCastReturnAt sum off elem structs
        go (i + 1) nextOff (acc ++ [elemValue])
    go 0 offset []
  | _ => .error s!"typed crosscall return `{returnType.name}` is not supported by scalar semantics"

def crosscallCastReturn (sum : Nat) (returnType : ValueType) (structs : Array StructDecl := #[]) :
    Except String Value := do
  let (value, _) ← crosscallCastReturnAt sum 0 returnType structs
  pure value

mutual
partial def evalExpr (state : State) (frame : Frame) : Expr → Except String ExprResult
  | .literal literal => do
      let value ← literalValue literal
      .ok (state, value)
  | .local name =>
      match frame.read name with
      | some value => .ok (state, value)
      | none => .error s!"unknown local `{name}`"
  | .arrayLit _ values => do
      let mut nextState := state
      let mut evaluated := #[]
      for value in values do
        let (stateAfterValue, evaluatedValue) ← evalExpr nextState frame value
        nextState := stateAfterValue
        evaluated := evaluated.push evaluatedValue
      .ok (nextState, .array evaluated.toList)
  | .arrayGet array index => do
      let (stateAfterArray, arrayValue) ← evalExpr state frame array
      let (stateAfterIndex, rawIndex) ← evalExpr stateAfterArray frame index
      let indexValue ← indexValue rawIndex
      .ok (stateAfterIndex, ← arrayGetValue arrayValue indexValue)
  | .structLit typeName fields => do
      let mut nextState := state
      let mut evaluated := #[]
      for field in fields do
        let (stateAfterField, fieldValue) ← evalExpr nextState frame field.snd
        nextState := stateAfterField
        evaluated := evaluated.push (field.fst, fieldValue)
      .ok (nextState, .struct typeName evaluated.toList)
  | .field base fieldName => do
      let (nextState, baseValue) ← evalExpr state frame base
      .ok (nextState, ← structFieldValue baseValue fieldName)
  | .add lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "add" (· + ·) lhsValue rhsValue)
  | .sub lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "sub" (· - ·) lhsValue rhsValue)
  | .mul lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "mul" (· * ·) lhsValue rhsValue)
  | .div lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "div" (fun lhs rhs => if rhs == 0 then 0 else lhs / rhs)
        lhsValue rhsValue)
  | .mod lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "mod" (fun lhs rhs => if rhs == 0 then 0 else lhs % rhs)
        lhsValue rhsValue)
  | .pow lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "pow" (fun lhs rhs => lhs ^ rhs)
        lhsValue rhsValue)
  | .bitAnd lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "bitAnd" Nat.land lhsValue rhsValue)
  | .bitOr lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "bitOr" Nat.lor lhsValue rhsValue)
  | .bitXor lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "bitXor" Nat.xor lhsValue rhsValue)
  | .shiftLeft lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "shiftLeft" (fun lhs rhs => lhs * (2 ^ rhs))
        lhsValue rhsValue)
  | .shiftRight lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericBinary "shiftRight" (fun lhs rhs => lhs / (2 ^ rhs))
        lhsValue rhsValue)
  | .cast value targetType => do
      let (nextState, rawValue) ← evalExpr state frame value
      .ok (nextState, ← castValue rawValue targetType)
  | .eq lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalEquality lhsValue rhsValue)
  | .ne lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      match ← evalEquality lhsValue rhsValue with
      | .bool value => .ok (stateAfterRhs, .bool (!value))
      | _ => .error "equality returned a non-Bool value"
  | .lt lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericPredicate "lt" (· < ·) lhsValue rhsValue)
  | .le lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericPredicate "le" (· <= ·) lhsValue rhsValue)
  | .gt lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericPredicate "gt" (· > ·) lhsValue rhsValue)
  | .ge lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalNumericPredicate "ge" (· >= ·) lhsValue rhsValue)
  | .boolAnd lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalBooleanBinary "boolAnd" (fun lhs rhs => lhs && rhs)
        lhsValue rhsValue)
  | .boolOr lhs rhs => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      .ok (stateAfterRhs, ← evalBooleanBinary "boolOr" (fun lhs rhs => lhs || rhs)
        lhsValue rhsValue)
  | .boolNot value => do
      let (nextState, rawValue) ← evalExpr state frame value
      match rawValue with
      | .bool value => .ok (nextState, .bool (!value))
      | _ => .error "boolNot expects Bool operand"
  | .crosscallInvoke target methodId args => evalCrosscallInvoke state frame target methodId args
  | .crosscallInvokeTyped target methodId args returnType =>
      evalCrosscallInvokeTyped state frame target methodId args returnType
  | .crosscallInvokeValueTyped target methodId callValue args returnType =>
      evalCrosscallInvokeValueTyped state frame target methodId callValue args returnType
  | .crosscallInvokeStaticTyped target methodId args returnType =>
      evalCrosscallInvokeStaticTyped state frame target methodId args returnType
  | .crosscallInvokeDelegateTyped target methodId args returnType =>
      evalCrosscallInvokeDelegateTyped state frame target methodId args returnType
  | .crosscallCreate callValue _ => evalCrosscallCreate state frame callValue
  | .crosscallCreate2 callValue salt _ => evalCrosscallCreate2 state frame callValue salt
  | .effect effect => evalEffect state frame effect
  | .nativeValue => .ok (state, .u64 0)
  | _ => .error "expression is not supported by the scalar semantics model"

/-- Deterministic crosscall stub: sum target, method, and scalar args (aligned with Quint lowering). -/
partial def evalCrosscallInvokeSum (state : State) (frame : Frame) (target methodId : Expr)
    (args : Array Expr) : Except String (State × Nat) := do
  let (stateAfterTarget, targetValue) ← evalExpr state frame target
  let (stateAfterMethod, methodValue) ← evalExpr stateAfterTarget frame methodId
  let targetU64 ← match targetValue with
    | .u64 value => pure value
    | _ => .error "crosscall target expected U64"
  let methodU64 ← match methodValue with
    | .u64 value => pure value
    | _ => .error "crosscall method expected U64"
  let mut nextState := stateAfterMethod
  let mut sum := targetU64 + methodU64
  for arg in args do
    let (stateAfterArg, argValue) ← evalExpr nextState frame arg
    nextState := stateAfterArg
    let argNat ← crosscallArgToNat argValue
    sum := sum + argNat
  .ok (nextState, sum)

partial def evalCrosscallInvoke (state : State) (frame : Frame) (target methodId : Expr)
    (args : Array Expr) : Except String ExprResult := do
  let (nextState, sum) ← evalCrosscallInvokeSum state frame target methodId args
  .ok (nextState, .u64 sum)

partial def evalCrosscallInvokeTyped (state : State) (frame : Frame) (target methodId : Expr)
    (args : Array Expr) (returnType : ValueType) : Except String ExprResult := do
  let (nextState, sum) ← evalCrosscallInvokeSum state frame target methodId args
  let value ← crosscallCastReturn sum returnType frame.structs
  .ok (nextState, value)

partial def evalCrosscallInvokeValueTyped (state : State) (frame : Frame) (target methodId callValue : Expr)
    (args : Array Expr) (returnType : ValueType) : Except String ExprResult := do
  let (stateAfterValue, callValueResult) ← evalExpr state frame callValue
  let callNat ← match callValueResult with
    | .u64 n => pure n
    | _ => .error "value-bearing crosscall callValue expected U64"
  let (nextState, sum) ← evalCrosscallInvokeSum stateAfterValue frame target methodId args
  let value ← crosscallCastReturn (sum + callNat) returnType frame.structs
  .ok (nextState, value)

partial def evalCrosscallInvokeStaticTyped (state : State) (frame : Frame) (target methodId : Expr)
    (args : Array Expr) (returnType : ValueType) : Except String ExprResult := do
  let (nextState, sum) ← evalCrosscallInvokeSum state frame target methodId args
  let value ← crosscallCastReturn (sum + crosscallStaticTag) returnType frame.structs
  .ok (nextState, value)

partial def evalCrosscallInvokeDelegateTyped (state : State) (frame : Frame) (target methodId : Expr)
    (args : Array Expr) (returnType : ValueType) : Except String ExprResult := do
  let (nextState, sum) ← evalCrosscallInvokeSum state frame target methodId args
  let value ← crosscallCastReturn (sum + crosscallDelegateTag) returnType frame.structs
  .ok (nextState, value)

partial def evalCrosscallCreate (state : State) (frame : Frame) (callValue : Expr) :
    Except String ExprResult := do
  let (nextState, callValueResult) ← evalExpr state frame callValue
  let callNat ← match callValueResult with
    | .u64 n => pure n
    | _ => .error "crosscallCreate callValue expected U64"
  .ok (nextState, .u64 (callNat + crosscallCreateTag))

partial def evalCrosscallCreate2 (state : State) (frame : Frame) (callValue salt : Expr) :
    Except String ExprResult := do
  let (stateAfterValue, callValueResult) ← evalExpr state frame callValue
  let callNat ← match callValueResult with
    | .u64 n => pure n
    | _ => .error "crosscallCreate2 callValue expected U64"
  let (nextState, saltValue) ← evalExpr stateAfterValue frame salt
  let saltNat ← crosscallArgToNat saltValue
  .ok (nextState, .u64 (callNat + saltNat + crosscallCreate2Tag))

partial def evalPathSegmentKey (state : State) (frame : Frame) : StoragePathSegment →
    Except String (State × String)
  | .field fieldName => .ok (state, s!".{fieldName}")
  | .index indexExpr => do
      let (nextState, rawIndex) ← evalExpr state frame indexExpr
      let index ← indexValue rawIndex
      .ok (nextState, s!"[{index}]")
  | .mapKey keyExpr => do
      let (nextState, key) ← evalExpr state frame keyExpr
      .ok (nextState, "{" ++ valueKey key ++ "}")

partial def evalStoragePathKey (state : State) (frame : Frame) (stateId : String)
    (path : Array StoragePathSegment) : Except String (State × String) := do
  let mut nextState := state
  let mut key := stateId
  for segment in path do
    let (stateAfterSegment, segmentKey) ← evalPathSegmentKey nextState frame segment
    nextState := stateAfterSegment
    key := key ++ segmentKey
  .ok (nextState, key)

partial def evalEffect (state : State) (frame : Frame) : Effect → Except String ExprResult
  | .storageScalarRead name =>
      match state.read name with
      | some value => .ok (state, value)
      | none => .error s!"unknown scalar state `{name}`"
  | .storageScalarWrite name valueExpr => do
      let (nextState, value) ← evalExpr state frame valueExpr
      .ok (nextState.write name value, .unit)
  | .storageScalarAssignOp name op valueExpr => do
      let current ←
        match state.read name with
        | some value => .ok value
        | none => .error s!"unknown scalar state `{name}`"
      let (nextState, rhs) ← evalExpr state frame valueExpr
      let value ← evalAssignOp op current rhs
      .ok (nextState.write name value, value)
  | .storageMapContains name keyExpr => do
      let (nextState, keyValue) ← evalExpr state frame keyExpr
      let key := valueKey keyValue
      .ok (nextState, .bool ((nextState.read (mapPresentKey name key)).isSome))
  | .storageMapGet name keyExpr => do
      let (nextState, keyValue) ← evalExpr state frame keyExpr
      let key := valueKey keyValue
      match nextState.read (mapKey name key) with
      | some value => .ok (nextState, value)
      | none => .error s!"unknown map state `{name}` key `{key}`"
  | .storageMapInsert name keyExpr valueExpr
  | .storageMapSet name keyExpr valueExpr => do
      let (stateAfterKey, keyValue) ← evalExpr state frame keyExpr
      let key := valueKey keyValue
      let (stateAfterValue, newValue) ← evalExpr stateAfterKey frame valueExpr
      let oldValue := (stateAfterValue.read (mapKey name key)).getD (zeroLike newValue)
      let nextState :=
        (stateAfterValue.write (mapKey name key) newValue).write (mapPresentKey name key) (.bool true)
      .ok (nextState, oldValue)
  | .storageArrayRead name indexExpr => do
      let (nextState, rawIndex) ← evalExpr state frame indexExpr
      let index ← indexValue rawIndex
      match nextState.read (arrayKey name index) with
      | some value => .ok (nextState, value)
      | none => .error s!"unknown array state `{name}` index {index}"
  | .storageArrayWrite name indexExpr valueExpr => do
      let (stateAfterIndex, rawIndex) ← evalExpr state frame indexExpr
      let index ← indexValue rawIndex
      let (stateAfterValue, value) ← evalExpr stateAfterIndex frame valueExpr
      .ok (stateAfterValue.write (arrayKey name index) value, .unit)
  | .storageArrayStructFieldRead name indexExpr fieldName => do
      let (nextState, rawIndex) ← evalExpr state frame indexExpr
      let index ← indexValue rawIndex
      match nextState.read (arrayFieldKey name index fieldName) with
      | some value => .ok (nextState, value)
      | none => .error s!"unknown array struct field `{name}[{index}].{fieldName}`"
  | .storageArrayStructFieldWrite name indexExpr fieldName valueExpr => do
      let (stateAfterIndex, rawIndex) ← evalExpr state frame indexExpr
      let index ← indexValue rawIndex
      let (stateAfterValue, value) ← evalExpr stateAfterIndex frame valueExpr
      .ok (stateAfterValue.write (arrayFieldKey name index fieldName) value, .unit)
  | .storageDynamicArrayPush name valueExpr => do
      let (stateAfterValue, value) ← evalExpr state frame valueExpr
      let length ←
        match stateAfterValue.read (s!"{name}.length") with
        | some lengthValue => indexValue lengthValue
        | none => .ok 0
      let nextState := stateAfterValue.write (s!"{name}.[{length}]") value
      let nextState := nextState.write (s!"{name}.length") (.u64 (length + 1))
      .ok (nextState, .unit)
  | .storageDynamicArrayPop name => do
      let length ←
        match state.read (s!"{name}.length") with
        | some lengthValue => indexValue lengthValue
        | none => .ok 0
      if length == 0 then
        .error s!"pop from empty dynamic array `{name}`"
      else
        .ok (state.write (s!"{name}.length") (.u64 (length - 1)), .unit)
  | .memoryArraySet _ _ _ =>
      .error "memory arrays are not supported by the IR semantics interpreter"
  | .storageStructFieldRead name fieldName => do
      match state.readStructField name fieldName with
      | some value => .ok (state, value)
      | none => .error s!"unknown struct field state `{name}.{fieldName}`"
  | .storageStructFieldWrite name fieldName valueExpr => do
      let (nextState, value) ← evalExpr state frame valueExpr
      .ok (nextState.write (fieldKey name fieldName) value, .unit)
  | .storagePathRead name path => do
      let (nextState, key) ← evalStoragePathKey state frame name path
      match nextState.read key with
      | some value => .ok (nextState, value)
      | none => .error s!"unknown storage path `{key}`"
  | .storagePathWrite name path valueExpr => do
      let (stateAfterPath, key) ← evalStoragePathKey state frame name path
      let (stateAfterValue, value) ← evalExpr stateAfterPath frame valueExpr
      let nextState := stateAfterValue.write key value
      let nextState :=
        if path.any (fun segment => match segment with | .mapKey _ => true | _ => false) then
          nextState.write (key ++ ".present") (.bool true)
        else
          nextState
      .ok (nextState, .unit)
  | .storagePathAssignOp name path op valueExpr => do
      let (stateAfterPath, key) ← evalStoragePathKey state frame name path
      let current ←
        match stateAfterPath.read key with
        | some value => .ok value
        | none => .error s!"unknown storage path `{key}`"
      let (stateAfterValue, rhs) ← evalExpr stateAfterPath frame valueExpr
      let value ← match current with
        | .hash _ _ _ _ => pure rhs
        | _ => evalAssignOp op current rhs
      .ok (stateAfterValue.write key value, value)
  | .contextRead field =>
      match field with
      | .userId | .contractId | .checkpointId | .timestamp | .epochHeight | .chainId | .gasPrice | .gasLeft | .baseFee | .prevRandao =>
          .ok (state, .u64 0)
      | .userIdHash | .randomSeed | .origin | .coinbase | .blockHash _ =>
          .ok (state, .hash 0 0 0 0)
  | .eventEmit name fields => do
      let (nextState, data) ← evalEventFields state frame fields
      .ok (nextState.recordEvent name #[] data, .unit)
  | .eventEmitIndexed name indexedFields dataFields => do
      let (nextState, indexed) ← evalEventFields state frame indexedFields
      let (nextState, data) ← evalEventFields nextState frame dataFields
      .ok (nextState.recordEvent name indexed data, .unit)

partial def evalEventFields (state : State) (frame : Frame) (fields : Array (String × Expr)) :
    Except String (State × Array Value) := do
  let mut nextState := state
  let mut values := #[]
  for field in fields do
    let (stateAfterField, value) ← evalExpr nextState frame field.snd
    nextState := stateAfterField
    values := values.push value
  pure (nextState, values)
end

def execEffectStmt (state : State) (frame : Frame) : Effect → Except String State
  | effect => do
      let (nextState, _) ← evalEffect state frame effect
      .ok nextState

mutual
partial def execStmt (state : State) (frame : Frame) : Statement →
    Except String (State × Frame × Option Value)
  | .letBind name _ value => do
      let (nextState, evaluated) ← evalExpr state frame value
      .ok (nextState, frame.write name evaluated, none)
  | .letMutBind name _ value => do
      let (nextState, evaluated) ← evalExpr state frame value
      .ok (nextState, frame.write name evaluated, none)
  | .assign target value =>
      match target with
      | .local name => do
          let (nextState, evaluated) ← evalExpr state frame value
          .ok (nextState, frame.write name evaluated, none)
      | _ => .error "assign target is not supported by the scalar semantics model"
  | .assignOp target op value =>
      match target with
      | .local name => do
          let current ← match frame.read name with
            | some v => pure v
            | none => .error s!"assignOp on unbound local `{name}`"
          let (nextState, rhs) ← evalExpr state frame value
          let updated ← evalAssignOp op current rhs
          .ok (nextState, frame.write name updated, none)
      | _ => .error "assignOp target is not supported by the scalar semantics model"
  | .effect effect => do
      .ok (← execEffectStmt state frame effect, frame, none)
  | .assert condition message _ => do
      let (nextState, conditionValue) ← evalExpr state frame condition
      if ← truthy conditionValue then
        .ok (nextState, frame, none)
      else
        .error s!"assertion failed: {message}"
  | .assertEq lhs rhs message _ => do
      let (stateAfterLhs, lhsValue) ← evalExpr state frame lhs
      let (stateAfterRhs, rhsValue) ← evalExpr stateAfterLhs frame rhs
      if lhsValue == rhsValue then
        .ok (stateAfterRhs, frame, none)
      else
        .error s!"assertion failed: {message}"
  | .revert message =>
      -- User-visible transaction rollback. Surfaced via the revert-shaped
      -- error string consumed by `ExecResult.ofExcept` / `runEntrypointResult`.
      .error s!"revert: {message}"
  | .revertWithError errorRef =>
      .error s!"revert: assertion_id={errorRef.assertionId}"
  | .ifElse condition thenBody elseBody => do
      let (nextState, conditionValue) ← evalExpr state frame condition
      let selectedBody := if ← truthy conditionValue then thenBody else elseBody
      let (branchState, returnValue?) ← execStatements selectedBody.toList nextState frame
      .ok (branchState, frame, returnValue?)
  | .boundedFor indexName start stopExclusive body =>
      execBoundedFor indexName start stopExclusive body state frame
  | .whileLoop condition body =>
      execWhileLoop condition body state frame
  | .return value => do
      let (nextState, returnValue) ← evalExpr state frame value
      .ok (nextState, frame, some returnValue)
  | _ => .error "statement is not supported by the scalar semantics model"

partial def execStatements : List Statement → State → Frame → Except String (State × Option Value)
  | [], state, _frame => .ok (state, none)
  | statement :: rest, state, frame => do
      let (nextState, nextFrame, returnValue?) ← execStmt state frame statement
      match returnValue? with
      | some returnValue => .ok (nextState, some returnValue)
      | none => execStatements rest nextState nextFrame

partial def execBoundedFor
    (indexName : String)
    (index stopExclusive : Nat)
    (body : Array Statement)
    (state : State)
    (frame : Frame) : Except String (State × Frame × Option Value) := do
  if index < stopExclusive then
    let loopFrame := frame.write indexName (.u32 index)
    let (nextState, returnValue?) ← execStatements body.toList state loopFrame
    match returnValue? with
    | some value => .ok (nextState, frame, some value)
    | none => execBoundedFor indexName (index + 1) stopExclusive body nextState frame
  else
    .ok (state, frame, none)

partial def execWhileLoop
    (condition : Expr)
    (body : Array Statement)
    (state : State)
    (frame : Frame) : Except String (State × Frame × Option Value) := do
  let (stateAfterCond, conditionValue) ← evalExpr state frame condition
  if ← truthy conditionValue then
    let (bodyState, returnValue?) ← execStatements body.toList stateAfterCond frame
    match returnValue? with
    | some value => .ok (bodyState, frame, some value)
    | none => execWhileLoop condition body bodyState frame
  else
    .ok (stateAfterCond, frame, none)
end

/-! ## Three-valued execution result

The interpreter historically returned `Except String`, which conflates two
distinct outcomes: a user-visible transaction rollback (e.g. `assert` failure,
explicit `revert`) and an internal interpreter error (unsupported construct).
`ExecResult` separates the two so that contract reverts become first-class.
The legacy `Except String` interface is preserved for existing callers; use
`ExecResult.ofExcept` to lift an `Except String` outcome into `ExecResult`. -/

inductive ExecResult (α : Type) where
  | ok (value : α)
  | reverted (message : String)
  | error (message : String)
  deriving Repr

/-- Classify an interpreter error string as a revert (user-visible rollback) or
a true error (interpreter gap). -/
def ExecResult.isRevertMessage (message : String) : Bool :=
  message.startsWith "assertion failed:" || message = "revert" ||
    message.startsWith "revert:"

/-- Lift a legacy `Except String` outcome into `ExecResult`, classifying
revert-shaped error strings as `.reverted` and everything else as `.error`. -/
def ExecResult.ofExcept {α : Type} (outcome : Except String α) : ExecResult α :=
  match outcome with
  | .ok v => .ok v
  | .error msg =>
      if isRevertMessage msg then .reverted msg else .error msg

def runEntrypointWithArgs (state : State) (entrypoint : Entrypoint) (args : Array Value)
    (structs : Array StructDecl := #[]) : Except String (State × Option Value) := do
  let frame ← bindParams entrypoint.params args structs
  execStatements entrypoint.body.toList state frame

def runEntrypoint (state : State) (entrypoint : Entrypoint) :
    Except String (State × Option Value) :=
  runEntrypointWithArgs state entrypoint #[]

/-- Same as `runEntrypointWithArgs` but returns a three-valued `ExecResult`
distinguishing `ok` / `reverted` / `error`. -/
def runEntrypointWithArgsResult (state : State) (entrypoint : Entrypoint)
    (args : Array Value) (structs : Array StructDecl := #[]) :
    ExecResult (State × Option Value) :=
  ExecResult.ofExcept (runEntrypointWithArgs state entrypoint args structs)

/-- Same as `runEntrypoint` but returns a three-valued `ExecResult`. -/
def runEntrypointResult (state : State) (entrypoint : Entrypoint) :
    ExecResult (State × Option Value) :=
  runEntrypointWithArgsResult state entrypoint #[]

/-! FV-2 metatheory anchors for the executable semantics. These are intentionally
small, but they make the interpreter's determinism and bounded-loop measure
explicit in Lean rather than leaving them as prose in the roadmap. -/

theorem evalExpr_deterministic {state : State} {frame : Frame} {expr : Expr}
    {lhs rhs : Except String ExprResult}
    (hLhs : evalExpr state frame expr = lhs)
    (hRhs : evalExpr state frame expr = rhs) :
    lhs = rhs :=
  hLhs.symm.trans hRhs

theorem execStatements_deterministic {statements : List Statement} {state : State}
    {frame : Frame} {lhs rhs : Except String (State × Option Value)}
    (hLhs : execStatements statements state frame = lhs)
    (hRhs : execStatements statements state frame = rhs) :
    lhs = rhs :=
  hLhs.symm.trans hRhs

theorem runEntrypointWithArgs_deterministic {state : State} {entrypoint : Entrypoint}
    {args : Array Value} {lhs rhs : Except String (State × Option Value)}
    (hLhs : runEntrypointWithArgs state entrypoint args = lhs)
    (hRhs : runEntrypointWithArgs state entrypoint args = rhs) :
    lhs = rhs :=
  hLhs.symm.trans hRhs

def boundedForRemaining (index stopExclusive : Nat) : Nat :=
  stopExclusive - index

theorem boundedForRemaining_decreases {index stopExclusive : Nat}
    (h : index < stopExclusive) :
    boundedForRemaining (index + 1) stopExclusive <
      boundedForRemaining index stopExclusive := by
  unfold boundedForRemaining
  omega

def counterTrace : Except String (State × Option Value) := do
  let (initialized, _) ←
    runEntrypoint State.empty ProofForge.IR.Examples.Counter.initializeEntrypoint
  let (incremented, _) ←
    runEntrypoint initialized ProofForge.IR.Examples.Counter.increment
  runEntrypoint incremented ProofForge.IR.Examples.Counter.get

def resultValue : Except String (State × Option Value) → Except String (Option Value)
  | .ok (_, value) => .ok value
  | .error message => .error message

def resultMatches (lhs rhs : Except String (State × Option Value)) : Bool :=
  match lhs, rhs with
  | .ok (lhsState, lhsValue), .ok (rhsState, rhsValue) =>
      lhsState == rhsState && lhsValue == rhsValue
  | .error lhsMessage, .error rhsMessage => lhsMessage == rhsMessage
  | _, _ => false

def resultValueMatches (result : Except String (State × Option Value)) (expected : Option Value) :
    Bool :=
  match resultValue result with
  | .ok actual => actual == expected
  | .error _ => false

def counterTraceGetsOne : Bool :=
  resultMatches counterTrace (.ok ({ storage := [("count", .u64 1)] }, some (.u64 1)))

theorem counter_trace_gets_one :
    counterTraceGetsOne = true := by
  native_decide

theorem counter_exports_match_near_entrypoints :
    ProofForge.IR.Examples.Counter.module.entrypoints.map (fun entrypoint => entrypoint.name) =
      #["initialize", "increment", "get"] := by
  native_decide

def arraySumLiteralTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.ArrayProbe.sumLiteral

theorem array_sum_literal_trace_returns_sixty :
    resultValueMatches arraySumLiteralTrace (some (.u64 60)) = true := by
  native_decide

def arrayStorageLifecycleTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.ArrayProbe.storageLifecycle

theorem array_storage_lifecycle_trace_returns_thirty_one :
    resultValueMatches arrayStorageLifecycleTrace (some (.u64 31)) = true := by
  native_decide

def arrayPredicatesTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.ArrayProbe.arrayPredicates

theorem array_predicates_trace_returns_one :
    resultValueMatches arrayPredicatesTrace (some (.u64 1)) = true := by
  native_decide

def abiSumPairTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.sumPair
    #[.struct "Pair" [("left", .u64 12), ("right", .u64 30)]]

theorem abi_sum_pair_trace_returns_forty_two :
    resultValueMatches abiSumPairTrace (some (.u64 42)) = true := by
  native_decide

def abiMakeArrayTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.makeArray
    #[.u64 1, .u64 2, .u64 3]

theorem abi_make_array_trace_returns_array :
    resultValueMatches abiMakeArrayTrace (some (.array [.u64 1, .u64 2, .u64 3])) = true := by
  native_decide

def mapLifecycleTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmMapProbe.mapLifecycle

theorem map_lifecycle_trace_returns_fifty_five :
    resultValueMatches mapLifecycleTrace (some (.u64 55)) = true := by
  native_decide

def mapContainsLifecycleTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmMapProbe.containsLifecycle

theorem map_contains_lifecycle_trace_returns_ninety_nine :
    resultValueMatches mapContainsLifecycleTrace (some (.u64 99)) = true := by
  native_decide

def mapParameterizedLifecycleTrace : Except String (List (Option Value)) := do
  let (stateAfterInsert, oldValue) ←
    runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmMapProbe.upsertBalance
      #[.u64 7007, .u64 123]
  let (stateAfterRead, insertedValue) ←
    runEntrypointWithArgs stateAfterInsert ProofForge.IR.Examples.EvmMapProbe.readBalance
      #[.u64 7007]
  let (stateAfterSet, _) ←
    runEntrypointWithArgs stateAfterRead ProofForge.IR.Examples.EvmMapProbe.setBalance
      #[.u64 7007, .u64 456]
  let (_, setValue) ←
    runEntrypointWithArgs stateAfterSet ProofForge.IR.Examples.EvmMapProbe.readBalance
      #[.u64 7007]
  .ok [oldValue, insertedValue, setValue]

def valuesTraceMatches (result : Except String (List (Option Value))) (expected : List (Option Value)) :
    Bool :=
  match result with
  | .ok actual => actual == expected
  | .error _ => false

theorem map_parameterized_lifecycle_trace_matches :
    valuesTraceMatches mapParameterizedLifecycleTrace
      [some (.u64 0), some (.u64 123), some (.u64 456)] = true := by
  native_decide

def mapPathLifecycleTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmMapProbe.pathLifecycle

theorem map_path_lifecycle_trace_returns_seventy_seven :
    resultValueMatches mapPathLifecycleTrace (some (.u64 77)) = true := by
  native_decide

def mapPathAssignLifecycleTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmMapProbe.pathAssignLifecycle

theorem map_path_assign_lifecycle_trace_returns_fifty_eight :
    resultValueMatches mapPathAssignLifecycleTrace (some (.u64 58)) = true := by
  native_decide

def mapNestedPathLifecycleTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmMapProbe.nestedPathLifecycle

theorem map_nested_path_lifecycle_trace_returns_ninety_five :
    resultValueMatches mapNestedPathLifecycleTrace (some (.u64 95)) = true := by
  native_decide

def mapNestedPathDynamicTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmMapProbe.nestedPathDynamic
    #[.u64 41, .u64 42, .u64 1234]

theorem map_nested_path_dynamic_trace_returns_argument_value :
    resultValueMatches mapNestedPathDynamicTrace (some (.u64 1234)) = true := by
  native_decide

def storageStructPathLifecycleTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmStorageStructProbe.pathLifecycle

theorem storage_struct_path_lifecycle_trace_returns_forty_eight :
    resultValueMatches storageStructPathLifecycleTrace (some (.u64 48)) = true := by
  native_decide

def storageStructLifecycleTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmStorageStructProbe.structLifecycle

theorem storage_struct_lifecycle_trace_returns_eighteen :
    resultValueMatches storageStructLifecycleTrace (some (.u64 18)) = true := by
  native_decide

def storageStructArrayLifecycleTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmStorageStructProbe.arrayStructLifecycle

theorem storage_struct_array_lifecycle_trace_returns_twelve :
    resultValueMatches storageStructArrayLifecycleTrace (some (.u64 12)) = true := by
  native_decide

def storageStructArrayPathLifecycleTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmStorageStructProbe.arrayPathLifecycle

theorem storage_struct_array_path_lifecycle_trace_returns_twenty_three :
    resultValueMatches storageStructArrayPathLifecycleTrace (some (.u64 23)) = true := by
  native_decide

def storageStructWholeWriteTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmStorageStructProbe.wholeStructWriteSum

theorem storage_struct_whole_write_trace_returns_seventy :
    resultValueMatches storageStructWholeWriteTrace (some (.u64 70)) = true := by
  native_decide

def storageStructWholeReturnTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmStorageStructProbe.wholeStructReturn

theorem storage_struct_whole_return_trace_returns_point :
    resultValueMatches storageStructWholeReturnTrace
      (some (.struct "Point" [("x", .u64 8), ("y", .u64 13)])) = true := by
  native_decide

def storageStructSelfWriteTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmStorageStructProbe.selfStructStorageWrite

theorem storage_struct_self_write_trace_returns_seven_hundred_five :
    resultValueMatches storageStructSelfWriteTrace (some (.u64 705)) = true := by
  native_decide

def storageStructReturnPointsTrace : Except String (State × Option Value) :=
  runEntrypoint State.empty ProofForge.IR.Examples.EvmStorageStructProbe.returnPoints

theorem storage_struct_return_points_trace_returns_array :
    resultValueMatches storageStructReturnPointsTrace
      (some (.array [
        .struct "Point" [("x", .u64 29), ("y", .u64 31)],
        .struct "Point" [("x", .u64 37), ("y", .u64 41)]
      ])) = true := by
  native_decide

def abiSumArrayTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.sumArray
    #[.array [.u64 4, .u64 5, .u64 6]]

theorem abi_sum_array_trace_returns_fifteen :
    resultValueMatches abiSumArrayTrace (some (.u64 15)) = true := by
  native_decide

def abiSumMatrixTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.sumMatrix
    #[.array [.array [.u64 1, .u64 2], .array [.u64 3, .u64 4]]]

theorem abi_sum_matrix_trace_returns_ten :
    resultValueMatches abiSumMatrixTrace (some (.u64 10)) = true := by
  native_decide

def abiSumPairArrayTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.sumPairArray
    #[.array [
      .struct "Pair" [("left", .u64 1), ("right", .u64 2)],
      .struct "Pair" [("left", .u64 3), ("right", .u64 4)]
    ]]

theorem abi_sum_pair_array_trace_returns_ten :
    resultValueMatches abiSumPairArrayTrace (some (.u64 10)) = true := by
  native_decide

def abiMakePairTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.makePair
    #[.u64 8, .u64 13]

theorem abi_make_pair_trace_returns_struct :
    resultValueMatches abiMakePairTrace
      (some (.struct "Pair" [("left", .u64 8), ("right", .u64 13)])) = true := by
  native_decide

def abiMakePairArrayTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.makePairArray
    #[.u64 1, .u64 2, .u64 3, .u64 4]

theorem abi_make_pair_array_trace_returns_struct_array :
    resultValueMatches abiMakePairArrayTrace
      (some (.array [
        .struct "Pair" [("left", .u64 1), ("right", .u64 2)],
        .struct "Pair" [("left", .u64 3), ("right", .u64 4)]
      ])) = true := by
  native_decide

def abiMakeMatrixTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.makeMatrix
    #[.u64 5, .u64 6, .u64 7, .u64 8]

theorem abi_make_matrix_trace_returns_nested_array :
    resultValueMatches abiMakeMatrixTrace
      (some (.array [.array [.u64 5, .u64 6], .array [.u64 7, .u64 8]])) = true := by
  native_decide

def abiSumSmallTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.sumSmall
    #[.array [.u32 9, .u32 10]]

theorem abi_sum_small_trace_returns_nineteen :
    resultValueMatches abiSumSmallTrace (some (.u32 19)) = true := by
  native_decide

def abiSumSmallMatrixTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.sumSmallMatrix
    #[.array [.array [.u32 1, .u32 2], .array [.u32 3, .u32 4]]]

theorem abi_sum_small_matrix_trace_returns_ten :
    resultValueMatches abiSumSmallMatrixTrace (some (.u32 10)) = true := by
  native_decide

def abiAndFlagsTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.andFlags
    #[.struct "Flags" [("enabled", .bool true), ("archived", .bool false)]]

theorem abi_and_flags_trace_returns_false :
    resultValueMatches abiAndFlagsTrace (some (.bool false)) = true := by
  native_decide

def abiEchoHashPairTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.echoHashPair
    #[.struct "HashPair" [
      ("left", .hash 1 2 3 4),
      ("right", .hash 5 6 7 8)
    ]]

theorem abi_echo_hash_pair_trace_returns_right_hash :
    resultValueMatches abiEchoHashPairTrace (some (.hash 5 6 7 8)) = true := by
  native_decide

def abiMakeHashArrayTrace : Except String (State × Option Value) :=
  runEntrypointWithArgs State.empty ProofForge.IR.Examples.EvmAbiAggregateProbe.makeHashArray
    #[.hash 1 2 3 4, .hash 5 6 7 8]

theorem abi_make_hash_array_trace_returns_hash_array :
    resultValueMatches abiMakeHashArrayTrace
      (some (.array [.hash 1 2 3 4, .hash 5 6 7 8])) = true := by
  native_decide

end ProofForge.IR.Semantics

import ProofForge.IR.Core.Id
import ProofForge.IR.Core.Type
import ProofForge.IR.Core.Storage
import ProofForge.IR.Core.Syntax
import ProofForge.IR.Core.Error
import ProofForge.IR.Canonical
import Std

namespace ProofForge.IR.Core.Semantics

open ProofForge.IR.Core
open ProofForge.IR.Canonical

/- Runtime values for the Core reference interpreter. `memRef` is a runtime-only
reference to a memory allocation and never appears in a validated Core literal. -/

inductive CoreValue
  | unit
  | bool (b : Bool)
  | u8 (n : UInt8)
  | u32 (n : UInt32)
  | u64 (n : UInt64)
  | u128 (n : UInt128)
  | address (s : String)
  | bytes (b : ByteArray)
  | string (s : String)
  | hash (s : String)
  | memRef (id : Nat)
  deriving BEq, Repr, Inhabited

/- The Core type of a runtime value. `memRef` is reported as `u64` because it is
only produced by memory allocation and never flows into validated storage. -/

def typeOfValue : CoreValue → CoreType
  | .unit => .unit
  | .bool _ => .bool
  | .u8 _ => .u8
  | .u32 _ => .u32
  | .u64 _ => .u64
  | .u128 _ => .u128
  | .address _ => .address
  | .bytes _ => .bytes
  | .string _ => .string
  | .hash _ => .hash
  | .memRef _ => .u64

/- Default value derived from a Core type. No target allocation value or
hard-coded `.u64 0` default is used for missing state. Aggregate defaults are
runtime placeholders that never leak into observable storage results. -/

def typeDefault : CoreType → CoreValue
  | .unit => .unit
  | .bool => .bool false
  | .u8 => .u8 0
  | .u32 => .u32 0
  | .u64 => .u64 0
  | .u128 => .u128 0
  | .address => .address ""
  | .bytes => .bytes ByteArray.empty
  | .string => .string ""
  | .hash => .hash ""
  | .fixedArray _ _ | .array _ | .structType _ => .unit

/- Errors produced by the reference interpreter. Each tag is distinct so that
divide-by-zero, assertion failure, revert, and unknown host operations cannot
be confused. -/

inductive RuntimeError
  | outOfFuel
  | divisionByZero
  | arithmeticOverflow
  | assertionFailure (error : CoreErrorRef)
  | explicitRevert (error : CoreErrorRef)
  | unknownHostOp (id : HostOpId)
  | invalidStorageShape
  | arrayOutOfBounds
  | typeMismatch
  | missingFunction
  | argMismatch
  | invalidCast
  deriving BEq, Repr

/- Logical storage cells mirror the validated `StateShape`. Map entries are
represented as a total lookup function so that separation lemmas are purely
functional; arrays use Lean `Array`. -/

inductive StorageCell
  | scalar (value : CoreValue)
  | map (keyType : CoreType) (valueType : CoreType) (entries : CoreValue → Option CoreValue)
  | fixedArray (element : CoreType) (entries : Array CoreValue)
  | dynamicArray (element : CoreType) (entries : Array CoreValue)
  | record (fields : FieldId → Option CoreValue)

/- Create a default cell for a declared state shape. Missing state is derived
from the shape, never from a hard-coded scalar zero. -/

def stateShapeDefault : StateShape → StorageCell
  | .scalar ty => .scalar (typeDefault ty)
  | .map keyTy valTy _ => .map keyTy valTy (fun _ => none)
  | .fixedArray elem len => .fixedArray elem (Array.mk (List.replicate len (typeDefault elem)))
  | .dynamicArray elem => .dynamicArray elem #[]
  | .record _ => .record (fun _ => none)

/- The logical state contains persistent storage cells and ephemeral memory
allocations. Target allocation (EVM slots, account offsets, storage prefixes) is
absent. -/

structure LogicalState where
  storage : Std.HashMap StateId StorageCell
  memory : Array (CoreType × Array CoreValue) := #[]
  nextMemId : Nat := 0

instance : Repr LogicalState where
  reprPrec _ _ := "LogicalState"

instance : Inhabited LogicalState where
  default := { storage := {}, memory := #[], nextMemId := 0 }

abbrev Env := Std.HashMap ValueId CoreValue

/- Observable trace records events and host calls in execution order. Errors are
kept separate in `RuntimeError` so that a failed trace cannot be mistaken for a
successful one. -/

structure ObservableTrace where
  events : Array (EventId × Array CoreValue) := #[]
  hostCalls : Array (HostOpId × Array CoreValue) := #[]
  deriving Repr, BEq, Inhabited

structure ExecutionResult where
  returnValue : CoreValue
  finalState : LogicalState
  trace : ObservableTrace
  deriving Repr, Inhabited

/- The running machine state: value environment, current function/block, logical
state, and observable trace. -/

structure Machine where
  env : Env
  currentFunction : Function
  currentBlock : BlockId
  state : LogicalState
  trace : ObservableTrace

/- Host semantics is the extension hook for target-specific operations. A host
handler that does not recognise an operation must return `unknownHostOp`; the
interpreter never supplies a default value. -/

structure HostSemantics where
  handle : HostOpCall → Array CoreValue → LogicalState → Except RuntimeError (CoreValue × LogicalState)

/- Convert a literal to its runtime value. -/

def literalValue (lit : CoreLiteral) : CoreValue :=
  match lit with
  | .unitLit => .unit
  | .boolLit b => .bool b
  | .u8Lit n => .u8 n
  | .u32Lit n => .u32 n
  | .u64Lit n => .u64 n
  | .u128Lit n => .u128 n
  | .addressLit s => .address s
  | .bytesLit b => .bytes b
  | .stringLit s => .string s
  | .hashLit s => .hash s

/- Look up a value reference in the current environment. -/

def evalRef (env : Env) (ref : ValueRef) : Except RuntimeError CoreValue :=
  match Std.HashMap.get? env ref.id with
  | some v => .ok v
  | none => .error .invalidStorageShape

/- Convert a runtime scalar to an array index. -/

def asArrayIndex (v : CoreValue) : Except RuntimeError Nat :=
  match v with
  | .u32 n => .ok n.toNat
  | .u64 n => .ok n.toNat
  | _ => .error .typeMismatch

/- Default values for context fields. These are semantic defaults, not storage
defaults. -/

def defaultContextValue (field : ContextField) : CoreValue :=
  match field with
  | .sender | .contractAddress => .address ""
  | .value => .u128 0
  | .blockNumber | .blockTimestamp | .gas => .u64 0

/- Pure unary operations. `neg` uses wrapping semantics because Core only
preserves a mode on binary arithmetic. -/

def evalUnary (op : UnaryOp) (arg : CoreValue) : Except RuntimeError CoreValue :=
  match op, arg with
  | .not, .bool b => .ok (.bool (!b))
  | .neg, .u8 n => .ok (.u8 (-n))
  | .neg, .u32 n => .ok (.u32 (-n))
  | .neg, .u64 n => .ok (.u64 (-n))
  | .neg, .u128 n => .ok (.u128 (-n))
  | _, _ => .error .typeMismatch

/- Binary arithmetic with explicit wrapping or checked mode. -/

def evalArithmetic (op : ArithmeticOp) (mode : OverflowMode) (lhs rhs : CoreValue) : Except RuntimeError CoreValue :=
  match lhs, rhs with
  | .u8 a, .u8 b =>
    let f := fun (x y : UInt8) =>
      match op with
      | .add => x + y
      | .sub => x - y
      | .mul => x * y
      | .div => x / y
      | .mod => x % y
      | .and => x &&& y
      | .or => x ||| y
      | .xor => x ^^^ y
      | .shl => x <<< y
      | .shr => x >>> y
    match op, mode with
    | .add, .checked => if a.toNat + b.toNat ≥ 256 then .error .arithmeticOverflow else .ok (.u8 (a + b))
    | .sub, .checked => if a.toNat < b.toNat then .error .arithmeticOverflow else .ok (.u8 (a - b))
    | .mul, .checked => if a.toNat * b.toNat ≥ 256 then .error .arithmeticOverflow else .ok (.u8 (a * b))
    | .div, _ => if b == 0 then .error .divisionByZero else .ok (.u8 (a / b))
    | .mod, _ => if b == 0 then .error .divisionByZero else .ok (.u8 (a % b))
    | _, .checked => .error .arithmeticOverflow -- shl/shr checked not modelled
    | _, _ => .ok (.u8 (f a b))
  | .u32 a, .u32 b =>
    let f := fun (x y : UInt32) =>
      match op with
      | .add => x + y
      | .sub => x - y
      | .mul => x * y
      | .div => x / y
      | .mod => x % y
      | .and => x &&& y
      | .or => x ||| y
      | .xor => x ^^^ y
      | .shl => x <<< y
      | .shr => x >>> y
    match op, mode with
    | .add, .checked => if a.toNat + b.toNat ≥ 4294967296 then .error .arithmeticOverflow else .ok (.u32 (a + b))
    | .sub, .checked => if a.toNat < b.toNat then .error .arithmeticOverflow else .ok (.u32 (a - b))
    | .mul, .checked => if a.toNat * b.toNat ≥ 4294967296 then .error .arithmeticOverflow else .ok (.u32 (a * b))
    | .div, _ => if b == 0 then .error .divisionByZero else .ok (.u32 (a / b))
    | .mod, _ => if b == 0 then .error .divisionByZero else .ok (.u32 (a % b))
    | _, .checked => .error .arithmeticOverflow
    | _, _ => .ok (.u32 (f a b))
  | .u64 a, .u64 b =>
    let f := fun (x y : UInt64) =>
      match op with
      | .add => x + y
      | .sub => x - y
      | .mul => x * y
      | .div => x / y
      | .mod => x % y
      | .and => x &&& y
      | .or => x ||| y
      | .xor => x ^^^ y
      | .shl => x <<< y
      | .shr => x >>> y
    match op, mode with
    | .add, .checked => if a.toNat + b.toNat ≥ 18446744073709551616 then .error .arithmeticOverflow else .ok (.u64 (a + b))
    | .sub, .checked => if a.toNat < b.toNat then .error .arithmeticOverflow else .ok (.u64 (a - b))
    | .mul, .checked => if a.toNat * b.toNat ≥ 18446744073709551616 then .error .arithmeticOverflow else .ok (.u64 (a * b))
    | .div, _ => if b == 0 then .error .divisionByZero else .ok (.u64 (a / b))
    | .mod, _ => if b == 0 then .error .divisionByZero else .ok (.u64 (a % b))
    | _, .checked => .error .arithmeticOverflow
    | _, _ => .ok (.u64 (f a b))
  | .u128 a, .u128 b =>
    let f := fun (x y : UInt128) =>
      match op with
      | .add => x + y
      | .sub => x - y
      | .mul => x * y
      | .div => x / y
      | .mod => x % y
      | .and => x &&& y
      | .or => x ||| y
      | .xor => x ^^^ y
      | .shl => x <<< y
      | .shr => x >>> y
    match op, mode with
    | .add, .checked => if a.toNat + b.toNat ≥ 340282366920938463463374607431768211456 then .error .arithmeticOverflow else .ok (.u128 (a + b))
    | .sub, .checked => if a.toNat < b.toNat then .error .arithmeticOverflow else .ok (.u128 (a - b))
    | .mul, .checked => if a.toNat * b.toNat ≥ 340282366920938463463374607431768211456 then .error .arithmeticOverflow else .ok (.u128 (a * b))
    | .div, _ => if b == 0 then .error .divisionByZero else .ok (.u128 (a / b))
    | .mod, _ => if b == 0 then .error .divisionByZero else .ok (.u128 (a % b))
    | _, .checked => .error .arithmeticOverflow
    | _, _ => .ok (.u128 (f a b))
  | _, _ => .error .typeMismatch

/- Comparisons over integer and identity-like scalars. -/

def evalCompare (op : CompareOp) (lhs rhs : CoreValue) : Except RuntimeError CoreValue :=
  match lhs, rhs with
  | .bool a, .bool b =>
    let r := match op with | .eq => a == b | .ne => a != b | .lt => a < b | .le => a ≤ b | .gt => a > b | .ge => a ≥ b
    .ok (.bool r)
  | .u8 a, .u8 b =>
    let r := match op with | .eq => a == b | .ne => a != b | .lt => a < b | .le => a ≤ b | .gt => a > b | .ge => a ≥ b
    .ok (.bool r)
  | .u32 a, .u32 b =>
    let r := match op with | .eq => a == b | .ne => a != b | .lt => a < b | .le => a ≤ b | .gt => a > b | .ge => a ≥ b
    .ok (.bool r)
  | .u64 a, .u64 b =>
    let r := match op with | .eq => a == b | .ne => a != b | .lt => a < b | .le => a ≤ b | .gt => a > b | .ge => a ≥ b
    .ok (.bool r)
  | .u128 a, .u128 b =>
    let r := match op with | .eq => a == b | .ne => a != b | .lt => a < b | .le => a ≤ b | .gt => a > b | .ge => a ≥ b
    .ok (.bool r)
  | .address a, .address b =>
    let r := match op with | .eq => a == b | .ne => a != b | _ => false
    .ok (.bool r)
  | .hash a, .hash b =>
    let r := match op with | .eq => a == b | .ne => a != b | _ => false
    .ok (.bool r)
  | .string a, .string b =>
    let r := match op with | .eq => a == b | .ne => a != b | _ => false
    .ok (.bool r)
  | .bytes a, .bytes b =>
    let r := match op with | .eq => a == b | .ne => a != b | _ => false
    .ok (.bool r)
  | _, _ => .error .typeMismatch

/- Narrowing casts are checked; widening casts and same-width casts copy the
value. -/

def evalCast (to : CoreType) (arg : CoreValue) : Except RuntimeError CoreValue :=
  match to, arg with
  | .u8, .u8 n => .ok (.u8 n)
  | .u8, .u32 n => if n.toNat ≤ 255 then .ok (.u8 (UInt8.ofNat n.toNat)) else .error .invalidCast
  | .u8, .u64 n => if n.toNat ≤ 255 then .ok (.u8 (UInt8.ofNat n.toNat)) else .error .invalidCast
  | .u8, .u128 n => if n.toNat ≤ 255 then .ok (.u8 (UInt8.ofNat n.toNat)) else .error .invalidCast
  | .u32, .u8 n => .ok (.u32 (UInt32.ofNat n.toNat))
  | .u32, .u32 n => .ok (.u32 n)
  | .u32, .u64 n => if n.toNat ≤ 4294967295 then .ok (.u32 (UInt32.ofNat n.toNat)) else .error .invalidCast
  | .u32, .u128 n => if n.toNat ≤ 4294967295 then .ok (.u32 (UInt32.ofNat n.toNat)) else .error .invalidCast
  | .u64, .u8 n => .ok (.u64 (UInt64.ofNat n.toNat))
  | .u64, .u32 n => .ok (.u64 (UInt64.ofNat n.toNat))
  | .u64, .u64 n => .ok (.u64 n)
  | .u64, .u128 n => if n.toNat ≤ 18446744073709551615 then .ok (.u64 (UInt64.ofNat n.toNat)) else .error .invalidCast
  | .u128, .u8 n => .ok (.u128 (BitVec.ofNat 128 n.toNat))
  | .u128, .u32 n => .ok (.u128 (BitVec.ofNat 128 n.toNat))
  | .u128, .u64 n => .ok (.u128 (BitVec.ofNat 128 n.toNat))
  | .u128, .u128 n => .ok (.u128 n)
  | .bool, .bool b => .ok (.bool b)
  | .unit, .unit => .ok .unit
  | .address, .address s => .ok (.address s)
  | .bytes, .bytes b => .ok (.bytes b)
  | .string, .string s => .ok (.string s)
  | .hash, .hash s => .ok (.hash s)
  | _, _ => .error .typeMismatch

/- Hash is modelled as an opaque hash tag; the value is not interpreted. -/

def evalHash (_arg : CoreValue) : CoreValue :=
  .hash ""

def evalPureOp (env : Env) (op : PureOp) : Except RuntimeError CoreValue := do
  match op with
  | .literal lit => .ok (literalValue lit)
  | .unary op arg => evalUnary op (← evalRef env arg)
  | .arithmetic op mode lhs rhs => evalArithmetic op mode (← evalRef env lhs) (← evalRef env rhs)
  | .compare op lhs rhs => evalCompare op (← evalRef env lhs) (← evalRef env rhs)
  | .cast to arg => evalCast to (← evalRef env arg)
  | .hash arg => .ok (evalHash (← evalRef env arg))

/- Storage cell accessors used by path read/write. -/

def StorageCell.readScalar : StorageCell → Except RuntimeError CoreValue
  | .scalar v => .ok v
  | _ => .error .invalidStorageShape

def StorageCell.readMap (key : CoreValue) (valueType : CoreType) : StorageCell → Except RuntimeError CoreValue
  | .map _ _ entries => .ok (entries key |>.getD (typeDefault valueType))
  | _ => .error .invalidStorageShape

def StorageCell.readArray (index : Nat) : StorageCell → Except RuntimeError CoreValue
  | .fixedArray _ entries | .dynamicArray _ entries =>
    if h : index < Array.size entries then .ok entries[index] else .error .arrayOutOfBounds
  | _ => .error .invalidStorageShape

def StorageCell.readRecord (field : FieldId) : StorageCell → Except RuntimeError CoreValue
  | .record fields =>
    match fields field with
    | some v => .ok v
    | none => .error .invalidStorageShape
  | _ => .error .invalidStorageShape

def StorageCell.writeScalar (value : CoreValue) : StorageCell → Except RuntimeError StorageCell
  | .scalar _ => .ok (.scalar value)
  | _ => .error .invalidStorageShape

def StorageCell.writeMap (key : CoreValue) (value : CoreValue) : StorageCell → Except RuntimeError StorageCell
  | .map kt vt entries => .ok (.map kt vt (fun k => if k == key then some value else entries k))
  | _ => .error .invalidStorageShape

def StorageCell.writeArray (index : Nat) (value : CoreValue) : StorageCell → Except RuntimeError StorageCell
  | .fixedArray elem entries | .dynamicArray elem entries =>
    if h : index < Array.size entries then .ok (.fixedArray elem (Array.set entries index value h)) else .error .arrayOutOfBounds
  | _ => .error .invalidStorageShape

def StorageCell.writeRecord (field : FieldId) (value : CoreValue) : StorageCell → Except RuntimeError StorageCell
  | .record fields => .ok (.record (fun k => if k == field then some value else fields k))
  | _ => .error .invalidStorageShape

/- Locate a storage cell, materialising a default from the declared shape if the
state has not been accessed before. -/

def getStateCell (module : Module) (state : LogicalState) (root : StateId) : Except RuntimeError StorageCell :=
  match Std.HashMap.get? state.storage root with
  | some cell => .ok cell
  | none =>
    match module.state.find? (fun s => s.id == root) with
    | some decl => .ok (stateShapeDefault decl.shape)
    | none => .error .invalidStorageShape

/- Read a logical storage path. Missing map keys return the declared value type
default; out-of-bounds array access is an error. -/

def readPath (module : Module) (env : Env) (state : LogicalState) (path : StorageRef) : Except RuntimeError CoreValue := do
  let cell ← getStateCell module state path.root
  match path.path.toList with
  | [] => cell.readScalar
  | [.mapKey key] =>
    let k ← evalRef env key
    cell.readMap k path.resultType
  | [.index idx] =>
    let i ← asArrayIndex (← evalRef env idx)
    cell.readArray i
  | [.field f] => cell.readRecord f
  | _ => .error .invalidStorageShape

/- Write a logical storage path, materialising a default cell first if needed. -/

def writePath (module : Module) (env : Env) (state : LogicalState) (path : StorageRef) (value : CoreValue) : Except RuntimeError LogicalState := do
  let cell ← getStateCell module state path.root
  let newCell ← match path.path.toList with
    | [] => cell.writeScalar value
    | [.mapKey key] =>
      let k ← evalRef env key
      cell.writeMap k value
    | [.index idx] =>
      let i ← asArrayIndex (← evalRef env idx)
      cell.writeArray i value
    | [.field f] => cell.writeRecord f value
    | _ => .error .invalidStorageShape
  .ok { state with storage := state.storage.insert path.root newCell }

/- Membership test for maps and arrays. -/

def containsPath (module : Module) (env : Env) (state : LogicalState) (path : StorageRef) : Except RuntimeError CoreValue := do
  let cell ← getStateCell module state path.root
  match path.path.toList with
  | [] => .ok (.bool true)
  | [.mapKey key] =>
    let k ← evalRef env key
    match cell with
    | .map _ _ entries => .ok (.bool (entries k).isSome)
    | _ => .error .invalidStorageShape
  | [.index idx] =>
    let i ← asArrayIndex (← evalRef env idx)
    match cell with
    | .fixedArray _ entries | .dynamicArray _ entries => .ok (.bool (i < Array.size entries))
    | _ => .error .invalidStorageShape
  | [.field f] =>
    match cell with
    | .record fields => .ok (.bool (fields f).isSome)
    | _ => .error .invalidStorageShape
  | _ => .error .invalidStorageShape

/- Length of an array-shaped state. -/

def storageLength (module : Module) (state : LogicalState) (root : StateId) : Except RuntimeError CoreValue := do
  let cell ← getStateCell module state root
  match cell with
  | .fixedArray _ entries | .dynamicArray _ entries => .ok (.u64 (UInt64.ofNat (Array.size entries)))
  | _ => .error .invalidStorageShape

/- Resize a dynamic array, filling new slots with the element type default. -/

def storageResize (module : Module) (state : LogicalState) (root : StateId) (length : CoreValue) : Except RuntimeError LogicalState := do
  let len ← asArrayIndex length
  let cell ← getStateCell module state root
  match cell with
  | .dynamicArray elem entries =>
    let newEntries :=
      if len ≤ Array.size entries then
        Array.shrink entries len
      else
        entries ++ Array.mk (List.replicate (len - Array.size entries) (typeDefault elem))
    .ok { state with storage := state.storage.insert root (.dynamicArray elem newEntries) }
  | _ => .error .invalidStorageShape

/- Memory allocation returns a `memRef` handle; loads and stores use that handle. -/

def allocMemory (state : LogicalState) (ty : CoreType) (length : CoreValue) : Except RuntimeError (LogicalState × CoreValue) := do
  let len ← asArrayIndex length
  let id := state.nextMemId
  let entries := Array.mk (List.replicate len (typeDefault ty))
  let state' := { state with memory := Array.push state.memory (ty, entries), nextMemId := id + 1 }
  .ok (state', .memRef id)

def loadMemory (state : LogicalState) (base index : CoreValue) : Except RuntimeError CoreValue := do
  let id ← match base with | .memRef id => .ok id | _ => .error .typeMismatch
  let i ← asArrayIndex index
  match state.memory[id]? with
  | none => .error .invalidStorageShape
  | some (ty, entries) =>
    if h : i < Array.size entries then .ok entries[i] else .error .arrayOutOfBounds

def storeMemory (state : LogicalState) (base index value : CoreValue) : Except RuntimeError LogicalState := do
  let id ← match base with | .memRef id => .ok id | _ => .error .typeMismatch
  let i ← asArrayIndex index
  match state.memory[id]? with
  | none => .error .invalidStorageShape
  | some (ty, entries) =>
    if h : i < Array.size entries then
      .ok { state with memory := Array.set! state.memory id (ty, Array.set entries i value h) }
    else
      .error .arrayOutOfBounds

def releaseMemory (state : LogicalState) (base : CoreValue) : Except RuntimeError LogicalState := do
  let id ← match base with | .memRef id => .ok id | _ => .error .typeMismatch
  .ok { state with memory := Array.set! state.memory id (default, #[]) }

/- Bind a list of parameter definitions to argument values. -/

def bindParams (params : Array ValueDef) (args : Array CoreValue) : Env :=
  let pairs := Array.zip params args
  Array.foldl (fun env (p, a) => env.insert p.id a) {} pairs

/- Bind instruction results to produced values. -/

def bindResults (results : Array ValueDef) (values : Array CoreValue) (env : Env) : Except RuntimeError Env :=
  if results.size == values.size then
    .ok (Array.foldl (fun env (r, v) => env.insert r.id v) env (Array.zip results values))
  else
    .error .typeMismatch

/- Execute a single instruction. -/

def execInstruction (host : HostSemantics) (module : Module) (env : Env) (state : LogicalState) (trace : ObservableTrace) (instr : Instruction) : Except RuntimeError (Env × LogicalState × ObservableTrace) := do
  match instr.op with
  | .pure op =>
    let v ← evalPureOp env op
    let env' ← bindResults instr.results #[v] env
    .ok (env', state, trace)
  | .storageLoad path =>
    let v ← readPath module env state path
    let env' ← bindResults instr.results #[v] env
    .ok (env', state, trace)
  | .storageContains path =>
    let v ← containsPath module env state path
    let env' ← bindResults instr.results #[v] env
    .ok (env', state, trace)
  | .storageStore path value =>
    let v ← evalRef env value
    let state' ← writePath module env state path v
    .ok (env, state', trace)
  | .storageLength root =>
    let v ← storageLength module state root
    let env' ← bindResults instr.results #[v] env
    .ok (env', state, trace)
  | .storageResize root length =>
    let len ← evalRef env length
    let state' ← storageResize module state root len
    .ok (env, state', trace)
  | .memoryAlloc ty length =>
    let len ← evalRef env length
    let (state', ref) ← allocMemory state ty len
    let env' ← bindResults instr.results #[ref] env
    .ok (env', state', trace)
  | .memoryLoad base index =>
    let b ← evalRef env base
    let i ← evalRef env index
    let v ← loadMemory state b i
    let env' ← bindResults instr.results #[v] env
    .ok (env', state, trace)
  | .memoryStore base index value =>
    let b ← evalRef env base
    let i ← evalRef env index
    let v ← evalRef env value
    let state' ← storeMemory state b i v
    .ok (env, state', trace)
  | .memoryRelease base =>
    let b ← evalRef env base
    let state' ← releaseMemory state b
    .ok (env, state', trace)
  | .contextRead field =>
    let v := defaultContextValue field
    let env' ← bindResults instr.results #[v] env
    .ok (env', state, trace)
  | .emit eventId args =>
    let argVals ← args.mapM (evalRef env)
    let trace' := { trace with events := trace.events.push (eventId, argVals) }
    .ok (env, state, trace')
  | .assert condition error =>
    let cond ← evalRef env condition
    match cond with
    | .bool true => .ok (env, state, trace)
    | .bool false => .error (.assertionFailure error)
    | _ => .error .typeMismatch
  | .crosscall _ _ =>
    let env' ← bindResults instr.results #[.u64 0] env
    .ok (env', state, trace)
  | .hostCall call =>
    let argVals ← call.args.mapM (evalRef env)
    let (v, state') ← host.handle call argVals state
    let trace' := { trace with hostCalls := trace.hostCalls.push (call.id, argVals) }
    let env' ← bindResults instr.results #[v] env
    .ok (env', state', trace')

/- Execute all instructions of a block in order. -/

def execInstructions (host : HostSemantics) (module : Module) (env : Env) (state : LogicalState) (trace : ObservableTrace) (instrs : Array Instruction) : Except RuntimeError (Env × LogicalState × ObservableTrace) :=
  instrs.foldlM (fun (env, state, trace) instr =>
    execInstruction host module env state trace instr) (env, state, trace)

/- Execute a block. Fuel decreases on every block transition so execution is
total and bounded. The terminator is handled inline to avoid mutual recursion. -/

def execBlock (host : HostSemantics) (fuel : Nat) (module : Module) (func : Function) (env : Env) (state : LogicalState) (trace : ObservableTrace) (blockId : BlockId) : Except RuntimeError ExecutionResult :=
  match fuel with
  | 0 => .error .outOfFuel
  | fuel + 1 => do
    let block ← match func.blocks.find? (fun b => b.id == blockId) with
      | some b => .ok b
      | none => .error .missingFunction
    let (env', state', trace') ← execInstructions host module env state trace block.instructions
    match block.terminator with
    | .jump target args _ => do
      let targetBlock ← match func.blocks.find? (fun b => b.id == target) with
        | some b => .ok b
        | none => .error .missingFunction
      let argVals ← args.mapM (evalRef env')
      let env'' := bindParams targetBlock.params argVals
      execBlock host fuel module func env'' state' trace' target
    | .branch condition onTrue onFalse => do
      let cond ← evalRef env' condition
      match cond with
      | .bool true => execBlock host fuel module func env' state' trace' onTrue
      | .bool false => execBlock host fuel module func env' state' trace' onFalse
      | _ => .error .typeMismatch
    | .return values => do
      let vals ← values.mapM (evalRef env')
      match vals with
      | #[] => .ok { returnValue := .unit, finalState := state', trace := trace' }
      | #[v] => .ok { returnValue := v, finalState := state', trace := trace' }
      | _ => .error .invalidStorageShape
    | .revert error => .error (.explicitRevert error)

/- Entry point: validate the entry function, bind arguments, and start execution
with the provided fuel. This function is total: every path returns a result or a
`RuntimeError`. -/

def execute (host : HostSemantics) (fuel : Nat) (checked : CheckedCanonicalContract) (entrypoint : FunctionId) (args : Array CoreValue) (state : LogicalState) : Except RuntimeError ExecutionResult := do
  let module := match checked with | { contract := c } => c.module
  let func ← match module.functions.find? (fun f => f.id == entrypoint) with
    | some f => .ok f
    | none => .error .missingFunction
  unless func.params.size == args.size do
    .error .argMismatch
  for i in [:func.params.size] do
    unless typeOfValue args[i]! == func.params[i]!.type do
      .error .argMismatch
  let env := bindParams func.params args
  execBlock host fuel module func env state {} func.entry

end ProofForge.IR.Core.Semantics

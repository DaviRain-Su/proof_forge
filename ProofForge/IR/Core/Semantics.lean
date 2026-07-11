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
  | memRef (element : CoreType) (id : Nat)
  | fixedArray (element : CoreType) (entries : Array CoreValue)
  | array (element : CoreType) (entries : Array CoreValue)
  | structValue (typeId : TypeId) (fields : Array (FieldId × CoreValue))
  deriving BEq, Repr, Hashable

instance : Inhabited CoreValue := ⟨.unit⟩

/- The Core type of a runtime value. Memory references have an ephemeral type
that cannot be confused with ordinary arrays. -/

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
  | .memRef element _ => .memoryRef element
  | .fixedArray element entries => .fixedArray element entries.size
  | .array element _ => .array element
  | .structValue typeId _ => .structType typeId

/- Default value derived from a Core type. No target allocation value or
hard-coded `.u64 0` default is used for missing state. Aggregate defaults retain
their declared runtime shape. -/

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
  | .fixedArray element length =>
    if length ≤ maxLogicalCollectionLength then
      .fixedArray element (Array.mk (List.replicate length (typeDefault element)))
    else
      .fixedArray element #[]
  | .array element => .array element #[]
  | .memoryRef _ => .unit
  | .structType typeId => .structValue typeId #[]

private def coreTypeDepth : CoreType → Nat
  | .fixedArray element _ | .array element | .memoryRef element => coreTypeDepth element + 1
  | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address | .bytes |
      .string | .hash | .structType _ => 1

private def moduleTypeFuel (module : Module) (root : CoreType) : Nat :=
  module.structs.foldl (fun total declaration =>
    declaration.fields.foldl (fun fieldTotal field => fieldTotal + coreTypeDepth field.type) total)
    (coreTypeDepth root + module.structs.size + 1)

private def saturatingAdd (lhs rhs : Nat) : Nat :=
  if lhs > maxLogicalCollectionLength || rhs > maxLogicalCollectionLength - lhs then
    maxLogicalCollectionLength + 1
  else lhs + rhs

private def saturatingMul (lhs rhs : Nat) : Nat :=
  if lhs == 0 || rhs == 0 then 0
  else if lhs > maxLogicalCollectionLength / rhs then maxLogicalCollectionLength + 1
  else lhs * rhs

private def typeFootprintFuel (module : Module) : Nat → CoreType → Nat
  | 0, _ => maxLogicalCollectionLength + 1
  | fuel + 1, type => match type with
    | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address | .bytes |
        .string | .hash | .memoryRef _ => 1
    | .fixedArray element length =>
        max 1 (saturatingMul length (typeFootprintFuel module fuel element))
    | .array _ => 1
    | .structType typeId =>
        match module.structs.find? (·.id == typeId) with
        | none => maxLogicalCollectionLength + 1
        | some declaration =>
            let rec sumFields : List FieldDecl → Nat → Nat
              | [], total => max 1 total
              | field :: rest, total =>
                  if total > maxLogicalCollectionLength then total
                  else sumFields rest (saturatingAdd total
                    (typeFootprintFuel module fuel field.type))
            sumFields declaration.fields.toList 0

def typeFootprintForModule (module : Module) (type : CoreType) : Nat :=
  typeFootprintFuel module (moduleTypeFuel module type) type

private def valueFootprintFuel : Nat → CoreValue → Nat
  | 0, _ => maxLogicalCollectionLength + 1
  | fuel + 1, value =>
    let rec sumValues : List CoreValue → Nat → Nat
      | [], total => max 1 total
      | entry :: rest, total =>
          if total > maxLogicalCollectionLength then total
          else sumValues rest (saturatingAdd total (valueFootprintFuel fuel entry))
    match value with
    | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .memRef _ _ => 1
    | .address address | .hash address => max 1 address.toUTF8.size
    | .bytes bytes => max 1 bytes.size
    | .string string => max 1 string.toUTF8.size
    | .fixedArray _ entries | .array _ entries => sumValues entries.toList 0
    | .structValue _ fields => sumValues (fields.toList.map (·.2)) 0

def valueFootprint (value : CoreValue) : Nat :=
  valueFootprintFuel (maxLogicalCollectionLength + 1) value

private def typeDefaultForModuleFuel (module : Module) : Nat → CoreType → CoreValue
  | 0, type => typeDefault type
  | fuel + 1, type =>
    match type with
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
    | .fixedArray element length =>
      if length ≤ maxLogicalCollectionLength then .fixedArray element
          (Array.mk (List.replicate length (typeDefaultForModuleFuel module fuel element)))
      else .fixedArray element #[]
    | .array element => .array element #[]
    | .memoryRef _ => .unit
    | .structType typeId =>
      match module.structs.find? (·.id == typeId) with
      | none => .structValue typeId #[]
      | some declaration => .structValue typeId
          (declaration.fields.map (fun field =>
            (field.id, typeDefaultForModuleFuel module fuel field.type)))

def typeDefaultForModule (module : Module) (type : CoreType) : CoreValue :=
  if typeFootprintForModule module type > maxLogicalCollectionLength then
    match type with
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
    | .fixedArray element _ => .fixedArray element #[]
    | .array element => .array element #[]
    | .memoryRef _ => .unit
    | .structType typeId => .structValue typeId #[]
  else
    typeDefaultForModuleFuel module (moduleTypeFuel module type) type

private def valueHasTypeFuel (module : Module) : Nat → CoreValue → CoreType → Bool
  | 0, value, expected => typeOfValue value == expected
  | fuel + 1, value, expected => match value, expected with
  | .unit, .unit => true
  | .bool _, .bool => true
  | .u8 _, .u8 => true
  | .u32 _, .u32 => true
  | .u64 _, .u64 => true
  | .u128 _, .u128 => true
  | .address _, .address => true
  | .bytes _, .bytes => true
  | .string _, .string => true
  | .hash _, .hash => true
  | .memRef element _, .memoryRef expectedElement => element == expectedElement
  | .fixedArray element entries, .fixedArray expectedElement expectedLength =>
      element == expectedElement && entries.size == expectedLength &&
        entries.all (fun entry => valueHasTypeFuel module fuel entry expectedElement)
  | .array element entries, .array expectedElement =>
      element == expectedElement && entries.size ≤ maxLogicalCollectionLength &&
        entries.all (fun entry => valueHasTypeFuel module fuel entry expectedElement)
  | .structValue typeId fields, .structType expectedTypeId =>
      typeId == expectedTypeId &&
        match module.structs.find? (·.id == typeId) with
        | none => false
        | some declaration =>
            let rec fieldsMatch : List FieldDecl → List (FieldId × CoreValue) → Bool
              | [], [] => true
              | declared :: declaredRest, field :: fieldRest =>
                  field.1 == declared.id &&
                    valueHasTypeFuel module fuel field.2 declared.type &&
                    fieldsMatch declaredRest fieldRest
              | _, _ => false
            fieldsMatch declaration.fields.toList fields.toList
  | .unit, _ | .bool _, _ | .u8 _, _ | .u32 _, _ | .u64 _, _ | .u128 _, _ |
      .address _, _ | .bytes _, _ | .string _, _ | .hash _, _ | .memRef _ _, _ |
      .fixedArray _ _, _ | .array _ _, _ | .structValue _ _, _ => false

def valueHasType (module : Module) (value : CoreValue) (expected : CoreType) : Bool :=
  valueFootprint value ≤ maxLogicalCollectionLength &&
    valueHasTypeFuel module (moduleTypeFuel module expected) value expected

structure RuntimeErrorValue where
  id : ErrorId
  args : Array CoreValue
  deriving BEq, Repr

/- Errors produced by the reference interpreter. Each tag is distinct so that
divide-by-zero, assertion failure, revert, and unknown host operations cannot
be confused. -/

inductive RuntimeError
  | outOfFuel
  | divisionByZero
  | arithmeticOverflow
  | assertionFailure (error : RuntimeErrorValue)
  | explicitRevert (error : RuntimeErrorValue)
  | unknownHostOp (id : HostOpId)
  | invalidStorageShape
  | arrayOutOfBounds
  | typeMismatch
  | missingFunction
  | argMismatch
  | invalidCast
  | loopBoundExceeded (block : BlockId)
  | unsupportedContext (field : ContextField)
  | unsupportedHash
  | unsupportedCrosscall (mode : CoreCrosscallMode)
  | invalidMemoryRef (id : Nat)
  | memoryAlreadyReleased (id : Nat)
  | mapCapacityExceeded (capacity : Nat)
  | collectionLimitExceeded (requested maximum : Nat)
  deriving BEq, Repr

/- Logical storage cells mirror the validated `StateShape`. Map entries are
represented as a total lookup function so that separation lemmas are purely
functional; arrays use Lean `Array`. -/

inductive StorageCell
  | scalar (value : CoreValue)
  | map (keyType : CoreType) (valueType : CoreType) (capacity : Option Nat)
      (entries : Array (CoreValue × CoreValue))
  | fixedArray (element : CoreType) (entries : Array CoreValue)
  | dynamicArray (element : CoreType) (entries : Array CoreValue)
  | record (typeId : TypeId) (fields : FieldId → Option CoreValue)

private def mapEntriesFootprint : List (CoreValue × CoreValue) → Nat → Nat
  | [], total => max 1 total
  | entry :: rest, total =>
      if total > maxLogicalCollectionLength then total
      else mapEntriesFootprint rest <| saturatingAdd total <|
        saturatingAdd (valueFootprint entry.1) (valueFootprint entry.2)

def validateStorageCell (module : Module) (shape : StateShape)
    (cell : StorageCell) : Except RuntimeError Unit := do
  let footprint ← match shape, cell with
    | .scalar type, .scalar value => do
        unless valueHasType module value type do
          .error .typeMismatch
        pure (valueFootprint value)
    | .map keyType valueType capacity, .map cellKeyType cellValueType cellCapacity entries => do
        unless cellKeyType == keyType && cellValueType == valueType &&
            cellCapacity == capacity do
          .error .invalidStorageShape
        match capacity with
        | some maximum =>
            if entries.size > maximum then
              .error (.mapCapacityExceeded maximum)
        | none => pure ()
        if entries.size > maxLogicalCollectionLength then
          .error (.collectionLimitExceeded entries.size maxLogicalCollectionLength)
        let mut keys : Std.HashSet CoreValue := {}
        for entry in entries do
          if keys.contains entry.1 then
            .error .invalidStorageShape
          unless valueHasType module entry.1 keyType &&
              valueHasType module entry.2 valueType do
            .error .typeMismatch
          keys := keys.insert entry.1
        pure (mapEntriesFootprint entries.toList 0)
    | .fixedArray element length, .fixedArray cellElement entries => do
        unless cellElement == element && entries.size == length do
          .error .invalidStorageShape
        for entry in entries do
          unless valueHasType module entry element do
            .error .typeMismatch
        pure (valueFootprint (.fixedArray element entries))
    | .dynamicArray element, .dynamicArray cellElement entries => do
        unless cellElement == element do
          .error .invalidStorageShape
        if entries.size > maxLogicalCollectionLength then
          .error (.collectionLimitExceeded entries.size maxLogicalCollectionLength)
        for entry in entries do
          unless valueHasType module entry element do
            .error .typeMismatch
        pure (valueFootprint (.array element entries))
    | .record typeId, .record cellTypeId fields => do
        unless cellTypeId == typeId do
          .error .invalidStorageShape
        let declaration ← match module.structs.find? (·.id == typeId) with
          | some declaration => pure declaration
          | none => .error .invalidStorageShape
        let mut values : Array (FieldId × CoreValue) := #[]
        for field in declaration.fields do
          let value ← match fields field.id with
            | some value => pure value
            | none => .error .invalidStorageShape
          unless valueHasType module value field.type do
            .error .typeMismatch
          values := values.push (field.id, value)
        pure (valueFootprint (.structValue typeId values))
    | .scalar _, .map _ _ _ _ | .scalar _, .fixedArray _ _ |
        .scalar _, .dynamicArray _ _ | .scalar _, .record _ _ |
        .map _ _ _, .scalar _ | .map _ _ _, .fixedArray _ _ |
        .map _ _ _, .dynamicArray _ _ | .map _ _ _, .record _ _ |
        .fixedArray _ _, .scalar _ | .fixedArray _ _, .map _ _ _ _ |
        .fixedArray _ _, .dynamicArray _ _ | .fixedArray _ _, .record _ _ |
        .dynamicArray _, .scalar _ | .dynamicArray _, .map _ _ _ _ |
        .dynamicArray _, .fixedArray _ _ | .dynamicArray _, .record _ _ |
        .record _, .scalar _ | .record _, .map _ _ _ _ |
        .record _, .fixedArray _ _ | .record _, .dynamicArray _ _ =>
      .error .invalidStorageShape
  if footprint > maxLogicalCollectionLength then
    .error (.collectionLimitExceeded footprint maxLogicalCollectionLength)

/- Create a default cell for a declared state shape. Missing state is derived
from the shape, never from a hard-coded scalar zero. -/

def stateShapeDefault (module : Module) : StateShape → StorageCell
  | .scalar ty => .scalar (typeDefaultForModule module ty)
  | .map keyTy valTy capacity => .map keyTy valTy capacity #[]
  | .fixedArray elem len =>
      if typeFootprintForModule module (.fixedArray elem len) ≤ maxLogicalCollectionLength then
        .fixedArray elem
        (Array.mk (List.replicate len (typeDefaultForModule module elem)))
      else .fixedArray elem #[]
  | .dynamicArray elem => .dynamicArray elem #[]
  | .record typeId =>
      match typeDefaultForModule module (.structType typeId) with
      | .structValue _ fields => .record typeId
          (fun id => (fields.find? (fun field => field.1 == id)).map (·.2))
      | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
          .bytes _ | .string _ | .hash _ | .memRef _ _ | .fixedArray _ _ | .array _ _ =>
        .record typeId (fun _ => none)

/- The logical state contains persistent storage cells and ephemeral memory
allocations. Target allocation (EVM slots, account offsets, storage prefixes) is
absent. -/

structure LogicalState where
  storage : StateId → Option StorageCell
  memory : Array (Option (CoreType × Array CoreValue)) := #[]

instance : Repr LogicalState where
  reprPrec _ _ := "LogicalState"

instance : Inhabited LogicalState where
  default := { storage := fun _ => none, memory := #[] }

abbrev Env := Std.HashMap ValueId CoreValue

/- Observable trace records events and host calls in execution order. Errors are
kept separate in `RuntimeError` so that a failed trace cannot be mistaken for a
successful one. -/

structure RuntimeCrosscallRequest where
  mode : CoreCrosscallMode
  target : CoreValue
  method : CoreValue
  gas : Option CoreValue
  value : Option CoreValue
  args : Array CoreValue
  returnType : CoreType
  deriving Repr, BEq, Inhabited

inductive ObservableEffect
  | emit (event : EventId) (args : Array CoreValue)
  | hostCall (id : HostOpId) (args : Array CoreValue)
  | crosscall (request : RuntimeCrosscallRequest)
  deriving Repr, BEq, Inhabited

structure ObservableTrace where
  effects : Array ObservableEffect := #[]
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

/- Host semantics is the extension hook for target-specific operations. Every
host-dependent operation has an explicit handler; an implementation that does
not recognise one must return a runtime error rather than a placeholder value. -/

structure HostSemantics where
  handle : HostOpCall → Array CoreValue → LogicalState → Except RuntimeError (CoreValue × LogicalState)
  handleContext : ContextField → Except RuntimeError CoreValue
  handleHash : CoreValue → Except RuntimeError CoreValue
  handleCrosscall : RuntimeCrosscallRequest → LogicalState →
    Except RuntimeError (Option CoreValue × LogicalState)

/-- Trace entry for a `near.promise.create@1.0.0` host call. -/
structure NearPromiseTrace where
  accountId : String
  methodName : String
  args : ByteArray
  deposit : UInt128
  gas : UInt64
  promiseIndex : UInt64
  deriving Repr, BEq

/-- Reference host semantics for `near.promise.create@1.0.0`.
Appends a `NearPromiseTrace` entry and returns the next promise index.
Unknown versions remain errors. -/
def nearPromiseHost (traces : Array NearPromiseTrace) (call : HostOpCall) (args : Array CoreValue) :
    Except RuntimeError (CoreValue × Array NearPromiseTrace) :=
  match call.id.namespace_, call.id.name, call.id.version with
  | "near.promise", "create", { major := 1, minor := 0, patch := 0 } =>
    if args.size != 5 then .error .argMismatch
    else
      match args[0]!, args[1]!, args[2]!, args[3]!, args[4]! with
      | .string accountId, .string methodName, .bytes argBytes, .u128 deposit, .u64 gas =>
        let idx := UInt64.ofNat traces.size
        let trace := { accountId, methodName, args := argBytes, deposit, gas, promiseIndex := idx }
        .ok (.u64 idx, traces.push trace)
      | _, _, _, _, _ => .error .typeMismatch
  | _, _, _ => .error (.unknownHostOp call.id)

/- Convert a literal to its runtime value. -/

def literalValue (expected : CoreType) (lit : CoreLiteral) : Except RuntimeError CoreValue :=
  match lit, expected with
  | .unitLit, .unit => .ok .unit
  | .boolLit b, .bool => .ok (.bool b)
  | .u8Lit n, .u8 => if n < 256 then .ok (.u8 (UInt8.ofNat n)) else .error .typeMismatch
  | .u32Lit n, .u32 => if n < 4294967296 then .ok (.u32 (UInt32.ofNat n)) else .error .typeMismatch
  | .u64Lit n, .u64 => if n < 18446744073709551616 then .ok (.u64 (UInt64.ofNat n)) else .error .typeMismatch
  | .u128Lit n, .u128 => if n < 340282366920938463463374607431768211456 then
      .ok (.u128 (BitVec.ofNat 128 n)) else .error .typeMismatch
  | .addressLit s, .address => .ok (.address s)
  | .bytesLit b, .bytes => .ok (.bytes b)
  | .stringLit s, .string => .ok (.string s)
  | .hashLit s, .hash => .ok (.hash s)
  | .unitLit, _ | .boolLit _, _ | .u8Lit _, _ | .u32Lit _, _ | .u64Lit _, _ |
      .u128Lit _, _ | .addressLit _, _ | .bytesLit _, _ | .stringLit _, _ |
      .hashLit _, _ => .error .typeMismatch

/- Look up a value reference in the current environment. -/

def evalRef (env : Env) (ref : ValueRef) : Except RuntimeError CoreValue :=
  match Std.HashMap.get? env ref.id with
  | some v =>
    if typeOfValue v == ref.type then .ok v else .error .typeMismatch
  | none => .error .invalidStorageShape

def evalErrorRef (env : Env) (error : CoreErrorRef) : Except RuntimeError RuntimeErrorValue := do
  let args ← error.args.mapM (evalRef env)
  .ok { id := error.id, args := args }

/- Convert a runtime scalar to an array index. -/

def asArrayIndex (v : CoreValue) : Except RuntimeError Nat :=
  match v with
  | .u32 n => .ok n.toNat
  | .u64 n => .ok n.toNat
  | _ => .error .typeMismatch

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
    | .and, .checked | .or, .checked | .xor, .checked | .shr, .checked => .ok (.u8 (f a b))
    | .shl, .checked =>
      if b.toNat ≥ 8 then
        if a == 0 then .ok (.u8 0) else .error .arithmeticOverflow
      else if a.toNat * (2 ^ b.toNat) ≥ 256 then .error .arithmeticOverflow
      else .ok (.u8 (a <<< b))
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
    | .and, .checked | .or, .checked | .xor, .checked | .shr, .checked => .ok (.u32 (f a b))
    | .shl, .checked =>
      if b.toNat ≥ 32 then
        if a == 0 then .ok (.u32 0) else .error .arithmeticOverflow
      else if a.toNat * (2 ^ b.toNat) ≥ 4294967296 then .error .arithmeticOverflow
      else .ok (.u32 (a <<< b))
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
    | .and, .checked | .or, .checked | .xor, .checked | .shr, .checked => .ok (.u64 (f a b))
    | .shl, .checked =>
      if b.toNat ≥ 64 then
        if a == 0 then .ok (.u64 0) else .error .arithmeticOverflow
      else if a.toNat * (2 ^ b.toNat) ≥ 18446744073709551616 then .error .arithmeticOverflow
      else .ok (.u64 (a <<< b))
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
    | .and, .checked | .or, .checked | .xor, .checked | .shr, .checked => .ok (.u128 (f a b))
    | .shl, .checked =>
      if b.toNat ≥ 128 then
        if a == 0 then .ok (.u128 0) else .error .arithmeticOverflow
      else if a.toNat * (2 ^ b.toNat) ≥ 340282366920938463463374607431768211456 then
        .error .arithmeticOverflow
      else .ok (.u128 (a <<< b))
    | _, _ => .ok (.u128 (f a b))
  | _, _ => .error .typeMismatch

/- Comparisons over integer and identity-like scalars. -/

def evalCompare (op : CompareOp) (lhs rhs : CoreValue) : Except RuntimeError CoreValue :=
  match lhs, rhs with
  | .bool a, .bool b =>
    match op with
    | .eq => .ok (.bool (a == b))
    | .ne => .ok (.bool (a != b))
    | .lt | .le | .gt | .ge => .error .typeMismatch
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
    match op with
    | .eq => .ok (.bool (a == b))
    | .ne => .ok (.bool (a != b))
    | .lt | .le | .gt | .ge => .error .typeMismatch
  | .hash a, .hash b =>
    match op with
    | .eq => .ok (.bool (a == b))
    | .ne => .ok (.bool (a != b))
    | .lt | .le | .gt | .ge => .error .typeMismatch
  | .string a, .string b =>
    match op with
    | .eq => .ok (.bool (a == b))
    | .ne => .ok (.bool (a != b))
    | .lt | .le | .gt | .ge => .error .typeMismatch
  | .bytes a, .bytes b =>
    match op with
    | .eq => .ok (.bool (a == b))
    | .ne => .ok (.bool (a != b))
    | .lt | .le | .gt | .ge => .error .typeMismatch
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

def evalPureOp (env : Env) (resultType : CoreType) (op : PureOp) : Except RuntimeError CoreValue := do
  match op with
  | .literal lit => literalValue resultType lit
  | .unary op arg => evalUnary op (← evalRef env arg)
  | .arithmetic op mode lhs rhs => evalArithmetic op mode (← evalRef env lhs) (← evalRef env rhs)
  | .compare op lhs rhs => evalCompare op (← evalRef env lhs) (← evalRef env rhs)
  | .cast to arg => evalCast to (← evalRef env arg)
  | .hash _ => .error .unsupportedHash
  | .hashTwoToOne _ _ => .error .unsupportedHash

/- Storage cell accessors used by path read/write. -/

def StorageCell.readScalar : StorageCell → Except RuntimeError CoreValue
  | .scalar v => .ok v
  | _ => .error .invalidStorageShape

def findMapValueList? : List (CoreValue × CoreValue) → CoreValue → Option CoreValue
  | [], _ => none
  | entry :: rest, key =>
      if entry.1 == key then some entry.2 else findMapValueList? rest key

def upsertMapEntryList : List (CoreValue × CoreValue) → CoreValue → CoreValue →
    List (CoreValue × CoreValue)
  | [], key, value => [(key, value)]
  | entry :: rest, key, value =>
      if entry.1 == key then (key, value) :: rest
      else entry :: upsertMapEntryList rest key value

def findMapValue? (entries : Array (CoreValue × CoreValue))
    (key : CoreValue) : Option CoreValue :=
  findMapValueList? entries.toList key

def upsertMapEntry (entries : Array (CoreValue × CoreValue))
    (key value : CoreValue) : Array (CoreValue × CoreValue) :=
  (upsertMapEntryList entries.toList key value).toArray

def StorageCell.readMap (key : CoreValue) (valueType : CoreType) : StorageCell → Except RuntimeError CoreValue
  | .map _ _ _ entries => .ok ((findMapValue? entries key).getD (typeDefault valueType))
  | _ => .error .invalidStorageShape

def StorageCell.readArray (index : Nat) : StorageCell → Except RuntimeError CoreValue
  | .fixedArray _ entries | .dynamicArray _ entries =>
    if h : index < Array.size entries then .ok entries[index] else .error .arrayOutOfBounds
  | _ => .error .invalidStorageShape

def StorageCell.readRecord (field : FieldId) : StorageCell → Except RuntimeError CoreValue
  | .record _ fields =>
    match fields field with
    | some v => .ok v
    | none => .error .invalidStorageShape
  | _ => .error .invalidStorageShape

def StorageCell.writeScalar (value : CoreValue) : StorageCell → Except RuntimeError StorageCell
  | .scalar previous =>
    if typeOfValue value == typeOfValue previous then .ok (.scalar value)
    else .error .typeMismatch
  | _ => .error .invalidStorageShape

def StorageCell.writeMap (key : CoreValue) (value : CoreValue) : StorageCell → Except RuntimeError StorageCell
  | .map kt vt capacity entries =>
    if typeOfValue key == kt && typeOfValue value == vt then
      let isNew := (findMapValue? entries key).isNone
      match capacity with
      | some maximum =>
          if isNew && entries.size ≥ maximum then .error (.mapCapacityExceeded maximum)
          else .ok (.map kt vt capacity (upsertMapEntry entries key value))
      | none => .ok (.map kt vt capacity (upsertMapEntry entries key value))
    else
      .error .typeMismatch
  | _ => .error .invalidStorageShape

def StorageCell.writeArray (index : Nat) (value : CoreValue) : StorageCell → Except RuntimeError StorageCell
  | .fixedArray elem entries =>
    if typeOfValue value != elem then .error .typeMismatch
    else if h : index < Array.size entries then
      .ok (.fixedArray elem (Array.set entries index value h))
    else
      .error .arrayOutOfBounds
  | .dynamicArray elem entries =>
    if typeOfValue value != elem then .error .typeMismatch
    else if h : index < Array.size entries then
      .ok (.dynamicArray elem (Array.set entries index value h))
    else
      .error .arrayOutOfBounds
  | _ => .error .invalidStorageShape

def StorageCell.writeRecord (field : FieldId) (value : CoreValue) : StorageCell → Except RuntimeError StorageCell
  | .record typeId fields =>
      .ok (.record typeId (fun k => if k == field then some value else fields k))
  | _ => .error .invalidStorageShape

/- Locate a storage cell, materialising a default from the declared shape if the
state has not been accessed before. -/

def getStateCell (module : Module) (state : LogicalState) (root : StateId) : Except RuntimeError StorageCell :=
  match module.state.find? (fun declaration => declaration.id == root) with
  | none => .error .invalidStorageShape
  | some declaration => do
      let cell := (state.storage root).getD (stateShapeDefault module declaration.shape)
      validateStorageCell module declaration.shape cell
      .ok cell

def validateLogicalState (module : Module) (state : LogicalState) : Except RuntimeError Unit := do
  for declaration in module.state do
    let _ ← getStateCell module state declaration.id

def setStateCell (state : LogicalState) (root : StateId) (cell : StorageCell) : LogicalState :=
  { state with
    storage := fun key =>
      if key.value = root.value then some cell else state.storage key }

def structFieldType? (module : Module) (typeId : TypeId) (fieldId : FieldId) : Option CoreType :=
  (module.structs.find? (·.id == typeId)).bind fun declaration =>
    (declaration.fields.find? (·.id == fieldId)).map (·.type)

def readNestedValue (module : Module) (env : Env) :
    CoreValue → List StorageSegment → Except RuntimeError CoreValue
  | value, [] => .ok value
  | .structValue typeId fields, .field fieldId :: rest => do
      let fieldType ← match structFieldType? module typeId fieldId with
        | some fieldType => .ok fieldType
        | none => .error .invalidStorageShape
      let fieldValue := (fields.find? (fun field => field.1 == fieldId)).map (·.2)
        |>.getD (typeDefaultForModule module fieldType)
      readNestedValue module env fieldValue rest
  | .fixedArray _ entries, .index indexRef :: rest
  | .array _ entries, .index indexRef :: rest => do
      let index ← asArrayIndex (← evalRef env indexRef)
      if h : index < entries.size then
        readNestedValue module env entries[index] rest
      else
        .error .arrayOutOfBounds
  | .unit, _ :: _ | .bool _, _ :: _ | .u8 _, _ :: _ | .u32 _, _ :: _ |
      .u64 _, _ :: _ | .u128 _, _ :: _ | .address _, _ :: _ |
      .bytes _, _ :: _ | .string _, _ :: _ | .hash _, _ :: _ |
      .memRef _ _, _ :: _ | .fixedArray _ _, .mapKey _ :: _ |
      .fixedArray _ _, .field _ :: _ | .array _ _, .mapKey _ :: _ |
      .array _ _, .field _ :: _ | .structValue _ _, .mapKey _ :: _ |
      .structValue _ _, .index _ :: _ => .error .invalidStorageShape

def writeNestedValue (module : Module) (env : Env) :
    CoreValue → List StorageSegment → CoreValue → Except RuntimeError CoreValue
  | _, [], replacement => .ok replacement
  | .structValue typeId fields, .field fieldId :: rest, replacement => do
      let fieldType ← match structFieldType? module typeId fieldId with
        | some fieldType => .ok fieldType
        | none => .error .invalidStorageShape
      let previous := (fields.find? (fun field => field.1 == fieldId)).map (·.2)
        |>.getD (typeDefaultForModule module fieldType)
      let updated ← writeNestedValue module env previous rest replacement
      unless valueHasType module updated fieldType do
        .error .typeMismatch
      .ok (.structValue typeId (fields.map fun field =>
        if field.1 == fieldId then (fieldId, updated) else field))
  | .fixedArray element entries, .index indexRef :: rest, replacement => do
      let index ← asArrayIndex (← evalRef env indexRef)
      if h : index < entries.size then
        let updated ← writeNestedValue module env entries[index] rest replacement
        unless valueHasType module updated element do
          .error .typeMismatch
        .ok (.fixedArray element (Array.set entries index updated h))
      else
        .error .arrayOutOfBounds
  | .array element entries, .index indexRef :: rest, replacement => do
      let index ← asArrayIndex (← evalRef env indexRef)
      if h : index < entries.size then
        let updated ← writeNestedValue module env entries[index] rest replacement
        unless valueHasType module updated element do
          .error .typeMismatch
        .ok (.array element (Array.set entries index updated h))
      else
        .error .arrayOutOfBounds
  | .unit, _ :: _, _ | .bool _, _ :: _, _ | .u8 _, _ :: _, _ |
      .u32 _, _ :: _, _ | .u64 _, _ :: _, _ | .u128 _, _ :: _, _ |
      .address _, _ :: _, _ | .bytes _, _ :: _, _ | .string _, _ :: _, _ |
      .hash _, _ :: _, _ | .memRef _ _, _ :: _, _ |
      .fixedArray _ _, .mapKey _ :: _, _ | .fixedArray _ _, .field _ :: _, _ |
      .array _ _, .mapKey _ :: _, _ | .array _ _, .field _ :: _, _ |
      .structValue _ _, .mapKey _ :: _, _ |
      .structValue _ _, .index _ :: _, _ => .error .invalidStorageShape

def containsNestedValue (module : Module) (env : Env) :
    CoreValue → List StorageSegment → Except RuntimeError Bool
  | _, [] => .ok true
  | .structValue typeId fields, .field fieldId :: rest => do
      let fieldType ← match structFieldType? module typeId fieldId with
        | some fieldType => .ok fieldType
        | none => .error .invalidStorageShape
      let value := (fields.find? (fun field => field.1 == fieldId)).map (·.2)
        |>.getD (typeDefaultForModule module fieldType)
      if rest.isEmpty then .ok true else containsNestedValue module env value rest
  | .fixedArray _ entries, .index indexRef :: rest
  | .array _ entries, .index indexRef :: rest => do
      let index ← asArrayIndex (← evalRef env indexRef)
      if h : index < entries.size then
        if rest.isEmpty then .ok true else containsNestedValue module env entries[index] rest
      else
        .ok false
  | .unit, _ :: _ | .bool _, _ :: _ | .u8 _, _ :: _ | .u32 _, _ :: _ |
      .u64 _, _ :: _ | .u128 _, _ :: _ | .address _, _ :: _ |
      .bytes _, _ :: _ | .string _, _ :: _ | .hash _, _ :: _ |
      .memRef _ _, _ :: _ | .fixedArray _ _, .mapKey _ :: _ |
      .fixedArray _ _, .field _ :: _ | .array _ _, .mapKey _ :: _ |
      .array _ _, .field _ :: _ | .structValue _ _, .mapKey _ :: _ |
      .structValue _ _, .index _ :: _ => .error .invalidStorageShape

/- Read a logical storage path recursively through aggregate values. -/

def readPath (module : Module) (env : Env) (state : LogicalState) (path : StorageRef) : Except RuntimeError CoreValue := do
  let cell ← getStateCell module state path.root
  let result ← match cell, path.path.toList with
    | .scalar value, segments => readNestedValue module env value segments
    | .map _ valueType _ entries, .mapKey keyRef :: rest => do
        let key ← evalRef env keyRef
        let value := (findMapValue? entries key).getD (typeDefaultForModule module valueType)
        readNestedValue module env value rest
    | .fixedArray element entries, .index indexRef :: rest =>
        readNestedValue module env (.fixedArray element entries) (.index indexRef :: rest)
    | .dynamicArray element entries, .index indexRef :: rest =>
        readNestedValue module env (.array element entries) (.index indexRef :: rest)
    | .record typeId fields, .field fieldId :: rest =>
        let aggregate := typeDefaultForModule module (.structType typeId)
        match aggregate with
        | .structValue _ defaults =>
            let merged := defaults.map fun field => (field.1, (fields field.1).getD field.2)
            readNestedValue module env (.structValue typeId merged) (.field fieldId :: rest)
        | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
            .bytes _ | .string _ | .hash _ | .memRef _ _ | .fixedArray _ _ | .array _ _ =>
          .error .invalidStorageShape
    | .fixedArray element entries, [] => .ok (.fixedArray element entries)
    | .dynamicArray element entries, [] => .ok (.array element entries)
    | .record typeId fields, [] =>
        match typeDefaultForModule module (.structType typeId) with
        | .structValue _ defaults => .ok (.structValue typeId
            (defaults.map fun field => (field.1, (fields field.1).getD field.2)))
        | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
            .bytes _ | .string _ | .hash _ | .memRef _ _ | .fixedArray _ _ | .array _ _ =>
          .error .invalidStorageShape
    | .map _ _ _ _, [] | .map _ _ _ _, .index _ :: _ |
        .map _ _ _ _, .field _ :: _ |
        .fixedArray _ _, .mapKey _ :: _ | .fixedArray _ _, .field _ :: _ |
        .dynamicArray _ _, .mapKey _ :: _ | .dynamicArray _ _, .field _ :: _ |
        .record _ _, .mapKey _ :: _ | .record _ _, .index _ :: _ =>
      .error .invalidStorageShape
  if valueHasType module result path.resultType then .ok result else .error .typeMismatch

def writePath (module : Module) (env : Env) (state : LogicalState) (path : StorageRef)
    (value : CoreValue) : Except RuntimeError LogicalState := do
  unless valueHasType module value path.resultType do
    .error .typeMismatch
  let cell ← getStateCell module state path.root
  let newCell ← match cell, path.path.toList with
    | .scalar previous, segments => do
        let updated ← writeNestedValue module env previous segments value
        .ok (.scalar updated)
    | .map keyType valueType capacity entries, .mapKey keyRef :: rest => do
        let key ← evalRef env keyRef
        let previous := (findMapValue? entries key).getD (typeDefaultForModule module valueType)
        let updated ← writeNestedValue module env previous rest value
        unless valueHasType module updated valueType do
          .error .typeMismatch
        let isNew := (findMapValue? entries key).isNone
        match capacity with
        | some maximum =>
            if isNew && entries.size ≥ maximum then .error (.mapCapacityExceeded maximum)
            else .ok (.map keyType valueType capacity (upsertMapEntry entries key updated))
        | none => .ok (.map keyType valueType capacity (upsertMapEntry entries key updated))
    | .fixedArray element entries, .index indexRef :: rest => do
        let updated ← writeNestedValue module env (.fixedArray element entries)
          (.index indexRef :: rest) value
        match updated with
        | .fixedArray _ updatedEntries =>
            let requested := valueFootprint (.fixedArray element updatedEntries)
            if requested > maxLogicalCollectionLength then
              .error (.collectionLimitExceeded requested maxLogicalCollectionLength)
            .ok (.fixedArray element updatedEntries)
        | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
            .bytes _ | .string _ | .hash _ | .memRef _ _ | .array _ _ | .structValue _ _ =>
          .error .invalidStorageShape
    | .dynamicArray element entries, .index indexRef :: rest => do
        let updated ← writeNestedValue module env (.array element entries)
          (.index indexRef :: rest) value
        match updated with
        | .array _ updatedEntries =>
            let requested := valueFootprint (.array element updatedEntries)
            if requested > maxLogicalCollectionLength then
              .error (.collectionLimitExceeded requested maxLogicalCollectionLength)
            .ok (.dynamicArray element updatedEntries)
        | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
            .bytes _ | .string _ | .hash _ | .memRef _ _ | .fixedArray _ _ | .structValue _ _ =>
          .error .invalidStorageShape
    | .record typeId fields, .field fieldId :: rest => do
        let fieldType ← match structFieldType? module typeId fieldId with
          | some fieldType => .ok fieldType
          | none => .error .invalidStorageShape
        let previous := (fields fieldId).getD (typeDefaultForModule module fieldType)
        let updated ← writeNestedValue module env previous rest value
        .ok (.record typeId (fun candidate =>
          if candidate == fieldId then some updated else fields candidate))
    | .fixedArray element _, [] =>
        match value with
        | .fixedArray replacementElement replacementEntries =>
            if replacementElement == element then
              let requested := valueFootprint (.fixedArray element replacementEntries)
              if requested > maxLogicalCollectionLength then
                .error (.collectionLimitExceeded requested maxLogicalCollectionLength)
              .ok (.fixedArray element replacementEntries)
            else .error .typeMismatch
        | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
            .bytes _ | .string _ | .hash _ | .memRef _ _ | .array _ _ | .structValue _ _ =>
          .error .typeMismatch
    | .dynamicArray element _, [] =>
        match value with
        | .array replacementElement replacementEntries =>
            if replacementElement == element then
              let requested := valueFootprint (.array element replacementEntries)
              if requested > maxLogicalCollectionLength then
                .error (.collectionLimitExceeded requested maxLogicalCollectionLength)
              .ok (.dynamicArray element replacementEntries)
            else .error .typeMismatch
        | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
            .bytes _ | .string _ | .hash _ | .memRef _ _ | .fixedArray _ _ | .structValue _ _ =>
          .error .typeMismatch
    | .record typeId _, [] =>
        match value with
        | .structValue replacementType fields =>
            if replacementType == typeId then .ok (.record typeId fun fieldId =>
              (fields.find? (fun field => field.1 == fieldId)).map (·.2))
            else .error .typeMismatch
        | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
            .bytes _ | .string _ | .hash _ | .memRef _ _ | .fixedArray _ _ | .array _ _ =>
          .error .typeMismatch
    | .map _ _ _ _, [] | .map _ _ _ _, .index _ :: _ |
        .map _ _ _ _, .field _ :: _ |
        .fixedArray _ _, .mapKey _ :: _ | .fixedArray _ _, .field _ :: _ |
        .dynamicArray _ _, .mapKey _ :: _ | .dynamicArray _ _, .field _ :: _ |
        .record _ _, .mapKey _ :: _ | .record _ _, .index _ :: _ =>
      .error .invalidStorageShape
  let declaration ← match module.state.find? (·.id == path.root) with
    | some declaration => pure declaration
    | none => .error .invalidStorageShape
  validateStorageCell module declaration.shape newCell
  .ok (setStateCell state path.root newCell)

def containsPath (module : Module) (env : Env) (state : LogicalState)
    (path : StorageRef) : Except RuntimeError CoreValue := do
  let cell ← getStateCell module state path.root
  let present ← match cell, path.path.toList with
    | .map _ _ _ entries, .mapKey keyRef :: rest => do
        let key ← evalRef env keyRef
        match findMapValue? entries key with
        | none => .ok false
        | some value => if rest.isEmpty then .ok true else containsNestedValue module env value rest
    | .fixedArray element entries, .index indexRef :: rest =>
        containsNestedValue module env (.fixedArray element entries) (.index indexRef :: rest)
    | .dynamicArray element entries, .index indexRef :: rest =>
        containsNestedValue module env (.array element entries) (.index indexRef :: rest)
    | .record typeId fields, .field fieldId :: rest =>
        match fields fieldId with
        | none => .ok false
        | some value => if rest.isEmpty then .ok true else containsNestedValue module env value rest
    | .scalar value, segments => containsNestedValue module env value segments
    | .map _ _ _ _, [] | .fixedArray _ _, [] | .dynamicArray _ _, [] |
        .record _ _, [] | .map _ _ _ _, .index _ :: _ |
        .map _ _ _ _, .field _ :: _ |
        .fixedArray _ _, .mapKey _ :: _ | .fixedArray _ _, .field _ :: _ |
        .dynamicArray _ _, .mapKey _ :: _ | .dynamicArray _ _, .field _ :: _ |
        .record _ _, .mapKey _ :: _ | .record _ _, .index _ :: _ =>
      .error .invalidStorageShape
  .ok (.bool present)

/- Length of an array-shaped state. -/

def storageLength (module : Module) (state : LogicalState) (root : StateId) : Except RuntimeError CoreValue := do
  let cell ← getStateCell module state root
  match cell with
  | .fixedArray _ entries | .dynamicArray _ entries => .ok (.u64 (UInt64.ofNat (Array.size entries)))
  | _ => .error .invalidStorageShape

/- Resize a dynamic array, filling new slots with the element type default. -/

def storageResize (module : Module) (state : LogicalState) (root : StateId) (length : CoreValue) : Except RuntimeError LogicalState := do
  let len ← asArrayIndex length
  if len > maxLogicalCollectionLength then
    .error (.collectionLimitExceeded len maxLogicalCollectionLength)
  let cell ← getStateCell module state root
  match cell with
  | .dynamicArray elem entries =>
    let newEntries :=
      if len ≤ Array.size entries then
        Array.shrink entries len
      else
        entries ++ Array.mk (List.replicate (len - Array.size entries)
          (typeDefaultForModule module elem))
    let newCell := StorageCell.dynamicArray elem newEntries
    validateStorageCell module (.dynamicArray elem) newCell
    .ok (setStateCell state root newCell)
  | _ => .error .invalidStorageShape

/- Memory allocation returns a `memRef` handle; loads and stores use that handle. -/

def allocMemory (module : Module) (state : LogicalState) (ty : CoreType)
    (length : CoreValue) : Except RuntimeError (LogicalState × CoreValue) := do
  let len ← asArrayIndex length
  if len > maxLogicalCollectionLength then
    .error (.collectionLimitExceeded len maxLogicalCollectionLength)
  let elementFootprint := typeFootprintForModule module ty
  if elementFootprint > maxLogicalCollectionLength then
    .error (.collectionLimitExceeded elementFootprint maxLogicalCollectionLength)
  let requested := max 1 (saturatingMul len elementFootprint)
  if requested > maxLogicalCollectionLength then
    .error (.collectionLimitExceeded requested maxLogicalCollectionLength)
  let id := state.memory.size
  let entries := Array.mk (List.replicate len (typeDefaultForModule module ty))
  let state' := { state with memory := Array.push state.memory (some (ty, entries)) }
  .ok (state', .memRef ty id)

private def validateMemoryEntries (module : Module) (type : CoreType)
    (entries : Array CoreValue) : Except RuntimeError Unit := do
  if entries.size > maxLogicalCollectionLength then
    .error (.collectionLimitExceeded entries.size maxLogicalCollectionLength)
  for entry in entries do
    unless valueHasType module entry type do
      .error .typeMismatch
  let footprint := valueFootprint (.array type entries)
  if footprint > maxLogicalCollectionLength then
    .error (.collectionLimitExceeded footprint maxLogicalCollectionLength)

def loadMemory (module : Module) (state : LogicalState) (base index : CoreValue) : Except RuntimeError CoreValue := do
  let (element, id) ← match base with
    | .memRef element id => .ok (element, id)
    | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
        .bytes _ | .string _ | .hash _ | .fixedArray _ _ | .array _ _ | .structValue _ _ =>
      .error .typeMismatch
  let i ← asArrayIndex index
  match state.memory[id]? with
  | none => .error (.invalidMemoryRef id)
  | some none => .error (.memoryAlreadyReleased id)
  | some (some (ty, entries)) =>
    if element != ty then .error .typeMismatch
    else do
      validateMemoryEntries module ty entries
      if h : i < Array.size entries then .ok entries[i] else .error .arrayOutOfBounds

def storeMemory (module : Module) (state : LogicalState) (base index value : CoreValue) : Except RuntimeError LogicalState := do
  let (element, id) ← match base with
    | .memRef element id => .ok (element, id)
    | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
        .bytes _ | .string _ | .hash _ | .fixedArray _ _ | .array _ _ | .structValue _ _ =>
      .error .typeMismatch
  let i ← asArrayIndex index
  match state.memory[id]? with
  | none => .error (.invalidMemoryRef id)
  | some none => .error (.memoryAlreadyReleased id)
  | some (some (ty, entries)) =>
    if element != ty || !valueHasType module value ty then
      .error .typeMismatch
    else if h : i < Array.size entries then
      if hid : id < state.memory.size then
        let newEntries := Array.set entries i value h
        validateMemoryEntries module ty newEntries
        .ok { state with memory :=
          (Array.set state.memory id (some (ty, newEntries)) hid) }
      else
        .error (.invalidMemoryRef id)
    else
      .error .arrayOutOfBounds

def releaseMemory (module : Module) (state : LogicalState) (base : CoreValue) : Except RuntimeError LogicalState := do
  let (element, id) ← match base with
    | .memRef element id => .ok (element, id)
    | .unit | .bool _ | .u8 _ | .u32 _ | .u64 _ | .u128 _ | .address _ |
        .bytes _ | .string _ | .hash _ | .fixedArray _ _ | .array _ _ | .structValue _ _ =>
      .error .typeMismatch
  match state.memory[id]? with
  | none => .error (.invalidMemoryRef id)
  | some none => .error (.memoryAlreadyReleased id)
  | some (some (ty, entries)) =>
      if element != ty then .error .typeMismatch
      else do
        validateMemoryEntries module ty entries
        if h : id < state.memory.size then
          .ok { state with memory := Array.set state.memory id none h }
        else
          .error (.invalidMemoryRef id)

/- Bind typed values into an existing environment. Jump bindings overwrite only
their target block parameters, so values from dominating blocks stay live. -/

def bindParams (module : Module) (params : Array ValueDef) (args : Array CoreValue) (env : Env) :
    Except RuntimeError Env := do
  unless params.size == args.size do
    .error .argMismatch
  let mut bound := env
  for i in [:params.size] do
    let param := params[i]!
    let arg := args[i]!
    unless valueHasType module arg param.type do
      .error .typeMismatch
    bound := bound.insert param.id arg
  return bound

/- Bind instruction results to produced values. -/

def bindResults (module : Module) (results : Array ValueDef) (values : Array CoreValue)
    (env : Env) : Except RuntimeError Env := do
  unless results.size == values.size do
    .error .typeMismatch
  let mut bound := env
  for i in [:results.size] do
    let result := results[i]!
    let value := values[i]!
    unless valueHasType module value result.type do
      .error .typeMismatch
    bound := bound.insert result.id value
  return bound

/- Execute a single instruction. -/

def execInstruction (host : HostSemantics) (module : Module) (env : Env) (state : LogicalState) (trace : ObservableTrace) (instr : Instruction) : Except RuntimeError (Env × LogicalState × ObservableTrace) := do
  match instr.op with
  | .pure (.hash arg) =>
    let argValue ← evalRef env arg
    let value ← host.handleHash argValue
    let env' ← bindResults module instr.results #[value] env
    .ok (env', state, trace)
  | .pure (.hashTwoToOne lhs rhs) =>
    let lhsValue ← evalRef env lhs
    let rhsValue ← evalRef env rhs
    let preimage ← match lhsValue, rhsValue with
      | .hash left, .hash right => .ok (.hash (left ++ right))
      | _, _ => .error .typeMismatch
    let value ← host.handleHash preimage
    let env' ← bindResults module instr.results #[value] env
    .ok (env', state, trace)
  | .pure op =>
    let resultType ← match instr.results with
      | #[result] => .ok result.type
      | #[] => .error .typeMismatch
      | _ => .error .typeMismatch
    let v ← evalPureOp env resultType op
    let env' ← bindResults module instr.results #[v] env
    .ok (env', state, trace)
  | .storageLoad path =>
    let v ← readPath module env state path
    let env' ← bindResults module instr.results #[v] env
    .ok (env', state, trace)
  | .storageContains path =>
    let v ← containsPath module env state path
    let env' ← bindResults module instr.results #[v] env
    .ok (env', state, trace)
  | .storageStore path value =>
    let v ← evalRef env value
    let state' ← writePath module env state path v
    .ok (env, state', trace)
  | .storageLength root =>
    let v ← storageLength module state root
    let env' ← bindResults module instr.results #[v] env
    .ok (env', state, trace)
  | .storageResize root length =>
    let len ← evalRef env length
    let state' ← storageResize module state root len
    .ok (env, state', trace)
  | .memoryAlloc ty length =>
    let len ← evalRef env length
    let (state', ref) ← allocMemory module state ty len
    let env' ← bindResults module instr.results #[ref] env
    .ok (env', state', trace)
  | .memoryLoad base index =>
    let b ← evalRef env base
    let i ← evalRef env index
    let v ← loadMemory module state b i
    let env' ← bindResults module instr.results #[v] env
    .ok (env', state, trace)
  | .memoryStore base index value =>
    let b ← evalRef env base
    let i ← evalRef env index
    let v ← evalRef env value
    let state' ← storeMemory module state b i v
    .ok (env, state', trace)
  | .memoryRelease base =>
    let b ← evalRef env base
    let state' ← releaseMemory module state b
    .ok (env, state', trace)
  | .contextRead field =>
    let v ← host.handleContext field
    let env' ← bindResults module instr.results #[v] env
    .ok (env', state, trace)
  | .emit eventId args =>
    let argVals ← args.mapM (evalRef env)
    let trace' := { trace with effects := trace.effects.push (.emit eventId argVals) }
    .ok (env, state, trace')
  | .assert condition error =>
    let cond ← evalRef env condition
    match cond with
    | .bool true => .ok (env, state, trace)
    | .bool false => .error (.assertionFailure (← evalErrorRef env error))
    | _ => .error .typeMismatch
  | .crosscall spec args =>
    let target ← evalRef env spec.target
    let method ← evalRef env spec.method
    let gas ← spec.gas.mapM (evalRef env)
    let value ← spec.value.mapM (evalRef env)
    let argVals ← args.mapM (evalRef env)
    let request : RuntimeCrosscallRequest := {
      mode := spec.mode, target := target, method := method, gas := gas,
      value := value, args := argVals, returnType := spec.returnType
    }
    let (result, state') ← host.handleCrosscall request state
    let resultValues ← if spec.returnType == .unit then
        match result with
        | none => .ok #[]
        | some _ => .error .typeMismatch
      else
        match result with
        | some result => .ok #[result]
        | none => .error .typeMismatch
    let env' ← bindResults module instr.results resultValues env
    let trace' := { trace with effects := trace.effects.push (.crosscall request) }
    let effectiveState := if spec.mode == .delegateInvoke then
        { state' with memory := state.memory }
      else state
    .ok (env', effectiveState, trace')
  | .hostCall call =>
    let argVals ← call.args.mapM (evalRef env)
    let (v, state') ← host.handle call argVals state
    let trace' := { trace with effects := trace.effects.push (.hostCall call.id argVals) }
    let env' ← bindResults module instr.results #[v] env
    .ok (env', state', trace')

/- Execute all instructions of a block in order. -/

def execInstructions (host : HostSemantics) (module : Module) (env : Env) (state : LogicalState) (trace : ObservableTrace) (instrs : Array Instruction) : Except RuntimeError (Env × LogicalState × ObservableTrace) :=
  instrs.foldlM (fun (env, state, trace) instr =>
    execInstruction host module env state trace instr) (env, state, trace)

abbrev LoopBudgets := Std.HashMap BlockId Nat

/- A bound belongs to the loop-tail block that carries the annotated backedge.
It is consumed before that block executes, so `atMost 0` executes zero loop
iterations rather than failing only after the loop body has run. -/

def consumeLoopBound (block : Block) (budgets : LoopBudgets) :
    Except RuntimeError LoopBudgets :=
  match block.terminator with
  | .jump _ _ (some (.atMost maximum)) =>
    let remaining := (Std.HashMap.get? budgets block.id).getD maximum
    if remaining == 0 then
      .error (.loopBoundExceeded block.id)
    else
      .ok (budgets.insert block.id (remaining - 1))
  | .jump _ _ (some .requiresUnbounded) | .jump _ _ none
  | .branch _ _ _ | .return _ | .revert _ => .ok budgets

/- Execute a block. Fuel decreases on every block transition so execution is
total and bounded. Loop budgets are threaded separately from global fuel. -/

def execBlockWithBudgets (host : HostSemantics) (fuel : Nat) (module : Module)
    (func : Function) (env : Env) (state : LogicalState) (trace : ObservableTrace)
    (budgets : LoopBudgets) (blockId : BlockId) : Except RuntimeError ExecutionResult :=
  match fuel with
  | 0 => .error .outOfFuel
  | fuel + 1 => do
    let block ← match func.blocks.find? (fun b => b.id == blockId) with
      | some b => .ok b
      | none => .error .missingFunction
    let budgets' ← consumeLoopBound block budgets
    let (env', state', trace') ← execInstructions host module env state trace block.instructions
    match block.terminator with
    | .jump target args _ => do
      let targetBlock ← match func.blocks.find? (fun b => b.id == target) with
        | some b => .ok b
        | none => .error .missingFunction
      let argVals ← args.mapM (evalRef env')
      let env'' ← bindParams module targetBlock.params argVals env'
      execBlockWithBudgets host fuel module func env'' state' trace' budgets' target
    | .branch condition onTrue onFalse => do
      let cond ← evalRef env' condition
      match cond with
      | .bool true => execBlockWithBudgets host fuel module func env' state' trace' budgets' onTrue
      | .bool false => execBlockWithBudgets host fuel module func env' state' trace' budgets' onFalse
      | _ => .error .typeMismatch
    | .return values => do
      let vals ← values.mapM (evalRef env')
      let finalState := { state' with memory := #[] }
      validateLogicalState module finalState
      match vals with
      | #[] =>
        if func.retType == .unit then
          .ok { returnValue := .unit, finalState := finalState, trace := trace' }
        else
          .error .typeMismatch
      | #[v] =>
        if func.retType != .unit && valueHasType module v func.retType then
          .ok { returnValue := v, finalState := finalState, trace := trace' }
        else
          .error .typeMismatch
      | _ => .error .typeMismatch
    | .revert error => .error (.explicitRevert (← evalErrorRef env' error))

def execBlock (host : HostSemantics) (fuel : Nat) (module : Module)
    (func : Function) (env : Env) (state : LogicalState) (trace : ObservableTrace)
    (blockId : BlockId) : Except RuntimeError ExecutionResult :=
  execBlockWithBudgets host fuel module func env state trace {} blockId

/- Entry point: validate the entry function, bind arguments, and start execution
with the provided fuel. This function is total: every path returns a result or a
`RuntimeError`. -/

def execute (host : HostSemantics) (fuel : Nat) (checked : CheckedCanonicalContract) (entrypoint : FunctionId) (args : Array CoreValue) (state : LogicalState) : Except RuntimeError ExecutionResult := do
  let module := checked.contract.module
  unless checked.contract.interface.entrypoints.any (·.functionId == entrypoint) do
    .error .missingFunction
  let func ← match module.functions.find? (fun f => f.id == entrypoint) with
    | some f => .ok f
    | none => .error .missingFunction
  unless func.params.size == args.size do
    .error .argMismatch
  for i in [:func.params.size] do
    unless valueHasType module args[i]! func.params[i]!.type do
      .error .argMismatch
  let callState := { state with memory := #[] }
  validateLogicalState module callState
  let env ← bindParams module func.params args {}
  execBlock host fuel module func env callState {} func.entry

end ProofForge.IR.Core.Semantics

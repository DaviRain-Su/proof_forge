import ProofForge.Frontend.Authored.Syntax
import ProofForge.Frontend.Authored.Validate
import ProofForge.IR.Core
import ProofForge.IR.Canonical
import Std

/-! # Authored AST — Normalizer Environment

Symbol tables, identifier supplies, and monadic infrastructure for
the Authored-to-Core normalizer. Mirrors the Legacy adapter's `AdapterEnv`/
`AdapterState`/`AdapterM` but with Authored-owned types and error messages.
-/

namespace ProofForge.Frontend.Authored.Canonicalize

open ProofForge.IR.Core

/-- Errors produced by the Authored normalizer. Fail-closed: no wildcard fallback. -/
inductive AuthoredNormalizeError
  | unknownState (name : String)
  | unknownFunction (name : String)
  | unknownEvent (name : String)
  | unknownType (name : String)
  | unknownError (name : String)
  | unboundLocal (name : String)
  | typeMismatch (expected : String) (actual : String)
  | literalOutOfRange (ty : String) (value : String)
  | invalidLValue (desc : String)
  | terminatedBlock (desc : String)
  | unboundedLoop (reason : String)
  | unsupportedAuthored (nodeTag : String) (reason : String)
  | duplicateName (context : String) (name : String)
  | validation (error : ProofForge.IR.Core.Error.ValidationError)
  deriving Repr

/-- Resolve a Authored type to a Core type using the declaration-order type-id map. -/
def resolveAuthoredType (typeIds : Std.HashMap String TypeId)
    (ty : AuthoredType) : Except AuthoredNormalizeError CoreType :=
  match ty with
  | .unit => .ok .unit
  | .bool => .ok .bool
  | .u8 => .ok .u8
  | .u32 => .ok .u32
  | .u64 => .ok .u64
  | .u128 => .ok .u128
  | .address => .ok .address
  | .bytes => .ok .bytes
  | .string => .ok .string
  | .hash => .ok .hash
  | .fixedArray elem len => do .ok (.fixedArray (← resolveAuthoredType typeIds elem) len)
  | .array elem => do .ok (.array (← resolveAuthoredType typeIds elem))
  | .memoryRef elem => do .ok (.memoryRef (← resolveAuthoredType typeIds elem))
  | .structType name =>
    match Std.HashMap.get? typeIds name with
    | some id => .ok (.structType id)
    | none => .error (AuthoredNormalizeError.unknownType name)

/-- Resolve a Authored state kind to a Core StateShape. -/
def resolveStateKind (typeIds : Std.HashMap String TypeId)
    (kind : AuthoredStateKind) : Except AuthoredNormalizeError StateShape :=
  match kind with
  | .scalar ty => do .ok (.scalar (← resolveAuthoredType typeIds ty))
  | .map kty vty cap => do
      .ok (.map (← resolveAuthoredType typeIds kty)
        (← resolveAuthoredType typeIds vty) cap)
  | .mapN keyTypes valueType cap => do
      .ok (.mapN (← keyTypes.mapM (resolveAuthoredType typeIds))
        (← resolveAuthoredType typeIds valueType) cap)
  | .fixedArray elem len => do .ok (.fixedArray (← resolveAuthoredType typeIds elem) len)
  | .dynamicArray elem => do .ok (.dynamicArray (← resolveAuthoredType typeIds elem))
  | .record typeName =>
    match Std.HashMap.get? typeIds typeName with
    | some id => .ok (.record id)
    | none => .error (AuthoredNormalizeError.unknownType typeName)

/-- Convert a Authored literal to a Core literal, checking fixed-width ranges. -/
def adaptLiteral (lit : AuthoredLiteral) : Except AuthoredNormalizeError CoreLiteral :=
  match lit with
  | .unitLit => .ok .unitLit
  | .boolLit b => .ok (.boolLit b)
  | .u8Lit n =>
      if n < 256 then .ok (.u8Lit n)
      else .error (AuthoredNormalizeError.literalOutOfRange "u8" (toString n))
  | .u32Lit n =>
      if n < 4294967296 then .ok (.u32Lit n)
      else .error (AuthoredNormalizeError.literalOutOfRange "u32" (toString n))
  | .u64Lit n =>
      if n < 18446744073709551616 then .ok (.u64Lit n)
      else .error (AuthoredNormalizeError.literalOutOfRange "u64" (toString n))
  | .u128Lit n =>
      if n < 340282366920938463463374607431768211456 then .ok (.u128Lit n)
      else .error (AuthoredNormalizeError.literalOutOfRange "u128" (toString n))
  | .addressLit s => .ok (.addressLit s)
  | .stringLit s => .ok (.stringLit s)
  | .hashLit s => .ok (.hashLit s)
  | .bytesLit data => .ok (.bytesLit data)
/-- Core literal result type. -/
def coreLiteralType (l : CoreLiteral) : CoreType :=
  match l with
  | .unitLit => .unit
  | .boolLit _ => .bool
  | .u8Lit _ => .u8
  | .u32Lit _ => .u32
  | .u64Lit _ => .u64
  | .u128Lit _ => .u128
  | .addressLit _ => .address
  | .bytesLit _ => .bytes
  | .stringLit _ => .string
  | .hashLit _ => .hash

/-- Convert a Authored arithmetic op to a Core arithmetic op. -/
def adaptArithOp (op : AuthoredArithOp) : ArithmeticOp :=
  match op with
  | .add => .add | .sub => .sub | .mul => .mul | .div => .div | .mod => .mod
  | .bitAnd => .and | .bitOr => .or | .bitXor => .xor
  | .shiftLeft => .shl | .shiftRight => .shr

/-- Convert a Authored comparison op to a Core comparison op. -/
def adaptCompareOp (op : AuthoredCompareOp) : CompareOp :=
  match op with
  | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge

/-- Convert a Authored unary op to a Core unary op. -/
def adaptUnaryOp (op : AuthoredUnaryOp) : UnaryOp :=
  match op with | .not => .not | .neg => .neg

/-- Convert a Authored context field to a Core context field. -/
def adaptContextField (field : AuthoredContextField) : ContextField :=
  match field with
  | .sender => .sender
  | .value => .value
  | .blockNumber => .blockNumber
  | .blockTimestamp => .blockTimestamp
  | .gas => .gas
  | .contractAddress => .contractAddress

/-- Result type of a Core context read. -/
def contextFieldType (field : ContextField) : CoreType :=
  match field with
  | .sender | .signer | .contractAddress => .address
  | .value => .u128
  | .blockNumber | .blockTimestamp | .gas => .u64

/- Convert a Authored constructor binding kind to Canonical. -/
def adaptCtorKind (kind : AuthoredConstructorBindingKind) :
    ProofForge.IR.Canonical.ConstructorBindingKind :=
  match kind with
  | .scalarU64 => .scalarU64
  | .addressWord => .addressWord
  | .addressKeccak => .addressKeccak
  | .stringLength => .stringLength
  | .stringKeccak => .stringKeccak
  | .bytesLength => .bytesLength
  | .bytesKeccak => .bytesKeccak
  | .arrayLength => .arrayLength
  | .arraySumU64 => .arraySumU64

/- Convert a Authored mutability to Interface. -/
def adaptMutability (mut_ : AuthoredMutability) :
    ProofForge.IR.Canonical.InterfaceMutability :=
  match mut_ with | .call => .call | .view => .view

/-- Resolved symbol tables and identifier supplies. -/
structure AuthoredEnv where
  typeIds : Std.HashMap String TypeId
  structFields : Std.HashMap TypeId (Array (String × CoreType))
  stateIds : Std.HashMap String (StateId × StateShape)
  functionIds : Std.HashMap String FunctionId
  eventIds : Std.HashMap String EventId
  errorDecls : Array ErrorDecl
  overflowMode : OverflowMode
  localValues : Std.HashMap String ValueRef
  nextTypeId : Nat
  nextStateId : Nat
  nextFunctionId : Nat
  nextEventId : Nat
  nextErrorId : Nat
  deriving Repr

structure AuthoredState where
  env : AuthoredEnv
  nextValueId : Nat
  nextBlockId : Nat
  deriving Repr

abbrev AuthoredM := StateT AuthoredState (Except AuthoredNormalizeError)

/-- Lift an Except into AuthoredM. -/
def liftExcept {α} : Except AuthoredNormalizeError α → AuthoredM α :=
  fun x => match x with | .ok a => return a | .error e => throw e

/-- Fresh value ID. -/
def freshValueId : AuthoredM ValueId := do
  let s ← get
  set { s with nextValueId := s.nextValueId + 1 }
  return ⟨s.nextValueId⟩

/-- Fresh block ID. -/
def freshBlockId : AuthoredM BlockId := do
  let s ← get
  set { s with nextBlockId := s.nextBlockId + 1 }
  return ⟨s.nextBlockId⟩

/-- Lookup a type by name. -/
def lookupType (name : String) : AuthoredM TypeId := do
  match Std.HashMap.get? (← get).env.typeIds name with
  | some id => return id
  | none => throw (AuthoredNormalizeError.unknownType name)

/-- Lookup a state by name. -/
def lookupState (name : String) : AuthoredM StateId := do
  match Std.HashMap.get? (← get).env.stateIds name with
  | some (id, _) => return id
  | none => throw (AuthoredNormalizeError.unknownState name)

/-- Lookup a state shape by name. -/
def lookupStateShape (name : String) : AuthoredM StateShape := do
  match Std.HashMap.get? (← get).env.stateIds name with
  | some (_, shape) => return shape
  | none => throw (AuthoredNormalizeError.unknownState name)

/-- Lookup a function by name. -/
def lookupFunction (name : String) : AuthoredM FunctionId := do
  match Std.HashMap.get? (← get).env.functionIds name with
  | some id => return id
  | none => throw (AuthoredNormalizeError.unknownFunction name)

/-- Lookup an event by name. -/
def lookupEvent (name : String) : AuthoredM EventId := do
  match Std.HashMap.get? (← get).env.eventIds name with
  | some id => return id
  | none => throw (AuthoredNormalizeError.unknownEvent name)

/-- Lookup a local by name. -/
def lookupLocal (name : String) : AuthoredM ValueRef := do
  match Std.HashMap.get? (← get).env.localValues name with
  | some ref => return ref
  | none => throw (AuthoredNormalizeError.unboundLocal name)

/-- Bind a local name to a value reference. -/
def bindLocal (name : String) (ref : ValueRef) : AuthoredM Unit :=
  modify (fun s => { s with env := { s.env with localValues := s.env.localValues.insert name ref } })

/-- Reset local bindings (at function boundary). -/
def resetLocals : AuthoredM Unit :=
  modify (fun s => { s with env := { s.env with localValues := {} } })

/-- Scalar element type of a state variable. -/
def stateScalarType (name : String) : AuthoredM CoreType := do
  let shape ← lookupStateShape name
  match shape with
  | .scalar ty => return ty
  | _ => throw (AuthoredNormalizeError.typeMismatch "scalar" "non-scalar state")

def stateMapTypes (name : String) : AuthoredM (CoreType × CoreType) := do
  let shape ← lookupStateShape name
  match shape with
  | .map keyType valueType _ => return (keyType, valueType)
  | _ => throw (AuthoredNormalizeError.typeMismatch "map" "non-map state")

def lookupStructField (typeId : TypeId) (name : String) : AuthoredM (FieldId × CoreType) := do
  let fields ← match Std.HashMap.get? (← get).env.structFields typeId with
    | some fields => pure fields
    | none => throw (AuthoredNormalizeError.unknownType s!"type#{typeId.value}")
  match fields.findIdx? (fun field => field.1 == name) with
  | some index => return (⟨index⟩, fields[index]!.2)
  | none => throw (AuthoredNormalizeError.unknownType s!"type#{typeId.value}.{name}")

def stateArrayType (name : String) : AuthoredM CoreType := do
  let shape ← lookupStateShape name
  match shape with
  | .fixedArray element _ | .dynamicArray element => return element
  | _ => throw (AuthoredNormalizeError.typeMismatch "array" "non-array state")

/-- Build a resolved Authored environment from a AuthoredContract.
Identifiers are assigned deterministically in declaration order. -/
def buildEnv (contract : AuthoredContract) : Except AuthoredNormalizeError AuthoredEnv := do
  let mut env : AuthoredEnv := {
    typeIds := {},
    structFields := {},
    stateIds := {},
    functionIds := {},
    eventIds := {},
    errorDecls := #[],
    overflowMode := .checked,
    localValues := {},
    nextTypeId := 0,
    nextStateId := 0,
    nextFunctionId := 0,
    nextEventId := 0,
    nextErrorId := 0
  }
  for struct in contract.structs do
    let id := ⟨env.nextTypeId⟩
    env := { env with typeIds := env.typeIds.insert struct.name id, nextTypeId := env.nextTypeId + 1 }
  for struct in contract.structs do
    let typeId ← match Std.HashMap.get? env.typeIds struct.name with
      | some typeId => pure typeId
      | none => throw (AuthoredNormalizeError.unknownType struct.name)
    let fields ← struct.fields.mapM fun field => do
      let type ← resolveAuthoredType env.typeIds field.type
      return (field.name, type)
    env := { env with structFields := env.structFields.insert typeId fields }
  for state in contract.state do
    let id := ⟨env.nextStateId⟩
    let shape ← resolveStateKind env.typeIds state.kind
    env := { env with stateIds := env.stateIds.insert state.name (id, shape), nextStateId := env.nextStateId + 1 }
  for ep in contract.entrypoints do
    let id := ⟨env.nextFunctionId⟩
    env := { env with functionIds := env.functionIds.insert ep.name id, nextFunctionId := env.nextFunctionId + 1 }
  for ev in contract.events do
    let id := ⟨env.nextEventId⟩
    env := { env with eventIds := env.eventIds.insert ev.name id, nextEventId := env.nextEventId + 1 }
  for err in contract.errors do
    let id := ⟨env.nextErrorId⟩
    let coreParams ← err.params.mapM (resolveAuthoredType env.typeIds)
    env := { env with
      errorDecls := env.errorDecls.push {
        id := id, namespace_ := "$surface", name := err.name, code := id.value, params := coreParams }
      nextErrorId := env.nextErrorId + 1 }
  return env

/-- Construct empty AuthoredState from an environment. -/
def AuthoredState.ofEnv (env : AuthoredEnv) : AuthoredState :=
  { env := env, nextValueId := 0, nextBlockId := 0 }

end ProofForge.Frontend.Authored.Canonicalize

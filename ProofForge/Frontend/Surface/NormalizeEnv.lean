import ProofForge.Frontend.Surface.Syntax
import ProofForge.Frontend.Surface.Validate
import ProofForge.IR.Core
import ProofForge.IR.Canonical
import Std

/-! # Surface AST — Normalizer Environment

Symbol tables, identifier supplies, and monadic infrastructure for
the Surface-to-Core normalizer. Mirrors the Legacy adapter's `AdapterEnv`/
`AdapterState`/`AdapterM` but with Surface-owned types and error messages.
-/

namespace ProofForge.Frontend.Surface

open ProofForge.IR.Core

/-- Errors produced by the Surface normalizer. Fail-closed: no wildcard fallback. -/
inductive SurfaceNormalizeError
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
  | unsupportedSurface (nodeTag : String) (reason : String)
  | duplicateName (context : String) (name : String)
  | validation (error : ProofForge.IR.Core.Error.ValidationError)
  deriving Repr

/-- Resolve a Surface type to a Core type using the declaration-order type-id map. -/
def resolveSurfaceType (typeIds : Std.HashMap String TypeId)
    (ty : SurfaceType) : Except SurfaceNormalizeError CoreType :=
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
  | .fixedArray elem len => do .ok (.fixedArray (← resolveSurfaceType typeIds elem) len)
  | .array elem => do .ok (.array (← resolveSurfaceType typeIds elem))
  | .structType name =>
    match Std.HashMap.get? typeIds name with
    | some id => .ok (.structType id)
    | none => .error (SurfaceNormalizeError.unknownType name)

/-- Resolve a Surface state kind to a Core StateShape. -/
def resolveStateKind (typeIds : Std.HashMap String TypeId)
    (kind : SurfaceStateKind) : Except SurfaceNormalizeError StateShape :=
  match kind with
  | .scalar ty => do .ok (.scalar (← resolveSurfaceType typeIds ty))
  | .map kty vty cap => do
      .ok (.map (← resolveSurfaceType typeIds kty)
        (← resolveSurfaceType typeIds vty) cap)
  | .fixedArray elem len => do .ok (.fixedArray (← resolveSurfaceType typeIds elem) len)
  | .dynamicArray elem => do .ok (.dynamicArray (← resolveSurfaceType typeIds elem))
  | .record typeName =>
    match Std.HashMap.get? typeIds typeName with
    | some id => .ok (.record id)
    | none => .error (SurfaceNormalizeError.unknownType typeName)

/-- Convert a Surface literal to a Core literal, checking fixed-width ranges. -/
def adaptLiteral (lit : SurfaceLiteral) : Except SurfaceNormalizeError CoreLiteral :=
  match lit with
  | .unitLit => .ok .unitLit
  | .boolLit b => .ok (.boolLit b)
  | .u8Lit n =>
      if n < 256 then .ok (.u8Lit n)
      else .error (SurfaceNormalizeError.literalOutOfRange "u8" (toString n))
  | .u32Lit n =>
      if n < 4294967296 then .ok (.u32Lit n)
      else .error (SurfaceNormalizeError.literalOutOfRange "u32" (toString n))
  | .u64Lit n =>
      if n < 18446744073709551616 then .ok (.u64Lit n)
      else .error (SurfaceNormalizeError.literalOutOfRange "u64" (toString n))
  | .u128Lit n =>
      if n < 340282366920938463463374607431768211456 then .ok (.u128Lit n)
      else .error (SurfaceNormalizeError.literalOutOfRange "u128" (toString n))
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

/-- Convert a Surface arithmetic op to a Core arithmetic op. -/
def adaptArithOp (op : SurfaceArithOp) : ArithmeticOp :=
  match op with
  | .add => .add | .sub => .sub | .mul => .mul | .div => .div | .mod => .mod
  | .bitAnd => .and | .bitOr => .or | .bitXor => .xor
  | .shiftLeft => .shl | .shiftRight => .shr

/-- Convert a Surface comparison op to a Core comparison op. -/
def adaptCompareOp (op : SurfaceCompareOp) : CompareOp :=
  match op with
  | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge

/-- Convert a Surface unary op to a Core unary op. -/
def adaptUnaryOp (op : SurfaceUnaryOp) : UnaryOp :=
  match op with | .not => .not | .neg => .neg

/-- Convert a Surface context field to a Core context field. -/
def adaptContextField (field : SurfaceContextField) : ContextField :=
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
  | .sender | .contractAddress => .address
  | .value => .u128
  | .blockNumber | .blockTimestamp | .gas => .u64

/- Convert a Surface constructor binding kind to Canonical. -/
def adaptCtorKind (kind : SurfaceConstructorBindingKind) :
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

/- Convert a Surface mutability to Interface. -/
def adaptMutability (mut_ : SurfaceMutability) :
    ProofForge.IR.Canonical.InterfaceMutability :=
  match mut_ with | .call => .call | .view => .view

/-- Resolved symbol tables and identifier supplies. -/
structure SurfaceEnv where
  typeIds : Std.HashMap String TypeId
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

structure SurfaceState where
  env : SurfaceEnv
  nextValueId : Nat
  nextBlockId : Nat
  deriving Repr

abbrev SurfaceM := StateT SurfaceState (Except SurfaceNormalizeError)

/-- Lift an Except into SurfaceM. -/
def liftExcept {α} : Except SurfaceNormalizeError α → SurfaceM α :=
  fun x => match x with | .ok a => return a | .error e => throw e

/-- Fresh value ID. -/
def freshValueId : SurfaceM ValueId := do
  let s ← get
  set { s with nextValueId := s.nextValueId + 1 }
  return ⟨s.nextValueId⟩

/-- Fresh block ID. -/
def freshBlockId : SurfaceM BlockId := do
  let s ← get
  set { s with nextBlockId := s.nextBlockId + 1 }
  return ⟨s.nextBlockId⟩

/-- Lookup a type by name. -/
def lookupType (name : String) : SurfaceM TypeId := do
  match Std.HashMap.get? (← get).env.typeIds name with
  | some id => return id
  | none => throw (SurfaceNormalizeError.unknownType name)

/-- Lookup a state by name. -/
def lookupState (name : String) : SurfaceM StateId := do
  match Std.HashMap.get? (← get).env.stateIds name with
  | some (id, _) => return id
  | none => throw (SurfaceNormalizeError.unknownState name)

/-- Lookup a state shape by name. -/
def lookupStateShape (name : String) : SurfaceM StateShape := do
  match Std.HashMap.get? (← get).env.stateIds name with
  | some (_, shape) => return shape
  | none => throw (SurfaceNormalizeError.unknownState name)

/-- Lookup a function by name. -/
def lookupFunction (name : String) : SurfaceM FunctionId := do
  match Std.HashMap.get? (← get).env.functionIds name with
  | some id => return id
  | none => throw (SurfaceNormalizeError.unknownFunction name)

/-- Lookup an event by name. -/
def lookupEvent (name : String) : SurfaceM EventId := do
  match Std.HashMap.get? (← get).env.eventIds name with
  | some id => return id
  | none => throw (SurfaceNormalizeError.unknownEvent name)

/-- Lookup a local by name. -/
def lookupLocal (name : String) : SurfaceM ValueRef := do
  match Std.HashMap.get? (← get).env.localValues name with
  | some ref => return ref
  | none => throw (SurfaceNormalizeError.unboundLocal name)

/-- Bind a local name to a value reference. -/
def bindLocal (name : String) (ref : ValueRef) : SurfaceM Unit :=
  modify (fun s => { s with env := { s.env with localValues := s.env.localValues.insert name ref } })

/-- Reset local bindings (at function boundary). -/
def resetLocals : SurfaceM Unit :=
  modify (fun s => { s with env := { s.env with localValues := {} } })

/-- Scalar element type of a state variable. -/
def stateScalarType (name : String) : SurfaceM CoreType := do
  let shape ← lookupStateShape name
  match shape with
  | .scalar ty => return ty
  | _ => throw (SurfaceNormalizeError.typeMismatch "scalar" "non-scalar state")

def stateMapTypes (name : String) : SurfaceM (CoreType × CoreType) := do
  let shape ← lookupStateShape name
  match shape with
  | .map keyType valueType _ => return (keyType, valueType)
  | _ => throw (SurfaceNormalizeError.typeMismatch "map" "non-map state")

def stateArrayType (name : String) : SurfaceM CoreType := do
  let shape ← lookupStateShape name
  match shape with
  | .fixedArray element _ | .dynamicArray element => return element
  | _ => throw (SurfaceNormalizeError.typeMismatch "array" "non-array state")

/-- Build a resolved Surface environment from a SurfaceContract.
Identifiers are assigned deterministically in declaration order. -/
def buildEnv (contract : SurfaceContract) : Except SurfaceNormalizeError SurfaceEnv := do
  let mut env : SurfaceEnv := {
    typeIds := {},
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
    let coreParams ← err.params.mapM (resolveSurfaceType env.typeIds)
    env := { env with
      errorDecls := env.errorDecls.push {
        id := id, namespace_ := "$surface", name := err.name, code := id.value, params := coreParams }
      nextErrorId := env.nextErrorId + 1 }
  return env

/-- Construct empty SurfaceState from an environment. -/
def SurfaceState.ofEnv (env : SurfaceEnv) : SurfaceState :=
  { env := env, nextValueId := 0, nextBlockId := 0 }

end ProofForge.Frontend.Surface

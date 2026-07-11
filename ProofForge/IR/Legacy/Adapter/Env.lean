import ProofForge.IR.Contract
import ProofForge.IR.Core.Id
import ProofForge.IR.Core.Type
import ProofForge.IR.Core.Storage
import ProofForge.IR.Core.Syntax
import ProofForge.IR.Core.Error
import Std

namespace ProofForge.IR.Legacy.Adapter

open ProofForge.IR
open ProofForge.IR.Core

/- Errors produced by the fail-closed legacy adapter. Every unsupported or
unclassified construct is reported explicitly; no wildcard fallback exists. -/

inductive CanonicalizeError
  | unclassifiedConstructor (nodeTag : String)
  | unclassifiedField (field : String)
  | unsupportedConstructor (nodeTag : String) (reason : String)
  | unknownState (name : String)
  | unknownFunction (name : String)
  | unknownEvent (name : String)
  | unknownType (name : String)
  | unboundLocal (name : String)
  | typeMismatch (expected : String) (actual : String)
  | literalOutOfRange (ty : String) (value : String)
  | invalidLValue (desc : String)
  | terminatedBlock (desc : String)
  | unboundedLoop (reason : String)
  | other (msg : String)
  deriving Repr, BEq

/- Resolved symbol tables and identifier supplies. State entries store the
logical `StateId` and `StateShape`; target slots are never recorded. Local
values are scoped per function and reset at function boundaries. -/

structure AdapterEnv where
  typeIds : Std.HashMap String TypeId
  stateIds : Std.HashMap String (StateId × StateShape)
  functionIds : Std.HashMap String FunctionId
  eventIds : Std.HashMap String EventId
  localValues : Std.HashMap String ValueRef
  nextTypeId : Nat
  nextStateId : Nat
  nextFunctionId : Nat
  nextEventId : Nat
  deriving Repr

structure AdapterState where
  env : AdapterEnv
  nextValueId : Nat
  nextBlockId : Nat
  deriving Repr

abbrev AdapterM := StateT AdapterState (Except CanonicalizeError)

def freshValueId : AdapterM ValueId := do
  let s ← get
  let id := s.nextValueId
  set { s with nextValueId := id + 1 }
  return ⟨id⟩

def freshBlockId : AdapterM BlockId := do
  let s ← get
  let id := s.nextBlockId
  set { s with nextBlockId := id + 1 }
  return ⟨id⟩

def freshTypeId : AdapterM TypeId := do
  let s ← get
  let id := s.env.nextTypeId
  modify (fun s => { s with env := { s.env with nextTypeId := id + 1 } })
  return ⟨id⟩

def freshStateId : AdapterM StateId := do
  let s ← get
  let id := s.env.nextStateId
  modify (fun s => { s with env := { s.env with nextStateId := id + 1 } })
  return ⟨id⟩

def freshFunctionId : AdapterM FunctionId := do
  let s ← get
  let id := s.env.nextFunctionId
  modify (fun s => { s with env := { s.env with nextFunctionId := id + 1 } })
  return ⟨id⟩

def freshEventId : AdapterM EventId := do
  let s ← get
  let id := s.env.nextEventId
  modify (fun s => { s with env := { s.env with nextEventId := id + 1 } })
  return ⟨id⟩

def lookupType (name : String) : AdapterM TypeId := do
  match Std.HashMap.get? (← get).env.typeIds name with
  | some id => return id
  | none => throw (CanonicalizeError.unknownType name)

def lookupState (name : String) : AdapterM StateId := do
  match Std.HashMap.get? (← get).env.stateIds name with
  | some (id, _) => return id
  | none => throw (CanonicalizeError.unknownState name)

def lookupStateShape (name : String) : AdapterM StateShape := do
  match Std.HashMap.get? (← get).env.stateIds name with
  | some (_, shape) => return shape
  | none => throw (CanonicalizeError.unknownState name)

def lookupFunction (name : String) : AdapterM FunctionId := do
  match Std.HashMap.get? (← get).env.functionIds name with
  | some id => return id
  | none => throw (CanonicalizeError.unknownFunction name)

def lookupEvent (name : String) : AdapterM EventId := do
  match Std.HashMap.get? (← get).env.eventIds name with
  | some id => return id
  | none => throw (CanonicalizeError.unknownEvent name)

def lookupLocal (name : String) : AdapterM ValueRef := do
  match Std.HashMap.get? (← get).env.localValues name with
  | some ref => return ref
  | none => throw (CanonicalizeError.unboundLocal name)

def bindLocal (name : String) (ref : ValueRef) : AdapterM Unit :=
  modify (fun s => { s with env := { s.env with localValues := s.env.localValues.insert name ref } })

def resetLocals : AdapterM Unit :=
  modify (fun s => { s with env := { s.env with localValues := {} } })

/- Map a legacy `ValueType` to the canonical `CoreType`. -/

def adaptType (t : ValueType) : Except CanonicalizeError CoreType :=
  match t with
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
  | .fixedArray e n => do .ok (.fixedArray (← adaptType e) n)
  | .structType n => .error (CanonicalizeError.unsupportedConstructor "ValueType.structType" s!"struct types not in initial fragment ({n})")
  | .array e => do .ok (.array (← adaptType e))

/- Map a legacy `StateDecl` to a canonical `StateShape`. The result is purely
logical; no target allocation information is introduced. -/

def adaptStateShape (decl : StateDecl) : Except CanonicalizeError StateShape :=
  match decl.kind with
  | .scalar => do .ok (.scalar (← adaptType decl.type))
  | .map keyType _ => do .ok (.map (← adaptType keyType) (← adaptType decl.type) none)
  | .array length => do .ok (.fixedArray (← adaptType decl.type) length)
  | .dynamicArray => do .ok (.dynamicArray (← adaptType decl.type))

private def pushEventName (names : Array String) (name : String) : Array String :=
  if names.contains name then names else names.push name

private def collectEventNamesStmt (stmt : Statement) (names : Array String) : Array String :=
  match stmt with
  | .effect (.eventEmit name _) => pushEventName names name
  | .effect (.eventEmitIndexed name _ _) => pushEventName names name
  | .ifElse _ thenBody elseBody =>
      let names := thenBody.foldl (fun acc nested => collectEventNamesStmt nested acc) names
      elseBody.foldl (fun acc nested => collectEventNamesStmt nested acc) names
  | .boundedFor _ _ _ body | .whileLoop _ body =>
      body.foldl (fun acc nested => collectEventNamesStmt nested acc) names
  | _ => names

private def collectEventNames (m : Module) : Array String :=
  m.entrypoints.foldl (fun names ep =>
    ep.body.foldl (fun acc stmt => collectEventNamesStmt stmt acc) names) #[]

/- Build a resolved adapter environment from a legacy `Module`. Identifiers are
assigned deterministically in declaration order. -/

def buildEnv (m : Module) : Except CanonicalizeError AdapterEnv := do
  let mut env : AdapterEnv := {
    typeIds := {},
    stateIds := {},
    functionIds := {},
    eventIds := {},
    localValues := {},
    nextTypeId := 0,
    nextStateId := 0,
    nextFunctionId := 0,
    nextEventId := 0
  }
  for struct in m.structs do
    let id := ⟨env.nextTypeId⟩
    env := { env with typeIds := env.typeIds.insert struct.name id, nextTypeId := env.nextTypeId + 1 }
  for state in m.state do
    let id := ⟨env.nextStateId⟩
    let shape ← adaptStateShape state
    env := { env with stateIds := env.stateIds.insert state.id (id, shape), nextStateId := env.nextStateId + 1 }
  for ep in m.entrypoints do
    let id := ⟨env.nextFunctionId⟩
    env := { env with functionIds := env.functionIds.insert ep.name id, nextFunctionId := env.nextFunctionId + 1 }
  for eventName in collectEventNames m do
    let id := ⟨env.nextEventId⟩
    env := {
      env with
      eventIds := env.eventIds.insert eventName id
      nextEventId := env.nextEventId + 1
    }
  return env

/- Convert a legacy `ContextField` to a canonical `ContextField`. Only the
fields used by the initial fragment are accepted. -/

def adaptContextField (field : ProofForge.IR.ContextField) : Except CanonicalizeError ProofForge.IR.Core.ContextField :=
  match field with
  | .userId => .ok .sender
  | .contractId => .ok .contractAddress
  | .checkpointId => .ok .blockNumber
  | .timestamp => .ok .blockTimestamp
  | other => .error (CanonicalizeError.unsupportedConstructor s!"ContextField.{other.name}" "context field not in initial fragment")

/- Result type of a canonical context read. -/

def contextFieldType (field : ProofForge.IR.Core.ContextField) : CoreType :=
  match field with
  | .sender | .contractAddress => .address
  | .value => .u128
  | .blockNumber | .blockTimestamp | .gas => .u64

/- Construct an empty `AdapterState` from an environment. -/

def AdapterState.ofEnv (env : AdapterEnv) : AdapterState := { env := env, nextValueId := 0, nextBlockId := 0 }

end ProofForge.IR.Legacy.Adapter

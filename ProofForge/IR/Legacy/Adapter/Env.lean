import ProofForge.IR.Contract
import ProofForge.IR.Core.Id
import ProofForge.IR.Core.Type
import ProofForge.IR.Core.Storage
import ProofForge.IR.Core.Syntax
import ProofForge.IR.Core.Error
import ProofForge.Target.HostOps.Evm
import ProofForge.Target.HostOps.Near
import Std

namespace ProofForge.IR.Legacy.Adapter

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.IR.Core.Error

/- Errors produced by the fail-closed legacy adapter. Every unsupported or
unclassified construct is reported explicitly; no wildcard fallback exists. -/

inductive CanonicalizeError
  | unclassifiedConstructor (nodeTag : String)
  | unclassifiedField (field : String)
  | unsupportedConstructor (nodeTag : String) (reason : String)
  | unknownState (name : String)
  | unknownFunction (name : String)
  | unknownEvent (name : String)
  | conflictingEventSchema (name : String) (reason : String)
  | conflictingErrorSchema (name : String) (reason : String)
  | unknownType (name : String)
  | unboundLocal (name : String)
  | typeMismatch (expected : String) (actual : String)
  | literalOutOfRange (ty : String) (value : String)
  | invalidLValue (desc : String)
  | terminatedBlock (desc : String)
  | unboundedLoop (reason : String)
  | validation (error : ValidationError)
  | other (msg : String)
  deriving Repr, BEq

inductive RegisteredErrorForm where
  | assertFallback
  | revertMessage
  | proofForgeEnvelope
  | solidityCustom
  deriving Repr, BEq

/-- Complete source error site retained until the canonical interface and
materialization envelopes are assembled. `coreName` is unique even when the
same source-facing custom error is used with different static argument words. -/
structure RegisteredError where
  id : ErrorId
  namespace_ : String
  coreName : String
  name : String
  userCode? : Option String
  code : Nat
  message : String
  form : RegisteredErrorForm
  soliditySelector? : Option String
  solidityArgWords : Array Nat
  solidityArgTypes : Array String
  params : Array CoreType
  deriving Repr, BEq

/- Resolved symbol tables and identifier supplies. State entries store the
logical `StateId` and `StateShape`; target slots are never recorded. Local
values are scoped per function and reset at function boundaries. -/

structure AdapterEnv where
  typeIds : Std.HashMap String TypeId
  stateIds : Std.HashMap String (StateId × StateShape)
  functionIds : Std.HashMap String FunctionId
  eventIds : Std.HashMap String EventId
  errorDecls : Array ErrorDecl
  registeredErrors : Array RegisteredError
  overflowMode : OverflowMode
  crosscallStrings : Array String
  localValues : Std.HashMap String ValueRef
  localArrays : Std.HashMap String (Array ValueRef)
  nextTypeId : Nat
  nextStateId : Nat
  nextFunctionId : Nat
  nextEventId : Nat
  nextErrorId : Nat
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

def freshErrorId : AdapterM ErrorId := do
  let s ← get
  let id := s.env.nextErrorId
  modify (fun s => { s with env := { s.env with nextErrorId := id + 1 } })
  return ⟨id⟩

def registerError (namespace_ name : String) (userCode? : Option String)
    (code : Nat) (message : String) (form : RegisteredErrorForm)
    (soliditySelector? : Option String := none)
    (solidityArgWords : Array Nat := #[])
    (solidityArgTypes : Array String := #[])
    (params : Array CoreType := #[]) : AdapterM ErrorId := do
  let s ← get
  match s.env.registeredErrors.find? (fun error =>
      error.namespace_ == namespace_ && error.name == name &&
      error.userCode? == userCode? && error.code == code &&
      error.message == message && error.form == form &&
      error.soliditySelector? == soliditySelector? &&
      error.solidityArgWords == solidityArgWords &&
      error.solidityArgTypes == solidityArgTypes && error.params == params) with
  | some error => return error.id
  | none =>
    let id ← freshErrorId
    let coreName := s!"{name}#{id.value}"
    modify (fun s => { s with
      env := { s.env with
        errorDecls := s.env.errorDecls.push {
          id := id,
          namespace_ := namespace_,
          name := coreName,
          code := code,
          params := params
        },
        registeredErrors := s.env.registeredErrors.push {
          id := id,
          namespace_ := namespace_,
          coreName := coreName,
          name := name,
          userCode? := userCode?,
          code := code,
          message := message,
          form := form,
          soliditySelector? := soliditySelector?,
          solidityArgWords := solidityArgWords,
          solidityArgTypes := solidityArgTypes,
          params := params
        }
      }
    })
    return id

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

def bindLocalArray (name : String) (values : Array ValueRef) : AdapterM Unit :=
  modify (fun s => { s with env := { s.env with localArrays := s.env.localArrays.insert name values } })

def lookupLocalArray (name : String) : AdapterM (Array ValueRef) := do
  match Std.HashMap.get? (← get).env.localArrays name with
  | some values => return values
  | none => throw (CanonicalizeError.unboundLocal name)

def resetLocals : AdapterM Unit :=
  modify (fun s => { s with env := { s.env with localValues := {}, localArrays := {} } })

/- Map a legacy `ValueType` to the canonical `CoreType`. -/

def adaptType (typeIds : Std.HashMap String TypeId) (t : ValueType) :
    Except CanonicalizeError CoreType :=
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
  | .fixedArray e n => do .ok (.fixedArray (← adaptType typeIds e) n)
  | .structType name =>
      match Std.HashMap.get? typeIds name with
      | some typeId => .ok (.structType typeId)
      | none => .error (CanonicalizeError.unknownType name)
  | .array e => do .ok (.array (← adaptType typeIds e))

/- Map a legacy `StateDecl` to a canonical `StateShape`. The result is purely
logical; no target allocation information is introduced. -/

def adaptStateShape (typeIds : Std.HashMap String TypeId) (decl : StateDecl) :
    Except CanonicalizeError StateShape :=
  match decl.kind with
  | .scalar => do .ok (.scalar (← adaptType typeIds decl.type))
  | .map keyType capacity => do
      if decl.keyPathTypes.isEmpty then
        .ok (.map (← adaptType typeIds keyType)
          (← adaptType typeIds decl.type) (some capacity))
      else
        .ok (.mapN (← decl.keyPathTypes.mapM (adaptType typeIds))
          (← adaptType typeIds decl.type) (some capacity))
  | .array length => do .ok (.fixedArray (← adaptType typeIds decl.type) length)
  | .dynamicArray => do .ok (.dynamicArray (← adaptType typeIds decl.type))

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
    errorDecls := #[],
    registeredErrors := #[],
    overflowMode := if m.overflowChecked then .checked else .wrapping,
    crosscallStrings := m.crosscallStrings,
    localValues := {},
    localArrays := {},
    nextTypeId := 0,
    nextStateId := 0,
    nextFunctionId := 0,
    nextEventId := 0,
    nextErrorId := 0
  }
  for struct in m.structs do
    let id := ⟨env.nextTypeId⟩
    env := { env with typeIds := env.typeIds.insert struct.name id, nextTypeId := env.nextTypeId + 1 }
  for state in m.state do
    let id := ⟨env.nextStateId⟩
    let shape ← adaptStateShape env.typeIds state
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

inductive AdaptedContextRead where
  | portable (field : ProofForge.IR.Core.ContextField) (type : CoreType)
  | host (id : ProofForge.Target.HostOpId) (type : CoreType)
  deriving Repr

def adaptContextRead (field : ProofForge.IR.ContextField) :
    Except CanonicalizeError AdaptedContextRead :=
  match field with
  | .userId => .ok (.portable .sender .address)
  | .contractId => .ok (.portable .contractAddress .address)
  | .checkpointId => .ok (.portable .blockNumber .u64)
  | .timestamp => .ok (.portable .blockTimestamp .u64)
  | .gasLeft => .ok (.portable .gas .u64)
  | .signer => .ok (.portable .signer .address)
  | .epochHeight => .ok (.host ProofForge.Target.HostOps.Near.epochHeightSig.id .u64)
  | .randomSeed => .ok (.host ProofForge.Target.HostOps.Near.randomSeedSig.id .hash)
  | .accountId => .ok (.host ProofForge.Target.HostOps.Near.predecessorAccountIdSig.id .string)
  | .prepaidGas => .ok (.host ProofForge.Target.HostOps.Near.prepaidGasSig.id .u64)
  | .usedGas => .ok (.host ProofForge.Target.HostOps.Near.usedGasSig.id .u64)
  | other => .error (CanonicalizeError.unsupportedConstructor
      s!"ContextField.{other.name}" "context field not in canonical compatibility fragment")

def adaptContextField (field : ProofForge.IR.ContextField) : Except CanonicalizeError ProofForge.IR.Core.ContextField :=
  match adaptContextRead field with
  | .ok (.portable coreField _) => .ok coreField
  | .ok (.host _ _) => .error (CanonicalizeError.unsupportedConstructor
      s!"ContextField.{field.name}" "target context must normalize through a HostOp")
  | .error error => .error error

/- Result type of a canonical context read. -/

def contextFieldType (field : ProofForge.IR.Core.ContextField) : CoreType :=
  match field with
  | .sender | .signer | .contractAddress => .address
  | .value => .u128
  | .blockNumber | .blockTimestamp | .gas => .u64

/- Construct an empty `AdapterState` from an environment. -/

def AdapterState.ofEnv (env : AdapterEnv) : AdapterState := { env := env, nextValueId := 0, nextBlockId := 0 }

end ProofForge.IR.Legacy.Adapter

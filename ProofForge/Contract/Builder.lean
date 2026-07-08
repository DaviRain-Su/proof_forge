import Init.Control.State
import ProofForge.Contract.Spec
import ProofForge.Target.Plan

namespace ProofForge.Contract.Builder

open ProofForge.IR
open ProofForge.Target

structure ModuleBuilder where
  name : String
  structs : Array StructDecl := #[]
  state : Array StateDecl := #[]
  entrypoints : Array Entrypoint := #[]
  nearCrosscallStrings : Array String := #[]
  intents : Array Intent := #[]
  evmConstructorParams : Array ProofForge.Contract.EvmConstructorParam := #[]
  evmConstructorInitBindings : Array ProofForge.Contract.EvmConstructorInitBinding := #[]
  upgradePolicy? : Option ProofForge.Contract.UpgradePolicy := none
  proxyPattern? : Option ProofForge.Contract.ProxyPattern := none
  quintInvariants : Array (String × String) := #[]
  quintLiveness : Array (String × String) := #[]
  deriving Repr

structure EntryBuilder where
  body : Array Statement := #[]
  intents : Array Intent := #[]
  deriving Repr

abbrev ModuleM := StateM ModuleBuilder
abbrev EntryM := StateM EntryBuilder

def ModuleBuilder.toModule (builder : ModuleBuilder) : Module := {
  name := builder.name
  structs := builder.structs
  state := builder.state
  entrypoints := builder.entrypoints
  nearCrosscallStrings := builder.nearCrosscallStrings
  evmProxyPattern? := builder.proxyPattern?.map ProofForge.Contract.ProxyPattern.kind
}

def ModuleBuilder.toSpec (builder : ModuleBuilder) : ContractSpec :=
  let module := builder.toModule
  {
    name := module.name
    module := module
    intents := intentsFromIR module ++ builder.intents
    upgradePolicy? := builder.upgradePolicy?
    proxyPattern? := builder.proxyPattern?
    evmConstructorParams := builder.evmConstructorParams
    evmConstructorInitBindings := builder.evmConstructorInitBindings
    quintInvariants := builder.quintInvariants
    quintLiveness := builder.quintLiveness
  }

def buildModule (name : String) (body : ModuleM Unit) : Module :=
  let (_, builder) := body.run { name := name }
  builder.toModule

def build (name : String) (body : ModuleM Unit) : ContractSpec :=
  let (_, builder) := body.run { name := name }
  builder.toSpec

def intent (intent : Intent) : ModuleM Unit := do
  modify fun builder => { builder with intents := builder.intents.push intent }

def capability (capability : Capability) (operation : String := capability.id)
    (source? : Option String := none) (metadata : Array TargetMetadata := #[]) : ModuleM Unit :=
  intent (Intent.capability capability operation source? metadata)

/-- Register a compile-time NEAR account/method string for `module.nearCrosscallStrings`. -/
def nearCrosscallString (value : String) : ModuleM Nat := do
  let builder ← get
  let idx := builder.nearCrosscallStrings.size
  modify fun b => { b with nearCrosscallStrings := b.nearCrosscallStrings.push value }
  pure idx

def entryIntent (intent : Intent) : EntryM Unit := do
  modify fun builder => { builder with intents := builder.intents.push intent }

def entryCapability (capability : Capability) (operation : String := capability.id)
    (source? : Option String := none) (metadata : Array TargetMetadata := #[]) : EntryM Unit :=
  entryIntent (Intent.capability capability operation source? metadata)

def entrypointMetadata (name : String) : TargetMetadata := {
  key := "proof_forge.entrypoint"
  value := name
}

def scopeEntryIntent (entrypointName : String) (intent : Intent) : Intent := {
  intent with
  kind := .entrypoint
  metadata := intent.metadata.push (entrypointMetadata entrypointName)
}

def struct (decl : StructDecl) : ModuleM Unit := do
  modify fun builder => { builder with structs := builder.structs.push decl }

def state (id : String) (type : ValueType) (kind : StateKind := .scalar) : ModuleM Unit := do
  modify fun builder => { builder with state := builder.state.push { id, kind, type } }

def scalarState (id : String) (type : ValueType) : ModuleM Unit :=
  state id type .scalar

def constructorParam (name : String) (abiType : String) : ModuleM Unit := do
  modify fun builder =>
    { builder with
      evmConstructorParams := builder.evmConstructorParams.push { name, abiType }
    }

def constructorInitBinding
    (stateId paramName : String) (kind : ProofForge.Contract.EvmConstructorInitKind) : ModuleM Unit := do
  modify fun builder =>
    { builder with
      evmConstructorInitBindings :=
        builder.evmConstructorInitBindings.push { stateId, paramName, kind }
    }

def upgradePolicy (policy : ProofForge.Contract.UpgradePolicy) : ModuleM Unit := do
  modify fun builder => { builder with upgradePolicy? := some policy }

def proxyPattern (pattern : ProofForge.Contract.ProxyPattern) : ModuleM Unit := do
  modify fun builder => { builder with proxyPattern? := some pattern }

def quintInvariant (name expr : String) : ModuleM Unit := do
  modify fun builder => { builder with quintInvariants := builder.quintInvariants.push (name, expr) }

def quintLiveness (name expr : String) : ModuleM Unit := do
  modify fun builder => { builder with quintLiveness := builder.quintLiveness.push (name, expr) }

def mapState (id : String) (keyType type : ValueType) (capacity : Nat) : ModuleM Unit :=
  state id type (.map keyType capacity)

def arrayState (id : String) (type : ValueType) (length : Nat) : ModuleM Unit :=
  state id type (.array length)

def pushStmt (statement : Statement) : EntryM Unit := do
  modify fun builder => { builder with body := builder.body.push statement }

def entryFull (name : String) (selector? : Option String) (returns : ValueType)
    (params : Array (String × ValueType)) (paramEvmAbiWords : Array (Option String))
    (body : EntryM Unit) : ModuleM Unit := do
  let (_, entryBuilder) := body.run {}
  let entrypoint : Entrypoint := {
    name := name
    selector? := selector?
    params := params
    paramEvmAbiWords := paramEvmAbiWords
    returns := returns
    body := entryBuilder.body
  }
  let entryIntents := entryBuilder.intents.map (scopeEntryIntent name)
  modify fun builder => {
    builder with
    entrypoints := builder.entrypoints.push entrypoint
    intents := builder.intents ++ entryIntents
  }

def defaultParamEvmAbiWords (params : Array (String × ValueType)) : Array (Option String) :=
  params.map fun _ => none

def entry (name : String) (body : EntryM Unit) : ModuleM Unit :=
  entryFull name none .unit #[] #[] body

def entrySelector (name selector : String) (body : EntryM Unit) : ModuleM Unit :=
  entryFull name (some selector) .unit #[] #[] body

def entryReturns (name : String) (returns : ValueType) (body : EntryM Unit) : ModuleM Unit :=
  entryFull name none returns #[] #[] body

def entrySelectorReturns (name selector : String) (returns : ValueType) (body : EntryM Unit) : ModuleM Unit :=
  entryFull name (some selector) returns #[] #[] body

def entryWithParams (name : String) (params : Array (String × ValueType)) (returns : ValueType)
    (body : EntryM Unit) : ModuleM Unit :=
  entryFull name none returns params (defaultParamEvmAbiWords params) body

def entrySelectorWithParams (name selector : String) (params : Array (String × ValueType))
    (returns : ValueType) (body : EntryM Unit) : ModuleM Unit :=
  entryFull name (some selector) returns params (defaultParamEvmAbiWords params) body

def letBind (name : String) (type : ValueType) (value : Expr) : EntryM Unit :=
  pushStmt (.letBind name type value)

def letMutBind (name : String) (type : ValueType) (value : Expr) : EntryM Unit :=
  pushStmt (.letMutBind name type value)

def assign (target value : Expr) : EntryM Unit :=
  pushStmt (.assign target value)

def assignOp (target : Expr) (op : AssignOp) (value : Expr) : EntryM Unit :=
  pushStmt (.assignOp target op value)

def effect (effect : Effect) : EntryM Unit :=
  pushStmt (.effect effect)

def assert (condition : Expr) (message : String) (errorRef? : Option ProofForge.IR.ErrorRef := none) : EntryM Unit :=
  pushStmt (.assert condition message errorRef?)

def assertEq (lhs rhs : Expr) (message : String) (errorRef? : Option ProofForge.IR.ErrorRef := none) : EntryM Unit :=
  pushStmt (.assertEq lhs rhs message errorRef?)

def ifElse (condition : Expr) (thenBody elseBody : Array Statement) : EntryM Unit :=
  pushStmt (.ifElse condition thenBody elseBody)

def boundedFor (indexName : String) (start stopExclusive : Nat) (body : Array Statement) : EntryM Unit :=
  pushStmt (.boundedFor indexName start stopExclusive body)

def ret (value : Expr) : EntryM Unit :=
  pushStmt (.return value)

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def bool (value : Bool) : Expr :=
  .literal (.bool value)

def localVar (name : String) : Expr :=
  .local name

def storageScalarRead (stateId : String) : Expr :=
  .effect (.storageScalarRead stateId)

def storageScalarWrite (stateId : String) (value : Expr) : Effect :=
  .storageScalarWrite stateId value

def storageScalarAssignOp (stateId : String) (op : AssignOp) (value : Expr) : Effect :=
  .storageScalarAssignOp stateId op value

def storageMapContains (stateId : String) (key : Expr) : Expr :=
  .effect (.storageMapContains stateId key)

def storageMapGet (stateId : String) (key : Expr) : Expr :=
  .effect (.storageMapGet stateId key)

def storageMapInsert (stateId : String) (key value : Expr) : Effect :=
  .storageMapInsert stateId key value

def storageMapSet (stateId : String) (key value : Expr) : Effect :=
  .storageMapSet stateId key value

def storageArrayRead (stateId : String) (index : Expr) : Expr :=
  .effect (.storageArrayRead stateId index)

def storageArrayWrite (stateId : String) (index value : Expr) : Effect :=
  .storageArrayWrite stateId index value

def storageStructFieldRead (stateId fieldName : String) : Expr :=
  .effect (.storageStructFieldRead stateId fieldName)

def storageStructFieldWrite (stateId fieldName : String) (value : Expr) : Effect :=
  .storageStructFieldWrite stateId fieldName value

def contextRead (field : ContextField) : Expr :=
  .effect (.contextRead field)

def eventEmit (name : String) (fields : Array (String × Expr)) : Effect :=
  .eventEmit name fields

def add (lhs rhs : Expr) (overflowChecked : Bool := true) : Expr :=
  .add lhs rhs overflowChecked

def sub (lhs rhs : Expr) (overflowChecked : Bool := true) : Expr :=
  .sub lhs rhs overflowChecked

def mul (lhs rhs : Expr) (overflowChecked : Bool := true) : Expr :=
  .mul lhs rhs overflowChecked

def div (lhs rhs : Expr) : Expr :=
  .div lhs rhs

def mod (lhs rhs : Expr) : Expr :=
  .mod lhs rhs

def eq (lhs rhs : Expr) : Expr :=
  .eq lhs rhs

def ne (lhs rhs : Expr) : Expr :=
  .ne lhs rhs

def lt (lhs rhs : Expr) : Expr :=
  .lt lhs rhs

def le (lhs rhs : Expr) : Expr :=
  .le lhs rhs

def gt (lhs rhs : Expr) : Expr :=
  .gt lhs rhs

def ge (lhs rhs : Expr) : Expr :=
  .ge lhs rhs

def boolAnd (lhs rhs : Expr) : Expr :=
  .boolAnd lhs rhs

def boolOr (lhs rhs : Expr) : Expr :=
  .boolOr lhs rhs

def boolNot (value : Expr) : Expr :=
  .boolNot value

def cast (value : Expr) (target : ValueType) : Expr :=
  .cast value target

def nearCrosscallInvokePool (accountIndex methodId : Expr) (args : Array Expr) (deposit : Expr) : Expr :=
  .nearCrosscallInvokePool accountIndex methodId args deposit

def nearPromiseThen (parentPromise callbackMethod : Expr) (args : Array Expr) (deposit : Expr) : Expr :=
  .nearPromiseThen parentPromise callbackMethod args deposit

def nearPromiseResultU64 (index : Expr) : Expr :=
  .nearPromiseResultU64 index

def nearAddressLit (idx : Nat) : Expr :=
  .literal (.address idx)

end ProofForge.Contract.Builder

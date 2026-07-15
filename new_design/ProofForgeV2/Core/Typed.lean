import ProofForgeV2.Core.Source

namespace ProofForgeV2.Typed

open ProofForgeV2

/-- Declaration-order identity of a callable parameter. Parameter IDs are local
to their initializer or entry. -/
structure ParamId where
  value : Nat
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

/-- Declaration-order identity of a program state cell. -/
structure StateId where
  value : Nat
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

/-- A resolved value reference. Its type is retained so every expression is
self-typing without consulting source names. -/
inductive ValueRef where
  | param (id : ParamId) (type : Source.ValueType)
  | state (id : StateId) (type : Source.ValueType)
  deriving BEq, Inhabited, Repr

namespace ValueRef

def type : ValueRef → Source.ValueType
  | .param _ type | .state _ type => type

end ValueRef

/-- Typed source expression. `checkedAdd` is accepted only for two UInt64
operands, so its result type is always UInt64. -/
inductive Expr where
  | literal (value : UInt64)
  | ref (value : ValueRef)
  | checkedAdd (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

namespace Expr

def type : Expr → Source.ValueType
  | .literal .. | .checkedAdd .. => .u64
  | .ref value => value.type

end Expr

inductive Statement where
  | assign (state : StateId) (value : Expr)
  | returnValue (value : Expr)
  | synchronousCall (callee : String)
  deriving BEq, Inhabited, Repr

structure Param where
  id : ParamId
  name : String
  type : Source.ValueType
  visibility : Source.Visibility
  deriving BEq, Inhabited, Repr

structure StateDecl where
  id : StateId
  name : String
  type : Source.ValueType
  deriving BEq, Inhabited, Repr

structure Initializer where
  params : Array Param
  body : Array Statement
  deriving BEq, Inhabited, Repr

inductive EntryMode where
  | mutate
  | view
  deriving BEq, Inhabited, Repr

structure Entry where
  name : String
  params : Array Param
  result : Source.ValueType
  mode : EntryMode
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Name-resolved, type-checked program. It has no target identity and contains
no unresolved source references. -/
structure Program where
  qualifiedName : String
  name : String
  state : Array StateDecl
  initializer : Option Initializer
  entries : Array Entry
  deriving BEq, Inhabited, Repr

private def invalid (message : String) : CompileResult α :=
  .error (.invalidProgram message)

private def duplicateName? (names : Array String) : Option String := Id.run do
  let mut found : Array String := #[]
  for name in names do
    if found.contains name then
      return some name
    found := found.push name
  return none

private def checkDistinct (kind owner : String) (names : Array String) : CompileResult Unit :=
  match duplicateName? names with
  | none => .ok ()
  | some name => invalid s!"duplicate {kind} '{name}' in {owner}"

private def resolveParams (owner : String) (params : Array Source.Param) : CompileResult (Array Param) := do
  checkDistinct "parameter" owner (params.map (·.name))
  return params.mapIdx fun index param => {
    id := ⟨index⟩
    name := param.name
    type := param.type
    visibility := param.visibility
  }

private structure Scope where
  owner : String
  state : Array StateDecl
  params : Array Param

private def Scope.findParam? (scope : Scope) (name : String) : Option Param :=
  scope.params.find? (·.name == name)

private def Scope.findState? (scope : Scope) (name : String) : Option StateDecl :=
  scope.state.find? (·.name == name)

private partial def checkExpr (scope : Scope) : Source.Expr → CompileResult Expr
  | .literal value => .ok (.literal value)
  | .variable name =>
      match scope.findParam? name with
      | some param => .ok (.ref (.param param.id param.type))
      | none =>
          match scope.findState? name with
          | some state => .ok (.ref (.state state.id state.type))
          | none => invalid s!"unknown value '{name}' in {scope.owner}"
  | .state name =>
      match scope.findState? name with
      | some state => .ok (.ref (.state state.id state.type))
      | none => invalid s!"unknown state '{name}' in {scope.owner}"
  | .checkedAdd lhs rhs => do
      let lhs ← checkExpr scope lhs
      let rhs ← checkExpr scope rhs
      unless lhs.type == .u64 && rhs.type == .u64 do
        throw <| .invalidProgram s!"checked addition in {scope.owner} requires two UInt64 operands"
      return .checkedAdd lhs rhs

private def checkStatement (scope : Scope) (mode : EntryMode) :
    Source.Statement → CompileResult Statement
  | .assign stateName value => do
      if mode == .view then
        throw <| .invalidProgram s!"view '{scope.owner}' cannot write state '{stateName}'"
      let state ← match scope.findState? stateName with
        | some state => pure state
        | none => invalid (s!"assignment target '{stateName}' in {scope.owner} is not declared state")
      let value ← checkExpr scope value
      unless value.type == state.type do
        throw <| .invalidProgram s!"assignment to state '{stateName}' in {scope.owner} has a type mismatch"
      return .assign state.id value
  | .returnValue value => .returnValue <$> checkExpr scope value
  | .synchronousCall callee =>
      if mode == .view then
        invalid s!"view '{scope.owner}' cannot perform synchronous call '{callee}'"
      else if callee.isEmpty then
        invalid s!"synchronous call target in {scope.owner} cannot be empty"
      else
        .ok (.synchronousCall callee)

private def checkInitializer (state : Array StateDecl)
    (initializer : Source.Initializer) : CompileResult Initializer := do
  let params ← resolveParams "initializer" initializer.params
  let scope : Scope := { owner := "initializer", state, params }
  let mut body : Array Statement := #[]
  for statement in initializer.body do
    match statement with
    | .returnValue .. =>
        throw <| .invalidProgram "initializer cannot return a value"
    | _ => body := body.push (← checkStatement scope .mutate statement)
  return { params, body }

private def adaptMode : Source.EntryMode → EntryMode
  | .mutate => .mutate
  | .view => .view

private def checkEntry (state : Array StateDecl) (entry : Source.Entry) : CompileResult Entry := do
  let owner := s!"entry '{entry.name}'"
  let params ← resolveParams owner entry.params
  let mode := adaptMode entry.mode
  let scope : Scope := { owner := entry.name, state, params }
  let mut body : Array Statement := #[]
  let mut returned := false
  for statement in entry.body do
    if returned then
      throw <| .invalidProgram s!"{owner} contains a statement after return"
    let checked ← checkStatement scope mode statement
    match checked with
    | .returnValue value =>
        unless value.type == entry.result do
          throw <| .invalidProgram s!"{owner} return type does not match its declaration"
        returned := true
    | _ => pure ()
    body := body.push checked
  unless returned do
    throw <| .invalidProgram s!"{owner} is missing a return value"
  return { name := entry.name, params, result := entry.result, mode, body }

/-- Resolve source names and enforce the minimum Phase-1 type/effect rules.
No requirement is trusted from `Source.Program`; requirements are derived later
from the checked Semantic IR. -/
def check (source : Source.Program) : CompileResult Program := do
  if source.qualifiedName.isEmpty then
    throw <| .invalidProgram "program qualified identity cannot be empty"
  if source.name.isEmpty then
    throw <| .invalidProgram "program name cannot be empty"
  checkDistinct "state declaration" s!"program '{source.qualifiedName}'"
    (source.state.map (·.name))
  checkDistinct "entry declaration" s!"program '{source.qualifiedName}'"
    (source.entries.map (·.name))
  if source.entries.isEmpty then
    throw <| .invalidProgram s!"program '{source.qualifiedName}' must declare at least one entry or view"
  let state := source.state.mapIdx fun index declaration => {
    id := ⟨index⟩
    name := declaration.name
    type := declaration.type
  }
  let initializer ← source.initializer.mapM (checkInitializer state)
  let entries ← source.entries.mapM (checkEntry state)
  return {
    qualifiedName := source.qualifiedName
    name := source.name
    state
    initializer
    entries
  }

end ProofForgeV2.Typed

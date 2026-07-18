import ProofForgeV2.Core.Source
import Std.Data.HashMap
import Std.Data.HashSet

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
  visibility : Source.Visibility := .verifierVisible
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

namespace NameIndex

/-- Internal alpha name environment. `ordered` is the only source of typed
state output; `byName` is an ephemeral lookup index shared by all callables. -/
structure StateEnv where
  ordered : Array StateDecl
  byName : Std.HashMap String StateDecl

/-- Internal alpha parameter environment local to one callable. -/
structure ParamEnv where
  ordered : Array Param
  byName : Std.HashMap String Param

/-- Build the declaration-order state output and its lookup index in one pass. -/
def resolveState (owner : String) (declarations : Array Source.StateDecl) :
    CompileResult StateEnv := do
  let mut ordered : Array StateDecl := #[]
  let mut byName := Std.HashMap.emptyWithCapacity declarations.size
  for declaration in declarations do
    let state : StateDecl := {
      id := ⟨ordered.size⟩
      name := declaration.name
      type := declaration.type
      visibility := declaration.visibility
    }
    let (existing, updated) := byName.getThenInsertIfNew? declaration.name state
    if existing.isSome then
      throw <| .invalidProgram s!"duplicate state declaration '{declaration.name}' in {owner}"
    byName := updated
    ordered := ordered.push state
  return { ordered, byName }

/-- Reject the first repeated entry name without using the set as output. -/
def checkDistinctEntries (owner : String) (entries : Array Source.Entry) :
    CompileResult Unit := do
  let mut names := Std.HashSet.emptyWithCapacity entries.size
  for entry in entries do
    let (alreadyPresent, updated) := names.containsThenInsert entry.name
    if alreadyPresent then
      throw <| .invalidProgram s!"duplicate entry declaration '{entry.name}' in {owner}"
    names := updated

/-- Build one callable's declaration-order parameter output and lookup index. -/
def resolveParams (owner : String) (params : Array Source.Param) :
    CompileResult ParamEnv := do
  let mut ordered : Array Param := #[]
  let mut byName := Std.HashMap.emptyWithCapacity params.size
  for sourceParam in params do
    let param : Param := {
      id := ⟨ordered.size⟩
      name := sourceParam.name
      type := sourceParam.type
      visibility := sourceParam.visibility
    }
    let (existing, updated) := byName.getThenInsertIfNew? sourceParam.name param
    if existing.isSome then
      throw <| .invalidProgram s!"duplicate parameter '{sourceParam.name}' in {owner}"
    byName := updated
    ordered := ordered.push param
  return { ordered, byName }

end NameIndex

private structure Scope where
  owner : String
  stateByName : Std.HashMap String StateDecl
  paramByName : Std.HashMap String Param

private def Scope.findParam? (scope : Scope) (name : String) : Option Param :=
  scope.paramByName.get? name

private def Scope.findState? (scope : Scope) (name : String) : Option StateDecl :=
  scope.stateByName.get? name

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
  | .boolLiteral .. =>
      throw <| .invalidProgram "boolean literals are not yet supported by typed checking"
  | .checkedSub .. =>
      throw <| .invalidProgram "checked subtraction is not yet supported by typed checking"
  | .checkedMul .. =>
      throw <| .invalidProgram "checked multiplication is not yet supported by typed checking"
  | .checkedNeg .. =>
      throw <| .invalidProgram "checked negation is not yet supported by typed checking"
  | .bitwiseNot .. =>
      throw <| .invalidProgram "bitwise not is not yet supported by typed checking"
  | .logicalNot .. =>
      throw <| .invalidProgram "logical not is not yet supported by typed checking"
  | .checkedDiv .. =>
      throw <| .invalidProgram "checked division is not yet supported by typed checking"
  | .checkedMod .. =>
      throw <| .invalidProgram "checked modulo is not yet supported by typed checking"
  | .shiftLeft .. =>
      throw <| .invalidProgram "shift left is not yet supported by typed checking"
  | .shiftRight .. =>
      throw <| .invalidProgram "shift right is not yet supported by typed checking"
  | .equal .. =>
      throw <| .invalidProgram "equality is not yet supported by typed checking"
  | .notEqual .. =>
      throw <| .invalidProgram "not-equal comparison is not yet supported by typed checking"
  | .lessThan .. =>
      throw <| .invalidProgram "less-than comparison is not yet supported by typed checking"
  | .lessEqual .. =>
      throw <| .invalidProgram "less-equal comparison is not yet supported by typed checking"
  | .greaterThan .. =>
      throw <| .invalidProgram "greater-than comparison is not yet supported by typed checking"
  | .greaterEqual .. =>
      throw <| .invalidProgram "greater-equal comparison is not yet supported by typed checking"
  | .bitwiseAnd .. =>
      throw <| .invalidProgram "bitwise and is not yet supported by typed checking"

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
  | .letDecl .. =>
      throw <| .invalidProgram "let statements are not yet supported by typed checking"
  | .assertStmt .. =>
      throw <| .invalidProgram "assert statements are not yet supported by typed checking"

private def checkInitializer (state : NameIndex.StateEnv)
    (initializer : Source.Initializer) : CompileResult Initializer := do
  let params ← NameIndex.resolveParams "initializer" initializer.params
  let scope : Scope := {
    owner := "initializer"
    stateByName := state.byName
    paramByName := params.byName
  }
  let mut body : Array Statement := #[]
  for statement in initializer.body do
    match statement with
    | .returnValue .. =>
        throw <| .invalidProgram "initializer cannot return a value"
    | _ => body := body.push (← checkStatement scope .mutate statement)
  return { params := params.ordered, body }

private def adaptMode : Source.EntryMode → EntryMode
  | .mutate => .mutate
  | .view => .view

private def checkEntry (state : NameIndex.StateEnv) (entry : Source.Entry) : CompileResult Entry := do
  let owner := s!"entry '{entry.name}'"
  let params ← NameIndex.resolveParams owner entry.params
  let mode := adaptMode entry.mode
  let scope : Scope := {
    owner := entry.name
    stateByName := state.byName
    paramByName := params.byName
  }
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
  return { name := entry.name, params := params.ordered, result := entry.result, mode, body }

/-- Resolve source names and enforce the minimum Phase-1 type/effect rules.
No requirement is trusted from `Source.Program`; requirements are derived later
from the checked Semantic IR. -/
def check (source : Source.Program) : CompileResult Program := do
  if source.qualifiedName.isEmpty then
    throw <| .invalidProgram "program qualified identity cannot be empty"
  if source.name.isEmpty then
    throw <| .invalidProgram "program name cannot be empty"
  if !source.structs.isEmpty then
    throw <| .invalidProgram "struct declarations are not yet supported by typed checking"
  if !source.enums.isEmpty then
    throw <| .invalidProgram "enum declarations are not yet supported by typed checking"
  if !source.consts.isEmpty then
    throw <| .invalidProgram "const declarations are not yet supported by typed checking"
  if !source.events.isEmpty then
    throw <| .invalidProgram "event declarations are not yet supported by typed checking"
  if !source.errors.isEmpty then
    throw <| .invalidProgram "error declarations are not yet supported by typed checking"
  if !source.functions.isEmpty then
    throw <| .invalidProgram "fn declarations are not yet supported by typed checking"
  if !source.invariants.isEmpty then
    throw <| .invalidProgram "invariant declarations are not yet supported by typed checking"
  if !source.extensionRequirements.isEmpty then
    throw <| .invalidProgram
      "extension requirements are not yet supported by typed checking"
  if !source.proofReferences.isEmpty then
    throw <| .invalidProgram
      "proof references are not yet supported by typed checking"
  let owner := s!"program '{source.qualifiedName}'"
  let state ← NameIndex.resolveState owner source.state
  NameIndex.checkDistinctEntries owner source.entries
  if source.entries.isEmpty then
    throw <| .invalidProgram s!"program '{source.qualifiedName}' must declare at least one entry or view"
  let initializer ← source.initializer.mapM (checkInitializer state)
  let entries ← source.entries.mapM (checkEntry state)
  return {
    qualifiedName := source.qualifiedName
    name := source.name
    state := state.ordered
    initializer
    entries
  }

end ProofForgeV2.Typed

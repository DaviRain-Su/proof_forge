import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.ModelV1

namespace ProofForgeV2.Typed.NameResolutionV1

open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1

structure ResolutionState where
  diagnostics : Array DiagnosticV1

abbrev M := StateM ResolutionState

def emit (diag : DiagnosticV1) : M Unit :=
  modify fun s => { s with diagnostics := s.diagnostics.push diag }

structure Scope where
  locals : List SourceNameComponentV1
  params : Array SourceNameComponentV1

/-- Return the declaration kind (and its smallest source-order ordinal) that
    contains `name`, preferring the earliest ordinal across all named tables. -/
def findFirstMatchingKind (tables : TypedDeclTablesV1) (name : SourceNameComponentV1) :
    Option (DeclKindV1 × Nat) :=
  let candidates : List (DeclKindV1 × Option Nat) := [
    (.state, tables.state.find? name |>.map (·.1)),
    (.struct, tables.struct.find? name |>.map (·.1)),
    (.enum, tables.enum.find? name |>.map (·.1)),
    (.const, tables.const.find? name |>.map (·.1)),
    (.event, tables.event.find? name |>.map (·.1)),
    (.error, tables.error.find? name |>.map (·.1)),
    (.entry, tables.entry.find? name |>.map (·.1)),
    (.view, tables.view.find? name |>.map (·.1)),
    (.fn, tables.fn.find? name |>.map (·.1)),
    (.invariant, tables.invariant.find? name |>.map (·.1)),
    (.proof, tables.proof.find? name |>.map (·.1))
  ]
  let found := candidates.filterMap fun (kind, opt) => opt.map (fun o => (kind, o))
  found.foldl (init := (none : Option (DeclKindV1 × Nat))) fun best entry =>
    match best with
    | none => some entry
    | some (k, o) =>
        if entry.2 < o then some entry else some (k, o)

def resolveConstructorName (tables : TypedDeclTablesV1) (ctor : SourceQualifiedNameV1) :
    M Unit := do
  let comps := NonEmptyArray.toArray ctor.components
  match comps with
  | #[name] =>
      if tables.struct.find? name |>.isSome then
        pure ()
      else
        let variantCount := tables.enum.toArray.foldl (fun acc (_, _, enumDecl) =>
          if enumDecl.variants.any (·.name == name) then acc + 1 else acc) 0
        if variantCount == 1 then
          pure ()
        else if variantCount > 1 then
          emit (ambiguousNameDiagnostic name "constructor")
        else
          match findFirstMatchingKind tables name with
          | some (kind, _) => emit (wrongCategoryDiagnostic name kind "constructor")
          | none => emit (unknownNameDiagnostic name "constructor")
  | #[enumName, variantName] =>
      match tables.enum.find? enumName with
      | some p =>
          let enumDecl := p.2
          if enumDecl.variants.any (·.name == variantName) then
            pure ()
          else
            emit (unknownNameDiagnostic variantName "constructor variant")
      | none =>
          match findFirstMatchingKind tables enumName with
          | some (kind, _) => emit (wrongCategoryDiagnostic enumName kind "constructor")
          | none => emit (unknownNameDiagnostic enumName "constructor enum")
  | _ =>
      emit (unknownQualifiedNameDiagnostic ctor "constructor")

def resolveValueName (tables : TypedDeclTablesV1) (scope : Scope)
    (name : SourceNameComponentV1) : M Unit :=
  if scope.locals.contains name then pure ()
  else if scope.params.contains name then pure ()
  else
    let inState := tables.state.find? name |>.isSome
    let inConst := tables.const.find? name |>.isSome
    if inState && inConst then emit (ambiguousNameDiagnostic name "value")
    else if inState || inConst then pure ()
    else emit (unknownNameDiagnostic name "value")

partial def resolvePattern (tables : TypedDeclTablesV1) : PatternV1 → M (List SourceNameComponentV1)
  | .wildcard | .literal _ => pure []
  | .bind name => pure [name]
  | .constructor ctor args => do
      resolveConstructorName tables ctor
      args.foldlM (fun acc p => do
        let bs ← resolvePattern tables p
        pure (acc ++ bs)) []

partial def resolveType (tables : TypedDeclTablesV1) : TypeV1 → M Unit
  | .named name => do
      let struct? := tables.struct.find? name
      let enum? := tables.enum.find? name
      match struct?, enum? with
      | some _, some _ => emit (ambiguousNameDiagnostic name "type")
      | some _, none | none, some _ => pure ()
      | none, none =>
          match findFirstMatchingKind tables name with
          | some (kind, _) => emit (wrongCategoryDiagnostic name kind "type")
          | none => emit (unknownNameDiagnostic name "type")
  | .array elem _ => resolveType tables elem
  | .map key value => do
      resolveType tables key
      resolveType tables value
  | .option elem => resolveType tables elem
  | _ => pure ()

def resolveLocalCall (tables : TypedDeclTablesV1) (scope : Scope)
    (callee : SourceNameComponentV1) : M Unit := do
  if scope.locals.contains callee then
    emit (localAsFunctionDiagnostic callee "local")
  else if scope.params.contains callee then
    emit (localAsFunctionDiagnostic callee "parameter")
  else if tables.fn.find? callee |>.isSome then pure ()
  else
    match findFirstMatchingKind tables callee with
    | some (kind, _) => emit (wrongCategoryDiagnostic callee kind "function")
    | none => emit (unknownNameDiagnostic callee "function")

mutual
  partial def resolvePlace (tables : TypedDeclTablesV1) (scope : Scope) :
      PlaceV1 → M Unit
    | .name n => resolveValueName tables scope n
    | .field base _ => resolvePlace tables scope base
    | .index base idx => do
        resolvePlace tables scope base
        resolveExpr tables scope idx

  partial def resolveExpr (tables : TypedDeclTablesV1) (scope : Scope) :
      ExprV1 → M Unit
    | .literal _ => pure ()
    | .place p => resolvePlace tables scope p
    | .constructor ctor args => do
        resolveConstructorName tables ctor
        args.forM (resolveExpr tables scope)
    | .unary _ e => resolveExpr tables scope e
    | .binary _ lhs rhs => do
        resolveExpr tables scope lhs
        resolveExpr tables scope rhs
    | .localCall callee args => do
        resolveLocalCall tables scope callee
        args.forM (resolveExpr tables scope)
    | .match_ scrutinee arms => do
        resolveExpr tables scope scrutinee
        for arm in arms do
          let binders ← resolvePattern tables arm.pattern
          resolveExpr tables { scope with locals := binders ++ scope.locals } arm.value

  partial def resolveBlock (tables : TypedDeclTablesV1) (scope : Scope)
      (block : BlockV1) : M Unit := do
    resolveStmts tables scope block.statements.toList

  partial def resolveStmts (tables : TypedDeclTablesV1) (scope : Scope) :
      List StmtV1 → M Unit
    | [] => pure ()
    | stmt :: rest => do
        let added ← resolveStmt tables scope stmt
        resolveStmts tables { scope with locals := added ++ scope.locals } rest

  partial def resolveStmt (tables : TypedDeclTablesV1) (scope : Scope) :
      StmtV1 → M (List SourceNameComponentV1)
    | .let_ name typeAnn value => do
        typeAnn.forM (resolveType tables)
        resolveExpr tables scope value
        pure [name]
    | .assign target value => do
        resolvePlace tables scope target
        resolveExpr tables scope value
        pure []
    | .if_ condition thenBlock elseBlock => do
        resolveExpr tables scope condition
        resolveBlock tables scope thenBlock
        elseBlock.forM (resolveBlock tables scope)
        pure []
    | .match_ scrutinee arms => do
        resolveExpr tables scope scrutinee
        for arm in arms do
          let binders ← resolvePattern tables arm.pattern
          resolveBlock tables { scope with locals := binders ++ scope.locals } arm.body
        pure []
    | .for_ binder start endExclusive _ body => do
        resolveExpr tables scope start
        resolveExpr tables scope endExclusive
        resolveBlock tables { scope with locals := binder :: scope.locals } body
        pure []
    | .assert_ condition error? => do
        resolveExpr tables scope condition
        error?.forM fun error => do
          if (tables.error.find? error |>.isNone) then
            emit (unknownNameDiagnostic error "error")
        pure []
    | .revert error args => do
        if (tables.error.find? error |>.isNone) then
          emit (unknownNameDiagnostic error "error")
        args.forM (resolveExpr tables scope)
        pure []
    | .emit event args => do
        if (tables.event.find? event |>.isNone) then
          emit (unknownNameDiagnostic event "event")
        args.forM (resolveExpr tables scope)
        pure []
    | .return_ value? => do
        value?.forM (resolveExpr tables scope)
        pure []
    | .call externalCall | .schedule externalCall => do
        externalCall.args.forM (resolveExpr tables scope)
        pure []
end

def mkBaseScope (params : Array ParamV1) : Scope :=
  { locals := [], params := params.map (·.name) }

def resolveItem (tables : TypedDeclTablesV1) (item : ProgramItemV1) : M Unit := do
  let baseScope := mkBaseScope #[]
  match item with
  | .state declaration =>
      resolveType tables declaration.type_
  | .struct declaration =>
      declaration.fields.forM fun field => do resolveType tables field.type_
  | .enum declaration =>
      declaration.variants.forM fun variant => do
        variant.payloadTypes.forM (resolveType tables)
  | .const declaration => do
      resolveType tables declaration.type_
      resolveExpr tables baseScope declaration.value
  | .event declaration =>
      declaration.params.forM fun param => do resolveType tables param.type_
  | .error declaration =>
      declaration.params.forM fun param => do resolveType tables param.type_
  | .init declaration => do
      declaration.params.forM fun param => do resolveType tables param.type_
      resolveBlock tables (mkBaseScope declaration.params) declaration.body
  | .entry declaration => do
      declaration.params.forM fun param => do resolveType tables param.type_
      resolveType tables declaration.result
      resolveBlock tables (mkBaseScope declaration.params) declaration.body
  | .view declaration => do
      declaration.params.forM fun param => do resolveType tables param.type_
      resolveType tables declaration.result
      resolveBlock tables (mkBaseScope declaration.params) declaration.body
  | .fn declaration => do
      declaration.params.forM fun param => do resolveType tables param.type_
      resolveType tables declaration.result
      resolveBlock tables (mkBaseScope declaration.params) declaration.body
  | .invariant declaration =>
      resolveExpr tables baseScope declaration.predicate
  | .extensionReq _ =>
      pure ()
  | .proof declaration =>
      if (tables.invariant.find? declaration.invariant |>.isSome) then
        pure ()
      else
        emit (unknownNameDiagnostic declaration.invariant "invariant")

def emptyTables : TypedDeclTablesV1 :=
  { state := .empty, struct := .empty, enum := .empty, const := .empty,
    event := .empty, error := .empty, init := .empty, entry := .empty,
    view := .empty, fn := .empty, invariant := .empty, extensionReq := .empty,
    proof := .empty }

def buildTables (program : ProgramV1) : M TypedDeclTablesV1 := do
  let mut tables := emptyTables
  for item in program.items do
    match item with
    | .state d =>
        if tables.state.find? d.name |>.isSome then
          emit (duplicateDeclarationDiagnostic d.name .state)
        else pure ()
        tables := { tables with state := tables.state.insert d.name tables.state.size d }
    | .struct d =>
        if tables.struct.find? d.name |>.isSome then
          emit (duplicateDeclarationDiagnostic d.name .struct)
        else pure ()
        tables := { tables with struct := tables.struct.insert d.name tables.struct.size d }
    | .enum d =>
        if tables.enum.find? d.name |>.isSome then
          emit (duplicateDeclarationDiagnostic d.name .enum)
        else pure ()
        tables := { tables with enum := tables.enum.insert d.name tables.enum.size d }
    | .const d =>
        if tables.const.find? d.name |>.isSome then
          emit (duplicateDeclarationDiagnostic d.name .const)
        else pure ()
        tables := { tables with const := tables.const.insert d.name tables.const.size d }
    | .event d =>
        if tables.event.find? d.name |>.isSome then
          emit (duplicateDeclarationDiagnostic d.name .event)
        else pure ()
        tables := { tables with event := tables.event.insert d.name tables.event.size d }
    | .error d =>
        if tables.error.find? d.name |>.isSome then
          emit (duplicateDeclarationDiagnostic d.name .error)
        else pure ()
        tables := { tables with error := tables.error.insert d.name tables.error.size d }
    | .init d =>
        if tables.init.size > 0 then
          emit duplicateInitDiagnostic
        else pure ()
        tables := { tables with init := tables.init.insert () tables.init.size d }
    | .entry d =>
        if tables.entry.find? d.name |>.isSome then
          emit (duplicateDeclarationDiagnostic d.name .entry)
        else pure ()
        tables := { tables with entry := tables.entry.insert d.name tables.entry.size d }
    | .view d =>
        if tables.view.find? d.name |>.isSome then
          emit (duplicateDeclarationDiagnostic d.name .view)
        else pure ()
        tables := { tables with view := tables.view.insert d.name tables.view.size d }
    | .fn d =>
        if tables.fn.find? d.name |>.isSome then
          emit (duplicateDeclarationDiagnostic d.name .fn)
        else pure ()
        tables := { tables with fn := tables.fn.insert d.name tables.fn.size d }
    | .invariant d =>
        if tables.invariant.find? d.name |>.isSome then
          emit (duplicateDeclarationDiagnostic d.name .invariant)
        else pure ()
        tables := { tables with invariant := tables.invariant.insert d.name tables.invariant.size d }
    | .extensionReq d =>
        if tables.extensionReq.find? d.id |>.isSome then
          emit (duplicateExtensionReqDiagnostic d.id)
        else pure ()
        tables := { tables with extensionReq := tables.extensionReq.insert d.id tables.extensionReq.size d }
    | .proof d =>
        if tables.proof.find? d.invariant |>.isSome then
          emit (duplicateDeclarationDiagnostic d.invariant .proof)
        else pure ()
        tables := { tables with proof := tables.proof.insert d.invariant tables.proof.size d }
  pure tables
/-- Resolve every in-scope name use in a validated ProgramV1 source unit.
    Builds source-order declaration tables, then walks init/entry/view/fn/invariant
    bodies and type annotations with explicit scope rules.  No type checking of
    expressions or effects is performed; unknown or wrong-category names fail
    closed with deterministic `DiagnosticV1` messages in source order. -/
def resolveProgramV1 (source : ValidatedSourceV1) : NameResolutionResultV1 :=
  let (tables, s1) := (buildTables source.program).run { diagnostics := #[] }
  let (_, s2) := (source.program.items.forM (resolveItem tables)).run s1
  { tables := tables,
    diagnostics := s2.diagnostics,
    ok := s2.diagnostics.isEmpty }

end ProofForgeV2.Typed.NameResolutionV1

/-
  ProofForgeV2.Typed.NameResolutionV1 — declaration tables + name resolution.

  B7b1: single path-threaded walk is the authority for resolution diagnostic
  drafts. Paths use only NodeTraversalV1 childPath helpers. Public
  `resolveProgramV1` erases drafts; additive `resolveProgramDraftsV1` exposes
  located drafts for tests/materialization through B7a.
-/
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.ContextCommitSurfaceV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import ProofForgeV2.Typed.DiagnosticDraftV1
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
open ProofForgeV2.Source.ContextCommitSurfaceV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Core.RequirementIdsV1

/-- Resolution walk state. `drafts` is the authority; `diagnostics` is the
    order-preserving erased projection kept in lockstep for public consumers
    that still construct/run `buildTables` with unlocated DiagnosticV1 arrays. -/
structure ResolutionState where
  diagnostics : Array DiagnosticV1 := #[]
  drafts : Array TypedDiagnosticDraftV1 := #[]

abbrev M := StateM ResolutionState

def emit (diag : TypedDiagnosticDraftV1) : M Unit :=
  modify fun s => {
    s with
    drafts := s.drafts.push diag
    diagnostics := s.diagnostics.push (erase diag)
  }

def emitLocated
    (base : TypedDiagnosticDraftV1)
    (primaryPath : NormalizedSyntacticPathV1)
    (relatedPaths : Array NormalizedSyntacticPathV1 := #[]) : M Unit :=
  emit (withPaths base primaryPath relatedPaths)

/-- Child path or internal fail-closed draft (no silent drop). -/
def childOrInternal
    (parent : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat) :
    M (Option NormalizedSyntacticPathV1) :=
  match childPathV1 parent parentTag fieldTag index with
  | .ok p => pure (some p)
  | .error detail => do
      emit (pathInternalDraft detail)
      pure none

def directOrInternal
    (parent : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) : M (Option NormalizedSyntacticPathV1) :=
  childOrInternal parent parentTag fieldTag 0

structure Scope where
  locals : List SourceNameComponentV1
  params : Array SourceNameComponentV1

private def firstProofOrdinalForInvariant?
    (table : DeclTableV1 ProofDeclKeyV1 ProofDeclV1)
    (name : SourceNameComponentV1) : Option Nat :=
  table.entries.findSome? fun (key, ordinal, _) =>
    if key.invariant == name then some ordinal else none

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
    (.proof, firstProofOrdinalForInvariant? tables.proof name)
  ]
  let found := candidates.filterMap fun (kind, opt) => opt.map (fun o => (kind, o))
  found.foldl (init := (none : Option (DeclKindV1 × Nat))) fun best entry =>
    match best with
    | none => some entry
    | some (k, o) =>
        if entry.2 < o then some entry else some (k, o)

def relatedPathForKindOrdinal (tables : TypedDeclTablesV1) (kind : DeclKindV1)
    (ordinal : Nat) : Array NormalizedSyntacticPathV1 :=
  match itemPathForOrdinal? tables kind ordinal with
  | some p => #[p]
  | none => #[]

def optPathArray (p? : Option NormalizedSyntacticPathV1) :
    Array NormalizedSyntacticPathV1 :=
  match p? with
  | some p => #[p]
  | none => #[]

def resolveConstructorName (tables : TypedDeclTablesV1)
    (sitePath : NormalizedSyntacticPathV1) (ctor : SourceQualifiedNameV1) :
    M Unit := do
  let comps := NonEmptyArray.toArray ctor.components
  match comps with
  | #[name] =>
      let structPresent := tables.struct.find? name |>.isSome
      let hasEnumVariant :=
        tables.enum.toArray.any fun (_, _, enumDecl) =>
          enumDecl.variants.any (·.name == name)
      if structPresent && hasEnumVariant then
        -- Related = struct decl(s) named `name` plus every enum whose variants
        -- contain `name` (source order). Do not look up EnumDecl named `name`.
        let related :=
          optPathArray (itemPathForNamed? tables .struct name) ++
          tables.enum.toArray.filterMap fun (_, o, enumDecl) =>
            if enumDecl.variants.any (·.name == name) then
              itemPathForOrdinal? tables .enum o
            else none
        emitLocated (ambiguousNameDiagnosticDraft name "constructor") sitePath related
      else if structPresent then
        pure ()
      else
        let variantCount := tables.enum.toArray.foldl (fun acc (_, _, enumDecl) =>
          if enumDecl.variants.any (·.name == name) then acc + 1 else acc) 0
        if variantCount == 1 then
          pure ()
        else if variantCount > 1 then
          let related :=
            tables.enum.toArray.filterMap fun (_, o, enumDecl) =>
              if enumDecl.variants.any (·.name == name) then
                itemPathForOrdinal? tables .enum o
              else none
          emitLocated (ambiguousNameDiagnosticDraft name "constructor") sitePath related
        else
          match findFirstMatchingKind tables name with
          | some (kind, ord) =>
              emitLocated (wrongCategoryDiagnosticDraft name kind "constructor")
                sitePath (relatedPathForKindOrdinal tables kind ord)
          | none =>
              emitLocated (unknownNameDiagnosticDraft name "constructor") sitePath #[]
  | #[typeName, methodOrVariant] =>
      -- Phase-1: StructName.new | EnumName.Variant | Option.some/none (N-A4)
      if methodOrVariant.raw == "new" then
        match tables.struct.find? typeName with
        | some _ => pure ()
        | none =>
            match findFirstMatchingKind tables typeName with
            | some (kind, ord) =>
                emitLocated (wrongCategoryDiagnosticDraft typeName kind "constructor")
                  sitePath (relatedPathForKindOrdinal tables kind ord)
            | none =>
                emitLocated (unknownNameDiagnosticDraft typeName "constructor struct")
                  sitePath #[]
      else if typeName.raw == "Option" then
        -- Built-in Option constructors (TypeCheck still requires Option expected type).
        let m := methodOrVariant.raw
        if m == "some" || m == "Some" || m == "none" || m == "None" then
          pure ()
        else
          emitLocated (unknownNameDiagnosticDraft methodOrVariant "constructor variant")
            sitePath #[]
      else if typeName.raw == "Map" then
        -- N-1: Map.empty(); N-MAP-CONSTRUCT: Map.of(k0, v0, ...) variadic.
        let m := methodOrVariant.raw
        if m == "empty" || m == "Empty" || m == "of" then
          pure ()
        else
          emitLocated (unknownNameDiagnosticDraft methodOrVariant "constructor variant")
            sitePath #[]
      else
        match tables.enum.find? typeName with
        | some p =>
            let enumDecl := p.2
            if enumDecl.variants.any (·.name == methodOrVariant) then
              pure ()
            else
              emitLocated (unknownNameDiagnosticDraft methodOrVariant "constructor variant")
                sitePath (relatedPathForKindOrdinal tables .enum p.1)
        | none =>
            match findFirstMatchingKind tables typeName with
            | some (kind, ord) =>
                emitLocated (wrongCategoryDiagnosticDraft typeName kind "constructor")
                  sitePath (relatedPathForKindOrdinal tables kind ord)
            | none =>
                emitLocated (unknownNameDiagnosticDraft typeName "constructor enum")
                  sitePath #[]
  | _ =>
      emitLocated (unknownQualifiedNameDiagnosticDraft ctor "constructor") sitePath #[]

def resolveValueName (tables : TypedDeclTablesV1) (scope : Scope)
    (sitePath : NormalizedSyntacticPathV1) (name : SourceNameComponentV1) : M Unit :=
  if scope.locals.contains name then pure ()
  else if scope.params.contains name then pure ()
  else
    let inState := tables.state.find? name |>.isSome
    let inConst := tables.const.find? name |>.isSome
    if inState && inConst then
      let related :=
        optPathArray (itemPathForNamed? tables .state name) ++
        optPathArray (itemPathForNamed? tables .const name)
      emitLocated (ambiguousNameDiagnosticDraft name "value") sitePath related
    else if inState || inConst then pure ()
    else
      emitLocated (unknownNameDiagnosticDraft name "value") sitePath #[]

def resolvePatternFuelV1 (tables : TypedDeclTablesV1)
    (patternPath : NormalizedSyntacticPathV1) :
    Nat → PatternV1 → M (List SourceNameComponentV1)
  | 0, _ => do
      emit (pathInternalDraft "name resolution exceeds the validated source node bound")
      pure []
  | _ + 1, .wildcard | _ + 1, .literal _ => pure []
  | _ + 1, .bind name => pure [name]
  | fuel + 1, .constructor ctor args => do
      resolveConstructorName tables patternPath ctor
      let mut acc : List SourceNameComponentV1 := []
      for (p, i) in args.zipIdx do
        match ← childOrInternal patternPath "Pattern.Constructor" "args" i with
        | none => pure ()
        | some ap =>
            let bs ← resolvePatternFuelV1 tables ap fuel p
            acc := acc ++ bs
      pure acc

/-- Total production pattern resolver. Validated source traversal admits at
    most 100000 nodes, so one extra fuel unit covers every recursive descent;
    an impossible exhaustion still emits a fail-closed internal draft. -/
def resolvePattern (tables : TypedDeclTablesV1)
    (patternPath : NormalizedSyntacticPathV1) (pattern : PatternV1) :
    M (List SourceNameComponentV1) :=
  resolvePatternFuelV1 tables patternPath 100001 pattern

def resolveType (tables : TypedDeclTablesV1)
    (typePath : NormalizedSyntacticPathV1) : TypeV1 → M Unit
  | .named name => do
      let struct? := tables.struct.find? name
      let enum? := tables.enum.find? name
      match struct?, enum? with
      | some _, some _ =>
          let related :=
            optPathArray (itemPathForNamed? tables .struct name) ++
            optPathArray (itemPathForNamed? tables .enum name)
          emitLocated (ambiguousNameDiagnosticDraft name "type") typePath related
      | some _, none | none, some _ => pure ()
      | none, none =>
          match findFirstMatchingKind tables name with
          | some (kind, ord) =>
              emitLocated (wrongCategoryDiagnosticDraft name kind "type")
                typePath (relatedPathForKindOrdinal tables kind ord)
          | none =>
              emitLocated (unknownNameDiagnosticDraft name "type") typePath #[]
  | .array elem _ => do
      match ← directOrInternal typePath "Type.Array" "element" with
      | none => pure ()
      | some ep => resolveType tables ep elem
  | .map key value => do
      match ← directOrInternal typePath "Type.Map" "key" with
      | none => pure ()
      | some kp => resolveType tables kp key
      match ← directOrInternal typePath "Type.Map" "value" with
      | none => pure ()
      | some vp => resolveType tables vp value
  | .option elem => do
      match ← directOrInternal typePath "Type.Option" "element" with
      | none => pure ()
      | some ep => resolveType tables ep elem
  | _ => pure ()

def resolveLocalCall (tables : TypedDeclTablesV1) (scope : Scope)
    (sitePath : NormalizedSyntacticPathV1) (callee : SourceNameComponentV1) : M Unit := do
  if scope.locals.contains callee then
    emitLocated (localAsFunctionDiagnosticDraft callee "local") sitePath #[]
  else if scope.params.contains callee then
    emitLocated (localAsFunctionDiagnosticDraft callee "parameter") sitePath #[]
  else if tables.fn.find? callee |>.isSome then pure ()
  -- N5: intrinsic `commit(_)` when no user `fn commit` shadows it.
  else if isCommitCalleeNameV1 callee then pure ()
  else
    match findFirstMatchingKind tables callee with
    | some (kind, ord) =>
        emitLocated (wrongCategoryDiagnosticDraft callee kind "function")
          sitePath (relatedPathForKindOrdinal tables kind ord)
    | none =>
        emitLocated (unknownNameDiagnosticDraft callee "function") sitePath #[]

mutual
  def resolvePlaceFuelV1 (tables : TypedDeclTablesV1) (scope : Scope)
      (placePath : NormalizedSyntacticPathV1) : Nat → PlaceV1 → M Unit
    | 0, _ =>
        emit (pathInternalDraft "name resolution exceeds the validated source node bound")
    | _ + 1, .name n => resolveValueName tables scope placePath n
    | fuel + 1, .field base field => do
        -- N5/N-2: ContextRead surfaces are not value-name roots; skip base
        -- resolution for exact `context.unixTimeSeconds` / `context.caller`.
        if isContextReadPlaceV1 (.field base field) then pure ()
        else
          match ← directOrInternal placePath "Place.Field" "base" with
          | none => pure ()
          | some bp => resolvePlaceFuelV1 tables scope bp fuel base
    | fuel + 1, .index base idx => do
        match ← directOrInternal placePath "Place.Index" "base" with
        | none => pure ()
        | some bp => resolvePlaceFuelV1 tables scope bp fuel base
        match ← directOrInternal placePath "Place.Index" "index" with
        | none => pure ()
        | some ip => resolveExprFuelV1 tables scope ip fuel idx

  def resolveExprFuelV1 (tables : TypedDeclTablesV1) (scope : Scope)
      (exprPath : NormalizedSyntacticPathV1) : Nat → ExprV1 → M Unit
    | 0, _ =>
        emit (pathInternalDraft "name resolution exceeds the validated source node bound")
    | _ + 1, .literal _ => pure ()
    | fuel + 1, .place p => do
        match ← directOrInternal exprPath "Expr.Place" "place" with
        | none => pure ()
        | some pp => resolvePlaceFuelV1 tables scope pp fuel p
    | fuel + 1, .constructor ctor args => do
        -- ADR-0030 E2: env-read catalog QNs are not struct/enum constructors;
        -- skip `resolveConstructorName` (TypeCheck validates arg shape +
        -- extension declaration). Still walk args for place/name resolution.
        let ctorQn := sourceQualifiedNameV1ToString ctor
        unless isPfAssetsEnvReadQnV1 ctorQn do
          resolveConstructorName tables exprPath ctor
        for (arg, i) in args.zipIdx do
          match ← childOrInternal exprPath "Expr.Constructor" "args" i with
          | none => pure ()
          | some ap => resolveExprFuelV1 tables scope ap fuel arg
    | fuel + 1, .unary _ e => do
        match ← directOrInternal exprPath "Expr.Unary" "operand" with
        | none => pure ()
        | some op => resolveExprFuelV1 tables scope op fuel e
    | fuel + 1, .binary _ lhs rhs => do
        match ← directOrInternal exprPath "Expr.Binary" "lhs" with
        | none => pure ()
        | some lp => resolveExprFuelV1 tables scope lp fuel lhs
        match ← directOrInternal exprPath "Expr.Binary" "rhs" with
        | none => pure ()
        | some rp => resolveExprFuelV1 tables scope rp fuel rhs
    | fuel + 1, .localCall callee args => do
        resolveLocalCall tables scope exprPath callee
        for (arg, i) in args.zipIdx do
          match ← childOrInternal exprPath "Expr.LocalCall" "args" i with
          | none => pure ()
          | some ap => resolveExprFuelV1 tables scope ap fuel arg
    | fuel + 1, .match_ scrutinee arms => do
        match ← directOrInternal exprPath "Expr.Match" "scrutinee" with
        | none => pure ()
        | some sp => resolveExprFuelV1 tables scope sp fuel scrutinee
        for (arm, i) in arms.zipIdx do
          match ← childOrInternal exprPath "Expr.Match" "arms" i with
          | none => pure ()
          | some armPath => do
              match ← directOrInternal armPath "ExprMatchArm" "pattern" with
              | none => pure ()
              | some pp => do
                  let binders ← resolvePatternFuelV1 tables pp fuel arm.pattern
                  match ← directOrInternal armPath "ExprMatchArm" "value" with
                  | none => pure ()
                  | some vp =>
                      resolveExprFuelV1 tables
                        { scope with locals := binders ++ scope.locals }
                        vp fuel arm.value
    | fuel + 1, .externalCall call => do
        match ← directOrInternal exprPath "Expr.ExternalCall" "call" with
        | none => pure ()
        | some cp =>
            for (arg, i) in call.args.zipIdx do
              match ← childOrInternal cp "ExternalCallExpr" "args" i with
              | none => pure ()
              | some ap => resolveExprFuelV1 tables scope ap fuel arg

  def resolveBlockFuelV1 (tables : TypedDeclTablesV1) (scope : Scope)
      (blockPath : NormalizedSyntacticPathV1) : Nat → BlockV1 → M Unit
    | 0, _ =>
        emit (pathInternalDraft "name resolution exceeds the validated source node bound")
    | fuel + 1, block =>
        resolveStmtsFuelV1 tables scope blockPath fuel block.statements.toList 0

  def resolveStmtsFuelV1 (tables : TypedDeclTablesV1) (scope : Scope)
      (blockPath : NormalizedSyntacticPathV1) :
      Nat → List StmtV1 → Nat → M Unit
    | 0, _, _ =>
        emit (pathInternalDraft "name resolution exceeds the validated source node bound")
    | _ + 1, [], _ => pure ()
    | fuel + 1, stmt :: rest, idx => do
        match ← childOrInternal blockPath "Block" "statements" idx with
        | none => pure ()
        | some stmtPath => do
            let added ← resolveStmtFuelV1 tables scope stmtPath fuel stmt
            resolveStmtsFuelV1 tables
              { scope with locals := added ++ scope.locals }
              blockPath fuel rest (idx + 1)

  def resolveStmtFuelV1 (tables : TypedDeclTablesV1) (scope : Scope)
      (stmtPath : NormalizedSyntacticPathV1) :
      Nat → StmtV1 → M (List SourceNameComponentV1)
    | 0, _ => do
        emit (pathInternalDraft "name resolution exceeds the validated source node bound")
        pure []
    | fuel + 1, .let_ name typeAnn value => do
        match typeAnn with
        | none => pure ()
        | some ty =>
            match ← directOrInternal stmtPath "Stmt.Let" "typeAnn" with
            | none => pure ()
            | some tp => resolveType tables tp ty
        match ← directOrInternal stmtPath "Stmt.Let" "value" with
        | none => pure ()
        | some vp => resolveExprFuelV1 tables scope vp fuel value
        pure [name]
    | fuel + 1, .assign target value => do
        match ← directOrInternal stmtPath "Stmt.Assign" "target" with
        | none => pure ()
        | some tp => resolvePlaceFuelV1 tables scope tp fuel target
        match ← directOrInternal stmtPath "Stmt.Assign" "value" with
        | none => pure ()
        | some vp => resolveExprFuelV1 tables scope vp fuel value
        pure []
    | fuel + 1, .if_ condition thenBlock elseBlock => do
        match ← directOrInternal stmtPath "Stmt.If" "condition" with
        | none => pure ()
        | some cp => resolveExprFuelV1 tables scope cp fuel condition
        match ← directOrInternal stmtPath "Stmt.If" "thenBlock" with
        | none => pure ()
        | some tp => resolveBlockFuelV1 tables scope tp fuel thenBlock
        match elseBlock with
        | none => pure ()
        | some eb =>
            match ← directOrInternal stmtPath "Stmt.If" "elseBlock" with
            | none => pure ()
            | some ep => resolveBlockFuelV1 tables scope ep fuel eb
        pure []
    | fuel + 1, .match_ scrutinee arms => do
        match ← directOrInternal stmtPath "Stmt.Match" "scrutinee" with
        | none => pure ()
        | some sp => resolveExprFuelV1 tables scope sp fuel scrutinee
        for (arm, i) in arms.zipIdx do
          match ← childOrInternal stmtPath "Stmt.Match" "arms" i with
          | none => pure ()
          | some armPath => do
              match ← directOrInternal armPath "StmtMatchArm" "pattern" with
              | none => pure ()
              | some pp => do
                  let binders ← resolvePatternFuelV1 tables pp fuel arm.pattern
                  match ← directOrInternal armPath "StmtMatchArm" "body" with
                  | none => pure ()
                  | some bp =>
                      resolveBlockFuelV1 tables
                        { scope with locals := binders ++ scope.locals }
                        bp fuel arm.body
        pure []
    | fuel + 1, .for_ binder start endExclusive _ body => do
        match ← directOrInternal stmtPath "Stmt.For" "start" with
        | none => pure ()
        | some sp => resolveExprFuelV1 tables scope sp fuel start
        match ← directOrInternal stmtPath "Stmt.For" "endExclusive" with
        | none => pure ()
        | some ep => resolveExprFuelV1 tables scope ep fuel endExclusive
        match ← directOrInternal stmtPath "Stmt.For" "body" with
        | none => pure ()
        | some bp =>
            resolveBlockFuelV1 tables
              { scope with locals := binder :: scope.locals } bp fuel body
        pure []
    | fuel + 1, .assert_ condition error? => do
        match ← directOrInternal stmtPath "Stmt.Assert" "condition" with
        | none => pure ()
        | some cp => resolveExprFuelV1 tables scope cp fuel condition
        match error? with
        | none => pure ()
        | some error =>
            if (tables.error.find? error |>.isNone) then
              emitLocated (unknownNameDiagnosticDraft error "error") stmtPath #[]
        pure []
    | fuel + 1, .revert error args => do
        if (tables.error.find? error |>.isNone) then
          emitLocated (unknownNameDiagnosticDraft error "error") stmtPath #[]
        for (arg, i) in args.zipIdx do
          match ← childOrInternal stmtPath "Stmt.Revert" "args" i with
          | none => pure ()
          | some ap => resolveExprFuelV1 tables scope ap fuel arg
        pure []
    | fuel + 1, .emit event args => do
        if (tables.event.find? event |>.isNone) then
          emitLocated (unknownNameDiagnosticDraft event "event") stmtPath #[]
        for (arg, i) in args.zipIdx do
          match ← childOrInternal stmtPath "Stmt.Emit" "args" i with
          | none => pure ()
          | some ap => resolveExprFuelV1 tables scope ap fuel arg
        pure []
    | fuel + 1, .return_ value? => do
        match value? with
        | none => pure ()
        | some value =>
            match ← directOrInternal stmtPath "Stmt.Return" "value" with
            | none => pure ()
            | some vp => resolveExprFuelV1 tables scope vp fuel value
        pure []
    | fuel + 1, .call externalCall => do
        match ← directOrInternal stmtPath "Stmt.Call" "call" with
        | none => pure ()
        | some cp =>
            for (arg, i) in externalCall.args.zipIdx do
              match ← childOrInternal cp "ExternalCallExpr" "args" i with
              | none => pure ()
              | some ap => resolveExprFuelV1 tables scope ap fuel arg
        pure []
    | fuel + 1, .schedule externalCall => do
        match ← directOrInternal stmtPath "Stmt.Schedule" "call" with
        | none => pure ()
        | some cp =>
            for (arg, i) in externalCall.args.zipIdx do
              match ← childOrInternal cp "ExternalCallExpr" "args" i with
              | none => pure ()
              | some ap => resolveExprFuelV1 tables scope ap fuel arg
        pure []
end

/-- Total production wrappers over the single fuelled mutual resolver. The
    validated source node bound makes exhaustion unreachable for valid input. -/
def resolvePlace (tables : TypedDeclTablesV1) (scope : Scope)
    (placePath : NormalizedSyntacticPathV1) (place : PlaceV1) : M Unit :=
  resolvePlaceFuelV1 tables scope placePath 100001 place

def resolveExpr (tables : TypedDeclTablesV1) (scope : Scope)
    (exprPath : NormalizedSyntacticPathV1) (expr : ExprV1) : M Unit :=
  resolveExprFuelV1 tables scope exprPath 100001 expr

def resolveBlock (tables : TypedDeclTablesV1) (scope : Scope)
    (blockPath : NormalizedSyntacticPathV1) (block : BlockV1) : M Unit :=
  resolveBlockFuelV1 tables scope blockPath 100001 block

def resolveStmts (tables : TypedDeclTablesV1) (scope : Scope)
    (blockPath : NormalizedSyntacticPathV1)
    (statements : List StmtV1) (index : Nat) : M Unit :=
  resolveStmtsFuelV1 tables scope blockPath 100001 statements index

def resolveStmt (tables : TypedDeclTablesV1) (scope : Scope)
    (stmtPath : NormalizedSyntacticPathV1) (stmt : StmtV1) :
    M (List SourceNameComponentV1) :=
  resolveStmtFuelV1 tables scope stmtPath 100001 stmt

def mkBaseScope (params : Array ParamV1) : Scope :=
  { locals := [], params := params.map (·.name) }

def resolveItem (tables : TypedDeclTablesV1)
    (itemPath : NormalizedSyntacticPathV1) (item : ProgramItemV1) : M Unit := do
  let baseScope := mkBaseScope #[]
  match item with
  | .state declaration =>
      match ← directOrInternal itemPath "StateDecl" "type" with
      | none => pure ()
      | some tp => resolveType tables tp declaration.type_
  | .struct declaration =>
      for (field, i) in declaration.fields.zipIdx do
        match ← childOrInternal itemPath "StructDecl" "fields" i with
        | none => pure ()
        | some fp =>
            match ← directOrInternal fp "FieldDecl" "type" with
            | none => pure ()
            | some tp => resolveType tables tp field.type_
  | .enum declaration =>
      for (variant, i) in declaration.variants.zipIdx do
        match ← childOrInternal itemPath "EnumDecl" "variants" i with
        | none => pure ()
        | some vp =>
            for (pty, j) in variant.payloadTypes.zipIdx do
              match ← childOrInternal vp "EnumVariant" "payloadTypes" j with
              | none => pure ()
              | some tp => resolveType tables tp pty
  | .const declaration => do
      match ← directOrInternal itemPath "ConstDecl" "type" with
      | none => pure ()
      | some tp => resolveType tables tp declaration.type_
      match ← directOrInternal itemPath "ConstDecl" "value" with
      | none => pure ()
      | some vp => resolveExpr tables baseScope vp declaration.value
  | .event declaration =>
      for (param, i) in declaration.params.zipIdx do
        match ← childOrInternal itemPath "EventDecl" "params" i with
        | none => pure ()
        | some pp =>
            match ← directOrInternal pp "Param" "type" with
            | none => pure ()
            | some tp => resolveType tables tp param.type_
  | .error declaration =>
      for (param, i) in declaration.params.zipIdx do
        match ← childOrInternal itemPath "ErrorDecl" "params" i with
        | none => pure ()
        | some pp =>
            match ← directOrInternal pp "Param" "type" with
            | none => pure ()
            | some tp => resolveType tables tp param.type_
  | .init declaration => do
      for (param, i) in declaration.params.zipIdx do
        match ← childOrInternal itemPath "InitDecl" "params" i with
        | none => pure ()
        | some pp =>
            match ← directOrInternal pp "Param" "type" with
            | none => pure ()
            | some tp => resolveType tables tp param.type_
      match ← directOrInternal itemPath "InitDecl" "body" with
      | none => pure ()
      | some bp => resolveBlock tables (mkBaseScope declaration.params) bp declaration.body
  | .entry declaration => do
      for (param, i) in declaration.params.zipIdx do
        match ← childOrInternal itemPath "EntryDecl" "params" i with
        | none => pure ()
        | some pp =>
            match ← directOrInternal pp "Param" "type" with
            | none => pure ()
            | some tp => resolveType tables tp param.type_
      match ← directOrInternal itemPath "EntryDecl" "result" with
      | none => pure ()
      | some rp => resolveType tables rp declaration.result
      match ← directOrInternal itemPath "EntryDecl" "body" with
      | none => pure ()
      | some bp => resolveBlock tables (mkBaseScope declaration.params) bp declaration.body
  | .view declaration => do
      for (param, i) in declaration.params.zipIdx do
        match ← childOrInternal itemPath "ViewDecl" "params" i with
        | none => pure ()
        | some pp =>
            match ← directOrInternal pp "Param" "type" with
            | none => pure ()
            | some tp => resolveType tables tp param.type_
      match ← directOrInternal itemPath "ViewDecl" "result" with
      | none => pure ()
      | some rp => resolveType tables rp declaration.result
      match ← directOrInternal itemPath "ViewDecl" "body" with
      | none => pure ()
      | some bp => resolveBlock tables (mkBaseScope declaration.params) bp declaration.body
  | .fn declaration => do
      for (param, i) in declaration.params.zipIdx do
        match ← childOrInternal itemPath "FnDecl" "params" i with
        | none => pure ()
        | some pp =>
            match ← directOrInternal pp "Param" "type" with
            | none => pure ()
            | some tp => resolveType tables tp param.type_
      match ← directOrInternal itemPath "FnDecl" "result" with
      | none => pure ()
      | some rp => resolveType tables rp declaration.result
      match ← directOrInternal itemPath "FnDecl" "body" with
      | none => pure ()
      | some bp => resolveBlock tables (mkBaseScope declaration.params) bp declaration.body
  | .invariant declaration =>
      match ← directOrInternal itemPath "InvariantDecl" "predicate" with
      | none => pure ()
      | some pp => resolveExpr tables baseScope pp declaration.predicate
  | .extensionReq _ =>
      pure ()
  | .proof declaration =>
      if (tables.invariant.find? declaration.invariant |>.isSome) then
        pure ()
      else
        emitLocated (unknownNameDiagnosticDraft declaration.invariant "invariant")
          itemPath #[]

def emptyTables : TypedDeclTablesV1 :=
  { state := .empty, struct := .empty, enum := .empty, const := .empty,
    event := .empty, error := .empty, init := .empty, entry := .empty,
    view := .empty, fn := .empty, invariant := .empty, extensionReq := .empty,
    proof := .empty, itemIndices := emptyDeclItemIndicesV1 }

/-- Stateful source-list driver shared by both production name-resolution
    passes. Exposing this boundary lets kernel proofs replay one real source
    item at a time without introducing a second table builder or body walker. -/
def foldProgramItemsV1
    (step : α → ProgramItemV1 → Nat → M α) :
    List (ProgramItemV1 × Nat) → α → M α
  | [], acc => pure acc
  | (item, itemIndex) :: items, acc => do
      let next ← step acc item itemIndex
      foldProgramItemsV1 step items next

/-- Process one source item in the sole production declaration-table pass. -/
def buildTableItemV1
    (initial : TypedDeclTablesV1) (item : ProgramItemV1) (itemIndex : Nat) :
    M TypedDeclTablesV1 := do
  let mut tables := initial
  match programItemPathV1 itemIndex with
  | .error detail => emit (pathInternalDraft detail)
  | .ok itemPath =>
      match item with
        | .state d =>
            if tables.state.find? d.name |>.isSome then
              let firstRelated :=
                match tables.state.find? d.name with
                | some (ord, _) => relatedPathForKindOrdinal tables .state ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.name .state)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              state := tables.state.insert d.name tables.state.size d
              itemIndices := {
                tables.itemIndices with
                state := tables.itemIndices.state.push itemIndex
              }
            }
        | .struct d =>
            if tables.struct.find? d.name |>.isSome then
              let firstRelated :=
                match tables.struct.find? d.name with
                | some (ord, _) => relatedPathForKindOrdinal tables .struct ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.name .struct)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              struct := tables.struct.insert d.name tables.struct.size d
              itemIndices := {
                tables.itemIndices with
                struct := tables.itemIndices.struct.push itemIndex
              }
            }
        | .enum d =>
            if tables.enum.find? d.name |>.isSome then
              let firstRelated :=
                match tables.enum.find? d.name with
                | some (ord, _) => relatedPathForKindOrdinal tables .enum ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.name .enum)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              enum := tables.enum.insert d.name tables.enum.size d
              itemIndices := {
                tables.itemIndices with
                enum := tables.itemIndices.enum.push itemIndex
              }
            }
        | .const d =>
            if tables.const.find? d.name |>.isSome then
              let firstRelated :=
                match tables.const.find? d.name with
                | some (ord, _) => relatedPathForKindOrdinal tables .const ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.name .const)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              const := tables.const.insert d.name tables.const.size d
              itemIndices := {
                tables.itemIndices with
                const := tables.itemIndices.const.push itemIndex
              }
            }
        | .event d =>
            if tables.event.find? d.name |>.isSome then
              let firstRelated :=
                match tables.event.find? d.name with
                | some (ord, _) => relatedPathForKindOrdinal tables .event ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.name .event)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              event := tables.event.insert d.name tables.event.size d
              itemIndices := {
                tables.itemIndices with
                event := tables.itemIndices.event.push itemIndex
              }
            }
        | .error d =>
            if tables.error.find? d.name |>.isSome then
              let firstRelated :=
                match tables.error.find? d.name with
                | some (ord, _) => relatedPathForKindOrdinal tables .error ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.name .error)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              error := tables.error.insert d.name tables.error.size d
              itemIndices := {
                tables.itemIndices with
                error := tables.itemIndices.error.push itemIndex
              }
            }
        | .init d =>
            if tables.init.size > 0 then
              let firstRelated := relatedPathForKindOrdinal tables .init 0
              emitLocated duplicateInitDiagnosticDraft itemPath firstRelated
            else pure ()
            tables := {
              tables with
              init := tables.init.insert () tables.init.size d
              itemIndices := {
                tables.itemIndices with
                init := tables.itemIndices.init.push itemIndex
              }
            }
        | .entry d =>
            if tables.entry.find? d.name |>.isSome then
              let firstRelated :=
                match tables.entry.find? d.name with
                | some (ord, _) => relatedPathForKindOrdinal tables .entry ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.name .entry)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              entry := tables.entry.insert d.name tables.entry.size d
              itemIndices := {
                tables.itemIndices with
                entry := tables.itemIndices.entry.push itemIndex
              }
            }
        | .view d =>
            if tables.view.find? d.name |>.isSome then
              let firstRelated :=
                match tables.view.find? d.name with
                | some (ord, _) => relatedPathForKindOrdinal tables .view ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.name .view)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              view := tables.view.insert d.name tables.view.size d
              itemIndices := {
                tables.itemIndices with
                view := tables.itemIndices.view.push itemIndex
              }
            }
        | .fn d =>
            if tables.fn.find? d.name |>.isSome then
              let firstRelated :=
                match tables.fn.find? d.name with
                | some (ord, _) => relatedPathForKindOrdinal tables .fn ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.name .fn)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              fn := tables.fn.insert d.name tables.fn.size d
              itemIndices := {
                tables.itemIndices with
                fn := tables.itemIndices.fn.push itemIndex
              }
            }
        | .invariant d =>
            if tables.invariant.find? d.name |>.isSome then
              let firstRelated :=
                match tables.invariant.find? d.name with
                | some (ord, _) => relatedPathForKindOrdinal tables .invariant ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.name .invariant)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              invariant := tables.invariant.insert d.name tables.invariant.size d
              itemIndices := {
                tables.itemIndices with
                invariant := tables.itemIndices.invariant.push itemIndex
              }
            }
        | .extensionReq d =>
            if tables.extensionReq.find? d.id |>.isSome then
              let firstRelated :=
                match tables.extensionReq.find? d.id with
                | some (ord, _) => relatedPathForKindOrdinal tables .extensionReq ord
                | none => #[]
              emitLocated (duplicateExtensionReqDiagnosticDraft d.id)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              extensionReq := tables.extensionReq.insert d.id tables.extensionReq.size d
              itemIndices := {
                tables.itemIndices with
                extensionReq := tables.itemIndices.extensionReq.push itemIndex
              }
            }
        | .proof d =>
            let key := d.key
            if tables.proof.find? key |>.isSome then
              let firstRelated :=
                match tables.proof.find? key with
                | some (ord, _) => relatedPathForKindOrdinal tables .proof ord
                | none => #[]
              emitLocated (duplicateDeclarationDiagnosticDraft d.invariant .proof)
                itemPath firstRelated
            else pure ()
            tables := {
              tables with
              proof := tables.proof.insert key tables.proof.size d
              itemIndices := {
                tables.itemIndices with
                proof := tables.itemIndices.proof.push itemIndex
              }
            }
  pure tables

/-- Sole production declaration-table pass, implemented by the item step above
    in exact source order. -/
def buildTables (program : ProgramV1) : M TypedDeclTablesV1 :=
  foldProgramItemsV1 buildTableItemV1 program.items.zipIdx.toList emptyTables

/-- Additive draft-bearing resolution result (B7b1). -/
structure NameResolutionDraftResultV1 where
  tables : TypedDeclTablesV1
  drafts : Array TypedDiagnosticDraftV1
  ok : Bool
deriving Repr

/-- Process one source item in the sole production resolution-body walk. -/
def resolveProgramItemV1
    (tables : TypedDeclTablesV1) (_ : Unit)
    (item : ProgramItemV1) (itemIndex : Nat) : M Unit := do
  match programItemPathV1 itemIndex with
  | .error detail => emit (pathInternalDraft detail)
  | .ok itemPath => resolveItem tables itemPath item

/-- Sole production resolution-body pass, using the same source-list driver as
    declaration-table construction. -/
def resolveProgramItemsV1
    (tables : TypedDeclTablesV1) (items : List (ProgramItemV1 × Nat)) : M Unit :=
  foldProgramItemsV1 (resolveProgramItemV1 tables) items ()

/-- Path-threaded resolution authority: declaration tables + body walk with
    canonical paths on every resolution diagnostic draft. -/
def resolveProgramDraftsV1 (source : ValidatedSourceV1) : NameResolutionDraftResultV1 :=
  let (tables, s1) := (buildTables source.program).run {}
  let (_, s2) :=
    (resolveProgramItemsV1 tables source.program.items.zipIdx.toList).run s1
  { tables := tables
    drafts := s2.drafts
    ok := s2.drafts.isEmpty }

/-- Public unlocated projection: erases drafts; preserves code/message/phase/order. -/
def resolveProgramV1 (source : ValidatedSourceV1) : NameResolutionResultV1 :=
  let r := resolveProgramDraftsV1 source
  { tables := r.tables
    diagnostics := eraseArray r.drafts
    ok := r.ok }

end ProofForgeV2.Typed.NameResolutionV1

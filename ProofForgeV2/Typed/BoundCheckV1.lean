/-
  ProofForgeV2.Typed.BoundCheckV1 — D2-03 termination/bound checker slice.

  Independent pass over ValidatedSourceV1 that:

    A. Rejects pure-fn local-call recursion/cycles with stable
       `DiagnosticCodeV1.resourceBound` (`PF-BOUND-001`).  Edges and SCCs reuse
       CallGraphV1 construction (fn ordinals only; entry/view/init are call
       sites, never cycle members).  CallGraphV1 continues to emit its own
       `.sourceInvalid` cycle diagnostics; this module does not alter them.

    B. Checks nested `for ... bounded N` iteration-count products with checked
       `UInt32` multiply.  Overflow ⇒ `PF-BOUND-001`.  Static credit is the
       explicit bound literal only; no range proof of `end - start ≤ N`.

  B7b3b: sole path-threaded draft authority.  Public `checkBoundsV1` /
  `checkProgramBoundsV1` / `checkProgramBoundsResultV1`, plus collector
  helpers `collectCycleDiagnostics` / `collectLoopProductDiagnostics` /
  `checkLoopBoundsInBody`, are exact erase projections of the same draft
  execution.  Recursion-cycle drafts reuse one `collectFnCallEdgesV1` (no
  second local-call AST walk): primary = min-ordinal FnDecl; related =
  remaining SCC FnDecls (ordinal order) + every in-SCC Expr.LocalCall site
  (edge source order).  Loop-product overflow drafts use one path-threaded
  loop walk: primary = overflowing Stmt.For; related = enclosing callable
  item + active ancestor Stmt.For nodes (not the current primary).

  Duplicate `fn` keys make call-graph edges ambiguous.  In that case analysis
  is incomplete: `analysisComplete = false`, `ok = false`, no cycle/loop
  diagnostics are invented, and `checkProgramBoundsV1` surfaces name-resolution
  structural diagnostics so the independent entry cannot report success.

  Phase order inside a complete BoundCheck: cycle diagnostics (sorted by
  earliest member ordinal), then loop-product diagnostics (program item /
  statement source order).

  Product consumption: composed into `CheckV1` and fail-closed gated from
  `Typed.checkV1`.  Out of scope here: deleting CallGraph cycle codes,
  effect-occurrence Semantic IR, ResourceProfile limits, disclosure/authority,
  context.read, extension effects, Disclosure/CheckV1 locate wiring.
-/
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import ProofForgeV2.Typed.CallGraphV1
import ProofForgeV2.Typed.DiagnosticDraftV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1

namespace ProofForgeV2.Typed.BoundCheckV1

open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.CallGraphV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

/-- Checked `UInt32` multiply.  Returns `none` when the mathematical product is
    not representable in `UInt32` (i.e. ≥ 2^32). -/
def mulUInt32Checked (a b : UInt32) : Option UInt32 :=
  let p := a.toNat * b.toNat
  if p ≥ UInt32.size then none
  else some (UInt32.ofNat p)

/-- Enclosing callable identity for loop diagnostics. -/
structure CallableLabel where
  kindLabel : String
  name : String
  deriving Repr

/-- Message for a recursive pure-fn call cycle (members declaration-ordinal order). -/
def recursionCycleMessage (tables : TypedDeclTablesV1) (scc : Array Nat) : String :=
  let members := (scc.qsort (· < ·)).map (fnNameAt tables)
  let memberText := String.intercalate ", " members.toList
  s!"unbounded recursion (call cycle): {memberText}"

/-- Message for a loop nest whose iteration-count product overflows UInt32. -/
def loopProductOverflowMessage (kindLabel name : String) (bound : UInt32) : String :=
  s!"loop bound product overflows UInt32 in {kindLabel} '{name}' (bound {bound.toNat})"

/-- Diagnostic for a recursive pure-fn call cycle (unlocated projection helper). -/
def recursionCycleDiagnostic (tables : TypedDeclTablesV1) (scc : Array Nat) :
    DiagnosticV1 :=
  DiagnosticV1.make .resourceBound (recursionCycleMessage tables scc)

/-- Diagnostic for a loop-product overflow (unlocated projection helper). -/
def loopProductOverflowDiagnostic (kindLabel name : String) (bound : UInt32) :
    DiagnosticV1 :=
  DiagnosticV1.make .resourceBound (loopProductOverflowMessage kindLabel name bound)

/-- Cycle draft: primary = min-ordinal FnDecl; related = remaining SCC decls
    (ordinal order) + in-SCC LocalCall sites (edge source order). -/
def recursionCycleDiagnosticDraft
    (tables : TypedDeclTablesV1)
    (scc : Array Nat)
    (edges : Array FnCallEdgeV1) : TypedDiagnosticDraftV1 :=
  let sorted := scc.qsort (· < ·)
  let msg := recursionCycleMessage tables scc
  let base := make .resourceBound msg
  match sorted[0]? with
  | none => pathInternalDraft "bound cycle draft: empty SCC"
  | some primaryOrd =>
      match itemPathForOrdinal? tables .fn primaryOrd with
      | none =>
          pathInternalDraft s!"bound cycle draft: missing FnDecl path ordinal {primaryOrd}"
      | some primaryPath =>
          let remainingDecls : Array NormalizedSyntacticPathV1 :=
            (sorted.extract 1 sorted.size).filterMap fun o =>
              itemPathForOrdinal? tables .fn o
          let callSites : Array NormalizedSyntacticPathV1 :=
            edges.filterMap fun e =>
              if sccContains scc e.callerOrdinal && sccContains scc e.calleeOrdinal then
                some e.callSitePath
              else
                none
          withPaths base primaryPath (remainingDecls ++ callSites)

/-- Loop overflow draft: primary = overflowing Stmt.For; related = enclosing
    callable item + active ancestor For nodes (excludes current primary). -/
def loopProductOverflowDraft
    (label : CallableLabel) (bound : UInt32)
    (primaryPath : NormalizedSyntacticPathV1)
    (relatedPaths : Array NormalizedSyntacticPathV1) : TypedDiagnosticDraftV1 :=
  makeLocated .resourceBound
    (loopProductOverflowMessage label.kindLabel label.name bound)
    primaryPath relatedPaths

/-- Unlocated loop overflow draft (body-only projection when no item path). -/
def loopProductOverflowDraftUnlocated
    (label : CallableLabel) (bound : UInt32) : TypedDiagnosticDraftV1 :=
  make .resourceBound (loopProductOverflowMessage label.kindLabel label.name bound)

/-- Accumulator while walking nested `for` statements (path-threaded). -/
structure LoopWalkState where
  product : UInt32
  /-- Active outer `Stmt.For` paths enclosing the current statement (not including
      a For currently being entered until its body walk). -/
  ancestors : Array NormalizedSyntacticPathV1
  drafts : Array TypedDiagnosticDraftV1

abbrev LoopWalkM := StateM LoopWalkState

def emitLoopOverflowDraft
    (label : CallableLabel) (bound : UInt32)
    (callablePath? : Option NormalizedSyntacticPathV1)
    (forPath? : Option NormalizedSyntacticPathV1) : LoopWalkM Unit :=
  modify fun s =>
    let draft :=
      match forPath?, callablePath? with
      | some forPath, some callablePath =>
          -- related = enclosing callable + outer active Fors (exclude primary)
          loopProductOverflowDraft label bound forPath
            (#[callablePath] ++ s.ancestors)
      | some forPath, none =>
          loopProductOverflowDraft label bound forPath s.ancestors
      | none, _ =>
          loopProductOverflowDraftUnlocated label bound
    { s with drafts := s.drafts.push draft }

def emitPathError (detail : String) : LoopWalkM Unit :=
  modify fun s =>
    { s with drafts := s.drafts.push (pathInternalDraft detail) }

def childOrFail
    (parent : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat) :
    LoopWalkM (Option NormalizedSyntacticPathV1) :=
  match childPathV1 parent parentTag fieldTag index with
  | .ok p => pure (some p)
  | .error detail => do
      emitPathError detail
      pure none

def directOrFail
    (parent : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) : LoopWalkM (Option NormalizedSyntacticPathV1) :=
  childOrFail parent parentTag fieldTag 0

mutual
  /-- Walk expression subtrees only to reach nested statement-free structure.
      Bound products are statement-level; expressions do not introduce `for`. -/
  partial def walkExpr (_label : CallableLabel) : ExprV1 → LoopWalkM Unit
    | .literal _ => pure ()
    | .place p => walkPlace p
    | .constructor _ args => args.forM (walkExpr _label)
    | .unary _ e => walkExpr _label e
    | .binary _ lhs rhs => do
        walkExpr _label lhs
        walkExpr _label rhs
    | .localCall _ args => args.forM (walkExpr _label)
    | .match_ scrutinee arms => do
        walkExpr _label scrutinee
        for arm in arms do
          walkExpr _label arm.value

  partial def walkPlace : PlaceV1 → LoopWalkM Unit
    | .name _ => pure ()
    | .field base _ => walkPlace base
    | .index base idx => do
        walkPlace base
        walkExpr { kindLabel := "", name := "" } idx

  partial def walkBlock
      (label : CallableLabel)
      (callablePath? : Option NormalizedSyntacticPathV1)
      (blockPath? : Option NormalizedSyntacticPathV1)
      (block : BlockV1) : LoopWalkM Unit :=
    match blockPath? with
    | none =>
        -- Body-only projection: still check products, no path evidence.
        block.statements.forM (walkStmtUnpathed label callablePath?)
    | some blockPath =>
        walkStmts label callablePath? blockPath block.statements.toList 0

  partial def walkStmts
      (label : CallableLabel)
      (callablePath? : Option NormalizedSyntacticPathV1)
      (blockPath : NormalizedSyntacticPathV1) :
      List StmtV1 → Nat → LoopWalkM Unit
    | [], _ => pure ()
    | stmt :: rest, idx => do
        match ← childOrFail blockPath "Block" "statements" idx with
        | none => pure ()
        | some stmtPath => walkStmt label callablePath? (some stmtPath) stmt
        walkStmts label callablePath? blockPath rest (idx + 1)

  /-- Statement walk without path (legacy body-only erase projection). -/
  partial def walkStmtUnpathed
      (label : CallableLabel)
      (callablePath? : Option NormalizedSyntacticPathV1) :
      StmtV1 → LoopWalkM Unit
    | .let_ _ _ value => walkExpr label value
    | .assign target value => do
        walkPlace target
        walkExpr label value
    | .if_ condition thenBlock elseBlock? => do
        walkExpr label condition
        walkBlock label callablePath? none thenBlock
        elseBlock?.forM (walkBlock label callablePath? none)
    | .match_ scrutinee arms => do
        walkExpr label scrutinee
        for arm in arms do
          walkBlock label callablePath? none arm.body
    | .for_ _binder start endExclusive bound body => do
        walkExpr label start
        walkExpr label endExclusive
        let s ← get
        match mulUInt32Checked s.product bound with
        | none =>
            emitLoopOverflowDraft label bound callablePath? none
            walkBlock label callablePath? none body
        | some p' =>
            modify fun s' => { s' with product := p' }
            walkBlock label callablePath? none body
            modify fun s' => { s' with product := s.product }
    | .assert_ condition _ => walkExpr label condition
    | .revert _ args => args.forM (walkExpr label)
    | .emit _ args => args.forM (walkExpr label)
    | .return_ value? => value?.forM (walkExpr label)
    | .call externalCall | .schedule externalCall =>
        externalCall.args.forM (walkExpr label)

  partial def walkStmt
      (label : CallableLabel)
      (callablePath? : Option NormalizedSyntacticPathV1)
      (stmtPath? : Option NormalizedSyntacticPathV1) :
      StmtV1 → LoopWalkM Unit
    | .let_ _ _ value => walkExpr label value
    | .assign target value => do
        walkPlace target
        walkExpr label value
    | .if_ condition thenBlock elseBlock? => do
        walkExpr label condition
        match stmtPath? with
        | none =>
            walkBlock label callablePath? none thenBlock
            elseBlock?.forM (walkBlock label callablePath? none)
        | some stmtPath => do
            match ← directOrFail stmtPath "Stmt.If" "thenBlock" with
            | none => pure ()
            | some tp => walkBlock label callablePath? (some tp) thenBlock
            match elseBlock? with
            | none => pure ()
            | some eb =>
                match ← directOrFail stmtPath "Stmt.If" "elseBlock" with
                | none => pure ()
                | some ep => walkBlock label callablePath? (some ep) eb
    | .match_ scrutinee arms => do
        walkExpr label scrutinee
        match stmtPath? with
        | none =>
            for arm in arms do
              walkBlock label callablePath? none arm.body
        | some stmtPath =>
            for (arm, i) in arms.zipIdx do
              match ← childOrFail stmtPath "Stmt.Match" "arms" i with
              | none => pure ()
              | some armPath =>
                  match ← directOrFail armPath "StmtMatchArm" "body" with
                  | none => pure ()
                  | some bp => walkBlock label callablePath? (some bp) arm.body
    | .for_ _binder start endExclusive bound body => do
        walkExpr label start
        walkExpr label endExclusive
        let s ← get
        let savedProduct := s.product
        let savedAncestors := s.ancestors
        let forPath? := stmtPath?
        match mulUInt32Checked savedProduct bound with
        | none =>
            emitLoopOverflowDraft label bound callablePath? forPath?
            -- Continue into the body with the pre-multiply product so further
            -- nests still see a defined UInt32 credit; the overflow at this
            -- level is already reported.  Push this For as an active ancestor
            -- for nested overflow related evidence.
            match forPath? with
            | none => walkBlock label callablePath? none body
            | some forPath => do
                match ← directOrFail forPath "Stmt.For" "body" with
                | none => pure ()
                | some bp => do
                    modify fun s' => { s' with ancestors := s'.ancestors.push forPath }
                    walkBlock label callablePath? (some bp) body
                    modify fun s' =>
                      { s' with product := savedProduct, ancestors := savedAncestors }
        | some p' =>
            match forPath? with
            | none => do
                modify fun s' => { s' with product := p' }
                walkBlock label callablePath? none body
                modify fun s' => { s' with product := savedProduct }
            | some forPath => do
                match ← directOrFail forPath "Stmt.For" "body" with
                | none => pure ()
                | some bp => do
                    modify fun s' =>
                      { s' with
                        product := p'
                        ancestors := s'.ancestors.push forPath }
                    walkBlock label callablePath? (some bp) body
                    modify fun s' =>
                      { s' with product := savedProduct, ancestors := savedAncestors }
    | .assert_ condition _ => walkExpr label condition
    | .revert _ args => args.forM (walkExpr label)
    | .emit _ args => args.forM (walkExpr label)
    | .return_ value? => value?.forM (walkExpr label)
    | .call externalCall | .schedule externalCall =>
        externalCall.args.forM (walkExpr label)
end

/-- Collect loop-product overflow drafts for one callable body.

    When `callablePath?`/`bodyPath?` are `none`, drafts are unlocated (legacy
    body-only projection).  When paths are present, overflow drafts carry
    primary=Stmt.For and related=callable+ancestor Fors. -/
def checkLoopBoundsInBodyDrafts
    (label : CallableLabel)
    (callablePath? : Option NormalizedSyntacticPathV1)
    (bodyPath? : Option NormalizedSyntacticPathV1)
    (body : BlockV1) : Array TypedDiagnosticDraftV1 :=
  let init : LoopWalkState := { product := 1, ancestors := #[], drafts := #[] }
  let (_, st) := (walkBlock label callablePath? bodyPath? body).run init
  st.drafts

/-- Collect loop-product overflow diagnostics for one callable body. -/
def checkLoopBoundsInBody (label : CallableLabel) (body : BlockV1) :
    Array DiagnosticV1 :=
  eraseArray (checkLoopBoundsInBodyDrafts label none none body)

/-- Collect loop-product drafts for every init/entry/view/fn body in program
    source order (path-threaded). -/
def collectLoopProductDrafts (program : ProgramV1) : Array TypedDiagnosticDraftV1 :=
  program.items.zipIdx.foldl (init := #[]) fun acc (item, itemIndex) =>
    match programItemPathV1 itemIndex with
    | .error detail => acc.push (pathInternalDraft detail)
    | .ok itemPath =>
        let run (label : CallableLabel) (parentTag : String) (body : BlockV1) :=
          let bodyPath? :=
            match directChildPathV1 itemPath parentTag "body" with
            | .ok bp => some bp
            | .error _ => none
          let pathErrs : Array TypedDiagnosticDraftV1 :=
            match directChildPathV1 itemPath parentTag "body" with
            | .error detail => #[pathInternalDraft detail]
            | .ok _ => #[]
          acc ++ pathErrs ++
            checkLoopBoundsInBodyDrafts label (some itemPath) bodyPath? body
        match item with
        | .fn decl =>
            run { kindLabel := "fn", name := decl.name.raw } "FnDecl" decl.body
        | .entry decl =>
            run { kindLabel := "entry", name := decl.name.raw } "EntryDecl" decl.body
        | .view decl =>
            run { kindLabel := "view", name := decl.name.raw } "ViewDecl" decl.body
        | .init decl =>
            run { kindLabel := "init", name := "init" } "InitDecl" decl.body
        | _ => acc

/-- Collect loop-product diagnostics for every init/entry/view/fn body in
    program source order. -/
def collectLoopProductDiagnostics (program : ProgramV1) : Array DiagnosticV1 :=
  eraseArray (collectLoopProductDrafts program)

/-- Collect recursion-cycle drafts reusing one site-bearing CallGraph edge walk.
    Emits `PF-BOUND-001` (resourceBound), not CallGraph's `.sourceInvalid`. -/
def collectCycleDrafts (program : ProgramV1) (tables : TypedDeclTablesV1) :
    Array TypedDiagnosticDraftV1 :=
  let collected := collectFnCallEdgesV1 program tables
  let edges := collected.edges
  let fnCount := tables.fn.size
  let pairEdges := edges.map fun e => (e.callerOrdinal, e.calleeOrdinal)
  let adj := buildAdjacency fnCount pairEdges
  let sccs := Tarjan.run fnCount adj
  let cycles := cyclicSccs adj sccs
  let sortedCycles := cycles.qsort (fun a b =>
    let minA := a.foldl (init := fnCount) (fun acc n => min acc n)
    let minB := b.foldl (init := fnCount) (fun acc n => min acc n)
    minA < minB)
  collected.pathErrors ++
    sortedCycles.map (fun scc => recursionCycleDiagnosticDraft tables scc edges)

/-- Collect recursion-cycle diagnostics reusing CallGraph edge/SCC machinery.
    Emits `PF-BOUND-001` (resourceBound), not CallGraph's `.sourceInvalid`. -/
def collectCycleDiagnostics (program : ProgramV1) (tables : TypedDeclTablesV1) :
    Array DiagnosticV1 :=
  eraseArray (collectCycleDrafts program tables)

/-- Result of the bound/termination checker (unlocated public projection). -/
structure BoundCheckResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Draft-bearing authority result (B7b3b). -/
structure BoundCheckDraftResultV1 where
  drafts : Array TypedDiagnosticDraftV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Incomplete analysis result used for ambiguous declaration tables. -/
def incompleteBoundResult : BoundCheckResultV1 :=
  { diagnostics := #[], ok := false, analysisComplete := false }

def incompleteBoundDraftResult : BoundCheckDraftResultV1 :=
  { drafts := #[], ok := false, analysisComplete := false }

/-- Draft authority: path-threaded cycle then loop-product bound check. -/
def checkBoundsDraftsV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    BoundCheckDraftResultV1 :=
  if tables.fn.hasDuplicateKey then
    incompleteBoundDraftResult
  else
    let cycleDrafts := collectCycleDrafts program tables
    let loopDrafts := collectLoopProductDrafts program
    let drafts := cycleDrafts ++ loopDrafts
    { drafts := drafts
      ok := drafts.isEmpty
      analysisComplete := true }

/-- Check ProgramV1 recursion cycles and nested for-bound products.

    When `tables.fn` has duplicate keys, returns `analysisComplete = false` and
    does not invent edges or loop diagnostics.  Otherwise always runs cycle
    then loop-product collection (phase order). -/
def checkBoundsV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    BoundCheckResultV1 :=
  let r := checkBoundsDraftsV1 program tables
  { diagnostics := eraseArray r.drafts
    ok := r.ok
    analysisComplete := r.analysisComplete }

/-- Draft-bearing entry over a validated source unit. -/
def checkProgramBoundsDraftsV1 (source : ValidatedSourceV1) : BoundCheckDraftResultV1 :=
  let resolution := resolveProgramDraftsV1 source
  let boundRes := checkBoundsDraftsV1 source.program resolution.tables
  if boundRes.analysisComplete then
    boundRes
  else
    { drafts := resolution.drafts ++ boundRes.drafts
      ok := false
      analysisComplete := false }

/-- Entry point over a validated source unit.

    Builds declaration tables via name resolution.  When bound analysis is
    incomplete (duplicate `fn` keys), returns resolution structural diagnostics
    so the independent entry fails closed and cannot present as success.
    When analysis is complete, returns bound diagnostics only (cycles then
    loop products). -/
def checkProgramBoundsV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  eraseArray (checkProgramBoundsDraftsV1 source).drafts

/-- Full result entry including `analysisComplete`, for tests and future
    product wiring that need the structured outcome. -/
def checkProgramBoundsResultV1 (source : ValidatedSourceV1) : BoundCheckResultV1 :=
  let r := checkProgramBoundsDraftsV1 source
  { diagnostics := eraseArray r.drafts
    ok := r.ok
    analysisComplete := r.analysisComplete }

end ProofForgeV2.Typed.BoundCheckV1

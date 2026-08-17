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

  Product consumption: composed into `CheckV1`, whose located result is the
  Normalize product gate. The legacy alpha compatibility checker also consumes
  the unlocated projection. Out of scope here: deleting CallGraph cycle codes,
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
  analysisComplete : Bool

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

/-- Fuel exhaustion is an internal, fail-closed outcome. Keep one stable draft
    even if an enclosing list resumes after a nested walk exhausts its fuel. -/
def emitFuelExhausted : LoopWalkM Unit :=
  modify fun s =>
    if s.analysisComplete then
      { s with
        drafts := s.drafts.push
          (pathInternalDraft "bound loop walk: traversal fuel exhausted")
        analysisComplete := false }
    else
      s

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
  /-- Bounded-total block walk. Validated source admits at most 100000 nodes;
      production wrappers provide one additional unit of fuel. -/
  def walkBlockFuelV1
      (label : CallableLabel)
      (callablePath? : Option NormalizedSyntacticPathV1)
      (blockPath? : Option NormalizedSyntacticPathV1) :
      Nat → BlockV1 → LoopWalkM Unit
    | 0, _ => emitFuelExhausted
    | fuel + 1, block =>
        walkStmtsFuelV1 label callablePath? blockPath? fuel
          block.statements.toList 0

  def walkStmtsFuelV1
      (label : CallableLabel)
      (callablePath? : Option NormalizedSyntacticPathV1)
      (blockPath? : Option NormalizedSyntacticPathV1) :
      Nat → List StmtV1 → Nat → LoopWalkM Unit
    | _, [], _ => pure ()
    | 0, _ :: _, _ => emitFuelExhausted
    | fuel + 1, stmt :: rest, idx => do
        let stmtPath? ← match blockPath? with
          | none => pure none
          | some blockPath => childOrFail blockPath "Block" "statements" idx
        walkStmtFuelV1 label callablePath? stmtPath? fuel stmt
        walkStmtsFuelV1 label callablePath? blockPath? fuel rest (idx + 1)

  /-- Only statement structure can contain loops. Expression and place
      subtrees are intentionally not traversed because they cannot affect the
      bound-product result. -/
  def walkStmtFuelV1
      (label : CallableLabel)
      (callablePath? : Option NormalizedSyntacticPathV1)
      (stmtPath? : Option NormalizedSyntacticPathV1) : Nat → StmtV1 → LoopWalkM Unit
    | 0, _ => emitFuelExhausted
    | _fuel + 1, .let_ _ _ _ => pure ()
    | _fuel + 1, .assign _ _ => pure ()
    | fuel + 1, .if_ _ thenBlock elseBlock? => do
        match stmtPath? with
        | none =>
            walkBlockFuelV1 label callablePath? none fuel thenBlock
            match elseBlock? with
            | none => pure ()
            | some eb => walkBlockFuelV1 label callablePath? none fuel eb
        | some stmtPath => do
            match ← directOrFail stmtPath "Stmt.If" "thenBlock" with
            | none => pure ()
            | some tp => walkBlockFuelV1 label callablePath? (some tp) fuel thenBlock
            match elseBlock? with
            | none => pure ()
            | some eb =>
                match ← directOrFail stmtPath "Stmt.If" "elseBlock" with
                | none => pure ()
                | some ep => walkBlockFuelV1 label callablePath? (some ep) fuel eb
    | fuel + 1, .match_ _ arms => do
        match stmtPath? with
        | none =>
            for arm in arms do
              walkBlockFuelV1 label callablePath? none fuel arm.body
        | some stmtPath =>
            for (arm, i) in arms.zipIdx do
              match ← childOrFail stmtPath "Stmt.Match" "arms" i with
              | none => pure ()
              | some armPath =>
                  match ← directOrFail armPath "StmtMatchArm" "body" with
                  | none => pure ()
                  | some bp =>
                      walkBlockFuelV1 label callablePath? (some bp) fuel arm.body
    | fuel + 1, .for_ _ _ _ bound body => do
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
            | none => walkBlockFuelV1 label callablePath? none fuel body
            | some forPath => do
                match ← directOrFail forPath "Stmt.For" "body" with
                | none => pure ()
                | some bp => do
                    modify fun s' => { s' with ancestors := s'.ancestors.push forPath }
                    walkBlockFuelV1 label callablePath? (some bp) fuel body
                    modify fun s' =>
                      { s' with product := savedProduct, ancestors := savedAncestors }
        | some p' =>
            match forPath? with
            | none => do
                modify fun s' => { s' with product := p' }
                walkBlockFuelV1 label callablePath? none fuel body
                modify fun s' => { s' with product := savedProduct }
            | some forPath => do
                match ← directOrFail forPath "Stmt.For" "body" with
                | none => pure ()
                | some bp => do
                    modify fun s' =>
                      { s' with
                        product := p'
                        ancestors := s'.ancestors.push forPath }
                    walkBlockFuelV1 label callablePath? (some bp) fuel body
                    modify fun s' =>
                      { s' with product := savedProduct, ancestors := savedAncestors }
    | _fuel + 1, .assert_ _ _ => pure ()
    | _fuel + 1, .revert _ _ => pure ()
    | _fuel + 1, .emit _ _ => pure ()
    | _fuel + 1, .return_ _ => pure ()
    | _fuel + 1, .call _ => pure ()
    | _fuel + 1, .schedule _ => pure ()
end

/-- Production bounded-total wrapper. -/
def walkBlock
    (label : CallableLabel)
    (callablePath? : Option NormalizedSyntacticPathV1)
    (blockPath? : Option NormalizedSyntacticPathV1)
    (block : BlockV1) : LoopWalkM Unit :=
  walkBlockFuelV1 label callablePath? blockPath? 100001 block

/-- Result of one bounded loop-product body walk. -/
structure LoopBodyDraftResultV1 where
  drafts : Array TypedDiagnosticDraftV1
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Collect loop-product overflow drafts for one callable body.

    When `callablePath?`/`bodyPath?` are `none`, drafts are unlocated (legacy
    body-only projection).  When paths are present, overflow drafts carry
    primary=Stmt.For and related=callable+ancestor Fors. -/
def checkLoopBoundsInBodyDraftResultV1
    (label : CallableLabel)
    (callablePath? : Option NormalizedSyntacticPathV1)
    (bodyPath? : Option NormalizedSyntacticPathV1)
    (body : BlockV1) : LoopBodyDraftResultV1 :=
  let init : LoopWalkState :=
    { product := 1, ancestors := #[], drafts := #[], analysisComplete := true }
  let (_, st) := (walkBlock label callablePath? bodyPath? body).run init
  { drafts := st.drafts, analysisComplete := st.analysisComplete }

/-- Draft-only compatibility projection of the authoritative bounded walk. -/
def checkLoopBoundsInBodyDrafts
    (label : CallableLabel)
    (callablePath? : Option NormalizedSyntacticPathV1)
    (bodyPath? : Option NormalizedSyntacticPathV1)
    (body : BlockV1) : Array TypedDiagnosticDraftV1 :=
  (checkLoopBoundsInBodyDraftResultV1 label callablePath? bodyPath? body).drafts

/-- Collect loop-product overflow diagnostics for one callable body. -/
def checkLoopBoundsInBody (label : CallableLabel) (body : BlockV1) :
    Array DiagnosticV1 :=
  eraseArray (checkLoopBoundsInBodyDrafts label none none body)

/-- Result of the bounded-total loop walk over all callable bodies. -/
structure LoopProgramDraftResultV1 where
  drafts : Array TypedDiagnosticDraftV1
  analysisComplete : Bool
  deriving Repr, Inhabited

def collectLoopProductItemDraftResultV1
    (item : ProgramItemV1) (itemIndex : Nat) : LoopProgramDraftResultV1 :=
  let empty : LoopProgramDraftResultV1 :=
    { drafts := #[], analysisComplete := true }
  let pathFailure (detail : String) : LoopProgramDraftResultV1 :=
    { drafts := #[pathInternalDraft detail], analysisComplete := true }
  let run (itemPath : NormalizedSyntacticPathV1) (label : CallableLabel)
      (parentTag : String) (body : BlockV1) :=
    match directChildPathV1 itemPath parentTag "body" with
    | .error detail => pathFailure detail
    | .ok bodyPath =>
        let result := checkLoopBoundsInBodyDraftResultV1 label
          (some itemPath) (some bodyPath) body
        { drafts := result.drafts
          analysisComplete := result.analysisComplete }
  match programItemPathV1 itemIndex with
  | .error detail => pathFailure detail
  | .ok itemPath =>
      match item with
      | .fn decl =>
          run itemPath { kindLabel := "fn", name := decl.name.raw }
            "FnDecl" decl.body
      | .entry decl =>
          run itemPath { kindLabel := "entry", name := decl.name.raw }
            "EntryDecl" decl.body
      | .view decl =>
          run itemPath { kindLabel := "view", name := decl.name.raw }
            "ViewDecl" decl.body
      | .init decl =>
          run itemPath { kindLabel := "init", name := "init" }
            "InitDecl" decl.body
      | _ => empty

def collectLoopProductItemsDraftResultV1 :
    List (ProgramItemV1 × Nat) → LoopProgramDraftResultV1
  | [] => { drafts := #[], analysisComplete := true }
  | (item, itemIndex) :: rest =>
      let head := collectLoopProductItemDraftResultV1 item itemIndex
      let tail := collectLoopProductItemsDraftResultV1 rest
      { drafts := head.drafts ++ tail.drafts
        analysisComplete := head.analysisComplete && tail.analysisComplete }

/-- Collect loop-product drafts and completion state for every callable body in
    source order through one structurally recursive production fold. -/
def collectLoopProductDraftResultV1 (program : ProgramV1) :
    LoopProgramDraftResultV1 :=
  collectLoopProductItemsDraftResultV1 program.items.zipIdx.toList

/-- Draft-only compatibility projection of the authoritative program walk. -/
def collectLoopProductDrafts (program : ProgramV1) : Array TypedDiagnosticDraftV1 :=
  (collectLoopProductDraftResultV1 program).drafts

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
    let loopRes := collectLoopProductDraftResultV1 program
    let drafts := cycleDrafts ++ loopRes.drafts
    { drafts := drafts
      ok := loopRes.analysisComplete && drafts.isEmpty
      analysisComplete := loopRes.analysisComplete }

/-- Check ProgramV1 recursion cycles and nested for-bound products.

    When `tables.fn` has duplicate keys, returns `analysisComplete = false` and
    does not invent edges or loop diagnostics. Fuel exhaustion in the bounded
    loop walk also forces an incomplete, non-success result. Otherwise always
    runs cycle then loop-product collection (phase order). -/
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

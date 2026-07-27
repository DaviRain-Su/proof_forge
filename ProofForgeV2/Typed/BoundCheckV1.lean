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
  context.read, extension effects.
-/
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.CallGraphV1
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
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.CallGraphV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1

def emptyOrigins : Array SourceOrigin := #[]

/-- Checked `UInt32` multiply.  Returns `none` when the mathematical product is
    not representable in `UInt32` (i.e. ≥ 2^32). -/
def mulUInt32Checked (a b : UInt32) : Option UInt32 :=
  let p := a.toNat * b.toNat
  if p ≥ UInt32.size then none
  else some (UInt32.ofNat p)

/-- Diagnostic for a recursive pure-fn call cycle.  Members are named in
    ascending declaration ordinal so reporting is deterministic. -/
def recursionCycleDiagnostic (tables : TypedDeclTablesV1) (scc : Array Nat) :
    DiagnosticV1 :=
  let members := (scc.qsort (· < ·)).map (fnNameAt tables)
  let memberText := String.intercalate ", " members.toList
  { code := .resourceBound
    message := s!"unbounded recursion (call cycle): {memberText}"
    origins := emptyOrigins }

/-- Diagnostic for a loop nest whose iteration-count product overflows UInt32. -/
def loopProductOverflowDiagnostic (kindLabel name : String) (bound : UInt32) :
    DiagnosticV1 :=
  { code := .resourceBound
    message :=
      s!"loop bound product overflows UInt32 in {kindLabel} '{name}' (bound {bound.toNat})"
    origins := emptyOrigins }

/-- Enclosing callable identity for loop diagnostics. -/
structure CallableLabel where
  kindLabel : String
  name : String
  deriving Repr

/-- Accumulator while walking nested `for` statements. -/
structure LoopWalkState where
  product : UInt32
  diagnostics : Array DiagnosticV1

abbrev LoopWalkM := StateM LoopWalkState

def emitLoopOverflow (label : CallableLabel) (bound : UInt32) : LoopWalkM Unit :=
  modify fun s =>
    { s with
      diagnostics :=
        s.diagnostics.push (loopProductOverflowDiagnostic label.kindLabel label.name bound) }

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
        -- Index expressions may nest further expressions only (no `for`).
        walkExpr { kindLabel := "", name := "" } idx

  partial def walkBlock (label : CallableLabel) (block : BlockV1) : LoopWalkM Unit :=
    block.statements.forM (walkStmt label)

  partial def walkStmt (label : CallableLabel) : StmtV1 → LoopWalkM Unit
    | .let_ _ _ value => walkExpr label value
    | .assign target value => do
        walkPlace target
        walkExpr label value
    | .if_ condition thenBlock elseBlock? => do
        walkExpr label condition
        walkBlock label thenBlock
        elseBlock?.forM (walkBlock label)
    | .match_ scrutinee arms => do
        walkExpr label scrutinee
        for arm in arms do
          walkBlock label arm.body
    | .for_ _binder start endExclusive bound body => do
        walkExpr label start
        walkExpr label endExclusive
        let s ← get
        match mulUInt32Checked s.product bound with
        | none =>
            emitLoopOverflow label bound
            -- Continue into the body with the pre-multiply product so further
            -- nests still see a defined UInt32 credit; the overflow at this
            -- level is already reported.  Using the old product under-approximates
            -- deeper products after an overflow, which is acceptable: this
            -- slice only requires detecting the first overflowing multiply on
            -- required nests (e.g. three×4096 fails at the third level before
            -- any prior overflow).
            walkBlock label body
        | some p' =>
            set { s with product := p' }
            walkBlock label body
            modify fun s' => { s' with product := s.product }
    | .assert_ condition _ => walkExpr label condition
    | .revert _ args => args.forM (walkExpr label)
    | .emit _ args => args.forM (walkExpr label)
    | .return_ value? => value?.forM (walkExpr label)
    | .call externalCall | .schedule externalCall =>
        externalCall.args.forM (walkExpr label)
end

/-- Collect loop-product overflow diagnostics for one callable body. -/
def checkLoopBoundsInBody (label : CallableLabel) (body : BlockV1) :
    Array DiagnosticV1 :=
  let init : LoopWalkState := { product := 1, diagnostics := #[] }
  let (_, st) := (walkBlock label body).run init
  st.diagnostics

/-- Collect loop-product diagnostics for every init/entry/view/fn body in
    program source order. -/
def collectLoopProductDiagnostics (program : ProgramV1) : Array DiagnosticV1 :=
  program.items.foldl (init := #[]) fun acc item =>
    match item with
    | .fn decl =>
        acc ++ checkLoopBoundsInBody { kindLabel := "fn", name := decl.name.raw } decl.body
    | .entry decl =>
        acc ++ checkLoopBoundsInBody { kindLabel := "entry", name := decl.name.raw } decl.body
    | .view decl =>
        acc ++ checkLoopBoundsInBody { kindLabel := "view", name := decl.name.raw } decl.body
    | .init decl =>
        -- Init has no declaration name; use a stable label for diagnostics.
        acc ++ checkLoopBoundsInBody { kindLabel := "init", name := "init" } decl.body
    | _ => acc

/-- Collect recursion-cycle diagnostics reusing CallGraph edge/SCC machinery.
    Emits `PF-BOUND-001` (resourceBound), not CallGraph's `.sourceInvalid`. -/
def collectCycleDiagnostics (program : ProgramV1) (tables : TypedDeclTablesV1) :
    Array DiagnosticV1 :=
  let fnCount := tables.fn.size
  let edges := buildFnCallEdges program tables
  let adj := buildAdjacency fnCount edges
  let sccs := Tarjan.run fnCount adj
  let cycles := cyclicSccs adj sccs
  let sortedCycles := cycles.qsort (fun a b =>
    let minA := a.foldl (init := fnCount) (fun acc n => min acc n)
    let minB := b.foldl (init := fnCount) (fun acc n => min acc n)
    minA < minB)
  sortedCycles.map (recursionCycleDiagnostic tables)

/-- Result of the bound/termination checker.

    `analysisComplete` is false when declaration tables are too ambiguous to
    attribute local-call edges (currently: duplicate `fn` keys).  In that case
    `ok` is also false and no cycle/loop bound diagnostics are produced. -/
structure BoundCheckResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Incomplete analysis result used for ambiguous declaration tables. -/
def incompleteBoundResult : BoundCheckResultV1 :=
  { diagnostics := #[], ok := false, analysisComplete := false }

/-- Check ProgramV1 recursion cycles and nested for-bound products.

    When `tables.fn` has duplicate keys, returns `analysisComplete = false` and
    does not invent edges or loop diagnostics.  Otherwise always runs cycle
    then loop-product collection (phase order). -/
def checkBoundsV1 (program : ProgramV1) (tables : TypedDeclTablesV1) :
    BoundCheckResultV1 :=
  if tables.fn.hasDuplicateKey then
    incompleteBoundResult
  else
    let cycleDiags := collectCycleDiagnostics program tables
    let loopDiags := collectLoopProductDiagnostics program
    let diagnostics := cycleDiags ++ loopDiags
    { diagnostics := diagnostics
      ok := diagnostics.isEmpty
      analysisComplete := true }

/-- Entry point over a validated source unit.

    Builds declaration tables via name resolution.  When bound analysis is
    incomplete (duplicate `fn` keys), returns resolution structural diagnostics
    so the independent entry fails closed and cannot present as success.
    When analysis is complete, returns bound diagnostics only (cycles then
    loop products). -/
def checkProgramBoundsV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  let resolution := resolveProgramV1 source
  let boundRes := checkBoundsV1 source.program resolution.tables
  if boundRes.analysisComplete then
    boundRes.diagnostics
  else
    resolution.diagnostics ++ boundRes.diagnostics

/-- Full result entry including `analysisComplete`, for tests and future
    product wiring that need the structured outcome. -/
def checkProgramBoundsResultV1 (source : ValidatedSourceV1) : BoundCheckResultV1 :=
  let resolution := resolveProgramV1 source
  let boundRes := checkBoundsV1 source.program resolution.tables
  if boundRes.analysisComplete then
    boundRes
  else
    { diagnostics := resolution.diagnostics ++ boundRes.diagnostics
      ok := false
      analysisComplete := false }

end ProofForgeV2.Typed.BoundCheckV1

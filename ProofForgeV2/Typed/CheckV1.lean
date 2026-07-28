/-
  ProofForgeV2.Typed.CheckV1 — additive independent multi-pass ProgramV1 checker.

  B7b3d: single draft-bearing composition is the sole phase authority.
  Public unlocated APIs are exact erase projections over that authority.
  Additive located APIs bind OriginInventoryV1 by exact sourceHash then
  materialize drafts all-or-nothing via DiagnosticDraftV1.locateArray only.

  Phase order (legacy, preserved exactly):

    1. structure   = resolution.drafts ++ callGraph.cycleDrafts
    2. type        = body type drafts (only when resolution.ok; no re-emit
                     of resolution drafts)
    3. effect      = effect drafts when analysisComplete; otherwise
                     append nothing and mark incomplete
    4. bound       = bound drafts when analysisComplete; otherwise
                     append nothing and mark incomplete
    5. disclosure  = disclosure drafts when analysisComplete
                     (explicit value-flow D2-04a + PC-label / implicit if/match
                     and assert-condition public-sink D2-04b); otherwise append
                     nothing and mark incomplete

  `ok` is true only when analysis is complete and diagnostics/drafts are empty.
  Incomplete analysis (currently: duplicate `fn` keys) forces `ok = false`
  even when allowlist/bound/disclosure arrays are empty.

  When resolution fails closed, type body / effect / bound / disclosure analysis
  that would cascade nonsense is skipped.  When resolution succeeds, later
  phases still run so multi-error reporting is useful (e.g. call-graph cycle +
  type error + bound cycle + disclosure share one composed result).

  Product wiring: `Typed.checkV1` runs the unlocated multi-pass checker as a
  fail-closed gate before alpha supported-shape validation and alpha Typed IR
  lowering.  `compileValidatedSourceV1` / CLI `build` inherit the gate via that
  single product Typed boundary (no dual source readers; alpha IR lowering
  retained).  Located CheckV1 APIs are additive engineering surfaces only —
  B8 public DiagnosticBundle / CLI multi-error wiring remains pending.

  Deliberately outside this composition module:
    * replacing alpha Typed/Semantic IR lowering
    * authority / custody analysis and disclosure.commit operator
    * formal full-coverage TST-VIS-002 / TASK-D2-04 (engineering subset only)
    * SemanticProgramV1 / provenance / exact resolver / OutputSetV1
    * unifying CallGraph `.sourceInvalid` cycles with Bound `.resourceBound`
    * new DiagnosticCodeV1 constructors beyond those owned by existing phases
    * B8 public compiler/CLI DiagnosticBundle normalize/sort/dedupe/cap
    * formal TASK-D2-* completion claims
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.BoundCheckV1
import ProofForgeV2.Typed.CallGraphV1
import ProofForgeV2.Typed.DiagnosticDraftV1
import ProofForgeV2.Typed.DisclosureCheckV1
import ProofForgeV2.Typed.EffectCheckV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1
import ProofForgeV2.Typed.TypeCheckV1

namespace ProofForgeV2.Typed.CheckV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.BoundCheckV1
open ProofForgeV2.Typed.CallGraphV1
open ProofForgeV2.Typed.DiagnosticDraftV1
open ProofForgeV2.Typed.DisclosureCheckV1
open ProofForgeV2.Typed.EffectCheckV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1
open ProofForgeV2.Typed.TypeCheckV1

/-- Unlocated multi-pass Typed checker result (erase projection).

    `analysisComplete` is false when declaration tables are too ambiguous for
    effect/bound/disclosure analysis (currently: duplicate `fn` keys).  In that
    case `ok` is also false even if some phase arrays are empty. -/
structure TypedCheckResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Draft-bearing multi-pass Typed checker result (sole phase authority). -/
structure TypedCheckDraftResultV1 where
  drafts : Array TypedDiagnosticDraftV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Located multi-pass Typed checker result (all-or-nothing NodeId materialization). -/
structure TypedCheckLocatedResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Closed locate errors for CheckV1 located APIs.

    Distinguishes source-hash computation/mismatch (before any path lookup)
    from DiagnosticDraftV1.locateArray failure (path/origin materialization). -/
inductive TypedCheckLocateErrorV1 where
  | sourceHash (detail : String)
  | locate (err : TypedDiagnosticLocateErrorV1)
  deriving Repr

/-- Convert a legacy unlocated name-resolution result into unlocated drafts for
    the compatibility adapter only. Program-backed APIs must use
    `resolveProgramDraftsV1` so real paths are retained. -/
private def unlocatedDraftsFromResolution
    (resolution : NameResolutionResultV1) : NameResolutionDraftResultV1 :=
  { tables := resolution.tables
    drafts := resolution.diagnostics.map fun d =>
      { diagnostic := d, location := none }
    ok := resolution.ok }

/-- Sole draft-bearing composition authority.

    Consumes one `NameResolutionDraftResultV1`, runs `analyzeFnCallGraphV1`
    once, and concatenates phase drafts in exact legacy order. Does not re-run
    name resolution. Does not sort/dedupe/cap. -/
def checkProgramTypedDraftWithResolutionV1 (program : ProgramV1)
    (resolution : NameResolutionDraftResultV1) : TypedCheckDraftResultV1 :=
  let tables := resolution.tables
  let cg := analyzeFnCallGraphV1 program tables
  let structureDrafts := resolution.drafts ++ cg.cycleDrafts
  -- Resolution failure: emit structure only; skip type body / effect / bound /
  -- disclosure analysis that would cascade.  Duplicate fn keys leave analysis
  -- incomplete.
  if !resolution.ok then
    let analysisComplete := !tables.fn.hasDuplicateKey
    { drafts := structureDrafts
      ok := false
      analysisComplete := analysisComplete }
  else
    -- Type body only when resolution succeeded.  typeCheckProgramDraftsV1 under
    -- ok returns body drafts only (does not re-append resolution drafts).
    let typeRes := typeCheckProgramDraftsV1 program resolution
    let effectRes := checkEffectsDraftsV1 program tables
    let boundRes := checkBoundsDraftsV1 program tables
    let discRes := checkDisclosureDraftsV1 program tables
    let analysisComplete :=
      effectRes.analysisComplete && boundRes.analysisComplete &&
        discRes.analysisComplete
    let effectDrafts :=
      if effectRes.analysisComplete then effectRes.drafts else #[]
    let boundDrafts :=
      if boundRes.analysisComplete then boundRes.drafts else #[]
    let discDrafts :=
      if discRes.analysisComplete then discRes.drafts else #[]
    let drafts :=
      structureDrafts ++ typeRes.drafts ++ effectDrafts ++ boundDrafts ++
        discDrafts
    { drafts := drafts
      ok := analysisComplete && drafts.isEmpty
      analysisComplete := analysisComplete }

/-- Draft-bearing multi-pass Typed check over a validated ProgramV1 source unit.

    Runs `resolveProgramDraftsV1` exactly once and feeds tables/drafts into the
    sole composition authority. -/
def checkProgramTypedDraftResultV1 (source : ValidatedSourceV1) :
    TypedCheckDraftResultV1 :=
  checkProgramTypedDraftWithResolutionV1 source.program
    (resolveProgramDraftsV1 source)

/-- Exact erase projection of a draft result (no second phase implementation). -/
private def eraseDraftResult (r : TypedCheckDraftResultV1) : TypedCheckResultV1 :=
  { diagnostics := eraseArray r.drafts
    ok := r.ok
    analysisComplete := r.analysisComplete }

/-- Compose structure / type / effect / bound / disclosure phases from a single
    legacy unlocated resolution result. Compatibility adapter only: converts
    diagnostics to unlocated drafts, then erases the sole draft authority. -/
def checkProgramTypedWithResolutionV1 (program : ProgramV1)
    (resolution : NameResolutionResultV1) : TypedCheckResultV1 :=
  eraseDraftResult
    (checkProgramTypedDraftWithResolutionV1 program
      (unlocatedDraftsFromResolution resolution))

/-- Multi-pass Typed check over a validated ProgramV1 source unit.

    Exact erase of `checkProgramTypedDraftResultV1` (single resolve + composition). -/
def checkProgramTypedResultV1 (source : ValidatedSourceV1) : TypedCheckResultV1 :=
  eraseDraftResult (checkProgramTypedDraftResultV1 source)

/-- Diagnostics-only entry for the multi-pass Typed checker. -/
def checkProgramTypedV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  (checkProgramTypedResultV1 source).diagnostics

/-- Gate inventory by exact production sourceHash before any path lookup. -/
private def requireMatchingInventory
    (source : ValidatedSourceV1) (inv : OriginInventoryV1) :
    Except TypedCheckLocateErrorV1 Unit :=
  match sourceHashV1 source with
  | .error detail => .error (.sourceHash detail)
  | .ok digest =>
      if digest == originInventorySourceHashV1 inv then
        pure ()
      else
        .error (.sourceHash
          "sourceHashV1 does not match originInventorySourceHashV1")

/-- Materialize full draft array through inventory (all-or-nothing; no partial). -/
private def locateDraftResult
    (inv : OriginInventoryV1) (r : TypedCheckDraftResultV1) :
    Except TypedCheckLocateErrorV1 TypedCheckLocatedResultV1 :=
  match locateArray inv r.drafts with
  | .error err => .error (.locate err)
  | .ok diags =>
      pure {
        diagnostics := diags
        ok := r.ok
        analysisComplete := r.analysisComplete
      }

/-- Located multi-pass Typed check: hash-gate then all-or-nothing locateArray.

    Does not sort/dedupe/cap (B8). Does not fall back to unlocated diagnostics. -/
def checkProgramTypedLocatedResultV1
    (source : ValidatedSourceV1) (inv : OriginInventoryV1) :
    Except TypedCheckLocateErrorV1 TypedCheckLocatedResultV1 := do
  requireMatchingInventory source inv
  locateDraftResult inv (checkProgramTypedDraftResultV1 source)

/-- Diagnostics-only located entry (same hash gate + all-or-nothing locate). -/
def checkProgramTypedLocatedV1
    (source : ValidatedSourceV1) (inv : OriginInventoryV1) :
    Except TypedCheckLocateErrorV1 (Array DiagnosticV1) := do
  let r ← checkProgramTypedLocatedResultV1 source inv
  pure r.diagnostics

end ProofForgeV2.Typed.CheckV1

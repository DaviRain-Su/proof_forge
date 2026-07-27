/-
  ProofForgeV2.Typed.CheckV1 — additive independent multi-pass ProgramV1 checker.

  Composes already-completed D2-01/02/03/04a/04b analyzers with a single
  name-resolution pass and stable phase-order diagnostics:

    1. structure   = resolution.diagnostics ++ callGraph.diagnostics
    2. type        = type body diagnostics (only when resolution.ok; no re-emit
                     of resolution diagnostics)
    3. effect      = checkEffectsV1 diagnostics when analysisComplete; otherwise
                     append nothing and mark incomplete
    4. bound       = checkBoundsV1 diagnostics when analysisComplete; otherwise
                     append nothing and mark incomplete
    5. disclosure  = checkDisclosureV1 diagnostics when analysisComplete
                     (explicit value-flow D2-04a + PC-label / implicit if/match
                     and assert-condition public-sink D2-04b); otherwise append
                     nothing and mark incomplete

  `ok` is true only when analysis is complete and diagnostics are empty.
  Incomplete analysis (currently: duplicate `fn` keys) forces `ok = false`
  even when allowlist/bound/disclosure arrays are empty.

  When resolution fails closed, type body / effect / bound / disclosure analysis
  that would cascade nonsense is skipped.  When resolution succeeds, later
  phases still run so multi-error reporting is useful (e.g. call-graph cycle +
  type error + bound cycle + disclosure share one composed result).

  Product wiring: `Typed.checkV1` runs this multi-pass checker as a fail-closed
  gate before alpha supported-shape validation and alpha Typed IR lowering.
  `compileValidatedSourceV1` / CLI `build` inherit the gate via that single
  product Typed boundary (no dual source readers; alpha IR lowering retained).

  Deliberately outside this composition module:
    * replacing alpha Typed/Semantic IR lowering
    * authority / custody analysis and disclosure.commit operator
    * formal full-coverage TST-VIS-002 / TASK-D2-04 (engineering subset only)
    * SemanticProgramV1 / provenance / exact resolver / OutputSetV1
    * unifying CallGraph `.sourceInvalid` cycles with Bound `.resourceBound`
    * new DiagnosticCodeV1 constructors beyond those owned by existing phases
    * formal TASK-D2-* completion claims
-/
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.BoundCheckV1
import ProofForgeV2.Typed.CallGraphV1
import ProofForgeV2.Typed.DisclosureCheckV1
import ProofForgeV2.Typed.EffectCheckV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1
import ProofForgeV2.Typed.TypeCheckV1

namespace ProofForgeV2.Typed.CheckV1

open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.BoundCheckV1
open ProofForgeV2.Typed.CallGraphV1
open ProofForgeV2.Typed.DisclosureCheckV1
open ProofForgeV2.Typed.EffectCheckV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1
open ProofForgeV2.Typed.TypeCheckV1

/-- Result of the independent multi-pass Typed checker.

    `analysisComplete` is false when declaration tables are too ambiguous for
    effect/bound/disclosure analysis (currently: duplicate `fn` keys).  In that
    case `ok` is also false even if some phase arrays are empty. -/
structure TypedCheckResultV1 where
  diagnostics : Array DiagnosticV1
  ok : Bool
  analysisComplete : Bool
  deriving Repr, Inhabited

/-- Compose structure / type / effect / bound / disclosure phases from a single
    resolution result.  Does not re-run name resolution. -/
def checkProgramTypedWithResolutionV1 (program : ProgramV1)
    (resolution : NameResolutionResultV1) : TypedCheckResultV1 :=
  let tables := resolution.tables
  let cg := checkCallGraphV1 program tables
  let structureDiags := resolution.diagnostics ++ cg.diagnostics
  -- Resolution failure: emit structure only; skip type body / effect / bound /
  -- disclosure analysis that would cascade.  Duplicate fn keys leave analysis
  -- incomplete.
  if !resolution.ok then
    let analysisComplete := !tables.fn.hasDuplicateKey
    { diagnostics := structureDiags
      ok := false
      analysisComplete := analysisComplete }
  else
    -- Prefer (a): type body only when resolution succeeded.  typeCheckProgramV1
    -- already returns resolution diags when !ok; under ok its prefix is empty.
    let typeRes := typeCheckProgramV1 program resolution
    let effectRes := checkEffectsV1 program tables
    let boundRes := checkBoundsV1 program tables
    let discRes := checkDisclosureV1 program tables
    let analysisComplete :=
      effectRes.analysisComplete && boundRes.analysisComplete &&
        discRes.analysisComplete
    let effectDiags :=
      if effectRes.analysisComplete then effectRes.diagnostics else #[]
    let boundDiags :=
      if boundRes.analysisComplete then boundRes.diagnostics else #[]
    let discDiags :=
      if discRes.analysisComplete then discRes.diagnostics else #[]
    let diagnostics :=
      structureDiags ++ typeRes.diagnostics ++ effectDiags ++ boundDiags ++
        discDiags
    { diagnostics := diagnostics
      ok := analysisComplete && diagnostics.isEmpty
      analysisComplete := analysisComplete }

/-- Multi-pass Typed check over a validated ProgramV1 source unit.

    Runs `resolveProgramV1` once and feeds tables into later phases. -/
def checkProgramTypedResultV1 (source : ValidatedSourceV1) : TypedCheckResultV1 :=
  checkProgramTypedWithResolutionV1 source.program (resolveProgramV1 source)

/-- Diagnostics-only entry for the multi-pass Typed checker. -/
def checkProgramTypedV1 (source : ValidatedSourceV1) : Array DiagnosticV1 :=
  (checkProgramTypedResultV1 source).diagnostics

end ProofForgeV2.Typed.CheckV1

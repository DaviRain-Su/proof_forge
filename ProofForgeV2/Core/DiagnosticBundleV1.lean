/-
  ProofForgeV2.Core.DiagnosticBundleV1 — B8a inert failure-bundle foundation.

  Opaque `DiagnosticBundleV1` with private constructor. Callers obtain a
  failure bundle only through the total `mkFailureBundleV1`, which reuses the
  sole DiagnosticV1 authority:

    * `DiagnosticV1.normalizeDiagnosticBundleV1` (sort/dedupe/100-cap + limit)
    * `DiagnosticV1.validate` / `toCanonicalJson` / `make` / `toPfJson`

  Invariants of a retained failure bundle:
    * nonempty
    * ≥1 severity=error diagnostic with code ≠ PF-DIAG-LIMIT
    * ≤1 PF-DIAG-LIMIT and only in final position (normalize guarantee)
    * every retained diagnostic encodes canonically via PF-JCS

  Empty, limit-only, warning/note-only, structurally invalid, or non-encodable
  inputs fail closed to one fixed public-safe PF-INTERNAL diagnostic that does
  not echo rejected input details.

  Exit selection considers severity=error only; PF-DIAG-LIMIT and non-error
  diagnostics are neutral. Highest SPEC-CLI-001 priority wins:
    internal code → 70
    deploy/verify phase → 7
    emit/tool phase → 6
    plan/lower phase → 5
    resolve phase → 4
    source/type/effect/semantic phase → 3

  `DiagnosticResultV1` is a product-only foundation type and does not replace
  or modify global alpha `CompileResult` / `CompileError`.

  B8a delivered this inert foundation. **B8b** (engineering) performs the sole
  atomic product cutover: Loader → located Normalize → Compiler → CLI consume
  `DiagnosticResultV1` / `mkFailureBundleV1` / `selectExitCode` without first-
  error truncation. Formal TASK-D1-07 remains pending. Full JSON result
  envelope/receipts, Emit/Toolchain bundle migration, and OutputSet remain
  out of scope.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1

namespace ProofForgeV2.Core.DiagnosticBundleV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1

/-- Opaque failure diagnostic bundle. Sole constructor is `mkFailureBundleV1`. -/
structure DiagnosticBundleV1 where
  private mk ::
  private diagnostics_ : Array DiagnosticV1

/-- Product-only result carrier. Does not replace alpha `CompileResult`. -/
inductive DiagnosticResultV1 (α : Type) where
  | ok (value : α)
  | error (bundle : DiagnosticBundleV1)

/-- Fixed public-safe PF-INTERNAL used when construction invariants fail.
    Deterministic, bounded, redacted, independent of rejected input details. -/
private def fixedInternalDiagnostic : DiagnosticV1 :=
  DiagnosticV1.make .internal "diagnostic bundle invariant failed"
    (actual := some (PfJson.string "bundleInvariant"))

/-- True when `d` is a real severity=error diagnostic other than PF-DIAG-LIMIT. -/
private def isRealError (d : DiagnosticV1) : Bool :=
  d.severity == .error && d.code != .diagLimit

/-- Check normalize-produced shape: at most one PF-DIAG-LIMIT and only final. -/
private def limitShapeOk (diags : Array DiagnosticV1) : Bool :=
  let limits := diags.filter (fun d => d.code == .diagLimit)
  if limits.size == 0 then true
  else if limits.size > 1 then false
  else
    diags.size > 0 && diags[diags.size - 1]!.code == .diagLimit

/-- Every diagnostic must validate and encode canonically. -/
private def allEncodable (diags : Array DiagnosticV1) : Bool :=
  diags.all fun d =>
    match DiagnosticV1.validate d, DiagnosticV1.toCanonicalJson d with
    | .ok (), .ok _ => true
    | _, _ => false

namespace DiagnosticBundleV1

/-- Read-only projection of retained diagnostics (normalized order). -/
def diagnostics (bundle : DiagnosticBundleV1) : Array DiagnosticV1 :=
  bundle.diagnostics_

/-- Deterministic human rendering: one `CODE: message` line per diagnostic. -/
def renderHuman (bundle : DiagnosticBundleV1) : String :=
  String.intercalate "\n" (bundle.diagnostics_.toList.map DiagnosticV1.renderHuman)

/-- Deterministic canonical PF-JCS JSON array of retained diagnostics.
    Fail closed only if an internal invariant is somehow violated (should not
    occur for constructor-produced bundles). -/
def renderCanonicalJsonArray (bundle : DiagnosticBundleV1) : Except String String := do
  let values ← bundle.diagnostics_.mapM DiagnosticV1.toPfJson
  renderPfJcs (.array values)

/-- Map a single severity=error diagnostic to an exit priority, or none if neutral. -/
private def exitPriorityOf (d : DiagnosticV1) : Option Nat :=
  if d.severity != .error then none
  else if d.code == .diagLimit then none
  else if d.code == .internal then some 70
  else
    match d.phase with
    | .deploy | .verify => some 7
    | .emit | .tool => some 6
    | .plan | .lower => some 5
    | .resolve => some 4
    | .source | .type | .effect | .semantic => some 3

/-- SPEC-CLI-001 highest-priority exit among severity=error diagnostics.
    PF-DIAG-LIMIT and non-error diagnostics are neutral. Constructor-produced
    bundles always contain at least one real error, so a priority always exists;
    the fixed internal fallback yields 70. Empty/neutral priority sets fail closed
    to 70 (not success 0); nonempty sets take the max (private ctor makes empty
    priorities unreachable in normal construction — 70 is defensive). -/
def selectExitCode (bundle : DiagnosticBundleV1) : Nat :=
  let priorities := bundle.diagnostics_.filterMap exitPriorityOf
  if priorities.isEmpty then 70
  else priorities.foldl (fun acc p => if p > acc then p else acc) 0

end DiagnosticBundleV1

private def fixedInternalBundle : DiagnosticBundleV1 :=
  ⟨#[fixedInternalDiagnostic]⟩

/-- Accept normalized diagnostics only when all failure-bundle invariants hold. -/
private def tryAccept (normalized : Array DiagnosticV1) : Option DiagnosticBundleV1 :=
  if normalized.isEmpty then none
  else if !(normalized.any isRealError) then none
  else if !limitShapeOk normalized then none
  else if !allEncodable normalized then none
  else some ⟨normalized⟩

/-- Sole total failure-bundle constructor.

    Reuses `normalizeDiagnosticBundleV1` then enforces nonempty / real-error /
    limit-shape / canonical-encode invariants. Any failure yields the fixed
    public-safe PF-INTERNAL bundle (no input detail leak). Idempotent on the
    diagnostics of an already-constructed valid bundle. -/
def mkFailureBundleV1 (diagnostics : Array DiagnosticV1) : DiagnosticBundleV1 :=
  let normalized := DiagnosticV1.normalizeDiagnosticBundleV1 diagnostics
  match tryAccept normalized with
  | some bundle => bundle
  | none => fixedInternalBundle

end ProofForgeV2.Core.DiagnosticBundleV1

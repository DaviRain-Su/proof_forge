import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Core.SemanticIR
import ProofForgeV2.Core.TypedV1
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Compiler

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.ValidatedSourceV1

/-- Compatibility compiler entry for hand-built alpha fixtures. Product source
loading uses `compileProgramProductV1`; this function does not participate in
the ProgramV1 product frontend path. -/
def compile (source : Source.Program) : CompileResult Semantic.Program := do
  let typed ← Typed.check source
  return Semantic.fromTyped source.sourceHash typed

private def invalid (message : String) : CompileResult α :=
  .error (.invalidProgram message)

private def isLowerHex (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

private def semanticSourceHash (source : ValidatedSourceV1) : CompileResult String := do
  let digest ← match sourceHashV1 source with
    | .ok digest => pure digest
    | .error error => invalid error
  let rendered ← match renderDigest digest with
    | .ok rendered => pure rendered
    | .error error => invalid error
  unless rendered.startsWith "sha256:" do
    return ← invalid "validated ProgramV1 source hash must use sha256:"
  let suffix := (rendered.drop 7).toString
  unless suffix.length == 64 && suffix.all isLowerHex do
    return ← invalid
      "validated ProgramV1 source hash must contain 64 lowercase hex characters"
  pure suffix

/-- Closed, hand-written summary for structure-gate wire failures.
    Stable product text — never Lean `repr` (not a contract). -/
private def renderSemanticWireErrorSummaryV1 : SemanticWireErrorV1 → String
  | .truncated => "truncated"
  | .limitExceeded => "limitExceeded"
  | .badMagic => "badMagic"
  | .badTag => "badTag"
  | .badFieldCount => "badFieldCount"
  | .badScalar => "badScalar"
  | .nonCanonical => "nonCanonical"
  | .duplicate => "duplicate"
  | .badReference => "badReference"
  | .badType => "badType"
  | .badCfg => "badCfg"
  | .badRequirement => "badRequirement"
  | .badProvenance => "badProvenance"
  | .trailingBytes => "trailingBytes"

/-- Product `invalidProgram` message for Normalize `.wire` failures (non-product). -/
def productMessageFromWireErrorV1 (e : SemanticWireErrorV1) : String :=
  s!"semantic structure gate: {renderSemanticWireErrorSummaryV1 e}"

/-- Map residual alpha `CompileError` into a structured failure bundle.
    Never leaks alpha `PF-SEM-*` codes onto the product diagnostic surface. -/
private def residualAlphaFailureBundle (err : CompileError) : DiagnosticBundleV1 :=
  match err with
  | .effectDisallowed msg =>
      mkFailureBundleV1 #[DiagnosticV1.make .effectDisallowed msg]
  | .visibilityViolation msg =>
      mkFailureBundleV1 #[DiagnosticV1.make .visibilityViolation msg]
  | .resourceBound msg =>
      mkFailureBundleV1 #[DiagnosticV1.make .resourceBound msg]
  | .invalidProgram msg =>
      mkFailureBundleV1 #[DiagnosticV1.make .sourceInvalid msg]
  | _ =>
      mkFailureBundleV1 #[
        DiagnosticV1.make .internal "residual materialization failed"
          (actual := some (PfJson.string "residualAlpha"))]

/-- Sole product compiler entry (B8b).

    Gate order:
    1. `NormalizeV1.normalizeProgramLocatedV1` — located CheckV1 (ok ∧
       analysisComplete) then S1 structure-gated SemanticProgramV1. Preserves
       the complete diagnostic bundle (no first-error truncation).
    2. On located Normalize success only: residual alpha `Typed.checkV1` +
       `Semantic.fromTyped` for Registry / EVM / NEAR / Solana / Noir Plan APIs.

    Fail closed: Normalize rejection never falls back to alpha-only compile.
    Impossible residual alpha failures become public-safe structured diagnostics
    (no `PF-SEM-*` leakage). Pattern-matches `DiagnosticResultV1` only.
-/
def compileProgramProductV1
    (source : ValidatedSourceV1) (inv : OriginInventoryV1) :
    DiagnosticResultV1 Semantic.Program :=
  match normalizeProgramLocatedV1 source inv with
  | .error bundle => .error bundle
  | .ok _carrier =>
      match Typed.checkV1 source with
      | .error err => .error (residualAlphaFailureBundle err)
      | .ok typed =>
          match semanticSourceHash source with
          | .error err => .error (residualAlphaFailureBundle err)
          | .ok sourceHash =>
              .ok (Semantic.fromTyped sourceHash typed)

/-- Non-product typed-not-ok mapping for hand-built fixtures only.

    Takes the first phase-ordered multipass diagnostic (CheckV1 order; not
    `mkFailureBundleV1` sort). Product paths must use `compileProgramProductV1`
    and never erase a bundle to a single `CompileError`.
-/
private def nonProductTypedNotOk (diags : Array DiagnosticV1) : CompileError :=
  match diags.toList with
  | [] => .invalidProgram "typed multi-pass analysis incomplete"
  | d :: _ =>
      match d.code with
      | .resourceBound => .resourceBound d.message
      | .effectDisallowed => .effectDisallowed d.message
      | .visibilityViolation => .visibilityViolation d.message
      | _ => .invalidProgram d.message

/-- Non-product compatibility compiler for hand-built `ValidatedSourceV1` fixtures.

    Uses unlocated `normalizeProgramV1`. Typed multi-pass failures map via
    `nonProductTypedNotOk` (fixture convenience only). Product Loader/CLI must
    use `compileProgramProductV1` and preserve full `DiagnosticBundleV1`.
-/
def compileValidatedSourceV1 (source : ValidatedSourceV1) : CompileResult Semantic.Program := do
  match normalizeProgramV1 source with
  | .error (.typedNotOk diags) => .error (nonProductTypedNotOk diags)
  | .error (.unsupported detail) => .error (.invalidProgram detail)
  | .error (.identity detail) => .error (.invalidProgram detail)
  | .error (.wire e) => .error (.invalidProgram (productMessageFromWireErrorV1 e))
  | .ok _carrier =>
      let typed ← Typed.checkV1 source
      let sourceHash ← semanticSourceHash source
      pure (Semantic.fromTyped sourceHash typed)

end ProofForgeV2.Compiler

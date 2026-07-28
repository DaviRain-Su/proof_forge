import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Core.SemanticIR
import ProofForgeV2.Core.TypedV1
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Compiler

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1

/-- Compatibility compiler entry for hand-built alpha fixtures. Product source
loading uses `compileValidatedSourceV1`; this function does not participate in
the ProgramV1 frontend path. -/
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

/-- Map a multi-pass `DiagnosticV1` onto the single-error product carrier.
    Wire codes stay stable: PF-BOUND-001 / PF-EFFECT-001 / PF-VIS-001 /
    PF-SRC-INVALID (and PF-INTERNAL → invalidProgram). Local replica of the
    TypedV1 private mapper so Pipeline stays independent of TypedV1 internals. -/
private def compileErrorFromDiagnosticV1 (diag : DiagnosticV1) : CompileError :=
  match diag.code with
  | .resourceBound => .resourceBound diag.message
  | .effectDisallowed => .effectDisallowed diag.message
  | .visibilityViolation => .visibilityViolation diag.message
  | _ => .invalidProgram diag.message

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

/-- Product `invalidProgram` message for Normalize `.wire` failures. -/
def productMessageFromWireErrorV1 (e : SemanticWireErrorV1) : String :=
  s!"semantic structure gate: {renderSemanticWireErrorSummaryV1 e}"

/-- Map NormalizeV1 failures to product `CompileError`.
    * `.typedNotOk` preserves exact CheckV1 phase-ordered wires
      (resourceBound / effectDisallowed / visibilityViolation / invalidProgram).
    * `.unsupported` / `.identity` / `.wire` map to stable `invalidProgram`
      text (no new formal DiagnosticCode inventing). -/
private def compileErrorFromNormalizeV1 (err : NormalizeErrorV1) : CompileError :=
  match err with
  | .typedNotOk diags =>
      match diags[0]? with
      | some diag => compileErrorFromDiagnosticV1 diag
      | none => .invalidProgram "typed multi-pass analysis incomplete"
  | .unsupported detail => .invalidProgram detail
  | .identity detail => .invalidProgram detail
  | .wire e => .invalidProgram (productMessageFromWireErrorV1 e)

/-- Production target-neutral compiler boundary for ProgramV1.

    Gate order (S3):
    1. `NormalizeV1.normalizeProgramV1` — CheckV1 (ok ∧ analysisComplete) then
       S1 lowering into structure-gated `SemanticProgramV1` (sole success path).
    2. On Normalize success only: residual alpha `Typed.checkV1` +
       `Semantic.fromTyped` so Registry / EVM / NEAR / Solana / Noir Plan APIs
       continue to consume alpha `Semantic.Program` without adapter or dual path.

    Fail closed: Normalize rejection never falls back to alpha-only compile.
    No flag, dual source reader, alpha→SemanticProgramV1 adapter, or
    target-specific semantic branch. The Normalize carrier is discarded after
    the gate; residual materializers stay on alpha Semantic. -/
def compileValidatedSourceV1 (source : ValidatedSourceV1) : CompileResult Semantic.Program := do
  match normalizeProgramV1 source with
  | .error err => .error (compileErrorFromNormalizeV1 err)
  | .ok _carrier =>
      -- Residual alpha carrier for current Registry/target materializers.
      let typed ← Typed.checkV1 source
      let sourceHash ← semanticSourceHash source
      pure (Semantic.fromTyped sourceHash typed)

end ProofForgeV2.Compiler

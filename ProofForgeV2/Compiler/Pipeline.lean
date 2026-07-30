import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Compiler

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.ValidatedSourceV1

private def invalid (message : String) : CompileResult α :=
  .error (.invalidProgram message)

/-- Map a multi-pass `DiagnosticV1` onto the single-error compatibility carrier.
    Wire codes stay stable: PF-BOUND-001 / PF-EFFECT-001 / PF-VIS-001 /
    PF-SRC-INVALID (and PF-INTERNAL → invalidProgram). -/
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
def productMessageFromWireErrorV1 (error : SemanticWireErrorV1) : String :=
  s!"semantic structure gate: {renderSemanticWireErrorSummaryV1 error}"

/-- Map NormalizeV1 failures to compatibility `CompileError` while preserving
    CheckV1's exact diagnostic phase/code choice. -/
private def compileErrorFromNormalizeV1 (error : NormalizeErrorV1) : CompileError :=
  match error with
  | .typedNotOk diagnostics =>
      match diagnostics[0]? with
      | some diagnostic => compileErrorFromDiagnosticV1 diagnostic
      | none => .invalidProgram "typed multi-pass analysis incomplete"
  | .unsupported detail => .invalidProgram detail
  | .identity detail => .invalidProgram detail
  | .wire wireError => .invalidProgram (productMessageFromWireErrorV1 wireError)

/-- Map a post-Normalize identity/hash failure into a public-safe product bundle. -/
private def postNormalizeFailureBundleV1 (error : CompileError) : DiagnosticBundleV1 :=
  match error with
  | .effectDisallowed message =>
      mkFailureBundleV1 #[DiagnosticV1.make .effectDisallowed message]
  | .visibilityViolation message =>
      mkFailureBundleV1 #[DiagnosticV1.make .visibilityViolation message]
  | .resourceBound message =>
      mkFailureBundleV1 #[DiagnosticV1.make .resourceBound message]
  | .invalidProgram message =>
      mkFailureBundleV1 #[DiagnosticV1.make .sourceInvalid message]
  | _ =>
      mkFailureBundleV1 #[DiagnosticV1.make .internal "compiled semantic identity failed"]

private def digestHexV1 (label : String) (digest : Digest) : CompileResult String := do
  let rendered ← match renderDigest digest with
    | .ok value => pure value
    | .error error => invalid s!"{label} digest render failed: {error}"
  unless rendered.startsWith "sha256:" do
    return ← invalid s!"{label} digest must use sha256:"
  let suffix := (rendered.drop 7).toString
  unless suffix.length == 64 do
    return ← invalid s!"{label} digest must contain 64 lowercase hex characters"
  pure suffix

/-- Single retained-semantic compiler result.

    The private constructor atomically binds:
    * the structure-valid canonical `SemanticProgramV1`;
    * the artifact name derived from its validated qualified-name final component;
    * the canonical ProgramV1 `sourceHashV1` digest;
    * the canonical `semanticHashV1` digest.

    No alpha Typed/Semantic carrier, duplicate hash strings, caller identity
    override, or post-Normalize semantic fallback is retained. Sole mint:
    `finishCompiledSemanticV1`. This is still an engineering carrier, not
    BuildIdentity or OutputSetV1. -/
structure CompiledSemanticV1 where
  private mk ::
  semanticV1 : SemanticProgramV1
  artifactProgramName : String
  sourceDigest : Digest
  semanticDigest : Digest

namespace CompiledSemanticV1

/-- Read-only retained semantic accessor. -/
def semanticV1Of (compiled : CompiledSemanticV1) : SemanticProgramV1 :=
  compiled.semanticV1

/-- Artifact stem derived at the sole mint from semantic qualified identity. -/
def artifactProgramNameOf (compiled : CompiledSemanticV1) : String :=
  compiled.artifactProgramName

/-- Exact canonical ProgramV1 source digest. -/
def sourceDigestOf (compiled : CompiledSemanticV1) : Digest :=
  compiled.sourceDigest

/-- Exact canonical retained SemanticProgramV1 digest. -/
def semanticDigestOf (compiled : CompiledSemanticV1) : Digest :=
  compiled.semanticDigest

/-- Derived lowercase SHA-256 source hex for transitional v2alpha1 rendering. -/
def artifactSourceHashHexOf (compiled : CompiledSemanticV1) : CompileResult String :=
  digestHexV1 "compiled source" compiled.sourceDigest

/-- Derived lowercase SHA-256 semantic hex for Noir/v2alpha1 rendering. -/
def artifactSemanticHashHexOf (compiled : CompiledSemanticV1) : CompileResult String :=
  digestHexV1 "compiled semantic" compiled.semanticDigest

end CompiledSemanticV1

/-- Shared post-Normalize success path and sole `CompiledSemanticV1` mint.
    It performs only identity/digest joins over the retained semantic carrier;
    the legacy alpha checker/lowering path is deliberately absent. -/
private def finishCompiledSemanticV1
    (source : ValidatedSourceV1) (carrier : SemanticProgramV1) :
    CompileResult CompiledSemanticV1 := do
  let data ← match validateSemanticProgramV1 carrier with
    | .ok value => pure value
    | .error error =>
        invalid s!"compiled semantic structure invalid ({renderSemanticWireErrorSummaryV1 error})"
  let components := data.qualifiedName.components.toArray
  let artifactProgramName := components.back!
  unless artifactProgramName == ProofForgeV2.Source.NameComponentV1.SourceNameComponentV1.raw source.program.name do
    return ← invalid
      "compiled semantic qualified-name final component diverges from source program name"
  let sourceDigest ← match sourceHashV1 source with
    | .ok digest => pure digest
    | .error error => invalid s!"compiled source digest unavailable: {error}"
  let semanticDigest ← match semanticHashV1 carrier with
    | .ok digest => pure digest
    | .error error =>
        invalid s!"compiled semantic digest unavailable ({renderSemanticWireErrorSummaryV1 error})"
  match validateDigest sourceDigest with
  | .ok () => pure ()
  | .error error => return ← invalid s!"compiled source digest invalid: {error}"
  match validateDigest semanticDigest with
  | .ok () => pure ()
  | .error error => return ← invalid s!"compiled semantic digest invalid: {error}"
  pure (CompiledSemanticV1.mk carrier artifactProgramName sourceDigest semanticDigest)

/-- Sole product compiler entry.

    Gate order:
    1. `normalizeProgramLocatedV1` preserves the complete located diagnostic
       bundle and returns one structure-valid `SemanticProgramV1`.
    2. `finishCompiledSemanticV1` binds canonical source/semantic identity and
       mints the private single-semantic compiler result.

    Normalize failure is returned byte-for-byte as one `DiagnosticBundleV1`.
    There is no unlocated fallback, second Typed/Semantic path, target-specific
    semantic branch, or alpha parity stage. -/
def compileProgramProductV1
    (source : ValidatedSourceV1) (inventory : OriginInventoryV1) :
    DiagnosticResultV1 CompiledSemanticV1 :=
  match normalizeProgramLocatedV1 source inventory with
  | .error bundle => .error bundle
  | .ok carrier =>
      match finishCompiledSemanticV1 source carrier with
      | .ok compiled => .ok compiled
      | .error error => .error (postNormalizeFailureBundleV1 error)

/-- Non-product compatibility compiler for hand-built `ValidatedSourceV1`
    fixtures. Product Loader/CLI must use `compileProgramProductV1` so located
    multi-error bundles are never truncated. Its successful carrier and identity
    mint are exactly the same as the product path. -/
def compileValidatedSourceV1 (source : ValidatedSourceV1) :
    CompileResult CompiledSemanticV1 := do
  match normalizeProgramV1 source with
  | .error error => .error (compileErrorFromNormalizeV1 error)
  | .ok carrier => finishCompiledSemanticV1 source carrier

end ProofForgeV2.Compiler

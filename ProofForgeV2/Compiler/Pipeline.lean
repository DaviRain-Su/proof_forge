import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Core.SemanticIR
import ProofForgeV2.Core.TypedV1
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Compiler

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.ValidatedSourceV1

/-- Compatibility compiler entry for hand-built alpha fixtures. Product source
loading uses `compileProgramProductV1`; this function does not participate in
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

/-- Map post-Normalize engineering failures into a public-safe product bundle.
    Residual alpha and dual-carrier failures never leak legacy `PF-SEM-*` codes. -/
private def postNormalizeFailureBundleV1 (err : CompileError) : DiagnosticBundleV1 :=
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

/-- Product dual-carrier: structure-valid SemanticProgramV1 retained from
    NormalizeV1 plus residual alpha Semantic.Program for target Plan/IR.
    Private constructor — sole mint site is `finishCompiledProgramV1`. -/
structure CompiledProgramV1 where
  private mk ::
  semanticV1 : SemanticProgramV1
  alphaResidual : Semantic.Program

namespace CompiledProgramV1

/-- Read-only SemanticProgramV1 accessor. -/
def semanticV1Of (c : CompiledProgramV1) : SemanticProgramV1 := c.semanticV1

/-- Read-only residual alpha Semantic.Program accessor. -/
def alphaResidualOf (c : CompiledProgramV1) : Semantic.Program := c.alphaResidual

end CompiledProgramV1

/-- Public read-only engineering bridge: closed S2 catalog id → residual alpha
    constructor. Shared by dual-carrier gate and engineering requirement resolver.
    Not SupportClaim / formal CAP resolution. -/
def mappedAlphaOfV1Id? (id : String) : Option ProgramRequirement :=
  if id == "state.persistent" then some .persistentState
  else if id == "value.checked-arithmetic" then some .checkedArithmetic
  else if id == "failure.atomic-rollback" then some .transactionalRollback
  else none

/-- Public read-only engineering bridge: residual alpha mapped constructor →
    S2 catalog id. Shared by dual-carrier gate and engineering requirement resolver. -/
def v1IdOfMappedAlpha? : ProgramRequirement → Option String
  | .persistentState => some "state.persistent"
  | .checkedArithmetic => some "value.checked-arithmetic"
  | .transactionalRollback => some "failure.atomic-rollback"
  | _ => none

private def countAlpha (reqs : Array ProgramRequirement) (want : ProgramRequirement) : Nat :=
  reqs.foldl (fun n r => if r == want then n + 1 else n) 0

private def countV1Ids (items : Array RequirementRequestV1) (want : String) : Nat :=
  items.foldl (fun n r => if r.id == want then n + 1 else n) 0

/-- Engineering dual-carrier consistency gate (test seam + compile gate).
    Not SupportClaim / claim resolution. Validates structure-valid
    SemanticProgramV1, then (known-ID → unconditional duplicate-id →
    version/digest/empty predicates) and exact bidirectional equality of S2
    catalog requirement requests with residual alpha mapped constructors:
      state.persistent ↔ .persistentState
      value.checked-arithmetic ↔ .checkedArithmetic
      failure.atomic-rollback ↔ .transactionalRollback
    Unmapped alpha constructors are outside this gate. Failures are
    `.invalidProgram` (product render `PF-SRC-INVALID`). Returns `Unit` only —
    never a capability and never mints `CompiledProgramV1`. -/
def validateDualCarrierConsistencyV1
    (semanticV1 : SemanticProgramV1) (alpha : Semantic.Program) :
    CompileResult Unit := do
  let data ← match validateSemanticProgramV1 semanticV1 with
    | .ok d => pure d
    | .error e =>
        invalid s!"dual-carrier: semantic structure invalid ({renderSemanticWireErrorSummaryV1 e})"
  let items := data.requirements.items
  -- Phase a: known-ID recognition (single unknown row precedes duplicate/version checks).
  for item in items do
    match mappedAlphaOfV1Id? item.id with
    | none =>
        return ← invalid s!"dual-carrier: unknown requirement id '{item.id}'"
    | some _ => pure ()
  -- Phase b: duplicate V1 requirement identity — unconditional after known-ID recognition.
  -- Same-id rows with distinct wire keys (version/digest) are structure-valid; report
  -- duplicate before validating any repeated row's version, digest, or predicates.
  for item in items do
    unless countV1Ids items item.id == 1 do
      return ← invalid s!"dual-carrier: duplicate V1 requirement id '{item.id}'"
  -- Phase c: per-row version, digest, empty predicates (only after uniqueness is settled).
  for item in items do
    unless item.version == s2RequirementVersionV1 do
      return ← invalid s!"dual-carrier: requirement '{item.id}' version mismatch"
    let expectedDigest ← match engineeringRequirementDigestV1 item.id with
      | .ok d => pure d
      | .error e => invalid s!"dual-carrier: requirement '{item.id}' digest unavailable: {e}"
    unless item.digest == expectedDigest do
      return ← invalid s!"dual-carrier: requirement '{item.id}' digest mismatch"
    unless item.predicates.isEmpty do
      return ← invalid s!"dual-carrier: requirement '{item.id}' must have empty predicates"
  -- Mapped alpha constructors: multiplicity 0 or 1; no duplicates among the three.
  for alphaReq in #[ProgramRequirement.persistentState,
      .checkedArithmetic, .transactionalRollback] do
    let n := countAlpha alpha.requirements alphaReq
    if n > 1 then
      return ← invalid s!"dual-carrier: duplicate alpha requirement '{alphaReq}'"
  -- Bidirectional set equality on mapped constructors only.
  for item in items do
    match mappedAlphaOfV1Id? item.id with
    | none => pure () -- unreachable after above
    | some alphaReq =>
        unless countAlpha alpha.requirements alphaReq == 1 do
          return ← invalid
            s!"dual-carrier: missing alpha requirement for V1 id '{item.id}'"
  for alphaReq in #[ProgramRequirement.persistentState,
      .checkedArithmetic, .transactionalRollback] do
    if countAlpha alpha.requirements alphaReq == 1 then
      match v1IdOfMappedAlpha? alphaReq with
      | none => pure ()
      | some id =>
          unless countV1Ids items id == 1 do
            return ← invalid
              s!"dual-carrier: missing V1 requirement for alpha '{alphaReq}'"
  pure ()

/-- Shared post-Normalize success path and sole `CompiledProgramV1` mint site.
    Both product-located and non-product compatibility entries must pass the
    same residual alpha lowering and dual-carrier consistency gate. -/
private def finishCompiledProgramV1
    (source : ValidatedSourceV1) (carrier : SemanticProgramV1) :
    CompileResult CompiledProgramV1 := do
  let typed ← Typed.checkV1 source
  let sourceHash ← semanticSourceHash source
  let alpha := Semantic.fromTyped sourceHash typed
  validateDualCarrierConsistencyV1 carrier alpha
  pure (CompiledProgramV1.mk carrier alpha)

/-- Sole product compiler entry.

    Gate order:
    1. `normalizeProgramLocatedV1` preserves the complete located diagnostic
       bundle and returns the retained structure-valid `SemanticProgramV1`.
    2. `finishCompiledProgramV1` performs residual alpha lowering, exact
       dual-carrier consistency, and the sole private carrier mint.

    Normalize failure is returned byte-for-byte as one `DiagnosticBundleV1`;
    post-Normalize engineering failures are mapped to public-safe diagnostics.
    There is no unlocated fallback or target-specific semantic branch. -/
def compileProgramProductV1
    (source : ValidatedSourceV1) (inv : OriginInventoryV1) :
    DiagnosticResultV1 CompiledProgramV1 :=
  match normalizeProgramLocatedV1 source inv with
  | .error bundle => .error bundle
  | .ok carrier =>
      match finishCompiledProgramV1 source carrier with
      | .ok compiled => .ok compiled
      | .error err => .error (postNormalizeFailureBundleV1 err)

/-- Non-product compatibility compiler for hand-built `ValidatedSourceV1`
    fixtures. Product Loader/CLI must use `compileProgramProductV1` so located
    multi-error bundles are never truncated. The successful dual-carrier path
    is identical to the product path. -/
def compileValidatedSourceV1 (source : ValidatedSourceV1) :
    CompileResult CompiledProgramV1 := do
  match normalizeProgramV1 source with
  | .error err => .error (compileErrorFromNormalizeV1 err)
  | .ok carrier => finishCompiledProgramV1 source carrier

end ProofForgeV2.Compiler

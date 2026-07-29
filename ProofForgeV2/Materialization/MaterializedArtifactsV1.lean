/-
  Engineering materialized-artifact carrier (D3/S7a).

  Private-constructor capability-bound product carrier returned by aggregate
  `Targets.materializeResult`. Sole mint: `mintMaterializedArtifactsV1`
  (called only from Registry after capability-gated target emit).

  Binds exact targetId / codegenProfileId / TargetKind from
  `ResolvedEngineeringBuildV1`, transitional residual-alpha program identity
  and residual source/semantic hex hashes (for exact v2alpha1 disk bytes),
  retained SemanticProgramV1 digest via `semanticHashV1`, retained source
  Digest parsed from the residual alpha bridge, and canonical ordered
  `Array OutputFile`.

  **Not** formal OutputSetV1 / proof-forge.output.v1 / BuildIdentity /
  SupportClaim / hermetic output. No public constructor, no caller overrides,
  no Inhabited, no partial carrier on failure.
-/
import ProofForgeV2.Materialization.Protocol
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Core.Common

namespace ProofForgeV2

open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Core.Common
open System

/-- Engineering materialized-artifact carrier (private sole mint).

    Field notes:
    * `residualProgramName` / `residualSourceHash` / `residualSemanticHash` are
      **transitional residual-alpha bridge** identities used for artifact path
      names and exact `proof-forge-output/v2alpha1` on-disk bytes.
    * `retainedSourceDigest` is the exact Digest form of the residual source
      hash bridge (parsed `sha256:` + 64 hex) — never Option/zero/fabricated.
    * `retainedSemanticDigest` is `semanticHashV1` of the dual-carrier retained
      `SemanticProgramV1` — fail closed if structure/hash unavailable.
    * `files` is the canonical ordered target-owned artifact set (bytes/names
      unchanged from target `buildFromCapability`). -/
structure MaterializedArtifactsV1 where
  private mk ::
  targetId : TargetId
  codegenProfileId : CodegenProfileId
  kind : TargetKind
  residualProgramName : String
  residualSourceHash : String
  residualSemanticHash : String
  retainedSourceDigest : Digest
  retainedSemanticDigest : Digest
  files : Array OutputFile
  deriving BEq, Repr

namespace MaterializedArtifactsV1

def targetIdOf (a : MaterializedArtifactsV1) : TargetId := a.targetId

def codegenProfileIdOf (a : MaterializedArtifactsV1) : CodegenProfileId :=
  a.codegenProfileId

def kindOf (a : MaterializedArtifactsV1) : TargetKind := a.kind

def residualProgramNameOf (a : MaterializedArtifactsV1) : String :=
  a.residualProgramName

/-- Transitional residual-alpha source hash hex (64 lowercase, no tag). -/
def residualSourceHashOf (a : MaterializedArtifactsV1) : String :=
  a.residualSourceHash

/-- Transitional residual-alpha semantic hash hex (64 lowercase, no tag). -/
def residualSemanticHashOf (a : MaterializedArtifactsV1) : String :=
  a.residualSemanticHash

def retainedSourceDigestOf (a : MaterializedArtifactsV1) : Digest :=
  a.retainedSourceDigest

def retainedSemanticDigestOf (a : MaterializedArtifactsV1) : Digest :=
  a.retainedSemanticDigest

def filesOf (a : MaterializedArtifactsV1) : Array OutputFile := a.files

end MaterializedArtifactsV1

private def isLowerHex (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

/-- Parse residual alpha 64-hex into Digest (`sha256:` + hex). Fail closed. -/
private def digestFromResidualHex (hex : String) (label : String) :
    CompileResult Digest := do
  unless hex.length == 64 && hex.all isLowerHex do
    throw <| .invalidProgram
      s!"materialized artifacts: {label} is not 64 lowercase hex"
  match parseDigest ("sha256:" ++ hex) with
  | .ok d => pure d
  | .error e =>
      throw <| .invalidProgram
        s!"materialized artifacts: {label} digest parse failed: {e}"

/-- Package-visible relative artifact path safety (mint + CLI emit dual defense).

    Nonempty relative path, UTF-8 length ≤240, no absolute / `..` / `.`
    components, no null / CR / LF. Sole definition — CLI must not reimplement. -/
def safeRelativeArtifactPathV1 (value : String) : Bool :=
  let path := FilePath.mk value
  !value.isEmpty && value.toUTF8.size <= 240 && !path.isAbsolute &&
    !(path.components.contains "..") && !(path.components.contains ".") &&
    !value.contains "\u0000" && !value.contains "\r" && !value.contains "\n"

/-- Validate ordered artifact paths: safety + uniqueness. Empty set rejected
    (all shipped targets emit ≥1 file). No partial carrier. -/
private def validateArtifactFiles (files : Array OutputFile) : CompileResult Unit := do
  if files.isEmpty then
    throw <| .invalidProgram
      "materialized artifacts: empty artifact set is noncanonical"
  let mut paths : Array String := #[]
  for file in files do
    unless safeRelativeArtifactPathV1 file.path do
      throw <| .invalidProgram
        s!"materialized artifacts: unsafe artifact path '{file.path}'"
    if paths.contains file.path then
      throw <| .invalidProgram
        s!"materialized artifacts: duplicate artifact path '{file.path}'"
    paths := paths.push file.path
  pure ()

/-- Sole mint of `MaterializedArtifactsV1`.

    Inputs: private engineering capability + residual target descriptor used for
    dispatch + ordered files from capability-gated target emit.

    Validates before `.mk`:
    1. selection ↔ descriptor identity parity (targetId / profile)
    2. closed kind wire label equals target id string
    3. residual alpha hex shape + retained source Digest parse/round-trip
    4. retained SemanticProgramV1 digest via `semanticHashV1` recompute
    5. independent residual re-extract after path gates (name/hash BEq)
    6. ordered path safety + uniqueness + nonempty

    Note: selection accessors on the same capability are pure projections of
    `selectionOf` — they are not independent drift gates. Live identity checks
    are selection↔descriptor, kind wire, residual re-bind, and path gates.

    Failure → CompileResult error only (`invalidProgram` / `registryInvalid`);
    never returns a partial carrier. No public constructor / overrides. -/
def mintMaterializedArtifactsV1
    (capability : ResolvedEngineeringBuildV1)
    (descriptor : TargetDescriptor)
    (files : Array OutputFile) :
    CompileResult MaterializedArtifactsV1 := do
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let residual := CompiledProgramV1.alphaResidualOf compiled
  -- Live identity: selection ↔ descriptor (dispatch row used by Registry).
  unless selection.targetId == descriptor.targetId do
    throw <| .registryInvalid
      "materialized artifacts: descriptor target diverges from capability selection"
  unless selection.codegenProfile == descriptor.codegenProfile do
    throw <| .registryInvalid
      "materialized artifacts: descriptor profile diverges from capability selection"
  -- Kind wire label must match target id string for closed implemented set.
  unless selection.kind.toString == selection.targetId.toString do
    throw <| .registryInvalid
      "materialized artifacts: kind wire diverges from target id"
  -- Transitional residual-alpha hashes must be well-formed 64 lowercase hex.
  unless residual.sourceHash.length == 64 && residual.sourceHash.all isLowerHex do
    throw <| .invalidProgram
      "materialized artifacts: residual sourceHash is not 64 lowercase hex"
  unless residual.semanticHash.length == 64 && residual.semanticHash.all isLowerHex do
    throw <| .invalidProgram
      "materialized artifacts: residual semanticHash is not 64 lowercase hex"
  let retainedSource ← digestFromResidualHex residual.sourceHash "residual sourceHash"
  -- Retained source Digest must re-render to the residual hex bridge.
  match renderDigest retainedSource with
  | .ok wire =>
      unless wire == "sha256:" ++ residual.sourceHash do
        throw <| .invalidProgram
          "materialized artifacts: retained source Digest diverges from residual hex"
  | .error e =>
      throw <| .invalidProgram
        s!"materialized artifacts: retained source Digest render failed: {e}"
  -- Retained SemanticProgramV1 digest — exact recompute, fail closed.
  let semanticV1 := CompiledProgramV1.semanticV1Of compiled
  let retainedSemantic ← match semanticHashV1 semanticV1 with
    | .ok d => pure d
    | .error e =>
        throw <| .invalidProgram
          s!"materialized artifacts: retained SemanticProgramV1 digest unavailable ({repr e})"
  validateArtifactFiles files
  -- Independent residual re-extract after path gates (dual-carrier re-bind).
  let residualAgain := CompiledProgramV1.alphaResidualOf compiled
  unless residualAgain.name == residual.name &&
      residualAgain.sourceHash == residual.sourceHash &&
      residualAgain.semanticHash == residual.semanticHash do
    throw <| .invalidProgram
      "materialized artifacts: residual alpha identity drifted during mint"
  pure (MaterializedArtifactsV1.mk
    selection.targetId
    selection.codegenProfile
    selection.kind
    residual.name
    residual.sourceHash
    residual.semanticHash
    retainedSource
    retainedSemantic
    files)

end ProofForgeV2

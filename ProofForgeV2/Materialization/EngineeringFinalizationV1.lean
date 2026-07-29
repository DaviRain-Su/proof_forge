/-
  Engineering finalization carrier (D3/S7b).

  Private-constructor capability-bound product carrier returned by aggregate
  `Targets.finalizeMaterializedArtifactsV1`. Sole mint: `mintFinalizedArtifactsV1`
  (package-visible; called only after target-owned finalization adapters write
  any tool-produced extras into staging).

  Binds `ResolvedEngineeringBuildV1` + pure-base `MaterializedArtifactsV1` to
  deployable, ordered finalized extra-file relative paths, and exact evidence
  note. Base target-core files remain on `MaterializedArtifactsV1`.

  **Not** formal OutputSetV1 / proof-forge.output.v1 / BuildIdentity /
  SupportClaim / ToolchainIdentity / hermetic finalizer. No public constructor,
  no caller deployability/note override of identity, no Inhabited, no partial
  carrier on failure.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2

open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1

/-- Intermediate finalization data produced by target-owned adapters before sole
    `FinalizedArtifactsV1` mint. Not a product carrier; no private ctor. -/
structure EngineeringFinalizationDraftV1 where
  deployable : Bool
  extraFiles : Array String
  evidenceNote : String
  deriving BEq, Repr

/-- Engineering finalized-artifact carrier (private sole mint).

    Field notes:
    * `capability` / `artifacts` are the exact build + base-file carriers that
      finalization was authorized against.
    * `deployable` and `evidenceNote` are target-owned finalization authority
      (tool success / non-deployable maturity notes) — not CLI overrides.
    * `extraFiles` is the ordered list of finalized extra relative paths written
      into staging by adapters (e.g. `.bin` / `.wasm`); empty when zero tools. -/
structure FinalizedArtifactsV1 where
  private mk ::
  capability : ResolvedEngineeringBuildV1
  artifacts : MaterializedArtifactsV1
  deployable : Bool
  extraFiles : Array String
  evidenceNote : String

namespace FinalizedArtifactsV1

def capabilityOf (f : FinalizedArtifactsV1) : ResolvedEngineeringBuildV1 :=
  f.capability

def artifactsOf (f : FinalizedArtifactsV1) : MaterializedArtifactsV1 :=
  f.artifacts

def deployableOf (f : FinalizedArtifactsV1) : Bool := f.deployable

def extraFilesOf (f : FinalizedArtifactsV1) : Array String := f.extraFiles

def evidenceNoteOf (f : FinalizedArtifactsV1) : String := f.evidenceNote

end FinalizedArtifactsV1

/-- Validate ordered extra paths: safety + uniqueness vs each other and base. -/
private def validateExtraFiles
    (base : Array OutputFile) (extraFiles : Array String) : CompileResult Unit := do
  let mut paths : Array String := base.map (·.path)
  for path in extraFiles do
    unless safeRelativeArtifactPathV1 path do
      throw <| .invalidProgram
        s!"finalized artifacts: unsafe extra path '{path}'"
    if paths.contains path then
      throw <| .invalidProgram
        s!"finalized artifacts: duplicate extra path '{path}'"
    paths := paths.push path
  pure ()

/-- Sole mint of `FinalizedArtifactsV1`.

    Validates before `.mk`:
    1. capability ↔ artifacts targetId / codegenProfileId / kind exact
    2. residual program name + residual source/semantic hex exact bind
    3. retained digests still present on artifacts (non-empty re-projection)
    4. extra paths via sole `safeRelativeArtifactPathV1`, unique vs base and each other

    Failure → CompileResult error only; never returns a partial carrier.
    No public constructor / no CLI deployability-note authority. -/
def mintFinalizedArtifactsV1
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (draft : EngineeringFinalizationDraftV1) :
    CompileResult FinalizedArtifactsV1 := do
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let residual := CompiledProgramV1.alphaResidualOf compiled
  -- capability ↔ artifacts identity
  unless MaterializedArtifactsV1.targetIdOf artifacts == selection.targetId do
    throw <| .registryInvalid
      "finalized artifacts: artifact target diverges from capability"
  unless MaterializedArtifactsV1.codegenProfileIdOf artifacts == selection.codegenProfile do
    throw <| .registryInvalid
      "finalized artifacts: artifact profile diverges from capability"
  unless MaterializedArtifactsV1.kindOf artifacts == selection.kind do
    throw <| .registryInvalid
      "finalized artifacts: artifact kind diverges from capability"
  -- residual program / hash bind
  unless MaterializedArtifactsV1.residualProgramNameOf artifacts == residual.name do
    throw <| .invalidProgram
      "finalized artifacts: residual program name diverges from capability"
  unless MaterializedArtifactsV1.residualSourceHashOf artifacts == residual.sourceHash do
    throw <| .invalidProgram
      "finalized artifacts: residual sourceHash diverges from capability"
  unless MaterializedArtifactsV1.residualSemanticHashOf artifacts == residual.semanticHash do
    throw <| .invalidProgram
      "finalized artifacts: residual semanticHash diverges from capability"
  -- retained digests must still project (mint already checked; re-bind defense)
  let _ := MaterializedArtifactsV1.retainedSourceDigestOf artifacts
  let _ := MaterializedArtifactsV1.retainedSemanticDigestOf artifacts
  validateExtraFiles (MaterializedArtifactsV1.filesOf artifacts) draft.extraFiles
  -- Independent residual re-extract after path gates.
  let residualAgain := CompiledProgramV1.alphaResidualOf compiled
  unless residualAgain.name == residual.name &&
      residualAgain.sourceHash == residual.sourceHash &&
      residualAgain.semanticHash == residual.semanticHash do
    throw <| .invalidProgram
      "finalized artifacts: residual alpha identity drifted during mint"
  pure (FinalizedArtifactsV1.mk
    capability
    artifacts
    draft.deployable
    draft.extraFiles
    draft.evidenceNote)

end ProofForgeV2

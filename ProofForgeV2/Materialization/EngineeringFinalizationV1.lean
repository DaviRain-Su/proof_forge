/-
  Engineering finalization carrier (D3/S7b).

  Private-constructor capability-bound product carrier returned by aggregate
  `Targets.finalizeMaterializedArtifactsV1`. Sole mint:
  `mintFinalizedArtifactsV1` after target-owned finalization adapters write any
  tool-produced extras into staging.

  It binds the exact build capability and pure-base MaterializedArtifactsV1 to
  deployability, ordered extra paths, and an evidence note. Not formal
  OutputSetV1 / BuildIdentity / SupportClaim / ToolchainIdentity / hermetic
  finalization.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2

open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1

structure EngineeringFinalizationDraftV1 where
  deployable : Bool
  extraFiles : Array String
  evidenceNote : String
  deriving BEq, Repr

structure FinalizedArtifactsV1 where
  private mk ::
  capability : ResolvedEngineeringBuildV1
  artifacts : MaterializedArtifactsV1
  deployable : Bool
  extraFiles : Array String
  evidenceNote : String

namespace FinalizedArtifactsV1

def capabilityOf (finalized : FinalizedArtifactsV1) : ResolvedEngineeringBuildV1 :=
  finalized.capability

def artifactsOf (finalized : FinalizedArtifactsV1) : MaterializedArtifactsV1 :=
  finalized.artifacts

def deployableOf (finalized : FinalizedArtifactsV1) : Bool := finalized.deployable

def extraFilesOf (finalized : FinalizedArtifactsV1) : Array String :=
  finalized.extraFiles

def evidenceNoteOf (finalized : FinalizedArtifactsV1) : String :=
  finalized.evidenceNote

end FinalizedArtifactsV1

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

/-- Sole mint of `FinalizedArtifactsV1`.

    Validates capability↔artifact target/profile/kind plus the non-alpha
    program/source/semantic identity and extra path closure before minting. -/
def mintFinalizedArtifactsV1
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (draft : EngineeringFinalizationDraftV1) :
    CompileResult FinalizedArtifactsV1 := do
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  unless MaterializedArtifactsV1.targetIdOf artifacts == selection.targetId do
    throw <| .registryInvalid
      "finalized artifacts: artifact target diverges from capability"
  unless MaterializedArtifactsV1.codegenProfileIdOf artifacts == selection.codegenProfile do
    throw <| .registryInvalid
      "finalized artifacts: artifact profile diverges from capability"
  unless MaterializedArtifactsV1.kindOf artifacts == selection.kind do
    throw <| .registryInvalid
      "finalized artifacts: artifact kind diverges from capability"
  unless MaterializedArtifactsV1.artifactProgramNameOf artifacts ==
      CompiledSemanticV1.artifactProgramNameOf compiled do
    throw <| .invalidProgram
      "finalized artifacts: artifact program name diverges from capability"
  unless MaterializedArtifactsV1.sourceDigestOf artifacts ==
      CompiledSemanticV1.sourceDigestOf compiled do
    throw <| .invalidProgram
      "finalized artifacts: source digest diverges from capability"
  unless MaterializedArtifactsV1.semanticDigestOf artifacts ==
      CompiledSemanticV1.semanticDigestOf compiled do
    throw <| .invalidProgram
      "finalized artifacts: semantic digest diverges from capability"
  validateExtraFiles (MaterializedArtifactsV1.filesOf artifacts) draft.extraFiles
  pure (FinalizedArtifactsV1.mk
    capability
    artifacts
    draft.deployable
    draft.extraFiles
    draft.evidenceNote)

end ProofForgeV2

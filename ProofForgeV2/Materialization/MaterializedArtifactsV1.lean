/-
  Engineering materialized-artifact carrier (D3/S7a + M3b BuildIdentity bind).

  Private-constructor capability-bound product carrier returned by aggregate
  `Targets.materializeResult`. Sole mint: `mintMaterializedArtifactsV1` after
  capability-gated target emission.

  It binds exact target/profile/kind, the non-alpha compiled artifact name,
  canonical ProgramV1 source digest, canonical SemanticProgramV1 digest,
  the engineering BuildIdentity chain (M3b), and ordered output files. Hash
  strings are derived only at transitional rendering boundaries; they are not
  stored as a second identity truth.

  Not formal OutputSetV1 / formal BuildIdentity / formal SupportClaim /
  hermetic output. No public constructor, caller overrides, Inhabited
  instance, or partial carrier on failure. Engineering BuildIdentity is
  bound into MaterializedArtifactsV1 and published via M3c
  `EngineeringOutputSetV1` (engineering `proof-forge.output.v1` only).
-/
import ProofForgeV2.Materialization.Protocol
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EngineeringBuildIdentityV1
import ProofForgeV2.Targets.SupportClaimV1
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Core.Common

namespace ProofForgeV2

open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EngineeringBuildIdentityV1
open ProofForgeV2.Targets.SupportClaimV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Core.Common
open System

structure MaterializedArtifactsV1 where
  private mk ::
  targetId : TargetId
  codegenProfileId : CodegenProfileId
  kind : TargetKind
  artifactProgramName : String
  sourceDigest : Digest
  semanticDigest : Digest
  buildIdentity : EngineeringBuildIdentityV1
  files : Array OutputFile
  deriving Repr

namespace MaterializedArtifactsV1

def targetIdOf (artifacts : MaterializedArtifactsV1) : TargetId := artifacts.targetId

def codegenProfileIdOf (artifacts : MaterializedArtifactsV1) : CodegenProfileId :=
  artifacts.codegenProfileId

def kindOf (artifacts : MaterializedArtifactsV1) : TargetKind := artifacts.kind

def artifactProgramNameOf (artifacts : MaterializedArtifactsV1) : String :=
  artifacts.artifactProgramName

def sourceDigestOf (artifacts : MaterializedArtifactsV1) : Digest :=
  artifacts.sourceDigest

def semanticDigestOf (artifacts : MaterializedArtifactsV1) : Digest :=
  artifacts.semanticDigest

def buildIdentityOf (artifacts : MaterializedArtifactsV1) : EngineeringBuildIdentityV1 :=
  artifacts.buildIdentity

def filesOf (artifacts : MaterializedArtifactsV1) : Array OutputFile := artifacts.files

/-- Exact field equality (digests + nested engineering BuildIdentity via beq). -/
def beq (a b : MaterializedArtifactsV1) : Bool :=
  a.targetId == b.targetId &&
  a.codegenProfileId == b.codegenProfileId &&
  a.kind == b.kind &&
  a.artifactProgramName == b.artifactProgramName &&
  a.sourceDigest.algorithm == b.sourceDigest.algorithm &&
  a.sourceDigest.bytes == b.sourceDigest.bytes &&
  a.semanticDigest.algorithm == b.semanticDigest.algorithm &&
  a.semanticDigest.bytes == b.semanticDigest.bytes &&
  EngineeringBuildIdentityV1.beq a.buildIdentity b.buildIdentity &&
  a.files == b.files

instance : BEq MaterializedArtifactsV1 := ⟨beq⟩

end MaterializedArtifactsV1

private def validateBoundDigestV1 (label : String) (digest : Digest) : CompileResult Unit :=
  match validateDigest digest with
  | .ok () => pure ()
  | .error error =>
      throw <| .invalidProgram s!"materialized artifacts: {label} is invalid: {error}"

/-- Package-visible relative artifact path safety (mint + CLI emit dual defense). -/
def safeRelativeArtifactPathV1 (value : String) : Bool :=
  let path := FilePath.mk value
  !value.isEmpty && value.toUTF8.size <= 240 && !path.isAbsolute &&
    !(path.components.contains "..") && !(path.components.contains ".") &&
    !value.contains "\u0000" && !value.contains "\r" && !value.contains "\n"

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

/-- Sole mint of `MaterializedArtifactsV1`.

    Validates selection↔descriptor identity, closed kind wire, compiled
    name/digests, independent retained-semantic name/hash recomputation,
    engineering BuildIdentity chain binding, and ordered file path closure
    before minting. -/
def mintMaterializedArtifactsV1
    (capability : ResolvedEngineeringBuildV1)
    (descriptor : TargetDescriptor)
    (files : Array OutputFile)
    (planDigest : Digest) :
    CompileResult MaterializedArtifactsV1 := do
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let supportClaim := ResolvedEngineeringBuildV1.supportClaimOf capability
  unless selection.targetId == descriptor.targetId do
    throw <| .registryInvalid
      "materialized artifacts: descriptor target diverges from capability selection"
  -- Residual descriptor binds the default profile; multi-profile targets accept
  -- additional registered profiles (see DescriptorDataV1.acceptsCodegenProfile).
  unless acceptsCodegenProfile descriptor selection.codegenProfile do
    throw <| .registryInvalid
      "materialized artifacts: descriptor profile diverges from capability selection"
  unless selection.kind.toString == selection.targetId.toString do
    throw <| .registryInvalid
      "materialized artifacts: kind wire diverges from target id"
  let artifactProgramName := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
  let semanticDigest := CompiledSemanticV1.semanticDigestOf compiled
  validateBoundDigestV1 "source digest" sourceDigest
  validateBoundDigestV1 "semantic digest" semanticDigest
  let semanticV1 := CompiledSemanticV1.semanticV1Of compiled
  let data ← match validateSemanticProgramV1 semanticV1 with
    | .ok value => pure value
    | .error error =>
        throw <| .invalidProgram
          s!"materialized artifacts: retained SemanticProgramV1 invalid ({repr error})"
  unless data.qualifiedName.components.toArray.back! == artifactProgramName do
    throw <| .invalidProgram
      "materialized artifacts: semantic program name diverges from compiled identity"
  let recomputedSemantic ← match semanticHashV1 semanticV1 with
    | .ok digest => pure digest
    | .error error =>
        throw <| .invalidProgram
          s!"materialized artifacts: semantic digest unavailable ({repr error})"
  unless recomputedSemantic == semanticDigest do
    throw <| .invalidProgram
      "materialized artifacts: semantic digest diverges from compiled identity"
  -- Claim binding must already match selection (resolver gate); re-check here.
  unless EngineeringSupportClaimV1.targetIdOf supportClaim == selection.targetId do
    throw <| .registryInvalid
      "materialized artifacts: support claim target diverges from capability"
  unless EngineeringSupportClaimV1.codegenProfileOf supportClaim == selection.codegenProfile do
    throw <| .registryInvalid
      "materialized artifacts: support claim profile diverges from capability"
  let engineeringRegistryRootDigest :=
    EngineeringSupportClaimV1.engineeringRegistryRootDigestOf supportClaim
  let supportClaimDigest := EngineeringSupportClaimV1.claimDigestOf supportClaim
  validateBoundDigestV1 "engineering registry root digest" engineeringRegistryRootDigest
  validateBoundDigestV1 "support claim digest" supportClaimDigest
  validateBoundDigestV1 "plan digest" planDigest
  let buildIdentity ← match mintEngineeringBuildIdentityV1
      selection.targetId
      selection.codegenProfile
      artifactProgramName
      sourceDigest
      semanticDigest
      engineeringRegistryRootDigest
      supportClaimDigest
      planDigest with
    | .ok identity => pure identity
    | .error error =>
        throw <| .invalidProgram
          s!"materialized artifacts: engineering build identity mint failed: {error}"
  validateArtifactFiles files
  pure (MaterializedArtifactsV1.mk
    selection.targetId
    selection.codegenProfile
    selection.kind
    artifactProgramName
    sourceDigest
    semanticDigest
    buildIdentity
    files)

end ProofForgeV2

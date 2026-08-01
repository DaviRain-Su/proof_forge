/-
  Engineering OutputSet carrier (M3c / Wave formal-identity third slice).

  Private-constructor on-disk identity for one finalized engineering publish:

    outputSetDigest = domainSeparatedSha256(
      "pf.output-set.engineering.v1",
      canonicalOutputSetBytes)

  Canonical preimage (length-framed, deterministic):
    String(schemaVersion)                 -- "proof-forge.output.v1"
    String(targetId)
    String(codegenProfile)
    String(artifactProgramName)
    u32le(fileCount)
    String(path) × count                  -- base then extras, source order
    String(renderDigest(sourceDigest))
    String(renderDigest(semanticDigest))
    String(renderDigest(engineeringRegistryRootDigest))
    String(renderDigest(supportClaimDigest))
    String(renderDigest(buildIdentityDigest))
    String("true" | "false")              -- deployable

  Sole mint: `mintEngineeringOutputSetV1` from private-ctor
  `FinalizedArtifactsV1` (capability + MaterializedArtifactsV1 + extras).
  On-disk JSON renderer: `renderEngineeringOutputSetManifestV1`
  (schema `"proof-forge.output.v1"`). Evidence sidecar remains a separate
  publisher render of finalized note + digests.

  **Engineering only — not formal OutputSetV1 / TASK-D3-05:**
  * Domain is `pf.output-set.engineering.v1` (engineering-only suffix).
  * Structure name is `EngineeringOutputSetV1` (not public `OutputSet`).
  * Mint name is `mintEngineeringOutputSetV1` (not `makeOutput`).
  * Renderer is `renderEngineeringOutputSetManifestV1` (not `manifestJson`).
  * No public `validateOutputSet`. Sidecar leaf names remain
    `evidence.json` / `manifest.json` (S7c exact disk closure unchanged).
  * Not formal proof-forge.output.v1 product completion / hermetic publish.
-/
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Targets.EngineeringBuildIdentityV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.SupportClaimV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common

namespace ProofForgeV2

open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.EngineeringBuildIdentityV1
open ProofForgeV2.Targets.SupportClaimV1

/-- On-disk engineering schema string (not formal OutputSetV1 completion). -/
def engineeringOutputSchemaVersionV1 : String :=
  "proof-forge.output.v1"

/-- Domain tag for the **engineering** output-set digest. -/
def engineeringOutputSetDomainV1 : String :=
  "pf.output-set.engineering.v1"

/-- One engineering output set. Private constructor; sole mint via
    `mintEngineeringOutputSetV1`. -/
structure EngineeringOutputSetV1 where
  private mk ::
  targetId : TargetId
  codegenProfile : CodegenProfileId
  artifactProgramName : String
  /-- Ordered artifact paths (base files then finalized extras; no sidecars). -/
  files : Array String
  sourceDigest : Digest
  semanticDigest : Digest
  engineeringRegistryRootDigest : Digest
  supportClaimDigest : Digest
  buildIdentityDigest : Digest
  deployable : Bool
  evidenceNote : String
  /-- Domain-separated digest of the canonical output-set preimage. -/
  outputSetDigest : Digest
  deriving Repr

namespace EngineeringOutputSetV1

def targetIdOf (o : EngineeringOutputSetV1) : TargetId := o.targetId

def codegenProfileOf (o : EngineeringOutputSetV1) : CodegenProfileId :=
  o.codegenProfile

def artifactProgramNameOf (o : EngineeringOutputSetV1) : String :=
  o.artifactProgramName

def filesOf (o : EngineeringOutputSetV1) : Array String := o.files

def sourceDigestOf (o : EngineeringOutputSetV1) : Digest := o.sourceDigest

def semanticDigestOf (o : EngineeringOutputSetV1) : Digest := o.semanticDigest

def engineeringRegistryRootDigestOf (o : EngineeringOutputSetV1) : Digest :=
  o.engineeringRegistryRootDigest

def supportClaimDigestOf (o : EngineeringOutputSetV1) : Digest :=
  o.supportClaimDigest

def buildIdentityDigestOf (o : EngineeringOutputSetV1) : Digest :=
  o.buildIdentityDigest

def deployableOf (o : EngineeringOutputSetV1) : Bool := o.deployable

def evidenceNoteOf (o : EngineeringOutputSetV1) : String := o.evidenceNote

def outputSetDigestOf (o : EngineeringOutputSetV1) : Digest := o.outputSetDigest

/-- Exact field equality (digests by algorithm + raw bytes). -/
def beq (a b : EngineeringOutputSetV1) : Bool :=
  a.targetId == b.targetId &&
  a.codegenProfile == b.codegenProfile &&
  a.artifactProgramName == b.artifactProgramName &&
  a.files == b.files &&
  a.sourceDigest.algorithm == b.sourceDigest.algorithm &&
  a.sourceDigest.bytes == b.sourceDigest.bytes &&
  a.semanticDigest.algorithm == b.semanticDigest.algorithm &&
  a.semanticDigest.bytes == b.semanticDigest.bytes &&
  a.engineeringRegistryRootDigest.algorithm == b.engineeringRegistryRootDigest.algorithm &&
  a.engineeringRegistryRootDigest.bytes == b.engineeringRegistryRootDigest.bytes &&
  a.supportClaimDigest.algorithm == b.supportClaimDigest.algorithm &&
  a.supportClaimDigest.bytes == b.supportClaimDigest.bytes &&
  a.buildIdentityDigest.algorithm == b.buildIdentityDigest.algorithm &&
  a.buildIdentityDigest.bytes == b.buildIdentityDigest.bytes &&
  a.deployable == b.deployable &&
  a.evidenceNote == b.evidenceNote &&
  a.outputSetDigest.algorithm == b.outputSetDigest.algorithm &&
  a.outputSetDigest.bytes == b.outputSetDigest.bytes

instance : BEq EngineeringOutputSetV1 := ⟨beq⟩

end EngineeringOutputSetV1

-- ---------------------------------------------------------------------------
-- Canonical length-framed preimage
-- ---------------------------------------------------------------------------

private def encodeU32le (value : UInt32) : ByteArray :=
  let v := value.toNat
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  ((((ByteArray.empty.push b0).push b1).push b2).push b3)

private def encodeNatAsU32le (count : Nat) : Except String ByteArray := do
  unless count ≤ UInt32.size - 1 do
    throw "output set u32 length is not representable"
  pure (encodeU32le (UInt32.ofNat count))

private def encodeString (value : String) : Except String ByteArray := do
  let raw := value.toUTF8
  let header ← encodeNatAsU32le raw.size
  pure (header.append raw)

private def encodeDigestWire (digest : Digest) : Except String ByteArray := do
  let wire ← renderDigest digest
  encodeString wire

private def validateBoundDigest (label : String) (digest : Digest) : Except String Unit :=
  match validateDigest digest with
  | .ok () => pure ()
  | .error e => throw s!"output set {label} is invalid: {e}"

/-- Canonical engineering output-set preimage bytes. -/
def encodeEngineeringOutputSetBytesV1
    (targetId : TargetId)
    (codegenProfile : CodegenProfileId)
    (artifactProgramName : String)
    (files : Array String)
    (sourceDigest : Digest)
    (semanticDigest : Digest)
    (engineeringRegistryRootDigest : Digest)
    (supportClaimDigest : Digest)
    (buildIdentityDigest : Digest)
    (deployable : Bool) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString engineeringOutputSchemaVersionV1)
  out := out.append (← encodeString targetId.toString)
  out := out.append (← encodeString codegenProfile.toString)
  out := out.append (← encodeString artifactProgramName)
  out := out.append (← encodeNatAsU32le files.size)
  for path in files do
    out := out.append (← encodeString path)
  out := out.append (← encodeDigestWire sourceDigest)
  out := out.append (← encodeDigestWire semanticDigest)
  out := out.append (← encodeDigestWire engineeringRegistryRootDigest)
  out := out.append (← encodeDigestWire supportClaimDigest)
  out := out.append (← encodeDigestWire buildIdentityDigest)
  out := out.append (← encodeString (if deployable then "true" else "false"))
  pure out

/-- Compute outputSetDigest for the given binding fields. -/
def engineeringOutputSetDigestV1
    (targetId : TargetId)
    (codegenProfile : CodegenProfileId)
    (artifactProgramName : String)
    (files : Array String)
    (sourceDigest : Digest)
    (semanticDigest : Digest)
    (engineeringRegistryRootDigest : Digest)
    (supportClaimDigest : Digest)
    (buildIdentityDigest : Digest)
    (deployable : Bool) : Except String Digest := do
  let bytes ← encodeEngineeringOutputSetBytesV1
    targetId codegenProfile artifactProgramName files
    sourceDigest semanticDigest
    engineeringRegistryRootDigest supportClaimDigest
    buildIdentityDigest deployable
  domainSeparatedSha256 engineeringOutputSetDomainV1 bytes

private def digestHexExcept (label : String) (digest : Digest) : Except String String := do
  let rendered ← renderDigest digest
  unless rendered.startsWith "sha256:" do
    throw s!"output set {label} digest is not sha256"
  let suffix := (rendered.drop 7).toString
  unless suffix.length == 64 do
    throw s!"output set {label} digest has invalid length"
  pure suffix

/-- Sole mint of `EngineeringOutputSetV1`.

    Consumes private `FinalizedArtifactsV1` only. Re-binds target/profile/
    digests/files from the finalized capability + materialization + extras,
    recomputes `outputSetDigest`, and fail-closes on any identity divergence. -/
def mintEngineeringOutputSetV1
    (finalized : FinalizedArtifactsV1) :
    CompileResult EngineeringOutputSetV1 := do
  let capability := FinalizedArtifactsV1.capabilityOf finalized
  let artifacts := FinalizedArtifactsV1.artifactsOf finalized
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  let claim := ResolvedEngineeringBuildV1.supportClaimOf capability
  let identity := MaterializedArtifactsV1.buildIdentityOf artifacts
  unless MaterializedArtifactsV1.targetIdOf artifacts == selection.targetId do
    throw <| .registryInvalid
      "output set: artifact target diverges from capability"
  unless MaterializedArtifactsV1.codegenProfileIdOf artifacts == selection.codegenProfile do
    throw <| .registryInvalid
      "output set: artifact profile diverges from capability"
  unless EngineeringBuildIdentityV1.targetIdOf identity == selection.targetId do
    throw <| .registryInvalid
      "output set: build identity target diverges from capability"
  unless EngineeringBuildIdentityV1.codegenProfileOf identity == selection.codegenProfile do
    throw <| .registryInvalid
      "output set: build identity profile diverges from capability"
  unless EngineeringSupportClaimV1.targetIdOf claim == selection.targetId do
    throw <| .registryInvalid
      "output set: support claim target diverges from capability"
  unless EngineeringSupportClaimV1.codegenProfileOf claim == selection.codegenProfile do
    throw <| .registryInvalid
      "output set: support claim profile diverges from capability"
  let artifactProgramName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  unless EngineeringBuildIdentityV1.artifactNameOf identity == artifactProgramName do
    throw <| .invalidProgram
      "output set: build identity artifact name diverges"
  let sourceDigest := MaterializedArtifactsV1.sourceDigestOf artifacts
  let semanticDigest := MaterializedArtifactsV1.semanticDigestOf artifacts
  unless EngineeringBuildIdentityV1.sourceDigestOf identity == sourceDigest do
    throw <| .invalidProgram
      "output set: build identity source digest diverges"
  unless EngineeringBuildIdentityV1.semanticDigestOf identity == semanticDigest do
    throw <| .invalidProgram
      "output set: build identity semantic digest diverges"
  let engineeringRegistryRootDigest :=
    EngineeringBuildIdentityV1.engineeringRegistryRootDigestOf identity
  let supportClaimDigest :=
    EngineeringBuildIdentityV1.supportClaimDigestOf identity
  unless EngineeringSupportClaimV1.engineeringRegistryRootDigestOf claim ==
      engineeringRegistryRootDigest do
    throw <| .invalidProgram
      "output set: claim registry root diverges from build identity"
  unless EngineeringSupportClaimV1.claimDigestOf claim == supportClaimDigest do
    throw <| .invalidProgram
      "output set: claim digest diverges from build identity"
  let buildIdentityDigest := EngineeringBuildIdentityV1.identityDigestOf identity
  let basePaths :=
    (MaterializedArtifactsV1.filesOf artifacts).map (·.path)
  let files := basePaths ++ FinalizedArtifactsV1.extraFilesOf finalized
  if files.isEmpty then
    throw <| .invalidProgram "output set: empty file list is noncanonical"
  let mut seen : Array String := #[]
  for path in files do
    unless safeRelativeArtifactPathV1 path do
      throw <| .invalidProgram s!"output set: unsafe artifact path '{path}'"
    if seen.contains path then
      throw <| .invalidProgram s!"output set: duplicate artifact path '{path}'"
    seen := seen.push path
  match validateBoundDigest "source digest" sourceDigest with
  | .ok () => pure ()
  | .error e => throw <| .invalidProgram e
  match validateBoundDigest "semantic digest" semanticDigest with
  | .ok () => pure ()
  | .error e => throw <| .invalidProgram e
  match validateBoundDigest "engineering registry root digest" engineeringRegistryRootDigest with
  | .ok () => pure ()
  | .error e => throw <| .invalidProgram e
  match validateBoundDigest "support claim digest" supportClaimDigest with
  | .ok () => pure ()
  | .error e => throw <| .invalidProgram e
  match validateBoundDigest "build identity digest" buildIdentityDigest with
  | .ok () => pure ()
  | .error e => throw <| .invalidProgram e
  -- Recompute build-identity digest from nested fields (tamper dual-defense).
  let recomputedIdentity ← match engineeringBuildIdentityDigestV1
      selection.targetId
      selection.codegenProfile
      artifactProgramName
      sourceDigest
      semanticDigest
      engineeringRegistryRootDigest
      supportClaimDigest with
    | .ok d => pure d
    | .error e =>
        throw <| .invalidProgram s!"output set: build identity recompute failed: {e}"
  unless recomputedIdentity == buildIdentityDigest do
    throw <| .invalidProgram
      "output set: build identity digest diverges from recomputed preimage"
  let deployable := FinalizedArtifactsV1.deployableOf finalized
  let evidenceNote := FinalizedArtifactsV1.evidenceNoteOf finalized
  let outputSetDigest ← match engineeringOutputSetDigestV1
      selection.targetId
      selection.codegenProfile
      artifactProgramName
      files
      sourceDigest
      semanticDigest
      engineeringRegistryRootDigest
      supportClaimDigest
      buildIdentityDigest
      deployable with
    | .ok d => pure d
    | .error e =>
        throw <| .invalidProgram s!"output set: digest mint failed: {e}"
  pure (EngineeringOutputSetV1.mk
    selection.targetId
    selection.codegenProfile
    artifactProgramName
    files
    sourceDigest
    semanticDigest
    engineeringRegistryRootDigest
    supportClaimDigest
    buildIdentityDigest
    deployable
    evidenceNote
    outputSetDigest)

/-- Deterministic engineering on-disk manifest JSON for `proof-forge.output.v1`.

    Digests are bare 64-char lowercase hex (same presentation as the retired
    v2alpha1 `sourceHash`/`semanticHash` fields). Sidecar leaf names are not
    listed in `files`. Not formal OutputSetV1 / PF-JCS product wire. -/
def renderEngineeringOutputSetManifestV1 (outputSet : EngineeringOutputSetV1) :
    Except String String := do
  let sourceHash ← digestHexExcept "source" outputSet.sourceDigest
  let semanticHash ← digestHexExcept "semantic" outputSet.semanticDigest
  let registryRoot ←
    digestHexExcept "engineering registry root" outputSet.engineeringRegistryRootDigest
  let claimHash ← digestHexExcept "support claim" outputSet.supportClaimDigest
  let identityHash ← digestHexExcept "build identity" outputSet.buildIdentityDigest
  let setHash ← digestHexExcept "output set" outputSet.outputSetDigest
  let files := String.intercalate "," <|
    outputSet.files.toList.map fun path => s!"\"{Targets.escapeJson path}\""
  let deployable := if outputSet.deployable then "true" else "false"
  pure <|
    "{\n" ++
    s!"  \"schemaVersion\": \"{engineeringOutputSchemaVersionV1}\",\n" ++
    s!"  \"target\": \"{outputSet.targetId}\",\n" ++
    s!"  \"codegenProfile\": \"{Targets.escapeJson outputSet.codegenProfile.toString}\",\n" ++
    s!"  \"artifactProgramName\": \"{Targets.escapeJson outputSet.artifactProgramName}\",\n" ++
    s!"  \"sourceHash\": \"{sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{semanticHash}\",\n" ++
    s!"  \"buildIdentityDigest\": \"{identityHash}\",\n" ++
    s!"  \"supportClaimDigest\": \"{claimHash}\",\n" ++
    s!"  \"engineeringRegistryRootDigest\": \"{registryRoot}\",\n" ++
    s!"  \"outputSetDigest\": \"{setHash}\",\n" ++
    s!"  \"deployable\": {deployable},\n" ++
    s!"  \"files\": [{files}]\n" ++
    "}\n"

/-- Deterministic engineering evidence sidecar JSON (publisher companion).

    Keeps the historical evidence field surface (`target` / source+semantic
    hashes / deployable / note) so tool-note pins remain stable while the
    manifest carries the full identity chain. -/
def renderEngineeringOutputSetEvidenceV1 (outputSet : EngineeringOutputSetV1) :
    Except String String := do
  let sourceHash ← digestHexExcept "source" outputSet.sourceDigest
  let semanticHash ← digestHexExcept "semantic" outputSet.semanticDigest
  let deployable := if outputSet.deployable then "true" else "false"
  pure <|
    "{\n" ++
    s!"  \"target\": \"{outputSet.targetId}\",\n" ++
    s!"  \"sourceHash\": \"{sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{semanticHash}\",\n" ++
    s!"  \"deployable\": {deployable},\n" ++
    s!"  \"note\": \"{Targets.escapeJson outputSet.evidenceNote}\"\n" ++
    "}\n"

end ProofForgeV2

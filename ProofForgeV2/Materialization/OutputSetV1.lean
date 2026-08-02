/-
  Engineering OutputSet carrier (M3c / D3-E7 commit 2/2 artifact-content bind).

  Private-constructor on-disk identity for one finalized engineering publish:

    outputSetDigest = domainSeparatedSha256(
      "pf.output-set.engineering.v1",
      canonicalOutputSetBytes)

  Canonical preimage (length-framed, deterministic):
    String(schemaVersion)                 -- "proof-forge.output.v1"
    String(targetId)
    String(codegenProfile)
    String(artifactProgramName)
    u32le(descriptorCount)
    × count, in canonical role-rank then path order:
      String(role wire)
      String(path)
      u64le(size)
      String(renderDigest(contentSha256))
    String(renderDigest(sourceDigest))
    String(renderDigest(semanticDigest))
    String(renderDigest(engineeringRegistryRootDigest))
    String(renderDigest(supportClaimDigest))
    String(renderDigest(buildIdentityDigest))
    String(renderDigest(planDigest))
    String("true" | "false")              -- deployable
    String(renderDigest(evidenceSha256))  -- exact evidence.json UTF-8 SHA-256

  Sole mint: `mintEngineeringOutputSetV1` from private-ctor
  `FinalizedArtifactsV1` + private-ctor `ArtifactContentInventoryV1` (scanner).
  Pure mint — no IO. On-disk JSON renderer:
  `renderEngineeringOutputSetManifestV1` (schema `"proof-forge.output.v1"`).
  Evidence sidecar is a pure render of finalized-bound fields/note; its exact
  UTF-8 digest is stored as `evidenceSha256` (no circular outputSetDigest dep).

  **Engineering only — not formal OutputSetV1 / TASK-D3-05:**
  * Domain is `pf.output-set.engineering.v1` (engineering-only suffix).
  * Structure name is `EngineeringOutputSetV1` (not public `OutputSet`).
  * Mint name is `mintEngineeringOutputSetV1` (not `makeOutput`).
  * Renderer is `renderEngineeringOutputSetManifestV1` (not `manifestJson`).
  * No public `validateOutputSet`. Sidecar leaf names remain
    `evidence.json` / `manifest.json` (S7c exact disk closure).
  * Not formal proof-forge.output.v1 product completion / hermetic publish.
-/
import ProofForgeV2.Materialization.ArtifactContentV1
import ProofForgeV2.Materialization.EngineeringDiskClosureV1
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
  /-- Canonical artifact content descriptors (role/path/size/contentSha256).
      Sidecars never appear. Order = role-rank then UTF-8 path. -/
  files : Array ArtifactContentDescriptorV1
  sourceDigest : Digest
  semanticDigest : Digest
  engineeringRegistryRootDigest : Digest
  supportClaimDigest : Digest
  buildIdentityDigest : Digest
  planDigest : Digest
  deployable : Bool
  evidenceNote : String
  /-- SHA-256 of exact evidence.json UTF-8 bytes (no circular outputSetDigest). -/
  evidenceSha256 : Digest
  /-- Domain-separated digest of the canonical output-set preimage. -/
  outputSetDigest : Digest
  deriving Repr

namespace EngineeringOutputSetV1

def targetIdOf (o : EngineeringOutputSetV1) : TargetId := o.targetId

def codegenProfileOf (o : EngineeringOutputSetV1) : CodegenProfileId :=
  o.codegenProfile

def artifactProgramNameOf (o : EngineeringOutputSetV1) : String :=
  o.artifactProgramName

def filesOf (o : EngineeringOutputSetV1) : Array ArtifactContentDescriptorV1 :=
  o.files

def sourceDigestOf (o : EngineeringOutputSetV1) : Digest := o.sourceDigest

def semanticDigestOf (o : EngineeringOutputSetV1) : Digest := o.semanticDigest

def engineeringRegistryRootDigestOf (o : EngineeringOutputSetV1) : Digest :=
  o.engineeringRegistryRootDigest

def supportClaimDigestOf (o : EngineeringOutputSetV1) : Digest :=
  o.supportClaimDigest

def buildIdentityDigestOf (o : EngineeringOutputSetV1) : Digest :=
  o.buildIdentityDigest

def planDigestOf (o : EngineeringOutputSetV1) : Digest := o.planDigest

def deployableOf (o : EngineeringOutputSetV1) : Bool := o.deployable

def evidenceNoteOf (o : EngineeringOutputSetV1) : String := o.evidenceNote

def evidenceSha256Of (o : EngineeringOutputSetV1) : Digest := o.evidenceSha256

def outputSetDigestOf (o : EngineeringOutputSetV1) : Digest := o.outputSetDigest

/-- Exact field equality (digests by algorithm + raw bytes). -/
def beq (a b : EngineeringOutputSetV1) : Bool :=
  a.targetId == b.targetId &&
  a.codegenProfile == b.codegenProfile &&
  a.artifactProgramName == b.artifactProgramName &&
  a.files.size == b.files.size &&
  (Id.run do
    let mut ok := true
    for pair in a.files.zip b.files do
      unless ArtifactContentDescriptorV1.beq pair.1 pair.2 do
        ok := false
    pure ok) &&
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
  a.planDigest.algorithm == b.planDigest.algorithm &&
  a.planDigest.bytes == b.planDigest.bytes &&
  a.deployable == b.deployable &&
  a.evidenceNote == b.evidenceNote &&
  a.evidenceSha256.algorithm == b.evidenceSha256.algorithm &&
  a.evidenceSha256.bytes == b.evidenceSha256.bytes &&
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

private def encodeU64le (value : Nat) : Except String ByteArray := do
  unless value < UInt64.size do
    throw "output set u64 size is not representable"
  let v := value
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  let b4 := UInt8.ofNat ((v / 4294967296) % 256)
  let b5 := UInt8.ofNat ((v / 1099511627776) % 256)
  let b6 := UInt8.ofNat ((v / 281474976710656) % 256)
  let b7 := UInt8.ofNat ((v / 72057594037927936) % 256)
  pure ((((((((ByteArray.empty.push b0).push b1).push b2).push b3).push b4).push b5).push b6).push b7)

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

/-- Encode one artifact content descriptor into the output-set preimage. -/
private def encodeDescriptorBytesV1 (d : ArtifactContentDescriptorV1) :
    Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString (ArtifactContentRoleV1.toWire d.role))
  out := out.append (← encodeString d.path)
  out := out.append (← encodeU64le d.size)
  out := out.append (← encodeDigestWire d.contentSha256)
  pure out

/-- Canonical engineering output-set preimage bytes. -/
def encodeEngineeringOutputSetBytesV1
    (targetId : TargetId)
    (codegenProfile : CodegenProfileId)
    (artifactProgramName : String)
    (files : Array ArtifactContentDescriptorV1)
    (sourceDigest : Digest)
    (semanticDigest : Digest)
    (engineeringRegistryRootDigest : Digest)
    (supportClaimDigest : Digest)
    (buildIdentityDigest : Digest)
    (planDigest : Digest)
    (deployable : Bool)
    (evidenceSha256 : Digest) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString engineeringOutputSchemaVersionV1)
  out := out.append (← encodeString targetId.toString)
  out := out.append (← encodeString codegenProfile.toString)
  out := out.append (← encodeString artifactProgramName)
  out := out.append (← encodeNatAsU32le files.size)
  for d in files do
    out := out.append (← encodeDescriptorBytesV1 d)
  out := out.append (← encodeDigestWire sourceDigest)
  out := out.append (← encodeDigestWire semanticDigest)
  out := out.append (← encodeDigestWire engineeringRegistryRootDigest)
  out := out.append (← encodeDigestWire supportClaimDigest)
  out := out.append (← encodeDigestWire buildIdentityDigest)
  out := out.append (← encodeDigestWire planDigest)
  out := out.append (← encodeString (if deployable then "true" else "false"))
  out := out.append (← encodeDigestWire evidenceSha256)
  pure out

/-- Compute outputSetDigest for the given binding fields. -/
def engineeringOutputSetDigestV1
    (targetId : TargetId)
    (codegenProfile : CodegenProfileId)
    (artifactProgramName : String)
    (files : Array ArtifactContentDescriptorV1)
    (sourceDigest : Digest)
    (semanticDigest : Digest)
    (engineeringRegistryRootDigest : Digest)
    (supportClaimDigest : Digest)
    (buildIdentityDigest : Digest)
    (planDigest : Digest)
    (deployable : Bool)
    (evidenceSha256 : Digest) : Except String Digest := do
  let bytes ← encodeEngineeringOutputSetBytesV1
    targetId codegenProfile artifactProgramName files
    sourceDigest semanticDigest
    engineeringRegistryRootDigest supportClaimDigest
    buildIdentityDigest planDigest deployable evidenceSha256
  domainSeparatedSha256 engineeringOutputSetDomainV1 bytes

private def digestHexExcept (label : String) (digest : Digest) : Except String String := do
  let rendered ← renderDigest digest
  unless rendered.startsWith "sha256:" do
    throw s!"output set {label} digest is not sha256"
  let suffix := (rendered.drop 7).toString
  unless suffix.length == 64 do
    throw s!"output set {label} digest has invalid length"
  pure suffix

/-- Pure evidence.json body from finalized-bound fields (no outputSetDigest).

    Exact UTF-8 of the returned string is what `evidenceSha256` hashes. -/
def renderEngineeringEvidenceBodyV1
    (targetId : TargetId)
    (sourceDigest : Digest)
    (semanticDigest : Digest)
    (deployable : Bool)
    (evidenceNote : String) : Except String String := do
  if evidenceNote.toList.any fun c =>
      c.toNat < 0x20 && c != '\n' && c != '\r' && c != '\t' then
    throw "output set evidence note contains an unsupported control character"
  let sourceHash ← digestHexExcept "source" sourceDigest
  let semanticHash ← digestHexExcept "semantic" semanticDigest
  let deployableWire := if deployable then "true" else "false"
  pure <|
    "{\n" ++
    s!"  \"target\": \"{targetId}\",\n" ++
    s!"  \"sourceHash\": \"{sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{semanticHash}\",\n" ++
    s!"  \"deployable\": {deployableWire},\n" ++
    s!"  \"note\": \"{Targets.escapeJson evidenceNote}\"\n" ++
    "}\n"

/-- Pure dual-defense validation of inventory join to finalized claims.

    Claim derivation is sole `deriveArtifactPathClaimsFromFinalizedV1`
    (EngineeringDiskClosureV1); no second claim authority. -/
private def validateInventoryJoinV1
    (finalized : FinalizedArtifactsV1)
    (inventory : ArtifactContentInventoryV1) :
    Except String (Array ArtifactContentDescriptorV1) := do
  let ds := ArtifactContentInventoryV1.descriptorsOf inventory
  if ds.isEmpty then
    throw "output set: empty artifact inventory is noncanonical"
  if ds.size > maxEngineeringDiskClosureFilesV1 then
    throw s!"output set: too many artifact descriptors ({ds.size})"
  let expected :=
    sortArtifactPathClaimsV1 (deriveArtifactPathClaimsFromFinalizedV1 finalized)
  unless ds.size == expected.size do
    throw s!"output set: inventory size {ds.size} diverges from finalized claims {expected.size}"
  let mut totalBytes : Nat := 0
  let mut seen : Array String := #[]
  for pair in ds.zip expected do
    let d := pair.1
    let c := pair.2
    unless d.role == c.role do
      throw s!"output set: descriptor role diverges at '{d.path}'"
    unless d.path == c.path do
      throw s!"output set: descriptor path '{d.path}' diverges from claim '{c.path}'"
    unless safeRelativeArtifactPathV1 d.path do
      throw s!"output set: unsafe artifact path '{d.path}'"
    if isFixedSidecarPathV1 d.path then
      throw s!"output set: sidecar path collides with artifact '{d.path}'"
    if seen.contains d.path then
      throw s!"output set: duplicate artifact path '{d.path}'"
    seen := seen.push d.path
    match validateBoundDigest s!"content digest for '{d.path}'" d.contentSha256 with
    | .ok () => pure ()
    | .error e => throw e
    match d.contentSha256.algorithm with
    | .sha256 => pure ()
    if d.size > maxEngineeringDiskClosureFileBytesV1 then
      throw s!"output set: file exceeds size limit '{d.path}'"
    totalBytes := totalBytes + d.size
    if totalBytes > maxEngineeringDiskClosureTotalBytesV1 then
      throw s!"output set: artifact inventory total size exceeds limit at '{d.path}'"
  for a in ds do
    for b in ds do
      if a.path != b.path && b.path.startsWith (a.path ++ "/") then
        throw s!"output set: file/directory prefix conflict '{a.path}'"
  -- Exact canonical order (role-rank then path).
  let sorted := sortArtifactContentDescriptorsV1 ds
  unless ds.size == sorted.size do
    throw "output set: artifact inventory order is noncanonical"
  for pair in ds.zip sorted do
    unless ArtifactContentDescriptorV1.beq pair.1 pair.2 do
      throw "output set: artifact inventory order is noncanonical"
  pure ds

/-- Sole mint of `EngineeringOutputSetV1`.

    Consumes private `FinalizedArtifactsV1` + private `ArtifactContentInventoryV1`
    from the sole scanner. Exact-joins inventory role/path claims to finalized
    base/extras, recomputes evidenceSha256 from exact evidence body bytes, binds
    descriptors + evidence digest into `outputSetDigest`. Pure — no IO. -/
def mintEngineeringOutputSetV1
    (finalized : FinalizedArtifactsV1)
    (inventory : ArtifactContentInventoryV1) :
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
  let planDigest := EngineeringBuildIdentityV1.planDigestOf identity
  let files ← match validateInventoryJoinV1 finalized inventory with
    | .ok ds => pure ds
    | .error e => throw <| .invalidProgram e
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
  match validateBoundDigest "plan digest" planDigest with
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
      supportClaimDigest
      planDigest with
    | .ok d => pure d
    | .error e =>
        throw <| .invalidProgram s!"output set: build identity recompute failed: {e}"
  unless recomputedIdentity == buildIdentityDigest do
    throw <| .invalidProgram
      "output set: build identity digest diverges from recomputed preimage"
  let deployable := FinalizedArtifactsV1.deployableOf finalized
  let evidenceNote := FinalizedArtifactsV1.evidenceNoteOf finalized
  -- Exact evidence body bytes → evidenceSha256 (no circular outputSetDigest).
  let evidenceBody ← match renderEngineeringEvidenceBodyV1
      selection.targetId sourceDigest semanticDigest deployable evidenceNote with
    | .ok text => pure text
    | .error e =>
        throw <| .invalidProgram s!"output set: evidence body render failed: {e}"
  let evidenceSha256 := sha256Bytes evidenceBody.toUTF8
  match validateBoundDigest "evidence sha256" evidenceSha256 with
  | .ok () => pure ()
  | .error e => throw <| .invalidProgram e
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
      planDigest
      deployable
      evidenceSha256 with
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
    planDigest
    deployable
    evidenceNote
    evidenceSha256
    outputSetDigest)

/-- Deterministic engineering on-disk manifest JSON for `proof-forge.output.v1`.

    Digests are bare 64-char lowercase hex. `files` is an array of exact-key
    objects `{role,path,size,contentSha256}` (path-only string arrays are
    rejected by the inspect parser). Top-level `evidenceSha256` binds the exact
    evidence.json UTF-8 digest. Not formal OutputSetV1 / PF-JCS product wire. -/
def renderEngineeringOutputSetManifestV1 (outputSet : EngineeringOutputSetV1) :
    Except String String := do
  let sourceHash ← digestHexExcept "source" outputSet.sourceDigest
  let semanticHash ← digestHexExcept "semantic" outputSet.semanticDigest
  let registryRoot ←
    digestHexExcept "engineering registry root" outputSet.engineeringRegistryRootDigest
  let claimHash ← digestHexExcept "support claim" outputSet.supportClaimDigest
  let identityHash ← digestHexExcept "build identity" outputSet.buildIdentityDigest
  let planHash ← digestHexExcept "plan" outputSet.planDigest
  let setHash ← digestHexExcept "output set" outputSet.outputSetDigest
  let evidenceHash ← digestHexExcept "evidence" outputSet.evidenceSha256
  let mut fileObjs : Array String := #[]
  for d in outputSet.files do
    let role := ArtifactContentRoleV1.toWire d.role
    let contentHash ← digestHexExcept s!"content '{d.path}'" d.contentSha256
    fileObjs := fileObjs.push <|
      s!"    \{\"role\": \"{role}\", \"path\": \"{Targets.escapeJson d.path}\", \"size\": {d.size}, \"contentSha256\": \"{contentHash}\"}"
  let filesBody :=
    if fileObjs.isEmpty then ""
    else "\n" ++ String.intercalate ",\n" fileObjs.toList ++ "\n  "
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
    s!"  \"planDigest\": \"{planHash}\",\n" ++
    s!"  \"supportClaimDigest\": \"{claimHash}\",\n" ++
    s!"  \"engineeringRegistryRootDigest\": \"{registryRoot}\",\n" ++
    s!"  \"outputSetDigest\": \"{setHash}\",\n" ++
    s!"  \"evidenceSha256\": \"{evidenceHash}\",\n" ++
    s!"  \"deployable\": {deployable},\n" ++
    s!"  \"files\": [{filesBody}]\n" ++
    "}\n"

/-- Deterministic engineering evidence sidecar JSON (publisher companion).

    Same exact bytes as `renderEngineeringEvidenceBodyV1` from the mint-time
    fields (identity fields + note). SHA-256 of these UTF-8 bytes is
    `evidenceSha256` on the output set / manifest. -/
def renderEngineeringOutputSetEvidenceV1 (outputSet : EngineeringOutputSetV1) :
    Except String String :=
  renderEngineeringEvidenceBodyV1
    outputSet.targetId
    outputSet.sourceDigest
    outputSet.semanticDigest
    outputSet.deployable
    outputSet.evidenceNote

end ProofForgeV2

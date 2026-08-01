/-
  Engineering BuildIdentity carrier (M3b / Wave formal-identity second slice).

  Private-constructor identity binding the full engineering identity chain:

    identityDigest = domainSeparatedSha256(
      "pf.build-identity.engineering.v1",
      canonicalBuildIdentityBytes)

  Canonical preimage (length-framed, deterministic):
    String(targetId)
    String(codegenProfile)
    String(artifactName)
    String(renderDigest(sourceDigest))
    String(renderDigest(semanticDigest))
    String(renderDigest(engineeringRegistryRootDigest))
    String(renderDigest(supportClaimDigest))
    String(renderDigest(planDigest))   -- M4: EVM Plan schema digest, or
                                       -- engineering-absent plan digest for other targets

  Sole mint: `mintEngineeringBuildIdentityV1`, called from
  `mintMaterializedArtifactsV1` after capability + digest validation.

  **Engineering only — not formal BuildIdentity / TASK-D3-03:**
  * Distinct from private five-field formal-layout `BuildIdentityV1` (no mint).
  * Domain is `pf.build-identity.engineering.v1`.
  * Field name for the registry root anchor is `engineeringRegistryRootDigest`
    (engineering-prefixed; not the formal root-digest product API name).
  * Mint name is `mintEngineeringBuildIdentityV1` (engineering-prefixed sole mint).
  * M3c publishes `identityDigest` via engineering `EngineeringOutputSetV1`
    (`proof-forge.output.v1`); not formal OutputSetV1.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets.EngineeringBuildIdentityV1

open ProofForgeV2
open ProofForgeV2.Core.Common

/-- Domain tag for the **engineering** build-identity digest. -/
def engineeringBuildIdentityDomainV1 : String :=
  "pf.build-identity.engineering.v1"

/-- Full engineering build identity chain. Private constructor; sole mint via
    `mintEngineeringBuildIdentityV1`. -/
structure EngineeringBuildIdentityV1 where
  private mk ::
  targetId : TargetId
  codegenProfile : CodegenProfileId
  artifactName : String
  sourceDigest : Digest
  semanticDigest : Digest
  engineeringRegistryRootDigest : Digest
  supportClaimDigest : Digest
  /-- Target Plan engineering digest (M4). EVM uses
      `engineeringEvmPlanDigestV1`; other targets bind
      `engineeringAbsentPlanDigestV1` so the identity chain always carries a
      plan slot without inventing fake Plan schemas. -/
  planDigest : Digest
  /-- Domain-separated digest of the canonical identity preimage. -/
  identityDigest : Digest
  deriving Repr

namespace EngineeringBuildIdentityV1

def targetIdOf (b : EngineeringBuildIdentityV1) : TargetId := b.targetId

def codegenProfileOf (b : EngineeringBuildIdentityV1) : CodegenProfileId :=
  b.codegenProfile

def artifactNameOf (b : EngineeringBuildIdentityV1) : String := b.artifactName

def sourceDigestOf (b : EngineeringBuildIdentityV1) : Digest := b.sourceDigest

def semanticDigestOf (b : EngineeringBuildIdentityV1) : Digest := b.semanticDigest

def engineeringRegistryRootDigestOf (b : EngineeringBuildIdentityV1) : Digest :=
  b.engineeringRegistryRootDigest

def supportClaimDigestOf (b : EngineeringBuildIdentityV1) : Digest :=
  b.supportClaimDigest

def planDigestOf (b : EngineeringBuildIdentityV1) : Digest := b.planDigest

def identityDigestOf (b : EngineeringBuildIdentityV1) : Digest := b.identityDigest

/-- Exact field equality (digests by algorithm + raw bytes). -/
def beq (a b : EngineeringBuildIdentityV1) : Bool :=
  a.targetId == b.targetId &&
  a.codegenProfile == b.codegenProfile &&
  a.artifactName == b.artifactName &&
  a.sourceDigest.algorithm == b.sourceDigest.algorithm &&
  a.sourceDigest.bytes == b.sourceDigest.bytes &&
  a.semanticDigest.algorithm == b.semanticDigest.algorithm &&
  a.semanticDigest.bytes == b.semanticDigest.bytes &&
  a.engineeringRegistryRootDigest.algorithm == b.engineeringRegistryRootDigest.algorithm &&
  a.engineeringRegistryRootDigest.bytes == b.engineeringRegistryRootDigest.bytes &&
  a.supportClaimDigest.algorithm == b.supportClaimDigest.algorithm &&
  a.supportClaimDigest.bytes == b.supportClaimDigest.bytes &&
  a.planDigest.algorithm == b.planDigest.algorithm &&
  a.planDigest.bytes == b.planDigest.bytes &&
  a.identityDigest.algorithm == b.identityDigest.algorithm &&
  a.identityDigest.bytes == b.identityDigest.bytes

instance : BEq EngineeringBuildIdentityV1 := ⟨beq⟩

end EngineeringBuildIdentityV1

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
    throw "build identity u32 length is not representable"
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
  | .error e => throw s!"build identity {label} is invalid: {e}"

/-- Canonical engineering build-identity preimage bytes. -/
def encodeEngineeringBuildIdentityBytesV1
    (targetId : TargetId)
    (codegenProfile : CodegenProfileId)
    (artifactName : String)
    (sourceDigest : Digest)
    (semanticDigest : Digest)
    (engineeringRegistryRootDigest : Digest)
    (supportClaimDigest : Digest)
    (planDigest : Digest) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString targetId.toString)
  out := out.append (← encodeString codegenProfile.toString)
  out := out.append (← encodeString artifactName)
  out := out.append (← encodeDigestWire sourceDigest)
  out := out.append (← encodeDigestWire semanticDigest)
  out := out.append (← encodeDigestWire engineeringRegistryRootDigest)
  out := out.append (← encodeDigestWire supportClaimDigest)
  out := out.append (← encodeDigestWire planDigest)
  pure out

/-- Compute identityDigest for the given binding fields. -/
def engineeringBuildIdentityDigestV1
    (targetId : TargetId)
    (codegenProfile : CodegenProfileId)
    (artifactName : String)
    (sourceDigest : Digest)
    (semanticDigest : Digest)
    (engineeringRegistryRootDigest : Digest)
    (supportClaimDigest : Digest)
    (planDigest : Digest) : Except String Digest := do
  let bytes ← encodeEngineeringBuildIdentityBytesV1
    targetId codegenProfile artifactName
    sourceDigest semanticDigest
    engineeringRegistryRootDigest supportClaimDigest
    planDigest
  domainSeparatedSha256 engineeringBuildIdentityDomainV1 bytes

/-- Domain for targets that have no engineering Plan schema yet (non-EVM M4). -/
def engineeringAbsentPlanDomainV1 : String :=
  "pf.plan.engineering.absent.v1"

/-- Deterministic plan-slot digest when no target Plan schema is wired.
    Binds target + profile so absent slots are not identity-colliding across
    targets/profiles. Not a Plan content digest. -/
def engineeringAbsentPlanDigestV1
    (targetId : TargetId)
    (codegenProfile : CodegenProfileId) : Except String Digest := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString targetId.toString)
  out := out.append (← encodeString codegenProfile.toString)
  domainSeparatedSha256 engineeringAbsentPlanDomainV1 out

/-- Sole mint of `EngineeringBuildIdentityV1`.

    Validates all bound digests, recomputes identityDigest from the canonical
    preimage, and returns the private-ctor carrier. -/
def mintEngineeringBuildIdentityV1
    (targetId : TargetId)
    (codegenProfile : CodegenProfileId)
    (artifactName : String)
    (sourceDigest : Digest)
    (semanticDigest : Digest)
    (engineeringRegistryRootDigest : Digest)
    (supportClaimDigest : Digest)
    (planDigest : Digest) :
    Except String EngineeringBuildIdentityV1 := do
  validateBoundDigest "source digest" sourceDigest
  validateBoundDigest "semantic digest" semanticDigest
  validateBoundDigest "engineering registry root digest" engineeringRegistryRootDigest
  validateBoundDigest "support claim digest" supportClaimDigest
  validateBoundDigest "plan digest" planDigest
  unless artifactName.toUTF8.size > 0 do
    throw "build identity artifact name must be non-empty"
  let identityDigest ← engineeringBuildIdentityDigestV1
    targetId codegenProfile artifactName
    sourceDigest semanticDigest
    engineeringRegistryRootDigest supportClaimDigest
    planDigest
  pure (EngineeringBuildIdentityV1.mk
    targetId
    codegenProfile
    artifactName
    sourceDigest
    semanticDigest
    engineeringRegistryRootDigest
    supportClaimDigest
    planDigest
    identityDigest)

end ProofForgeV2.Targets.EngineeringBuildIdentityV1

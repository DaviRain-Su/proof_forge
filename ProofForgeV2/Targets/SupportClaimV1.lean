/-
  Engineering SupportClaim carrier (M3b / Wave formal-identity second slice).

  Private-constructor claim binding one implemented (targetId, codegenProfile)
  S2 support row to the engineering registry root digest:

    claimDigest = domainSeparatedSha256(
      "pf.support-claim.engineering.v1",
      canonicalSupportClaimBytes)

  Canonical preimage (length-framed, deterministic):
    String(targetId)
    String(codegenProfile)
    u32le(supportedIdCount)
    String(requirementId) × count   -- SPEC/S2 wire order (ids only)
    String(renderDigest(engineeringRegistryRootDigest))

  Sole bulk mint: `mintEngineeringSupportClaimsV1` over the frozen support index
  in canonical (targetId, profile) order. Product resolver binds the selected
  claim into `ResolvedEngineeringBuildV1`.

  **Engineering only — not formal TASK-D3-03 / formal SupportClaim:**
  * Domain is `pf.support-claim.engineering.v1` (engineering-only suffix).
  * Field name for the root anchor is `engineeringRegistryRootDigest`
    (engineering-prefixed; not the formal root-digest product API name).
  * No predicate implication, evidence grade, or ProfileSupportIndex.
  * M3c publishes `claimDigest` via engineering `EngineeringOutputSetV1`
    (`proof-forge.output.v1`); not formal OutputSetV1.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.RegistryRootV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.TargetRegistryV1

namespace ProofForgeV2.Targets.SupportClaimV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.RegistryRootV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.TargetRegistryV1

/-- Domain tag for the **engineering** support-claim digest. -/
def engineeringSupportClaimDomainV1 : String :=
  "pf.support-claim.engineering.v1"

/-- One engineering support claim. Private constructor; sole mint via
    `mintEngineeringSupportClaimsV1` / `mintEngineeringSupportClaimFromRowV1`. -/
structure EngineeringSupportClaimV1 where
  private mk ::
  targetId : TargetId
  codegenProfile : CodegenProfileId
  /-- Exact S2 support row requests (wire order; empty predicates). -/
  supported : Array RequirementRequestV1
  /-- Engineering registry root digest anchoring this claim (M3a). -/
  engineeringRegistryRootDigest : Digest
  /-- Domain-separated digest of the canonical claim preimage. -/
  claimDigest : Digest

namespace EngineeringSupportClaimV1

def targetIdOf (c : EngineeringSupportClaimV1) : TargetId := c.targetId

def codegenProfileOf (c : EngineeringSupportClaimV1) : CodegenProfileId :=
  c.codegenProfile

def supportedOf (c : EngineeringSupportClaimV1) : Array RequirementRequestV1 :=
  c.supported

def engineeringRegistryRootDigestOf (c : EngineeringSupportClaimV1) : Digest :=
  c.engineeringRegistryRootDigest

def claimDigestOf (c : EngineeringSupportClaimV1) : Digest := c.claimDigest

def supportedIdsOf (c : EngineeringSupportClaimV1) : Array String :=
  c.supported.map (·.id)

/-- Exact field equality (digests by algorithm + raw bytes). -/
def beq (a b : EngineeringSupportClaimV1) : Bool :=
  a.targetId == b.targetId &&
  a.codegenProfile == b.codegenProfile &&
  a.supported == b.supported &&
  a.engineeringRegistryRootDigest.algorithm == b.engineeringRegistryRootDigest.algorithm &&
  a.engineeringRegistryRootDigest.bytes == b.engineeringRegistryRootDigest.bytes &&
  a.claimDigest.algorithm == b.claimDigest.algorithm &&
  a.claimDigest.bytes == b.claimDigest.bytes

instance : BEq EngineeringSupportClaimV1 := ⟨beq⟩

end EngineeringSupportClaimV1

-- ---------------------------------------------------------------------------
-- Canonical length-framed preimage (matches RegistryRootV1 framing style)
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
    throw "support claim u32 length is not representable"
  pure (encodeU32le (UInt32.ofNat count))

/-- Length-framed UTF-8 string: `u32le(len) || utf8Bytes`. -/
private def encodeString (value : String) : Except String ByteArray := do
  let raw := value.toUTF8
  let header ← encodeNatAsU32le raw.size
  pure (header.append raw)

/-- Embed a validated digest as its exact wire form (`sha256:<64 hex>`). -/
private def encodeDigestWire (digest : Digest) : Except String ByteArray := do
  let wire ← renderDigest digest
  encodeString wire

/-- Canonical engineering support-claim preimage bytes.

    Layout:
    ```
    String(targetId)
    String(codegenProfile)
    u32le(supportedIdCount)
    String(requirementId) × count
    String(renderDigest(engineeringRegistryRootDigest))
    String = u32le(utf8ByteLen) || utf8Bytes
    ```
-/
def encodeEngineeringSupportClaimBytesV1
    (targetId : TargetId)
    (codegenProfile : CodegenProfileId)
    (supportedIds : Array String)
    (engineeringRegistryRootDigest : Digest) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString targetId.toString)
  out := out.append (← encodeString codegenProfile.toString)
  out := out.append (← encodeNatAsU32le supportedIds.size)
  for id in supportedIds do
    out := out.append (← encodeString id)
  out := out.append (← encodeDigestWire engineeringRegistryRootDigest)
  pure out

/-- Compute claimDigest for the given binding fields. -/
def engineeringSupportClaimDigestV1
    (targetId : TargetId)
    (codegenProfile : CodegenProfileId)
    (supportedIds : Array String)
    (engineeringRegistryRootDigest : Digest) : Except String Digest := do
  let bytes ← encodeEngineeringSupportClaimBytesV1
    targetId codegenProfile supportedIds engineeringRegistryRootDigest
  domainSeparatedSha256 engineeringSupportClaimDomainV1 bytes

/-- Mint one claim from a support row + registry root digest. -/
def mintEngineeringSupportClaimFromRowV1
    (row : StaticRequirementSupportRowV1)
    (engineeringRegistryRootDigest : Digest) :
    Except String EngineeringSupportClaimV1 := do
  match validateDigest engineeringRegistryRootDigest with
  | .ok () => pure ()
  | .error e => throw s!"support claim registry root digest invalid: {e}"
  let ids := row.supported.map (·.id)
  let claimDigest ← engineeringSupportClaimDigestV1
    row.targetId row.codegenProfile ids engineeringRegistryRootDigest
  pure (EngineeringSupportClaimV1.mk
    row.targetId
    row.codegenProfile
    row.supported
    engineeringRegistryRootDigest
    claimDigest)

/-- Sole bulk mint: one claim per support-index row in canonical index order
    (already strictly ascending by (targetId, codegenProfile)). -/
def mintEngineeringSupportClaimsV1
    (registry : TargetRegistryV1)
    (index : StaticRequirementSupportIndexV1) :
    Except String (Array EngineeringSupportClaimV1) := do
  let rootDigest ← engineeringRegistryRootDigestV1 registry
  let rows := StaticRequirementSupportIndexV1.toArray index
  if rows.isEmpty then
    throw "engineering support claim mint requires a non-empty support index"
  let mut claims : Array EngineeringSupportClaimV1 := #[]
  for row in rows do
    let claim ← mintEngineeringSupportClaimFromRowV1 row rootDigest
    claims := claims.push claim
  pure claims

/-- Lookup a claim by exact (targetId, codegenProfile). -/
def findEngineeringSupportClaimV1
    (claims : Array EngineeringSupportClaimV1)
    (targetId : TargetId) (codegenProfile : CodegenProfileId) :
    Option EngineeringSupportClaimV1 :=
  claims.find? (fun c =>
    c.targetId == targetId && c.codegenProfile == codegenProfile)

end ProofForgeV2.Targets.SupportClaimV1

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
  -- `renderDigest` accepts only a validated 32-byte SHA-256 digest, so its wire
  -- form is exactly 71 ASCII bytes. Emit that canonical fixed-width frame
  -- directly; this is byte-identical to `encodeString wire` and avoids a
  -- second value-dependent representability check.
  pure ((encodeU32le 71).append wire.toUTF8)

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

private def validateStringFrameV1 (value : String) : Except String Unit := do
  unless value.toUTF8.size ≤ UInt32.size - 1 do
    throw "support claim u32 length is not representable"

private def validateCountFrameV1 (count : Nat) : Except String Unit := do
  unless count ≤ UInt32.size - 1 do
    throw "support claim u32 length is not representable"

private def validateEngineeringSupportClaimRowsV1 :
    List StaticRequirementSupportRowV1 → Except String Unit
  | [] => .ok ()
  | row :: rest => do
      validateStringFrameV1 row.targetId.toString
      validateStringFrameV1 row.codegenProfile.toString
      validateCountFrameV1 row.supported.size
      for request in row.supported do
        validateStringFrameV1 request.id
      validateEngineeringSupportClaimRowsV1 rest

private def encodeStringTotalV1 (value : String) : ByteArray :=
  let raw := value.toUTF8
  (encodeU32le (UInt32.ofNat raw.size)).append raw

private def encodeEngineeringSupportClaimBytesTotalV1
    (row : StaticRequirementSupportRowV1) (rootWire : String) : ByteArray :=
  let target := encodeStringTotalV1 row.targetId.toString
  let profile := encodeStringTotalV1 row.codegenProfile.toString
  let count := encodeU32le (UInt32.ofNat row.supported.size)
  let ids := row.supported.foldl
    (fun out request => out.append (encodeStringTotalV1 request.id)) ByteArray.empty
  target.append profile |>.append count |>.append ids |>.append
    ((encodeU32le 71).append rootWire.toUTF8)

private def mintEngineeringSupportClaimTotalV1
    (row : StaticRequirementSupportRowV1)
    (engineeringRegistryRootDigest : Digest)
    (rootWire : String) : EngineeringSupportClaimV1 :=
  let bytes := encodeEngineeringSupportClaimBytesTotalV1 row rootWire
  let claimDigest := sha256Bytes
    ((engineeringSupportClaimDomainV1.toUTF8.push 0).append bytes)
  EngineeringSupportClaimV1.mk row.targetId row.codegenProfile row.supported
    engineeringRegistryRootDigest claimDigest

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
  -- Render/validate the shared root and all length-framed source fields before
  -- the total map. The total map is byte-identical to the per-row public mint,
  -- but cannot fail after these checks and does not re-render the same root 17
  -- times.
  let rootWire ← renderDigest rootDigest
  validateEngineeringSupportClaimRowsV1 rows.toList
  pure (rows.map fun row =>
    mintEngineeringSupportClaimTotalV1 row rootDigest rootWire)

private theorem mintEngineeringSupportClaimsV1_eq_ok_of_stages
    (registry : TargetRegistryV1)
    (index : StaticRequirementSupportIndexV1)
    (rootDigest : Digest)
    (rows : Array StaticRequirementSupportRowV1)
    (rootWire : String)
    (hroot : engineeringRegistryRootDigestV1 registry = .ok rootDigest)
    (hrows : StaticRequirementSupportIndexV1.toArray index = rows)
    (hnonempty : rows.isEmpty = false)
    (hrender : renderDigest rootDigest = .ok rootWire)
    (hvalidate : validateEngineeringSupportClaimRowsV1 rows.toList = .ok ()) :
    mintEngineeringSupportClaimsV1 registry index =
      .ok (rows.map fun row =>
        mintEngineeringSupportClaimTotalV1 row rootDigest rootWire) := by
  simp only [mintEngineeringSupportClaimsV1, hroot, hrows, hnonempty,
    Bool.false_eq_true, ↓reduceIte, hrender, hvalidate, Bind.bind, Except.bind,
    Pure.pure, Except.pure]

/-- Lookup a claim by exact (targetId, codegenProfile). -/
def findEngineeringSupportClaimV1
    (claims : Array EngineeringSupportClaimV1)
    (targetId : TargetId) (codegenProfile : CodegenProfileId) :
    Option EngineeringSupportClaimV1 :=
  claims.find? (fun c =>
    c.targetId == targetId && c.codegenProfile == codegenProfile)

private theorem exceptToOptionGetSuccessV1 {ε α : Type}
    (result : Except ε α) (success : result.toOption.isSome = true) :
    result = .ok (result.toOption.get success) := by
  cases result with
  | error _ => simp [Except.toOption] at success
  | ok _ => rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
/-- The sole bulk claim mint succeeds for the frozen registry/support-index
    pair. Claim/root digests remain symbolic results of the production SHA-256
    implementation; no concrete digest bytes or alternate claim are supplied. -/
theorem mintEngineeringSupportClaimsV1_initial_exists
    (registry : TargetRegistryV1)
    (index : StaticRequirementSupportIndexV1)
    (hregistry : initialTargetRegistryV1Result = .ok registry)
    (hindex : initialStaticRequirementSupportIndexV1Result = .ok index) :
    ∃ claims claim,
      mintEngineeringSupportClaimsV1 registry index = .ok claims ∧
      findEngineeringSupportClaimV1 claims TargetId.solana
          CodegenProfileId.solanaSbpfCpiElfV1 = some claim ∧
      EngineeringSupportClaimV1.targetIdOf claim = TargetId.solana ∧
      EngineeringSupportClaimV1.codegenProfileOf claim =
        CodegenProfileId.solanaSbpfCpiElfV1 ∧
      EngineeringSupportClaimV1.supportedOf claim =
        initialSolanaSupportRowV1.supported := by
  rcases engineeringRegistryRootDigestV1_initial_exists registry hregistry with
    ⟨rootDigest, hrootDigest, hrootValid⟩
  have hrenderSome : (renderDigest rootDigest).toOption.isSome = true := by
    unfold renderDigest
    rw [hrootValid]
    simp only [Bind.bind, Except.bind, Pure.pure, Except.pure, Except.toOption,
      Option.isSome]
  let rootWire := (renderDigest rootDigest).toOption.get hrenderSome
  have hrender : renderDigest rootDigest = .ok rootWire :=
    exceptToOptionGetSuccessV1 _ hrenderSome
  have hrows : StaticRequirementSupportIndexV1.toArray index =
      initialSupportRowsV1 := by
    rw [initialStaticRequirementSupportIndexV1Result_eq_ok] at hindex
    injection hindex with hindexValue
    subst index
    rfl
  have hnonempty : initialSupportRowsV1.isEmpty = false := by
    unfold initialSupportRowsV1 buildInitialSupportRowsV1
    rfl
  have hvalidate :
      validateEngineeringSupportClaimRowsV1 initialSupportRowsV1.toList =
        .ok () := by
    have hsome :
        (validateEngineeringSupportClaimRowsV1
          initialSupportRowsV1.toList).toOption.isSome = true := by
      decide
    simpa using exceptToOptionGetSuccessV1
      (validateEngineeringSupportClaimRowsV1 initialSupportRowsV1.toList) hsome
  let claims := initialSupportRowsV1.map fun row =>
    mintEngineeringSupportClaimTotalV1 row rootDigest rootWire
  let claim := mintEngineeringSupportClaimTotalV1 initialSolanaSupportRowV1
    rootDigest rootWire
  have hmint : mintEngineeringSupportClaimsV1 registry index = .ok claims :=
    mintEngineeringSupportClaimsV1_eq_ok_of_stages registry index rootDigest
      initialSupportRowsV1 rootWire hrootDigest hrows hnonempty hrender hvalidate
  have hfind : findEngineeringSupportClaimV1 claims TargetId.solana
      CodegenProfileId.solanaSbpfCpiElfV1 = some claim := by
    unfold findEngineeringSupportClaimV1
    rw [Array.find?_eq_some_iff_getElem]
    refine ⟨?_, ⟨12, ?_, ?_, ?_⟩⟩
    · rfl
    · unfold claims initialSupportRowsV1 buildInitialSupportRowsV1
      simp only [Array.size_map]
      decide
    · rw [Array.getElem_map]
      rfl
    · intro j hj
      have hrowsSize : initialSupportRowsV1.size = 17 := by
        unfold initialSupportRowsV1 buildInitialSupportRowsV1
        rfl
      have hjRows : j < initialSupportRowsV1.size := by
        rw [hrowsSize]
        omega
      unfold claims
      rw [Array.getElem_map]
      change (!(initialSupportRowsV1[j].targetId == TargetId.solana &&
        initialSupportRowsV1[j].codegenProfile ==
          CodegenProfileId.solanaSbpfCpiElfV1)) = true
      have hjCases :
          j = 0 ∨ j = 1 ∨ j = 2 ∨ j = 3 ∨ j = 4 ∨ j = 5 ∨
          j = 6 ∨ j = 7 ∨ j = 8 ∨ j = 9 ∨ j = 10 ∨ j = 11 := by
        omega
      rcases hjCases with rfl | rfl | rfl | rfl | rfl | rfl |
        rfl | rfl | rfl | rfl | rfl | rfl <;>
      unfold initialSupportRowsV1 buildInitialSupportRowsV1
      all_goals rfl
  refine ⟨claims, claim, hmint, hfind, ?_, ?_, ?_⟩
  · rfl
  · rfl
  · rfl

end ProofForgeV2.Targets.SupportClaimV1

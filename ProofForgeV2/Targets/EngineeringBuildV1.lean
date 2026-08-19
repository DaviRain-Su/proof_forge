/-
  Private engineering materialize/emit capability leaf (D3/S6 + M3b claim bind).

  Cycle-free: BuildSelectionV1, RequirementResolverV1, SupportClaimV1,
  TargetRegistryV1, Pipeline, InlineProofCertifierV1, WireV1,
  RequirementsV1, DescriptorDataV1 —
  does not import target Plan modules or Registry.

  Sole mint of `ResolvedEngineeringBuildV1`:
  `resolveEngineeringRequirementsV1`. The NEAR-only
  `authorizeCertifiedNearInvariantErasureV1` transition can enrich an already
  resolved capability with private certificate authority, but cannot mint from
  `(selection, compiled)` or override requirements. The exact retained
  `SemanticProgramV1.data.requirements` remains the only request authority.

  M3b binds the selected engineering SupportClaim (registry-root anchored) into
  the capability. Not formal SupportClaim / formal registry root or digest /
  formal BuildIdentity / OutputSetV1 / complete SemanticProgramV1 lowering.
-/
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.SupportClaimV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Compiler.CertifiedInlineProofV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.RequirementsV1

namespace ProofForgeV2.Targets

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Compiler.InlineProofCertifierV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.SupportClaimV1
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Semantic.RequirementsV1

/-- Opaque NEAR-only authorization minted from an audited inline certificate
    whose source/semantic digests match the exact compile carrier and whose
    preserving rows cover every validated semantic invariant. -/
structure NearInvariantErasureAuthorizationV1 where
  private mk ::
  private sourceDigest_ : Digest
  private semanticDigest_ : Digest
  private proofCertificationDigest_ : Digest
  private invariantCount_ : Nat

namespace NearInvariantErasureAuthorizationV1

def sourceDigest (authorization : NearInvariantErasureAuthorizationV1) : Digest :=
  authorization.sourceDigest_

def semanticDigest (authorization : NearInvariantErasureAuthorizationV1) : Digest :=
  authorization.semanticDigest_

def proofCertificationDigest
    (authorization : NearInvariantErasureAuthorizationV1) : Digest :=
  authorization.proofCertificationDigest_

def invariantCount (authorization : NearInvariantErasureAuthorizationV1) : Nat :=
  authorization.invariantCount_

end NearInvariantErasureAuthorizationV1

/-- Private engineering materialize/emit capability.
    Contains frozen selection, the single retained-semantic compiler result,
    the exact embedded ProgramRequirementsV1 freeze, and the selected
    engineering SupportClaim (M3b). Not formal SupportClaim /
    ResolvedSupportDecision / formal BuildIdentity. -/
structure ResolvedEngineeringBuildV1 where
  private mk ::
  selection : ResolvedBuildSelectionV1
  compiled : CompiledSemanticV1
  requirements : ProgramRequirementsV1
  supportClaim : EngineeringSupportClaimV1
  nearInvariantErasure? : Option NearInvariantErasureAuthorizationV1

namespace ResolvedEngineeringBuildV1

def selectionOf (capability : ResolvedEngineeringBuildV1) : ResolvedBuildSelectionV1 :=
  capability.selection

def compiledOf (capability : ResolvedEngineeringBuildV1) : CompiledSemanticV1 :=
  capability.compiled

def requirementsOf (capability : ResolvedEngineeringBuildV1) : ProgramRequirementsV1 :=
  capability.requirements

def supportClaimOf (capability : ResolvedEngineeringBuildV1) : EngineeringSupportClaimV1 :=
  capability.supportClaim

def kindOf (capability : ResolvedEngineeringBuildV1) : TargetKind :=
  capability.selection.kind

def targetIdOf (capability : ResolvedEngineeringBuildV1) : TargetId :=
  capability.selection.targetId

def codegenProfileOf (capability : ResolvedEngineeringBuildV1) : CodegenProfileId :=
  capability.selection.codegenProfile

/-- Present only on the proof-bearing NEAR resolver path. The authorization is
    opaque and cannot be caller-constructed. -/
def nearInvariantErasureAuthorization?
    (capability : ResolvedEngineeringBuildV1) :
    Option NearInvariantErasureAuthorizationV1 :=
  capability.nearInvariantErasure?

end ResolvedEngineeringBuildV1

/-- Sole constructor path for `ResolvedEngineeringBuildV1`.

    Requirements are always recovered from the retained semantic carrier.

    Order:
    1. bind the frozen engineering support seed;
    2. exact target/profile support-row match;
    3. validate the retained semantic carrier and exact-resolve its embedded
       requirements (unknown/version/digest/no support → PF-REQ-UNSUPPORTED;
       predicates → PF-REQ-PRECONDITION);
    4. bind descriptor target/profile identity;
    5. mint engineering SupportClaims over the frozen registry + support index
       and bind the selected claim (target/profile + supported row must match);
    6. mint the private capability with the unchanged request set + claim and
       no invariant-erasure authorization.

    Arbitrary request matrices remain inspection-only. This is not formal
    SupportClaim resolution or predicate implication. -/
def resolveEngineeringRequirementsV1
    (selection : ResolvedBuildSelectionV1)
    (compiled : CompiledSemanticV1) :
    CompileResult ResolvedEngineeringBuildV1 := do
  let supportIndex ← initialStaticRequirementSupportIndexV1Result
  let inspection ← inspectSupportWithSeedV1 (.ok supportIndex)
    selection.targetId selection.codegenProfile
  unless inspection.kind == selection.kind do
    throw <| .registryInvalid
      "engineering support row kind diverges from resolved selection"
  let data ← match validateSemanticProgramV1 (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok value => pure value
    | .error _ =>
        throw <| .registryInvalid
          "engineering resolver: retained SemanticProgramV1 failed structure validation"
  let requested : ProgramRequirementsV1 := data.requirements
  inspectResolveRequestsV1 inspection.supported requested
  let descriptor ← match descriptorForKind? selection.kind with
    | some value => pure value
    | none => throw <| .targetNotImplemented selection.kind
  unless descriptor.targetId == selection.targetId do
    throw <| .registryInvalid
      "descriptor target identity diverges from resolved selection"
  -- The descriptor carries the default profile; the registry profile axis may
  -- admit additional exact profiles through
  -- DescriptorDataV1.acceptsCodegenProfile.
  unless DescriptorDataV1.acceptsCodegenProfile descriptor selection.codegenProfile do
    throw <| .registryInvalid
      "descriptor codegen profile diverges from resolved selection"
  let registry ← initialTargetRegistryV1Result
  let registration ← match findRegistrationV1 registry selection.targetId with
    | some value => pure value
    | none =>
        throw <| .registryInvalid
          "engineering resolver: selection target missing from frozen registry"
  unless registration.kind == selection.kind do
    throw <| .registryInvalid
      "engineering resolver: descriptor registration kind diverges from selection"
  validateDescriptorAxesJoinV1 registration descriptor
  let claims ← match mintEngineeringSupportClaimsV1 registry supportIndex with
    | .ok value => pure value
    | .error e =>
        throw <| .registryInvalid s!"engineering support claim mint failed: {e}"
  let supportClaim ← match
      findEngineeringSupportClaimV1 claims selection.targetId selection.codegenProfile with
    | some claim => pure claim
    | none =>
        throw <| .registryInvalid
          s!"no engineering support claim for target '{selection.targetId}' profile '{selection.codegenProfile}'"
  unless EngineeringSupportClaimV1.targetIdOf supportClaim == selection.targetId do
    throw <| .registryInvalid
      "engineering support claim target diverges from selection"
  unless EngineeringSupportClaimV1.codegenProfileOf supportClaim == selection.codegenProfile do
    throw <| .registryInvalid
      "engineering support claim profile diverges from selection"
  unless EngineeringSupportClaimV1.supportedOf supportClaim == inspection.supported do
    throw <| .registryInvalid
      "engineering support claim supported row diverges from support index"
  pure (ResolvedEngineeringBuildV1.mk selection compiled requested supportClaim
    none)

/-- Compose successful results of every existing engineering-resolver stage.
    This is a proof decomposition of the sole production resolver: it neither
    constructs a second request resolver nor exposes the private capability
    constructor to callers. -/
theorem resolveEngineeringRequirementsV1_exists_of_stages
    (selection : ResolvedBuildSelectionV1)
    (compiled : CompiledSemanticV1)
    (supportIndex : StaticRequirementSupportIndexV1)
    (inspection : RequirementResolutionInspectionV1)
    (data : SemanticProgramDataV1)
    (descriptor : TargetDescriptor)
    (registry : TargetRegistryV1)
    (registration : TargetRegistrationDataV1)
    (claims : Array EngineeringSupportClaimV1)
    (supportClaim : EngineeringSupportClaimV1)
    (hindex : initialStaticRequirementSupportIndexV1Result = .ok supportIndex)
    (hinspection : inspectSupportWithSeedV1 (.ok supportIndex)
      selection.targetId selection.codegenProfile = .ok inspection)
    (hkind : (inspection.kind == selection.kind) = true)
    (hdata : validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) = .ok data)
    (hrequests : inspectResolveRequestsV1 inspection.supported
      data.requirements = .ok ())
    (hdescriptor : descriptorForKind? selection.kind = some descriptor)
    (hdescriptorTarget : (descriptor.targetId == selection.targetId) = true)
    (hdescriptorProfile :
      DescriptorDataV1.acceptsCodegenProfile descriptor
        selection.codegenProfile = true)
    (hregistry : initialTargetRegistryV1Result = .ok registry)
    (hregistration : findRegistrationV1 registry selection.targetId =
      some registration)
    (hregistrationKind : (registration.kind == selection.kind) = true)
    (hdescriptorJoin : validateDescriptorAxesJoinV1 registration descriptor =
      .ok ())
    (hclaims : mintEngineeringSupportClaimsV1 registry supportIndex = .ok claims)
    (hclaim : findEngineeringSupportClaimV1 claims selection.targetId
      selection.codegenProfile = some supportClaim)
    (hclaimTarget :
      (EngineeringSupportClaimV1.targetIdOf supportClaim ==
        selection.targetId) = true)
    (hclaimProfile :
      (EngineeringSupportClaimV1.codegenProfileOf supportClaim ==
        selection.codegenProfile) = true)
    (hclaimSupported :
      (EngineeringSupportClaimV1.supportedOf supportClaim ==
        inspection.supported) = true) :
    ∃ capability,
      resolveEngineeringRequirementsV1 selection compiled = .ok capability := by
  unfold resolveEngineeringRequirementsV1
  simp only [hindex, hinspection, hkind, ↓reduceIte,
    hdata, hrequests, hdescriptor, hdescriptorTarget, hdescriptorProfile,
    hregistry, hregistration, hregistrationKind, hdescriptorJoin, hclaims,
    hclaim, hclaimTarget, hclaimProfile, hclaimSupported, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  exact ⟨_, rfl⟩

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
/-- A compiled semantic carrier whose retained requirements pass the exact
    frozen Solana production support row can cross the sole engineering
    capability resolver. Static registry, descriptor, claim-mint and identity
    joins are replayed here; callers still supply the real compiler-validation
    and exact request-resolution equations. -/
theorem resolveEngineeringRequirementsV1_solana_sbpf_cpi_elf_exists
    (selection : ResolvedBuildSelectionV1)
    (compiled : CompiledSemanticV1)
    (data : SemanticProgramDataV1)
    (htarget : ResolvedBuildSelectionV1.targetIdOf selection = TargetId.solana)
    (hprofile : ResolvedBuildSelectionV1.codegenProfileOf selection =
      CodegenProfileId.solanaSbpfCpiElfV1)
    (hkind : ResolvedBuildSelectionV1.kindOf selection = .solana)
    (hdata : validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) = .ok data)
    (hrequests : inspectResolveRequestsV1 initialSolanaSupportRowV1.supported
      data.requirements = .ok ()) :
    ∃ capability,
      resolveEngineeringRequirementsV1 selection compiled = .ok capability := by
  rcases initialStaticRequirementSupportIndexV1Result_exists with
    ⟨supportIndex, hindex⟩
  let inspection : RequirementResolutionInspectionV1 := {
    targetId := initialSolanaSupportRowV1.targetId
    codegenProfile := initialSolanaSupportRowV1.codegenProfile
    kind := initialSolanaSupportRowV1.kind
    supported := initialSolanaSupportRowV1.supported
  }
  rcases initialTargetRegistryV1Result_exists with ⟨registry, hregistry⟩
  let descriptor := DescriptorDataV1.solana
  let registration := solanaRegistrationRowV1
  have htargetField : selection.targetId = TargetId.solana := by
    exact htarget
  have hprofileField : selection.codegenProfile =
      CodegenProfileId.solanaSbpfCpiElfV1 := by
    exact hprofile
  have hkindField : selection.kind = .solana := by
    exact hkind
  have hinspection : inspectSupportWithSeedV1 (.ok supportIndex)
      selection.targetId selection.codegenProfile = .ok inspection := by
    have hstatic := inspectSupportWithSeedV1_initial_solana_eq_ok
    rw [hindex] at hstatic
    simpa only [inspection, htargetField, hprofileField] using hstatic
  have hinspectionKind : (inspection.kind == selection.kind) = true := by
    rw [hkindField]
    rfl
  have hdescriptor : descriptorForKind? selection.kind = some descriptor := by
    rw [hkindField]
    rfl
  have hdescriptorTarget :
      (descriptor.targetId == selection.targetId) = true := by
    rw [htargetField]
    rfl
  have hdescriptorProfile :
      DescriptorDataV1.acceptsCodegenProfile descriptor
        selection.codegenProfile = true := by
    rw [hprofileField]
    rfl
  have hregistration : findRegistrationV1 registry selection.targetId =
      some registration := by
    rw [htargetField]
    have hseed : registrationWithSeedV1 initialTargetRegistryV1Result
        TargetId.solana = .ok (some registration) := by
      unfold registrationWithSeedV1
      rw [initialTargetRegistryV1Result_eq_ok]
      simp only [Bind.bind, Except.bind,
        findRegistrationV1_initial_solana_eq_some, Pure.pure, Except.pure,
        registration]
    rw [hregistry] at hseed
    simp only [registrationWithSeedV1, Bind.bind, Except.bind, Pure.pure,
      Except.pure] at hseed
    injection hseed
  have hregistrationKind : (registration.kind == selection.kind) = true := by
    rw [hkindField]
    rfl
  have hdescriptorJoin : validateDescriptorAxesJoinV1 registration descriptor =
      .ok () := by
    rfl
  rcases mintEngineeringSupportClaimsV1_initial_exists registry supportIndex
      hregistry hindex with
    ⟨claims, supportClaim, hclaims, hclaimStatic, hclaimTargetEq,
      hclaimProfileEq, hclaimSupportedEq⟩
  have hclaim : findEngineeringSupportClaimV1 claims selection.targetId
      selection.codegenProfile = some supportClaim := by
    simpa only [htargetField, hprofileField] using hclaimStatic
  have hclaimTarget :
      (EngineeringSupportClaimV1.targetIdOf supportClaim ==
        selection.targetId) = true := by
    rw [hclaimTargetEq, htargetField]
    rw [TargetId.beq_eq_toString]
    rfl
  have hclaimProfile :
      (EngineeringSupportClaimV1.codegenProfileOf supportClaim ==
        selection.codegenProfile) = true := by
    rw [hclaimProfileEq, hprofileField]
    rw [CodegenProfileId.beq_eq_toString]
    rfl
  have hclaimSupported :
      (EngineeringSupportClaimV1.supportedOf supportClaim ==
        inspection.supported) = true := by
    rw [hclaimSupportedEq]
    unfold inspection
    exact initialSolanaSupportRowV1_supported_beq_self
  exact resolveEngineeringRequirementsV1_exists_of_stages selection compiled
    supportIndex inspection data descriptor registry registration claims
    supportClaim hindex hinspection hinspectionKind hdata
    (by simpa only [inspection] using hrequests) hdescriptor
    hdescriptorTarget hdescriptorProfile hregistry hregistration
    hregistrationKind hdescriptorJoin hclaims hclaim hclaimTarget
    hclaimProfile hclaimSupported

/-- Enrich an already-resolved NEAR capability with invariant-erasure authority.
    This is not a second `(selection, compiled)` capability mint: requirements,
    support claim, selection and compiled carrier are retained unchanged. The
    private certifier carrier must bind the exact compiled source/semantic
    digests and completely cover every invariant with an audited preserving
    theorem. -/
def authorizeCertifiedNearInvariantErasureV1
    (capability : ResolvedEngineeringBuildV1)
    (certificate : CertifiedInlineProofV1) :
    CompileResult ResolvedEngineeringBuildV1 := do
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  unless selection.kind == .near do
    throw <| .planInvariant selection.kind
      "proof-only invariant erasure is currently authorized only for NEAR"
  unless (ResolvedEngineeringBuildV1.nearInvariantErasureAuthorization? capability).isNone do
    throw <| .planInvariant .near
      "proof-only invariant erasure authorization is already present"
  let data ← match validateSemanticProgramV1 (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok value => pure value
    | .error _ =>
        throw <| .registryInvalid
          "proof-bearing authorization: retained SemanticProgramV1 failed structure validation"
  unless CertifiedInlineProofV1.sourceDigest certificate ==
        CompiledSemanticV1.sourceDigestOf compiled do
    throw <| .registryInvalid
      "proof-bearing authorization: certificate source digest does not bind the compiled program"
  unless CertifiedInlineProofV1.semanticDigest certificate ==
        CompiledSemanticV1.semanticDigestOf compiled do
    throw <| .registryInvalid
      "proof-bearing authorization: certificate semantic digest does not bind the compiled program"
  unless CertifiedInlineProofV1.hasCompletePreservingInvariantCoverage certificate do
    throw <| .planInvariant .near
      "proof-only invariant erasure requires one audited preserving proof for every invariant"
  unless !data.invariants.isEmpty do
    throw <| .planInvariant .near
      "proof-only invariant erasure requires a nonempty invariant table"
  let authorization : NearInvariantErasureAuthorizationV1 := ⟨
    CertifiedInlineProofV1.sourceDigest certificate,
    CertifiedInlineProofV1.semanticDigest certificate,
    CertifiedInlineProofV1.proofCertificationDigest certificate,
    data.invariants.size⟩
  pure { capability with nearInvariantErasure? := some authorization }

end ProofForgeV2.Targets

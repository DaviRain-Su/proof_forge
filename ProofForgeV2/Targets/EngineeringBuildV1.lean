/-
  Private engineering materialize/emit capability leaf (D3/S6 + M3b claim bind).

  Cycle-free: BuildSelectionV1, RequirementResolverV1, SupportClaimV1,
  TargetRegistryV1, Pipeline, WireV1, RequirementsV1, DescriptorDataV1 —
  does not import target Plan modules or Registry.

  Sole mint of `ResolvedEngineeringBuildV1`:
  `resolveEngineeringRequirementsV1`. The exact retained
  `SemanticProgramV1.data.requirements` is the only request authority; there is
  no caller override, alpha parity path, or re-inference.

  M3b binds the selected engineering SupportClaim (registry-root anchored) into
  the capability. Not formal SupportClaim / formal registry root or digest /
  formal BuildIdentity / OutputSetV1 / complete SemanticProgramV1 lowering.
-/
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.SupportClaimV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.RequirementsV1

namespace ProofForgeV2.Targets

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.SupportClaimV1
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Semantic.RequirementsV1

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

end ResolvedEngineeringBuildV1

/-- Sole constructor of `ResolvedEngineeringBuildV1`.

    Signature: `(selection, compiled)` only — no caller-supplied requirements.

    Order:
    1. bind the frozen engineering support seed;
    2. exact target/profile support-row match;
    3. validate the retained semantic carrier and exact-resolve its embedded
       requirements (unknown/version/digest/no support → PF-REQ-UNSUPPORTED;
       predicates → PF-REQ-PRECONDITION);
    4. bind descriptor target/profile identity;
    5. mint engineering SupportClaims over the frozen registry + support index
       and bind the selected claim (target/profile + supported row must match);
    6. mint the private capability with the unchanged request set + claim.

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
  -- Residual descriptor binds the default profile; multi-profile targets
  -- (Solana plan + elf) accept additional registered profiles via
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
  pure (ResolvedEngineeringBuildV1.mk selection compiled requested supportClaim)

end ProofForgeV2.Targets

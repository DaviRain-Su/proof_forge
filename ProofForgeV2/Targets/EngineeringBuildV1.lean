/-
  Private engineering materialize/emit capability leaf (D3/S6).

  Cycle-free: BuildSelectionV1, RequirementResolverV1, Pipeline, WireV1,
  RequirementsV1, DescriptorDataV1 — does **not** import Evm/Solana/Near/Noir
  Plan modules or Registry.

  Sole mint of `ResolvedEngineeringBuildV1`: `resolveEngineeringRequirementsV1`.
  Exact retained SemanticProgramV1 `data.requirements` authority; dual-carrier
  mapped-S2 parity; no caller request override.

  **Not** SupportClaim / TargetRegistryV1 / formal resolver / BuildIdentity /
  OutputSetV1 / SemanticProgramV1 native Plan lowering.
-/
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.RequirementsV1

namespace ProofForgeV2.Targets

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Semantic.RequirementsV1

/-- Private engineering materialize/emit capability.
    Contains frozen selection, dual-carrier compiled program, and the exact
    retained `SemanticProgramV1` ProgramRequirementsV1 freeze (never a caller
    empty/subset override). **Not** SupportClaim / ResolvedSupportDecision /
    BuildIdentity. Sole mint: `resolveEngineeringRequirementsV1`. -/
structure ResolvedEngineeringBuildV1 where
  private mk ::
  selection : ResolvedBuildSelectionV1
  compiled : CompiledProgramV1
  requirements : ProgramRequirementsV1

namespace ResolvedEngineeringBuildV1

def selectionOf (c : ResolvedEngineeringBuildV1) : ResolvedBuildSelectionV1 :=
  c.selection

def compiledOf (c : ResolvedEngineeringBuildV1) : CompiledProgramV1 :=
  c.compiled

def requirementsOf (c : ResolvedEngineeringBuildV1) : ProgramRequirementsV1 :=
  c.requirements

def kindOf (c : ResolvedEngineeringBuildV1) : TargetKind :=
  c.selection.kind

def targetIdOf (c : ResolvedEngineeringBuildV1) : TargetId :=
  c.selection.targetId

def codegenProfileOf (c : ResolvedEngineeringBuildV1) : CodegenProfileId :=
  c.selection.codegenProfile

end ResolvedEngineeringBuildV1

private def countAlpha (reqs : Array ProgramRequirement) (want : ProgramRequirement) : Nat :=
  reqs.foldl (fun n r => if r == want then n + 1 else n) 0

private def countV1Ids (items : Array RequirementRequestV1) (want : String) : Nat :=
  items.foldl (fun n r => if r.id == want then n + 1 else n) 0

/-- Accepted V1 → residual alpha mapped-S2 join via the shared Compiler bridge
    (no duplicated string maps). Product mint always accepts the full retained
    `SemanticProgramV1.data.requirements` (no caller subset/empty override).
    Each accepted catalog id must be present exactly once on residual alpha.
    Reverse full-set equality is dual-carrier's job at compile time; this check
    is defense-in-depth. Drift is `PF-REGISTRY-INVALID`, not SupportClaim. -/
private def validateMappedS2ParityV1
    (accepted : ProgramRequirementsV1) (alpha : Semantic.Program) :
    CompileResult Unit := do
  let items := accepted.items
  for item in items do
    unless countV1Ids items item.id == 1 do
      throw <| .registryInvalid
        s!"engineering resolver: duplicate accepted V1 requirement id '{item.id}'"
  for item in items do
    match mappedAlphaOfV1Id? item.id with
    | none =>
        pure ()
    | some alphaReq =>
        unless countAlpha alpha.requirements alphaReq == 1 do
          throw <| .registryInvalid
            s!"engineering resolver: residual alpha missing mapped requirement for '{item.id}'"
  pure ()

/-- Sole constructor of `ResolvedEngineeringBuildV1`.

    Signature: `(selection, compiled)` only — no caller-supplied requirements.

    1. Bind frozen engineering support seed (`CompileResult`).
    2. Exact (targetId, codegenProfile) support-row match.
    3. Decode retained `CompiledProgramV1.semanticV1Of compiled` and exact-resolve
       its `data.requirements` against the row (empty preds only; unknown/version/
       digest/no support → `PF-REQ-UNSUPPORTED`; nonempty predicates →
       `PF-REQ-PRECONDITION`). Never replace, filter, empty, or subset that set.
    4. Residual descriptor target/profile parity vs selection; exact mapped-S2
       parity vs residual alpha via shared Compiler bridge (drift →
       `PF-REGISTRY-INVALID`).
    5. Mint private capability storing the same retained requirements.

    Arbitrary request matrices live only on non-capability inspection seams
    (`inspectResolveRequestsV1` / `inspectResolveWithSeedV1`).
    Not SupportClaim / formal resolver / predicate implication. -/
def resolveEngineeringRequirementsV1
    (selection : ResolvedBuildSelectionV1)
    (compiled : CompiledProgramV1) :
    CompileResult ResolvedEngineeringBuildV1 := do
  let insp ← inspectSupportWithSeedV1 initialStaticRequirementSupportIndexV1Result
    selection.targetId selection.codegenProfile
  unless insp.kind == selection.kind do
    throw <| .registryInvalid
      "engineering support row kind diverges from resolved selection"
  let semanticV1 := CompiledProgramV1.semanticV1Of compiled
  let data ← match validateSemanticProgramV1 semanticV1 with
    | .ok d => pure d
    | .error _ =>
        throw <| .registryInvalid
          "engineering resolver: retained SemanticProgramV1 failed structure validation"
  let requested : ProgramRequirementsV1 := data.requirements
  inspectResolveRequestsV1 insp.supported requested
  let descriptor ← match descriptorForKind? selection.kind with
    | some d => pure d
    | none => throw <| .targetNotImplemented selection.kind
  unless descriptor.targetId == selection.targetId do
    throw <| .registryInvalid
      "descriptor target identity diverges from resolved selection"
  unless descriptor.codegenProfile == selection.codegenProfile do
    throw <| .registryInvalid
      "descriptor codegen profile diverges from resolved selection"
  let alpha := CompiledProgramV1.alphaResidualOf compiled
  validateMappedS2ParityV1 requested alpha
  pure (ResolvedEngineeringBuildV1.mk selection compiled requested)

end ProofForgeV2.Targets

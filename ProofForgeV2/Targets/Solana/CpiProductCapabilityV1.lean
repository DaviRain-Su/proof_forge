/-
  ProofForgeV2.Targets.Solana.CpiProductCapabilityV1 — #125 product CPI capability.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole refine: `resolveSolanaCpiProductCapabilityV1` :
  `ResolvedEngineeringBuildV1 → CompileResult ResolvedSolanaCpiProductCapabilityV1`.

  Accepts only exact `(solana, solana-sbpf-cpi-elf-v1)` selection whose retained
  Semantic requirements and engineering SupportClaim both contain the active
  exact `effect.synchronous-call` S2 row and the ADR-0028 extension row, and
  neither contains `effect.asynchronous-workflow`. Retained Semantic /
  requirements bytes are never rewritten.

  No conversion function exists to/from `ResolvedSolanaCpiPreflightV1`
  (activationDenied preflight lane stays independent). Ordinary resolution
  advertises sync+extension only for this exact profile; this refine succeeds
  only when that engineering capability already carries both rows.
-/
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.SupportClaimV1
import ProofForgeV2.Targets.RequirementResolverV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.SupportClaimV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Core.RequirementIdsV1

/-- Private #125 product CPI capability. Holds the engineering capability under
    exact solana+cpi profile with sync+extension support. Not convertible to
    preflight/activationDenied carriers. -/
structure ResolvedSolanaCpiProductCapabilityV1 where
  private mk ::
  engineering : ResolvedEngineeringBuildV1

namespace ResolvedSolanaCpiProductCapabilityV1

def engineeringOf (c : ResolvedSolanaCpiProductCapabilityV1) :
    ResolvedEngineeringBuildV1 :=
  c.engineering

def selectionOf (c : ResolvedSolanaCpiProductCapabilityV1) :
    ResolvedBuildSelectionV1 :=
  ResolvedEngineeringBuildV1.selectionOf c.engineering

def compiledOf (c : ResolvedSolanaCpiProductCapabilityV1) : CompiledSemanticV1 :=
  ResolvedEngineeringBuildV1.compiledOf c.engineering

def requirementsOf (c : ResolvedSolanaCpiProductCapabilityV1) :
    ProgramRequirementsV1 :=
  ResolvedEngineeringBuildV1.requirementsOf c.engineering

def supportClaimOf (c : ResolvedSolanaCpiProductCapabilityV1) :
    EngineeringSupportClaimV1 :=
  ResolvedEngineeringBuildV1.supportClaimOf c.engineering

/-- Product capability is never activation-denied. -/
def activationDeniedOf (_ : ResolvedSolanaCpiProductCapabilityV1) : Bool :=
  false

end ResolvedSolanaCpiProductCapabilityV1

private def productCapFail (detail : String) : CompileResult α :=
  throw (.unsupportedRequirementV1 detail)

private def requestExact
    (items : Array RequirementRequestV1) (expected : RequirementRequestV1) : Bool :=
  items.any (fun r =>
    r.id == expected.id && r.version == expected.version && r.digest == expected.digest &&
      r.predicates.isEmpty && expected.predicates.isEmpty)

private def hasRequestId (items : Array RequirementRequestV1) (id : String) : Bool :=
  items.any (fun r => r.id == id)

/-- Sole refine of `ResolvedSolanaCpiProductCapabilityV1` from an ordinary
    engineering capability.

    Order:
    1. selection identity must be solana + `solana-sbpf-cpi-elf-v1`;
    2. retained Semantic structure-validate;
    3. retained requirements must equal the engineering capability freeze;
    4. require exact deferred `effect.synchronous-call` in requested AND support claim;
    5. require exact ADR-0028 extension in requested AND support claim;
    6. reject `effect.asynchronous-workflow` in requested AND support claim;
    7. mint private product capability (no activationDenied, no preflight conversion).
-/
def resolveSolanaCpiProductCapabilityV1
    (engineering : ResolvedEngineeringBuildV1) :
    CompileResult ResolvedSolanaCpiProductCapabilityV1 := do
  let selection := ResolvedEngineeringBuildV1.selectionOf engineering
  unless selection.targetId == TargetId.solana do
    productCapFail
      s!"Solana CPI product requires target 'solana', got '{selection.targetId}'"
  unless selection.kind == TargetKind.solana do
    productCapFail "Solana CPI product selection kind must be solana"
  unless selection.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1 do
    productCapFail
      s!"Solana CPI product requires profile 'solana-sbpf-cpi-elf-v1', got '{selection.codegenProfile}'"

  let compiled := ResolvedEngineeringBuildV1.compiledOf engineering
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok value => pure value
    | .error _ =>
        throw <| .registryInvalid
          "Solana CPI product: retained SemanticProgramV1 failed structure validation"
  let requested : ProgramRequirementsV1 := data.requirements
  let engReqs := ResolvedEngineeringBuildV1.requirementsOf engineering
  unless requested == engReqs do
    productCapFail
      "Solana CPI product: retained Semantic requirements diverge from engineering freeze"

  let syncReq ← match mkS2RequirementRequestV1 s2EffectSyncCallIdV1 with
    | .ok r => pure r
    | .error e =>
        productCapFail s!"Solana CPI product: sync requirement seed failed: {e}"
  let asyncReq ← match mkS2RequirementRequestV1 s2EffectAsyncWorkflowIdV1 with
    | .ok r => pure r
    | .error e =>
        productCapFail s!"Solana CPI product: async requirement seed failed: {e}"
  let extensionReq ← match solanaCpiAccountsExtensionRequirementV1 with
    | .ok r => pure r
    | .error e =>
        productCapFail s!"Solana CPI product: extension requirement seed failed: {e}"

  unless requestExact requested.items syncReq do
    productCapFail
      s!"Solana CPI product requires exact deferred requirement '{s2EffectSyncCallIdV1}'"
  if requestExact requested.items asyncReq ||
      hasRequestId requested.items s2EffectAsyncWorkflowIdV1 then
    productCapFail
      s!"Solana CPI product rejects '{s2EffectAsyncWorkflowIdV1}'"
  unless requestExact requested.items extensionReq do
    productCapFail
      s!"Solana CPI product requires exact extension requirement '{extensionReq.id}'"

  let claim := ResolvedEngineeringBuildV1.supportClaimOf engineering
  let supported := EngineeringSupportClaimV1.supportedOf claim
  unless requestExact supported syncReq do
    productCapFail
      s!"Solana CPI product SupportClaim must include exact '{s2EffectSyncCallIdV1}'"
  unless requestExact supported extensionReq do
    productCapFail
      s!"Solana CPI product SupportClaim must include exact extension '{extensionReq.id}'"
  if requestExact supported asyncReq ||
      hasRequestId supported s2EffectAsyncWorkflowIdV1 then
    productCapFail
      s!"Solana CPI product SupportClaim rejects '{s2EffectAsyncWorkflowIdV1}'"

  pure (ResolvedSolanaCpiProductCapabilityV1.mk engineering)

end ProofForgeV2.Targets.Solana.CpiV1

/-
  ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1 — #118 lane A
  private Solana CPI preflight carrier.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole mint: `resolveSolanaCpiPreflightV1`. Accepts only
  `(solana, solana-sbpf-cpi-elf-v1)` selection plus retained Semantic whose
  exact ProgramRequirements contain the ADR-0024 extension row and the
  deferred exact `effect.synchronous-call` S2 row. All other requested rows
  are resolved solely through product `RequirementResolverV1` support +
  `inspectResolveRequestsV1` (no second support-predicate algorithm).

  Carrier is activation-denied: it never converts to
  `ResolvedEngineeringBuildV1`, never mints OutputFile, and never authorizes
  product materialization. After #125, ordinary resolution admits sync only for
  the exact CPI product profile; that independent product path must never consume
  or reinterpret this historical preflight carrier.
-/
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.RequirementResolverV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Core.RequirementIdsV1

/-- Private #118 CPI preflight capability. Holds the resolved selection and
    retained compiled semantic under activationDenied=true. Not a product
    materialize capability and not convertible to `ResolvedEngineeringBuildV1`. -/
structure ResolvedSolanaCpiPreflightV1 where
  private mk ::
  selection : ResolvedBuildSelectionV1
  compiled : CompiledSemanticV1
  requirements : ProgramRequirementsV1
  /-- Always `true` by construction. Product activation / artifact mint stays
      denied while this carrier exists. -/
  activationDenied : Bool

namespace ResolvedSolanaCpiPreflightV1

def selectionOf (c : ResolvedSolanaCpiPreflightV1) : ResolvedBuildSelectionV1 :=
  c.selection

def compiledOf (c : ResolvedSolanaCpiPreflightV1) : CompiledSemanticV1 :=
  c.compiled

def requirementsOf (c : ResolvedSolanaCpiPreflightV1) : ProgramRequirementsV1 :=
  c.requirements

/-- Product activation is always denied for this carrier. -/
def activationDeniedOf (c : ResolvedSolanaCpiPreflightV1) : Bool :=
  c.activationDenied

end ResolvedSolanaCpiPreflightV1

private def preflightFail (detail : String) : CompileResult α :=
  throw (.unsupportedRequirementV1 detail)

private def requestExact
    (items : Array RequirementRequestV1) (expected : RequirementRequestV1) : Bool :=
  items.any (fun r =>
    r.id == expected.id && r.version == expected.version && r.digest == expected.digest &&
      r.predicates.isEmpty && expected.predicates.isEmpty)

/-- Sole mint of `ResolvedSolanaCpiPreflightV1`.

    Order:
    1. selection identity must be solana + `solana-sbpf-cpi-elf-v1`;
    2. retained Semantic structure-validate;
    3. product support row via `inspectSupportForSelectionV1`;
    4. require exact deferred `effect.synchronous-call` S2 row in requested;
    5. reject `effect.asynchronous-workflow` if present;
    6. require exact ADR-0024 extension row in requested;
    7. resolve every requested row **except** the deferred sync row through
       sole `inspectResolveRequestsV1` against the product support row;
    8. mint private carrier with `activationDenied := true`.

    Does not mint `ResolvedEngineeringBuildV1` or OutputFile. -/
def resolveSolanaCpiPreflightV1
    (selection : ResolvedBuildSelectionV1)
    (compiled : CompiledSemanticV1) :
    CompileResult ResolvedSolanaCpiPreflightV1 := do
  unless selection.targetId == TargetId.solana do
    preflightFail
      s!"Solana CPI preflight requires target 'solana', got '{selection.targetId}'"
  unless selection.kind == TargetKind.solana do
    preflightFail "Solana CPI preflight selection kind must be solana"
  unless selection.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1 do
    preflightFail
      s!"Solana CPI preflight requires profile 'solana-sbpf-cpi-elf-v1', got '{selection.codegenProfile}'"

  let inspection ← inspectSupportForSelectionV1 selection
  unless inspection.kind == selection.kind do
    throw <| .registryInvalid
      "Solana CPI preflight support row kind diverges from resolved selection"
  unless inspection.targetId == selection.targetId do
    throw <| .registryInvalid
      "Solana CPI preflight support row target diverges from resolved selection"
  unless inspection.codegenProfile == selection.codegenProfile do
    throw <| .registryInvalid
      "Solana CPI preflight support row profile diverges from resolved selection"

  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok value => pure value
    | .error _ =>
        throw <| .registryInvalid
          "Solana CPI preflight: retained SemanticProgramV1 failed structure validation"
  let requested : ProgramRequirementsV1 := data.requirements

  let syncReq ← match mkS2RequirementRequestV1 s2EffectSyncCallIdV1 with
    | .ok r => pure r
    | .error e =>
        preflightFail s!"Solana CPI preflight: sync requirement seed failed: {e}"
  let asyncReq ← match mkS2RequirementRequestV1 s2EffectAsyncWorkflowIdV1 with
    | .ok r => pure r
    | .error e =>
        preflightFail s!"Solana CPI preflight: async requirement seed failed: {e}"
  let extensionReq ← match solanaCpiAccountsExtensionRequirementV1 with
    | .ok r => pure r
    | .error e =>
        preflightFail s!"Solana CPI preflight: extension requirement seed failed: {e}"

  -- Deferred sync must be exact; ordinary product support still declines it.
  unless requestExact requested.items syncReq do
    preflightFail
      s!"Solana CPI preflight requires exact deferred requirement '{s2EffectSyncCallIdV1}'"
  if requestExact requested.items asyncReq ||
      requested.items.any (fun r => r.id == s2EffectAsyncWorkflowIdV1) then
    preflightFail
      s!"Solana CPI preflight rejects '{s2EffectAsyncWorkflowIdV1}'"
  unless requestExact requested.items extensionReq do
    preflightFail
      s!"Solana CPI preflight requires exact extension requirement '{extensionReq.id}'"

  -- All non-sync requested rows use sole product support matching. Sync is
  -- deliberately stripped so we never invent a second support row algorithm
  -- that claims effect.synchronous-call on the product index.
  let withoutSync : ProgramRequirementsV1 := {
    items := requested.items.filter (fun r => r.id != s2EffectSyncCallIdV1)
  }
  inspectResolveRequestsV1 inspection.supported withoutSync

  pure (ResolvedSolanaCpiPreflightV1.mk selection compiled requested true)

end ProofForgeV2.Targets.Solana.CpiV1

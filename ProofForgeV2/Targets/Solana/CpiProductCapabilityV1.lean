/-
  ProofForgeV2.Targets.Solana.CpiProductCapabilityV1 — #125 product CPI capability.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole refine: `resolveSolanaCpiProductCapabilityV1` :
  `ResolvedEngineeringBuildV1 → CompileResult ResolvedSolanaCpiProductCapabilityV1`.

  Accepts only exact `(solana, solana-sbpf-cpi-elf-v1)` selection. Closed
  admission modes (at least one required):

  1. **sync + extension** — exact `effect.synchronous-call` plus ADR-0028
     `extension.solana-cpi-accounts` and/or ADR-0029 `extension.pf-assets`
     (each present extension must also appear on the SupportClaim; sync must
     appear on SupportClaim when requested);
  2. **pf.assets envRead-only** — exact `extension.pf-assets` without sync-call
     (env-read programs; SupportClaim must carry pf.assets);
  3. **caller-only** — exact wire-owned `context.caller` requirement row
     (`callerContextRequirementV1`) without sync-call or either extension.
     Caller is wire-owned / target-independent in the engineering resolver, so
     it is **not** required on `EngineeringSupportClaim`. Near-miss/nonexact
     caller rows are already rejected by retained structure/resolver;
  4. **body-only** (ADR-0032 U1 P4) — no sync-call, no async, no solana CPI
     extension, no pf.assets, no context.caller. Ordinary Counter/Map body
     programs on the sole rail. Plan admission marker is
     `bodyOnlyAdmissionRequirementV1` (not a source freeze row).

  Neither requested freeze nor SupportClaim may carry
  `effect.asynchronous-workflow`. Retained Semantic / requirements bytes are
  never rewritten.

  No conversion function exists to/from `ResolvedSolanaCpiPreflightV1`
  (activationDenied preflight lane stays independent). Ordinary resolution
  advertises sync + both closed extensions for this exact profile; this refine
  succeeds for the closed admission modes above.
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
    exact solana+cpi profile with a closed admission mode (sync+extension,
    pf.assets envRead-only, or caller-only). Not convertible to
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
    4. admit at least one closed mode:
       - sync+extension (solana.cpi.accounts and/or pf.assets), or
       - pf.assets envRead-only (no sync), or
       - exact wire-owned `context.caller` only (no sync, no extension);
    5. each present extension must also be on the SupportClaim; sync on claim
       only when requested; caller is **not** required on SupportClaim;
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
  let solanaExtReq ← match solanaCpiAccountsExtensionRequirementV1 with
    | .ok r => pure r
    | .error e =>
        productCapFail s!"Solana CPI product: solana.cpi.accounts seed failed: {e}"
  let pfAssetsReq ← match pfAssetsExtensionRequirementV1 with
    | .ok r => pure r
    | .error e =>
        productCapFail s!"Solana CPI product: pf.assets seed failed: {e}"
  let callerReq ← match callerContextRequirementV1 with
    | .ok r => pure r
    | .error e =>
        productCapFail s!"Solana CPI product: context.caller requirement seed failed: {e}"

  let hasSolanaExt := requestExact requested.items solanaExtReq
  let hasPfAssets := requestExact requested.items pfAssetsReq
  let hasCallerContext := requestExact requested.items callerReq
  let hasSyncCall := requestExact requested.items syncReq
  let hasAsync :=
    requestExact requested.items asyncReq ||
      hasRequestId requested.items s2EffectAsyncWorkflowIdV1
  if hasAsync then
    productCapFail
      s!"Solana CPI product rejects '{s2EffectAsyncWorkflowIdV1}'"
  -- Closed admission:
  --   * sync+extension (solana.cpi.accounts and/or pf.assets)
  --   * pf.assets envRead-only or caller-only (no sync)
  --   * body-only (no sync, no ext, no pf.assets, no caller) — sole-rail plain body
  let bodyOnly :=
    !hasSyncCall && !hasSolanaExt && !hasPfAssets && !hasCallerContext
  unless hasSolanaExt || hasPfAssets || hasCallerContext || bodyOnly do
    productCapFail
      "Solana CPI product requires exact extension.solana-cpi-accounts, extension.pf-assets, context.caller, or body-only"
  -- Without sync-call: pf.assets / caller-only / body-only are legal.
  -- solana.cpi.accounts alone without sync stays fail-closed.
  unless hasSyncCall do
    unless hasPfAssets || hasCallerContext || bodyOnly do
      productCapFail
        s!"Solana CPI product requires exact deferred requirement '{s2EffectSyncCallIdV1}', extension.pf-assets envRead-only, context.caller, or body-only"
  -- Sync without any CPI/assets extension stays fail-closed (no naked sync).
  if hasSyncCall then
    unless hasSolanaExt || hasPfAssets do
      productCapFail
        "Solana CPI product sync-call requires exact extension.solana-cpi-accounts and/or extension.pf-assets"

  let claim := ResolvedEngineeringBuildV1.supportClaimOf engineering
  let supported := EngineeringSupportClaimV1.supportedOf claim
  -- SupportClaim sync-call check only when the program freezes sync-call.
  if hasSyncCall then
    unless requestExact supported syncReq do
      productCapFail
        s!"Solana CPI product SupportClaim must include exact '{s2EffectSyncCallIdV1}'"
  if hasSolanaExt then
    unless requestExact supported solanaExtReq do
      productCapFail
        s!"Solana CPI product SupportClaim must include exact '{solanaExtReq.id}'"
  if hasPfAssets then
    unless requestExact supported pfAssetsReq do
      productCapFail
        s!"Solana CPI product SupportClaim must include exact '{pfAssetsReq.id}'"
  -- context.caller is wire-owned / target-independent: not required on SupportClaim.
  if requestExact supported asyncReq ||
      hasRequestId supported s2EffectAsyncWorkflowIdV1 then
    productCapFail
      s!"Solana CPI product SupportClaim rejects '{s2EffectAsyncWorkflowIdV1}'"

  pure (ResolvedSolanaCpiProductCapabilityV1.mk engineering)

end ProofForgeV2.Targets.Solana.CpiV1

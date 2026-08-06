/-
  ProofForgeV2.Targets.Solana.CpiPlanV1 — #117 inspection-only pure CPI Plan model.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1` (shared with CpiContractV1).

  Public candidate DTOs + private-ctor structurally validated inspection carrier
  + sole structural validate / materialization-eligibility gates. Canonical
  PF-JCS + domain-separated digest live only on that carrier. This #117 leaf
  does not claim a SemanticProgram/capability join: #118 must derive the DTO
  from retained SemanticProgramV1 under the exact resolved profile and validate
  every anchor/value binding before any product consumer can use it. This module
  never mints OutputFile / product artifacts and is not wired to a materializer.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Solana.CpiContractV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1

/-! ## Plan digest domain -/

def planDigestDomainV1 : String := "pf.solana.cpi-plan.v1"

/-! ## A) Public candidate DTOs -/

/-- How an outer account role obtains its 32-byte key. -/
inductive RoleKeyPolicyV1 where
  | state (schemaId : Nat)
  | accountParameter (callableId : Nat) (paramOrdinal : Nat)
  | fixedProgram (packageId : String)
  /-- ADR-0029 B1: synthetic self-vault PDA (derived at runtime; not an ix param). -/
  | vaultPda
  /-- ADR-0029 B1: synthetic outer-signer caller for deposit. -/
  | handlerCaller
  /-- ADR-0030 E1b: synthetic vault ATA (derived from vault PDA + mint). -/
  | vaultAta
  /-- ADR-0030 E1b: synthetic destination ATA (derived from dst + mint). -/
  | dstAta
  deriving BEq, Repr

/-- One ProofForge-owned state account schema referenced by state roles.

    `initializedMarker` is the behavioral UInt64 written into the 8-byte state
    header (must be nonzero). It is exactly the first 8 bytes of
    `layoutDigest.bytes` interpreted big-endian — the same word as legacy
    Solana `layoutMarker` — so Plan marker and CPI schema cannot diverge. -/
structure StateSchemaV1 where
  schemaId : Nat
  name : String
  exactDataLen : Nat
  layoutDigest : Digest
  initializedMarker : UInt64
  deriving BEq

/-- Global account role schema (shared universe across handlers). -/
structure AccountRoleSchemaV1 where
  roleId : Nat
  name : String
  keyPolicy : RoleKeyPolicyV1
  constraint : AccountConstraint
  aliasPolicy : AliasPolicy
  deriving BEq, Repr

/-- Handler kind for direct state-role privilege rules. -/
inductive HandlerModeV1 where
  | initialize
  | entry
  | view
  deriving BEq, Repr

/-- Per-handler ordered use of one global role (local ABIv1 position). -/
structure HandlerAccountUseV1 where
  position : Nat
  roleId : Nat
  directSignerContribution : Bool
  directWritableContribution : Bool
  outerSigner : Bool
  outerWritable : Bool
  deriving BEq, Repr

/-- One entry/view/init handler account matrix + ordered CPI site ids. -/
structure HandlerPlanV1 where
  handlerId : Nat
  callableId : Nat
  name : String
  mode : HandlerModeV1
  accountUses : Array HandlerAccountUseV1
  cpiSiteIds : Array Nat
  deriving BEq, Repr

/-- One typed CPI argument binding (exact frozen arg order). -/
structure CpiArgumentBindingV1 where
  spec : FrozenArgSpec
  semanticValueId : Nat
  roleId : Option Nat
  deriving BEq, Repr

/-- One CPI meta slot bound to an outer role. -/
structure CpiMetaPlanV1 where
  metaIndex : Nat
  roleId : Nat
  spec : FrozenMetaSpec
  deriving BEq, Repr

/-- Outer-only (non-meta) account contribution at a CPI site. -/
structure CpiOuterOnlyPlanV1 where
  roleId : Nat
  spec : FrozenOuterOnlySpec
  deriving BEq, Repr

/-- Semantic effect anchor for a CPI site. -/
structure SemanticSiteAnchorV1 where
  callableId : Nat
  blockId : Nat
  instructionIndex : Nat
  effectId : Nat
  deriving BEq, Repr

/-- Site-time account predicate source (plan-owned; not a JCS authority).
    Constructors map to oracle `callee | meta(index) | outerOnly(index)`;
    `meta` is a Lean reserved word so the ctor is `metaIndex`. -/
inductive SitePredicateSourceV1 where
  | callee
  | metaIndex (index : Nat)
  | outerOnlyIndex (index : Nat)
  deriving BEq, Repr

/-- One site-time owner/data/init/provisioning recheck row. -/
structure SiteAccountPredicateV1 where
  source : SitePredicateSourceV1
  roleId : Nat
  constraint : AccountConstraint
  deriving BEq, Repr

/-- Exact return-data policy carrier (frozen strings only for product v1). -/
structure ReturnDataPolicyV1 where
  calleeEntry : String
  clearFault : String
  onCpiFailure : String
  onCpiSuccess : String
  topLevelSuccess : String
  deriving BEq, Repr

/-- Exact failure policy carrier (propagate-immediately product v1). -/
structure FailurePolicyV1 where
  clearAfterFailure : Bool
  continueAfterFailure : Bool
  innerNonzero : String
  rollback : String
  deriving BEq, Repr

/-- Frozen product return-data policy (profile + extension cpiContract). -/
def propagateImmediatelyReturnDataPolicyV1 : ReturnDataPolicyV1 where
  calleeEntry := "pinned-runtime-clears-stale-return-data-before-cpi"
  clearFault := "propagate-as-outer-failure"
  onCpiFailure := "propagate-without-generated-clear"
  onCpiSuccess :=
    "immediate-sol-set-return-data-zero-length-before-next-generated-op"
  topLevelSuccess := "empty"

/-- Frozen product failure policy (propagate immediately; no continue). -/
def propagateImmediatelyFailurePolicyV1 : FailurePolicyV1 where
  clearAfterFailure := false
  continueAfterFailure := false
  innerNonzero := "return-immediately-and-fail-outer-instruction"
  rollback := "runtime-rolls-back-all-top-level-account-changes"

/-- One typed CPI site plan. -/
structure CpiSitePlanV1 where
  siteId : Nat
  handlerId : Nat
  anchor : SemanticSiteAnchorV1
  qn : String
  packageId : String
  programRoleId : Nat
  programKey : SolanaPubkeyV1
  args : Array CpiArgumentBindingV1
  instructionCodec : InstructionCodec
  metas : Array CpiMetaPlanV1
  outerOnlyAccounts : Array CpiOuterOnlyPlanV1
  accountInfoRoleIds : Array Nat
  signerGroups : Array FrozenSignerGroup
  pda : FrozenPdaUse
  preflight : Array FrozenPreflightSpecV1
  sitePredicates : Array SiteAccountPredicateV1
  returnDataPolicy : ReturnDataPolicyV1
  failurePolicy : FailurePolicyV1
  deriving BEq, Repr

/-- Frozen product compute / cap assumptions echoed into every plan. -/
structure ComputeAssumptionsV1 where
  maxOuterRoles : Nat
  maxCpiAccountInfos : Nat
  maxCpiMetas : Nat
  maxCpiSitesPerHandler : Nat
  maxSignerGroupsPerCpi : Nat
  maxSeedsIncludingBump : Nat
  maxSeedBytes : Nat
  maxInstructionDataBytes : Nat
  maxPdaSpaceBytes : Nat
  instructionStackDepth : Nat
  returnDataPolicy : String
  failurePolicy : String
  activationRule : String
  implementationState : String
  deriving BEq, Repr

/-- Exact frozen compute assumptions for the inert CPI profile. -/
def frozenComputeAssumptionsV1 : ComputeAssumptionsV1 where
  maxOuterRoles := maxOuterRolesV1
  maxCpiAccountInfos := maxCpiAccountInfosV1
  maxCpiMetas := maxCpiMetasV1
  maxCpiSitesPerHandler := maxCpiSitesPerHandlerV1
  maxSignerGroupsPerCpi := maxSignerGroupsPerCpiV1
  maxSeedsIncludingBump := maxSeedsIncludingBumpV1
  maxSeedBytes := maxSeedBytesV1
  maxInstructionDataBytes := maxInstructionDataBytesV1
  maxPdaSpaceBytes := maxPdaSpaceBytesV1
  instructionStackDepth := 9
  returnDataPolicy :=
    "runtime-clears-before-callee;profile-clears-to-empty-after-each-successful-cpi"
  failurePolicy := "return-immediately-and-fail-outer-instruction"
  activationRule :=
    "every-referenced-callee-package-is-admitted-with-an-exact-artifact-or-runtime-native-binding"
  implementationState := "inert-contract-only-no-artifact-mint"

/-! ## #125 active product snapshot (consumes CpiContractV1 pins)

    Preactivation `profileDigestV1` / `catalogDigestV1` / `frozenCalleePackagesV1` /
    `frozenComputeAssumptionsV1` remain the sole inert authority and are never
    mutated here. Product Plan digests bind `activeProfileDigestV1` /
    `activeCatalogDigestV1` / `activeCalleePackagesV1` from `CpiContractV1`. -/

/-- Exact active product compute assumptions. Caps/policies match frozen product
    caps; implementation state is the active profile product-exact-sync label. -/
def activeComputeAssumptionsV1 : ComputeAssumptionsV1 where
  maxOuterRoles := maxOuterRolesV1
  maxCpiAccountInfos := maxCpiAccountInfosV1
  maxCpiMetas := maxCpiMetasV1
  maxCpiSitesPerHandler := maxCpiSitesPerHandlerV1
  maxSignerGroupsPerCpi := maxSignerGroupsPerCpiV1
  maxSeedsIncludingBump := maxSeedsIncludingBumpV1
  maxSeedBytes := maxSeedBytesV1
  maxInstructionDataBytes := maxInstructionDataBytesV1
  maxPdaSpaceBytes := maxPdaSpaceBytesV1
  instructionStackDepth := 9
  returnDataPolicy :=
    "runtime-clears-before-callee;profile-clears-to-empty-after-each-successful-cpi"
  failurePolicy := "return-immediately-and-fail-outer-instruction"
  activationRule :=
    "every-referenced-callee-package-is-admitted-with-an-exact-artifact-or-runtime-native-binding"
  implementationState := activeProfileImplementationStateV1

/-- Approved product ExternalCall QNs (#125 L2 five + ADR-0029 B1 L1 two).
    Companion three APIs are excluded. L2 authority remains `activeProductApiQnsV1`
    (docs_check five-element pin); L1 pf.assets is additive. -/
def isApprovedProductApiV1 (qn : String) : Bool :=
  activeProductApiQnsV1.any (· == qn) || isPfAssetsSolanaProductApiV1 qn

def isCompanionApiV1 (qn : String) : Bool :=
  qn == "solana.companion.invoke" ||
    qn == "solana.companion.fail" ||
    qn == "solana.companion.invokeSigned"

/-! ## ADR-0030 E2-3 env-read site plan (Solana vault observation)

    `pf.assets.native.balanceOfSelf()` / `pf.assets.token.balanceOfSelf(mint)`
    are read-only value-producing ops (not CPI invokes). The Plan carries one
    `EnvReadSitePlanV1` per Semantic `Op.envRead` occurrence so that the
    handler's account set includes the vault PDA role (native) or the vault
    ATA + mint + program roles (token), and the IR/emitter can resolve them. -/

inductive EnvReadKindV1 where
  | nativeVaultBalance
  | tokenVaultBalance
  deriving BEq, Repr

/-- One env-read site in the Plan (read-only; no CPI invoke). -/
structure EnvReadSitePlanV1 where
  siteId : Nat
  handlerId : Nat
  /-- Semantic anchor (callableId, blockId, instructionIndex). envRead has no
      EffectId (effect-free); `effectId` is always 0. -/
  anchor : SemanticSiteAnchorV1
  kind : EnvReadKindV1
  /-- Native: vault PDA role. Token: vault PDA role (authority / ATA wallet). -/
  vaultRoleId : Nat
  /-- Token only: vault ATA role (ATA(vault, mint)). Native: 0 (unused). -/
  vaultAtaRoleId : Nat
  /-- Token only: mint Principal parameter role. Native: 0 (unused). -/
  mintRoleId : Nat
  /-- Token only: system-v1 fixedProgram role (ATA address check). Native: 0. -/
  systemProgramRoleId : Nat
  /-- Token only: token-classic-v1 fixedProgram role. Native: 0. -/
  tokenProgramRoleId : Nat
  /-- Token only: ata-classic-v1 fixedProgram role. Native: 0. -/
  ataProgramRoleId : Nat
  deriving BEq, Repr

/-! ## ADR-0031 S1 / ADR-0030 E3 context.caller site plan (Solana signer role)

    Solana has no tx.origin / CALLER opcode. Honest binding of
    `context.caller : Principal` is the 32-byte pubkey of an ABI-specified
    **signer role** account (`AccountInfo.key` + site-time `is_signer`
    predicate). Wire identity is `u32le(32)||pubkey32` (body 8×UInt64 LE,
    high 32 bytes zero). This is **not** a transaction-fee-payer / origin
    concept — only the role marked `pf_caller` (RoleKeyV1.handlerCaller)
    with outerSigner=true. Legacy profiles stay fail closed. -/

/-- One context.caller read site in the Plan (read-only; no CPI invoke). -/
structure ContextReadSitePlanV1 where
  siteId : Nat
  handlerId : Nat
  /-- Semantic anchor (callableId, blockId, instructionIndex). contextRead has
      no EffectId (effect-free); `effectId` is always 0. -/
  anchor : SemanticSiteAnchorV1
  /-- Always the handler's synthetic `pf_caller` role (handlerCaller policy).
      Must carry outerSigner at the handler accountUses join. -/
  callerRoleId : Nat
  deriving BEq, Repr

/-- Public inspection candidate for a Solana CPI plan (not yet validated). -/
structure SolanaCpiPlanCandidateV1 where
  schema : String
  profileId : String
  profileDigest : Digest
  extensionRequirement : RequirementRequestV1
  calleeCatalogDigest : Digest
  programName : String
  stateSchemas : Array StateSchemaV1
  pdaRules : Array FrozenPdaRule
  accountRoles : Array AccountRoleSchemaV1
  handlers : Array HandlerPlanV1
  cpiSites : Array CpiSitePlanV1
  envReadSites : Array EnvReadSitePlanV1
  /-- ADR-0031 S1: context.caller sites (signer-role pubkey reads). -/
  contextReadSites : Array ContextReadSitePlanV1
  computeAssumptions : ComputeAssumptionsV1
  deriving BEq

/-! ## B) Validated private-ctor carrier -/

/-- Structurally validated, inspection-only CPI Plan carrier. Digest is only
    available after exact structural validation. It is deliberately not a
    SemanticProgram/capability authority and cannot authorize materialization;
    #118 must add that private product join. Public field projections
    `candidate` / `canonicalBytes` / `digest` are read-only (constructor private). -/
structure ValidatedSolanaCpiPlanV1 where
  private mk ::
  candidate : SolanaCpiPlanCandidateV1
  canonicalBytes : ByteArray
  digest : Digest

/-! ## E) Test helpers (Except; no Source/TargetId/legacy Plan) -/

def expectedProfileDigestV1 : Except String Digest :=
  parseDigest profileDigestV1

def expectedCatalogDigestV1 : Except String Digest :=
  parseDigest catalogDigestV1

def expectedActiveProfileDigestV1 : Except String Digest :=
  parseDigest activeProfileDigestV1

def expectedActiveCatalogDigestV1 : Except String Digest :=
  parseDigest activeCatalogDigestV1

def expectedExtensionRequirementV1 : Except String RequirementRequestV1 :=
  solanaCpiAccountsExtensionRequirementV1

/-! ## Internal helpers -/

private def planFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def mapExcept (e : Except String α) (ctx : String) : CompileResult α :=
  match e with
  | .ok v => pure v
  | .error msg => planFail s!"{ctx}: {msg}"

private def maxUInt32Nat : Nat := 4294967295

private def requireUInt32 (label : String) (n : Nat) : CompileResult Unit := do
  unless n ≤ maxUInt32Nat do
    planFail s!"{label} exceeds UInt32"

private def pfNat (label : String) (n : Nat) : CompileResult PfJson := do
  requireUInt32 label n
  pure (.int (Int.ofNat n))

private def lowerHexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

private def encodeLowerHex (bytes : ByteArray) : String :=
  bytes.foldl (fun result byte =>
    let value := byte.toNat
    (result.push (lowerHexDigit (value / 16))).push (lowerHexDigit (value % 16))) ""

private def digestsEqual (left right : Digest) : Bool :=
  left.algorithm == right.algorithm && left.bytes == right.bytes

private def namesUnique (names : Array String) : Bool :=
  Id.run do
    let sorted := names.qsort (· < ·)
    for i in [1:sorted.size] do
      if sorted[i - 1]! == sorted[i]! then return false
    return true

private def natsUnique (xs : Array Nat) : Bool :=
  Id.run do
    let sorted := xs.qsort (· < ·)
    for i in [1:sorted.size] do
      if sorted[i - 1]! == sorted[i]! then return false
    return true

private def natPairsUnique (xs : Array (Nat × Nat)) : Bool :=
  Id.run do
    let sorted := xs.qsort (fun a b =>
      a.1 < b.1 || (a.1 == b.1 && a.2 < b.2))
    for i in [1:sorted.size] do
      if sorted[i - 1]! == sorted[i]! then return false
    return true

private def natTriplesUnique (xs : Array (Nat × Nat × Nat)) : Bool :=
  Id.run do
    let sorted := xs.qsort (fun a b =>
      a.1 < b.1 ||
        (a.1 == b.1 &&
          (a.2.1 < b.2.1 || (a.2.1 == b.2.1 && a.2.2 < b.2.2))))
    for i in [1:sorted.size] do
      if sorted[i - 1]! == sorted[i]! then return false
    return true

private def arrayDenseFromZero (ids : Array Nat) : Bool :=
  Id.run do
    if ids.size == 0 then return true
    let mut seen : Array Bool := Array.replicate ids.size false
    for id in ids do
      if id ≥ ids.size then return false
      if seen[id]! then return false
      seen := seen.set! id true
    return true

private def getArr (arr : Array α) (i : Nat) (ctx : String) : CompileResult α :=
  match arr[i]? with
  | some v => pure v
  | none => planFail s!"{ctx}: index {i} out of range"

private def findRole?
    (roles : Array AccountRoleSchemaV1) (roleId : Nat) :
    Option AccountRoleSchemaV1 :=
  roles[roleId]?

private def findHandler?
    (handlers : Array HandlerPlanV1) (handlerId : Nat) :
    Option HandlerPlanV1 :=
  handlers[handlerId]?

private def findStateSchema?
    (schemas : Array StateSchemaV1) (schemaId : Nat) :
    Option StateSchemaV1 :=
  schemas[schemaId]?

private def pushUnique (acc : Array Nat) (id : Nat) : Array Nat :=
  if acc.any (· == id) then acc else acc.push id

/-- Insertion-sort Nat pairs by first component ascending (stable for ties). -/
private def sortByNatAsc (pairs : Array (Nat × Nat)) : Array (Nat × Nat) :=
  Id.run do
    let mut out := pairs
    for i in [1:out.size] do
      let mut j := i
      while j > 0 do
        let prev := out[j - 1]!
        let cur := out[j]!
        if cur.1 < prev.1 then
          out := (out.set! (j - 1) cur).set! j prev
          j := j - 1
        else
          break
    return out

/-- Exact handler-local role subset derivation (stable-unique source order).
    `stateRoleId?` is computed once for the whole candidate so this pass stays
    proportional to the handler's own sites/roles rather than global H×R. -/
private def deriveHandlerRoleIds
    (c : SolanaCpiPlanCandidateV1) (stateRoleId? : Option Nat)
    (h : HandlerPlanV1) : Array Nat :=
  Id.run do
    let mut acc : Array Nat := #[]
    -- 1) state role (if present in the global universe)
    match stateRoleId? with
    | some roleId => acc := acc.push roleId
    | none => pure ()
    -- 2) only accountParameter roles actually consumed by this handler's
    -- frozen API account/seed slots, in callable parameter declaration order.
    -- Unused Principal parameters remain opaque instruction data and therefore
    -- must never enter the outer-role table.
    let mut usedAccountRoles : Array Nat := #[]
    for siteId in h.cpiSiteIds do
      match c.cpiSites[siteId]? with
      | none => pure ()
      | some site =>
          for arg in site.args do
            if arg.spec.type_ == .principal then
              match arg.roleId with
              | some roleId => usedAccountRoles := pushUnique usedAccountRoles roleId
              | none => pure ()
    let mut params : Array (Nat × Nat) := #[]
    for roleId in usedAccountRoles do
      match c.accountRoles[roleId]? with
      | some role =>
          match role.keyPolicy with
          | .accountParameter callableId paramOrdinal =>
              if callableId == h.callableId then
                params := params.push (paramOrdinal, role.roleId)
          | _ => pure ()
      | none => pure ()
    let sorted := sortByNatAsc params
    for p in sorted do
      acc := pushUnique acc p.2
    -- 2.5) ADR-0030 E1b: for token.transfer sites, the handlerCaller role
    -- is auto-created (not a CPI meta) as the ATA ensure payer. Include it
    -- in the handler's derived role set so accountUses validation passes.
    let hasTokenTransfer := h.cpiSiteIds.any (fun sid =>
      match c.cpiSites[sid]? with
      | some s => s.qn == "pf.assets.token.transfer"
      | none => false)
    if hasTokenTransfer then
      for role in c.accountRoles do
        match role.keyPolicy with
        | .handlerCaller => acc := pushUnique acc role.roleId
        | .fixedProgram "system-v1" => acc := pushUnique acc role.roleId
        -- ADR-0030 E1b: the createIdempotent CPI's ATA program account must be
        -- an outer role (executable LoaderV3 program account), else the runtime
        -- rejects with NotEnoughAccountKeys.
        | .fixedProgram "ata-classic-v1" => acc := pushUnique acc role.roleId
        | _ => pure ()
    -- 3) handler sites source order: program role, then fixed-program metas
    for siteId in h.cpiSiteIds do
      match c.cpiSites[siteId]? with
      | none => pure ()
      | some site =>
          acc := pushUnique acc site.programRoleId
          for metaSlot in site.metas do
            match metaSlot.spec.binding with
            | .fixedProgram _ | .vaultPda | .handlerCaller
            | .vaultAta | .dstAta =>
                acc := pushUnique acc metaSlot.roleId
            | .arg _ => pure ()
    -- 3.5) ADR-0030 E2-3: env-read sites contribute their roles (vault PDA,
    -- vault ATA, mint param, and fixedProgram program roles for token). These
    -- are read-only; the mint param is an accountParameter consumed by the
    -- env-read site, added here in source order after CPI site roles. The
    -- vault/ATA/program roles are synthetic and added in envReadSite order.
    for envSite in c.envReadSites do
      if envSite.handlerId == h.handlerId then
        -- mint param role (token only): add in param-ordinal order via sort
        if envSite.kind == .tokenVaultBalance then
          match c.accountRoles[envSite.mintRoleId]? with
          | some role =>
              match role.keyPolicy with
              | .accountParameter cid _ =>
                  if cid == h.callableId then
                    acc := pushUnique acc envSite.mintRoleId
              | _ => acc := pushUnique acc envSite.mintRoleId
          | none => acc := pushUnique acc envSite.mintRoleId
        -- vault PDA role
        acc := pushUnique acc envSite.vaultRoleId
        -- token-only synthetic roles
        if envSite.kind == .tokenVaultBalance then
          acc := pushUnique acc envSite.vaultAtaRoleId
          acc := pushUnique acc envSite.systemProgramRoleId
          acc := pushUnique acc envSite.tokenProgramRoleId
          acc := pushUnique acc envSite.ataProgramRoleId
    -- 3.6) ADR-0031 S1: context.caller sites contribute the pf_caller role
    -- (handlerCaller). Outer-signer privilege is joined separately.
    for ctxSite in c.contextReadSites do
      if ctxSite.handlerId == h.handlerId then
        acc := pushUnique acc ctxSite.callerRoleId
    return acc

/-- Expected site predicates: callee, then metas order, then outer-only order. -/
private def deriveSitePredicates
    (s : CpiSitePlanV1) (programConstraint : AccountConstraint) :
    Array SiteAccountPredicateV1 :=
  Id.run do
    let mut out : Array SiteAccountPredicateV1 := #[{
      source := .callee
      roleId := s.programRoleId
      constraint := programConstraint
    }]
    for i in [0:s.metas.size] do
      match s.metas[i]? with
      | none => pure ()
      | some metaSlot =>
          out := out.push {
            source := .metaIndex i
            roleId := metaSlot.roleId
            constraint := metaSlot.spec.constraint
          }
    for i in [0:s.outerOnlyAccounts.size] do
      match s.outerOnlyAccounts[i]? with
      | none => pure ()
      | some outer =>
          out := out.push {
            source := .outerOnlyIndex i
            roleId := outer.roleId
            constraint := outer.spec.constraint
          }
    return out

/-! ### Canonical PF-JCS encoding (private; every candidate field) -/

private def encodeOwnerPolicy : OwnerPolicy → PfJson
  | .currentProgram => .object #[("kind", .string "currentProgram")]
  | .fixedProgram packageId =>
      .object #[("kind", .string "fixedProgram"), ("packageId", .string packageId)]
  | .catalogExecutionClass =>
      .object #[("kind", .string "catalogExecutionClass")]
  | .any => .object #[("kind", .string "any")]
  | .closedPackages packages =>
      .object #[
        ("kind", .string "closedPackages"),
        ("packages", .array (packages.map PfJson.string))
      ]

private def encodeExecutablePolicy : ExecutablePolicy → PfJson
  | .required => .string "required"
  | .forbidden => .string "forbidden"

private def encodeDataPolicy : DataPolicy → CompileResult PfJson
  | .notRead => pure (.object #[("kind", .string "notRead")])
  | .exactLength bytes lamports => do
      let b ← pfNat "dataPolicy.exactLength.bytes" bytes
      match lamports with
      | none => pure (.object #[("kind", .string "exactLength"), ("bytes", b)])
      | some lam =>
          let l ← pfNat "dataPolicy.exactLength.lamports" lam
          pure (.object #[
            ("kind", .string "exactLength"), ("bytes", b), ("lamports", l)
          ])
  | .proofForgeState => pure (.object #[("kind", .string "proofForgeState")])
  | .exactCounter bytes => do
      let b ← pfNat "dataPolicy.exactCounter.bytes" bytes
      pure (.object #[("kind", .string "exactCounter"), ("bytes", b)])
  | .classicTokenAccount bytes state mintEqualsArg ownerEqualsArg delegate => do
      let b ← pfNat "dataPolicy.classicTokenAccount.bytes" bytes
      pure (.object #[
        ("kind", .string "classicTokenAccount"),
        ("bytes", b),
        ("state", .string state),
        ("mintEqualsArg", match mintEqualsArg with
          | some s => .string s | none => .null),
        ("ownerEqualsArg", match ownerEqualsArg with
          | some s => .string s | none => .null),
        ("delegate", match delegate with
          | some s => .string s | none => .null)
      ])
  | .classicTokenMint bytes state decimalsEqualsArg => do
      let b ← pfNat "dataPolicy.classicTokenMint.bytes" bytes
      pure (.object #[
        ("kind", .string "classicTokenMint"),
        ("bytes", b),
        ("state", .string state),
        ("decimalsEqualsArg", match decimalsEqualsArg with
          | some s => .string s | none => .null)
      ])
  | .ataAccount mintEqualsArg ownerEqualsArg =>
      pure (.object #[
        ("kind", .string "ataAccount"),
        ("mintEqualsArg", .string mintEqualsArg),
        ("ownerEqualsArg", .string ownerEqualsArg)
      ])
  | .catalogProgram => pure (.object #[("kind", .string "catalogProgram")])

private def encodeInitializationPolicy : InitializationPolicy → PfJson
  | .initializerUninitializedOtherwiseInitialized =>
      .string "initializerUninitializedOtherwiseInitialized"
  | .initialized => .string "initialized"
  | .uninitialized => .string "uninitialized"
  | .existing => .string "existing"
  | .any => .string "any"
  | .canonicalPda => .string "canonicalPda"
  | .catalogPackageAdmitted => .string "catalogPackageAdmitted"
  | .uninitializedOrIdempotentlyInitialized =>
      .string "uninitializedOrIdempotentlyInitialized"

private def encodeProvisioningPolicy : ProvisioningPolicy → PfJson
  | .none => .string "none"
  | .mustExist => .string "mustExist"
  | .systemCreateAccount => .string "systemCreateAccount"
  | .ataCreateIdempotent => .string "ataCreateIdempotent"

private def encodeConstraint (c : AccountConstraint) : CompileResult PfJson := do
  let data ← encodeDataPolicy c.data
  pure (.object #[
    ("owner", encodeOwnerPolicy c.owner),
    ("executable", encodeExecutablePolicy c.executable),
    ("data", data),
    ("initialization", encodeInitializationPolicy c.initialization),
    ("provisioning", encodeProvisioningPolicy c.provisioning)
  ])

private def encodeAliasPolicy (a : AliasPolicy) : PfJson :=
  .object #[
    ("outerRoleKeys", .string a.outerRoleKeys),
    ("cpiSiteMetaKeys", .string a.cpiSiteMetaKeys),
    ("sameRoleAcrossCpiSites", .string a.sameRoleAcrossCpiSites),
    ("separateRolesAcrossCpiSites", .string a.separateRolesAcrossCpiSites)
  ]

private def encodeFrozenValueType : FrozenValueType → PfJson
  | .principal => .string "principal"
  | .uint64 => .string "uint64"
  | .uint8 => .string "uint8"
  | .unit => .string "unit"

private def encodeArgumentSource : ArgumentSource → PfJson
  | .bareDirectPublicPrincipalParameter =>
      .string "bareDirectPublicPrincipalParameter"
  | .typedExpression => .string "typedExpression"
  | .literalConstantOrBareDirectPublicUInt64Parameter =>
      .string "literalConstantOrBareDirectPublicUInt64Parameter"
  | .literalConstantOrBareDirectPublicUInt8Parameter =>
      .string "literalConstantOrBareDirectPublicUInt8Parameter"

private def encodeFrozenArgSpec (s : FrozenArgSpec) : PfJson :=
  .object #[
    ("name", .string s.name),
    ("type", encodeFrozenValueType s.type_),
    ("source", encodeArgumentSource s.source)
  ]

private def encodeInstructionEncoding : InstructionEncoding → PfJson
  | .uint64Le => .string "uint64Le"
  | .uint8 => .string "uint8"

private def encodeInstructionSegment : InstructionSegment → PfJson
  | .hex hex => .object #[("kind", .string "hex"), ("hex", .string hex)]
  | .arg name encoding =>
      .object #[
        ("kind", .string "arg"),
        ("name", .string name),
        ("encoding", encodeInstructionEncoding encoding)
      ]
  | .fixedCurrentProgramId32 =>
      .object #[("kind", .string "fixedCurrentProgramId32")]

private def encodeInstructionCodec (c : InstructionCodec) : CompileResult PfJson := do
  let length ← pfNat "instructionCodec.length" c.length
  pure (.object #[
    ("length", length),
    ("segments", .array (c.segments.map encodeInstructionSegment))
  ])

private def encodeMetaBinding : MetaBinding → PfJson
  | .arg name => .object #[("kind", .string "arg"), ("name", .string name)]
  | .fixedProgram packageId =>
      .object #[
        ("kind", .string "fixedProgram"),
        ("packageId", .string packageId)
      ]
  | .vaultPda => .object #[("kind", .string "vaultPda")]
  | .handlerCaller => .object #[("kind", .string "handlerCaller")]
  | .vaultAta => .object #[("kind", .string "vaultAta")]
  | .dstAta => .object #[("kind", .string "dstAta")]

private def encodeFrozenMetaSpec (s : FrozenMetaSpec) : CompileResult PfJson := do
  let constraint ← encodeConstraint s.constraint
  let signerGroup ← match s.signerGroupId with
    | none => pure PfJson.null
    | some id => pfNat "meta.signerGroupId" id
  pure (.object #[
    ("binding", encodeMetaBinding s.binding),
    ("constraint", constraint),
    ("cpiSigner", .bool s.cpiSigner),
    ("cpiWritable", .bool s.cpiWritable),
    ("outerSignerContribution", .bool s.outerSignerContribution),
    ("outerWritableContribution", .bool s.outerWritableContribution),
    ("signerGroupId", signerGroup)
  ])

private def encodeFrozenOuterOnlySpec (s : FrozenOuterOnlySpec) :
    CompileResult PfJson := do
  let constraint ← encodeConstraint s.constraint
  pure (.object #[
    ("arg", .string s.arg),
    ("constraint", constraint),
    ("outerSignerContribution", .bool s.outerSignerContribution),
    ("outerWritableContribution", .bool s.outerWritableContribution)
  ])

private def encodeFrozenPdaUse : FrozenPdaUse → PfJson
  | .none => .object #[("kind", .string "none")]
  | .signer rule targetArg seedAuthorityArg seedTagArg bumpArg signerArg =>
      .object #[
        ("kind", .string "signer"),
        ("rule", .string rule),
        ("targetArg", .string targetArg),
        ("seedAuthorityArg", .string seedAuthorityArg),
        ("seedTagArg", .string seedTagArg),
        ("bumpArg", .string bumpArg),
        ("signerArg", .string signerArg)
      ]
  | .addressCheckOnly rule targetArg walletArg mintArg =>
      .object #[
        ("kind", .string "addressCheckOnly"),
        ("rule", .string rule),
        ("targetArg", .string targetArg),
        ("walletArg", .string walletArg),
        ("mintArg", .string mintArg)
      ]
  | .vaultPdaSigner rule =>
      .object #[("kind", .string "vaultPdaSigner"), ("rule", .string rule)]

private def encodeFrozenSignerGroup (g : FrozenSignerGroup) :
    CompileResult PfJson := do
  let id ← pfNat "signerGroup.id" g.id
  pure (.object #[
    ("id", id),
    ("metaArg", .string g.metaArg),
    ("pdaRule", .string g.pdaRule)
  ])

private def encodePreflight : FrozenPreflightSpecV1 → CompileResult PfJson
  | .uint64AtMost argName value => do
      let v ← pfNat "preflight.uint64AtMost.value" value
      pure (.object #[
        ("kind", .string "uint64AtMost"),
        ("argName", .string argName),
        ("value", v)
      ])

private def encodeSeedTemplate : SeedTemplate → PfJson
  | .literalHex hex =>
      .object #[("kind", .string "literalHex"), ("hex", .string hex)]
  | .accountKey argName =>
      .object #[("kind", .string "accountKey"), ("argName", .string argName)]
  | .fixedProgramId packageId =>
      .object #[
        ("kind", .string "fixedProgramId"),
        ("packageId", .string packageId)
      ]
  | .uint64Le argName =>
      .object #[("kind", .string "uint64Le"), ("argName", .string argName)]
  | .uint8 argName =>
      .object #[("kind", .string "uint8"), ("argName", .string argName)]

private def encodeDerivationProgram : DerivationProgram → PfJson
  | .currentProgram => .object #[("kind", .string "currentProgram")]
  | .fixedPackage packageId =>
      .object #[
        ("kind", .string "fixedPackage"),
        ("packageId", .string packageId)
      ]

private def encodeBumpSearchPolicy : BumpSearchPolicy → PfJson
  | .providedBumpMustEqualCanonical255Through1 =>
      .string "providedBumpMustEqualCanonical255Through1"
  | .canonical255Through1 => .string "canonical255Through1"

private def encodeFrozenPdaRule (r : FrozenPdaRule) : CompileResult PfJson := do
  pure (.object #[
    ("ruleId", .string r.ruleId),
    ("derivationProgram", encodeDerivationProgram r.derivationProgram),
    ("seeds", .array (r.seeds.map encodeSeedTemplate)),
    ("search", encodeBumpSearchPolicy r.search),
    ("signerEligible", .bool r.signerEligible)
  ])

private def encodeRoleKeyPolicy : RoleKeyPolicyV1 → CompileResult PfJson
  | .state schemaId => do
      let id ← pfNat "roleKeyPolicy.state.schemaId" schemaId
      pure (.object #[("kind", .string "state"), ("schemaId", id)])
  | .accountParameter callableId paramOrdinal => do
      let c ← pfNat "roleKeyPolicy.accountParameter.callableId" callableId
      let p ← pfNat "roleKeyPolicy.accountParameter.paramOrdinal" paramOrdinal
      pure (.object #[
        ("kind", .string "accountParameter"),
        ("callableId", c),
        ("paramOrdinal", p)
      ])
  | .fixedProgram packageId =>
      pure (.object #[
        ("kind", .string "fixedProgram"),
        ("packageId", .string packageId)
      ])
  | .vaultPda => pure (.object #[("kind", .string "vaultPda")])
  | .handlerCaller => pure (.object #[("kind", .string "handlerCaller")])
  | .vaultAta => pure (.object #[("kind", .string "vaultAta")])
  | .dstAta => pure (.object #[("kind", .string "dstAta")])

/-- Fixed 16 lowercase hex digits for a UInt64 (lossless canonical form),
    shared by Plan/IR/IDL state-schema encoders. -/
def renderUInt64LowerHex16V1 (value : UInt64) : String :=
  Id.run do
    let mut out := ""
    for i in [0:16] do
      let shift := (15 - i) * 4
      let nibble := ((UInt64.shiftRight value shift.toUInt64) &&& (15 : UInt64)).toNat
      out := out.push (lowerHexDigit nibble)
    pure out

private def encodeStateSchema (s : StateSchemaV1) : CompileResult PfJson := do
  let id ← pfNat "stateSchema.schemaId" s.schemaId
  let len ← pfNat "stateSchema.exactDataLen" s.exactDataLen
  let dig ← mapExcept (renderDigest s.layoutDigest) "stateSchema.layoutDigest"
  pure (.object #[
    ("schemaId", id),
    ("name", .string s.name),
    ("exactDataLen", len),
    ("layoutDigest", .string dig),
    ("initializedMarker", .string (renderUInt64LowerHex16V1 s.initializedMarker))
  ])

private def encodeAccountRole (r : AccountRoleSchemaV1) : CompileResult PfJson := do
  let roleId ← pfNat "accountRole.roleId" r.roleId
  let keyPolicy ← encodeRoleKeyPolicy r.keyPolicy
  let constraint ← encodeConstraint r.constraint
  pure (.object #[
    ("roleId", roleId),
    ("name", .string r.name),
    ("keyPolicy", keyPolicy),
    ("constraint", constraint),
    ("aliasPolicy", encodeAliasPolicy r.aliasPolicy)
  ])

private def encodeHandlerMode : HandlerModeV1 → PfJson
  | .initialize => .string "initialize"
  | .entry => .string "entry"
  | .view => .string "view"

private def encodeHandlerAccountUse (u : HandlerAccountUseV1) :
    CompileResult PfJson := do
  let position ← pfNat "handlerAccountUse.position" u.position
  let roleId ← pfNat "handlerAccountUse.roleId" u.roleId
  pure (.object #[
    ("position", position),
    ("roleId", roleId),
    ("directSignerContribution", .bool u.directSignerContribution),
    ("directWritableContribution", .bool u.directWritableContribution),
    ("outerSigner", .bool u.outerSigner),
    ("outerWritable", .bool u.outerWritable)
  ])

private def encodeHandler (h : HandlerPlanV1) : CompileResult PfJson := do
  let handlerId ← pfNat "handler.handlerId" h.handlerId
  let callableId ← pfNat "handler.callableId" h.callableId
  let uses ← h.accountUses.mapM encodeHandlerAccountUse
  let siteIds ← h.cpiSiteIds.mapM (fun id => pfNat "handler.cpiSiteId" id)
  pure (.object #[
    ("handlerId", handlerId),
    ("callableId", callableId),
    ("name", .string h.name),
    ("mode", encodeHandlerMode h.mode),
    ("accountUses", .array uses),
    ("cpiSiteIds", .array siteIds)
  ])

private def encodeArgBinding (a : CpiArgumentBindingV1) : CompileResult PfJson := do
  let valueId ← pfNat "cpiArg.semanticValueId" a.semanticValueId
  let role ← match a.roleId with
    | none => pure PfJson.null
    | some id => pfNat "cpiArg.roleId" id
  pure (.object #[
    ("spec", encodeFrozenArgSpec a.spec),
    ("semanticValueId", valueId),
    ("roleId", role)
  ])

private def encodeMetaPlan (m : CpiMetaPlanV1) : CompileResult PfJson := do
  let metaIndex ← pfNat "cpiMeta.metaIndex" m.metaIndex
  let roleId ← pfNat "cpiMeta.roleId" m.roleId
  let spec ← encodeFrozenMetaSpec m.spec
  pure (.object #[
    ("metaIndex", metaIndex),
    ("roleId", roleId),
    ("spec", spec)
  ])

private def encodeOuterOnlyPlan (o : CpiOuterOnlyPlanV1) : CompileResult PfJson := do
  let roleId ← pfNat "cpiOuterOnly.roleId" o.roleId
  let spec ← encodeFrozenOuterOnlySpec o.spec
  pure (.object #[("roleId", roleId), ("spec", spec)])

private def encodeAnchor (a : SemanticSiteAnchorV1) : CompileResult PfJson := do
  let callableId ← pfNat "anchor.callableId" a.callableId
  let blockId ← pfNat "anchor.blockId" a.blockId
  let instructionIndex ← pfNat "anchor.instructionIndex" a.instructionIndex
  let effectId ← pfNat "anchor.effectId" a.effectId
  pure (.object #[
    ("callableId", callableId),
    ("blockId", blockId),
    ("instructionIndex", instructionIndex),
    ("effectId", effectId)
  ])

private def encodeSitePredicateSource : SitePredicateSourceV1 → CompileResult PfJson
  | .callee => pure (.object #[("kind", .string "callee")])
  | .metaIndex index => do
      let i ← pfNat "sitePredicate.meta.index" index
      pure (.object #[("kind", .string "meta"), ("index", i)])
  | .outerOnlyIndex index => do
      let i ← pfNat "sitePredicate.outerOnly.index" index
      pure (.object #[("kind", .string "outerOnly"), ("index", i)])

private def encodeSitePredicate (p : SiteAccountPredicateV1) :
    CompileResult PfJson := do
  let source ← encodeSitePredicateSource p.source
  let roleId ← pfNat "sitePredicate.roleId" p.roleId
  let constraint ← encodeConstraint p.constraint
  pure (.object #[
    ("source", source),
    ("roleId", roleId),
    ("constraint", constraint)
  ])

private def encodeReturnDataPolicy (p : ReturnDataPolicyV1) : PfJson :=
  .object #[
    ("calleeEntry", .string p.calleeEntry),
    ("clearFault", .string p.clearFault),
    ("onCpiFailure", .string p.onCpiFailure),
    ("onCpiSuccess", .string p.onCpiSuccess),
    ("topLevelSuccess", .string p.topLevelSuccess)
  ]

private def encodeFailurePolicy (p : FailurePolicyV1) : PfJson :=
  .object #[
    ("clearAfterFailure", .bool p.clearAfterFailure),
    ("continueAfterFailure", .bool p.continueAfterFailure),
    ("innerNonzero", .string p.innerNonzero),
    ("rollback", .string p.rollback)
  ]

private def encodePubkey (key : SolanaPubkeyV1) : PfJson :=
  .string (encodeLowerHex (SolanaPubkeyV1.toBytes key))

private def encodeCpiSite (s : CpiSitePlanV1) : CompileResult PfJson := do
  let siteId ← pfNat "cpiSite.siteId" s.siteId
  let handlerId ← pfNat "cpiSite.handlerId" s.handlerId
  let anchor ← encodeAnchor s.anchor
  let programRoleId ← pfNat "cpiSite.programRoleId" s.programRoleId
  let args ← s.args.mapM encodeArgBinding
  let codec ← encodeInstructionCodec s.instructionCodec
  let metas ← s.metas.mapM encodeMetaPlan
  let outerOnly ← s.outerOnlyAccounts.mapM encodeOuterOnlyPlan
  let accountInfos ← s.accountInfoRoleIds.mapM
    (fun id => pfNat "cpiSite.accountInfoRoleId" id)
  let groups ← s.signerGroups.mapM encodeFrozenSignerGroup
  let preflight ← s.preflight.mapM encodePreflight
  let predicates ← s.sitePredicates.mapM encodeSitePredicate
  pure (.object #[
    ("siteId", siteId),
    ("handlerId", handlerId),
    ("anchor", anchor),
    ("qn", .string s.qn),
    ("packageId", .string s.packageId),
    ("programRoleId", programRoleId),
    ("programKey", encodePubkey s.programKey),
    ("args", .array args),
    ("instructionCodec", codec),
    ("metas", .array metas),
    ("outerOnlyAccounts", .array outerOnly),
    ("accountInfoRoleIds", .array accountInfos),
    ("signerGroups", .array groups),
    ("pda", encodeFrozenPdaUse s.pda),
    ("preflight", .array preflight),
    ("sitePredicates", .array predicates),
    ("returnDataPolicy", encodeReturnDataPolicy s.returnDataPolicy),
    ("failurePolicy", encodeFailurePolicy s.failurePolicy)
  ])

private def encodeEnvReadKind (k : EnvReadKindV1) : PfJson :=
  match k with
  | .nativeVaultBalance => .string "nativeVaultBalance"
  | .tokenVaultBalance => .string "tokenVaultBalance"

private def encodeEnvReadSite (s : EnvReadSitePlanV1) : CompileResult PfJson := do
  let siteId ← pfNat "envReadSite.siteId" s.siteId
  let handlerId ← pfNat "envReadSite.handlerId" s.handlerId
  let anchor ← encodeAnchor s.anchor
  let vaultRoleId ← pfNat "envReadSite.vaultRoleId" s.vaultRoleId
  let vaultAtaRoleId ← pfNat "envReadSite.vaultAtaRoleId" s.vaultAtaRoleId
  let mintRoleId ← pfNat "envReadSite.mintRoleId" s.mintRoleId
  let systemProgramRoleId ←
    pfNat "envReadSite.systemProgramRoleId" s.systemProgramRoleId
  let tokenProgramRoleId ←
    pfNat "envReadSite.tokenProgramRoleId" s.tokenProgramRoleId
  let ataProgramRoleId ←
    pfNat "envReadSite.ataProgramRoleId" s.ataProgramRoleId
  pure (.object #[
    ("siteId", siteId),
    ("handlerId", handlerId),
    ("anchor", anchor),
    ("kind", encodeEnvReadKind s.kind),
    ("vaultRoleId", vaultRoleId),
    ("vaultAtaRoleId", vaultAtaRoleId),
    ("mintRoleId", mintRoleId),
    ("systemProgramRoleId", systemProgramRoleId),
    ("tokenProgramRoleId", tokenProgramRoleId),
    ("ataProgramRoleId", ataProgramRoleId)
  ])

private def encodeContextReadSite (s : ContextReadSitePlanV1) : CompileResult PfJson := do
  let siteId ← pfNat "contextReadSite.siteId" s.siteId
  let handlerId ← pfNat "contextReadSite.handlerId" s.handlerId
  let anchor ← encodeAnchor s.anchor
  let callerRoleId ← pfNat "contextReadSite.callerRoleId" s.callerRoleId
  pure (.object #[
    ("siteId", siteId),
    ("handlerId", handlerId),
    ("anchor", anchor),
    ("kind", .string "caller"),
    ("callerRoleId", callerRoleId)
  ])

private def encodeComputeAssumptions (c : ComputeAssumptionsV1) :
    CompileResult PfJson := do
  pure (.object #[
    ("maxOuterRoles", ← pfNat "compute.maxOuterRoles" c.maxOuterRoles),
    ("maxCpiAccountInfos", ← pfNat "compute.maxCpiAccountInfos" c.maxCpiAccountInfos),
    ("maxCpiMetas", ← pfNat "compute.maxCpiMetas" c.maxCpiMetas),
    ("maxCpiSitesPerHandler",
      ← pfNat "compute.maxCpiSitesPerHandler" c.maxCpiSitesPerHandler),
    ("maxSignerGroupsPerCpi",
      ← pfNat "compute.maxSignerGroupsPerCpi" c.maxSignerGroupsPerCpi),
    ("maxSeedsIncludingBump",
      ← pfNat "compute.maxSeedsIncludingBump" c.maxSeedsIncludingBump),
    ("maxSeedBytes", ← pfNat "compute.maxSeedBytes" c.maxSeedBytes),
    ("maxInstructionDataBytes",
      ← pfNat "compute.maxInstructionDataBytes" c.maxInstructionDataBytes),
    ("maxPdaSpaceBytes", ← pfNat "compute.maxPdaSpaceBytes" c.maxPdaSpaceBytes),
    ("instructionStackDepth",
      ← pfNat "compute.instructionStackDepth" c.instructionStackDepth),
    ("returnDataPolicy", .string c.returnDataPolicy),
    ("failurePolicy", .string c.failurePolicy),
    ("activationRule", .string c.activationRule),
    ("implementationState", .string c.implementationState)
  ])

private def encodeRequirement (r : RequirementRequestV1) : CompileResult PfJson := do
  let version ← mapExcept (renderSemVer r.version) "extensionRequirement.version"
  let digest ← mapExcept (renderDigest r.digest) "extensionRequirement.digest"
  unless r.predicates.isEmpty do
    planFail "extensionRequirement.predicates must be empty for product v1"
  pure (.object #[
    ("id", .string r.id),
    ("version", .string version),
    ("digest", .string digest),
    ("predicates", .array #[])
  ])

private def encodeCandidatePfJson
    (c : SolanaCpiPlanCandidateV1) : CompileResult PfJson := do
  let profileDigest ←
    mapExcept (renderDigest c.profileDigest) "profileDigest"
  let catalogDigest ←
    mapExcept (renderDigest c.calleeCatalogDigest) "calleeCatalogDigest"
  let extension ← encodeRequirement c.extensionRequirement
  let stateSchemas ← c.stateSchemas.mapM encodeStateSchema
  let pdaRules ← c.pdaRules.mapM encodeFrozenPdaRule
  let accountRoles ← c.accountRoles.mapM encodeAccountRole
  let handlers ← c.handlers.mapM encodeHandler
  let cpiSites ← c.cpiSites.mapM encodeCpiSite
  let envReadSites ← c.envReadSites.mapM encodeEnvReadSite
  let contextReadSites ← c.contextReadSites.mapM encodeContextReadSite
  let compute ← encodeComputeAssumptions c.computeAssumptions
  pure (.object #[
    ("schema", .string c.schema),
    ("profileId", .string c.profileId),
    ("profileDigest", .string profileDigest),
    ("extensionRequirement", extension),
    ("calleeCatalogDigest", .string catalogDigest),
    ("programName", .string c.programName),
    ("stateSchemas", .array stateSchemas),
    ("pdaRules", .array pdaRules),
    ("accountRoles", .array accountRoles),
    ("handlers", .array handlers),
    ("cpiSites", .array cpiSites),
    ("envReadSites", .array envReadSites),
    ("contextReadSites", .array contextReadSites),
    ("computeAssumptions", compute)
  ])

private def encodeCandidateCanonical
    (c : SolanaCpiPlanCandidateV1) : CompileResult ByteArray := do
  let json ← encodeCandidatePfJson c
  let text ← mapExcept (renderPfJcs json) "canonical PF-JCS"
  pure text.toUTF8

/-! ## C) Sole validateSolanaCpiPlanV1 -/

private def validateIdentity (c : SolanaCpiPlanCandidateV1) : CompileResult Unit := do
  unless c.schema == planSchemaV1 do
    planFail s!"schema must be exact {planSchemaV1}"
  unless c.profileId == profileIdV1 do
    planFail s!"profileId must be exact {profileIdV1}"
  let expectedProfile ← mapExcept expectedProfileDigestV1 "profileDigest"
  unless digestsEqual c.profileDigest expectedProfile do
    planFail "profileDigest must equal frozen pf.solana.cpi-profile.v1 digest"
  let expectedCatalog ← mapExcept expectedCatalogDigestV1 "calleeCatalogDigest"
  unless digestsEqual c.calleeCatalogDigest expectedCatalog do
    planFail "calleeCatalogDigest must equal frozen pf.solana.callee-catalog.v1 digest"
  let expectedExt ← mapExcept expectedExtensionRequirementV1 "extensionRequirement"
  let expectedPf ← match pfAssetsExtensionRequirementV1 with
    | .ok r => pure r
    | .error e => planFail s!"pf.assets extension seed: {e}"
  let expectedCaller ← match callerContextRequirementV1 with
    | .ok r => pure r
    | .error e => planFail s!"context.caller requirement seed: {e}"
  let expectedBodyOnly ← match bodyOnlyAdmissionRequirementV1 with
    | .ok r => pure r
    | .error e => planFail s!"body-only admission seed: {e}"
  let extOk :=
    (c.extensionRequirement.id == expectedExt.id &&
      c.extensionRequirement.version == expectedExt.version &&
      digestsEqual c.extensionRequirement.digest expectedExt.digest &&
      c.extensionRequirement.predicates == expectedExt.predicates) ||
    (c.extensionRequirement.id == expectedPf.id &&
      c.extensionRequirement.version == expectedPf.version &&
      digestsEqual c.extensionRequirement.digest expectedPf.digest &&
      c.extensionRequirement.predicates == expectedPf.predicates) ||
    (c.extensionRequirement.id == expectedCaller.id &&
      c.extensionRequirement.version == expectedCaller.version &&
      digestsEqual c.extensionRequirement.digest expectedCaller.digest &&
      c.extensionRequirement.predicates == expectedCaller.predicates) ||
    (c.extensionRequirement.id == expectedBodyOnly.id &&
      c.extensionRequirement.version == expectedBodyOnly.version &&
      digestsEqual c.extensionRequirement.digest expectedBodyOnly.digest &&
      c.extensionRequirement.predicates == expectedBodyOnly.predicates)
  unless extOk do
    planFail
      "extensionRequirement must equal exact solanaCpiAccounts, pf.assets, context.caller, or body-only seed"
  match validateIdentifierComponent c.programName with
  | .ok () => pure ()
  | .error msg => planFail s!"programName: {msg}"

private def validateStateAndAssumptions
    (c : SolanaCpiPlanCandidateV1) : CompileResult Unit := do
  unless c.pdaRules == frozenPdaRulesV1 do
    planFail "pdaRules must equal exact frozenPdaRulesV1"
  unless c.computeAssumptions == frozenComputeAssumptionsV1 do
    planFail "computeAssumptions must equal exact frozenComputeAssumptionsV1"
  unless c.stateSchemas.size ≤ 1 do
    planFail "stateSchemas size must be ≤ 1"
  let schemaIds := c.stateSchemas.map (·.schemaId)
  unless arrayDenseFromZero schemaIds do
    planFail "stateSchemas schemaIds must be dense 0..n-1"
  for i in [0:c.stateSchemas.size] do
    let s ← getArr c.stateSchemas i "stateSchemas"
    unless s.schemaId == i do
      planFail "stateSchemas must appear in dense schemaId order"
    requireUInt32 "stateSchema.schemaId" s.schemaId
    if s.name.utf8ByteSize == 0 then
      planFail "stateSchema name must be nonempty"
    match validateIdentifierComponent s.name with
    | .ok () => pure ()
    | .error msg => planFail s!"stateSchema name: {msg}"
    unless 1 ≤ s.exactDataLen && s.exactDataLen ≤ 4096 do
      planFail "stateSchema.exactDataLen must be in 1..4096"
    requireUInt32 "stateSchema.exactDataLen" s.exactDataLen
    match validateDigest s.layoutDigest with
    | .ok () => pure ()
    | .error msg => planFail s!"stateSchema.layoutDigest: {msg}"
    -- initializedMarker: nonzero and exact first 8 BE bytes of layoutDigest.
    unless s.initializedMarker != 0 do
      planFail "stateSchema.initializedMarker must be nonzero"
    unless s.layoutDigest.bytes.size == 32 do
      planFail "stateSchema.layoutDigest must be 32 raw bytes"
    let expectedMarker : UInt64 := Id.run do
      let mut value : UInt64 := 0
      for index in [0:8] do
        value := UInt64.shiftLeft value 8 ||| s.layoutDigest.bytes[index]!.toUInt64
      pure value
    unless s.initializedMarker == expectedMarker do
      planFail
        "stateSchema.initializedMarker must equal first 8 layoutDigest bytes (BE)"
  unless namesUnique (c.stateSchemas.map (·.name)) do
    planFail "stateSchema names must be unique"

private def validateRoles (c : SolanaCpiPlanCandidateV1) : CompileResult Unit := do
  -- `accountRoles` is the program-global schema universe. The frozen 16-role
  -- cap applies per handler/invocation, not across unrelated callables.
  unless c.accountRoles.size ≤ maxUInt32Nat do
    planFail "accountRoles size exceeds canonical UInt32 table bound"
  let roleIds := c.accountRoles.map (·.roleId)
  unless arrayDenseFromZero roleIds do
    planFail "accountRoles roleIds must be dense 0..n-1"
  for i in [0:c.accountRoles.size] do
    let role ← getArr c.accountRoles i "accountRoles"
    unless role.roleId == i do
      planFail "accountRoles must appear in dense roleId order"
    requireUInt32 "accountRole.roleId" role.roleId
    match validateIdentifierComponent role.name with
    | .ok () => pure ()
    | .error msg => planFail s!"accountRole name: {msg}"
    unless role.aliasPolicy == frozenAliasPolicyV1 do
      planFail "accountRole aliasPolicy must equal frozenAliasPolicyV1"
  unless namesUnique (c.accountRoles.map (·.name)) do
    planFail "accountRole names must be unique"

  let mut fixedPackages : Array String := #[]
  let mut accountParamKeys : Array (Nat × Nat) := #[]
  let mut stateRoleCount : Array Nat := Array.replicate c.stateSchemas.size 0
  for role in c.accountRoles do
    match role.keyPolicy with
    | .state schemaId =>
        requireUInt32 "roleKeyPolicy.state.schemaId" schemaId
        match findStateSchema? c.stateSchemas schemaId with
        | none => planFail "state role references unknown state schemaId"
        | some _ =>
            unless schemaId < stateRoleCount.size do
              planFail "state role schemaId out of range"
            match stateRoleCount[schemaId]? with
            | some n => stateRoleCount := stateRoleCount.set! schemaId (n + 1)
            | none => planFail "stateRoleCount index out of range"
        unless role.constraint == stateRoleConstraintV1 do
          planFail "state role constraint must equal stateRoleConstraintV1"
    | .accountParameter callableId paramOrdinal =>
        requireUInt32 "roleKeyPolicy.accountParameter.callableId" callableId
        requireUInt32 "roleKeyPolicy.accountParameter.paramOrdinal" paramOrdinal
        accountParamKeys := accountParamKeys.push (callableId, paramOrdinal)
        unless role.constraint == accountBoundRoleConstraintV1 do
          planFail
            "accountParameter role constraint must equal accountBoundRoleConstraintV1"
        -- callable must be owned by some handler
        unless c.handlers.any (fun h => h.callableId == callableId) do
          planFail "accountParameter role callableId is not a handler callable"
    | .fixedProgram packageId =>
        match findCalleePackage? packageId with
        | none => planFail s!"fixedProgram role package '{packageId}' is unknown"
        | some _ => pure ()
        unless role.constraint == calleeRoleConstraintV1 do
          planFail "fixedProgram role constraint must equal calleeRoleConstraintV1"
        if fixedPackages.any (· == packageId) then
          planFail s!"duplicate fixedProgram role for package '{packageId}'"
        fixedPackages := fixedPackages.push packageId
    | .vaultPda =>
        unless role.name == "pf_vault" do
          planFail "vaultPda role name must be pf_vault"
    | .handlerCaller =>
        unless role.name == "pf_caller" do
          planFail "handlerCaller role name must be pf_caller"
    | .vaultAta =>
        unless role.name == "pf_vault_ata" do
          planFail "vaultAta role name must be pf_vault_ata"
    | .dstAta =>
        unless role.name == "pf_dst_ata" do
          planFail "dstAta role name must be pf_dst_ata"
  unless natPairsUnique accountParamKeys do
    planFail "accountParameter (callableId,paramOrdinal) must be unique"
  -- each state schema has exactly one state role (no unused)
  for i in [0:stateRoleCount.size] do
    match stateRoleCount[i]? with
    | some 1 => pure ()
    | some 0 => planFail "state schema has no state role (unused schema)"
    | some _ => planFail "state schema must have exactly one state role"
    | none => planFail "stateRoleCount index out of range"

private def lexLt3 (a b : Nat × Nat × Nat) : Bool :=
  a.1 < b.1 || (a.1 == b.1 && (a.2.1 < b.2.1 || (a.2.1 == b.2.1 && a.2.2 < b.2.2)))

private def validateHandlers (c : SolanaCpiPlanCandidateV1) : CompileResult Unit := do
  let handlerIds := c.handlers.map (·.handlerId)
  unless arrayDenseFromZero handlerIds do
    planFail "handlerIds must be dense 0..n-1"
  for i in [0:c.handlers.size] do
    let h ← getArr c.handlers i "handlers"
    unless h.handlerId == i do
      planFail "handlers must appear in dense handlerId order"
    requireUInt32 "handler.handlerId" h.handlerId
    requireUInt32 "handler.callableId" h.callableId
    match validateIdentifierComponent h.name with
    | .ok () => pure ()
    | .error msg => planFail s!"handler name: {msg}"
  unless namesUnique (c.handlers.map (·.name)) do
    planFail "handler names must be unique"
  unless natsUnique (c.handlers.map (·.callableId)) do
    planFail "handler callableIds must be unique"
  unless (c.handlers.filter (fun h => h.mode == .initialize)).size ≤ 1 do
    planFail "at most one initialize handler is allowed"

  -- Site density + partition + source order by (handlerId, blockId, instructionIndex)
  let siteIds := c.cpiSites.map (·.siteId)
  unless arrayDenseFromZero siteIds do
    planFail "cpiSite siteIds must be dense 0..n-1"
  for i in [0:c.cpiSites.size] do
    let site ← getArr c.cpiSites i "cpiSites"
    unless site.siteId == i do
      planFail "cpiSites must appear in dense siteId order"
  -- Global sites strictly increasing by (handlerId, blockId, instructionIndex)
  for i in [1:c.cpiSites.size] do
    let prev ← getArr c.cpiSites (i - 1) "cpiSites"
    let cur ← getArr c.cpiSites i "cpiSites"
    let prevKey := (prev.handlerId, prev.anchor.blockId, prev.anchor.instructionIndex)
    let curKey := (cur.handlerId, cur.anchor.blockId, cur.anchor.instructionIndex)
    unless lexLt3 prevKey curKey do
      planFail
        "cpiSites must be strictly ordered by (handlerId, blockId, instructionIndex)"

  let mut claimed : Array Bool := Array.replicate c.cpiSites.size false
  for h in c.handlers do
    unless h.cpiSiteIds.size ≤ maxCpiSitesPerHandlerV1 do
      planFail s!"handler cpiSiteIds size must be ≤ {maxCpiSitesPerHandlerV1}"
    let mut prev? : Option Nat := none
    for siteId in h.cpiSiteIds do
      requireUInt32 "handler.cpiSiteId" siteId
      unless siteId < c.cpiSites.size do
        planFail "handler cpiSiteId out of range"
      match prev? with
      | some prev =>
          unless siteId > prev do
            planFail "handler cpiSiteIds must be strictly increasing source order"
      | none => pure ()
      prev? := some siteId
      let site ← getArr c.cpiSites siteId "cpiSites"
      unless site.handlerId == h.handlerId do
        planFail "handler cpiSiteIds must reference sites owned by that handler"
      match claimed[siteId]? with
      | some true => planFail "cpi site claimed by multiple handlers"
      | some false => claimed := claimed.set! siteId true
      | none => planFail "claimed bitmap index out of range"
  for i in [0:c.cpiSites.size] do
    match claimed[i]? with
    | some true => pure ()
    | some false => planFail "cpi site missing from its handler cpiSiteIds partition"
    | none => planFail "claimed bitmap index out of range"
  -- The exact partition above plus strictly increasing site ids proves each
  -- handler list is precisely its source-order site sequence; no H×S filter.

  -- Per-handler local ABI uses: derived role subset + direct privilege rules.
  -- The contract permits at most one state schema/role; compute it once.
  let stateRoleId? := (c.accountRoles.find? fun role =>
    match role.keyPolicy with | .state _ => true | _ => false).map (·.roleId)
  for h in c.handlers do
    let expectedRoles := deriveHandlerRoleIds c stateRoleId? h
    unless expectedRoles.size ≤ maxOuterRolesV1 do
      planFail s!"handler local account uses must be ≤ {maxOuterRolesV1}"
    unless h.accountUses.size == expectedRoles.size do
      planFail "handler accountUses size must equal derived role subset"
    unless natsUnique (h.accountUses.map (·.roleId)) do
      planFail "handler accountUses.roleId must be unique within handler"
    for i in [0:h.accountUses.size] do
      let use ← getArr h.accountUses i "handler.accountUses"
      unless use.position == i do
        planFail "handler accountUses.position must equal dense local order index"
      let expectedRole ← getArr expectedRoles i "derivedHandlerRoles"
      unless use.roleId == expectedRole do
        planFail "handler accountUses.roleId sequence must equal derived subset"
      requireUInt32 "handler.accountUse.position" use.position
      requireUInt32 "handler.accountUse.roleId" use.roleId
      let role ← match findRole? c.accountRoles use.roleId with
        | some r => pure r
        | none => planFail "handler accountUse roleId out of range"
      match role.keyPolicy with
      | .state _ =>
          match h.mode with
          | .initialize =>
              unless use.directSignerContribution && use.directWritableContribution do
                planFail
                  "initialize state role requires directSigner+directWritable"
          | .entry =>
              unless !use.directSignerContribution && use.directWritableContribution do
                planFail
                  "entry state role requires directWritable and non-signer"
          | .view =>
              unless !use.directSignerContribution && !use.directWritableContribution do
                planFail "view state role requires neither direct signer nor writable"
      | _ =>
          unless !use.directSignerContribution && !use.directWritableContribution do
            planFail
              "non-state role directSigner/directWritable must be false (site authority)"

  -- Global roles first-use order across handlers must be exact 0..n-1.
  -- Use a dense bitmap so this check is linear in actual account uses.
  let mut firstUse : Array Nat := #[]
  let mut seenRole : Array Bool := Array.replicate c.accountRoles.size false
  for h in c.handlers do
    for use in h.accountUses do
      match seenRole[use.roleId]? with
      | some false =>
          seenRole := seenRole.set! use.roleId true
          firstUse := firstUse.push use.roleId
      | some true => pure ()
      | none => planFail "handler accountUse roleId out of range"
  unless firstUse.size == c.accountRoles.size do
    planFail "global accountRoles must all appear in some handler (no unused roles)"
  for i in [0:firstUse.size] do
    let roleId ← getArr firstUse i "firstUse"
    unless roleId == i do
      planFail
        "global accountRoles first-use order must be exact dense 0..n-1"

private def validateSiteCaps (s : CpiSitePlanV1) : CompileResult Unit := do
  unless s.metas.size ≤ maxCpiMetasV1 do
    planFail s!"cpiSite metas size must be ≤ {maxCpiMetasV1}"
  unless s.accountInfoRoleIds.size ≤ maxCpiAccountInfosV1 do
    planFail s!"cpiSite accountInfoRoleIds size must be ≤ {maxCpiAccountInfosV1}"
  unless s.signerGroups.size ≤ maxSignerGroupsPerCpiV1 do
    planFail s!"cpiSite signerGroups size must be ≤ {maxSignerGroupsPerCpiV1}"
  unless s.instructionCodec.length ≤ maxInstructionDataBytesV1 do
    planFail s!"cpiSite instructionCodec.length must be ≤ {maxInstructionDataBytesV1}"

private def validateOneSite
    (c : SolanaCpiPlanCandidateV1) (s : CpiSitePlanV1) : CompileResult Unit := do
  requireUInt32 "cpiSite.siteId" s.siteId
  requireUInt32 "cpiSite.handlerId" s.handlerId
  requireUInt32 "anchor.callableId" s.anchor.callableId
  requireUInt32 "anchor.blockId" s.anchor.blockId
  requireUInt32 "anchor.instructionIndex" s.anchor.instructionIndex
  requireUInt32 "anchor.effectId" s.anchor.effectId
  requireUInt32 "cpiSite.programRoleId" s.programRoleId
  validateSiteCaps s

  let handler ← match findHandler? c.handlers s.handlerId with
    | some h => pure h
    | none => planFail "cpiSite.handlerId is unknown"
  unless s.anchor.callableId == handler.callableId do
    planFail "cpiSite.anchor.callableId must match handler.callableId"

  let api ← match findFrozenApi? s.qn with
    | some api => pure api
    | none => planFail s!"cpiSite.qn '{s.qn}' is not a frozen API"
  unless s.packageId == api.fixedProgram do
    planFail "cpiSite.packageId must equal frozen API fixedProgram"
  let pkg ← match findCalleePackage? s.packageId with
    | some p => pure p
    | none => planFail s!"cpiSite.packageId '{s.packageId}' is unknown"
  unless SolanaPubkeyV1.toBytes s.programKey == SolanaPubkeyV1.toBytes pkg.programId do
    planFail "cpiSite.programKey must equal frozen package programId raw bytes"
  unless s.preflight == api.preflight do
    planFail "cpiSite.preflight must equal frozen API preflight"

  -- programRole must be fixedProgram for this package.
  let programRole ← match findRole? c.accountRoles s.programRoleId with
    | some r => pure r
    | none => planFail "cpiSite.programRoleId is out of range"
  match programRole.keyPolicy with
  | .fixedProgram packageId =>
      unless packageId == s.packageId do
        planFail "cpiSite.programRoleId must be fixedProgram for site package"
  | _ => planFail "cpiSite.programRoleId must reference a fixedProgram role"
  unless programRole.constraint == calleeRoleConstraintV1 do
    planFail "cpiSite.programRole constraint must equal calleeRoleConstraintV1"
  -- programRole must appear in handler local uses
  unless handler.accountUses.any (fun u => u.roleId == s.programRoleId) do
    planFail "cpiSite.programRoleId must be present in handler accountUses"

  -- Args: exact frozen order + principal → same-callable accountParameter only.
  unless s.args.size == api.args.size do
    planFail "cpiSite.args count must equal frozen API args"
  let mut principalRoles : Array Nat := #[]
  for i in [0:s.args.size] do
    let binding ← getArr s.args i "cpiSite.args"
    let expected ← getArr api.args i "frozenApi.args"
    unless binding.spec == expected do
      planFail "cpiSite.args.spec must equal frozen API arg order/spec"
    requireUInt32 "cpiArg.semanticValueId" binding.semanticValueId
    match expected.type_ with
    | .principal =>
        match binding.roleId with
        | none => planFail "principal cpi arg must bind a roleId"
        | some roleId =>
            requireUInt32 "cpiArg.roleId" roleId
            if principalRoles.any (· == roleId) then
              planFail "principal cpi arg roleIds must be pairwise distinct"
            principalRoles := principalRoles.push roleId
            if roleId == s.programRoleId then
              planFail "principal cpi arg role must not equal programRoleId"
            let role ← match findRole? c.accountRoles roleId with
              | some r => pure r
              | none => planFail "principal cpi arg roleId out of range"
            match role.keyPolicy with
            | .accountParameter callableId _paramOrdinal =>
                unless callableId == handler.callableId do
                  planFail
                    "principal cpi arg must bind accountParameter of handler.callableId"
            | .state _ =>
                planFail "principal cpi arg must not bind a state role"
            | .fixedProgram _ =>
                planFail "principal cpi arg must not bind a fixedProgram role"
            | .vaultPda | .handlerCaller | .vaultAta | .dstAta =>
                planFail "principal cpi arg must not bind a synthetic vault/caller/ata role"
            unless handler.accountUses.any (fun u => u.roleId == roleId) do
              planFail "principal cpi arg role must appear in handler accountUses"
    | .uint64 | .uint8 | .unit =>
        match binding.roleId with
        | some _ => planFail "numeric/unit cpi arg must not bind a roleId"
        | none => pure ()

  unless s.instructionCodec == api.instructionCodec do
    planFail "cpiSite.instructionCodec must equal frozen API codec"

  -- Metas: exact frozen order/spec + metaIndex, role refs, binding match,
  -- pairwise distinct role IDs.
  unless s.metas.size == api.metas.size do
    planFail "cpiSite.metas count must equal frozen API metas"
  let mut metaRoleIds : Array Nat := #[]
  for i in [0:s.metas.size] do
    let metaSlot ← getArr s.metas i "cpiSite.metas"
    let expected ← getArr api.metas i "frozenApi.metas"
    unless metaSlot.metaIndex == i do
      planFail "cpiSite.metas.metaIndex must equal dense order index"
    unless metaSlot.spec == expected do
      planFail "cpiSite.metas.spec must equal frozen API meta order/spec"
    requireUInt32 "cpiMeta.roleId" metaSlot.roleId
    if metaRoleIds.any (· == metaSlot.roleId) then
      planFail "cpiSite meta roleIds must be pairwise distinct"
    metaRoleIds := metaRoleIds.push metaSlot.roleId
    if metaSlot.roleId == s.programRoleId then
      match expected.binding with
      | .fixedProgram _ | .arg _ | .vaultPda | .handlerCaller | .vaultAta | .dstAta =>
          planFail "cpiSite meta role must not equal programRoleId"
    let role ← match findRole? c.accountRoles metaSlot.roleId with
      | some r => pure r
      | none => planFail "cpiSite meta roleId out of range"
    unless handler.accountUses.any (fun u => u.roleId == metaSlot.roleId) do
      planFail "cpiSite meta role must appear in handler accountUses"
    match expected.binding with
    | .arg name =>
        let argIdx? := s.args.findIdx? (fun a => a.spec.name == name)
        match argIdx? with
        | none => planFail s!"cpiSite meta arg '{name}' missing from args"
        | some argIdx =>
            let binding ← getArr s.args argIdx "cpiSite.args"
            match binding.roleId with
            | none => planFail s!"cpiSite meta arg '{name}' has no role binding"
            | some roleId =>
                unless roleId == metaSlot.roleId do
                  planFail s!"cpiSite meta role must match arg '{name}' role binding"
            match role.keyPolicy with
            | .fixedProgram .. =>
                planFail "arg-bound meta must not use a fixedProgram role"
            | _ => pure ()
    | .fixedProgram packageId =>
        match role.keyPolicy with
        | .fixedProgram p =>
            unless p == packageId do
              planFail "fixedProgram meta role package must match meta binding"
        | _ => planFail "fixedProgram meta must bind a fixedProgram role"
    | .vaultPda =>
        match role.keyPolicy with
        | .vaultPda => pure ()
        | _ => planFail "vaultPda meta must bind a vaultPda role"
    | .handlerCaller =>
        match role.keyPolicy with
        | .handlerCaller => pure ()
        | _ => planFail "handlerCaller meta must bind a handlerCaller role"
    | .vaultAta =>
        match role.keyPolicy with
        | .vaultAta => pure ()
        | _ => planFail "vaultAta meta must bind a vaultAta role"
    | .dstAta =>
        match role.keyPolicy with
        | .dstAta => pure ()
        | _ => planFail "dstAta meta must bind a dstAta role"

  -- Outer-only exact match; principal roles already pairwise with metas/program.
  unless s.outerOnlyAccounts.size == api.outerOnlyAccounts.size do
    planFail "cpiSite.outerOnlyAccounts count must equal frozen API"
  for i in [0:s.outerOnlyAccounts.size] do
    let outer ← getArr s.outerOnlyAccounts i "cpiSite.outerOnlyAccounts"
    let expected ← getArr api.outerOnlyAccounts i "frozenApi.outerOnlyAccounts"
    unless outer.spec == expected do
      planFail "cpiSite.outerOnlyAccounts.spec must equal frozen API order/spec"
    requireUInt32 "cpiOuterOnly.roleId" outer.roleId
    if outer.roleId == s.programRoleId then
      planFail "outer-only role must not equal programRoleId"
    let role ← match findRole? c.accountRoles outer.roleId with
      | some r => pure r
      | none => planFail "cpiSite outer-only roleId out of range"
    unless handler.accountUses.any (fun u => u.roleId == outer.roleId) do
      planFail "outer-only role must appear in handler accountUses"
    let argIdx? := s.args.findIdx? (fun a => a.spec.name == expected.arg)
    match argIdx? with
    | none => planFail s!"outer-only arg '{expected.arg}' missing from args"
    | some argIdx =>
        let binding ← getArr s.args argIdx "cpiSite.args"
        match binding.roleId with
        | none => planFail s!"outer-only arg '{expected.arg}' has no role binding"
        | some roleId =>
            unless roleId == outer.roleId do
              planFail s!"outer-only role must match arg '{expected.arg}' binding"
            -- outer-only must already be a principal arg role (pairwise set)
            unless principalRoles.any (· == roleId) do
              planFail "outer-only role must equal a principal arg role binding"
    match role.keyPolicy with
    | .fixedProgram .. =>
        planFail "outer-only account must not use a fixedProgram role"
    | _ => pure ()

  -- Principal roles (args; outer-only reuses them) pairwise + distinct from program.
  unless natsUnique principalRoles do
    planFail "site principal arg roleIds (incl. outer-only) must be pairwise distinct"
  if principalRoles.any (· == s.programRoleId) then
    planFail "programRoleId must be distinct from principal arg roles"

  -- accountInfos exact handler local role order (not global full universe).
  let expectedInfos := handler.accountUses.map (·.roleId)
  unless s.accountInfoRoleIds == expectedInfos do
    planFail
      "cpiSite.accountInfoRoleIds must equal handler.accountUses.roleId order"

  unless s.signerGroups == api.signerGroups do
    planFail "cpiSite.signerGroups must equal frozen API signerGroups"
  unless s.pda == api.pda do
    planFail "cpiSite.pda must equal frozen API pda"
  unless s.returnDataPolicy == propagateImmediatelyReturnDataPolicyV1 do
    planFail "cpiSite.returnDataPolicy must equal propagateImmediatelyReturnDataPolicyV1"
  unless s.failurePolicy == propagateImmediatelyFailurePolicyV1 do
    planFail "cpiSite.failurePolicy must equal propagateImmediatelyFailurePolicyV1"

  -- Site predicates exact derived order: callee, metas, outer-only.
  let expectedPreds := deriveSitePredicates s programRole.constraint
  unless s.sitePredicates == expectedPreds do
    planFail "cpiSite.sitePredicates must equal derived callee/metas/outer-only order"

private def validateSites (c : SolanaCpiPlanCandidateV1) : CompileResult Unit := do
  -- Uniqueness: (callableId, effectId) and
  -- (callableId, blockId, instructionIndex), using sorted copies rather than
  -- quadratic source-order scans. Source order itself remains untouched.
  let effectKeys := c.cpiSites.map fun s =>
    (s.anchor.callableId, s.anchor.effectId)
  unless natPairsUnique effectKeys do
    planFail "cpiSite (callableId, effectId) must be unique"
  let anchorKeys := c.cpiSites.map fun s =>
    (s.anchor.callableId, s.anchor.blockId, s.anchor.instructionIndex)
  unless natTriplesUnique anchorKeys do
    planFail "cpiSite (callableId, blockId, instructionIndex) must be unique"

  for s in c.cpiSites do
    validateOneSite c s

  -- Per-handler count equality/cap was already proven by the exact partition
  -- and `handler.cpiSiteIds` validation phase; do not rescan all sites here.

/-- Site-level outerSigner/outerWritable contribution for one role.
    ADR-0030 E1b: for token.transfer sites, the synthetic handlerCaller role
    (ATA ensure payer) contributes outerSigner+outerWritable even though it
    is not a CPI meta. This mirrors the derive-time privilege injection. -/
private def siteRoleContributions
    (site : CpiSitePlanV1) (roleId : Nat) : Bool × Bool :=
  Id.run do
    let mut signer := false
    let mut writable := false
    for metaSlot in site.metas do
      if metaSlot.roleId == roleId then
        if metaSlot.spec.outerSignerContribution then signer := true
        if metaSlot.spec.outerWritableContribution then writable := true
    for outer in site.outerOnlyAccounts do
      if outer.roleId == roleId then
        if outer.spec.outerSignerContribution then signer := true
        if outer.spec.outerWritableContribution then writable := true
    pure (signer, writable)

private def validatePrivilegeJoin
    (c : SolanaCpiPlanCandidateV1) : CompileResult Unit := do
  for h in c.handlers do
    -- ADR-0030 E1b: detect handlerCaller role for token.transfer privilege join.
    let handlerCallerRoleId? := c.accountRoles.findSome? (fun r =>
      match r.keyPolicy with | .handlerCaller => some r.roleId | _ => none)
    let hasTokenTransferSite := h.cpiSiteIds.any (fun sid =>
      match c.cpiSites[sid]? with
      | some s => s.qn == "pf.assets.token.transfer"
      | none => false)
    -- ADR-0031 S1: context.caller sites require pf_caller outerSigner
    -- (read-only; not writable) even though they are not CPI metas.
    let hasContextCallerSite := c.contextReadSites.any (fun s =>
      s.handlerId == h.handlerId)
    for use in h.accountUses do
      let mut siteSigner := false
      let mut siteWritable := false
      for siteId in h.cpiSiteIds do
        let site ← getArr c.cpiSites siteId "privilege handler site"
        let (sg, wr) := siteRoleContributions site use.roleId
        if sg then siteSigner := true
        if wr then siteWritable := true
      -- ADR-0030 E1b: handlerCaller contributes signer+writable for
      -- token.transfer ATA ensure even though it is not a CPI meta.
      if hasTokenTransferSite && some use.roleId == handlerCallerRoleId? then
        siteSigner := true
        siteWritable := true
      -- ADR-0031 S1: context.caller contributes signer-only for pf_caller.
      if hasContextCallerSite && some use.roleId == handlerCallerRoleId? then
        siteSigner := true
      let expectedSigner := use.directSignerContribution || siteSigner
      let expectedWritable := use.directWritableContribution || siteWritable
      unless use.outerSigner == expectedSigner do
        planFail
          "handler outerSigner must equal directSignerContribution OR site contributions"
      unless use.outerWritable == expectedWritable do
        planFail
          "handler outerWritable must equal directWritableContribution OR site contributions"

    for siteId in h.cpiSiteIds do
      let site ← getArr c.cpiSites siteId "privilege handler site"
      for metaSlot in site.metas do
        let use ← match h.accountUses.find? (fun u => u.roleId == metaSlot.roleId) with
          | some u => pure u
          | none => planFail "meta role missing from handler accountUses"
        if metaSlot.spec.cpiWritable then
          unless use.outerWritable do
            planFail "cpiWritable requires handler outerWritable for the role"
        if metaSlot.spec.cpiSigner then
          match metaSlot.spec.signerGroupId with
          | none =>
              unless use.outerSigner do
                planFail
                  "cpiSigner without signer group requires handler outerSigner"
          | some groupId =>
              if use.outerSigner then
                planFail
                  "cpiSigner with signer group requires handler outerSigner=false"
              let group ← match site.signerGroups.find? (fun g => g.id == groupId) with
                | some g => pure g
                | none => planFail "meta signerGroupId missing from site.signerGroups"
              match metaSlot.spec.binding with
              | .arg name =>
                  unless group.metaArg == name do
                    planFail "signer group metaArg must equal meta arg binding name"
              | .vaultPda =>
                  unless group.metaArg == "vault" do
                    planFail "vaultPda signer group metaArg must be 'vault'"
              | .fixedProgram _ | .handlerCaller | .vaultAta | .dstAta =>
                  planFail "signer group cannot attach to fixedProgram/handlerCaller/ata meta"
              match site.pda with
              | .signer rule _ _ _ _ _ =>
                  unless group.pdaRule == rule do
                    planFail "signer group pdaRule must equal site PDA rule"
              | .addressCheckOnly rule _ _ _ =>
                  unless group.pdaRule == rule do
                    planFail "signer group pdaRule must equal site PDA rule"
              | .vaultPdaSigner rule =>
                  unless group.pdaRule == rule && rule == vaultPdaRuleIdV1 do
                    planFail "vaultPdaSigner group must use proof-forge:vault:v1"
              | .none =>
                  planFail "signer group requires site PDA rule"

/-! ## ADR-0030 E2-3 env-read site validation -/

private def validateEnvReadSites (c : SolanaCpiPlanCandidateV1) :
    CompileResult Unit := do
  let siteIds := c.envReadSites.map (·.siteId)
  unless arrayDenseFromZero siteIds do
    planFail "envReadSiteIds must be dense 0..n-1"
  for i in [0:c.envReadSites.size] do
    let s ← getArr c.envReadSites i "envReadSites"
    unless s.siteId == i do
      planFail "envReadSite.siteId must equal dense index"
    requireUInt32 "envReadSite.siteId" s.siteId
    requireUInt32 "envReadSite.handlerId" s.handlerId
    requireUInt32 "envReadSite.anchor.callableId" s.anchor.callableId
    requireUInt32 "envReadSite.anchor.blockId" s.anchor.blockId
    requireUInt32 "envReadSite.anchor.instructionIndex" s.anchor.instructionIndex
    -- effectId is always 0 for envRead (effect-free)
    requireUInt32 "envReadSite.anchor.effectId" s.anchor.effectId
    unless s.anchor.effectId == 0 do
      planFail "envReadSite.anchor.effectId must be 0 (effect-free)"
    -- handlerId must reference a real handler
    unless c.handlers.any (·.handlerId == s.handlerId) do
      planFail "envReadSite.handlerId must reference a real handler"
    -- handler must be a view (envRead is read-only; entry/init/pureFn FC)
    let h ← match c.handlers.find? (·.handlerId == s.handlerId) with
    | some h => pure h
    | none => planFail "envReadSite handler missing"
    unless h.mode == .view do
      planFail "envReadSite handler must be .view (read-only)"
    -- roleIds must reference real account roles
    for roleId in #[s.vaultRoleId, s.vaultAtaRoleId, s.mintRoleId,
        s.systemProgramRoleId, s.tokenProgramRoleId, s.ataProgramRoleId] do
      unless roleId < c.accountRoles.size do
        planFail "envReadSite roleId out of range"
    -- vault role must be .vaultPda
    let vaultRole ← getArr c.accountRoles s.vaultRoleId "envReadSite.vaultRole"
    unless vaultRole.keyPolicy == .vaultPda do
      planFail "envReadSite.vaultRoleId must be .vaultPda"
    match s.kind with
    | .nativeVaultBalance =>
        -- Native: vaultAta/mint/program roles are unused (must be 0)
        -- but we don't enforce 0 to keep the structure uniform; the IR/emitter
        -- ignore them. The key constraint is vault role only.
        pure ()
    | .tokenVaultBalance =>
        -- Token: vaultAta must be .vaultAta, mint must be .accountParameter,
        -- program roles must be .fixedProgram with exact package ids.
        let vaultAtaRole ←
          getArr c.accountRoles s.vaultAtaRoleId "envReadSite.vaultAtaRole"
        unless vaultAtaRole.keyPolicy == .vaultAta do
          planFail "envReadSite.vaultAtaRoleId must be .vaultAta"
        let mintRole ←
          getArr c.accountRoles s.mintRoleId "envReadSite.mintRole"
        match mintRole.keyPolicy with
        | .accountParameter cid _ =>
            unless cid == h.callableId do
              planFail "envReadSite.mintRoleId must belong to this handler"
        | _ =>
            planFail "envReadSite.mintRoleId must be .accountParameter"
        let sysRole ←
          getArr c.accountRoles s.systemProgramRoleId "envReadSite.systemRole"
        unless sysRole.keyPolicy == .fixedProgram "system-v1" do
          planFail "envReadSite.systemProgramRoleId must be .fixedProgram system-v1"
        let tokRole ←
          getArr c.accountRoles s.tokenProgramRoleId "envReadSite.tokenRole"
        unless tokRole.keyPolicy == .fixedProgram "token-classic-v1" do
          planFail "envReadSite.tokenProgramRoleId must be .fixedProgram token-classic-v1"
        let ataRole ←
          getArr c.accountRoles s.ataProgramRoleId "envReadSite.ataRole"
        unless ataRole.keyPolicy == .fixedProgram "ata-classic-v1" do
          planFail "envReadSite.ataProgramRoleId must be .fixedProgram ata-classic-v1"

/-! ## ADR-0031 S1 context.caller site validation -/

private def validateContextReadSites (c : SolanaCpiPlanCandidateV1) :
    CompileResult Unit := do
  let siteIds := c.contextReadSites.map (·.siteId)
  unless arrayDenseFromZero siteIds do
    planFail "contextReadSiteIds must be dense 0..n-1"
  for i in [0:c.contextReadSites.size] do
    let s ← getArr c.contextReadSites i "contextReadSites"
    unless s.siteId == i do
      planFail "contextReadSite.siteId must equal dense index"
    requireUInt32 "contextReadSite.siteId" s.siteId
    requireUInt32 "contextReadSite.handlerId" s.handlerId
    requireUInt32 "contextReadSite.anchor.callableId" s.anchor.callableId
    requireUInt32 "contextReadSite.anchor.blockId" s.anchor.blockId
    requireUInt32 "contextReadSite.anchor.instructionIndex" s.anchor.instructionIndex
    requireUInt32 "contextReadSite.anchor.effectId" s.anchor.effectId
    unless s.anchor.effectId == 0 do
      planFail "contextReadSite.anchor.effectId must be 0 (effect-free)"
    unless c.handlers.any (·.handlerId == s.handlerId) do
      planFail "contextReadSite.handlerId must reference a real handler"
    let h ← match c.handlers.find? (·.handlerId == s.handlerId) with
    | some h => pure h
    | none => planFail "contextReadSite handler missing"
    -- entry + view admitted (read-only account-key observation; view-safe).
    -- pureFn/invariant/initializer stay fail closed at derive.
    unless h.mode == .view || h.mode == .entry do
      planFail "contextReadSite handler must be .view or .entry"
    unless s.callerRoleId < c.accountRoles.size do
      planFail "contextReadSite.callerRoleId out of range"
    let callerRole ← getArr c.accountRoles s.callerRoleId "contextReadSite.callerRole"
    unless callerRole.keyPolicy == .handlerCaller do
      planFail "contextReadSite.callerRoleId must be .handlerCaller (pf_caller)"
    unless callerRole.name == "pf_caller" do
      planFail "contextReadSite caller role name must be pf_caller"
    -- Handler local ABI must include the caller role with outerSigner.
    unless h.accountUses.any (fun u =>
        u.roleId == s.callerRoleId && u.outerSigner) do
      planFail
        "contextReadSite caller role must appear in handler accountUses with outerSigner"

/-- Sole #117 structural validation entry: deterministic phase order 1..6.
    It binds every DTO field into canonical bytes but does not certify that
    caller-supplied semantic anchors/value IDs exist in a retained program. -/
def validateSolanaCpiPlanV1
    (candidate : SolanaCpiPlanCandidateV1) :
    CompileResult ValidatedSolanaCpiPlanV1 := do
  -- Phase 1: identity
  validateIdentity candidate
  -- Phase 2: pdaRules / compute / state schemas
  validateStateAndAssumptions candidate
  -- Phase 3: roles
  validateRoles candidate
  -- Phase 4: handlers (+ site partition / source order / local ABI derivation)
  validateHandlers candidate
  -- Phase 5: sites (content + caps + uniqueness + predicates)
  validateSites candidate
  -- Phase 5.5: env-read sites (E2-3)
  validateEnvReadSites candidate
  -- Phase 5.6: context.caller sites (ADR-0031 S1)
  validateContextReadSites candidate
  -- Phase 6: privilege join
  validatePrivilegeJoin candidate
  -- Canonical encode + digest (only validated carrier exposes digest).
  let canonicalBytes ← encodeCandidateCanonical candidate
  let digest ← mapExcept
    (domainSeparatedSha256 planDigestDomainV1 canonicalBytes)
    "plan digest"
  pure ⟨candidate, canonicalBytes, digest⟩

/-! ## D) Materialization eligibility (always rejects inert profile) -/

/-- Reject any referenced package that is not admitted, and always reject the
    current inert profile even when the candidate has zero CPI sites.
    Never mints files. -/
def checkSolanaCpiMaterializationEligibilityV1
    (plan : ValidatedSolanaCpiPlanV1) : CompileResult Unit := do
  let c := plan.candidate
  let mut packages : Array String := #[]
  for role in c.accountRoles do
    match role.keyPolicy with
    | .fixedProgram packageId =>
        if !(packages.any (· == packageId)) then
          packages := packages.push packageId
    | _ => pure ()
  for site in c.cpiSites do
    if !(packages.any (· == site.packageId)) then
      packages := packages.push site.packageId
    for metaSlot in site.metas do
      match metaSlot.spec.binding with
      | .fixedProgram packageId =>
          if !(packages.any (· == packageId)) then
            packages := packages.push packageId
      | _ => pure ()
  for packageId in packages do
    match findCalleePackage? packageId with
    | none =>
        planFail s!"materialization rejects absent package '{packageId}'"
    | some pkg =>
        unless pkg.admittedForMaterialization do
          planFail
            s!"materialization rejects package '{packageId}' with admitted=false"
        match pkg.artifactBinding with
        | .absent =>
            planFail
              s!"materialization rejects package '{packageId}' with artifactBinding=absent"
        | .runtimeNative _ => pure ()
  planFail
    "solana-sbpf-cpi-elf-v1 is inert-contract-only; materialization is not eligible"

/-! ## #125 product Plan validate + eligibility (active snapshot) -/

private def collectReferencedPackageIds
    (c : SolanaCpiPlanCandidateV1) : Array String :=
  Id.run do
    let mut packages : Array String := #[]
    for role in c.accountRoles do
      match role.keyPolicy with
      | .fixedProgram packageId =>
          if !(packages.any (· == packageId)) then
            packages := packages.push packageId
      | _ => pure ()
    for site in c.cpiSites do
      if !(packages.any (· == site.packageId)) then
        packages := packages.push site.packageId
      for metaSlot in site.metas do
        match metaSlot.spec.binding with
        | .fixedProgram packageId =>
            if !(packages.any (· == packageId)) then
              packages := packages.push packageId
        | _ => pure ()
    pure packages

private def validateProductIdentity
    (c : SolanaCpiPlanCandidateV1) : CompileResult Unit := do
  unless c.schema == planSchemaV1 do
    planFail s!"schema must be exact {planSchemaV1}"
  unless c.profileId == profileIdV1 do
    planFail s!"profileId must be exact {profileIdV1}"
  let expectedProfile ← mapExcept expectedActiveProfileDigestV1 "active profileDigest"
  unless digestsEqual c.profileDigest expectedProfile do
    planFail "product profileDigest must equal active pf.solana.cpi-profile.v1 digest"
  let expectedCatalog ← mapExcept expectedActiveCatalogDigestV1 "active catalogDigest"
  unless digestsEqual c.calleeCatalogDigest expectedCatalog do
    planFail "product calleeCatalogDigest must equal active catalog digest"
  let expectedExt ← mapExcept expectedExtensionRequirementV1 "extensionRequirement"
  let expectedPf ← match pfAssetsExtensionRequirementV1 with
    | .ok r => pure r
    | .error e => planFail s!"pf.assets extension seed: {e}"
  let expectedCaller ← match callerContextRequirementV1 with
    | .ok r => pure r
    | .error e => planFail s!"context.caller requirement seed: {e}"
  let expectedBodyOnly ← match bodyOnlyAdmissionRequirementV1 with
    | .ok r => pure r
    | .error e => planFail s!"body-only admission seed: {e}"
  let extOk :=
    (c.extensionRequirement.id == expectedExt.id &&
      c.extensionRequirement.version == expectedExt.version &&
      digestsEqual c.extensionRequirement.digest expectedExt.digest &&
      c.extensionRequirement.predicates == expectedExt.predicates) ||
    (c.extensionRequirement.id == expectedPf.id &&
      c.extensionRequirement.version == expectedPf.version &&
      digestsEqual c.extensionRequirement.digest expectedPf.digest &&
      c.extensionRequirement.predicates == expectedPf.predicates) ||
    (c.extensionRequirement.id == expectedCaller.id &&
      c.extensionRequirement.version == expectedCaller.version &&
      digestsEqual c.extensionRequirement.digest expectedCaller.digest &&
      c.extensionRequirement.predicates == expectedCaller.predicates) ||
    (c.extensionRequirement.id == expectedBodyOnly.id &&
      c.extensionRequirement.version == expectedBodyOnly.version &&
      digestsEqual c.extensionRequirement.digest expectedBodyOnly.digest &&
      c.extensionRequirement.predicates == expectedBodyOnly.predicates)
  unless extOk do
    planFail
      "extensionRequirement must equal exact solanaCpiAccounts, pf.assets, context.caller, or body-only seed"
  match validateIdentifierComponent c.programName with
  | .ok () => pure ()
  | .error msg => planFail s!"programName: {msg}"

private def validateProductStateAndAssumptions
    (c : SolanaCpiPlanCandidateV1) : CompileResult Unit := do
  unless c.pdaRules == frozenPdaRulesV1 do
    planFail "pdaRules must equal exact frozenPdaRulesV1"
  unless c.computeAssumptions == activeComputeAssumptionsV1 do
    planFail "product computeAssumptions must equal exact activeComputeAssumptionsV1"
  -- Reuse frozen state-schema gates by temporarily accepting only the shared
  -- state validation path: call the same checks as validateStateAndAssumptions
  -- except computeAssumptions (already checked above).
  unless c.stateSchemas.size ≤ 1 do
    planFail "stateSchemas size must be ≤ 1"
  let schemaIds := c.stateSchemas.map (·.schemaId)
  unless arrayDenseFromZero schemaIds do
    planFail "stateSchemas schemaIds must be dense 0..n-1"
  for i in [0:c.stateSchemas.size] do
    let s ← getArr c.stateSchemas i "stateSchemas"
    unless s.schemaId == i do
      planFail "stateSchemas must appear in dense schemaId order"
    requireUInt32 "stateSchema.schemaId" s.schemaId
    if s.name.utf8ByteSize == 0 then
      planFail "stateSchema name must be nonempty"
    match validateIdentifierComponent s.name with
    | .ok () => pure ()
    | .error msg => planFail s!"stateSchema name: {msg}"
    unless 1 ≤ s.exactDataLen && s.exactDataLen ≤ 4096 do
      planFail "stateSchema.exactDataLen must be in 1..4096"
    requireUInt32 "stateSchema.exactDataLen" s.exactDataLen
    match validateDigest s.layoutDigest with
    | .ok () => pure ()
    | .error msg => planFail s!"stateSchema.layoutDigest: {msg}"
    unless s.initializedMarker != 0 do
      planFail "stateSchema.initializedMarker must be nonzero"
    unless s.layoutDigest.bytes.size == 32 do
      planFail "stateSchema.layoutDigest must be 32 raw bytes"
    let expectedMarker : UInt64 := Id.run do
      let mut value : UInt64 := 0
      for index in [0:8] do
        value := UInt64.shiftLeft value 8 ||| s.layoutDigest.bytes[index]!.toUInt64
      pure value
    unless s.initializedMarker == expectedMarker do
      planFail
        "stateSchema.initializedMarker must equal first 8 layoutDigest bytes (BE)"
  unless namesUnique (c.stateSchemas.map (·.name)) do
    planFail "stateSchema names must be unique"

private def validateProductApprovedApis
    (c : SolanaCpiPlanCandidateV1) : CompileResult Unit := do
  for site in c.cpiSites do
    if isCompanionApiV1 site.qn then
      planFail s!"product Plan rejects companion API '{site.qn}'"
    unless isApprovedProductApiV1 site.qn do
      planFail s!"product Plan rejects non-approved API '{site.qn}'"

/-- Sole #125 product structural validation. Binds active profile/catalog digests
    and active compute assumptions into canonical bytes/digest. Companion and
    non-approved APIs fail closed. Does not mint OutputFile. -/
def validateSolanaCpiProductPlanV1
    (candidate : SolanaCpiPlanCandidateV1) :
    CompileResult ValidatedSolanaCpiPlanV1 := do
  validateProductIdentity candidate
  validateProductStateAndAssumptions candidate
  validateRoles candidate
  validateHandlers candidate
  validateSites candidate
  validateEnvReadSites candidate
  validatePrivilegeJoin candidate
  validateProductApprovedApis candidate
  let canonicalBytes ← encodeCandidateCanonical candidate
  let digest ← mapExcept
    (domainSeparatedSha256 planDigestDomainV1 canonicalBytes)
    "product plan digest"
  pure ⟨candidate, canonicalBytes, digest⟩

/-- #125 product materialization eligibility: only packages in
    `activeCalleePackagesV1` with admitted=true and non-absent artifact
    binding; every site must be an approved product API. Succeeds when the
    active snapshot admits every referenced package (unlike inert eligibility,
    which always fails closed). -/
def checkSolanaCpiProductMaterializationEligibilityV1
    (plan : ValidatedSolanaCpiPlanV1) : CompileResult Unit := do
  let c := plan.candidate
  let expectedProfile ← mapExcept expectedActiveProfileDigestV1 "active profileDigest"
  unless digestsEqual c.profileDigest expectedProfile do
    planFail "product eligibility requires active profileDigest"
  let expectedCatalog ← mapExcept expectedActiveCatalogDigestV1 "active catalogDigest"
  unless digestsEqual c.calleeCatalogDigest expectedCatalog do
    planFail "product eligibility requires active catalogDigest"
  unless c.computeAssumptions == activeComputeAssumptionsV1 do
    planFail "product eligibility requires activeComputeAssumptionsV1"
  for site in c.cpiSites do
    unless isApprovedProductApiV1 site.qn do
      planFail s!"product eligibility rejects API '{site.qn}'"
  let packages := collectReferencedPackageIds c
  for packageId in packages do
    match findActiveCalleePackage? packageId with
    | none =>
        planFail
          s!"product materialization rejects package '{packageId}' not in active catalog"
    | some pkg =>
        unless pkg.admittedForMaterialization do
          planFail
            s!"product materialization rejects package '{packageId}' with admitted=false"
        match pkg.artifactBinding with
        | .absent =>
            planFail
              s!"product materialization rejects package '{packageId}' with artifactBinding=absent"
        | .runtimeNative _ => pure ()
        | .loaderV3Elf _ => pure ()

end ProofForgeV2.Targets.Solana.CpiV1

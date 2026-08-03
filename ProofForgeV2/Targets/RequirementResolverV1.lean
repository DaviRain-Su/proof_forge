/-
  Engineering-only exact static requirement support index / inspection
  (D3/S5 vertical).

  **Not** SupportClaim, formal resolver, ResolvedSupportDecision,
  BuildIdentity, formal registry root digest, claimDigest, predicate implication,
  or OutputSetV1.

  Static rows are exactly the four currently implemented (targetId, codegenProfile)
  pairs from the frozen TargetRegistry membership table, in canonical
  (targetId, profile) ASCII order. Each row supports a per-target subset of the
  S2 seven RequirementRequestV1 keys in wire order:
    effect.asynchronous-workflow, effect.event, effect.synchronous-call,
    failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic
  with SemVer 1.0.0, engineeringRequirementDigestV1, and empty predicates only.
  Capability gates: EVM/Solana admit both call keys via **static**
  `QualifiedName` callees (AddressBearing followup: no dynamic address type;
  Plan lowers CALL/CPI-shaped sites from compile-time QN). NEAR declines only
  `effect.synchronous-call` (async workflow promises are native), Noir
  supports all seven.

  Product seed is `CompileResult` — no panic / Inhabited / empty success fallback.
  Dependency-injected seams return index rows or
  `RequirementResolutionInspectionV1` only — never a materialization capability.
-/
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Semantic.RequirementIdsV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.TargetRegistryV1

namespace ProofForgeV2.Targets.RequirementResolverV1

open ProofForgeV2
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.TargetRegistryV1

/-- One static support row: implemented (target, profile) + exact S2 requests. -/
structure StaticRequirementSupportRowV1 where
  targetId : TargetId
  codegenProfile : CodegenProfileId
  kind : TargetKind
  supported : Array RequirementRequestV1
  deriving BEq

/-- Validated static support index. Private constructor. -/
structure StaticRequirementSupportIndexV1 where
  private mk ::
  rows : Array StaticRequirementSupportRowV1

namespace StaticRequirementSupportIndexV1

def toArray (index : StaticRequirementSupportIndexV1) :
    Array StaticRequirementSupportRowV1 :=
  index.rows

end StaticRequirementSupportIndexV1

/-- Non-capability inspection of a support match or request resolution outcome.
    Dependency-injected seams may return this — never a materialize capability. -/
structure RequirementResolutionInspectionV1 where
  targetId : TargetId
  codegenProfile : CodegenProfileId
  kind : TargetKind
  supported : Array RequirementRequestV1
  deriving BEq

private def findDuplicateString (values : Array String) : Option String :=
  Id.run do
    let mut seen : Array String := #[]
    for v in values do
      if seen.contains v then
        return some v
      seen := seen.push v
    return none

/-- Canonical row key for uniqueness / order: `targetId\tcodegenProfile`. -/
private def rowKey (row : StaticRequirementSupportRowV1) : String :=
  s!"{row.targetId.toString}\t{row.codegenProfile.toString}"

private def isStrictlyAscendingAscii (values : Array String) : Bool :=
  Id.run do
    let mut i : Nat := 0
    while i + 1 < values.size do
      let a := values[i]!
      let b := values[i + 1]!
      unless a < b do
        return false
      i := i + 1
    return true

private def s2CatalogRequests : CompileResult (Array RequirementRequestV1) := do
  let mut items : Array RequirementRequestV1 := #[]
  for id in s2CatalogIdsWireOrderV1 do
    match mkS2RequirementRequestV1 id with
    | .ok req => items := items.push req
    | .error e => throw <| .registryInvalid s!"engineering S2 request seed failed: {e}"
  pure items

/-- Validate one supported-requirements array: unique ids, S2 catalog
    membership (any subset — per-target capability gates), exact
    version/digest, empty predicates, and SPEC wire order. -/
private def validateSupportedRequests
    (label : String) (supported : Array RequirementRequestV1) : CompileResult Unit := do
  let ids := supported.map (·.id)
  if let some dup := findDuplicateString ids then
    throw <| .registryDuplicate
      s!"duplicate requirement id '{dup}' in support row '{label}'"
  unless isStrictlyAscendingAscii ids do
    throw <| .registryInvalid
      s!"support requirements for '{label}' must be in SPEC wire order"
  let mut i : Nat := 0
  while i < supported.size do
    match supported[i]? with
    | some item =>
        unless isS2CatalogIdV1 item.id do
          throw <| .registryInvalid
            s!"support row '{label}' unknown requirement id '{item.id}'"
        unless item.version == s2RequirementVersionV1 do
          throw <| .registryInvalid
            s!"support row '{label}' requirement '{item.id}' version must be 1.0.0"
        let expectedDigest ← match engineeringRequirementDigestV1 item.id with
          | .ok d => pure d
          | .error e =>
              throw <| .registryInvalid
                s!"support row '{label}' requirement '{item.id}' digest unavailable: {e}"
        unless item.digest == expectedDigest do
          throw <| .registryInvalid
            s!"support row '{label}' requirement '{item.id}' digest mismatch"
        unless item.predicates.isEmpty do
          throw <| .registryInvalid
            s!"support row '{label}' requirement '{item.id}' must have empty predicates"
    | none =>
        throw <| .registryInvalid
          s!"support row '{label}' requirement index out of range"
    i := i + 1

/-- Implemented (targetId, profile, kind) triple carrier (avoids nested Prod). -/
private structure ImplementedPairV1 where
  targetId : TargetId
  codegenProfile : CodegenProfileId
  kind : TargetKind

/-- Exact implemented (target,profile) pairs from frozen TargetRegistryV1, in
    canonical (targetId, codegenProfile) ASCII order. -/
private def expectedImplementedPairs
    (regs : Array TargetRegistrationDataV1) :
    CompileResult (Array ImplementedPairV1) := do
  let mut pairs : Array ImplementedPairV1 := #[]
  for reg in regs do
    if reg.implemented then
      for p in reg.profiles do
        pairs := pairs.push {
          targetId := reg.targetId
          codegenProfile := p
          kind := reg.kind
        }
  let keys := pairs.map (fun t => s!"{t.targetId.toString}\t{t.codegenProfile.toString}")
  unless isStrictlyAscendingAscii keys do
    throw <| .registryInvalid
      "implemented build-selection pairs are not in canonical (target,profile) order"
  pure pairs

/-- Validate and construct a static requirement support index. Seed error first
    when the caller binds a failed `CompileResult`; this function never panics. -/
def createStaticRequirementSupportIndexV1
    (rows : Array StaticRequirementSupportRowV1) :
    CompileResult StaticRequirementSupportIndexV1 := do
  if rows.isEmpty then
    throw <| .registryInvalid "static requirement support index must be non-empty"
  let keys := rows.map rowKey
  if let some dup := findDuplicateString keys then
    throw <| .registryDuplicate s!"duplicate support row key '{dup}'"
  unless isStrictlyAscendingAscii keys do
    throw <| .registryInvalid
      "support rows must be strictly ascending by (targetId, codegenProfile)"
  -- Exact coverage of implemented TargetRegistry pairs (no design-only / extra /
  -- missing / cross-profile / wrong-kind).
  let regs ← productRegistrations
  let expected ← expectedImplementedPairs regs
  unless rows.size == expected.size do
    throw <| .registryInvalid
      s!"support index must cover exactly {expected.size} implemented profiles, got {rows.size}"
  let mut i : Nat := 0
  while i < rows.size do
    match rows[i]?, expected[i]? with
    | some row, some exp =>
        unless row.targetId == exp.targetId do
          throw <| .registryInvalid
            s!"support row {i} targetId diverges from implemented pair '{exp.targetId}'"
        unless row.codegenProfile == exp.codegenProfile do
          throw <| .registryInvalid
            s!"support row {i} profile diverges from implemented pair '{exp.codegenProfile}'"
        unless row.kind == exp.kind do
          throw <| .registryInvalid
            s!"support row {i} kind diverges from implemented pair '{exp.kind}'"
        unless row.kind.toString == row.targetId.toString do
          throw <| .registryInvalid
            s!"support row '{rowKey row}' kind does not match targetId"
        validateSupportedRequests (rowKey row) row.supported
    | _, _ =>
        throw <| .registryInvalid "support row index out of range"
    i := i + 1
  pure (StaticRequirementSupportIndexV1.mk rows)

private def mkImplementedRow
    (kind : TargetKind) (profile : CodegenProfileId)
    (supported : Array RequirementRequestV1) : StaticRequirementSupportRowV1 :=
  {
    targetId := TargetId.ofKind kind
    codegenProfile := profile
    kind
    supported
  }

/-- Shipped ten-row seed body (canonical targetId order: aleo, cosmwasm, evm×2,
    near, noir, psy, solana×2, ton). EVM carries both
    `evm-yul-solc-0.8.34-cancun-v1` and `evm-yul-solc-0.8.34-v1` (ASCII ascending;
    default remains legacy v1). Solana carries both `solana-sbpf-elf-v1`
    and `solana-sbpf-plan-v1` (ASCII ascending); both share the same S2
    capability set. Capability gates are per target: EVM/Solana admit both call
    keys via static QualifiedName callees (AddressBearing: wire
    Op.ExternalCall/Schedule take compile-time QN, not a dynamic address
    ValueId — no Principal→20B/32B map); NEAR has no synchronous external calls
    but owns async workflow promises, so it declines sync and supports
    `effect.asynchronous-workflow`; Noir's verifier-witness response model
    supports both; Aleo declines both call families (no static-callee Plan
    open) and `effect.event` (Leo 4.0.2 has no on-chain event log — emit fails
    closed at the materializer); Psy supports sync calls and events but
    declines `effect.asynchronous-workflow` (no emitted deferred crosscall
    form — schedule fails closed at the materializer). CosmWasm declined both
    call families at MVP: its `WasmMsg::Execute` is a same-transaction
    submessage with a savepoint, **not** an EVM-style synchronous CALL, and
    SubMsg fire-and-forget is **not** a cross-transaction async workflow —
    aliasing either would overclaim the platform semantics (B-CALL-SEM
    discipline). Its `effect.event` maps to Response attributes. CW-4 follow-up:
    `effect.asynchronous-workflow` is now admitted — schedule lowers to
    `SubMsg{reply_on:never, id:0, WasmMsg::Execute}` (no reply channel, same-tx
    savepoint dispatch; submessage failure aborts the whole transaction per
    wasmd `DispatchSubmessages`; `contract_addr` is a static QN stub pending
    deployment wiring — never a cross-tx async claim). TON is a
    pure-async actor chain: cross-contract interaction exists only as async
    internal messages, so `effect.synchronous-call` is declined outright while
    `effect.asynchronous-workflow` maps to raw async out-messages (bounce and
    value/gas attachment are materializer concerns, never a hidden sync
    fallback). Its `effect.event` maps to external out-messages. -/
private def initialSupportRowsResult : CompileResult (Array StaticRequirementSupportRowV1) := do
  let catalogRequests ← s2CatalogRequests
  -- Capability filters reference closed S2 id spellings from RequirementIdsV1
  -- (not bare literals). s2CatalogIdsWireOrderV1 stays RequirementsV1 public.
  let withoutSync := catalogRequests.filter fun r =>
    r.id != Semantic.RequirementIdsV1.s2EffectSyncCallIdV1
  let aleoRequests := catalogRequests.filter fun r =>
    r.id != Semantic.RequirementIdsV1.s2EffectEventIdV1 &&
      r.id != Semantic.RequirementIdsV1.s2EffectAsyncWorkflowIdV1 &&
      r.id != Semantic.RequirementIdsV1.s2EffectSyncCallIdV1
  -- Psy supports sync crosscalls (__invoke_sync#<Felt>) and events (__emit),
  -- but has no emitted deferred-crosscall form, so schedule fails closed and
  -- effect.asynchronous-workflow is declined here (never alias sync semantics).
  let psyRequests := catalogRequests.filter fun r =>
    r.id != Semantic.RequirementIdsV1.s2EffectAsyncWorkflowIdV1
  -- CosmWasm MVP+CW-4: sync declined (WasmMsg::Execute savepoint is not a
  -- sync CALL); async admitted via SubMsg reply_on=never (same-tx dispatch,
  -- whole-tx abort on submessage failure — not cross-tx async).
  let cosmwasmRequests := catalogRequests.filter fun r =>
    r.id != Semantic.RequirementIdsV1.s2EffectSyncCallIdV1
  pure #[
    mkImplementedRow .aleo CodegenProfileId.aleoLeoU64V1 aleoRequests,
    mkImplementedRow .cosmwasm CodegenProfileId.cosmwasmWasmU64V1 cosmwasmRequests,
    -- AddressBearing: full seven keys — static QN call/schedule Plan open.
    -- Both EVM profiles share the same S2 capability set; hardfork is a
    -- Finalize/runtime pin, not a requirement-gate difference.
    mkImplementedRow .evm CodegenProfileId.evmYulSolc0834CancunV1 catalogRequests,
    mkImplementedRow .evm CodegenProfileId.evmYulSolc0834V1 catalogRequests,
    mkImplementedRow .near CodegenProfileId.nearWasmRawU64V1 withoutSync,
    mkImplementedRow .noir CodegenProfileId.noirSourceU64RelationsV1 catalogRequests,
    mkImplementedRow .psy CodegenProfileId.psyDargoU64V1 psyRequests,
    mkImplementedRow .solana CodegenProfileId.solanaSbpfElfV1 catalogRequests,
    mkImplementedRow .solana CodegenProfileId.solanaSbpfPlanV1 catalogRequests,
    mkImplementedRow .ton CodegenProfileId.tonTolkBocV1 withoutSync
  ]

/-- Frozen product seed as `CompileResult`. Binders surface seed errors first —
    never panic or empty success. -/
def initialStaticRequirementSupportIndexV1Result :
    CompileResult StaticRequirementSupportIndexV1 := do
  let rows ← initialSupportRowsResult
  createStaticRequirementSupportIndexV1 rows

private def findRow
    (index : StaticRequirementSupportIndexV1)
    (targetId : TargetId) (profile : CodegenProfileId) :
    Option StaticRequirementSupportRowV1 :=
  index.rows.find? (fun r => r.targetId == targetId && r.codegenProfile == profile)

/-- DI: full rows over an arbitrary seed Result (seed error first). -/
def supportRowsWithSeedV1
    (seed : CompileResult StaticRequirementSupportIndexV1) :
    CompileResult (Array StaticRequirementSupportRowV1) := do
  let index ← seed
  pure index.toArray

/-- Product full rows — binds frozen seed. -/
def productSupportRowsV1 : CompileResult (Array StaticRequirementSupportRowV1) :=
  supportRowsWithSeedV1 initialStaticRequirementSupportIndexV1Result

/-- DI inspection: lookup support for a (target, profile) without minting capability. -/
def inspectSupportWithSeedV1
    (seed : CompileResult StaticRequirementSupportIndexV1)
    (targetId : TargetId) (codegenProfile : CodegenProfileId) :
    CompileResult RequirementResolutionInspectionV1 := do
  let index ← seed
  match findRow index targetId codegenProfile with
  | none =>
      throw <| .unsupportedRequirementV1
        s!"no exact engineering support for target '{targetId}' profile '{codegenProfile}'"
  | some row =>
      pure {
        targetId := row.targetId
        codegenProfile := row.codegenProfile
        kind := row.kind
        supported := row.supported
      }

/-- Product support inspection for a resolved selection (rows only). -/
def inspectSupportForSelectionV1 (selection : ResolvedBuildSelectionV1) :
    CompileResult RequirementResolutionInspectionV1 :=
  inspectSupportWithSeedV1 initialStaticRequirementSupportIndexV1Result
    selection.targetId selection.codegenProfile

/-- Exact S2 request identities (ids in wire order) for a selection, for
    describe-target product text. Still requires a successful support match. -/
def supportedS2RequestIdsForSelectionV1 (selection : ResolvedBuildSelectionV1) :
    CompileResult (Array String) := do
  let insp ← inspectSupportForSelectionV1 selection
  pure (insp.supported.map (·.id))

/-- Supported S2 ids for an implemented registration default profile (describe). -/
def supportedS2RequestIdsForRegistrationV1 (reg : TargetRegistrationDataV1) :
    CompileResult (Array String) := do
  unless reg.implemented do
    throw <| .registryInvalid
      "supportedS2RequestIdsForRegistrationV1 requires an implemented registration"
  let profile ← match reg.defaultProfile with
    | some p => pure p
    | none =>
        throw <| .registryInvalid
          s!"implemented target '{reg.targetId}' is missing a registered default profile"
  let insp ← inspectSupportWithSeedV1 initialStaticRequirementSupportIndexV1Result
    reg.targetId profile
  pure (insp.supported.map (·.id))

/-- Count request rows by id. -/
private def countReqIds (items : Array RequirementRequestV1) (want : String) : Nat :=
  items.foldl (fun n r => if r.id == want then n + 1 else n) 0

private def requestSupportedExact
    (supported : Array RequirementRequestV1) (req : RequirementRequestV1) : Bool :=
  supported.any (fun s =>
    s.id == req.id && s.version == req.version && s.digest == req.digest &&
      s.predicates.isEmpty && req.predicates.isEmpty)

/-- Resolve requested V1 requirements against a support row (inspection only;
    never mints a materialization capability). Empty request set succeeds here
    so zero-request matrices can be unit-tested without product mint. Product
    sole mint always feeds retained SemanticProgramV1 requirements instead.
    Phase order after uniqueness:
    1. strictly ascending request ids (SPEC/S2 wire order) → `PF-REQ-UNSUPPORTED`;
    2. N5 wire-owned ContextRead/Commit exact rows accepted without support matrix;
    3. per-row known S2 catalog id → `PF-REQ-UNSUPPORTED` (before predicates);
    4. empty predicates only → `PF-REQ-PRECONDITION` for nonempty (known S2 only);
    5. version / digest / exact support row match → `PF-REQ-UNSUPPORTED`.
    Duplicate request id → `PF-REQ-UNSUPPORTED`. No predicate implication. -/
def inspectResolveRequestsV1
    (supported : Array RequirementRequestV1)
    (requested : ProgramRequirementsV1) :
    CompileResult Unit := do
  let items := requested.items
  -- Duplicate request ids first (stable product diagnostic).
  for item in items do
    unless countReqIds items item.id == 1 do
      throw <| .unsupportedRequirementV1
        s!"duplicate requirement request id '{item.id}'"
  -- Canonical request wire order (strictly ascending ids). Public arbitrary
  -- request matrices are only legal on this inspection seam (and
  -- `inspectResolveWithSeedV1`); product mint never accepts caller overrides.
  let ids := items.map (·.id)
  unless isStrictlyAscendingAscii ids do
    throw <| .unsupportedRequirementV1
      "requirement requests must be in SPEC wire order (strictly ascending ids)"
  for item in items do
    -- N5: wire-owned ContextRead/Commit exact rows are structure-gate binders
    -- (domains `pf.context-read-requirement.v1` / `pf.commit-requirement.v1`),
    -- not S2 engineering catalog members. Accept the exact mint only; do not
    -- require target support-matrix membership. Other non-S2 ids still fail.
    if item.id == unixTimeSecondsContextRequirementIdV1 ||
        item.id == callerContextRequirementIdV1 ||
        item.id == commitmentDisclosureRequirementIdV1 then
      let expected ←
        if item.id == unixTimeSecondsContextRequirementIdV1 then
          match unixTimeSecondsContextRequirementV1 with
          | .ok r => pure r
          | .error e =>
              throw <| .unsupportedRequirementV1
                s!"ContextRead unix-time requirement row unavailable: {e}"
        else if item.id == callerContextRequirementIdV1 then
          match callerContextRequirementV1 with
          | .ok r => pure r
          | .error e =>
              throw <| .unsupportedRequirementV1
                s!"ContextRead caller requirement row unavailable: {e}"
        else
          match commitmentDisclosureRequirementV1 with
          | .ok r => pure r
          | .error e =>
              throw <| .unsupportedRequirementV1
                s!"Commit requirement row unavailable: {e}"
      unless item == expected do
        throw <| .unsupportedRequirementV1
          s!"requirement '{item.id}' is not the exact wire-owned row"
      pure ()
    else do
      -- Known S2 catalog membership before predicates so non-catalog + nonempty
      -- predicates report PF-REQ-UNSUPPORTED (unknown class), not PRECONDITION.
      unless isS2CatalogIdV1 item.id do
        throw <| .unsupportedRequirementV1
          s!"unknown requirement id '{item.id}'"
      unless item.predicates.isEmpty do
        throw <| .requirementPrecondition
          s!"requirement '{item.id}' predicates must be empty (no implication)"
      unless item.version == s2RequirementVersionV1 do
        throw <| .unsupportedRequirementV1
          s!"requirement '{item.id}' version is not supported"
      let expectedDigest ← match engineeringRequirementDigestV1 item.id with
        | .ok d => pure d
        | .error e =>
            throw <| .unsupportedRequirementV1
              s!"requirement '{item.id}' digest unavailable: {e}"
      unless item.digest == expectedDigest do
        throw <| .unsupportedRequirementV1
          s!"requirement '{item.id}' digest is not supported"
      unless requestSupportedExact supported item do
        throw <| .unsupportedRequirementV1
          s!"no exact engineering support for requirement '{item.id}'"
  pure ()

/-- DI request-resolution inspection over a seed + selection identity.
    Returns inspection on success; never a capability. -/
def inspectResolveWithSeedV1
    (seed : CompileResult StaticRequirementSupportIndexV1)
    (targetId : TargetId) (codegenProfile : CodegenProfileId)
    (requested : ProgramRequirementsV1) :
    CompileResult RequirementResolutionInspectionV1 := do
  let insp ← inspectSupportWithSeedV1 seed targetId codegenProfile
  inspectResolveRequestsV1 insp.supported requested
  pure insp

end ProofForgeV2.Targets.RequirementResolverV1

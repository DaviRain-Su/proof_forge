/-
  Engineering-only exact static requirement support index / inspection
  (D3/S5 vertical).

  **Not** SupportClaim, formal resolver, ResolvedSupportDecision,
  BuildIdentity, formal registry root digest, claimDigest, predicate implication,
  or OutputSetV1.

  Static rows cover exactly the implemented (targetId, codegenProfile) pairs
  from the frozen TargetRegistry membership table, in canonical (targetId,
  profile) ASCII order. Each row supports a per-target subset of the
  S2 seven RequirementRequestV1 keys in wire order:
    effect.asynchronous-workflow, effect.event, effect.synchronous-call,
    failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic
  with SemVer 1.0.0, engineeringRequirementDigestV1, and empty predicates only.
  Capability gates (call keys): EVM (both profiles) and CosmWasm advertise
  both call keys plus `extension.pf-assets`; NEAR advertises both (sync is
  spelled by the pf.assets deposit/transferAsync half binding; generic sync
  stays Plan fail closed); Noir (both profiles) advertises all seven as a
  witness-binding relation. The sole Solana profile `solana-sbpf-cpi-elf-v1`
  (legacy profiles deleted, #125) advertises exact `effect.synchronous-call`
  plus the ADR-0028 extension and pf.assets, and still declines async.
  Psy/Quint advertise sync only; TON/ICP advertise async only; Aleo,
  Soroban, OpenVM and XRPL decline both call keys.

  Extension rows are **not** S2 catalog members. A closed advertise table maps
  each extension wire id to admitted (target, profile) pairs:
    * `extension.solana-cpi-accounts` → (solana, solana-sbpf-cpi-elf-v1)
      (ADR-0028 / #125)
    * `extension.pf-assets` → (quint, quint-source-u64-model-v1)
      (ADR-0029 Phase A)
    * `extension.pf-assets` → (evm, evm-yul-solc-0.8.34-cancun-v1) and
      (evm, evm-yul-solc-0.8.34-v1) (ADR-0029 Phase B2 native deposit/transfer)
    * `extension.pf-assets` → (solana, solana-sbpf-cpi-elf-v1)
      (ADR-0029 Phase B1 Solana vault-PDA + System CPI binding)
    * `extension.pf-assets` → (near, near-wasm-raw-u64-v1)
      (ADR-0029 Phase C2 NEAR deposit + transferAsync half binding)
    * `extension.pf-assets` → (cosmwasm, cosmwasm-wasm-u64-v1)
      (ADR-0029 Phase C1 bank funds / BankMsg::Send sync native binding)
  ADR-0029 Phase A5/B1/B2/C1/C2: Quint, all EVM profiles, Solana CPI, NEAR
  and CosmWasm advertise exact `extension.pf-assets` **and**
  `effect.synchronous-call` (sync pf.assets native deposit/transfer; NEAR
  binds deposit + transferAsync only, sync transfer permanently fail closed).
  Non-catalog QNs and async/token pf.assets QNs still fail closed at
  Plan/lowering; async workflow remains declined on Quint (EVM keeps
  schedule as fire-and-forget same-tx; Solana CPI declines async; CosmWasm
  keeps CW-4 async SubMsg schedule + C1 sync bank transfer).

  Product seed is `CompileResult` — no panic / Inhabited / empty success fallback.
  Dependency-injected seams return index rows or
  `RequirementResolutionInspectionV1` only — never a materialization capability.
-/
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.CallBindV1
import ProofForgeV2.Targets.TargetRegistryV1

namespace ProofForgeV2.Targets.RequirementResolverV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.CallBindV1
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

/-- B-CALL-SEM family-split tag (COMP-0 / COMP-1-CALL-SEM-LAND).

    Resolver `effect.synchronous-call` / `effect.asynchronous-workflow` support
    keys are **not** this string and are **not** a claim that cross-platform
    call is complete. Product `inspect` may surface the tag; engineering
    `SupportClaim` digest / requirement id lists do **not** include it.
    Deployment-address binding is a later ADR (`docs/plan/evm-call-addr-gap.md`).
    Address-shaped residuals use `callScheduleResidualV1` (inspect-only). -/
def callScheduleFamilyTagV1 : TargetKind → String
  | .evm => "evm-hashed-call+same-tx-schedule"
  | .solana => "solana-cpi-sync-async-fc"
  | .near => "near-promise+pfassets-sync-scope"
  | .cosmwasm => "cw-submsg+pfassets-sync-scope"
  | .noir => "noir-witness-binding"
  | .ton => "ton-async-out-message"
  | .icp => "icp-async-advertise-plan-fc"
  | .psy => "psy-void-sync-async-fc"
  | .quint => "quint-pfassets-sync-async-fc"
  | .aleo => "aleo-dual-fc"
  | .soroban => "soroban-dual-fc"
  | .openvm => "openvm-dual-fc"
  | .xrpl => "xrpl-dual-fc"

/-- Address-shaped residual tags for the three B-CALL-SEM gaps that still
    need an owner ADR (COMP-1-CALL-SEM-LAND inspect residual).

    Target-level `inspect <target>` always reports this table: there is no
    program on that surface. Program-level clear lives in
    `programCallScheduleResidualV1` (build only).
    `none` means this kind has no address-shaped residual on the inspect
    surface (the family tag already covers dual-FC / witness / promise etc.).
    Tags are inspect-only: they do **not** enter SupportClaim digest,
    requirement id lists, or `describeImplementedJoin` three lines.
    They do **not** implement binding. -/
def callScheduleResidualV1 : TargetKind → Option String
  | .evm => some "hashed-qn-no-deploy-bind"
  | .solana => some "callee-identity-outer-account-open"
  | .cosmwasm => some "contract-addr-qn-stub"
  | _ => none

/-- ADR-0053: `pf.crypto.*` / `pf.assets` never consult the bind table. -/
private def isCallBindExemptQnV1 (qn : String) : Bool :=
  qn.startsWith "pf.crypto." || qn.startsWith "pf.assets."

private def dottedCallBindQnV1 (name : Core.Common.QualifiedName) : String :=
  String.intercalate "." name.components.toArray.toList

private def isSolanaSystemTransferQnV1
    (name : Core.Common.QualifiedName) : Bool :=
  name.components.toArray == #["solana", "system", "transfer"]

/-- Generic `call`/`schedule` callees that the bind table must cover. -/
private def collectGenericCallBindCalleesV1
    (kind : TargetKind) (data : SemanticProgramDataV1) :
    Array Core.Common.QualifiedName := Id.run do
  let mut out : Array Core.Common.QualifiedName := #[]
  for callable in data.callables do
    for blk in callable.blocks do
      for instr in blk.instructions do
        match instr.op with
        | .externalCall _ callee _ | .schedule _ callee _ =>
            unless isCallBindExemptQnV1 (dottedCallBindQnV1 callee) ||
                (kind == .solana && isSolanaSystemTransferQnV1 callee) do
              out := out.push callee
        | _ => pure ()
  pure out

/-- Wave 3 is a synchronous outer AccountInfo join. Solana schedules remain
    rejected by the product CPI rail and cannot clear that residual. -/
private def hasGenericSolanaScheduleV1 (data : SemanticProgramDataV1) : Bool :=
  data.callables.any fun callable =>
    callable.blocks.any fun blk =>
      blk.instructions.any fun instr =>
        match instr.op with
        | .schedule _ callee _ =>
            !isCallBindExemptQnV1 (dottedCallBindQnV1 callee) &&
              !isSolanaSystemTransferQnV1 callee
        | _ => false

private def rowCoversGenericCalleeV1
    (kind : TargetKind) (table : CallBindTableV1)
    (callee : Core.Common.QualifiedName) :
    Bool :=
  let comps := callee.components.toArray
  match kind with
  | .evm =>
      match requireEvmAddressV1 table comps with
      | .ok _ => true
      | .error _ => false
  | .solana =>
      match requireSolanaProgramIdV1 table comps with
      | .ok _ => true
      | .error _ => false
  | .cosmwasm =>
      match requireCosmWasmAddressV1 table comps with
      | .ok _ => true
      | .error _ => false
  | _ => false

private def solanaRowsCloseOuterJoinV1
    (table : CallBindTableV1)
    (callees : Array Core.Common.QualifiedName) : Bool := Id.run do
  let mut firstQn : Option String := none
  for callee in callees do
    let qn := dottedCallBindQnV1 callee
    match firstQn with
    | none => firstQn := some qn
    | some first =>
        unless qn == first do return false
    match requireSolanaOuterAccountJoinV1 table callee.components.toArray with
    | .ok _ => pure ()
    | .error _ => return false
  return !callees.isEmpty

/-- Program-level address residual (build surface).

    * No generic `call`/`schedule` → `none` (nothing to bind).
    * Present table covering every generic QN:
      - evm / cosmwasm → `none` (hashed QN / contract_addr stub closed);
      - solana state-bearing, synchronous, one-callee nonempty
        identity-distinct rows → `none` (Wave 3 exact outer AccountInfo join);
        empty-state/scheduled/empty-row/multi-callee programs keep the residual.
    * Missing table or uncovered QN → target-level `callScheduleResidualV1`.
    Does **not** change target `inspect`. Does **not** enter SupportClaim. -/
def programCallScheduleResidualV1
    (kind : TargetKind)
    (program : SemanticProgramV1)
    (bindings : Option CallBindTableV1) :
    Except String (Option String) := do
  let data ← match validateSemanticProgramV1 program with
    | .ok d => pure d
    | .error _ =>
        throw "call-bind: compiled semantic failed structure validation"
  let callees := collectGenericCallBindCalleesV1 kind data
  if callees.isEmpty then
    pure none
  else
    match bindings with
    | none => pure (callScheduleResidualV1 kind)
    | some table =>
        let mut covered := true
        for callee in callees do
          unless rowCoversGenericCalleeV1 kind table callee do
            covered := false
        if covered then
          match kind with
          | .solana =>
              if !data.logicalState.isEmpty &&
                  !hasGenericSolanaScheduleV1 data &&
                  solanaRowsCloseOuterJoinV1 table callees then
                pure none
              else
                pure (some "callee-identity-outer-account-open")
          | _ => pure none
        else
          pure (callScheduleResidualV1 kind)

/-- SYS-S4 `context.attachedValue` family-split tag (COMP-1-SYS-CAP-L2 honesty).

    Resolver `context.attached-value` support is **not** this string and is
    **not** a claim that every callable kind can read attached value.
    Product `inspect` may surface the tag; engineering `SupportClaim` digest /
    requirement id lists do **not** include it. Official-program L2 catalog
    honesty uses `cryptoCatalogFamilyTagV1`. Callable-kind residuals use
    `attachedValueResidualV1` (inspect-only). -/
def attachedValueFamilyTagV1 : TargetKind → String
  | .evm => "evm-callvalue+view-reads-zero"
  | .near => "near-attached-deposit-entry-view-fc"
  | .cosmwasm => "cw-funds-execute-query-fc"
  | .solana => "solana-no-host-fc"
  | .noir => "noir-no-host-fc"
  | .ton => "ton-no-host-fc"
  | .icp => "icp-no-host-fc"
  | .psy => "psy-no-host-fc"
  | .quint => "quint-no-host-fc"
  | .aleo => "aleo-no-host-fc"
  | .soroban => "soroban-no-host-fc"
  | .openvm => "openvm-no-host-fc"
  | .xrpl => "xrpl-no-host-fc"

/-- Callable-kind residual tags for SYS-S4 attachedValue (inspect-only).

    `none` means this kind has no extra callable residual on the inspect
    surface (the family tag already covers no-host named FC).
    Tags do **not** enter SupportClaim digest, requirement id lists, or
    `describeImplementedJoin`. They do **not** open a host. -/
def attachedValueResidualV1 : TargetKind → Option String
  | .evm => some "constructor-fc"
  | .near => some "view-purefn-fc"
  | .cosmwasm => some "query-view-fc"
  | _ => none

/-- Official `pf.crypto.*` catalog family-split tag (COMP-1-SYS-CAP-L2).

    Host-backed QNs already shipped (sha256 / keccak256 / sha256Bytes /
    merkleVerifyKeccak256 / ecdsaRecoverSecp256k1) are listed; missing host
    is named fail-closed. Product `inspect` may surface the tag; engineering
    `SupportClaim` digest / requirement id lists do **not** include it.
    Tags do **not** open a new official-program leaf. Residuals use
    `cryptoCatalogResidualV1` (inspect-only). -/
def cryptoCatalogFamilyTagV1 : TargetKind → String
  | .evm => "sha256+keccak+sha256Bytes+merkle+ecdsa"
  | .solana => "sha256+keccak+sha256Bytes"
  | .near => "sha256+keccak+sha256Bytes"
  | .ton => "sha256+sha256Bytes"
  | .soroban => "sha256+sha256Bytes"
  | .psy => "keccak-gadget-sha256-fc"
  | .noir => "crypto-no-host-fc"
  | .aleo => "crypto-no-host-fc"
  | .quint => "crypto-no-host-fc"
  | .cosmwasm => "crypto-no-host-fc"
  | .openvm => "crypto-no-host-fc"
  | .icp => "crypto-no-host-fc"
  | .xrpl => "crypto-no-host-fc"

/-- Official-program residual tags for keep-FC crypto hosts (inspect-only).

    `none` means the family tag already covers the catalog (admitted set or
    generic no-host). Tags do **not** enter SupportClaim digest, requirement
    id lists, or `describeImplementedJoin`. They do **not** open a host. -/
def cryptoCatalogResidualV1 : TargetKind → Option String
  | .cosmwasm => some "no-sha256-host"
  | .xrpl => some "sha512-half-not-sha256"
  | .psy => some "keccak-gadget-not-sha2"
  | _ => none

/-- Inspect-only residual when Finalize `deployable` can be true while the
    static engineering validation label stays `source-only`.

    Does **not** change `expectedEngineeringValidationLabelOfKindV1` /
    SupportClaim / `describeImplementedJoin`. `none` means the engineering
    label and deployable already agree for the shipped default (or deployable
    is unconditionally false). -/
def engineeringValidationResidualV1 : TargetKind → Option String
  | .icp => some "deployable-wasm-vs-source-only-label"
  | .ton => some "conditional-boc-deployable-vs-source-only-label"
  | _ => none

/-- Non-capability inspection of a support match or request resolution outcome.
    Dependency-injected seams may return this — never a materialize capability. -/
structure RequirementResolutionInspectionV1 where
  targetId : TargetId
  codegenProfile : CodegenProfileId
  kind : TargetKind
  supported : Array RequirementRequestV1
  deriving BEq

private def containsString : List String → String → Bool
  | [], _ => false
  | value :: rest, wanted => value == wanted || containsString rest wanted

private def findDuplicateStringLoop : List String → List String → Option String
  | [], _ => none
  | value :: rest, seen =>
      if containsString seen value then
        some value
      else
        findDuplicateStringLoop rest (value :: seen)

private def findDuplicateString (values : Array String) : Option String :=
  findDuplicateStringLoop values.toList []

/-- Canonical row key for uniqueness / order: `targetId\tcodegenProfile`. -/
private def rowKey (row : StaticRequirementSupportRowV1) : String :=
  s!"{row.targetId.toString}\t{row.codegenProfile.toString}"

private def isStrictlyAscendingAsciiList : List String → Bool
  | [] | [_] => true
  | left :: right :: rest =>
      left < right && isStrictlyAscendingAsciiList (right :: rest)

private def isStrictlyAscendingAscii (values : Array String) : Bool :=
  isStrictlyAscendingAsciiList values.toList

private def buildS2CatalogRequests :
    List String → CompileResult (List RequirementRequestV1)
  | [] => .ok []
  | id :: rest => do
      let request ← match mkS2RequirementRequestV1 id with
        | .ok value => pure value
        | .error error =>
            throw <| .registryInvalid
              s!"engineering S2 request seed failed: {error}"
      let requests ← buildS2CatalogRequests rest
      pure (request :: requests)

private def s2CatalogRequests : CompileResult (Array RequirementRequestV1) := do
  let items ← buildS2CatalogRequests s2CatalogIdsWireOrderV1.toList
  pure items.toArray

/-- Closed (extension wire id → admitted target+profile + exact seed) table.
    One extension id may admit multiple (target, profile) rows (ADR-0029:
    Quint + all EVM profiles + Solana CPI + NEAR + CosmWasm for
    `extension.pf-assets`). Solana CPI remains ADR-0028 profile-scoped.
    Any other (target, profile) advertising an
    extension row fails closed at index construction. -/
private structure ExtensionAdvertisePermitV1 where
  rowId : String
  targetId : TargetId
  profile : CodegenProfileId
  expected : RequirementRequestV1

private def closedExtensionAdvertiseTableV1 :
    CompileResult (Array ExtensionAdvertisePermitV1) := do
  let solanaExt ← match solanaCpiAccountsExtensionRequirementV1 with
    | .ok row => pure row
    | .error e =>
        throw <| .registryInvalid
          s!"Solana CPI extension requirement seed failed: {e}"
  let pfAssets ← match pfAssetsExtensionRequirementV1 with
    | .ok row => pure row
    | .error e =>
        throw <| .registryInvalid
          s!"pf.assets extension requirement seed failed: {e}"
  pure #[
    { rowId := solanaCpiAccountsExtensionRequirementIdV1
      targetId := TargetId.solana
      profile := CodegenProfileId.solanaSbpfCpiElfV1
      expected := solanaExt },
    { rowId := pfAssetsExtensionRequirementIdV1
      targetId := TargetId.quint
      profile := CodegenProfileId.quintSourceU64ModelV1
      expected := pfAssets },
    -- ADR-0029 Phase B2: all EVM profiles advertise exact extension.pf-assets
    -- (same capability set; hardfork is Finalize/runtime pin only).
    { rowId := pfAssetsExtensionRequirementIdV1
      targetId := TargetId.evm
      profile := CodegenProfileId.evmYulSolc0834CancunV1
      expected := pfAssets },
    { rowId := pfAssetsExtensionRequirementIdV1
      targetId := TargetId.evm
      profile := CodegenProfileId.evmYulSolc0834V1
      expected := pfAssets },
    -- ADR-0029 Phase B1: Solana CPI product profile also advertises pf.assets.
    { rowId := pfAssetsExtensionRequirementIdV1
      targetId := TargetId.solana
      profile := CodegenProfileId.solanaSbpfCpiElfV1
      expected := pfAssets },
    -- ADR-0029 Phase C2: NEAR advertises pf.assets (native deposit +
    -- transferAsync half binding; sync transfer permanently fail closed).
    { rowId := pfAssetsExtensionRequirementIdV1
      targetId := TargetId.near
      profile := CodegenProfileId.nearWasmRawU64V1
      expected := pfAssets },
    -- ADR-0029 Phase C1: CosmWasm bank native deposit/transfer.
    { rowId := pfAssetsExtensionRequirementIdV1
      targetId := TargetId.cosmwasm
      profile := CodegenProfileId.cosmwasmWasmU64V1
      expected := pfAssets }
  ]

private def hasExtensionOwnerV1
    (targetId : TargetId) (profile : CodegenProfileId) :
    List ExtensionAdvertisePermitV1 → Bool
  | [] => false
  | permit :: rest =>
      (permit.targetId == targetId && permit.profile == profile) ||
        hasExtensionOwnerV1 targetId profile rest

private def exactRequirementRequestEqV1
    (left right : RequirementRequestV1) : Bool :=
  decide (left.id = right.id) &&
    decide (left.version = right.version) &&
    decide (left.digest = right.digest) &&
    left.predicates == right.predicates

private def validateSupportedRequestItem
    (label : String) (targetId : TargetId) (profile : CodegenProfileId)
    (permits : List ExtensionAdvertisePermitV1)
    (item : RequirementRequestV1) : CompileResult Unit := do
  let matching := permits.filter (·.rowId == item.id)
  if matching.isEmpty then
    unless isS2CatalogIdV1 item.id do
      throw <| .registryInvalid
        s!"support row '{label}' unknown requirement id '{item.id}'"
    unless item.version == s2RequirementVersionV1 do
      throw <| .registryInvalid
        s!"support row '{label}' requirement '{item.id}' version must be 1.0.0"
    let expectedDigest ← match engineeringRequirementDigestV1 item.id with
      | .ok digest => pure digest
      | .error error =>
          throw <| .registryInvalid
            s!"support row '{label}' requirement '{item.id}' digest unavailable: {error}"
    unless item.digest == expectedDigest do
      throw <| .registryInvalid
        s!"support row '{label}' requirement '{item.id}' digest mismatch"
    unless item.predicates.isEmpty do
      throw <| .registryInvalid
        s!"support row '{label}' requirement '{item.id}' must have empty predicates"
  else
    unless hasExtensionOwnerV1 targetId profile matching do
      throw <| .registryInvalid
        s!"support row '{label}' cannot advertise extension '{item.id}'"
    -- All permits for a given rowId share the exact seed.
    let some permit := matching.head? |
      throw <| .registryInvalid
        s!"support row '{label}' extension '{item.id}' permit table empty"
    unless exactRequirementRequestEqV1 item permit.expected do
      throw <| .registryInvalid
        s!"support row '{label}' extension '{item.id}' row mismatch"

private def validateSupportedRequestItems
    (label : String) (targetId : TargetId) (profile : CodegenProfileId)
    (permits : List ExtensionAdvertisePermitV1) :
    List RequirementRequestV1 → CompileResult Unit
  | [] => .ok ()
  | item :: rest => do
      validateSupportedRequestItem label targetId profile permits item
      validateSupportedRequestItems label targetId profile permits rest

private def validateOwnedExtensionPermits
    (label : String) (targetId : TargetId) (profile : CodegenProfileId)
    (ids : List String) : List ExtensionAdvertisePermitV1 → CompileResult Unit
  | [] => .ok ()
  | permit :: rest => do
      if targetId == permit.targetId && profile == permit.profile then
        unless containsString ids permit.rowId do
          throw <| .registryInvalid
            s!"support row '{label}' must carry the exact extension '{permit.rowId}'"
      validateOwnedExtensionPermits label targetId profile ids rest

/-- Validate one supported-requirements array: unique ids, exact S2
    catalog rows (any subset — per-target capability gates), plus closed
    extension advertise rows from `closedExtensionAdvertiseTableV1`
    (ADR-0028 Solana CPI profile; ADR-0029 Phase A Quint pf.assets).
    All rows use strict ASCII id order and empty predicates. -/
private def validateSupportedRequests
    (label : String) (targetId : TargetId) (profile : CodegenProfileId)
    (supported : Array RequirementRequestV1) : CompileResult Unit := do
  let ids := supported.map (·.id)
  if let some dup := findDuplicateString ids then
    throw <| .registryDuplicate
      s!"duplicate requirement id '{dup}' in support row '{label}'"
  unless isStrictlyAscendingAscii ids do
    throw <| .registryInvalid
      s!"support requirements for '{label}' must be in SPEC wire order"
  let permits ← closedExtensionAdvertiseTableV1
  validateSupportedRequestItems label targetId profile permits.toList
    supported.toList
  -- Each permit that owns this (target, profile) must be present exactly
  -- (seed content already checked above when present).
  validateOwnedExtensionPermits label targetId profile ids.toList permits.toList

/-- Implemented (targetId, profile, kind) triple carrier (avoids nested Prod). -/
private structure ImplementedPairV1 where
  targetId : TargetId
  codegenProfile : CodegenProfileId
  kind : TargetKind

private def implementedPairsForProfiles
    (reg : TargetRegistrationDataV1) :
    List CodegenProfileId → List ImplementedPairV1
  | [] => []
  | profile :: rest =>
      {
        targetId := reg.targetId
        codegenProfile := profile
        kind := reg.kind
      } :: implementedPairsForProfiles reg rest

private def collectImplementedPairs :
    List TargetRegistrationDataV1 → List ImplementedPairV1
  | [] => []
  | reg :: rest =>
      let tail := collectImplementedPairs rest
      if reg.implemented then
        implementedPairsForProfiles reg reg.profiles.toList ++ tail
      else
        tail

/-- Exact implemented (target,profile) pairs from frozen TargetRegistryV1, in
    canonical (targetId, codegenProfile) ASCII order. -/
private def expectedImplementedPairs
    (regs : Array TargetRegistrationDataV1) :
    CompileResult (Array ImplementedPairV1) := do
  let pairs := collectImplementedPairs regs.toList
  let keys := pairs.map (fun t => s!"{t.targetId.toString}\t{t.codegenProfile.toString}")
  unless isStrictlyAscendingAsciiList keys do
    throw <| .registryInvalid
      "implemented build-selection pairs are not in canonical (target,profile) order"
  pure pairs.toArray

private def validateSupportRowsAgainstExpected
    (index : Nat) :
    List StaticRequirementSupportRowV1 → List ImplementedPairV1 →
      CompileResult Unit
  | [], [] => .ok ()
  | row :: rows, expected :: expecteds => do
      unless row.targetId == expected.targetId do
        throw <| .registryInvalid
          s!"support row {index} targetId diverges from implemented pair '{expected.targetId}'"
      unless row.codegenProfile == expected.codegenProfile do
        throw <| .registryInvalid
          s!"support row {index} profile diverges from implemented pair '{expected.codegenProfile}'"
      unless row.kind == expected.kind do
        throw <| .registryInvalid
          s!"support row {index} kind diverges from implemented pair '{expected.kind}'"
      unless row.kind.toString == row.targetId.toString do
        throw <| .registryInvalid
          s!"support row '{rowKey row}' kind does not match targetId"
      validateSupportedRequests (rowKey row) row.targetId row.codegenProfile
        row.supported
      validateSupportRowsAgainstExpected (index + 1) rows expecteds
  | _, _ =>
      throw <| .registryInvalid "support row index out of range"

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
  validateSupportRowsAgainstExpected 0 rows.toList expected.toList
  pure (StaticRequirementSupportIndexV1.mk rows)

/-- Replay the ordered phases of the sole support-index validator and retain
    its private-constructor result. This theorem does not replace any runtime
    check; it lets frozen-index certificates prove each phase separately. -/
private theorem createStaticRequirementSupportIndexV1_eq_ok_of_stages
    (rows : Array StaticRequirementSupportRowV1)
    (registrations : Array TargetRegistrationDataV1)
    (expected : Array ImplementedPairV1)
    (hnonempty : rows.isEmpty = false)
    (hunique : findDuplicateString (rows.map rowKey) = none)
    (hordered : isStrictlyAscendingAscii (rows.map rowKey) = true)
    (hregistrations : productRegistrations = .ok registrations)
    (hexpected : expectedImplementedPairs registrations = .ok expected)
    (hsize : rows.size = expected.size)
    (hrows : validateSupportRowsAgainstExpected 0 rows.toList expected.toList =
      .ok ()) :
    createStaticRequirementSupportIndexV1 rows =
      .ok (StaticRequirementSupportIndexV1.mk rows) := by
  simp only [createStaticRequirementSupportIndexV1, hnonempty, Bool.false_eq_true,
    ↓reduceIte, hunique, hordered, hregistrations, hexpected, hsize,
    hrows, Bind.bind, Pure.pure, Except.bind, Except.pure]
  simp

@[reducible] def mkImplementedRow
    (kind : TargetKind) (profile : CodegenProfileId)
    (supported : Array RequirementRequestV1) : StaticRequirementSupportRowV1 :=
  {
    targetId := TargetId.ofKind kind
    codegenProfile := profile
    kind
    supported
  }

@[reducible] def filterRequirementRequestsList
    (keep : RequirementRequestV1 → Bool) :
    List RequirementRequestV1 → List RequirementRequestV1
  | [] => []
  | request :: rest =>
      if keep request then
        request :: filterRequirementRequestsList keep rest
      else
        filterRequirementRequestsList keep rest

@[reducible] def filterRequirementRequests
    (requests : Array RequirementRequestV1)
    (keep : RequirementRequestV1 → Bool) : Array RequirementRequestV1 :=
  (filterRequirementRequestsList keep requests.toList).toArray

@[reducible] def insertRequirementRequestV1
    (request : RequirementRequestV1) :
    List RequirementRequestV1 → List RequirementRequestV1
  | [] => [request]
  | current :: rest =>
      if request.id < current.id then
        request :: current :: rest
      else
        current :: insertRequirementRequestV1 request rest

@[reducible] def sortRequirementRequestsListV1 :
    List RequirementRequestV1 → List RequirementRequestV1
  | [] => []
  | request :: rest =>
      insertRequirementRequestV1 request (sortRequirementRequestsListV1 rest)

@[reducible] def sortRequirementRequestsV1
    (requests : Array RequirementRequestV1) : Array RequirementRequestV1 :=
  (sortRequirementRequestsListV1 requests.toList).toArray

/-- Shipped seventeen-row seed body (canonical targetId order: aleo, cosmwasm,
    evm×2, icp, near, noir×2, openvm×2, psy, quint, solana, soroban, ton, xrpl×2). Aleo
    and Psy each expose one direct target IR profile. OpenVM (both
    `openvm-guest-elf-v1` ADR-0046 and `openvm-guest-source-v1` ADR-0045) admits
    exactly `state.persistent`, `failure.atomic-rollback`, `value.bool`, and
    `value.checked-arithmetic`; it declines every `effect.*` key
    and `extension.pf-assets` — the controlled Rust guest source/build
    surface has no call/schedule/ContextRead/Commit/event surface; the elf
    profile only adds a Finalize-time cargo-openvm build/transpile, not a new
    requirement id. EVM carries both
    `evm-yul-solc-0.8.34-cancun-v1` and `evm-yul-solc-0.8.34-v1`
    (ASCII ascending; default is v1). Solana is sole
    `solana-sbpf-cpi-elf-v1` (ADR-0032 U1). The opt-in CPI profile (#125)
    admits exact `effect.synchronous-call` plus the exact ADR-0028 extension and
    still declines `effect.asynchronous-workflow`.

    **ADR-0029 Phase A5/B1/B2 extension advertise**: closed table (see
    `closedExtensionAdvertiseTableV1`) — Quint `quint-source-u64-model-v1`,
    all EVM profiles and Solana `solana-sbpf-cpi-elf-v1` advertise exact
    `extension.pf-assets`. Quint keeps the Q0 four S2 keys plus sync-call
    (vault-modeled native deposit/transfer only; non-catalog / async / token
    QNs fail closed at Plan/lowering). EVM keeps the full seven S2 keys plus
    the extension (native deposit/transfer materialization; async/token QNs
    fail closed at Plan/lowering). Solana CPI keeps sync+ADR-0028 extension
    and adds pf.assets (vault-PDA System CPI). All other targets/profiles fail
    closed if they advertise either extension row.

    Capability gates are per target: EVM admits both call keys via static
    QualifiedName callees (AddressBearing: wire Op.ExternalCall/Schedule take
    compile-time QN, not a dynamic address ValueId — no Principal→20B/32B map).
    EVM `schedule` is a **fire-and-forget same-transaction** interpretation:
    the dispatch executes synchronously (`CALL`) and the outcome is discarded,
    matching the Reference no-response-cursor contract — never a
    cross-transaction deferral claim (same admission discipline as the CW-4
    SubMsg note below). EVM result-bearing sync calls read `RETURNDATA` as one
    UInt64 word behind a size/range guard (BL-28; wider result types stay fail
    closed; the callee address is a keccak-of-QN stub pending deployment
    wiring). NEAR advertises `effect.synchronous-call` only for the pf.assets
    catalog (deposit + `transferAsync`); generic non-catalog sync stays Plan
    fail closed (Promise is async). `effect.asynchronous-workflow` stays for
    schedule. Noir admits both call keys as a **witness-binding relation** (B-CALL-SEM
    honesty, 2026-08-04 review): call/schedule args become public-input slots
    asserted equal to the computed values, and the outcome is a `callStatus`
    witness — the circuit executes **no** external call and the proof does
    **not** attest that any on-chain call happened; a caller-side executor must
    perform the call and supply the response. Result-bearing calls (N-CALL-RET)
    stay fail closed pending a response-witness contract. Aleo declines both
    call families (no static-callee Plan open) and `effect.event` (canonical
    Aleo Instructions expose no admitted event operation). Psy DPN supports
    void sync calls and events as PARTIAL operations:
    `InvokeExternalContractFunctionSync` has static-QN hashes, zero outputs,
    and no deployment/response/runtime binding; `DPNEventRecord` has no ordered
    event runtime gate. Psy declines `effect.asynchronous-workflow` because no
    deferred DPN operation is admitted, so schedule fails closed.
    CosmWasm declined both call families at MVP: its `WasmMsg::Execute` is a
    same-transaction submessage with a savepoint, **not** an EVM-style
    synchronous CALL, and SubMsg fire-and-forget is **not** a cross-transaction
    async workflow — aliasing either would overclaim the platform semantics
    (B-CALL-SEM discipline). Its `effect.event` maps to Response attributes.
    CW-4 follow-up: `effect.asynchronous-workflow` is now admitted — schedule
    lowers to `SubMsg{reply_on:never, id:0, WasmMsg::Execute}` (no reply
    channel, same-tx savepoint dispatch; submessage failure aborts the whole
    transaction per wasmd `DispatchSubmessages`; `contract_addr` is a static QN
    stub pending deployment wiring — never a cross-tx async claim). TON is a
    pure-async actor chain: cross-contract interaction exists only as async
    internal messages, so `effect.synchronous-call` is declined outright while
    `effect.asynchronous-workflow` maps to raw async out-messages (bounce and
    value/gas attachment are materializer concerns, never a hidden sync
    fallback). Its `effect.event` maps to external out-messages. ICP
    (ADR-0047) is likewise a pure-async Wasm actor: sync call and portable
    `effect.event` are declined; `effect.asynchronous-workflow` is advertised
    for inter-canister continuations while concrete Plan shapes may still fail
    closed. Message-local rollback must not be read as cross-await transaction
    atomicity. -/
def buildInitialSupportRowsV1
    (catalogRequests : Array RequirementRequestV1)
    (solanaExtensionRow : RequirementRequestV1)
    (pfAssetsRow : RequirementRequestV1) :
    Array StaticRequirementSupportRowV1 :=
  -- Capability filters reference closed S2 id spellings from RequirementIdsV1
  -- (not bare literals). s2CatalogIdsWireOrderV1 stays RequirementsV1 public.
  let withoutSync := filterRequirementRequests catalogRequests fun r =>
    r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectSyncCallIdV1
  -- ADR-0047: ICP declines sync call and portable emit; keeps async workflow.
  let icpRequests := filterRequirementRequests withoutSync fun r =>
    r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectEventIdV1
  let aleoRequests := filterRequirementRequests catalogRequests fun r =>
    r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectEventIdV1 &&
      r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectAsyncWorkflowIdV1 &&
      r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectSyncCallIdV1
  -- Psy DPN supports PARTIAL void sync calls
  -- (`InvokeExternalContractFunctionSync`) and `DPNEventRecord` events, but
  -- has no admitted deferred operation. Schedule remains fail closed and
  -- effect.asynchronous-workflow is declined (never alias sync semantics).
  let psyRequests := filterRequirementRequests catalogRequests fun r =>
    r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectAsyncWorkflowIdV1
  -- CosmWasm MVP+CW-4+C1:
  -- * async admitted via SubMsg reply_on=never (same-tx dispatch, whole-tx
  --   abort on submessage failure — not cross-tx async).
  -- * sync re-opened for ADR-0029 Phase C1 pf.assets native deposit/transfer
  --   only (BankMsg::Send error-propagating SubMsg + info.funds exact check).
  --   Non-catalog sync call stays Plan fail closed; token/async QNs FC.
  let cosmwasmRequests :=
    sortRequirementRequestsV1 (catalogRequests.push pfAssetsRow)
  -- Quint Q0 is an executable state-model projection, not a deployment target.
  -- It models persistent state, Bool, checked arithmetic, explicit rollback,
  -- and (ADR-0029 Phase A5) sync pf.assets native vault ops. Event/async
  -- workflow stay fail closed on the S2 matrix; non-catalog / async / token
  -- QNs fail closed at Quint Plan/lowering.
  let quintBaseRequests := filterRequirementRequests catalogRequests fun r =>
    r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectEventIdV1 &&
      r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectAsyncWorkflowIdV1
  -- #125: exact CPI profile admits sync call + extension; still excludes async.
  let withoutAsync := filterRequirementRequests catalogRequests fun r =>
    r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectAsyncWorkflowIdV1
  -- #125 + ADR-0029 B1: CPI profile = S2 sans async + solana.cpi.accounts + pf.assets.
  let solanaCpiRequests :=
    sortRequirementRequestsV1
      ((withoutAsync.push solanaExtensionRow).push pfAssetsRow)
  -- Phase A5: exact extension.pf-assets + effect.synchronous-call on Quint.
  let quintRequests :=
    sortRequirementRequestsV1 (quintBaseRequests.push pfAssetsRow)
  -- ADR-0044 Soroban S0: honest 4-key only (rollback/state/bool/checked-arith).
  -- Event/sync/async/pf.assets stay declined until auth-tree/TTL Plan fields exist.
  let sorobanRequests := filterRequirementRequests catalogRequests fun r =>
    r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectEventIdV1 &&
      r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectAsyncWorkflowIdV1 &&
      r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectSyncCallIdV1
  -- Phase B2: all EVM profiles carry full S2 seven keys + exact extension.pf-assets.
  let evmRequests :=
    sortRequirementRequestsV1 (catalogRequests.push pfAssetsRow)
  -- ADR-0029 Phase C2: NEAR advertises exact extension.pf-assets plus
  -- effect.synchronous-call. The sync-call key covers only the pf.assets
  -- catalog (native deposit via attached_deposit exact check and
  -- fire-and-forget transferAsync Promise); generic non-catalog sync calls
  -- remain fail closed at Plan/lowering, and sync transfer is permanently
  -- refused (Promise is async). effect.asynchronous-workflow stays for
  -- schedule.
  let nearRequests :=
    sortRequirementRequestsV1 (catalogRequests.push pfAssetsRow)
  -- ADR-0045 OpenVM O0: admit only state.persistent, failure.atomic-rollback,
  -- value.bool, value.checked-arithmetic. Decline all effect.* and
  -- extension.pf-assets — no call/schedule/ContextRead/Commit/events on the
  -- O0 controlled Rust guest source template.
  let openvmRequests := filterRequirementRequests catalogRequests fun r =>
    r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectEventIdV1 &&
      r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectAsyncWorkflowIdV1 &&
      r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectSyncCallIdV1
  -- ADR-0049 XRPL Q0: honest 4-key only (rollback/state/bool/checked-arith).
  -- Event/sync/async/pf.assets stay declined until ContractCall/emit Plan
  -- fields exist. Not Hooks, not EVM sidechain, not AlphaNet deployable.
  let xrplRequests := filterRequirementRequests catalogRequests fun r =>
    r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectEventIdV1 &&
      r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectAsyncWorkflowIdV1 &&
      r.id != ProofForgeV2.Core.RequirementIdsV1.s2EffectSyncCallIdV1
  #[
    mkImplementedRow .aleo CodegenProfileId.aleoInstructionsV1 aleoRequests,
    mkImplementedRow .cosmwasm CodegenProfileId.cosmwasmWasmU64V1 cosmwasmRequests,
    -- AddressBearing: full seven keys — static QN call/schedule Plan open.
    -- EVM profiles share the same S2+extension capability set; hardfork /
    -- Map-storage layout are Finalize/runtime pins, not requirement-gate diffs.
    -- ASCII ascending: cancun-v1 < v1.
    mkImplementedRow .evm CodegenProfileId.evmYulSolc0834CancunV1 evmRequests,
    mkImplementedRow .evm CodegenProfileId.evmYulSolc0834V1 evmRequests,
    mkImplementedRow .icp CodegenProfileId.icpWasmCandidU64V1 icpRequests,
    mkImplementedRow .near CodegenProfileId.nearWasmRawU64V1 nearRequests,
    -- Noir dual profiles share the exact S2 catalog set; ACIR dual-write is a
    -- Finalize/profile selection (NOIR-IR-6), not a new requirement id.
    -- ASCII ascending: nargo-acir < source-relations.
    mkImplementedRow .noir CodegenProfileId.noirNargoAcirV1 catalogRequests,
    mkImplementedRow .noir CodegenProfileId.noirSourceU64RelationsV1 catalogRequests,
    -- OpenVM dual profiles share the exact S2 catalog subset; the elf profile's
    -- cargo-openvm build/transpile is a Finalize/profile selection (ADR-0046),
    -- not a new requirement id. ASCII ascending: guest-elf < guest-source.
    mkImplementedRow .openvm CodegenProfileId.openvmGuestElfV1 openvmRequests,
    mkImplementedRow .openvm CodegenProfileId.openvmGuestSourceV1 openvmRequests,
    mkImplementedRow .psy CodegenProfileId.psyDpnV1 psyRequests,
    mkImplementedRow .quint CodegenProfileId.quintSourceU64ModelV1 quintRequests,
    -- ADR-0032 U1: sole Solana product profile (shims plan/elf removed).
    mkImplementedRow .solana CodegenProfileId.solanaSbpfCpiElfV1 solanaCpiRequests,
    -- ADR-0044: sole Soroban S0 source-only profile (ASCII: soroban < ton).
    mkImplementedRow .soroban CodegenProfileId.sorobanSourceU64V1 sorobanRequests,
    mkImplementedRow .ton CodegenProfileId.tonTolkBocV1 withoutSync,
    -- ADR-0049/0050: XRPL dual profiles share the exact 4-key subset; the
    -- WASM profile's ambient rustc build is a Finalize/profile selection,
    -- not a new requirement id. ASCII ascending: source-u64 < wasm-u64.
    mkImplementedRow .xrpl CodegenProfileId.xrplBedrockSourceU64V1 xrplRequests,
    mkImplementedRow .xrpl CodegenProfileId.xrplBedrockWasmU64V1 xrplRequests
  ]

private def initialSupportRowsResult :
    CompileResult (Array StaticRequirementSupportRowV1) := do
  let catalogRequests ← s2CatalogRequests
  let solanaExtensionRow ← match solanaCpiAccountsExtensionRequirementV1 with
    | .ok row => pure row
    | .error error =>
        throw <| .registryInvalid
          s!"Solana CPI extension requirement seed failed: {error}"
  let pfAssetsRow ← match pfAssetsExtensionRequirementV1 with
    | .ok row => pure row
    | .error error =>
        throw <| .registryInvalid
          s!"pf.assets extension requirement seed failed: {error}"
  pure (buildInitialSupportRowsV1 catalogRequests solanaExtensionRow pfAssetsRow)

private theorem exceptToOptionGetSuccessV1 {ε α : Type}
    (result : Except ε α) (success : result.toOption.isSome = true) :
    result = .ok (result.toOption.get success) := by
  cases result with
  | error _ => simp [Except.toOption] at success
  | ok _ => rfl

@[reducible] def initialS2RequestV1
    (id : String) (digestBytes : ByteArray) : RequirementRequestV1 :=
  {
    id
    version := s2RequirementVersionV1
    digest := { algorithm := .sha256, bytes := digestBytes }
    predicates := #[]
  }

/-- Exact transparent witness produced by the closed S2 request constructor.
    Digest bytes are referenced from the sole RequirementsV1 definitions, not
    copied into this certificate. -/
@[reducible] def initialS2CatalogRequestsV1 : Array RequirementRequestV1 := #[
  initialS2RequestV1 ProofForgeV2.Core.RequirementIdsV1.s2EffectAsyncWorkflowIdV1
    s2EffectAsyncWorkflowDigestBytesV1,
  initialS2RequestV1 ProofForgeV2.Core.RequirementIdsV1.s2EffectEventIdV1
    s2EffectEventDigestBytesV1,
  initialS2RequestV1 ProofForgeV2.Core.RequirementIdsV1.s2EffectSyncCallIdV1
    s2EffectSyncCallDigestBytesV1,
  initialS2RequestV1 ProofForgeV2.Core.RequirementIdsV1.s2FailureAtomicRollbackIdV1
    s2FailureAtomicRollbackDigestBytesV1,
  initialS2RequestV1 ProofForgeV2.Core.RequirementIdsV1.s2StatePersistentIdV1
    s2StatePersistentDigestBytesV1,
  initialS2RequestV1 ProofForgeV2.Core.RequirementIdsV1.s2ValueBoolIdV1
    s2ValueBoolDigestBytesV1,
  initialS2RequestV1 ProofForgeV2.Core.RequirementIdsV1.s2ValueCheckedArithmeticIdV1
    s2ValueCheckedArithmeticDigestBytesV1
]

private theorem initialS2CatalogRequestsSuccessV1 :
    s2CatalogRequests = .ok initialS2CatalogRequestsV1 := by
  rfl

private theorem solanaCpiExtensionDigestSomeV1 :
    (ProofForgeV2.Core.Common.parseDigest
      ProofForgeV2.Core.RequirementIdsV1.solanaCpiAccountsExtensionDigestV1).toOption.isSome =
      true := by
  simp [ProofForgeV2.Core.RequirementIdsV1.solanaCpiAccountsExtensionDigestV1,
    ProofForgeV2.Core.Common.parseDigest]
  decide

private def initialSolanaCpiExtensionDigestV1 :
    ProofForgeV2.Core.Common.Digest :=
  (ProofForgeV2.Core.Common.parseDigest
    ProofForgeV2.Core.RequirementIdsV1.solanaCpiAccountsExtensionDigestV1).toOption.get
      solanaCpiExtensionDigestSomeV1

private theorem solanaCpiExtensionDigestSuccessV1 :
    ProofForgeV2.Core.Common.parseDigest
      ProofForgeV2.Core.RequirementIdsV1.solanaCpiAccountsExtensionDigestV1 =
      .ok initialSolanaCpiExtensionDigestV1 :=
  exceptToOptionGetSuccessV1 _ solanaCpiExtensionDigestSomeV1

@[reducible] def initialSolanaCpiExtensionRequirementV1 : RequirementRequestV1 := {
  id := solanaCpiAccountsExtensionRequirementIdV1
  version := ProofForgeV2.Core.Common.s2CatalogSemVerCoreV1
  digest := initialSolanaCpiExtensionDigestV1
  predicates := #[]
}

private theorem solanaCpiExtensionRequirementSuccessV1 :
    solanaCpiAccountsExtensionRequirementV1 =
      .ok initialSolanaCpiExtensionRequirementV1 := by
  simp only [solanaCpiAccountsExtensionRequirementV1,
    ProofForgeV2.Core.RequirementIdsV1.solanaCpiAccountsExtensionVersionV1,
    ProofForgeV2.Core.Common.parseSemVer_1_0_0,
    solanaCpiExtensionDigestSuccessV1, Bind.bind, Except.bind,
    initialSolanaCpiExtensionRequirementV1, Pure.pure, Except.pure]

private theorem pfAssetsExtensionDigestSomeV1 :
    (ProofForgeV2.Core.Common.parseDigest
      ProofForgeV2.Core.RequirementIdsV1.pfAssetsExtensionDigestV1_1).toOption.isSome =
      true := by
  simp [
    ProofForgeV2.Core.RequirementIdsV1.pfAssetsExtensionDigestV1_1,
    ProofForgeV2.Core.Common.parseDigest]
  decide

private def initialPfAssetsExtensionDigestV1 :
    ProofForgeV2.Core.Common.Digest :=
  (ProofForgeV2.Core.Common.parseDigest
    ProofForgeV2.Core.RequirementIdsV1.pfAssetsExtensionDigestV1_1).toOption.get
      pfAssetsExtensionDigestSomeV1

private theorem pfAssetsExtensionDigestSuccessV1 :
    ProofForgeV2.Core.Common.parseDigest
      ProofForgeV2.Core.RequirementIdsV1.pfAssetsExtensionDigestV1_1 =
      .ok initialPfAssetsExtensionDigestV1 :=
  exceptToOptionGetSuccessV1 _ pfAssetsExtensionDigestSomeV1

@[reducible] def initialPfAssetsExtensionRequirementV1 : RequirementRequestV1 := {
  id := pfAssetsExtensionRequirementIdV1
  version := { major := 1, minor := 1, patch := 0 }
  digest := initialPfAssetsExtensionDigestV1
  predicates := #[]
}

private theorem pfAssetsExtensionRequirementSuccessV1 :
    pfAssetsExtensionRequirementV1 = .ok initialPfAssetsExtensionRequirementV1 := by
  simp only [pfAssetsExtensionRequirementV1, pfAssetsExtensionRequirementV1_1,
    ProofForgeV2.Core.RequirementIdsV1.pfAssetsExtensionVersionV1_1,
    ProofForgeV2.Core.Common.parseSemVer_1_1_0,
    pfAssetsExtensionDigestSuccessV1, Bind.bind, Except.bind,
    initialPfAssetsExtensionRequirementV1, Pure.pure, Except.pure]

/-- Frozen support-row source data consumed by the sole validated static index.
    Public for downstream claim/capability certificates; this is not a resolved
    build capability and cannot bypass `createStaticRequirementSupportIndexV1`. -/
def initialSupportRowsV1 : Array StaticRequirementSupportRowV1 :=
  buildInitialSupportRowsV1 initialS2CatalogRequestsV1
    initialSolanaCpiExtensionRequirementV1 initialPfAssetsExtensionRequirementV1

/-- Frozen Solana production-profile support source row. This is a projection
    of the sole validated index seed, not a resolved capability. -/
def initialSolanaSupportRowV1 : StaticRequirementSupportRowV1 :=
  initialSupportRowsV1[12]'(by
    unfold initialSupportRowsV1 buildInitialSupportRowsV1
    decide)

/-- Exact frozen Solana support contents in canonical request-wire order.
    Downstream certificates consume this proposition instead of unfolding the
    index seed or copying requirement/digest bytes. -/
theorem initialSolanaSupportRowV1_supported_eq :
    initialSolanaSupportRowV1.supported = #[
      initialS2RequestV1
        ProofForgeV2.Core.RequirementIdsV1.s2EffectEventIdV1
        s2EffectEventDigestBytesV1,
      initialS2RequestV1
        ProofForgeV2.Core.RequirementIdsV1.s2EffectSyncCallIdV1
        s2EffectSyncCallDigestBytesV1,
      initialPfAssetsExtensionRequirementV1,
      initialSolanaCpiExtensionRequirementV1,
      initialS2RequestV1
        ProofForgeV2.Core.RequirementIdsV1.s2FailureAtomicRollbackIdV1
        s2FailureAtomicRollbackDigestBytesV1,
      initialS2RequestV1
        ProofForgeV2.Core.RequirementIdsV1.s2StatePersistentIdV1
        s2StatePersistentDigestBytesV1,
      initialS2RequestV1
        ProofForgeV2.Core.RequirementIdsV1.s2ValueBoolIdV1
        s2ValueBoolDigestBytesV1,
      initialS2RequestV1
        ProofForgeV2.Core.RequirementIdsV1.s2ValueCheckedArithmeticIdV1
        s2ValueCheckedArithmeticDigestBytesV1
    ] := by
  rfl

/-- The exact frozen Solana support array passes the same derived BEq used by
    the production claim/index join. Kept at the seed owner so private parsed
    extension-digest witnesses do not need to be exposed downstream. -/
theorem initialSolanaSupportRowV1_supported_beq_self :
    (initialSolanaSupportRowV1.supported ==
      initialSolanaSupportRowV1.supported) = true := by
  letI : ReflBEq RequirementPredicateV1 := {
    rfl := by
      intro predicate
      cases predicate <;>
        change instBEqRequirementPredicateV1.beq _ _ = true <;>
        simp [instBEqRequirementPredicateV1.beq]
  }
  letI : ReflBEq RequirementRequestV1 := {
    rfl := by
      intro request
      cases request
      change instBEqRequirementRequestV1.beq _ _ = true
      simp [instBEqRequirementRequestV1.beq]
  }
  exact Array.isEqv_self_beq initialSolanaSupportRowV1.supported

private theorem initialSupportRowsSuccessV1 :
    initialSupportRowsResult = .ok initialSupportRowsV1 := by
  simp only [initialSupportRowsResult, initialS2CatalogRequestsSuccessV1,
    solanaCpiExtensionRequirementSuccessV1,
    pfAssetsExtensionRequirementSuccessV1, Bind.bind, Pure.pure, Except.bind,
    Except.pure, initialSupportRowsV1]

/-- Frozen product seed as `CompileResult`. Binders surface seed errors first —
    never panic or empty success. -/
def initialStaticRequirementSupportIndexV1Result :
    CompileResult StaticRequirementSupportIndexV1 := do
  let rows ← initialSupportRowsResult
  createStaticRequirementSupportIndexV1 rows

private def initialExpectedImplementedPairsV1 : Array ImplementedPairV1 :=
  (collectImplementedPairs initialCanonicalRegistrationRowsV1.toList).toArray

private theorem productRegistrationsV1_eq_canonical :
    productRegistrations = .ok initialCanonicalRegistrationRowsV1 := by
  simp only [productRegistrations, registrationsWithSeedV1,
    initialTargetRegistryV1Result_eq_canonical, Bind.bind, Except.bind,
    TargetRegistryV1.registrationsOf, Pure.pure, Except.pure]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem initialExpectedImplementedPairsSuccessV1 :
    expectedImplementedPairs initialCanonicalRegistrationRowsV1 =
      .ok initialExpectedImplementedPairsV1 := by
  unfold expectedImplementedPairs
  have hordered : isStrictlyAscendingAsciiList
      ((collectImplementedPairs initialCanonicalRegistrationRowsV1.toList).map
        (fun item =>
          s!"{item.targetId.toString}\t{item.codegenProfile.toString}")) = true := by
    unfold initialCanonicalRegistrationRowsV1 aleoRegistrationRowV1
      cosmwasmRegistrationRowV1 evmRegistrationRowV1 icpRegistrationRowV1
      nearRegistrationRowV1 noirRegistrationRowV1 openvmRegistrationRowV1
      psyRegistrationRowV1 quintRegistrationRowV1 solanaRegistrationRowV1
      sorobanRegistrationRowV1 tonRegistrationRowV1 xrplRegistrationRowV1
      registrationRowV1
    decide
  simp only [hordered, ↓reduceIte, Pure.pure, Except.pure,
    initialExpectedImplementedPairsV1]
  rfl

private theorem exceptUnitSuccessV1 {ε : Type}
    (result : Except ε Unit) (success : result.toOption.isSome = true) :
    result = .ok () := by
  simpa using exceptToOptionGetSuccessV1 result success

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem initialSupportRowsResult_unique :
    (match initialSupportRowsResult with
      | .error _ => false
      | .ok rows => (findDuplicateString (rows.map rowKey)).isNone) = true := by
  unfold initialSupportRowsResult
  rw [initialS2CatalogRequestsSuccessV1,
    solanaCpiExtensionRequirementSuccessV1,
    pfAssetsExtensionRequirementSuccessV1]
  dsimp only [Bind.bind, Except.bind, Pure.pure, Except.pure]
  unfold buildInitialSupportRowsV1 mkImplementedRow rowKey
  simp (config := { zeta := true }) <;> decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem initialSupportRowsV1_nonempty :
    initialSupportRowsV1.isEmpty = false := by
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem initialSupportRowsV1_unique :
    findDuplicateString (initialSupportRowsV1.map rowKey) = none := by
  have success := initialSupportRowsResult_unique
  rw [initialSupportRowsSuccessV1] at success
  cases duplicate : findDuplicateString (initialSupportRowsV1.map rowKey) with
  | none => rfl
  | some _ => simp [duplicate] at success

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem initialSupportRowsResult_ordered :
    (match initialSupportRowsResult with
      | .error _ => false
      | .ok rows => isStrictlyAscendingAscii (rows.map rowKey)) = true := by
  unfold initialSupportRowsResult
  rw [initialS2CatalogRequestsSuccessV1,
    solanaCpiExtensionRequirementSuccessV1,
    pfAssetsExtensionRequirementSuccessV1]
  dsimp only [Bind.bind, Except.bind, Pure.pure, Except.pure]
  unfold buildInitialSupportRowsV1 mkImplementedRow rowKey
  simp (config := { zeta := true }) <;> decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem initialSupportRowsV1_ordered :
    isStrictlyAscendingAscii (initialSupportRowsV1.map rowKey) = true := by
  have success := initialSupportRowsResult_ordered
  rw [initialSupportRowsSuccessV1] at success
  exact success

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem initialSupportRowsV1_size :
    initialSupportRowsV1.size = initialExpectedImplementedPairsV1.size := by
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem initialSupportRowsResult_valid :
    (match initialSupportRowsResult with
      | .error _ => false
      | .ok rows =>
          (validateSupportRowsAgainstExpected 0 rows.toList
            initialExpectedImplementedPairsV1.toList).toOption.isSome) = true := by
  unfold initialExpectedImplementedPairsV1 initialCanonicalRegistrationRowsV1
    aleoRegistrationRowV1 cosmwasmRegistrationRowV1 evmRegistrationRowV1
    icpRegistrationRowV1 nearRegistrationRowV1 noirRegistrationRowV1
    openvmRegistrationRowV1 psyRegistrationRowV1 quintRegistrationRowV1
    solanaRegistrationRowV1 sorobanRegistrationRowV1 tonRegistrationRowV1
    xrplRegistrationRowV1 registrationRowV1
  unfold initialSupportRowsResult
  rw [initialS2CatalogRequestsSuccessV1,
    solanaCpiExtensionRequirementSuccessV1,
    pfAssetsExtensionRequirementSuccessV1]
  dsimp only [Bind.bind, Except.bind, Pure.pure, Except.pure]
  unfold buildInitialSupportRowsV1
  simp (config := { zeta := true }) [mkImplementedRow,
    filterRequirementRequests, filterRequirementRequestsList,
    sortRequirementRequestsV1, sortRequirementRequestsListV1,
    insertRequirementRequestV1, initialS2CatalogRequestsV1,
    initialS2RequestV1, initialSolanaCpiExtensionRequirementV1,
    initialPfAssetsExtensionRequirementV1, validateSupportRowsAgainstExpected,
    validateSupportedRequests, validateSupportedRequestItems,
    validateSupportedRequestItem, validateOwnedExtensionPermits,
    closedExtensionAdvertiseTableV1, hasExtensionOwnerV1,
    exactRequirementRequestEqV1,
    solanaCpiExtensionRequirementSuccessV1,
    pfAssetsExtensionRequirementSuccessV1, findDuplicateString,
    findDuplicateStringLoop, containsString, isStrictlyAscendingAscii,
    isStrictlyAscendingAsciiList, rowKey, collectImplementedPairs,
    implementedPairsForProfiles,
    ProofForgeV2.Core.RequirementIdsV1.s2EffectAsyncWorkflowIdV1,
    ProofForgeV2.Core.RequirementIdsV1.s2EffectEventIdV1,
    ProofForgeV2.Core.RequirementIdsV1.s2EffectSyncCallIdV1,
    ProofForgeV2.Core.RequirementIdsV1.s2FailureAtomicRollbackIdV1,
    ProofForgeV2.Core.RequirementIdsV1.s2StatePersistentIdV1,
    ProofForgeV2.Core.RequirementIdsV1.s2ValueBoolIdV1,
    ProofForgeV2.Core.RequirementIdsV1.s2ValueCheckedArithmeticIdV1,
    solanaCpiAccountsExtensionRequirementIdV1,
    pfAssetsExtensionRequirementIdV1,
    ProofForgeV2.Core.RequirementIdsV1.wireExtensionSolanaCpiAccountsIdV1,
    ProofForgeV2.Core.RequirementIdsV1.wireExtensionPfAssetsIdV1,
    expectedImplementedOfKindV1, TargetId.beq_eq_toString, TargetId.ofKind,
    TargetId.toString, TargetId.aleo, TargetId.cosmwasm, TargetId.evm,
    TargetId.icp, TargetId.near, TargetId.noir, TargetId.openvm, TargetId.psy,
    TargetId.quint, TargetId.solana, TargetId.soroban, TargetId.ton,
    TargetId.xrpl, CodegenProfileId.beq_eq_toString,
    CodegenProfileId.toString, CodegenProfileId.aleoInstructionsV1,
    CodegenProfileId.cosmwasmWasmU64V1,
    CodegenProfileId.evmYulSolc0834CancunV1,
    CodegenProfileId.evmYulSolc0834V1,
    CodegenProfileId.icpWasmCandidU64V1,
    CodegenProfileId.nearWasmRawU64V1, CodegenProfileId.noirNargoAcirV1,
    CodegenProfileId.noirSourceU64RelationsV1,
    CodegenProfileId.openvmGuestElfV1, CodegenProfileId.openvmGuestSourceV1,
    CodegenProfileId.psyDpnV1, CodegenProfileId.quintSourceU64ModelV1,
    CodegenProfileId.solanaSbpfCpiElfV1,
    CodegenProfileId.sorobanSourceU64V1, CodegenProfileId.tonTolkBocV1,
    CodegenProfileId.xrplBedrockSourceU64V1,
    CodegenProfileId.xrplBedrockWasmU64V1, s2RequirementVersionV1] <;> decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem initialSupportRowsV1_valid :
    validateSupportRowsAgainstExpected 0 initialSupportRowsV1.toList
      initialExpectedImplementedPairsV1.toList = .ok () := by
  apply exceptUnitSuccessV1
  have success := initialSupportRowsResult_valid
  rw [initialSupportRowsSuccessV1] at success
  exact success

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
/-- Exact frozen-index equation for downstream kernel replay. The value remains
    the result of the sole production validator/private mint; this proposition
    does not introduce a second static index constructor path. -/
theorem initialStaticRequirementSupportIndexV1Result_eq_ok :
    initialStaticRequirementSupportIndexV1Result =
      .ok (StaticRequirementSupportIndexV1.mk initialSupportRowsV1) := by
  unfold initialStaticRequirementSupportIndexV1Result
  rw [initialSupportRowsSuccessV1]
  dsimp only [Bind.bind, Except.bind]
  exact createStaticRequirementSupportIndexV1_eq_ok_of_stages
    initialSupportRowsV1 initialCanonicalRegistrationRowsV1
    initialExpectedImplementedPairsV1 initialSupportRowsV1_nonempty
    initialSupportRowsV1_unique initialSupportRowsV1_ordered
    productRegistrationsV1_eq_canonical initialExpectedImplementedPairsSuccessV1
    initialSupportRowsV1_size initialSupportRowsV1_valid

/-- The frozen engineering support index succeeds through the sole production
    validator and private mint. The witness is exposed only propositionally. -/
theorem initialStaticRequirementSupportIndexV1Result_exists :
    ∃ index, initialStaticRequirementSupportIndexV1Result = .ok index := by
  exact ⟨StaticRequirementSupportIndexV1.mk initialSupportRowsV1,
    initialStaticRequirementSupportIndexV1Result_eq_ok⟩

private def findRow
    (index : StaticRequirementSupportIndexV1)
    (targetId : TargetId) (profile : CodegenProfileId) :
    Option StaticRequirementSupportRowV1 :=
  index.rows.find? (fun r => r.targetId == targetId && r.codegenProfile == profile)

private theorem findRow_initial_solana_eq_some :
    findRow (StaticRequirementSupportIndexV1.mk initialSupportRowsV1)
      TargetId.solana CodegenProfileId.solanaSbpfCpiElfV1 =
        some initialSolanaSupportRowV1 := by
  unfold findRow
  rw [Array.find?_eq_some_iff_getElem]
  refine ⟨?_, ⟨12, ?_, ?_, ?_⟩⟩
  · rfl
  · unfold initialSupportRowsV1 buildInitialSupportRowsV1
    decide
  · rfl
  · intro j hj
    have hrowsSize : initialSupportRowsV1.size = 17 := by
      unfold initialSupportRowsV1 buildInitialSupportRowsV1
      rfl
    have hjRows : j < initialSupportRowsV1.size := by
      rw [hrowsSize]
      omega
    have hjCases :
        j = 0 ∨ j = 1 ∨ j = 2 ∨ j = 3 ∨ j = 4 ∨ j = 5 ∨
        j = 6 ∨ j = 7 ∨ j = 8 ∨ j = 9 ∨ j = 10 ∨ j = 11 := by
      omega
    rcases hjCases with rfl | rfl | rfl | rfl | rfl | rfl |
      rfl | rfl | rfl | rfl | rfl | rfl <;>
    unfold initialSupportRowsV1 buildInitialSupportRowsV1
    all_goals rfl

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

/-- The frozen Solana production support row replays through the existing
    support inspection seam. The result is the exact row projected from the
    sole validated static index; this theorem does not mint a capability. -/
theorem inspectSupportWithSeedV1_initial_solana_eq_ok :
    inspectSupportWithSeedV1 initialStaticRequirementSupportIndexV1Result
      TargetId.solana CodegenProfileId.solanaSbpfCpiElfV1 = .ok {
        targetId := initialSolanaSupportRowV1.targetId
        codegenProfile := initialSolanaSupportRowV1.codegenProfile
        kind := initialSolanaSupportRowV1.kind
        supported := initialSolanaSupportRowV1.supported
      } := by
  unfold inspectSupportWithSeedV1
  rw [initialStaticRequirementSupportIndexV1Result_eq_ok]
  simp only [Bind.bind, Except.bind, findRow_initial_solana_eq_some,
    Pure.pure, Except.pure]

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
    2. wire-owned ContextRead/Commit exact rows accepted without support matrix;
    3. closed extension rows (Solana CPI / pf.assets) require support-row membership
       (from `closedExtensionAdvertiseTableV1` — profile-scoped advertise);
    4. per-row known S2 catalog id → `PF-REQ-UNSUPPORTED` (before predicates);
    5. empty predicates only → `PF-REQ-PRECONDITION` for nonempty (known S2 only);
    6. version / digest / exact support row match → `PF-REQ-UNSUPPORTED`.
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
  -- Closed extension wire ids (not S2). Membership in the advertise table is
  -- the sole recognition path; exact seed + support-row membership gate accept.
  let extensionPermits ← closedExtensionAdvertiseTableV1
  for item in items do
    -- ContextRead/Commit exact rows are structure-gate binders and remain
    -- target-independent. Closed engineering extension rows are also
    -- wire-owned but accepted only through exact support-row membership, so
    -- non-permitted targets/profiles cannot inherit them.
    if item.id == unixTimeSecondsContextRequirementIdV1 ||
        item.id == callerContextRequirementIdV1 ||
        item.id == blockHeightContextRequirementIdV1 ||
        item.id == chainIdContextRequirementIdV1 ||
        item.id == selfContextRequirementIdV1 ||
        item.id == attachedValueContextRequirementIdV1 ||
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
        else if item.id == blockHeightContextRequirementIdV1 then
          match blockHeightContextRequirementV1 with
          | .ok r => pure r
          | .error e =>
              throw <| .unsupportedRequirementV1
                s!"ContextRead block-height requirement row unavailable: {e}"
        else if item.id == chainIdContextRequirementIdV1 then
          match chainIdContextRequirementV1 with
          | .ok r => pure r
          | .error e =>
              throw <| .unsupportedRequirementV1
                s!"ContextRead chain-id requirement row unavailable: {e}"
        else if item.id == selfContextRequirementIdV1 then
          match selfContextRequirementV1 with
          | .ok r => pure r
          | .error e =>
              throw <| .unsupportedRequirementV1
                s!"ContextRead self requirement row unavailable: {e}"
        else if item.id == attachedValueContextRequirementIdV1 then
          match attachedValueContextRequirementV1 with
          | .ok r => pure r
          | .error e =>
              throw <| .unsupportedRequirementV1
                s!"ContextRead attached-value requirement row unavailable: {e}"
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
    else if let some permit := extensionPermits.find? (·.rowId == item.id) then
      -- pf.assets admits dual exact seeds (1.1.0 default advertise + 1.2.0
      -- full-width U128). Support matrix still carries the 1.1.0 seed; accept
      -- either closed program row when the profile advertises the wire id.
      let exactOk :=
        if item.id == pfAssetsExtensionRequirementIdV1 then
          isExactPfAssetsExtensionRequirementV1 item
        else
          item == permit.expected
      unless exactOk do
        throw <| .unsupportedRequirementV1
          s!"requirement '{item.id}' is not the exact wire-owned extension row"
      let supportOk :=
        if item.id == pfAssetsExtensionRequirementIdV1 then
          -- Profile advertises extension.pf-assets (1.1 seed on support row).
          supported.any (fun s => s.id == item.id) &&
            isExactPfAssetsExtensionRequirementV1 item
        else
          requestSupportedExact supported item
      unless supportOk do
        throw <| .unsupportedRequirementV1
          s!"no exact engineering support for requirement '{item.id}'"
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

/-- Any semantic program retaining exactly the persistent-state, atomic
    rollback, and checked-arithmetic S2 rows crosses the frozen Solana support
    row. The caller proves only its generated requirement items; all resolver
    control flow and support data remain owned and replayed here. -/
theorem inspectResolveRequestsV1_initial_solana_state_checked_eq_ok
    (requested : ProgramRequirementsV1)
    (hitems : requested.items = #[
      initialS2RequestV1
        ProofForgeV2.Core.RequirementIdsV1.s2FailureAtomicRollbackIdV1
        s2FailureAtomicRollbackDigestBytesV1,
      initialS2RequestV1
        ProofForgeV2.Core.RequirementIdsV1.s2StatePersistentIdV1
        s2StatePersistentDigestBytesV1,
      initialS2RequestV1
        ProofForgeV2.Core.RequirementIdsV1.s2ValueCheckedArithmeticIdV1
        s2ValueCheckedArithmeticDigestBytesV1
    ]) :
    inspectResolveRequestsV1 initialSolanaSupportRowV1.supported requested =
      .ok () := by
  cases requested with
  | mk items =>
      change items = _ at hitems
      subst items
      rw [initialSolanaSupportRowV1_supported_eq]
      simp (config := { zeta := true }) [inspectResolveRequestsV1, countReqIds,
        requestSupportedExact, closedExtensionAdvertiseTableV1,
        solanaCpiExtensionRequirementSuccessV1,
        pfAssetsExtensionRequirementSuccessV1, isStrictlyAscendingAscii,
        isStrictlyAscendingAsciiList, initialS2RequestV1,
        initialSolanaCpiExtensionRequirementV1,
        initialPfAssetsExtensionRequirementV1, s2RequirementVersionV1,
        ProofForgeV2.Core.RequirementIdsV1.s2EffectEventIdV1,
        ProofForgeV2.Core.RequirementIdsV1.s2EffectSyncCallIdV1,
        ProofForgeV2.Core.RequirementIdsV1.s2FailureAtomicRollbackIdV1,
        ProofForgeV2.Core.RequirementIdsV1.s2StatePersistentIdV1,
        ProofForgeV2.Core.RequirementIdsV1.s2ValueBoolIdV1,
        ProofForgeV2.Core.RequirementIdsV1.s2ValueCheckedArithmeticIdV1,
        unixTimeSecondsContextRequirementIdV1, callerContextRequirementIdV1,
        blockHeightContextRequirementIdV1, chainIdContextRequirementIdV1,
        selfContextRequirementIdV1, attachedValueContextRequirementIdV1,
        commitmentDisclosureRequirementIdV1,
        solanaCpiAccountsExtensionRequirementIdV1,
        pfAssetsExtensionRequirementIdV1,
        ProofForgeV2.Core.RequirementIdsV1.wireContextUnixTimeSecondsIdV1,
        ProofForgeV2.Core.RequirementIdsV1.wireContextCallerIdV1,
        ProofForgeV2.Core.RequirementIdsV1.wireContextBlockHeightIdV1,
        ProofForgeV2.Core.RequirementIdsV1.wireContextChainIdIdV1,
        ProofForgeV2.Core.RequirementIdsV1.wireContextSelfIdV1,
        ProofForgeV2.Core.RequirementIdsV1.wireContextAttachedValueIdV1,
        ProofForgeV2.Core.RequirementIdsV1.wireCommitmentDisclosureIdV1,
        ProofForgeV2.Core.RequirementIdsV1.wireExtensionSolanaCpiAccountsIdV1,
        ProofForgeV2.Core.RequirementIdsV1.wireExtensionPfAssetsIdV1]
      rfl

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

/-
  ProofForgeV2.Core.RequirementIdsV1 — closed string constants for every
  requirement identity used on the engineering product path.

  Single source of id spellings. Consumers must reference these defs; do not
  reintroduce bare requirement-id string literals in RequirementsV1,
  RequirementsInferV1, RequirementResolverV1, ProvenanceV1, or WireV1.

  ═══════════════════════════════════════════════════════════════════════════
  DIGEST DOMAINS (do not conflate the same id string across domains)
  ═══════════════════════════════════════════════════════════════════════════

  S2 engineering catalog (RequirementsV1 freeze only)
    Domain tag: `pf.requirement-key.engineering.v1`
    Digest: domainSeparatedSha256(domain, UTF-8(id))
    Members: the seven ids in `s2CatalogIdsWireOrderListV1`
    (Array view: `s2CatalogIdsWireOrderV1`).
    Consumers: RequirementsV1 (sole freeze), RequirementResolverV1 (S2 rows),
    ProvenanceV1 (origin attribution for S2 contributions),
    RequirementsInferV1 (may contribute these ids).

  Wire-owned ContextRead binding (WireV1 exact row)
    Domain tag: `pf.context-read-requirement.v1`
    Id: `context.unix-time-seconds` (`wireContextUnixTimeSecondsIdV1`)
    Bound only by `WireV1.unixTimeSecondsContextRequirementV1`.
    Not part of the S2 freeze catalog.

  Wire-owned Commit disclosure binding (WireV1 exact row)
    Domain tag: `pf.commit-requirement.v1`
    Id: `disclosure.commitment` (`wireCommitmentDisclosureIdV1`)
    Bound only by `WireV1.commitmentDisclosureRequirementV1`.
    Not part of the S2 freeze catalog.

  Wire-owned engineering extension bindings (closed table)
    Domain tag: `pf.extension-semantics.v1`
    Digest is the frozen extension JCS domain digest, not a digest of the id.
    Members (`engineeringExtensionIdentitiesV1`):
      * ADR-0028 Solana CPI:
          source `solana.cpi.accounts@1.0.0`
          wire `extension.solana-cpi-accounts`
          (`wireExtensionSolanaCpiAccountsIdV1`)
      * ADR-0029 portable assets:
          source `pf.assets@1.0.0`
          wire `extension.pf-assets`
          (`wireExtensionPfAssetsIdV1`)
    Not part of the S2 freeze catalog and does not advertise target support.
    Recognition mints an exact requirement row only; profile/target admission
    remains RequirementResolver-owned.

  Infer-only contributions (RequirementsInferV1)
    No engineering digest is minted for these ids today. They appear as
    contribution identities from ProgramV1 visibility/type surfaces.
    Members: `inferOnlyRequirementIdsV1`.
    N1/N2b freeze policy (`RequirementsV1.freezeProgramRequirementsV1`):
      * disclosure.private-state / commitment-state / private-witness /
        commitment — **skipped** (not frozen, not rejected); product disclosure
        is sole CheckV1/DisclosureCheck authority.
      * value.field.bn254-fr — **skipped** (N2b; Field arithmetic is exact
        modular and covered by `value.checked-arithmetic`; no new S2 key).

  KNOWN DUAL MEANING — `disclosure.commitment`
    The same UTF-8 id string is carried by:
      * `inferDisclosureCommitmentIdV1` — param-visibility contribution from
        RequirementsInferV1; skipped at S2 freeze (not in catalog).
      * `wireCommitmentDisclosureIdV1` — exact Commit-op requirement row in
        WireV1 under domain `pf.commit-requirement.v1`.
    This is intentional and safe today because the infer contribution never
    enters the S2 engineering digest domain, and the wire row never reuses
    `pf.requirement-key.engineering.v1`. Do NOT unify the two defs into one
    shared constant that blurs the domain boundary; do NOT add
    `disclosure.commitment` to the S2 catalog without a formal CAP decision.
-/

namespace ProofForgeV2.Core.RequirementIdsV1

/-! ### S2 closed catalog ids (domain `pf.requirement-key.engineering.v1`) -/

/-- S2 catalog: async workflow schedule surface. -/
def s2EffectAsyncWorkflowIdV1 : String := "effect.asynchronous-workflow"

/-- S2 catalog: event emit surface. -/
def s2EffectEventIdV1 : String := "effect.event"

/-- S2 catalog: synchronous external call surface. -/
def s2EffectSyncCallIdV1 : String := "effect.synchronous-call"

/-- S2 catalog: atomic rollback / checked failure surface. -/
def s2FailureAtomicRollbackIdV1 : String := "failure.atomic-rollback"

/-- S2 catalog: persistent logical state surface. -/
def s2StatePersistentIdV1 : String := "state.persistent"

/-- S2 catalog: Bool value surface. -/
def s2ValueBoolIdV1 : String := "value.bool"

/-- S2 catalog: checked arithmetic surface. -/
def s2ValueCheckedArithmeticIdV1 : String := "value.checked-arithmetic"

/-- Sole closed S2 catalog ID authority in SPEC wire order (UTF-8 ascending).
    Kernel-reducible `List` so membership certificates reduce by exact `==`
    without a second enumerated if-chain. Exact order is part of the
    engineering freeze contract; do not reorder. -/
def s2CatalogIdsWireOrderListV1 : List String :=
  [s2EffectAsyncWorkflowIdV1, s2EffectEventIdV1, s2EffectSyncCallIdV1,
    s2FailureAtomicRollbackIdV1, s2StatePersistentIdV1, s2ValueBoolIdV1,
    s2ValueCheckedArithmeticIdV1]

/-- Closed S2 catalog IDs as Array (derived from sole list authority). -/
def s2CatalogIdsWireOrderV1 : Array String :=
  s2CatalogIdsWireOrderListV1.toArray

/-! ### Wire-owned requirement ids (non-S2 digest domains) -/

/-- Wire ContextRead exact-row id (domain `pf.context-read-requirement.v1`). -/
def wireContextUnixTimeSecondsIdV1 : String := "context.unix-time-seconds"

/-- Wire ContextRead exact-row id for caller identity (N-2).
    Domain `pf.context-read-requirement.v1`. -/
def wireContextCallerIdV1 : String := "context.caller"

/-- Wire ContextRead exact-row id for block height (ADR-0031 S2).
    Domain `pf.context-read-requirement.v1`. -/
def wireContextBlockHeightIdV1 : String := "context.block-height"

/-- Wire Commit exact-row id (domain `pf.commit-requirement.v1`).
    Same spelling as `inferDisclosureCommitmentIdV1` — dual meaning; see
    module doc. -/
def wireCommitmentDisclosureIdV1 : String := "disclosure.commitment"

/-- Frozen source declaration id for ADR-0028's opt-in Solana CPI extension. -/
def solanaCpiAccountsExtensionSourceIdV1 : String := "solana.cpi.accounts"

/-- Frozen canonical SemVer spelling for the Solana CPI extension declaration. -/
def solanaCpiAccountsExtensionVersionV1 : String := "1.0.0"

/-- Frozen domain-separated digest of the exact Solana CPI extension JCS.
    This is intentionally not derived from the requirement id. -/
def solanaCpiAccountsExtensionDigestV1 : String :=
  "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

/-- Wire exact-row id for the Solana CPI extension declaration
    (domain `pf.extension-semantics.v1`). -/
def wireExtensionSolanaCpiAccountsIdV1 : String :=
  "extension.solana-cpi-accounts"

/-- Frozen source declaration id for ADR-0029's portable `pf.assets` extension. -/
def pfAssetsExtensionSourceIdV1 : String := "pf.assets"

/-- Frozen canonical SemVer spelling for the `pf.assets@1.0.0` extension
    declaration (ADR-0029 Phase A; original five statement QNs). -/
def pfAssetsExtensionVersionV1 : String := "1.0.0"

/-- Frozen domain-separated digest of the exact `pf.assets@1.0.0` extension JCS
    (`SHA-256("pf.extension-semantics.v1" || NUL || extensionJcs)` over
    `docs/specs/pf-assets-extension-v1.json`). Not derived from the wire id. -/
def pfAssetsExtensionDigestV1 : String :=
  "sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed"

/-- Frozen canonical SemVer spelling for the `pf.assets@1.1.0` extension
    declaration (ADR-0030 E2; adds the two env-read balanceOfSelf QNs).
    Additive acceptance: both v1.0.0 and v1.1.0 declarations are accepted by
    Source/Typed; the env-read QNs REQUIRE the 1.1.0 declaration. -/
def pfAssetsExtensionVersionV1_1 : String := "1.1.0"

/-- Frozen domain-separated digest of the exact `pf.assets@1.1.0` extension JCS
    (`SHA-256("pf.extension-semantics.v1" || NUL || extensionJcs)` over
    `docs/specs/pf-assets-extension-v1.1.json`). Not derived from the wire id. -/
def pfAssetsExtensionDigestV1_1 : String :=
  "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

/-- Wire exact-row id for the `pf.assets` extension declaration
    (domain `pf.extension-semantics.v1`). Shared by both accepted versions;
    the wire row carries the declared version/digest. -/
def wireExtensionPfAssetsIdV1 : String := "extension.pf-assets"

/-- Closed chain-neutral catalog QNs for `pf.assets@1.0.0` (ADR-0029).
    Target-neutral table lives here so Frontend/Typed/Semantic never import
    `Targets/`. A2 does not force QN-vs-declaration binding at Normalize;
    catalog-call lowering remains target/profile owned. These five statement
    QNs keep working under EITHER declaration version (E2-2a additive). -/
def pfAssetsCatalogQualifiedNamesV1 : Array String :=
  #["pf.assets.native.deposit", "pf.assets.native.transfer",
    "pf.assets.native.transferAsync", "pf.assets.token.transfer",
    "pf.assets.token.transferAsync"]

/-- Closed chain-neutral env-read catalog QNs for `pf.assets@1.1.0`
    (ADR-0030 E2). These are the first non-Unit catalog members:
    expression-position ONLY, result `UInt64`, effect-free, view-callable.
    They REQUIRE the 1.1.0 declaration; v1.0.0 programs using them fail
    closed. `typedCallReturn` is `env-read-family-only`. -/
def pfAssetsEnvReadQualifiedNamesV1 : Array String :=
  #["pf.assets.native.balanceOfSelf", "pf.assets.token.balanceOfSelf"]

/-- True when the qualified-name string is one of the two env-read catalog
    QNs (ADR-0030 E2). -/
def isPfAssetsEnvReadQnV1 (qn : String) : Bool :=
  pfAssetsEnvReadQualifiedNamesV1.contains qn

/-- The two env-read catalog QNs as distinct family tags for typing/Normalize.
    `native` → `.nativeVaultBalance` (0 args); `token` → `.tokenVaultBalance`
    (1 Principal arg). -/
inductive PfAssetsEnvReadFamilyV1 where
  | nativeBalance
  | tokenBalance
  deriving BEq, Repr, Inhabited

/-- Resolve a qualified-name string to its env-read family tag, if any. -/
def pfAssetsEnvReadFamilyOfV1 (qn : String) : Option PfAssetsEnvReadFamilyV1 :=
  if qn == "pf.assets.native.balanceOfSelf" then some .nativeBalance
  else if qn == "pf.assets.token.balanceOfSelf" then some .tokenBalance
  else none

/-- Expected argument count for an env-read family member. -/
def pfAssetsEnvReadArityV1 (family : PfAssetsEnvReadFamilyV1) : Nat :=
  match family with
  | .nativeBalance => 0
  | .tokenBalance => 1

/-- Closed engineering extension identity: source triple + wire row id. -/
structure EngineeringExtensionIdentityV1 where
  sourceId : String
  version : String
  digest : String
  wireRequirementId : String
  deriving Repr, BEq, Inhabited

/-- Solana CPI extension identity (ADR-0028). -/
def solanaCpiAccountsExtensionIdentityV1 : EngineeringExtensionIdentityV1 :=
  { sourceId := solanaCpiAccountsExtensionSourceIdV1
    version := solanaCpiAccountsExtensionVersionV1
    digest := solanaCpiAccountsExtensionDigestV1
    wireRequirementId := wireExtensionSolanaCpiAccountsIdV1 }

/-- Portable assets extension identity v1.0.0 (ADR-0029 Phase A; original five
    statement QNs). -/
def pfAssetsExtensionIdentityV1 : EngineeringExtensionIdentityV1 :=
  { sourceId := pfAssetsExtensionSourceIdV1
    version := pfAssetsExtensionVersionV1
    digest := pfAssetsExtensionDigestV1
    wireRequirementId := wireExtensionPfAssetsIdV1 }

/-- Portable assets extension identity v1.1.0 (ADR-0030 E2; adds two env-read
    balanceOfSelf QNs). Same wire row id as v1.0.0; the requirement row carries
    the declared version/digest. -/
def pfAssetsExtensionIdentityV1_1 : EngineeringExtensionIdentityV1 :=
  { sourceId := pfAssetsExtensionSourceIdV1
    version := pfAssetsExtensionVersionV1_1
    digest := pfAssetsExtensionDigestV1_1
    wireRequirementId := wireExtensionPfAssetsIdV1 }

/-- Sole closed table of admitted engineering extension identities.
    Order is stable for diagnostics (first-known for expected values); membership
    is exact source-id lookup. Dual distinct ids in one program are legal.
    ADR-0030 E2 cutover: `pf.assets@1.1.0` is the sole accepted pf.assets
    triple (the v1.0.0 declaration fails closed); the wire row id stays
    `extension.pf-assets` and the requirement row carries the 1.1.0
    version/digest. -/
def engineeringExtensionIdentitiesV1 : Array EngineeringExtensionIdentityV1 :=
  #[solanaCpiAccountsExtensionIdentityV1, pfAssetsExtensionIdentityV1_1]

/-- Look up a closed engineering extension by exact source declaration id.
    Returns the first matching identity (stable for diagnostics). When a
    source id has multiple accepted versions, use
    `findExactEngineeringExtensionTripleV1` for triple-precise lookup. -/
def findEngineeringExtensionBySourceIdV1 (sourceId : String) :
    Option EngineeringExtensionIdentityV1 :=
  engineeringExtensionIdentitiesV1.find? (·.sourceId == sourceId)

/-- All admitted identities for a source declaration id (stable order). -/
def engineeringExtensionsBySourceIdV1 (sourceId : String) :
    Array EngineeringExtensionIdentityV1 :=
  engineeringExtensionIdentitiesV1.filter (·.sourceId == sourceId)

/-- Look up a closed engineering extension by exact triple
    `(sourceId, version, digest)`. Returns the identity only when all three
    fields match a closed table row exactly. -/
def findExactEngineeringExtensionTripleV1
    (sourceId version digest : String) :
    Option EngineeringExtensionIdentityV1 :=
  engineeringExtensionIdentitiesV1.find? fun id =>
    id.sourceId == sourceId && id.version == version && id.digest == digest

/-- True when `(sourceId, version, digest)` matches a closed table row exactly. -/
def isExactEngineeringExtensionTripleV1
    (sourceId version digest : String) : Bool :=
  (findExactEngineeringExtensionTripleV1 sourceId version digest).isSome

/-- Wire requirement id for an exact closed extension triple, if any. -/
def wireRequirementIdOfExactExtensionTripleV1
    (sourceId version digest : String) : Option String :=
  match findExactEngineeringExtensionTripleV1 sourceId version digest with
  | some id => some id.wireRequirementId
  | none => none

/-- Closed wire-owned requirement ids (ContextRead + Commit + exact extension
    bindings). Membership here does not imply support by any target/profile. -/
def wireOwnedRequirementIdsV1 : Array String :=
  #[wireContextUnixTimeSecondsIdV1, wireContextCallerIdV1,
    wireContextBlockHeightIdV1,
    wireCommitmentDisclosureIdV1, wireExtensionSolanaCpiAccountsIdV1,
    wireExtensionPfAssetsIdV1]

/-! ### Infer-only contribution ids (S2 freeze rejects; no engineering digest) -/

/-- Infer-only: private param / witness disclosure contribution.
    Skipped at S2 freeze (N1); not cataloged. -/
def inferDisclosurePrivateWitnessIdV1 : String := "disclosure.private-witness"

/-- Infer-only: commitment-visibility param contribution.
    Same spelling as `wireCommitmentDisclosureIdV1` — dual meaning; see
    module doc. Skipped at S2 freeze (N1). -/
def inferDisclosureCommitmentIdV1 : String := "disclosure.commitment"

/-- Infer-only: private state disclosure contribution.
    Skipped at S2 freeze (N1); not cataloged. -/
def inferDisclosurePrivateStateIdV1 : String := "disclosure.private-state"

/-- Infer-only: commitment-visibility state disclosure contribution.
    Skipped at S2 freeze (N1); not cataloged. -/
def inferDisclosureCommitmentStateIdV1 : String := "disclosure.commitment-state"

/-- Infer-only: bn254 Fr Field type contribution (not S2 catalog; freeze-skipped N2b). -/
def inferValueFieldBn254FrIdV1 : String := "value.field.bn254-fr"

/-- Infer-only: BLS12-377 Fr Field type contribution (T14 catalog v2; not S2
    catalog; freeze-skipped). Admitted by Aleo (Leo native field). -/
def inferValueFieldBls12377FrIdV1 : String := "value.field.bls12-377-fr"

/-- Infer-only: Goldilocks Field type contribution (T14 catalog v2; not S2
    catalog; freeze-skipped). Admitted by Psy (plonky2 Felt). -/
def inferValueFieldGoldilocksIdV1 : String := "value.field.goldilocks"

/-- Closed infer-only contribution ids (not in S2 catalog).
    Disclosure ids are freeze-skipped (N1); field bn254/bls12-377/goldilocks
    are freeze-skipped (N2b; T14 catalog v2 extends the field set). -/
def inferOnlyRequirementIdsV1 : Array String :=
  #[inferDisclosurePrivateWitnessIdV1, inferDisclosureCommitmentIdV1,
    inferDisclosurePrivateStateIdV1, inferDisclosureCommitmentStateIdV1,
    inferValueFieldBn254FrIdV1, inferValueFieldBls12377FrIdV1,
    inferValueFieldGoldilocksIdV1]

end ProofForgeV2.Core.RequirementIdsV1

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

  Wire-owned Solana CPI extension binding (ADR-0024 engineering row)
    Extension source id: `solana.cpi.accounts`
    Version: `1.0.0`
    Domain tag: `pf.extension-semantics.v1`
    Id: `extension.solana-cpi-accounts`
      (`wireExtensionSolanaCpiAccountsIdV1`)
    Digest is the frozen extension JCS domain digest, not a digest of the id.
    Not part of the S2 freeze catalog and does not advertise target support.

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

/-- Wire Commit exact-row id (domain `pf.commit-requirement.v1`).
    Same spelling as `inferDisclosureCommitmentIdV1` — dual meaning; see
    module doc. -/
def wireCommitmentDisclosureIdV1 : String := "disclosure.commitment"

/-- Frozen source declaration id for ADR-0024's opt-in Solana CPI extension. -/
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

/-- Closed wire-owned requirement ids (ContextRead + Commit + exact extension
    bindings). Membership here does not imply support by any target/profile. -/
def wireOwnedRequirementIdsV1 : Array String :=
  #[wireContextUnixTimeSecondsIdV1, wireContextCallerIdV1,
    wireCommitmentDisclosureIdV1, wireExtensionSolanaCpiAccountsIdV1]

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

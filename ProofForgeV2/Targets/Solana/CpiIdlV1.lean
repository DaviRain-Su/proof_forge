/-
  ProofForgeV2.Targets.Solana.CpiIdlV1 — #117 pure inspect-only CPI IDL model.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1` (shared with Contract/Plan/IR).

  Typed projection of handler-local account policy/privilege provenance,
  instructions, CPI sites, state schemas, and frozen PDA rules for inspection
  only. Reuses Plan/Contract types; program keys are displayed as canonical
  base58 while Plan raw keys remain authority. The #118 SemanticProgram/
  capability join remains absent. Never mints OutputFile / product artifacts
  and never defines a second catalog or API surface.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common

/-! ## 1) Inspect-only typed projection rows -/

/-- One handler-local account row (local position, not global full universe). -/
structure CpiIdlAccountRowV1 where
  position : Nat
  roleId : Nat
  name : String
  keyPolicy : RoleKeyPolicyV1
  constraint : AccountConstraint
  aliasPolicy : AliasPolicy
  directSignerContribution : Bool
  directWritableContribution : Bool
  outerSigner : Bool
  outerWritable : Bool
  deriving BEq, Repr

/-- One instruction (handler) row with exact local accounts + CPI site ids. -/
structure CpiIdlInstructionRowV1 where
  handlerId : Nat
  name : String
  mode : HandlerModeV1
  accounts : Array CpiIdlAccountRowV1
  cpiSiteIds : Array Nat
  deriving BEq, Repr

/-- One CPI argument row for IDL (role name when principal-bound). -/
structure CpiIdlArgRowV1 where
  name : String
  type_ : FrozenValueType
  source : ArgumentSource
  roleName : Option String
  deriving BEq, Repr

/-- One ordered meta row: role name + full frozen meta spec (binding /
    constraint / CPI flags / outer contributions / group). -/
structure CpiIdlMetaRowV1 where
  metaIndex : Nat
  roleName : String
  spec : FrozenMetaSpec
  deriving BEq, Repr

/-- One outer-only account row (e.g. seedAuthority visibility). -/
structure CpiIdlOuterOnlyRowV1 where
  roleName : String
  spec : FrozenOuterOnlySpec
  deriving BEq, Repr

/-- One CPI site inspect row. Program id is canonical base58 for display;
    Plan `programKey` raw bytes remain the sole authority. -/
structure CpiIdlSiteRowV1 where
  siteId : Nat
  handlerId : Nat
  anchor : SemanticSiteAnchorV1
  qn : String
  packageId : String
  programRoleName : String
  programIdBase58 : String
  instructionCodec : InstructionCodec
  args : Array CpiIdlArgRowV1
  metas : Array CpiIdlMetaRowV1
  outerOnlyAccounts : Array CpiIdlOuterOnlyRowV1
  accountInfoRoleNames : Array String
  signerGroups : Array FrozenSignerGroup
  pda : FrozenPdaUse
  preflight : Array FrozenPreflightSpecV1
  sitePredicates : Array SiteAccountPredicateV1
  returnDataPolicy : ReturnDataPolicyV1
  failurePolicy : FailurePolicyV1
  deriving BEq, Repr

/-! ## 2) Public candidate + private validated carrier -/

/-- Public inspection candidate for Solana CPI IDL (not yet validated). -/
structure SolanaCpiIdlCandidateV1 where
  schema : String
  planDigest : Digest
  profileId : String
  profileDigest : Digest
  catalogDigest : Digest
  programName : String
  stateSchemas : Array StateSchemaV1
  pdaRules : Array FrozenPdaRule
  instructions : Array CpiIdlInstructionRowV1
  cpiSites : Array CpiIdlSiteRowV1
  deriving BEq

/-- Validated CPI IDL carrier. Retains the source validated Plan, accepted
    candidate, and canonical PF-JCS text+bytes. Constructor is private; public
    field projections are the sole read-only accessors. Does not mint
    OutputFile. -/
structure ValidatedSolanaCpiIdlV1 where
  private mk ::
  plan : ValidatedSolanaCpiPlanV1
  candidate : SolanaCpiIdlCandidateV1
  canonicalText : String
  canonicalBytes : ByteArray

/-! ## Internal helpers -/

private def idlFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def mapExcept (e : Except String α) (ctx : String) : CompileResult α :=
  match e with
  | .ok v => pure v
  | .error msg => idlFail s!"{ctx}: {msg}"

private def maxUInt32Nat : Nat := 4294967295

private def requireUInt32 (label : String) (n : Nat) : CompileResult Unit := do
  unless n ≤ maxUInt32Nat do
    idlFail s!"{label} exceeds UInt32"

private def pfNat (label : String) (n : Nat) : CompileResult PfJson := do
  requireUInt32 label n
  pure (.int (Int.ofNat n))

private def digestsEqual (left right : Digest) : Bool :=
  left.algorithm == right.algorithm && left.bytes == right.bytes

private def findRole?
    (roles : Array AccountRoleSchemaV1) (roleId : Nat) :
    Option AccountRoleSchemaV1 :=
  roles.find? (fun r => r.roleId == roleId)

/-! ## Sole expected projection from validated Plan -/

private def projectAccountRow
    (roles : Array AccountRoleSchemaV1) (use : HandlerAccountUseV1) :
    CompileResult CpiIdlAccountRowV1 := do
  let role ← match findRole? roles use.roleId with
    | some r => pure r
    | none => idlFail "handler account use roleId missing from plan accountRoles"
  pure {
    position := use.position
    roleId := use.roleId
    name := role.name
    keyPolicy := role.keyPolicy
    constraint := role.constraint
    aliasPolicy := role.aliasPolicy
    directSignerContribution := use.directSignerContribution
    directWritableContribution := use.directWritableContribution
    outerSigner := use.outerSigner
    outerWritable := use.outerWritable
  }

private def projectInstruction
    (c : SolanaCpiPlanCandidateV1) (h : HandlerPlanV1) :
    CompileResult CpiIdlInstructionRowV1 := do
  -- Handler-local uses/order only — never the global full role universe.
  let accounts ← h.accountUses.mapM (projectAccountRow c.accountRoles)
  pure {
    handlerId := h.handlerId
    name := h.name
    mode := h.mode
    accounts
    cpiSiteIds := h.cpiSiteIds
  }

private def projectArgRow
    (roles : Array AccountRoleSchemaV1) (a : CpiArgumentBindingV1) :
    CompileResult CpiIdlArgRowV1 := do
  let roleName ← match a.roleId with
    | none => pure none
    | some roleId =>
        match findRole? roles roleId with
        | some r => pure (some r.name)
        | none => idlFail "cpi arg roleId missing from plan accountRoles"
  pure {
    name := a.spec.name
    type_ := a.spec.type_
    source := a.spec.source
    roleName
  }

private def projectMetaRow
    (roles : Array AccountRoleSchemaV1) (m : CpiMetaPlanV1) :
    CompileResult CpiIdlMetaRowV1 := do
  let role ← match findRole? roles m.roleId with
    | some r => pure r
    | none => idlFail "cpi meta roleId missing from plan accountRoles"
  pure {
    metaIndex := m.metaIndex
    roleName := role.name
    spec := m.spec
  }

private def projectOuterOnlyRow
    (roles : Array AccountRoleSchemaV1) (o : CpiOuterOnlyPlanV1) :
    CompileResult CpiIdlOuterOnlyRowV1 := do
  let role ← match findRole? roles o.roleId with
    | some r => pure r
    | none => idlFail "outer-only roleId missing from plan accountRoles"
  pure {
    roleName := role.name
    spec := o.spec
  }

private def projectSite
    (c : SolanaCpiPlanCandidateV1) (s : CpiSitePlanV1) :
    CompileResult CpiIdlSiteRowV1 := do
  let programRole ← match findRole? c.accountRoles s.programRoleId with
    | some r => pure r
    | none => idlFail "program roleId missing from plan accountRoles"
  let args ← s.args.mapM (projectArgRow c.accountRoles)
  let metas ← s.metas.mapM (projectMetaRow c.accountRoles)
  let outerOnlyAccounts ← s.outerOnlyAccounts.mapM
    (projectOuterOnlyRow c.accountRoles)
  let mut accountInfoRoleNames : Array String := #[]
  for roleId in s.accountInfoRoleIds do
    match findRole? c.accountRoles roleId with
    | some r => accountInfoRoleNames := accountInfoRoleNames.push r.name
    | none => idlFail "accountInfo roleId missing from plan accountRoles"
  pure {
    siteId := s.siteId
    handlerId := s.handlerId
    anchor := s.anchor
    qn := s.qn
    packageId := s.packageId
    programRoleName := programRole.name
    programIdBase58 := SolanaPubkeyV1.toBase58 s.programKey
    instructionCodec := s.instructionCodec
    args
    metas
    outerOnlyAccounts
    accountInfoRoleNames
    signerGroups := s.signerGroups
    pda := s.pda
    preflight := s.preflight
    sitePredicates := s.sitePredicates
    returnDataPolicy := s.returnDataPolicy
    failurePolicy := s.failurePolicy
  }

private def projectExpectedIdl
    (plan : ValidatedSolanaCpiPlanV1) :
    CompileResult SolanaCpiIdlCandidateV1 := do
  let c := plan.candidate
  let instructions ← c.handlers.mapM (projectInstruction c)
  let cpiSites ← c.cpiSites.mapM (projectSite c)
  pure {
    schema := idlSchemaV1
    planDigest := plan.digest
    profileId := c.profileId
    profileDigest := c.profileDigest
    catalogDigest := c.calleeCatalogDigest
    programName := c.programName
    stateSchemas := c.stateSchemas
    pdaRules := c.pdaRules
    instructions
    cpiSites
  }

/-! ## PF-JCS encoding (every candidate field; private) -/

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

private def encodeRoleKeyPolicy : RoleKeyPolicyV1 → CompileResult PfJson
  | .state schemaId => do
      pure (.object #[
        ("kind", .string "state"),
        ("schemaId", ← pfNat "roleKeyPolicy.state.schemaId" schemaId)
      ])
  | .accountParameter callableId paramOrdinal => do
      pure (.object #[
        ("kind", .string "accountParameter"),
        ("callableId", ← pfNat "roleKeyPolicy.accountParameter.callableId" callableId),
        ("paramOrdinal",
          ← pfNat "roleKeyPolicy.accountParameter.paramOrdinal" paramOrdinal)
      ])
  | .fixedProgram packageId =>
      pure (.object #[
        ("kind", .string "fixedProgram"),
        ("packageId", .string packageId)
      ])
  | .vaultPda => pure (.object #[("kind", .string "vaultPda")])
  | .handlerCaller => pure (.object #[("kind", .string "handlerCaller")])
  | .vaultAta .. => pure (.object #[("kind", .string "vaultAta")])
  | .dstAta .. => pure (.object #[("kind", .string "dstAta")])

private def encodeHandlerMode : HandlerModeV1 → PfJson
  | .initialize => .string "initialize"
  | .entry => .string "entry"
  | .view => .string "view"

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
  pure (.object #[
    ("length", ← pfNat "instructionCodec.length" c.length),
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
  | .vaultAta .. => .object #[("kind", .string "vaultAta")]
  | .dstAta .. => .object #[("kind", .string "dstAta")]

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
  pure (.object #[
    ("arg", .string s.arg),
    ("constraint", ← encodeConstraint s.constraint),
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
  pure (.object #[
    ("id", ← pfNat "signerGroup.id" g.id),
    ("metaArg", .string g.metaArg),
    ("pdaRule", .string g.pdaRule)
  ])

private def encodePreflight : FrozenPreflightSpecV1 → CompileResult PfJson
  | .uint64AtMost argName value => do
      pure (.object #[
        ("kind", .string "uint64AtMost"),
        ("argName", .string argName),
        ("value", ← pfNat "preflight.uint64AtMost.value" value)
      ])

private def encodeSitePredicateSource : SitePredicateSourceV1 → CompileResult PfJson
  | .callee => pure (.object #[("kind", .string "callee")])
  | .metaIndex index => do
      pure (.object #[
        ("kind", .string "meta"),
        ("index", ← pfNat "sitePredicate.meta.index" index)
      ])
  | .outerOnlyIndex index => do
      pure (.object #[
        ("kind", .string "outerOnly"),
        ("index", ← pfNat "sitePredicate.outerOnly.index" index)
      ])

private def encodeSitePredicate (p : SiteAccountPredicateV1) :
    CompileResult PfJson := do
  pure (.object #[
    ("source", ← encodeSitePredicateSource p.source),
    ("roleId", ← pfNat "sitePredicate.roleId" p.roleId),
    ("constraint", ← encodeConstraint p.constraint)
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

private def encodeStateSchema (s : StateSchemaV1) : CompileResult PfJson := do
  let dig ← mapExcept (renderDigest s.layoutDigest) "stateSchema.layoutDigest"
  pure (.object #[
    ("schemaId", ← pfNat "stateSchema.schemaId" s.schemaId),
    ("name", .string s.name),
    ("exactDataLen", ← pfNat "stateSchema.exactDataLen" s.exactDataLen),
    ("layoutDigest", .string dig),
    ("initializedMarker", .string
      (renderUInt64LowerHex16V1 s.initializedMarker))
  ])

private def encodeAnchor (a : SemanticSiteAnchorV1) : CompileResult PfJson := do
  pure (.object #[
    ("callableId", ← pfNat "anchor.callableId" a.callableId),
    ("blockId", ← pfNat "anchor.blockId" a.blockId),
    ("instructionIndex", ← pfNat "anchor.instructionIndex" a.instructionIndex),
    ("effectId", ← pfNat "anchor.effectId" a.effectId)
  ])

private def encodeAccountRow (a : CpiIdlAccountRowV1) : CompileResult PfJson := do
  pure (.object #[
    ("position", ← pfNat "idlAccount.position" a.position),
    ("roleId", ← pfNat "idlAccount.roleId" a.roleId),
    ("name", .string a.name),
    ("keyPolicy", ← encodeRoleKeyPolicy a.keyPolicy),
    ("constraint", ← encodeConstraint a.constraint),
    ("aliasPolicy", encodeAliasPolicy a.aliasPolicy),
    ("directSignerContribution", .bool a.directSignerContribution),
    ("directWritableContribution", .bool a.directWritableContribution),
    ("outerSigner", .bool a.outerSigner),
    ("outerWritable", .bool a.outerWritable)
  ])

private def encodeInstructionRow (i : CpiIdlInstructionRowV1) :
    CompileResult PfJson := do
  let accounts ← i.accounts.mapM encodeAccountRow
  let siteIds ← i.cpiSiteIds.mapM (fun id => pfNat "idlInstruction.cpiSiteId" id)
  pure (.object #[
    ("handlerId", ← pfNat "idlInstruction.handlerId" i.handlerId),
    ("name", .string i.name),
    ("mode", encodeHandlerMode i.mode),
    ("accounts", .array accounts),
    ("cpiSiteIds", .array siteIds)
  ])

private def encodeArgRow (a : CpiIdlArgRowV1) : PfJson :=
  .object #[
    ("name", .string a.name),
    ("type", encodeFrozenValueType a.type_),
    ("source", encodeArgumentSource a.source),
    ("roleName", match a.roleName with
      | some n => .string n
      | none => .null)
  ]

private def encodeMetaRow (m : CpiIdlMetaRowV1) : CompileResult PfJson := do
  pure (.object #[
    ("metaIndex", ← pfNat "idlMeta.metaIndex" m.metaIndex),
    ("roleName", .string m.roleName),
    ("spec", ← encodeFrozenMetaSpec m.spec)
  ])

private def encodeOuterOnlyRow (o : CpiIdlOuterOnlyRowV1) : CompileResult PfJson := do
  pure (.object #[
    ("roleName", .string o.roleName),
    ("spec", ← encodeFrozenOuterOnlySpec o.spec)
  ])

private def encodeSiteRow (s : CpiIdlSiteRowV1) : CompileResult PfJson := do
  let metas ← s.metas.mapM encodeMetaRow
  let outerOnly ← s.outerOnlyAccounts.mapM encodeOuterOnlyRow
  let groups ← s.signerGroups.mapM encodeFrozenSignerGroup
  let preflight ← s.preflight.mapM encodePreflight
  let predicates ← s.sitePredicates.mapM encodeSitePredicate
  pure (.object #[
    ("siteId", ← pfNat "idlSite.siteId" s.siteId),
    ("handlerId", ← pfNat "idlSite.handlerId" s.handlerId),
    ("anchor", ← encodeAnchor s.anchor),
    ("qn", .string s.qn),
    ("packageId", .string s.packageId),
    ("programRoleName", .string s.programRoleName),
    ("programIdBase58", .string s.programIdBase58),
    ("instructionCodec", ← encodeInstructionCodec s.instructionCodec),
    ("args", .array (s.args.map encodeArgRow)),
    ("metas", .array metas),
    ("outerOnlyAccounts", .array outerOnly),
    ("accountInfoRoleNames",
      .array (s.accountInfoRoleNames.map PfJson.string)),
    ("signerGroups", .array groups),
    ("pda", encodeFrozenPdaUse s.pda),
    ("preflight", .array preflight),
    ("sitePredicates", .array predicates),
    ("returnDataPolicy", encodeReturnDataPolicy s.returnDataPolicy),
    ("failurePolicy", encodeFailurePolicy s.failurePolicy)
  ])

private def encodeCandidatePfJson
    (c : SolanaCpiIdlCandidateV1) : CompileResult PfJson := do
  let planDig ← mapExcept (renderDigest c.planDigest) "planDigest"
  let profileDig ← mapExcept (renderDigest c.profileDigest) "profileDigest"
  let catalogDig ← mapExcept (renderDigest c.catalogDigest) "catalogDigest"
  let stateSchemas ← c.stateSchemas.mapM encodeStateSchema
  let pdaRules ← c.pdaRules.mapM encodeFrozenPdaRule
  let instructions ← c.instructions.mapM encodeInstructionRow
  let cpiSites ← c.cpiSites.mapM encodeSiteRow
  pure (.object #[
    ("schema", .string c.schema),
    ("planDigest", .string planDig),
    ("profileId", .string c.profileId),
    ("profileDigest", .string profileDig),
    ("catalogDigest", .string catalogDig),
    ("programName", .string c.programName),
    ("stateSchemas", .array stateSchemas),
    ("pdaRules", .array pdaRules),
    ("instructions", .array instructions),
    ("cpiSites", .array cpiSites)
  ])

private def encodeCandidateCanonical
    (c : SolanaCpiIdlCandidateV1) : CompileResult (String × ByteArray) := do
  let json ← encodeCandidatePfJson c
  let text ← mapExcept (renderPfJcs json) "canonical PF-JCS"
  pure (text, text.toUTF8)

/-! ## 3) Sole validate + derive -/

/-- Sole IDL validation entry. Constructs the unique expected projection from
    `plan` and requires exact equality with `candidate`. Does not mint
    OutputFile. -/
def validateSolanaCpiIdlV1
    (plan : ValidatedSolanaCpiPlanV1)
    (candidate : SolanaCpiIdlCandidateV1) :
    CompileResult ValidatedSolanaCpiIdlV1 := do
  let expected ← projectExpectedIdl plan
  unless candidate.schema == expected.schema do
    idlFail s!"schema must be exact {idlSchemaV1}"
  unless digestsEqual candidate.planDigest expected.planDigest do
    idlFail "planDigest must equal validated plan digest"
  unless candidate.profileId == expected.profileId do
    idlFail "profileId must equal plan profileId"
  unless digestsEqual candidate.profileDigest expected.profileDigest do
    idlFail "profileDigest must equal plan profileDigest"
  unless digestsEqual candidate.catalogDigest expected.catalogDigest do
    idlFail "catalogDigest must equal plan calleeCatalogDigest"
  unless candidate.programName == expected.programName do
    idlFail "programName must equal plan programName"
  unless candidate.stateSchemas == expected.stateSchemas do
    idlFail "stateSchemas must equal plan stateSchemas projection"
  unless candidate.pdaRules == expected.pdaRules do
    idlFail "pdaRules must equal plan pdaRules projection"
  unless candidate.instructions == expected.instructions do
    idlFail "instructions must equal sole handler-local IDL projection"
  unless candidate.cpiSites == expected.cpiSites do
    idlFail "cpiSites must equal sole plan-derived IDL site projection"
  unless candidate == expected do
    idlFail "candidate must equal sole expected IDL projection"
  let (canonicalText, canonicalBytes) ← encodeCandidateCanonical candidate
  pure ⟨plan, candidate, canonicalText, canonicalBytes⟩

/-- Sole convenient mint: project then validate. -/
def deriveSolanaCpiIdlV1
    (plan : ValidatedSolanaCpiPlanV1) :
    CompileResult ValidatedSolanaCpiIdlV1 := do
  let expected ← projectExpectedIdl plan
  validateSolanaCpiIdlV1 plan expected

end ProofForgeV2.Targets.Solana.CpiV1

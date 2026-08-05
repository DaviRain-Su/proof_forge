/-
  ProofForgeV2.Targets.Solana.CpiIRV1 — #117 pure emitter-facing CPI IR model.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1` (shared with Contract/Plan).

  Closed Loader V3 ABIv1 layout + exact C struct field layouts, parsed role
  handles with full key/constraint/alias/privilege data (no ACC0 fixed
  assumption), Plan identity/state/PDA/compute projection, declarative site
  operations, and private-ctor validated carrier. Sole structural projection
  input is `ValidatedSolanaCpiPlanV1`; the #118 SemanticProgram/capability join
  remains deliberately absent. Never mints OutputFile / product artifacts and
  is never wired into emitter or platform invocation surfaces.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common

/-! ## IR digest domain -/

def irDigestDomainV1 : String := "pf.solana.cpi-ir.v1"

/-! ## 1) Closed exact ABI layouts (Loader V3 ABIv1 + C structs) -/

/-- One frozen C field (name + offset + width). -/
structure CFieldLayoutV1 where
  name : String
  offset : Nat
  byteWidth : Nat
  deriving BEq, Repr

/-- Frozen Loader V3 direct-mapped ABIv1 full-record layout (extension authority). -/
structure LoaderV3AbiLayoutV1 where
  schema : String
  loader : String
  parser : String
  fullPrefixBytes : Nat
  marker : Nat
  isSignerOffset : Nat
  isWritableOffset : Nat
  executableOffset : Nat
  originalDataLenOffset : Nat
  keyOffset : Nat
  ownerOffset : Nat
  lamportsOffset : Nat
  dataLenOffset : Nat
  maxPermittedDataIncrease : Nat
  dataRegionRule : String
  virtualCursorRule : String
  rentEpochRule : String
  instructionTail : Array String
  pointerTableLocation : String
  pointerTableAlignment : Nat
  pointerTableEntry : String
  pointerTableOneEntryPerOuterRole : Bool
  accountDataDirectMapping : Bool
  directAccountPointersInProgramInput : Bool
  virtualAddressSpaceAdjustments : Bool
  duplicateRecordBytes : Nat
  originalDataLenEntryValue : Nat
  deriving BEq, Repr

/-- One frozen `repr(C)` layout with exact field offsets/widths. -/
structure CStructLayoutV1 where
  name : String
  size : Nat
  align : Nat
  fields : Array CFieldLayoutV1
  deriving BEq, Repr

/-- Exact product CPI C layouts for Instruction/Meta/Info/Seed/Seeds.
    Field `accountMeta` (not bare `meta`) avoids the Lean reserved word. -/
structure CpiIRCLayoutsV1 where
  instruction : CStructLayoutV1
  accountMeta : CStructLayoutV1
  info : CStructLayoutV1
  seed : CStructLayoutV1
  seeds : CStructLayoutV1
  deriving BEq, Repr

private def cField (name : String) (offset byteWidth : Nat) : CFieldLayoutV1 :=
  { name, offset, byteWidth }

/-- Exact frozen ABIv1 layout. -/
def frozenLoaderV3AbiLayoutV1 : LoaderV3AbiLayoutV1 where
  schema := "abiv1"
  loader := "loader-v3"
  parser := "overflow-checked-virtual-address-walk-not-contiguous-backing-buffer-walk"
  fullPrefixBytes := 88
  marker := 0xff
  isSignerOffset := 1
  isWritableOffset := 2
  executableOffset := 3
  originalDataLenOffset := 4
  keyOffset := 8
  ownerOffset := 40
  lamportsOffset := 72
  dataLenOffset := 80
  maxPermittedDataIncrease := 10240
  dataRegionRule := "direct-mapped-at-prefix-plus-88"
  virtualCursorRule := "align8(data-address-plus-data-len-plus-10240)"
  rentEpochRule := "u64-max-at-align8(data-end-plus-10240)"
  instructionTail := #[
    "u64-le-instruction-data-len",
    "instruction-data",
    "current-program-id-32",
    "zero-pad-to-8",
    "account-marker-pointer-table"
  ]
  pointerTableLocation := "after-program-id-and-zero-padding"
  pointerTableAlignment := 8
  pointerTableEntry := "u64-le-vm-address-of-role-marker"
  pointerTableOneEntryPerOuterRole := true
  accountDataDirectMapping := true
  directAccountPointersInProgramInput := true
  virtualAddressSpaceAdjustments := true
  duplicateRecordBytes := 8
  originalDataLenEntryValue := 0

/-- Exact frozen C layouts with field offsets (Instruction 40/8, Meta 16/8,
    Info 56/8, Seed 16/8, Seeds 16/8). -/
def frozenCpiIRCLayoutsV1 : CpiIRCLayoutsV1 where
  instruction := {
    name := "SolInstruction", size := 40, align := 8
    fields := #[
      cField "program_id_addr" 0 8,
      cField "accounts_addr" 8 8,
      cField "accounts_len" 16 8,
      cField "data_addr" 24 8,
      cField "data_len" 32 8
    ]
  }
  accountMeta := {
    name := "SolAccountMeta", size := 16, align := 8
    fields := #[
      cField "pubkey_addr" 0 8,
      cField "is_writable" 8 1,
      cField "is_signer" 9 1,
      cField "zero_padding" 10 6
    ]
  }
  info := {
    name := "SolAccountInfo", size := 56, align := 8
    fields := #[
      cField "key_addr" 0 8,
      cField "lamports_addr" 8 8,
      cField "data_len" 16 8,
      cField "data_addr" 24 8,
      cField "owner_addr" 32 8,
      cField "rent_epoch" 40 8,
      cField "is_signer" 48 1,
      cField "is_writable" 49 1,
      cField "executable" 50 1,
      cField "zero_padding" 51 5
    ]
  }
  seed := {
    name := "SolSignerSeed", size := 16, align := 8
    fields := #[
      cField "addr" 0 8,
      cField "len" 8 8
    ]
  }
  seeds := {
    name := "SolSignerSeeds", size := 16, align := 8
    fields := #[
      cField "addr" 0 8,
      cField "len" 8 8
    ]
  }

/-! ## 2) Emitter-facing parsed-handle data (no ACC0 fixed assumption) -/

/-- One handler-local parsed role handle. Local index is the ABIv1 position
    within that handler; never a global ACC0_* constant. -/
structure CpiIRRoleHandleV1 where
  handlerId : Nat
  localIndex : Nat
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

/-- One CPI meta slot projected onto a local handle with its full frozen spec. -/
structure CpiIRMetaV1 where
  metaIndex : Nat
  roleId : Nat
  localHandleIndex : Nat
  spec : FrozenMetaSpec
  deriving BEq, Repr

/-- One ordered outer-only slot projected onto a local handle. -/
structure CpiIROuterOnlyV1 where
  roleId : Nat
  localHandleIndex : Nat
  spec : FrozenOuterOnlySpec
  deriving BEq, Repr

/-- One typed CPI site in emitter-facing IR form. -/
structure CpiIRSiteV1 where
  siteId : Nat
  handlerId : Nat
  anchor : SemanticSiteAnchorV1
  qn : String
  packageId : String
  programRoleId : Nat
  programHandleIndex : Nat
  programKey : SolanaPubkeyV1
  args : Array CpiArgumentBindingV1
  instructionCodec : InstructionCodec
  metas : Array CpiIRMetaV1
  outerOnlyAccounts : Array CpiIROuterOnlyV1
  accountInfoRoleIds : Array Nat
  accountInfoHandleIndices : Array Nat
  signerGroups : Array FrozenSignerGroup
  pda : FrozenPdaUse
  preflight : Array FrozenPreflightSpecV1
  sitePredicates : Array SiteAccountPredicateV1
  returnDataPolicy : ReturnDataPolicyV1
  failurePolicy : FailurePolicyV1
  deriving BEq, Repr

/-! ## 3) Typed declarative operations (description only; no invoke surface) -/

/-- Declarative CPI IR operation. Derived in exact site source order:
    preflight checks, then site predicates, then prepare/boundary steps.
    Description only — no platform invoke ctor or emitter. -/
inductive CpiIROperationV1 where
  | checkPreflight
      (siteId : Nat)
      (preflightIndex : Nat)
      (predicate : FrozenPreflightSpecV1)
  | checkPredicate
      (siteId : Nat)
      (predicateIndex : Nat)
      (predicate : SiteAccountPredicateV1)
  | prepareInstruction
      (siteId : Nat)
      (codec : InstructionCodec)
      (args : Array CpiArgumentBindingV1)
  | prepareMeta
      (siteId : Nat)
      (metaSlot : CpiIRMetaV1)
  | prepareFullAccountInfos
      (siteId : Nat)
      (handleIndices : Array Nat)
  | prepareSignerGroup
      (siteId : Nat)
      (group : FrozenSignerGroup)
  | cpiBoundary
      (siteId : Nat)
      (programHandleIndex : Nat)
      (signerGroupCount : Nat)
  deriving BEq, Repr

/-! ## 4) Public candidate + private validated carrier -/

/-- Public inspection candidate for Solana CPI IR (not yet validated). -/
structure SolanaCpiIRCandidateV1 where
  schema : String
  sourcePlanDigest : Digest
  profileId : String
  profileDigest : Digest
  catalogDigest : Digest
  stateSchemas : Array StateSchemaV1
  pdaRules : Array FrozenPdaRule
  computeAssumptions : ComputeAssumptionsV1
  abiLayout : LoaderV3AbiLayoutV1
  cLayouts : CpiIRCLayoutsV1
  roleHandles : Array CpiIRRoleHandleV1
  sites : Array CpiIRSiteV1
  operations : Array CpiIROperationV1
  deriving BEq

/-- Validated CPI IR carrier. Retains the source validated Plan, the accepted
    candidate, PF-JCS canonical bytes, and domain-separated digest
    (`pf.solana.cpi-ir.v1`). Constructor is private; public field projections
    are the sole read-only accessors. -/
structure ValidatedSolanaCpiIRV1 where
  private mk ::
  plan : ValidatedSolanaCpiPlanV1
  candidate : SolanaCpiIRCandidateV1
  canonicalBytes : ByteArray
  digest : Digest

/-! ## Internal helpers -/

private def irFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def mapExcept (e : Except String α) (ctx : String) : CompileResult α :=
  match e with
  | .ok v => pure v
  | .error msg => irFail s!"{ctx}: {msg}"

private def maxUInt32Nat : Nat := 4294967295

private def requireUInt32 (label : String) (n : Nat) : CompileResult Unit := do
  unless n ≤ maxUInt32Nat do
    irFail s!"{label} exceeds UInt32"

private def pfNat (label : String) (n : Nat) : CompileResult PfJson := do
  requireUInt32 label n
  pure (.int (Int.ofNat n))

private def digestsEqual (left right : Digest) : Bool :=
  left.algorithm == right.algorithm && left.bytes == right.bytes

private def lowerHexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

private def encodeLowerHex (bytes : ByteArray) : String :=
  bytes.foldl (fun result byte =>
    let value := byte.toNat
    (result.push (lowerHexDigit (value / 16))).push (lowerHexDigit (value % 16))) ""

private def encodePubkey (key : SolanaPubkeyV1) : PfJson :=
  .string (encodeLowerHex (SolanaPubkeyV1.toBytes key))

private def findHandler?
    (handlers : Array HandlerPlanV1) (handlerId : Nat) :
    Option HandlerPlanV1 :=
  handlers.find? (fun h => h.handlerId == handlerId)

private def localHandleIndexOf
    (handler : HandlerPlanV1) (roleId : Nat) : Option Nat :=
  handler.accountUses.findIdx? (fun u => u.roleId == roleId)

/-! ## Sole expected projection from validated Plan -/

private def projectRoleHandles
    (c : SolanaCpiPlanCandidateV1) : CompileResult (Array CpiIRRoleHandleV1) := do
  let mut out : Array CpiIRRoleHandleV1 := #[]
  for h in c.handlers do
    for use in h.accountUses do
      let role ← match c.accountRoles.find? (fun r => r.roleId == use.roleId) with
        | some r => pure r
        | none => irFail "role handle roleId missing from plan accountRoles"
      out := out.push {
        handlerId := h.handlerId
        localIndex := use.position
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
  pure out

private def projectMeta
    (handler : HandlerPlanV1) (m : CpiMetaPlanV1) : CompileResult CpiIRMetaV1 := do
  let localHandleIndex ← match localHandleIndexOf handler m.roleId with
    | some i => pure i
    | none => irFail "meta role missing from handler local uses"
  pure {
    metaIndex := m.metaIndex
    roleId := m.roleId
    localHandleIndex
    spec := m.spec
  }

private def projectOuterOnly
    (handler : HandlerPlanV1) (o : CpiOuterOnlyPlanV1) :
    CompileResult CpiIROuterOnlyV1 := do
  let localHandleIndex ← match localHandleIndexOf handler o.roleId with
    | some i => pure i
    | none => irFail "outer-only role missing from handler local uses"
  pure {
    roleId := o.roleId
    localHandleIndex
    spec := o.spec
  }

private def projectSite
    (c : SolanaCpiPlanCandidateV1) (s : CpiSitePlanV1) :
    CompileResult CpiIRSiteV1 := do
  let handler ← match findHandler? c.handlers s.handlerId with
    | some h => pure h
    | none => irFail "site handlerId unknown in plan"
  let programHandleIndex ← match localHandleIndexOf handler s.programRoleId with
    | some i => pure i
    | none => irFail "program role missing from handler local uses"
  let metas ← s.metas.mapM (projectMeta handler)
  let outerOnlyAccounts ← s.outerOnlyAccounts.mapM (projectOuterOnly handler)
  -- Project the Plan-owned exact AccountInfo role sequence through this
  -- handler's local handles; never reconstruct from a global role universe.
  let mut accountInfoHandleIndices : Array Nat := #[]
  for roleId in s.accountInfoRoleIds do
    let localIndex ← match localHandleIndexOf handler roleId with
      | some i => pure i
      | none => irFail "accountInfo role missing from handler local uses"
    accountInfoHandleIndices := accountInfoHandleIndices.push localIndex
  pure {
    siteId := s.siteId
    handlerId := s.handlerId
    anchor := s.anchor
    qn := s.qn
    packageId := s.packageId
    programRoleId := s.programRoleId
    programHandleIndex
    programKey := s.programKey
    args := s.args
    instructionCodec := s.instructionCodec
    metas
    outerOnlyAccounts
    accountInfoRoleIds := s.accountInfoRoleIds
    accountInfoHandleIndices
    signerGroups := s.signerGroups
    pda := s.pda
    preflight := s.preflight
    sitePredicates := s.sitePredicates
    returnDataPolicy := s.returnDataPolicy
    failurePolicy := s.failurePolicy
  }

/-- Exact declarative ops: per site, all preflight then all sitePredicates,
    then prepare/boundary sequence. -/
private def projectOperations
    (sites : Array CpiIRSiteV1) : Array CpiIROperationV1 :=
  Id.run do
    let mut ops : Array CpiIROperationV1 := #[]
    for site in sites do
      for i in [0:site.preflight.size] do
        match site.preflight[i]? with
        | none => pure ()
        | some pred =>
            ops := ops.push (.checkPreflight site.siteId i pred)
      for i in [0:site.sitePredicates.size] do
        match site.sitePredicates[i]? with
        | none => pure ()
        | some pred =>
            ops := ops.push (.checkPredicate site.siteId i pred)
      ops := ops.push
        (.prepareInstruction site.siteId site.instructionCodec site.args)
      for metaSlot in site.metas do
        ops := ops.push (.prepareMeta site.siteId metaSlot)
      ops := ops.push
        (.prepareFullAccountInfos site.siteId site.accountInfoHandleIndices)
      for group in site.signerGroups do
        ops := ops.push (.prepareSignerGroup site.siteId group)
      ops := ops.push
        (.cpiBoundary site.siteId site.programHandleIndex site.signerGroups.size)
    return ops

private def projectExpectedIR
    (plan : ValidatedSolanaCpiPlanV1) :
    CompileResult SolanaCpiIRCandidateV1 := do
  let c := plan.candidate
  let roleHandles ← projectRoleHandles c
  let sites ← c.cpiSites.mapM (projectSite c)
  let operations := projectOperations sites
  pure {
    schema := irSchemaV1
    sourcePlanDigest := plan.digest
    profileId := c.profileId
    profileDigest := c.profileDigest
    catalogDigest := c.calleeCatalogDigest
    stateSchemas := c.stateSchemas
    pdaRules := c.pdaRules
    computeAssumptions := c.computeAssumptions
    abiLayout := frozenLoaderV3AbiLayoutV1
    cLayouts := frozenCpiIRCLayoutsV1
    roleHandles
    sites
    operations
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
  | .vaultAta => pure (.object #[("kind", .string "vaultAta")])
  | .dstAta => pure (.object #[("kind", .string "dstAta")])

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
  let signerGroup ← match s.signerGroupId with
    | none => pure PfJson.null
    | some id => pfNat "meta.signerGroupId" id
  pure (.object #[
    ("binding", encodeMetaBinding s.binding),
    ("constraint", ← encodeConstraint s.constraint),
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

private def encodeAnchor (a : SemanticSiteAnchorV1) : CompileResult PfJson := do
  pure (.object #[
    ("callableId", ← pfNat "anchor.callableId" a.callableId),
    ("blockId", ← pfNat "anchor.blockId" a.blockId),
    ("instructionIndex", ← pfNat "anchor.instructionIndex" a.instructionIndex),
    ("effectId", ← pfNat "anchor.effectId" a.effectId)
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

private def encodeCField (f : CFieldLayoutV1) : CompileResult PfJson := do
  pure (.object #[
    ("name", .string f.name),
    ("offset", ← pfNat "cField.offset" f.offset),
    ("byteWidth", ← pfNat "cField.byteWidth" f.byteWidth)
  ])

private def encodeAbiLayout (a : LoaderV3AbiLayoutV1) : CompileResult PfJson := do
  pure (.object #[
    ("schema", .string a.schema),
    ("loader", .string a.loader),
    ("parser", .string a.parser),
    ("fullPrefixBytes", ← pfNat "abi.fullPrefixBytes" a.fullPrefixBytes),
    ("marker", ← pfNat "abi.marker" a.marker),
    ("isSignerOffset", ← pfNat "abi.isSignerOffset" a.isSignerOffset),
    ("isWritableOffset", ← pfNat "abi.isWritableOffset" a.isWritableOffset),
    ("executableOffset", ← pfNat "abi.executableOffset" a.executableOffset),
    ("originalDataLenOffset",
      ← pfNat "abi.originalDataLenOffset" a.originalDataLenOffset),
    ("keyOffset", ← pfNat "abi.keyOffset" a.keyOffset),
    ("ownerOffset", ← pfNat "abi.ownerOffset" a.ownerOffset),
    ("lamportsOffset", ← pfNat "abi.lamportsOffset" a.lamportsOffset),
    ("dataLenOffset", ← pfNat "abi.dataLenOffset" a.dataLenOffset),
    ("maxPermittedDataIncrease",
      ← pfNat "abi.maxPermittedDataIncrease" a.maxPermittedDataIncrease),
    ("dataRegionRule", .string a.dataRegionRule),
    ("virtualCursorRule", .string a.virtualCursorRule),
    ("rentEpochRule", .string a.rentEpochRule),
    ("instructionTail", .array (a.instructionTail.map PfJson.string)),
    ("pointerTableLocation", .string a.pointerTableLocation),
    ("pointerTableAlignment",
      ← pfNat "abi.pointerTableAlignment" a.pointerTableAlignment),
    ("pointerTableEntry", .string a.pointerTableEntry),
    ("pointerTableOneEntryPerOuterRole",
      .bool a.pointerTableOneEntryPerOuterRole),
    ("accountDataDirectMapping", .bool a.accountDataDirectMapping),
    ("directAccountPointersInProgramInput",
      .bool a.directAccountPointersInProgramInput),
    ("virtualAddressSpaceAdjustments",
      .bool a.virtualAddressSpaceAdjustments),
    ("duplicateRecordBytes",
      ← pfNat "abi.duplicateRecordBytes" a.duplicateRecordBytes),
    ("originalDataLenEntryValue",
      ← pfNat "abi.originalDataLenEntryValue" a.originalDataLenEntryValue)
  ])

private def encodeCStruct (s : CStructLayoutV1) : CompileResult PfJson := do
  let fields ← s.fields.mapM encodeCField
  pure (.object #[
    ("name", .string s.name),
    ("size", ← pfNat "cStruct.size" s.size),
    ("align", ← pfNat "cStruct.align" s.align),
    ("fields", .array fields)
  ])

private def encodeCLayouts (c : CpiIRCLayoutsV1) : CompileResult PfJson := do
  pure (.object #[
    ("instruction", ← encodeCStruct c.instruction),
    ("accountMeta", ← encodeCStruct c.accountMeta),
    ("info", ← encodeCStruct c.info),
    ("seed", ← encodeCStruct c.seed),
    ("seeds", ← encodeCStruct c.seeds)
  ])

private def encodeRoleHandle (h : CpiIRRoleHandleV1) : CompileResult PfJson := do
  pure (.object #[
    ("handlerId", ← pfNat "roleHandle.handlerId" h.handlerId),
    ("localIndex", ← pfNat "roleHandle.localIndex" h.localIndex),
    ("roleId", ← pfNat "roleHandle.roleId" h.roleId),
    ("name", .string h.name),
    ("keyPolicy", ← encodeRoleKeyPolicy h.keyPolicy),
    ("constraint", ← encodeConstraint h.constraint),
    ("aliasPolicy", encodeAliasPolicy h.aliasPolicy),
    ("directSignerContribution", .bool h.directSignerContribution),
    ("directWritableContribution", .bool h.directWritableContribution),
    ("outerSigner", .bool h.outerSigner),
    ("outerWritable", .bool h.outerWritable)
  ])

private def encodeIrMeta (m : CpiIRMetaV1) : CompileResult PfJson := do
  pure (.object #[
    ("metaIndex", ← pfNat "irMeta.metaIndex" m.metaIndex),
    ("roleId", ← pfNat "irMeta.roleId" m.roleId),
    ("localHandleIndex", ← pfNat "irMeta.localHandleIndex" m.localHandleIndex),
    ("spec", ← encodeFrozenMetaSpec m.spec)
  ])

private def encodeIrOuterOnly (o : CpiIROuterOnlyV1) : CompileResult PfJson := do
  pure (.object #[
    ("roleId", ← pfNat "irOuterOnly.roleId" o.roleId),
    ("localHandleIndex",
      ← pfNat "irOuterOnly.localHandleIndex" o.localHandleIndex),
    ("spec", ← encodeFrozenOuterOnlySpec o.spec)
  ])

private def encodeIrSite (s : CpiIRSiteV1) : CompileResult PfJson := do
  let args ← s.args.mapM encodeArgBinding
  let codec ← encodeInstructionCodec s.instructionCodec
  let metas ← s.metas.mapM encodeIrMeta
  let outerOnly ← s.outerOnlyAccounts.mapM encodeIrOuterOnly
  let infoRoles ← s.accountInfoRoleIds.mapM
    (fun i => pfNat "irSite.accountInfoRoleId" i)
  let infos ← s.accountInfoHandleIndices.mapM
    (fun i => pfNat "irSite.accountInfoHandleIndex" i)
  let groups ← s.signerGroups.mapM encodeFrozenSignerGroup
  let preflight ← s.preflight.mapM encodePreflight
  let predicates ← s.sitePredicates.mapM encodeSitePredicate
  pure (.object #[
    ("siteId", ← pfNat "irSite.siteId" s.siteId),
    ("handlerId", ← pfNat "irSite.handlerId" s.handlerId),
    ("anchor", ← encodeAnchor s.anchor),
    ("qn", .string s.qn),
    ("packageId", .string s.packageId),
    ("programRoleId", ← pfNat "irSite.programRoleId" s.programRoleId),
    ("programHandleIndex",
      ← pfNat "irSite.programHandleIndex" s.programHandleIndex),
    ("programKey", encodePubkey s.programKey),
    ("args", .array args),
    ("instructionCodec", codec),
    ("metas", .array metas),
    ("outerOnlyAccounts", .array outerOnly),
    ("accountInfoRoleIds", .array infoRoles),
    ("accountInfoHandleIndices", .array infos),
    ("signerGroups", .array groups),
    ("pda", encodeFrozenPdaUse s.pda),
    ("preflight", .array preflight),
    ("sitePredicates", .array predicates),
    ("returnDataPolicy", encodeReturnDataPolicy s.returnDataPolicy),
    ("failurePolicy", encodeFailurePolicy s.failurePolicy)
  ])

private def encodeOperation : CpiIROperationV1 → CompileResult PfJson
  | .checkPreflight siteId preflightIndex predicate => do
      pure (.object #[
        ("kind", .string "checkPreflight"),
        ("siteId", ← pfNat "op.siteId" siteId),
        ("preflightIndex", ← pfNat "op.preflightIndex" preflightIndex),
        ("predicate", ← encodePreflight predicate)
      ])
  | .checkPredicate siteId predicateIndex predicate => do
      pure (.object #[
        ("kind", .string "checkPredicate"),
        ("siteId", ← pfNat "op.siteId" siteId),
        ("predicateIndex", ← pfNat "op.predicateIndex" predicateIndex),
        ("predicate", ← encodeSitePredicate predicate)
      ])
  | .prepareInstruction siteId codec args => do
      let encodedArgs ← args.mapM encodeArgBinding
      pure (.object #[
        ("kind", .string "prepareInstruction"),
        ("siteId", ← pfNat "op.siteId" siteId),
        ("codec", ← encodeInstructionCodec codec),
        ("args", .array encodedArgs)
      ])
  | .prepareMeta siteId metaSlot => do
      pure (.object #[
        ("kind", .string "prepareMeta"),
        ("siteId", ← pfNat "op.siteId" siteId),
        ("meta", ← encodeIrMeta metaSlot)
      ])
  | .prepareFullAccountInfos siteId handleIndices => do
      let infos ← handleIndices.mapM
        (fun i => pfNat "op.handleIndex" i)
      pure (.object #[
        ("kind", .string "prepareFullAccountInfos"),
        ("siteId", ← pfNat "op.siteId" siteId),
        ("handleIndices", .array infos)
      ])
  | .prepareSignerGroup siteId group => do
      pure (.object #[
        ("kind", .string "prepareSignerGroup"),
        ("siteId", ← pfNat "op.siteId" siteId),
        ("group", ← encodeFrozenSignerGroup group)
      ])
  | .cpiBoundary siteId programHandleIndex signerGroupCount => do
      pure (.object #[
        ("kind", .string "cpiBoundary"),
        ("siteId", ← pfNat "op.siteId" siteId),
        ("programHandleIndex",
          ← pfNat "op.programHandleIndex" programHandleIndex),
        ("signerGroupCount", ← pfNat "op.signerGroupCount" signerGroupCount)
      ])

private def encodeCandidatePfJson
    (c : SolanaCpiIRCandidateV1) : CompileResult PfJson := do
  let planDig ← mapExcept (renderDigest c.sourcePlanDigest) "sourcePlanDigest"
  let profileDig ← mapExcept (renderDigest c.profileDigest) "profileDigest"
  let catalogDig ← mapExcept (renderDigest c.catalogDigest) "catalogDigest"
  let stateSchemas ← c.stateSchemas.mapM encodeStateSchema
  let pdaRules ← c.pdaRules.mapM encodeFrozenPdaRule
  let roleHandles ← c.roleHandles.mapM encodeRoleHandle
  let sites ← c.sites.mapM encodeIrSite
  let operations ← c.operations.mapM encodeOperation
  pure (.object #[
    ("schema", .string c.schema),
    ("sourcePlanDigest", .string planDig),
    ("profileId", .string c.profileId),
    ("profileDigest", .string profileDig),
    ("catalogDigest", .string catalogDig),
    ("stateSchemas", .array stateSchemas),
    ("pdaRules", .array pdaRules),
    ("computeAssumptions", ← encodeComputeAssumptions c.computeAssumptions),
    ("abiLayout", ← encodeAbiLayout c.abiLayout),
    ("cLayouts", ← encodeCLayouts c.cLayouts),
    ("roleHandles", .array roleHandles),
    ("sites", .array sites),
    ("operations", .array operations)
  ])

private def encodeCandidateCanonical
    (c : SolanaCpiIRCandidateV1) : CompileResult ByteArray := do
  let json ← encodeCandidatePfJson c
  let text ← mapExcept (renderPfJcs json) "canonical PF-JCS"
  pure text.toUTF8

/-! ## 5) Sole validate + derive -/

/-- Sole IR validation entry. Constructs the unique expected projection from
    `plan` and requires exact equality with `candidate` (any role / meta /
    order / layout / policy change is rejected). Digest is minted only on the
    validated private carrier. -/
def validateSolanaCpiIRV1
    (plan : ValidatedSolanaCpiPlanV1)
    (candidate : SolanaCpiIRCandidateV1) :
    CompileResult ValidatedSolanaCpiIRV1 := do
  let expected ← projectExpectedIR plan
  unless candidate.schema == expected.schema do
    irFail s!"schema must be exact {irSchemaV1}"
  unless digestsEqual candidate.sourcePlanDigest expected.sourcePlanDigest do
    irFail "sourcePlanDigest must equal validated plan digest"
  unless candidate.profileId == expected.profileId do
    irFail "profileId must equal validated plan profileId"
  unless digestsEqual candidate.profileDigest expected.profileDigest do
    irFail "profileDigest must equal validated plan profileDigest"
  unless digestsEqual candidate.catalogDigest expected.catalogDigest do
    irFail "catalogDigest must equal validated plan calleeCatalogDigest"
  unless candidate.stateSchemas == expected.stateSchemas do
    irFail "stateSchemas must equal validated plan stateSchemas"
  unless candidate.pdaRules == expected.pdaRules do
    irFail "pdaRules must equal validated plan pdaRules"
  unless candidate.computeAssumptions == expected.computeAssumptions do
    irFail "computeAssumptions must equal validated plan computeAssumptions"
  unless candidate.abiLayout == expected.abiLayout do
    irFail "abiLayout must equal frozen Loader V3 ABIv1 layout"
  unless candidate.cLayouts == expected.cLayouts do
    irFail "cLayouts must equal frozen CPI C struct layouts"
  unless candidate.roleHandles == expected.roleHandles do
    irFail "roleHandles must equal sole handler-local projection"
  unless candidate.sites == expected.sites do
    irFail "sites must equal sole plan-derived IR projection"
  unless candidate.operations == expected.operations do
    irFail "operations must equal sole site-source-order declarative sequence"
  unless candidate == expected do
    irFail "candidate must equal sole expected IR projection"
  let canonicalBytes ← encodeCandidateCanonical candidate
  let digest ← mapExcept
    (domainSeparatedSha256 irDigestDomainV1 canonicalBytes)
    "ir digest"
  pure ⟨plan, candidate, canonicalBytes, digest⟩

/-- Sole convenient mint: project then validate. -/
def deriveSolanaCpiIRV1
    (plan : ValidatedSolanaCpiPlanV1) :
    CompileResult ValidatedSolanaCpiIRV1 := do
  let expected ← projectExpectedIR plan
  validateSolanaCpiIRV1 plan expected

end ProofForgeV2.Targets.Solana.CpiV1

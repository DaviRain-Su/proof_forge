/-
  ProofForgeV2.Targets.Solana.CpiDeriveV1 — #118/#125 Semantic→CPI Plan derive.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Authority-free core: `deriveSolanaCpiPlanCandidateCoreV1` builds a
  `SolanaCpiPlanCandidateV1` from validated Semantic + snapshot digests/
  compute assumptions + optional product-API filter.

  Two private carriers (no conversion between them):
  * `SolanaCpiPreflightPlanV1` — #118 activationDenied; frozen snapshot;
    `validateSolanaCpiPlanV1`; admits all frozen APIs including companion.
  * `SolanaCpiProductPlanV1` — #125 product; active snapshot;
    `validateSolanaCpiProductPlanV1`; companion three APIs fail closed.

  Arg source rules (frozen API specs):
  * Principal → direct public Principal parameter of the owning callable;
  * typedExpression → exact anonymous UInt64 / UInt8 value;
  * literalOrBareDirect → exact-width UInt literal **or** direct public
    same-width parameter (const table itself is allowed; unsupported constant
    call args may still fail these source rules).

  schedule / pureFn|invariant call / unknown QN → fail closed.

  Nonempty logical state: sole legacy StateAccount via
  `deriveSolanaStateAccountFromSemanticDataV1` (validateSolanaTypeClosureV1 +
  makeStateAccountV1). Empty state remains supported (none).
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiProductCapabilityV1
import ProofForgeV2.Targets.Solana.LowerSemanticV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.Solana

/-! ## #118 preflight authority carrier -/

/-- Private product-join carrier for #118: resolved preflight capability plus
    structurally validated CPI Plan. Sole mint is
    `deriveSolanaCpiPlanFromPreflightV1`. Not a materialization authority. -/
structure SolanaCpiPreflightPlanV1 where
  private mk ::
  preflight : ResolvedSolanaCpiPreflightV1
  plan : ValidatedSolanaCpiPlanV1

namespace SolanaCpiPreflightPlanV1

def preflightOf (c : SolanaCpiPreflightPlanV1) : ResolvedSolanaCpiPreflightV1 :=
  c.preflight

def planOf (c : SolanaCpiPreflightPlanV1) : ValidatedSolanaCpiPlanV1 :=
  c.plan

def candidateOf (c : SolanaCpiPreflightPlanV1) : SolanaCpiPlanCandidateV1 :=
  c.plan.candidate

end SolanaCpiPreflightPlanV1

/-! ## #125 product authority carrier -/

/-- Private product-join carrier for #125: resolved product capability plus
    active-snapshot validated CPI Plan. Sole mint is
    `deriveSolanaCpiPlanFromProductCapabilityV1`. No conversion from/to
    preflight carriers. -/
structure SolanaCpiProductPlanV1 where
  private mk ::
  capability : ResolvedSolanaCpiProductCapabilityV1
  plan : ValidatedSolanaCpiPlanV1

namespace SolanaCpiProductPlanV1

def capabilityOf (c : SolanaCpiProductPlanV1) :
    ResolvedSolanaCpiProductCapabilityV1 :=
  c.capability

def planOf (c : SolanaCpiProductPlanV1) : ValidatedSolanaCpiPlanV1 :=
  c.plan

def candidateOf (c : SolanaCpiProductPlanV1) : SolanaCpiPlanCandidateV1 :=
  c.plan.candidate

def digestOf (c : SolanaCpiProductPlanV1) : Digest :=
  c.plan.digest

def canonicalBytesOf (c : SolanaCpiProductPlanV1) : ByteArray :=
  c.plan.canonicalBytes

end SolanaCpiProductPlanV1

private def deriveFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def mapExcept (e : Except String α) (ctx : String) : CompileResult α :=
  match e with
  | .ok v => pure v
  | .error msg => deriveFail s!"{ctx}: {msg}"

private def getArr (arr : Array α) (i : Nat) (ctx : String) : CompileResult α :=
  match arr[i]? with
  | some v => pure v
  | none => deriveFail s!"{ctx}: index {i} out of range"

private def packageRoleName (packageId : String) : String :=
  packageId.replace "-" "_" ++ "_program"

private def qnDotted (qn : QualifiedName) : CompileResult String := do
  let comps ← mapExcept (renderQualifiedNameComponents qn) "callee qualified name"
  pure (String.intercalate "." comps.toList)

private def anonUintWidth?
    (types : Array TypeDeclV1) (typeId : TypeIdV1) : Option Nat :=
  match types[typeId.toNat]? with
  | some decl =>
      if decl.name.isNone then
        match decl.shape with
        | .uint w => some w.toNat
        | _ => none
      else none
  | none => none

private def isAnonPrincipal
    (types : Array TypeDeclV1) (typeId : TypeIdV1) : Bool :=
  match types[typeId.toNat]? with
  | some decl =>
      decl.name.isNone &&
        match decl.shape with
        | .principal => true
        | _ => false
  | none => false

/-- Locate the defining type of a ValueId inside one callable (params, block
    params, instruction results). -/
private def typeOfValueId?
    (callable : CallableV1) (vid : ValueIdV1) : Option TypeIdV1 :=
  Id.run do
    for p in callable.params do
      if p.valueId == vid then return some p.typeId
    for blk in callable.blocks do
      for bp in blk.params do
        if bp.valueId == vid then return some bp.typeId
      for instr in blk.instructions do
        match instr.result with
        | some vd => if vd.valueId == vid then return some vd.typeId
        | none => pure ()
    return none

/-- True when `vid` is defined by an exact-width anonymous UInt literal. -/
private def isExactUintLiteral
    (types : Array TypeDeclV1) (callable : CallableV1)
    (vid : ValueIdV1) (width : Nat) : Bool :=
  Id.run do
    for blk in callable.blocks do
      for instr in blk.instructions do
        match instr.result, instr.op with
        | some vd, .literal tid _bytes =>
            if vd.valueId == vid then
              return anonUintWidth? types tid == some width
        | _, _ => pure ()
    return false

/-- Direct public parameter ordinal when `vid` is that parameter and matches
    the expected typeId. -/
private def directPublicParamOrdinal?
    (callable : CallableV1) (vid : ValueIdV1) (expectedTid : TypeIdV1) :
    Option Nat :=
  Id.run do
    for (p, i) in callable.params.zipIdx do
      if p.valueId == vid && p.typeId == expectedTid &&
          p.visibility == VisibilityV1.public_ then
        return some i
    return none

/-- Principal arg: must be a direct public Principal parameter. -/
private def requirePrincipalArg
    (types : Array TypeDeclV1) (callable : CallableV1)
    (vid : ValueIdV1) (argName : String) : CompileResult Nat := do
  let tid ← match typeOfValueId? callable vid with
    | some t => pure t
    | none =>
        deriveFail
          s!"CPI arg '{argName}': ValueId {vid} has no definition in callable"
  unless isAnonPrincipal types tid do
    deriveFail
      s!"CPI arg '{argName}': Principal source requires anonymous Principal type"
  match directPublicParamOrdinal? callable vid tid with
  | some ord => pure ord
  | none =>
      deriveFail
        s!"CPI arg '{argName}': Principal must be a direct public Principal parameter"

/-- typedExpression: exact anonymous UInt{width}. -/
private def requireTypedUintArg
    (types : Array TypeDeclV1) (callable : CallableV1)
    (vid : ValueIdV1) (width : Nat) (argName : String) : CompileResult Unit := do
  let tid ← match typeOfValueId? callable vid with
    | some t => pure t
    | none =>
        deriveFail
          s!"CPI arg '{argName}': ValueId {vid} has no definition in callable"
  unless anonUintWidth? types tid == some width do
    deriveFail
      s!"CPI arg '{argName}': typedExpression requires exact UInt{width}"

/-- literalOrBareDirect: exact-width literal or direct public same-width param. -/
private def requireLitOrBareUintArg
    (types : Array TypeDeclV1) (callable : CallableV1)
    (vid : ValueIdV1) (width : Nat) (argName : String) : CompileResult Unit := do
  let tid ← match typeOfValueId? callable vid with
    | some t => pure t
    | none =>
        deriveFail
          s!"CPI arg '{argName}': ValueId {vid} has no definition in callable"
  unless anonUintWidth? types tid == some width do
    deriveFail
      s!"CPI arg '{argName}': literalOrBareDirect requires exact UInt{width}"
  if isExactUintLiteral types callable vid width then
    pure ()
  else if (directPublicParamOrdinal? callable vid tid).isSome then
    pure ()
  else
    deriveFail
      s!"CPI arg '{argName}': literalOrBareDirect admits only exact-width literal or direct public same-width param"

/-- One discovered ExternalCall site before role assignment. -/
private structure RawSiteV1 where
  callableId : Nat
  handlerMode : HandlerModeV1
  handlerName : String
  blockId : Nat
  instructionIndex : Nat
  effectId : Nat
  qn : String
  api : FrozenApi
  argValueIds : Array ValueIdV1
  /-- For each Principal arg: (argIndex, paramOrdinal). -/
  principalParams : Array (Nat × Nat)

private def handlerModeOf (kind : CallableKindV1) : CompileResult HandlerModeV1 :=
  match kind with
  | .initializer => pure .initialize
  | .entry => pure .entry
  | .view => pure .view
  | .pureFn =>
      deriveFail "CPI derive rejects ExternalCall inside pureFn"
  | .invariant =>
      deriveFail "CPI derive rejects ExternalCall inside invariant"

private def handlerNameOf (callable : CallableV1) : CompileResult String :=
  match callable.kind, callable.name with
  | .initializer, none => pure "init"
  | .initializer, some n => pure n
  | _, some n => pure n
  | _, none =>
      deriveFail "CPI derive: named handler callable is missing its name"

private def validateArgSources
    (types : Array TypeDeclV1) (callable : CallableV1)
    (api : FrozenApi) (argIds : Array ValueIdV1) :
    CompileResult (Array (Nat × Nat)) := do
  unless argIds.size == api.args.size do
    deriveFail
      s!"CPI site '{api.qn}': arg arity {argIds.size} != frozen API {api.args.size}"
  let mut principals : Array (Nat × Nat) := #[]
  for i in [0:api.args.size] do
    let spec : FrozenArgSpec ← getArr api.args i "frozenApi.args"
    let vid : ValueIdV1 ← getArr argIds i "site.args"
    match (spec.type_ : FrozenValueType), (spec.source : ArgumentSource) with
    | FrozenValueType.principal,
      ArgumentSource.bareDirectPublicPrincipalParameter =>
        let ord ← requirePrincipalArg types callable vid spec.name
        principals := principals.push (i, ord)
    | FrozenValueType.uint64, ArgumentSource.typedExpression =>
        requireTypedUintArg types callable vid 64 spec.name
    | FrozenValueType.uint8, ArgumentSource.typedExpression =>
        requireTypedUintArg types callable vid 8 spec.name
    | FrozenValueType.uint64,
      ArgumentSource.literalConstantOrBareDirectPublicUInt64Parameter =>
        requireLitOrBareUintArg types callable vid 64 spec.name
    | FrozenValueType.uint8,
      ArgumentSource.literalConstantOrBareDirectPublicUInt8Parameter =>
        requireLitOrBareUintArg types callable vid 8 spec.name
    | _, _ =>
        deriveFail
          s!"CPI arg '{spec.name}': unsupported frozen type/source combination"
  pure principals

/-- Direct initializer/entry/view handler in Semantic source order. -/
private structure DirectHandlerV1 where
  callableId : Nat
  mode : HandlerModeV1
  name : String
  callable : CallableV1

private def collectDirectHandlers
    (data : SemanticProgramDataV1) : CompileResult (Array DirectHandlerV1) := do
  let mut out : Array DirectHandlerV1 := #[]
  for callable in data.callables do
    match callable.kind with
    | .initializer | .entry | .view =>
        let mode ← handlerModeOf callable.kind
        let hname ← handlerNameOf callable
        out := out.push {
          callableId := callable.id.toNat
          mode
          name := hname
          callable
        }
    | .pureFn | .invariant => pure ()
  pure out

private def collectRawSites
    (data : SemanticProgramDataV1) : CompileResult (Array RawSiteV1) := do
  unless data.invariants.isEmpty do
    deriveFail "CPI derive rejects nonempty invariants table"
  let mut out : Array RawSiteV1 := #[]
  for callable in data.callables do
    let callableId := callable.id.toNat
    let isHandler :=
      callable.kind == .initializer ||
        callable.kind == .entry ||
        callable.kind == .view
    for blk in callable.blocks do
      for (instr, instrIdx) in blk.instructions.zipIdx do
        match instr.op with
        | .schedule _effectId _callee _args =>
            deriveFail "CPI derive rejects schedule (async workflow stays fail closed)"
        | .externalCall effectId callee args =>
            unless isHandler do
              deriveFail
                "CPI derive rejects ExternalCall outside initializer/entry/view"
            let mode ← handlerModeOf callable.kind
            let hname ← handlerNameOf callable
            let qn ← qnDotted callee
            let api ← match findFrozenApi? qn with
              | some a => pure a
              | none =>
                  deriveFail s!"CPI derive rejects unknown callee QN '{qn}'"
            let principals ← validateArgSources data.types callable api args
            out := out.push {
              callableId
              handlerMode := mode
              handlerName := hname
              blockId := blk.id.toNat
              instructionIndex := instrIdx
              effectId := effectId.toNat
              qn
              api
              argValueIds := args
              principalParams := principals
            }
        | _ => pure ()
  pure out

/-- Role key for global dense assignment. -/
private inductive RoleKeyV1 where
  | state (schemaId : Nat)
  | accountParam (callableId : Nat) (paramOrdinal : Nat)
  | fixedProgram (packageId : String)
  | vaultPda
  | handlerCaller
  | vaultAta
  | dstAta
  deriving BEq

private def roleKeyEq (a b : RoleKeyV1) : Bool :=
  match a, b with
  | .state s1, .state s2 => s1 == s2
  | .accountParam c1 o1, .accountParam c2 o2 => c1 == c2 && o1 == o2
  | .fixedProgram p1, .fixedProgram p2 => p1 == p2
  | .vaultPda, .vaultPda => true
  | .handlerCaller, .handlerCaller => true
  | .vaultAta, .vaultAta => true
  | .dstAta, .dstAta => true
  | _, _ => false

private def findRoleId? (keys : Array RoleKeyV1) (want : RoleKeyV1) : Option Nat :=
  Id.run do
    for (k, i) in keys.zipIdx do
      if roleKeyEq k want then return some i
    return none

private def ensureRole
    (keys : Array RoleKeyV1) (roles : Array AccountRoleSchemaV1)
    (want : RoleKeyV1) (name : String) (constraint : AccountConstraint) :
    CompileResult (Array RoleKeyV1 × Array AccountRoleSchemaV1 × Nat) := do
  match findRoleId? keys want with
  | some id => pure (keys, roles, id)
  | none =>
      let id := roles.size
      let keyPolicy :=
        match want with
        | .state schemaId => RoleKeyPolicyV1.state schemaId
        | .accountParam cid ord => RoleKeyPolicyV1.accountParameter cid ord
        | .fixedProgram pkg => RoleKeyPolicyV1.fixedProgram pkg
        | .vaultPda => RoleKeyPolicyV1.vaultPda
        | .handlerCaller => RoleKeyPolicyV1.handlerCaller
        | .vaultAta => RoleKeyPolicyV1.vaultAta
        | .dstAta => RoleKeyPolicyV1.dstAta
      let role : AccountRoleSchemaV1 := {
        roleId := id
        name
        keyPolicy
        constraint
        aliasPolicy := frozenAliasPolicyV1
      }
      pure (keys.push want, roles.push role, id)

private def hasPfAssetsExtensionRow (data : SemanticProgramDataV1) : Bool :=
  data.requirements.items.any (·.id == wireExtensionPfAssetsIdV1)

private def hasSolanaCpiExtensionRow (data : SemanticProgramDataV1) : Bool :=
  data.requirements.items.any (·.id == wireExtensionSolanaCpiAccountsIdV1)

/-- Vault role entry constraint (ADR-0029 B1 / ADR-0028 §4.2).

    Entry preflight must **not** require current-program ownership: the first
    `nativeDeposit` may still need to ensure (createPda) a fresh System-owned
    vault (`owner=System ∧ data_len=0 ∧ lamports=0`). Closed owner alternatives
    are enforced at ensure site-time in `emitInvokeNativeDeposit`
    (System-fresh create **or** current-program skip; third states fail closed).
    Transfer site metas still carry `constraintVaultOwned` (current-program) so
    vault→dst CPI only runs after ensure has established program ownership.
    Data remains exact empty (`space=0` create / rent-exempt empty vault). -/
private def vaultRoleConstraintV1 : AccountConstraint where
  owner := .any
  executable := .forbidden
  data := .exactLength 0
  initialization := .existing
  provisioning := .mustExist

/-- Deposit caller: System-owned empty data, outer signer. -/
private def handlerCallerRoleConstraintV1 : AccountConstraint where
  owner := .fixedProgram "system-v1"
  executable := .forbidden
  data := .exactLength 0
  initialization := .existing
  provisioning := .mustExist

/-- ADR-0030 E1b vault ATA role: Token-owned 165B token account or
    (idempotent ensure) fresh System-owned zero. Key is ATA(vault, mint),
    derived at runtime. The entry constraint admits both pre-states; site-time
    checks enforce Token 165B before the transferChecked CPI. -/
private def vaultAtaRoleConstraintV1 : AccountConstraint where
  owner := .closedPackages #["system-v1", "token-classic-v1"]
  executable := .forbidden
  data := .ataAccount "mint" "vault"
  initialization := .uninitializedOrIdempotentlyInitialized
  provisioning := .ataCreateIdempotent

/-- ADR-0030 E1b destination ATA role: Token-owned 165B token account or
    (idempotent ensure) fresh System-owned zero. Key is ATA(dst, mint),
    derived at runtime. -/
private def dstAtaRoleConstraintV1 : AccountConstraint where
  owner := .closedPackages #["system-v1", "token-classic-v1"]
  executable := .forbidden
  data := .ataAccount "mint" "dst"
  initialization := .uninitializedOrIdempotentlyInitialized
  provisioning := .ataCreateIdempotent

/-- Account-parameter role name: prefer `handlerName_paramName`; fall back to
    a short unique form when the preferred name exceeds the 240-byte identifier
    limit or fails the shared identifier grammar. Never uses frozen API arg
    names as role identity. -/
private def accountParamRoleName
    (handlerName paramName : String) (callableId paramOrdinal : Nat) : String :=
  let preferred := handlerName ++ "_" ++ paramName
  if preferred.utf8ByteSize ≤ 240 && isIdentifier preferred then
    preferred
  else
    s!"p{callableId}_{paramOrdinal}"

private def paramNameAt
    (callable : CallableV1) (ord : Nat) : CompileResult String := do
  match callable.params[ord]? with
  | some p => pure p.name
  | none =>
      deriveFail
        s!"CPI derive: missing parameter ordinal {ord} on callable {callable.id}"

/-- Privilege contributions for one role across one site's metas/outer-only. -/
private def siteRolePrivilege
    (metas : Array CpiMetaPlanV1) (outerOnly : Array CpiOuterOnlyPlanV1)
    (roleId : Nat) : Bool × Bool :=
  Id.run do
    let mut signer := false
    let mut writable := false
    for m in metas do
      if m.roleId == roleId then
        if m.spec.outerSignerContribution then signer := true
        if m.spec.outerWritableContribution then writable := true
    for o in outerOnly do
      if o.roleId == roleId then
        if o.spec.outerSignerContribution then signer := true
        if o.spec.outerWritableContribution then writable := true
    pure (signer, writable)

private def directStatePrivileges (mode : HandlerModeV1) : Bool × Bool :=
  match mode with
  | .initialize => (true, true)
  | .entry => (false, true)
  | .view => (false, false)

/-- Build one site's metas/outer-only/args given role maps. -/
private def buildSiteBindings
    (raw : RawSiteV1)
    (principalRoleByArgIndex : Array (Nat × Nat))
    (fixedRoleByPackage : Array (String × Nat))
    (vaultRoleId? : Option Nat)
    (callerRoleId? : Option Nat)
    (vaultAtaRoleId? : Option Nat)
    (dstAtaRoleId? : Option Nat)
    (programRoleId : Nat) (programKey : SolanaPubkeyV1)
    (siteId handlerId : Nat) : CompileResult CpiSitePlanV1 := do
  let api := raw.api
  let mut args : Array CpiArgumentBindingV1 := #[]
  for i in [0:api.args.size] do
    let spec : FrozenArgSpec ← getArr api.args i "frozenApi.args"
    let vid : ValueIdV1 ← getArr raw.argValueIds i "site.args"
    let roleId ←
      if spec.type_ == FrozenValueType.principal then
        match principalRoleByArgIndex.find? (fun p => p.1 == i) with
        | some (_, rid) => pure (some rid)
        | none => deriveFail s!"missing principal role for arg '{spec.name}'"
      else pure none
    args := args.push {
      spec
      semanticValueId := vid.toNat
      roleId
    }
  let mut metas : Array CpiMetaPlanV1 := #[]
  for (spec, metaIndex) in api.metas.zipIdx do
    let roleId ← match spec.binding with
      | MetaBinding.arg name =>
          let mut found : Option Nat := none
          for i in [0:api.args.size] do
            let a : FrozenArgSpec ← getArr api.args i "frozenApi.args"
            if a.name == name then
              match principalRoleByArgIndex.find? (fun p => p.1 == i) with
              | some (_, rid) => found := some rid
              | none => pure ()
          match found with
          | some rid => pure rid
          | none => deriveFail s!"meta arg '{name}' missing principal role"
      | MetaBinding.fixedProgram packageId =>
          match fixedRoleByPackage.find? (fun p => p.1 == packageId) with
          | some (_, rid) => pure rid
          | none => deriveFail s!"meta fixedProgram '{packageId}' missing role"
      | MetaBinding.vaultPda =>
          match vaultRoleId? with
          | some rid => pure rid
          | none => deriveFail "meta vaultPda missing vault role"
      | MetaBinding.handlerCaller =>
          match callerRoleId? with
          | some rid => pure rid
          | none => deriveFail "meta handlerCaller missing caller role"
      | MetaBinding.vaultAta =>
          match vaultAtaRoleId? with
          | some rid => pure rid
          | none => deriveFail "meta vaultAta missing vaultAta role"
      | MetaBinding.dstAta =>
          match dstAtaRoleId? with
          | some rid => pure rid
          | none => deriveFail "meta dstAta missing dstAta role"
    metas := metas.push { metaIndex, roleId, spec }
  let mut outerOnly : Array CpiOuterOnlyPlanV1 := #[]
  for spec in api.outerOnlyAccounts do
    let mut found : Option Nat := none
    for i in [0:api.args.size] do
      let a : FrozenArgSpec ← getArr api.args i "frozenApi.args"
      if a.name == spec.arg then
        match principalRoleByArgIndex.find? (fun p => p.1 == i) with
        | some (_, rid) => found := some rid
        | none => pure ()
    let roleId ← match found with
      | some rid => pure rid
      | none => deriveFail s!"outer-only arg '{spec.arg}' missing principal role"
    outerOnly := outerOnly.push { roleId, spec }
  let predicates : Array SiteAccountPredicateV1 :=
    Id.run do
      let mut out : Array SiteAccountPredicateV1 := #[{
        source := SitePredicateSourceV1.callee
        roleId := programRoleId
        constraint := calleeRoleConstraintV1
      }]
      for (m, i) in metas.zipIdx do
        out := out.push {
          source := SitePredicateSourceV1.metaIndex i
          roleId := m.roleId
          constraint := m.spec.constraint
        }
      for (o, i) in outerOnly.zipIdx do
        out := out.push {
          source := SitePredicateSourceV1.outerOnlyIndex i
          roleId := o.roleId
          constraint := o.spec.constraint
        }
      pure out
  pure {
    siteId
    handlerId
    anchor := {
      callableId := raw.callableId
      blockId := raw.blockId
      instructionIndex := raw.instructionIndex
      effectId := raw.effectId
    }
    qn := raw.qn
    packageId := api.fixedProgram
    programRoleId
    programKey
    args
    instructionCodec := api.instructionCodec
    metas
    outerOnlyAccounts := outerOnly
    accountInfoRoleIds := #[]  -- filled after handler accountUses
    signerGroups := api.signerGroups
    pda := api.pda
    preflight := api.preflight
    sitePredicates := predicates
    returnDataPolicy := propagateImmediatelyReturnDataPolicyV1
    failurePolicy := propagateImmediatelyFailurePolicyV1
  }

/-! ## Authority-free core (shared by preflight + product carriers) -/

/-- Snapshot parameters that differ between preactivation and product Plans. -/
structure DerivePlanSnapshotV1 where
  profileDigest : Digest
  catalogDigest : Digest
  computeAssumptions : ComputeAssumptionsV1
  /-- When `true`, reject companion and non-approved product APIs. -/
  productApiFilter : Bool

/-- Collect raw ExternalCall sites. When `productApiFilter`, companion and
    non-approved QNs fail closed at discovery.

    ADR-0029 Phase B1 QN gate:
    * catalog pf.assets QN ⇒ retained freeze must carry exact `extension.pf-assets`
      (else fail closed with a stable diagnostic);
    * only `pf.assets.native.deposit` / `pf.assets.native.transfer` enter this
      lane (other three catalog QNs fail closed as Phase B scope);
    * non-catalog QNs keep existing CPI profile product filter behaviour. -/
private def collectRawSitesFiltered
    (data : SemanticProgramDataV1) (productApiFilter : Bool) :
    CompileResult (Array RawSiteV1) := do
  unless data.invariants.isEmpty do
    deriveFail "CPI derive rejects nonempty invariants table"
  let pfAssetsDeclared := hasPfAssetsExtensionRow data
  let mut out : Array RawSiteV1 := #[]
  for callable in data.callables do
    let callableId := callable.id.toNat
    let isHandler :=
      callable.kind == .initializer ||
        callable.kind == .entry ||
        callable.kind == .view
    for blk in callable.blocks do
      for (instr, instrIdx) in blk.instructions.zipIdx do
        match instr.op with
        | .schedule _effectId _callee _args =>
            deriveFail "CPI derive rejects schedule (async workflow stays fail closed)"
        | .externalCall effectId callee args =>
            unless isHandler do
              deriveFail
                "CPI derive rejects ExternalCall outside initializer/entry/view"
            let mode ← handlerModeOf callable.kind
            let hname ← handlerNameOf callable
            let qn ← qnDotted callee
            if isPfAssetsCatalogQnV1 qn then
              unless pfAssetsDeclared do
                deriveFail
                  s!"CPI derive: pf.assets catalog call '{qn}' requires extension.pf-assets declaration"
              unless isPfAssetsSolanaProductApiV1 qn do
                deriveFail
                  s!"CPI derive: pf.assets QN '{qn}' is outside Phase B Solana native vault scope (async/token fail closed)"
            if productApiFilter then
              if isCompanionApiV1 qn then
                deriveFail
                  s!"CPI product derive rejects companion API '{qn}'"
              unless isApprovedProductApiV1 qn do
                deriveFail
                  s!"CPI product derive rejects non-approved API '{qn}'"
            let api ← match findFrozenApi? qn with
              | some a => pure a
              | none =>
                  deriveFail s!"CPI derive rejects unknown callee QN '{qn}'"
            let principals ← validateArgSources data.types callable api args
            out := out.push {
              callableId
              handlerMode := mode
              handlerName := hname
              blockId := blk.id.toNat
              instructionIndex := instrIdx
              effectId := effectId.toNat
              qn
              api
              argValueIds := args
              principalParams := principals
            }
        | _ => pure ()
  pure out

/-- Authority-free core: Semantic data + programName + snapshot → Plan candidate.
    Does not mint carriers, does not validate, does not import Registry/Emit. -/
def deriveSolanaCpiPlanCandidateCoreV1
    (data : SemanticProgramDataV1)
    (programName : String)
    (snapshot : DerivePlanSnapshotV1) :
    CompileResult SolanaCpiPlanCandidateV1 := do
  let directHandlers ← collectDirectHandlers data
  let rawSites ← collectRawSitesFiltered data snapshot.productApiFilter
  unless rawSites.size > 0 do
    deriveFail "CPI derive requires at least one ExternalCall site"

  let stateAccount? ← deriveSolanaStateAccountFromSemanticDataV1 data
  let stateSchemas : Array StateSchemaV1 ←
    match stateAccount? with
    | none => pure (Array.empty : Array StateSchemaV1)
    | some account =>
        unless directHandlers.any (fun h => h.mode == .initialize) do
          deriveFail
            "CPI derive requires an initializer when logical state is nonempty"
        let schema : StateSchemaV1 := {
          schemaId := 0
          name := account.name
          exactDataLen := account.exactDataLen
          layoutDigest := layoutDigestOfFieldsV1 account.fields
          initializedMarker := account.initializedMarker
        }
        pure #[schema]

  let mut roleKeys : Array RoleKeyV1 := #[]
  let mut roles : Array AccountRoleSchemaV1 := #[]
  let mut builtSites : Array CpiSitePlanV1 := #[]
  let mut handlers : Array HandlerPlanV1 := #[]
  let mut stateRoleId? : Option Nat := none

  match stateAccount? with
  | some account =>
      let (k0, r0, stateRoleId) ← ensureRole roleKeys roles
        (RoleKeyV1.state 0) account.name stateRoleConstraintV1
      roleKeys := k0
      roles := r0
      stateRoleId? := some stateRoleId
  | none => pure ()

  for (handler, handlerId) in directHandlers.zipIdx do
    let callableId := handler.callableId
    let mode := handler.mode
    let hname := handler.name
    let hSites : Array RawSiteV1 :=
      rawSites.filter (fun s => s.callableId == callableId)
    let needsVault := hSites.any (fun s =>
      s.qn == "pf.assets.native.deposit" || s.qn == "pf.assets.native.transfer")
    let needsCaller := hSites.any (fun s =>
      s.qn == "pf.assets.native.deposit" || s.qn == "pf.assets.token.transfer")
    let mut usedOrds : Array Nat := #[]
    for site in hSites do
      for (_, ord) in site.principalParams do
        unless usedOrds.any (· == ord) do
          usedOrds := usedOrds.push ord
    let sortedOrds := usedOrds.qsort (· < ·)
    for ord in sortedOrds do
      let pname ← paramNameAt handler.callable ord
      let rname := accountParamRoleName hname pname callableId ord
      let (k', r', _) ← ensureRole roleKeys roles
        (RoleKeyV1.accountParam callableId ord) rname accountBoundRoleConstraintV1
      roleKeys := k'
      roles := r'
    -- Synthetic vault/caller roles are ensured at first meta use so global
    -- first-use order matches dense roleId assignment (Plan first-use gate).
    -- For token.transfer, the handlerCaller role is not a CPI meta but is
    -- still needed as the ATA ensure payer (outer signer). Ensure it before
    -- sites so it gets a dense global roleId in handler-local order.
    let tokenTransferNeedsCaller :=
      hSites.any (fun s => s.qn == "pf.assets.token.transfer")
    if tokenTransferNeedsCaller then
      match findRoleId? roleKeys RoleKeyV1.handlerCaller with
      | some _ => pure ()
      | none =>
          let (kC, rC, _) ← ensureRole roleKeys roles
            RoleKeyV1.handlerCaller "pf_caller" handlerCallerRoleConstraintV1
          roleKeys := kC
          roles := rC
    let mut siteIdsForHandler : Array Nat := #[]
    for site in hSites do
      let siteId := builtSites.size
      -- pf.assets APIs are not in the frozen callee package QN lists; resolve
      -- package by fixedProgram id so catalog digests stay stable.
      let pkg ← match findCalleePackage? site.api.fixedProgram with
        | some p => pure p
        | none => deriveFail s!"missing package '{site.api.fixedProgram}'"
      let (k1, r1, programRoleId) ← ensureRole roleKeys roles
        (RoleKeyV1.fixedProgram site.api.fixedProgram)
        (packageRoleName site.api.fixedProgram) calleeRoleConstraintV1
      roleKeys := k1
      roles := r1
      for metaSpec in site.api.metas do
        match metaSpec.binding with
        | MetaBinding.fixedProgram packageId =>
            let (k2, r2, _) ← ensureRole roleKeys roles
              (RoleKeyV1.fixedProgram packageId)
              (packageRoleName packageId) calleeRoleConstraintV1
            roleKeys := k2
            roles := r2
        | MetaBinding.vaultPda =>
            let (kV, rV, _) ← ensureRole roleKeys roles
              RoleKeyV1.vaultPda "pf_vault" vaultRoleConstraintV1
            roleKeys := kV
            roles := rV
        | MetaBinding.handlerCaller =>
            let (kC, rC, _) ← ensureRole roleKeys roles
              RoleKeyV1.handlerCaller "pf_caller" handlerCallerRoleConstraintV1
            roleKeys := kC
            roles := rC
        | MetaBinding.vaultAta =>
            let (kA, rA, _) ← ensureRole roleKeys roles
              RoleKeyV1.vaultAta "pf_vault_ata" vaultAtaRoleConstraintV1
            roleKeys := kA
            roles := rA
        | MetaBinding.dstAta =>
            let (kD, rD, _) ← ensureRole roleKeys roles
              RoleKeyV1.dstAta "pf_dst_ata" dstAtaRoleConstraintV1
            roleKeys := kD
            roles := rD
        | MetaBinding.arg _ => pure ()
      let mut principalRoleByArgIndex : Array (Nat × Nat) := #[]
      for (argIdx, ord) in site.principalParams do
        match findRoleId? roleKeys (RoleKeyV1.accountParam callableId ord) with
        | some rid =>
            principalRoleByArgIndex := principalRoleByArgIndex.push (argIdx, rid)
        | none =>
            deriveFail s!"principal role missing for callable {callableId} param {ord}"
      let mut fixedRoleByPackage : Array (String × Nat) := #[]
      match findRoleId? roleKeys (RoleKeyV1.fixedProgram site.api.fixedProgram) with
      | some rid =>
          fixedRoleByPackage :=
            fixedRoleByPackage.push (site.api.fixedProgram, rid)
      | none => deriveFail "program role missing after ensure"
      for metaSpec in site.api.metas do
        match metaSpec.binding with
        | MetaBinding.fixedProgram packageId =>
            unless fixedRoleByPackage.any (fun p => p.1 == packageId) do
              match findRoleId? roleKeys (RoleKeyV1.fixedProgram packageId) with
              | some rid =>
                  fixedRoleByPackage := fixedRoleByPackage.push (packageId, rid)
              | none => deriveFail s!"fixed role missing for '{packageId}'"
        | MetaBinding.arg _ | MetaBinding.vaultPda | MetaBinding.handlerCaller
        | MetaBinding.vaultAta | MetaBinding.dstAta =>
            pure ()
      let vaultRoleId? := findRoleId? roleKeys RoleKeyV1.vaultPda
      let callerRoleId? := findRoleId? roleKeys RoleKeyV1.handlerCaller
      let vaultAtaRoleId? := findRoleId? roleKeys RoleKeyV1.vaultAta
      let dstAtaRoleId? := findRoleId? roleKeys RoleKeyV1.dstAta
      let sitePlan ← buildSiteBindings site principalRoleByArgIndex
        fixedRoleByPackage vaultRoleId? callerRoleId?
        vaultAtaRoleId? dstAtaRoleId?
        programRoleId pkg.programId siteId handlerId
      builtSites := builtSites.push sitePlan
      siteIdsForHandler := siteIdsForHandler.push siteId

    -- Local ABI role order must match Plan `deriveHandlerRoleIds`:
    -- state → consumed accountParameter (param ordinal) → per-site program
    -- then fixedProgram/vaultPda/handlerCaller metas in site/meta source order.
    let mut localRoles : Array Nat := #[]
    let pushUnique (acc : Array Nat) (id : Nat) : Array Nat :=
      if acc.any (· == id) then acc else acc.push id
    match stateRoleId? with
    | some rid => localRoles := pushUnique localRoles rid
    | none => pure ()
    for ord in sortedOrds do
      match findRoleId? roleKeys (RoleKeyV1.accountParam callableId ord) with
      | some rid => localRoles := pushUnique localRoles rid
      | none => pure ()
    -- For token.transfer, the auto-created handlerCaller (ATA ensure payer)
    -- must appear in localRoles with outerSigner before sites. For deposit,
    -- handlerCaller is a CPI meta and is added in the site/meta loop below.
    -- Use a conditional to avoid changing role order for deposit handlers.
    if tokenTransferNeedsCaller then
      match findRoleId? roleKeys RoleKeyV1.handlerCaller with
      | some rid => localRoles := pushUnique localRoles rid
      | none => pure ()
    for siteId in siteIdsForHandler do
      let site : CpiSitePlanV1 ← getArr builtSites siteId "builtSites"
      localRoles := pushUnique localRoles site.programRoleId
      for metaSlot in site.metas do
        match metaSlot.spec.binding with
        | MetaBinding.fixedProgram _ | MetaBinding.vaultPda
        | MetaBinding.handlerCaller | MetaBinding.vaultAta | MetaBinding.dstAta =>
            localRoles := pushUnique localRoles metaSlot.roleId
        | MetaBinding.arg _ => pure ()

    let mut uses : Array HandlerAccountUseV1 := #[]
    for (roleId, position) in localRoles.zipIdx do
      let isState : Bool :=
        match stateRoleId? with
        | some sid => roleId == sid
        | none => false
      let isHandlerCallerRole : Bool :=
        match findRoleId? roleKeys RoleKeyV1.handlerCaller with
        | some rid => roleId == rid
        | none => false
      let (directSigner, directWritable) :=
        if isState then directStatePrivileges mode else (false, false)
      let mut signer := directSigner
      let mut writable := directWritable
      for siteId in siteIdsForHandler do
        let site : CpiSitePlanV1 ← getArr builtSites siteId "builtSites"
        let (sg, wr) :=
          siteRolePrivilege site.metas site.outerOnlyAccounts roleId
        -- ADR-0030 E1b: handlerCaller (ATA ensure payer) is not a CPI meta on
        -- token.transfer sites, but must contribute outerSigner+writable.
        let (sg2, wr2) :=
          if isHandlerCallerRole && site.qn == "pf.assets.token.transfer" then
            (true, true)
          else (sg, wr)
        if sg2 then signer := true
        if wr2 then writable := true
      uses := uses.push {
        position
        roleId
        directSignerContribution := directSigner
        directWritableContribution := directWritable
        outerSigner := signer
        outerWritable := writable
      }

    -- Deposit caller convention: handlers that use deposit must have exactly
    -- one outer signer role (the synthetic pf_caller).
    if needsCaller then
      let outerSignerCount := uses.foldl (fun n u =>
        if u.outerSigner then n + 1 else n) 0
      unless outerSignerCount == 1 do
        deriveFail
          s!"CPI derive: handler '{hname}' deposit requires exactly one outer signer (caller), got {outerSignerCount}"

    for siteId in siteIdsForHandler do
      let site : CpiSitePlanV1 ← getArr builtSites siteId "builtSites"
      builtSites := builtSites.set! siteId {
        site with accountInfoRoleIds := uses.map (·.roleId)
      }

    handlers := handlers.push {
      handlerId
      callableId
      name := hname
      mode
      accountUses := uses
      cpiSiteIds := siteIdsForHandler
    }

  -- Plan carries a single extensionRequirement field: prefer solana.cpi.accounts
  -- when present (L2 / dual), else pf.assets (L1-only TipJar path).
  let extensionRequirement ←
    if hasSolanaCpiExtensionRow data then
      mapExcept expectedExtensionRequirementV1 "extension requirement"
    else if hasPfAssetsExtensionRow data then
      match pfAssetsExtensionRequirementV1 with
      | .ok r => pure r
      | .error e => deriveFail s!"pf.assets extension seed: {e}"
    else
      mapExcept expectedExtensionRequirementV1 "extension requirement"

  let components := data.qualifiedName.components.toArray
  let qnTail ← match components.back? with
    | some n => pure n
    | none => deriveFail "CPI derive: empty program qualifiedName"
  unless programName == qnTail do
    deriveFail
      s!"CPI derive: artifactProgramName '{programName}' diverges from semantic QN tail '{qnTail}'"

  pure {
    schema := planSchemaV1
    profileId := profileIdV1
    profileDigest := snapshot.profileDigest
    extensionRequirement
    calleeCatalogDigest := snapshot.catalogDigest
    programName
    stateSchemas
    pdaRules := frozenPdaRulesV1
    accountRoles := roles
    handlers
    cpiSites := builtSites
    computeAssumptions := snapshot.computeAssumptions
  }

/-- Sole #118 lane A derive: preflight carrier → authority Plan carrier.
    Uses frozen profile/catalog digests + frozenComputeAssumptionsV1. -/
def deriveSolanaCpiPlanFromPreflightV1
    (preflight : ResolvedSolanaCpiPreflightV1) :
    CompileResult SolanaCpiPreflightPlanV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf preflight do
    deriveFail "CPI derive requires activationDenied preflight carrier"
  let selection := ResolvedSolanaCpiPreflightV1.selectionOf preflight
  unless selection.targetId == TargetId.solana &&
      selection.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1 do
    deriveFail "CPI derive selection must be solana + solana-sbpf-cpi-elf-v1"
  let compiled := ResolvedSolanaCpiPreflightV1.compiledOf preflight
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok v => pure v
    | .error _ =>
        deriveFail "CPI derive: retained SemanticProgramV1 failed structure validation"
  let profileDigest ← mapExcept expectedProfileDigestV1 "profile digest"
  let catalogDigest ← mapExcept expectedCatalogDigestV1 "catalog digest"
  let programName := CompiledSemanticV1.artifactProgramNameOf compiled
  let candidate ← deriveSolanaCpiPlanCandidateCoreV1 data programName {
    profileDigest
    catalogDigest
    computeAssumptions := frozenComputeAssumptionsV1
    productApiFilter := false
  }
  let plan ← validateSolanaCpiPlanV1 candidate
  pure (SolanaCpiPreflightPlanV1.mk preflight plan)

/-- Sole #125 product derive: product capability → product Plan carrier.
    Uses active profile/catalog digests + activeComputeAssumptionsV1 and
    product API filter (companion FC). -/
def deriveSolanaCpiPlanFromProductCapabilityV1
    (capability : ResolvedSolanaCpiProductCapabilityV1) :
    CompileResult SolanaCpiProductPlanV1 := do
  unless !ResolvedSolanaCpiProductCapabilityV1.activationDeniedOf capability do
    deriveFail "CPI product derive rejects activationDenied product capability"
  let selection := ResolvedSolanaCpiProductCapabilityV1.selectionOf capability
  unless selection.targetId == TargetId.solana &&
      selection.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1 do
    deriveFail "CPI product derive selection must be solana + solana-sbpf-cpi-elf-v1"
  let compiled := ResolvedSolanaCpiProductCapabilityV1.compiledOf capability
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok v => pure v
    | .error _ =>
        deriveFail
          "CPI product derive: retained SemanticProgramV1 failed structure validation"
  let profileDigest ← mapExcept expectedActiveProfileDigestV1 "active profile digest"
  let catalogDigest ← mapExcept expectedActiveCatalogDigestV1 "active catalog digest"
  let programName := CompiledSemanticV1.artifactProgramNameOf compiled
  let candidate ← deriveSolanaCpiPlanCandidateCoreV1 data programName {
    profileDigest
    catalogDigest
    computeAssumptions := activeComputeAssumptionsV1
    productApiFilter := true
  }
  let plan ← validateSolanaCpiProductPlanV1 candidate
  checkSolanaCpiProductMaterializationEligibilityV1 plan
  pure (SolanaCpiProductPlanV1.mk capability plan)

end ProofForgeV2.Targets.Solana.CpiV1

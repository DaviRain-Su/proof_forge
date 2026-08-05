/-
  ProofForgeV2.Targets.Solana.CpiTokenIRV1 — #122 classic Token CPI IR.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole mint: `resolveSolanaCpiTokenIRV1`. Consumes only private Semantic-bound
  `SolanaCpiPreflightPlanV1` (NOT `ResolvedSolanaCpiPreflightIRV1`, which
  rejects classicTokenAccount/classicTokenMint). Freshly derives/joins
  validated CpiIR and mints private `ResolvedSolanaCpiTokenIRV1`.

  * admits only `solana.token.transferChecked` and
    `solana.token.transferCheckedPda`;
  * single-block straight-line initializer/entry/view;
  * narrow public Principal/UInt64/UInt8 + state/literal/checked add/return;
  * transferChecked: data `0c||amount:u64le||decimals:u8` = 10B; metas source
    writable, mint readonly, destination writable, authority outer/CPI signer;
    zero signer groups;
  * transferCheckedPda: same 10B data; metas source/mint/destination +
    authorityPda CPI signer group0 outer non-signer; seedAuthority outer-only
    business signer; canonical recipe current-program-tagged-v1;
  * Token package exact token-classic-v1 / frozen classic program id /
    loader-v3-sbpf / artifactBinding.absent (package-owned locked ELF blocker);
  * per site: siteArgChecks → siteChecks → invoke (source order);
  * rejects Token-2022/dynamic callee/companion/System/ATA/schedule/
    constants/invariants/multiblock/loops;
  * rejects bump literal 0 on transferCheckedPda.

  Public structural Plan/IR cannot mint this carrier. No OutputFile.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.LowerSemanticV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.Solana

/-! ## Schema -/

def tokenIrSchemaV1 : String := "proof-forge.solana.cpi-token-ir.v1"
def tokenIrDigestDomainV1 : String := "pf.solana.cpi-token-ir.v1"

/-- UInt64 value sources for amount / seedTag. -/
inductive CpiTokenU64SourceV1 where
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  | literal (value : UInt64)
  deriving BEq, Repr, Inhabited

/-- UInt8 value sources for decimals / bump (bump literal 0 rejected at IR mint). -/
inductive CpiTokenU8SourceV1 where
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  | literal (value : UInt8)
  deriving BEq, Repr, Inhabited

/-- One CPI meta binding to a handler-local role. -/
structure CpiTokenMetaV1 where
  metaIndex : Nat
  roleId : Nat
  localIndex : Nat
  cpiWritable : Bool
  cpiSigner : Bool
  signerGroupId : Option Nat
  deriving BEq, Repr, Inhabited

/-- Exact Semantic Principal → callable parameter → role → dense local join. -/
structure CpiTokenPrincipalBindingV1 where
  argIndex : Nat
  semanticValueId : Nat
  paramOrdinal : Nat
  roleId : Nat
  localIndex : Nat
  deriving BEq, Repr, Inhabited

/-- Outer-only account binding (seedAuthority for transferCheckedPda). -/
structure CpiTokenOuterOnlyBindingV1 where
  outerOnlyIndex : Nat
  roleId : Nat
  localIndex : Nat
  outerSigner : Bool
  outerWritable : Bool
  deriving BEq, Repr, Inhabited

/-- Closed site-arg preflight (Token APIs currently empty; slot reserved). -/
inductive CpiTokenArgCheckV1 where
  | unusedPlaceholder
  deriving BEq, Repr, Inhabited

/-- Token API kind. -/
inductive CpiTokenKindV1 where
  | transferChecked
  | transferCheckedPda
  deriving BEq, Repr, Inhabited

/-- Site-local Token invoke (transferChecked or transferCheckedPda only). -/
structure CpiTokenInvokeV1 where
  siteId : Nat
  kind : CpiTokenKindV1
  qn : String
  packageId : String
  programLocalIndex : Nat
  dataLen : Nat
  source : CpiTokenPrincipalBindingV1
  mint : CpiTokenPrincipalBindingV1
  destination : CpiTokenPrincipalBindingV1
  /-- transferChecked authority; none for Pda. -/
  authority : Option CpiTokenPrincipalBindingV1
  /-- transferCheckedPda authorityPda; none for transferChecked. -/
  authorityPda : Option CpiTokenPrincipalBindingV1
  /-- transferCheckedPda seedAuthority; none for transferChecked. -/
  seedAuthority : Option CpiTokenPrincipalBindingV1
  seedTag : Option CpiTokenU64SourceV1
  bump : Option CpiTokenU8SourceV1
  amount : CpiTokenU64SourceV1
  decimals : CpiTokenU8SourceV1
  metas : Array CpiTokenMetaV1
  outerOnly : Array CpiTokenOuterOnlyBindingV1
  /-- none for transferChecked; some 0 for transferCheckedPda. -/
  signerGroupId : Option Nat
  /-- none for transferChecked; some current-program-tagged-v1 for Pda. -/
  pdaRule : Option String
  accountInfoCount : Nat
  deriving BEq, Repr

/-- Closed Token site-time predicate: generic preflight ops + exact SPL Token
    field joins. Field constructors carry dense localIndex (and value sources),
    never free-form strings — IR mint exact-joins against invoke Principal/
    decimals bindings. -/
inductive CpiTokenSiteCheckV1 where
  | generic (op : CpiPreflightOpV1)
  /-- Token Account.state @ data[108] == 1 (Initialized; reject 0/2). -/
  | tokenAccountStateInitialized (localIndex : Nat)
  /-- Token Account.mint @ data[0..32] == mint role key. -/
  | tokenAccountMintEqualsRole (accountLocalIndex mintLocalIndex : Nat)
  /-- Token Account.owner @ data[32..64] == authority/authorityPda role key. -/
  | tokenAccountOwnerEqualsRole (accountLocalIndex ownerLocalIndex : Nat)
  /-- Token Account.delegate COption tag @ data[72..76] u32le == 0 (None).
      Does not constrain delegate payload / is_native / close_authority. -/
  | tokenAccountDelegateNone (localIndex : Nat)
  /-- Mint.is_initialized @ data[45] == 1. -/
  | tokenMintInitialized (localIndex : Nat)
  /-- Mint.decimals @ data[44] == supplied decimals (param or literal). -/
  | tokenMintDecimalsEquals (localIndex : Nat) (decimals : CpiTokenU8SourceV1)
  deriving BEq, Repr

/-- Ordered body operations after handler-entry global preflight. -/
inductive CpiTokenBodyOpV1 where
  | loadParamU64 (tempId : Nat) (ixDataOffset : Nat)
  | loadParamU8 (tempId : Nat) (ixDataOffset : Nat)
  | loadLiteralU64 (tempId : Nat) (value : UInt64)
  | loadLiteralU8 (tempId : Nat) (value : UInt8)
  | stateLoadU64 (tempId : Nat) (stateLocalIndex : Nat) (byteOffset : Nat)
  | checkedAddU64 (dstTemp lhsTemp rhsTemp : Nat)
  | stateStoreU64 (stateLocalIndex : Nat) (byteOffset : Nat) (srcTemp : Nat)
    (writeInitializedMarker : Bool) (initializedMarker : UInt64)
  /-- Site-arg preflight (empty for Token APIs; preserves siteArgChecks→siteChecks→invoke). -/
  | siteArgChecks (siteId : Nat) (checks : Array CpiTokenArgCheckV1)
  /-- Site-time account predicates (must run immediately before invoke). -/
  | siteChecks (siteId : Nat) (ops : Array CpiTokenSiteCheckV1)
  | invokeToken (invoke : CpiTokenInvokeV1)
  | returnU64 (srcTemp : Nat)
  | returnNone
  deriving BEq, Repr, Inhabited

structure CpiTokenHandlerIRV1 where
  handlerId : Nat
  callableId : Nat
  name : String
  mode : HandlerModeV1
  localRoleCount : Nat
  localRoleOrder : Array CpiIRRoleHandleV1
  accountParameterBindings : Array CpiPreflightAccountParamBindingV1
  probeIxDataLen : Nat
  entryGlobalOps : Array CpiPreflightOpV1
  bodyOps : Array CpiTokenBodyOpV1
  tempCount : Nat
  deriving BEq, Repr

structure SolanaCpiTokenIRCandidateV1 where
  schema : String
  sourcePlanDigest : Digest
  sourceIrDigest : Digest
  profileId : String
  profileDigest : Digest
  catalogDigest : Digest
  abiLayout : LoaderV3AbiLayoutV1
  maxOuterRoles : Nat
  maxFrameBytes : Nat
  handlers : Array CpiTokenHandlerIRV1
  deriving BEq

/-- Private resolved Token IR. Sole mint from Semantic-bound preflight Plan. -/
structure ResolvedSolanaCpiTokenIRV1 where
  private mk ::
  authority : SolanaCpiPreflightPlanV1
  candidate : SolanaCpiTokenIRCandidateV1
  canonicalBytes : ByteArray
  digest : Digest

namespace ResolvedSolanaCpiTokenIRV1

def authorityOf (r : ResolvedSolanaCpiTokenIRV1) : SolanaCpiPreflightPlanV1 :=
  r.authority
def candidateOf (r : ResolvedSolanaCpiTokenIRV1) : SolanaCpiTokenIRCandidateV1 :=
  r.candidate
def digestOf (r : ResolvedSolanaCpiTokenIRV1) : Digest :=
  r.digest
def canonicalBytesOf (r : ResolvedSolanaCpiTokenIRV1) : ByteArray :=
  r.canonicalBytes

end ResolvedSolanaCpiTokenIRV1

/-! ## Internals -/

private def tFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def mapExcept (e : Except String α) (ctx : String) : CompileResult α :=
  match e with
  | .ok v => pure v
  | .error msg => tFail s!"{ctx}: {msg}"

private def digestsEqual (left right : Digest) : Bool :=
  left.algorithm == right.algorithm && left.bytes == right.bytes

private def getArr (arr : Array α) (i : Nat) (ctx : String) : CompileResult α :=
  match arr[i]? with
  | some v => pure v
  | none => tFail s!"{ctx}: index {i} out of range"

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

private def isAnonUnit
    (types : Array TypeDeclV1) (typeId : TypeIdV1) : Bool :=
  match types[typeId.toNat]? with
  | some decl =>
      decl.name.isNone &&
        match decl.shape with
        | .unit => true
        | _ => false
  | none => false

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

private def decodeUInt64LE (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 8 do
    tFail s!"UInt64 valueBytes must be exact 8 bytes, got {bytes.size}"
  let mut n : Nat := 0
  for i in [0:8] do
    n := n + bytes[i]!.toNat * (Nat.pow 2 (8 * i))
  pure (UInt64.ofNat n)

private def decodeUInt8 (bytes : ByteArray) : CompileResult UInt8 := do
  unless bytes.size == 1 do
    tFail s!"UInt8 valueBytes must be exact 1 byte, got {bytes.size}"
  pure bytes[0]!

private def effectiveSigner (h : CpiIRRoleHandleV1) : Bool :=
  h.directSignerContribution || h.outerSigner

private def effectiveWritable (h : CpiIRRoleHandleV1) : Bool :=
  h.directWritableContribution || h.outerWritable

private def findStateSchema?
    (schemas : Array StateSchemaV1) (schemaId : Nat) : Option StateSchemaV1 :=
  schemas.find? (fun s => s.schemaId == schemaId)

private def packageContextOfKeyPolicy : RoleKeyPolicyV1 → Option String
  | .fixedProgram packageId => some packageId
  | .state _ | .accountParameter .. | .vaultPda | .handlerCaller | .vaultAta | .dstAta => none

private def requireTokenPackage : CompileResult FrozenCalleePackage := do
  match findCalleePackage? "token-classic-v1" with
  | none => tFail "token-classic-v1 missing from frozen callee catalog"
  | some package =>
      unless package.packageId == "token-classic-v1" do
        tFail "token package id diverged"
      unless package.programId == tokenClassicProgramIdV1 do
        tFail "token-classic-v1 program id must match frozen classic Token id"
      unless package.executionClass == .loaderV3Sbpf do
        tFail "token-classic-v1 executionClass must be loaderV3Sbpf"
      match package.artifactBinding with
      | .absent => pure ()
      | .runtimeNative _ =>
          tFail "token-classic-v1 must have artifactBinding.absent (locked ELF blocker)"
      unless package.admittedForMaterialization == false do
        tFail "token-classic-v1 must remain admittedForMaterialization=false"
      pure package

/-- Token-aware owner resolution. -/
private def resolveOwnerOps
    (localIndex : Nat)
    (owner : OwnerPolicy)
    (catalogPackageId? : Option String) :
    CompileResult (Array CpiPreflightOpV1) := do
  match owner with
  | .currentProgram =>
      pure #[.checkOwnerCurrentProgram localIndex]
  | .fixedProgram packageId =>
      match findCalleePackage? packageId with
      | some package =>
          pure #[.checkOwnerExact localIndex package.programId]
      | none =>
          tFail s!"owner fixedProgram package '{packageId}' missing from catalog"
  | .catalogExecutionClass =>
      let packageId ← match catalogPackageId? with
        | some id => pure id
        | none =>
            tFail "catalogExecutionClass owner requires a fixed-program package context"
      match findCalleePackage? packageId with
      | some package =>
          pure #[.checkOwnerExact localIndex
            (executionClassOwnerPubkeyV1 package.executionClass)]
      | none =>
          tFail s!"catalogExecutionClass package '{packageId}' missing from catalog"
  | .any => pure #[]
  | .closedPackages _ =>
      tFail "Token CPI IR rejects closedPackages owner (ATA deferred)"

private def resolveExecutableOps
    (localIndex : Nat) (exec : ExecutablePolicy) : Array CpiPreflightOpV1 :=
  match exec with
  | .required => #[.checkExecutableRequired localIndex]
  | .forbidden => #[.checkExecutableForbidden localIndex]

/-- Admit classic Token account/mint exact lengths; reject System-create/ATA. -/
private def resolveDataAndInitOps
    (localIndex : Nat)
    (mode : HandlerModeV1)
    (keyPolicy : RoleKeyPolicyV1)
    (data : DataPolicy)
    (init : InitializationPolicy)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult (Array CpiPreflightOpV1) := do
  match init with
  | .uninitializedOrIdempotentlyInitialized =>
      tFail "Token CPI IR rejects ATA initialization"
  | .uninitialized =>
      tFail "Token CPI IR rejects uninitialized accounts (System create deferred)"
  | .canonicalPda => pure ()
  | .initializerUninitializedOtherwiseInitialized
  | .initialized | .existing | .any | .catalogPackageAdmitted =>
      pure ()
  let mut ops : Array CpiPreflightOpV1 := #[]
  match data with
  | .notRead | .catalogProgram => pure ()
  | .exactLength bytes lamports =>
      ops := ops.push (.checkExactDataLen localIndex bytes)
      match lamports with
      | none => pure ()
      | some lam => ops := ops.push (.checkExactLamports localIndex lam)
  | .exactCounter bytes =>
      ops := ops.push (.checkExactDataLen localIndex bytes)
  | .proofForgeState =>
      let schemaId ← match keyPolicy with
        | .state sid => pure sid
        | _ => tFail "proofForgeState data requires RoleKeyPolicyV1.state"
      let schema ← match findStateSchema? stateSchemas schemaId with
        | some s => pure s
        | none => tFail s!"proofForgeState schemaId {schemaId} missing"
      ops := ops.push (.checkExactDataLen localIndex schema.exactDataLen)
      match init with
      | .initializerUninitializedOtherwiseInitialized =>
          match mode with
          | .initialize =>
              ops := ops.push (.checkStateHeaderZero localIndex)
          | .entry | .view =>
              ops := ops.push
                (.checkStateHeaderMarker localIndex schema.initializedMarker)
      | .initialized =>
          ops := ops.push
            (.checkStateHeaderMarker localIndex schema.initializedMarker)
      | .existing | .any | .catalogPackageAdmitted | .canonicalPda
      | .uninitialized => pure ()
      | _ => pure ()
  | .classicTokenAccount bytes state _mintEqualsArg _ownerEqualsArg _delegate =>
      -- Generic layer: exact 165B only. Field joins (state/mint/owner/delegate)
      -- are projected as CpiTokenSiteCheckV1 at siteChecks (invoke-bound).
      unless bytes == 165 do
        tFail s!"classicTokenAccount bytes must be 165, got {bytes}"
      unless state == "initialized-not-frozen" do
        tFail s!"classicTokenAccount state must be initialized-not-frozen, got '{state}'"
      ops := ops.push (.checkExactDataLen localIndex 165)
  | .classicTokenMint bytes state _decimalsEqualsArg =>
      -- Generic layer: exact 82B only. is_initialized/decimals field joins are
      -- projected as CpiTokenSiteCheckV1 at siteChecks with decimals source.
      unless bytes == 82 do
        tFail s!"classicTokenMint bytes must be 82, got {bytes}"
      unless state == "initialized" do
        tFail s!"classicTokenMint state must be initialized, got '{state}'"
      ops := ops.push (.checkExactDataLen localIndex 82)
  | .ataAccount .. =>
      tFail "Token CPI IR rejects ataAccount data"
  pure ops

private def resolveProvisioning (prov : ProvisioningPolicy) : CompileResult Unit := do
  match prov with
  | .none | .mustExist => pure ()
  | .systemCreateAccount =>
      tFail "Token CPI IR rejects systemCreateAccount provisioning"
  | .ataCreateIdempotent =>
      tFail "Token CPI IR rejects ataCreateIdempotent provisioning"

private def projectConstraintOps
    (localIndex : Nat)
    (mode : HandlerModeV1)
    (keyPolicy : RoleKeyPolicyV1)
    (constraint : AccountConstraint)
    (stateSchemas : Array StateSchemaV1)
    (catalogPackageIdOverride : Option String := none) :
    CompileResult (Array CpiPreflightOpV1) := do
  resolveProvisioning constraint.provisioning
  let packageCtx :=
    match catalogPackageIdOverride with
    | some id => some id
    | none => packageContextOfKeyPolicy keyPolicy
  let ownerOps ← resolveOwnerOps localIndex constraint.owner packageCtx
  let execOps := resolveExecutableOps localIndex constraint.executable
  let dataInitOps ← resolveDataAndInitOps localIndex mode keyPolicy
    constraint.data constraint.initialization stateSchemas
  pure (ownerOps ++ execOps ++ dataInitOps)

private def projectEntryGlobalOps
    (abi : LoaderV3AbiLayoutV1)
    (mode : HandlerModeV1)
    (handles : Array CpiIRRoleHandleV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult
      (Array CpiPreflightAccountParamBindingV1 × Array CpiPreflightOpV1) := do
  let n := handles.size
  unless n ≤ maxOuterRolesV1 do
    tFail s!"handler local role count {n} exceeds maxOuterRoles {maxOuterRolesV1}"
  let mut bindings : Array CpiPreflightAccountParamBindingV1 := #[]
  let mut ops : Array CpiPreflightOpV1 := #[]
  ops := ops.push (.expectLocalRoleCount n)
  for i in [0:n] do
    ops := ops.push (.abiVirtualWalk i)
    ops := ops.push (.checkMarker i abi.marker)
    ops := ops.push (.checkOriginalDataLen i abi.originalDataLenEntryValue)
    ops := ops.push (.checkBoolFlagsInRange i)
    ops := ops.push (.checkRentEpochMax i)
  for i in [0:n] do
    ops := ops.push (.checkPointerTableEntry i)
  if n > 0 then
    ops := ops.push (.checkPairwiseDistinctKeys n)
  for handle in handles do
    let i := handle.localIndex
    match handle.keyPolicy with
    | .fixedProgram packageId =>
        match findCalleePackage? packageId with
        | some package =>
            ops := ops.push (.checkExactKey i package.programId)
        | none =>
            tFail s!"fixedProgram package '{packageId}' missing from frozen catalog"
    | .accountParameter callableId paramOrdinal =>
        bindings := bindings.push {
          callableId
          paramOrdinal
          roleId := handle.roleId
          localIndex := i
        }
    | .state _ | .vaultPda | .handlerCaller | .vaultAta | .dstAta => pure ()
    let constraintOps ← projectConstraintOps i mode handle.keyPolicy
      handle.constraint stateSchemas
    ops := ops ++ constraintOps
    ops := ops.push (.checkEffectiveSigner i (effectiveSigner handle))
    ops := ops.push (.checkEffectiveWritable i (effectiveWritable handle))
  pure (bindings, ops)

/-- Non-Principal public params → packed probe offsets in declaration order. -/
private def buildParamIxLayout
    (types : Array TypeDeclV1) (callable : CallableV1) :
    CompileResult (Array (Nat × Nat × Nat) × Nat) := do
  let mut layout : Array (Nat × Nat × Nat) := #[]
  let mut offset : Nat := 8
  for (p, ord) in callable.params.zipIdx do
    unless p.visibility == VisibilityV1.public_ do
      tFail "Token CPI IR requires public parameters only"
    if isAnonPrincipal types p.typeId then
      pure ()
    else if anonUintWidth? types p.typeId == some 64 then
      layout := layout.push (ord, offset, 64)
      offset := offset + 8
    else if anonUintWidth? types p.typeId == some 8 then
      layout := layout.push (ord, offset, 8)
      offset := offset + 1
    else
      tFail
        s!"Token CPI IR admits only public Principal/UInt64/UInt8 params, got '{p.name}'"
  pure (layout, offset)

private def ixOffsetOfParam?
    (layout : Array (Nat × Nat × Nat)) (paramOrdinal : Nat) : Option (Nat × Nat) :=
  Id.run do
    for (ord, off, w) in layout do
      if ord == paramOrdinal then return some (off, w)
    return none

private def requireStraightLineCallable
    (callable : CallableV1) : CompileResult BlockV1 := do
  unless callable.blocks.size == 1 do
    tFail
      s!"Token CPI IR requires single-block straight-line callables (got {callable.blocks.size} blocks)"
  unless callable.entryBlock.toNat == 0 do
    tFail "Token CPI IR requires entryBlock == 0"
  unless callable.loopBounds.isEmpty do
    tFail "Token CPI IR rejects loopBounds (no back edges)"
  let blk ← getArr callable.blocks 0 "callable.blocks"
  unless blk.id.toNat == 0 do
    tFail "Token CPI IR requires sole block id == 0"
  unless blk.params.isEmpty do
    tFail "Token CPI IR rejects block parameters"
  pure blk

private def localIndexOfRole
    (handles : Array CpiIRRoleHandleV1) (roleId : Nat) : CompileResult Nat :=
  match handles.find? (fun h => h.roleId == roleId) with
  | some h => pure h.localIndex
  | none => tFail s!"roleId {roleId} missing from handler local roles"


/-- Resolve a frozen Principal arg name → dense localIndex via site.args role join. -/
private def principalLocalOfArgName
    (site : CpiIRSiteV1) (handles : Array CpiIRRoleHandleV1) (argName : String) :
    CompileResult Nat := do
  let arg ← match site.args.find? (fun a => a.spec.name == argName) with
    | some a => pure a
    | none =>
        tFail s!"site {site.siteId}: Principal arg '{argName}' missing for Token field join"
  unless arg.spec.type_ == FrozenValueType.principal do
    tFail s!"site {site.siteId}: arg '{argName}' is not Principal"
  let roleId ← match arg.roleId with
    | some rid => pure rid
    | none =>
        tFail s!"site {site.siteId}: arg '{argName}' has no roleId for Token field join"
  let li ← localIndexOfRole handles roleId
  unless li < handles.size do
    tFail s!"site {site.siteId}: arg '{argName}' localIndex out of range"
  pure li

/-- Project one classic Token Account field join suite (closed). -/
private def projectClassicTokenAccountFields
    (site : CpiIRSiteV1)
    (handles : Array CpiIRRoleHandleV1)
    (localIndex : Nat)
    (mintEqualsArg : Option String)
    (ownerEqualsArg : Option String)
    (delegate : Option String) :
    CompileResult (Array CpiTokenSiteCheckV1) := do
  let mut ops : Array CpiTokenSiteCheckV1 := #[]
  -- data[108] == 1 (Initialized; reject Uninitialized=0 / Frozen=2)
  ops := ops.push (.tokenAccountStateInitialized localIndex)
  match mintEqualsArg with
  | some name =>
      let mintLi ← principalLocalOfArgName site handles name
      ops := ops.push (.tokenAccountMintEqualsRole localIndex mintLi)
  | none => pure ()
  match ownerEqualsArg with
  | some name =>
      let ownerLi ← principalLocalOfArgName site handles name
      ops := ops.push (.tokenAccountOwnerEqualsRole localIndex ownerLi)
  | none => pure ()
  match delegate with
  | some "none" =>
      ops := ops.push (.tokenAccountDelegateNone localIndex)
  | some other =>
      tFail
        s!"site {site.siteId}: classicTokenAccount delegate constraint '{other}' unsupported (only 'none')"
  | none => pure ()
  pure ops

/-- Project classic Mint field joins (closed). -/
private def projectClassicTokenMintFields
    (site : CpiIRSiteV1)
    (localIndex : Nat)
    (decimalsEqualsArg : Option String)
    (decimalsSrc : CpiTokenU8SourceV1) :
    CompileResult (Array CpiTokenSiteCheckV1) := do
  let mut ops : Array CpiTokenSiteCheckV1 := #[]
  ops := ops.push (.tokenMintInitialized localIndex)
  match decimalsEqualsArg with
  | some "decimals" =>
      ops := ops.push (.tokenMintDecimalsEquals localIndex decimalsSrc)
  | some other =>
      tFail
        s!"site {site.siteId}: classicTokenMint decimalsEqualsArg '{other}' unsupported (only 'decimals')"
  | none => pure ()
  pure ops

/-- Site-time predicates in frozen sitePredicates order: generic owner/exec/len
    then exact Token field joins bound to peer role localIndex / decimals source. -/
private def projectSiteChecks
    (mode : HandlerModeV1)
    (handles : Array CpiIRRoleHandleV1)
    (site : CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1)
    (decimalsSrc : CpiTokenU8SourceV1) :
    CompileResult (Array CpiTokenSiteCheckV1) := do
  let mut ops : Array CpiTokenSiteCheckV1 := #[]
  for pred in site.sitePredicates do
    let handle ← match handles.find? (fun h => h.roleId == pred.roleId) with
      | some h => pure h
      | none =>
          tFail s!"site predicate roleId {pred.roleId} missing from handler locals"
    unless handle.localIndex < handles.size do
      tFail s!"site predicate roleId {pred.roleId} has out-of-range localIndex"
    let denseHandle ← getArr handles handle.localIndex "site predicate dense local handles"
    unless denseHandle.roleId == handle.roleId &&
        denseHandle.localIndex == handle.localIndex do
      tFail s!"site predicate roleId {pred.roleId} has non-dense local handle"
    let packageOverride : Option String :=
      match pred.source with
      | .callee => some site.packageId
      | .metaIndex _ | .outerOnlyIndex _ => none
    let genericOps ← projectConstraintOps handle.localIndex mode handle.keyPolicy
      pred.constraint stateSchemas packageOverride
    for g in genericOps do
      ops := ops.push (.generic g)
    -- Exact Token field joins after generic owner/exec/dataLen (closed).
    match pred.constraint.data with
    | .classicTokenAccount _bytes _state mintEq ownerEq delegate =>
        let fieldOps ← projectClassicTokenAccountFields site handles
          handle.localIndex mintEq ownerEq delegate
        ops := ops ++ fieldOps
    | .classicTokenMint _bytes _state decimalsEq =>
        let fieldOps ← projectClassicTokenMintFields site handle.localIndex
          decimalsEq decimalsSrc
        ops := ops ++ fieldOps
    | _ => pure ()
  pure ops

private def findLiteralU64?
    (types : Array TypeDeclV1) (callable : CallableV1) (vid : ValueIdV1) :
    Option UInt64 :=
  Id.run do
    for blk in callable.blocks do
      for instr in blk.instructions do
        match instr.result, instr.op with
        | some vd, .literal tid bytes =>
            if vd.valueId == vid && anonUintWidth? types tid == some 64 then
              if bytes.size == 8 then
                let mut n : Nat := 0
                for i in [0:8] do
                  n := n + bytes[i]!.toNat * (Nat.pow 2 (8 * i))
                return some (UInt64.ofNat n)
              else return none
        | _, _ => pure ()
    return none

private def findLiteralU8?
    (types : Array TypeDeclV1) (callable : CallableV1) (vid : ValueIdV1) :
    Option UInt8 :=
  Id.run do
    for blk in callable.blocks do
      for instr in blk.instructions do
        match instr.result, instr.op with
        | some vd, .literal tid bytes =>
            if vd.valueId == vid && anonUintWidth? types tid == some 8 then
              if bytes.size == 1 then
                return some bytes[0]!
              else return none
        | _, _ => pure ()
    return none

private def directPublicU64ParamOrdinal?
    (types : Array TypeDeclV1) (callable : CallableV1) (vid : ValueIdV1) :
    Option Nat :=
  Id.run do
    for (p, i) in callable.params.zipIdx do
      if p.valueId == vid && p.visibility == VisibilityV1.public_ &&
          anonUintWidth? types p.typeId == some 64 then
        return some i
    return none

private def directPublicU8ParamOrdinal?
    (types : Array TypeDeclV1) (callable : CallableV1) (vid : ValueIdV1) :
    Option Nat :=
  Id.run do
    for (p, i) in callable.params.zipIdx do
      if p.valueId == vid && p.visibility == VisibilityV1.public_ &&
          anonUintWidth? types p.typeId == some 8 then
        return some i
    return none

private def directPublicPrincipalParamOrdinal?
    (types : Array TypeDeclV1) (callable : CallableV1) (vid : ValueIdV1) :
    Option Nat :=
  Id.run do
    for (p, i) in callable.params.zipIdx do
      if p.valueId == vid && p.visibility == VisibilityV1.public_ &&
          isAnonPrincipal types p.typeId then
        return some i
    return none

private def resolvePrincipalAccountBinding
    (types : Array TypeDeclV1)
    (callable : CallableV1)
    (handles : Array CpiIRRoleHandleV1)
    (bindings : Array CpiPreflightAccountParamBindingV1)
    (site : CpiIRSiteV1)
    (argIndex : Nat)
    (vid : ValueIdV1) :
    CompileResult CpiTokenPrincipalBindingV1 := do
  let paramOrdinal ← match directPublicPrincipalParamOrdinal? types callable vid with
    | some ord => pure ord
    | none =>
        tFail s!"site {site.siteId} arg {argIndex}: expected bare direct public Principal parameter"
  let arg ← getArr site.args argIndex s!"site {site.siteId}.args"
  unless arg.spec.type_ == FrozenValueType.principal &&
      arg.spec.source == ArgumentSource.bareDirectPublicPrincipalParameter do
    tFail s!"site {site.siteId} arg {argIndex}: frozen Principal source diverged"
  unless arg.semanticValueId == vid.toNat do
    tFail s!"site {site.siteId} arg {argIndex}: Semantic ValueId diverged from Plan binding"
  let roleId ← match arg.roleId with
    | some rid => pure rid
    | none => tFail s!"site {site.siteId} arg {argIndex}: Principal roleId missing"
  let handle ← match handles.find? (fun h => h.roleId == roleId) with
    | some h => pure h
    | none => tFail s!"site {site.siteId} arg {argIndex}: roleId {roleId} missing from handler"
  unless handle.localIndex < handles.size do
    tFail s!"site {site.siteId} arg {argIndex}: localIndex out of range"
  let denseHandle ← getArr handles handle.localIndex "handler dense local handles"
  unless denseHandle.roleId == roleId && denseHandle.localIndex == handle.localIndex do
    tFail s!"site {site.siteId} arg {argIndex}: local handle is not dense/exact"
  match handle.keyPolicy with
  | .accountParameter callableId boundOrdinal =>
      unless callableId == callable.id.toNat && boundOrdinal == paramOrdinal do
        tFail s!"site {site.siteId} arg {argIndex}: account role does not bind the exact callable parameter"
  | _ =>
      tFail s!"site {site.siteId} arg {argIndex}: Principal role is not accountParameter-bound"
  let paramBindings := bindings.filter (fun b =>
    b.callableId == callable.id.toNat && b.paramOrdinal == paramOrdinal)
  unless paramBindings.size == 1 do
    tFail s!"site {site.siteId} arg {argIndex}: expected exactly one preflight binding for the parameter"
  let exactBinding ← getArr paramBindings 0 "Principal preflight parameter binding"
  unless exactBinding.roleId == roleId &&
      exactBinding.localIndex == handle.localIndex do
    tFail s!"site {site.siteId} arg {argIndex}: preflight binding role/local index diverged"
  pure {
    argIndex
    semanticValueId := vid.toNat
    paramOrdinal
    roleId
    localIndex := handle.localIndex
  }

private def resolveU64Source
    (types : Array TypeDeclV1) (callable : CallableV1)
    (layout : Array (Nat × Nat × Nat)) (vid : ValueIdV1) (ctx : String) :
    CompileResult CpiTokenU64SourceV1 := do
  match findLiteralU64? types callable vid with
  | some v => pure (.literal v)
  | none =>
      match directPublicU64ParamOrdinal? types callable vid with
      | some ord =>
          match ixOffsetOfParam? layout ord with
          | some (off, w) =>
              unless w == 64 do
                tFail s!"{ctx}: UInt64 param ordinal {ord} has wrong width slot"
              pure (.param ord off)
          | none =>
              tFail s!"{ctx}: UInt64 param ordinal {ord} missing from probe layout"
      | none =>
          tFail
            s!"{ctx}: admits only direct public UInt64 param or UInt64 literal"

private def resolveU8Source
    (types : Array TypeDeclV1) (callable : CallableV1)
    (layout : Array (Nat × Nat × Nat)) (vid : ValueIdV1) (ctx : String)
    (rejectZeroLiteral : Bool) :
    CompileResult CpiTokenU8SourceV1 := do
  match findLiteralU8? types callable vid with
  | some v =>
      if rejectZeroLiteral && v == 0 then
        tFail s!"{ctx}: bump literal 0 is rejected (canonical search is 255..1)"
      pure (.literal v)
  | none =>
      match directPublicU8ParamOrdinal? types callable vid with
      | some ord =>
          match ixOffsetOfParam? layout ord with
          | some (off, w) =>
              unless w == 8 do
                tFail s!"{ctx}: UInt8 param ordinal {ord} has wrong width slot"
              pure (.param ord off)
          | none =>
              tFail s!"{ctx}: UInt8 param ordinal {ord} missing from probe layout"
      | none =>
          tFail
            s!"{ctx}: admits only direct public UInt8 param or UInt8 literal"

private def projectMetas
    (handles : Array CpiIRRoleHandleV1) (site : CpiIRSiteV1) :
    CompileResult (Array CpiTokenMetaV1) := do
  let mut metas : Array CpiTokenMetaV1 := #[]
  for m in site.metas do
    let li ← localIndexOfRole handles m.roleId
    unless m.localHandleIndex == li do
      tFail s!"site {site.siteId} meta {m.metaIndex} local handle diverged"
    metas := metas.push {
      metaIndex := m.metaIndex
      roleId := m.roleId
      localIndex := li
      cpiWritable := m.spec.cpiWritable
      cpiSigner := m.spec.cpiSigner
      signerGroupId := m.spec.signerGroupId
    }
  pure metas

private def projectSiteArgChecks
    (site : CpiIRSiteV1) :
    CompileResult (Array CpiTokenArgCheckV1) := do
  unless site.preflight.isEmpty do
    tFail s!"site {site.siteId}: Token APIs require empty preflight"
  pure #[]

private def validateTokenSiteShape (site : CpiIRSiteV1) : CompileResult Unit := do
  unless site.packageId == "token-classic-v1" do
    tFail
      s!"Token CPI admits only token-classic-v1, got '{site.packageId}' at site {site.siteId}"
  unless site.programKey == tokenClassicProgramIdV1 do
    tFail s!"site {site.siteId}: Token program key must be classic Token id"
  unless site.instructionCodec.length == 10 do
    tFail s!"site {site.siteId}: Token dataLen must be 10"
  match site.qn with
  | "solana.token.transferChecked" =>
      unless site.pda == .none do
        tFail s!"transferChecked site {site.siteId} must have pda.none"
      unless site.signerGroups.isEmpty do
        tFail s!"transferChecked site {site.siteId} requires zero signer groups"
      unless site.outerOnlyAccounts.isEmpty do
        tFail s!"transferChecked site {site.siteId} requires empty outer-only"
      unless site.metas.size == 4 do
        tFail s!"transferChecked site {site.siteId} requires exactly four metas"
      unless site.args.size == 6 do
        tFail s!"transferChecked site {site.siteId} requires exactly six args"
      unless site.preflight.isEmpty do
        tFail s!"transferChecked site {site.siteId} must have empty preflight"
  | "solana.token.transferCheckedPda" =>
      match site.pda with
      | .signer rule targetArg seedAuthArg seedTagArg bumpArg signerArg =>
          unless rule == "current-program-tagged-v1" do
            tFail s!"site {site.siteId}: PDA rule must be current-program-tagged-v1"
          unless targetArg == "authorityPda" && seedAuthArg == "seedAuthority" &&
              seedTagArg == "seedTag" && bumpArg == "bump" &&
              signerArg == "authorityPda" do
            tFail s!"site {site.siteId}: PDA arg names must match frozen transferCheckedPda"
      | .none =>
          tFail s!"transferCheckedPda requires PDA signer use at site {site.siteId}"
      | .addressCheckOnly .. | .vaultPdaSigner _ =>
          tFail s!"Token CPI rejects addressCheckOnly at site {site.siteId}"
      unless site.signerGroups.size == 1 do
        tFail s!"site {site.siteId}: exact one signer group required"
      let group ← getArr site.signerGroups 0 s!"site {site.siteId}.signerGroups"
      unless group.id == 0 && group.metaArg == "authorityPda" &&
          group.pdaRule == "current-program-tagged-v1" do
        tFail s!"site {site.siteId}: signer group must be id0/authorityPda/current-program-tagged-v1"
      unless site.metas.size == 4 do
        tFail s!"site {site.siteId}: transferCheckedPda requires exactly four metas"
      unless site.outerOnlyAccounts.size == 1 do
        tFail s!"site {site.siteId}: transferCheckedPda requires exactly one outer-only"
      unless site.args.size == 9 do
        tFail s!"site {site.siteId}: transferCheckedPda requires exactly nine args"
      unless site.preflight.isEmpty do
        tFail s!"transferCheckedPda site {site.siteId} must have empty preflight"
  | other =>
      tFail
        s!"Token CPI admits only solana.token.transferChecked|transferCheckedPda, got '{other}'"

private def projectTokenHandler
    (abi : LoaderV3AbiLayoutV1)
    (data : SemanticProgramDataV1)
    (planHandler : HandlerPlanV1)
    (handles : Array CpiIRRoleHandleV1)
    (sites : Array CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult CpiTokenHandlerIRV1 := do
  let _tokenPkg ← requireTokenPackage
  let callable ← getArr data.callables planHandler.callableId "callables"
  unless callable.id.toNat == planHandler.callableId do
    tFail "handler callableId must equal Semantic callable.id"
  unless callable.blocks.size ≥ 1 do
    tFail "callable has no blocks"
  unless handles.size == planHandler.accountUses.size do
    tFail "handler local handle count must equal Plan accountUses size"
  for i in [0:handles.size] do
    let handle ← getArr handles i "handler local handles"
    let use ← getArr planHandler.accountUses i "handler accountUses"
    unless handle.handlerId == planHandler.handlerId &&
        handle.localIndex == i && use.position == i &&
        handle.roleId == use.roleId do
      tFail s!"handler {planHandler.handlerId} local handle order diverged at {i}"
  for site in sites do
    unless site.handlerId == planHandler.handlerId do
      tFail "site handlerId mismatch"
    validateTokenSiteShape site

  let blk ← requireStraightLineCallable callable
  let (paramLayout, probeIxDataLen) ← buildParamIxLayout data.types callable
  let (bindings, entryGlobalOps) ←
    projectEntryGlobalOps abi planHandler.mode handles stateSchemas

  let mut tempOf : Array (Nat × Nat) := #[]
  let mut nextTemp : Nat := 0
  let mut body : Array CpiTokenBodyOpV1 := #[]

  let lookupTemp (table : Array (Nat × Nat)) (vid : Nat) : Option Nat :=
    Id.run do
      for (v, t) in table do
        if v == vid then return some t
      return none

  let allocTemp (table : Array (Nat × Nat)) (next : Nat) (vid : Nat) :
      Nat × Array (Nat × Nat) × Nat :=
    match lookupTemp table vid with
    | some t => (t, table, next)
    | none =>
        let t := next
        (t, table.push (vid, t), next + 1)

  for (ord, off, w) in paramLayout do
    let p ← getArr callable.params ord "callable.params"
    let (t, tempOf', next') := allocTemp tempOf nextTemp p.valueId.toNat
    tempOf := tempOf'
    nextTemp := next'
    if w == 64 then
      body := body.push (.loadParamU64 t off)
    else
      body := body.push (.loadParamU8 t off)

  let stateInfo? : Option (Nat × StateSchemaV1) :=
    Id.run do
      for h in handles do
        match h.keyPolicy with
        | .state sid =>
            match findStateSchema? stateSchemas sid with
            | some s => return some (h.localIndex, s)
            | none => return none
        | _ => pure ()
      return none

  for (instr, instrIdx) in blk.instructions.zipIdx do
    match instr.op with
    | .literal tid bytes =>
        let some vd := instr.result |
          tFail "literal must produce a result"
        match anonUintWidth? data.types tid with
        | some 64 =>
            let v ← decodeUInt64LE bytes
            let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
            tempOf := tempOf'
            nextTemp := next'
            body := body.push (.loadLiteralU64 t v)
        | some 8 =>
            let v ← decodeUInt8 bytes
            let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
            tempOf := tempOf'
            nextTemp := next'
            body := body.push (.loadLiteralU8 t v)
        | _ =>
            tFail "Token CPI IR admits only UInt64/UInt8 literals in body"
    | .stateLoad stateId =>
        let some vd := instr.result |
          tFail "stateLoad must produce a result"
        let (stateLocal, schema) ← match stateInfo? with
          | some s => pure s
          | none => tFail "stateLoad without state role"
        unless stateId.toNat == 0 do
          tFail "Token CPI IR first slice admits only stateId 0"
        unless schema.exactDataLen == 16 do
          tFail "stateLoad requires single UInt64 state layout"
        let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
        tempOf := tempOf'
        nextTemp := next'
        body := body.push (.stateLoadU64 t stateLocal 8)
    | .stateStore stateId value =>
        let (stateLocal, schema) ← match stateInfo? with
          | some s => pure s
          | none => tFail "stateStore without state role"
        unless stateId.toNat == 0 do
          tFail "Token CPI IR first slice admits only stateId 0"
        let src ← match lookupTemp tempOf value.toNat with
          | some t => pure t
          | none =>
              match directPublicU64ParamOrdinal? data.types callable value with
              | some ord =>
                  match ixOffsetOfParam? paramLayout ord with
                  | some (off, w) =>
                      unless w == 64 do
                        tFail "stateStore value width diverged"
                      let (t, tempOf', next') := allocTemp tempOf nextTemp value.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadParamU64 t off)
                      pure t
                  | none => tFail "stateStore value param missing from probe layout"
              | none =>
                  match findLiteralU64? data.types callable value with
                  | some lit =>
                      let (t, tempOf', next') := allocTemp tempOf nextTemp value.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadLiteralU64 t lit)
                      pure t
                  | none =>
                      tFail s!"stateStore value ValueId {value} is not materialised"
        let writeMarker := planHandler.mode == .initialize
        body := body.push
          (.stateStoreU64 stateLocal 8 src writeMarker schema.initializedMarker)
    | .binary opKind lhs rhs =>
        let some vd := instr.result |
          tFail "binary must produce a result"
        match opKind with
        | BinaryOpV1.add =>
            let l ← match lookupTemp tempOf lhs.toNat with
              | some t => pure t
              | none => tFail s!"checkedAdd lhs ValueId {lhs} not materialised"
            let r ← match lookupTemp tempOf rhs.toNat with
              | some t => pure t
              | none => tFail s!"checkedAdd rhs ValueId {rhs} not materialised"
            let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
            tempOf := tempOf'
            nextTemp := next'
            body := body.push (.checkedAddU64 t l r)
        | _ =>
            tFail "Token CPI IR first slice admits only checked UInt64 add in body"
    | .externalCall effectId callee args =>
        let qnComps ← mapExcept (renderQualifiedNameComponents callee) "callee QN"
        let qn := String.intercalate "." qnComps.toList
        unless qn == "solana.token.transferChecked" ||
            qn == "solana.token.transferCheckedPda" do
          tFail
            s!"Token CPI admits only token.transferChecked|transferCheckedPda, got '{qn}'"
        let site ← match sites.find? (fun s =>
            s.anchor.callableId == planHandler.callableId &&
              s.anchor.blockId == blk.id.toNat &&
              s.anchor.instructionIndex == instrIdx &&
              s.anchor.effectId == effectId.toNat) with
          | some s => pure s
          | none =>
              tFail
                s!"ExternalCall at instr {instrIdx} has no matching CPI site anchor"
        unless site.qn == qn do
          tFail "site QN diverges from Semantic ExternalCall"
        unless site.packageId == "token-classic-v1" do
          tFail "ExternalCall package must be token-classic-v1"
        let programLocal ← localIndexOfRole handles site.programRoleId
        unless site.programHandleIndex == programLocal do
          tFail s!"site {site.siteId} program handle index diverged"
        let metas ← projectMetas handles site
        if qn == "solana.token.transferChecked" then
          unless args.size == 6 && site.args.size == 6 do
            tFail "transferChecked requires exactly 6 Semantic and Plan args"
          let sourceVid ← getArr args 0 "externalCall.args"
          let sourceBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 0 sourceVid
          let mintVid ← getArr args 1 "externalCall.args"
          let mintBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 1 mintVid
          let destVid ← getArr args 2 "externalCall.args"
          let destBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 2 destVid
          let authVid ← getArr args 3 "externalCall.args"
          let authBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 3 authVid
          let amountVid ← getArr args 4 "externalCall.args"
          let amountArg ← getArr site.args 4 s!"site {site.siteId}.args"
          unless amountArg.semanticValueId == amountVid.toNat &&
              amountArg.roleId.isNone &&
              amountArg.spec.type_ == FrozenValueType.uint64 do
            tFail s!"site {site.siteId} amount binding diverged"
          let amountSrc ← resolveU64Source data.types callable paramLayout amountVid
            s!"site {site.siteId} amount"
          let decimalsVid ← getArr args 5 "externalCall.args"
          let decimalsArg ← getArr site.args 5 s!"site {site.siteId}.args"
          unless decimalsArg.semanticValueId == decimalsVid.toNat &&
              decimalsArg.roleId.isNone &&
              decimalsArg.spec.type_ == FrozenValueType.uint8 do
            tFail s!"site {site.siteId} decimals binding diverged"
          let decimalsSrc ← resolveU8Source data.types callable paramLayout decimalsVid
            s!"site {site.siteId} decimals" false
          -- Meta[0] source writable non-signer (outer writable)
          let meta0 ← getArr site.metas 0 s!"site {site.siteId}.metas"
          unless meta0.metaIndex == 0 &&
              meta0.roleId == sourceBinding.roleId &&
              meta0.localHandleIndex == sourceBinding.localIndex &&
              meta0.spec.cpiWritable == true &&
              meta0.spec.cpiSigner == false &&
              meta0.spec.outerSignerContribution == false &&
              meta0.spec.outerWritableContribution == true &&
              meta0.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId} source meta must be writable outer non-signer"
          -- Meta[1] mint readonly
          let meta1 ← getArr site.metas 1 s!"site {site.siteId}.metas"
          unless meta1.metaIndex == 1 &&
              meta1.roleId == mintBinding.roleId &&
              meta1.localHandleIndex == mintBinding.localIndex &&
              meta1.spec.cpiWritable == false &&
              meta1.spec.cpiSigner == false &&
              meta1.spec.outerSignerContribution == false &&
              meta1.spec.outerWritableContribution == false &&
              meta1.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId} mint meta must be readonly non-signer"
          -- Meta[2] destination writable non-signer
          let meta2 ← getArr site.metas 2 s!"site {site.siteId}.metas"
          unless meta2.metaIndex == 2 &&
              meta2.roleId == destBinding.roleId &&
              meta2.localHandleIndex == destBinding.localIndex &&
              meta2.spec.cpiWritable == true &&
              meta2.spec.cpiSigner == false &&
              meta2.spec.outerSignerContribution == false &&
              meta2.spec.outerWritableContribution == true &&
              meta2.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId} destination meta must be writable outer non-signer"
          -- Meta[3] authority CPI+outer signer non-writable
          let meta3 ← getArr site.metas 3 s!"site {site.siteId}.metas"
          unless meta3.metaIndex == 3 &&
              meta3.roleId == authBinding.roleId &&
              meta3.localHandleIndex == authBinding.localIndex &&
              meta3.spec.cpiWritable == false &&
              meta3.spec.cpiSigner == true &&
              meta3.spec.outerSignerContribution == true &&
              meta3.spec.outerWritableContribution == false &&
              meta3.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId} authority meta must be outer/CPI signer non-writable"
          let argChecks ← projectSiteArgChecks site
          let siteOps ← projectSiteChecks planHandler.mode handles site stateSchemas
            decimalsSrc
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeToken {
            siteId := site.siteId
            kind := .transferChecked
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 10
            source := sourceBinding
            mint := mintBinding
            destination := destBinding
            authority := some authBinding
            authorityPda := none
            seedAuthority := none
            seedTag := none
            bump := none
            amount := amountSrc
            decimals := decimalsSrc
            metas
            outerOnly := #[]
            signerGroupId := none
            pdaRule := none
            accountInfoCount := handles.size
          })
        else
          -- transferCheckedPda
          unless args.size == 9 && site.args.size == 9 do
            tFail "transferCheckedPda requires exactly 9 Semantic and Plan args"
          let sourceVid ← getArr args 0 "externalCall.args"
          let sourceBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 0 sourceVid
          let mintVid ← getArr args 1 "externalCall.args"
          let mintBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 1 mintVid
          let destVid ← getArr args 2 "externalCall.args"
          let destBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 2 destVid
          let authPdaVid ← getArr args 3 "externalCall.args"
          let authPdaBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 3 authPdaVid
          let seedAuthVid ← getArr args 4 "externalCall.args"
          let seedAuthBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 4 seedAuthVid
          let seedTagVid ← getArr args 5 "externalCall.args"
          let seedTagArg ← getArr site.args 5 s!"site {site.siteId}.args"
          unless seedTagArg.semanticValueId == seedTagVid.toNat &&
              seedTagArg.roleId.isNone &&
              seedTagArg.spec.type_ == FrozenValueType.uint64 do
            tFail s!"site {site.siteId} seedTag binding diverged"
          let seedTagSrc ← resolveU64Source data.types callable paramLayout seedTagVid
            s!"site {site.siteId} seedTag"
          let bumpVid ← getArr args 6 "externalCall.args"
          let bumpArg ← getArr site.args 6 s!"site {site.siteId}.args"
          unless bumpArg.semanticValueId == bumpVid.toNat &&
              bumpArg.roleId.isNone &&
              bumpArg.spec.type_ == FrozenValueType.uint8 do
            tFail s!"site {site.siteId} bump binding diverged"
          let bumpSrc ← resolveU8Source data.types callable paramLayout bumpVid
            s!"site {site.siteId} bump" true
          let amountVid ← getArr args 7 "externalCall.args"
          let amountArg ← getArr site.args 7 s!"site {site.siteId}.args"
          unless amountArg.semanticValueId == amountVid.toNat &&
              amountArg.roleId.isNone &&
              amountArg.spec.type_ == FrozenValueType.uint64 do
            tFail s!"site {site.siteId} amount binding diverged"
          let amountSrc ← resolveU64Source data.types callable paramLayout amountVid
            s!"site {site.siteId} amount"
          let decimalsVid ← getArr args 8 "externalCall.args"
          let decimalsArg ← getArr site.args 8 s!"site {site.siteId}.args"
          unless decimalsArg.semanticValueId == decimalsVid.toNat &&
              decimalsArg.roleId.isNone &&
              decimalsArg.spec.type_ == FrozenValueType.uint8 do
            tFail s!"site {site.siteId} decimals binding diverged"
          let decimalsSrc ← resolveU8Source data.types callable paramLayout decimalsVid
            s!"site {site.siteId} decimals" false
          -- Meta[0] source
          let meta0 ← getArr site.metas 0 s!"site {site.siteId}.metas"
          unless meta0.metaIndex == 0 &&
              meta0.roleId == sourceBinding.roleId &&
              meta0.localHandleIndex == sourceBinding.localIndex &&
              meta0.spec.cpiWritable == true &&
              meta0.spec.cpiSigner == false &&
              meta0.spec.outerSignerContribution == false &&
              meta0.spec.outerWritableContribution == true &&
              meta0.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId} source meta must be writable outer non-signer"
          -- Meta[1] mint
          let meta1 ← getArr site.metas 1 s!"site {site.siteId}.metas"
          unless meta1.metaIndex == 1 &&
              meta1.roleId == mintBinding.roleId &&
              meta1.localHandleIndex == mintBinding.localIndex &&
              meta1.spec.cpiWritable == false &&
              meta1.spec.cpiSigner == false &&
              meta1.spec.outerSignerContribution == false &&
              meta1.spec.outerWritableContribution == false &&
              meta1.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId} mint meta must be readonly non-signer"
          -- Meta[2] destination
          let meta2 ← getArr site.metas 2 s!"site {site.siteId}.metas"
          unless meta2.metaIndex == 2 &&
              meta2.roleId == destBinding.roleId &&
              meta2.localHandleIndex == destBinding.localIndex &&
              meta2.spec.cpiWritable == true &&
              meta2.spec.cpiSigner == false &&
              meta2.spec.outerSignerContribution == false &&
              meta2.spec.outerWritableContribution == true &&
              meta2.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId} destination meta must be writable outer non-signer"
          -- Meta[3] authorityPda CPI signer group 0, outer non-signer readonly
          let meta3 ← getArr site.metas 3 s!"site {site.siteId}.metas"
          unless meta3.metaIndex == 3 &&
              meta3.roleId == authPdaBinding.roleId &&
              meta3.localHandleIndex == authPdaBinding.localIndex &&
              meta3.spec.cpiWritable == false &&
              meta3.spec.cpiSigner == true &&
              meta3.spec.outerSignerContribution == false &&
              meta3.spec.outerWritableContribution == false &&
              meta3.spec.signerGroupId == some 0 do
            tFail s!"site {site.siteId} authorityPda meta must be CPI signer group 0 outer non-signer readonly"
          -- Outer-only seedAuthority: business signer, readonly
          let oo0 ← getArr site.outerOnlyAccounts 0 s!"site {site.siteId}.outerOnly"
          unless oo0.roleId == seedAuthBinding.roleId &&
              oo0.localHandleIndex == seedAuthBinding.localIndex &&
              oo0.spec.outerSignerContribution == true &&
              oo0.spec.outerWritableContribution == false do
            tFail s!"site {site.siteId} seedAuthority outer-only must be outer signer non-writable"
          let outerOnly : Array CpiTokenOuterOnlyBindingV1 := #[{
            outerOnlyIndex := 0
            roleId := oo0.roleId
            localIndex := oo0.localHandleIndex
            outerSigner := oo0.spec.outerSignerContribution
            outerWritable := oo0.spec.outerWritableContribution
          }]
          let argChecks ← projectSiteArgChecks site
          let siteOps ← projectSiteChecks planHandler.mode handles site stateSchemas
            decimalsSrc
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeToken {
            siteId := site.siteId
            kind := .transferCheckedPda
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 10
            source := sourceBinding
            mint := mintBinding
            destination := destBinding
            authority := none
            authorityPda := some authPdaBinding
            seedAuthority := some seedAuthBinding
            seedTag := some seedTagSrc
            bump := some bumpSrc
            amount := amountSrc
            decimals := decimalsSrc
            metas
            outerOnly
            signerGroupId := some 0
            pdaRule := some "current-program-tagged-v1"
            accountInfoCount := handles.size
          })
    | .constant _cid =>
        tFail "Token CPI IR rejects Op.Constant (constants table support deferred)"
    | .unary .. =>
        tFail "Token CPI IR rejects unary ops in first slice"
    | .pureCall .. =>
        tFail "Token CPI IR rejects pureCall in first slice"
    | .construct .. | .fieldGet .. | .fieldSet .. | .indexGet .. | .indexSet ..
    | .variantTag .. | .variantPayload .. | .checkedCast ..
    | .contextRead .. | .envRead .. | .commit .. | .assert_ .. | .emit .. | .schedule .. =>
        tFail "Token CPI IR rejects unsupported body op in first slice"

  match blk.terminator with
  | .return_ none =>
      body := body.push .returnNone
  | .return_ (some vid) =>
      if isAnonUnit data.types (← match typeOfValueId? callable vid with
          | some t => pure t
          | none => tFail "return value has no type") then
        body := body.push .returnNone
      else
        let src ← match lookupTemp tempOf vid.toNat with
          | some t => pure t
          | none =>
              match directPublicU64ParamOrdinal? data.types callable vid with
              | some ord =>
                  match ixOffsetOfParam? paramLayout ord with
                  | some (off, w) =>
                      unless w == 64 do
                        tFail "return param width diverged"
                      let (t, tempOf', next') := allocTemp tempOf nextTemp vid.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadParamU64 t off)
                      pure t
                  | none => tFail "return param missing from probe layout"
              | none =>
                  match findLiteralU64? data.types callable vid with
                  | some lit =>
                      let (t, tempOf', next') := allocTemp tempOf nextTemp vid.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadLiteralU64 t lit)
                      pure t
                  | none =>
                      tFail s!"return ValueId {vid} is not materialised"
        body := body.push (.returnU64 src)
  | .jump .. | .branch .. | .switch .. | .revert .. | .trap _ =>
      tFail "Token CPI IR requires return terminator only (straight-line)"

  let bodySiteIds :=
    body.foldl (init := ([] : List Nat)) fun acc op =>
      match op with
      | .invokeToken inv => acc ++ [inv.siteId]
      | _ => acc
  let planSiteIds := sites.map (·.siteId) |>.toList
  unless bodySiteIds == planSiteIds do
    tFail
      "Token body invoke site order must equal Plan cpiSiteIds (source order)"

  pure {
    handlerId := planHandler.handlerId
    callableId := planHandler.callableId
    name := planHandler.name
    mode := planHandler.mode
    localRoleCount := handles.size
    localRoleOrder := handles
    accountParameterBindings := bindings
    probeIxDataLen
    entryGlobalOps
    bodyOps := body
    tempCount := nextTemp
  }

private def projectTokenCandidate
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult SolanaCpiTokenIRCandidateV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    tFail "Token CPI IR requires activationDenied authority"
  let _ ← requireTokenPackage
  let plan := SolanaCpiPreflightPlanV1.planOf authority
  let compiled :=
    ResolvedSolanaCpiPreflightV1.compiledOf
      (SolanaCpiPreflightPlanV1.preflightOf authority)
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok v => pure v
    | .error _ =>
        tFail "Token CPI IR: retained Semantic failed structure validation"
  unless data.constants.isEmpty do
    tFail "Token CPI IR rejects nonempty constants table"
  unless data.invariants.isEmpty do
    tFail "Token CPI IR rejects nonempty invariants"
  let ir ← deriveSolanaCpiIRV1 plan
  let abi := ir.candidate.abiLayout
  unless abi == frozenLoaderV3AbiLayoutV1 do
    tFail "Token CPI IR requires frozen Loader V3 ABIv1 layout"
  let mut handlers : Array CpiTokenHandlerIRV1 := #[]
  for h in plan.candidate.handlers do
    let handles := ir.candidate.roleHandles.filter (fun x => x.handlerId == h.handlerId)
    unless handles.size == h.accountUses.size do
      tFail "handler local handle count mismatch"
    let sites := ir.candidate.sites.filter (fun s => s.handlerId == h.handlerId)
    unless sites.map (·.siteId) == h.cpiSiteIds do
      tFail "handler site order must equal Plan cpiSiteIds"
    let projected ← projectTokenHandler abi data h handles sites
      plan.candidate.stateSchemas
    handlers := handlers.push projected
  pure {
    schema := tokenIrSchemaV1
    sourcePlanDigest := plan.digest
    sourceIrDigest := ir.digest
    profileId := plan.candidate.profileId
    profileDigest := plan.candidate.profileDigest
    catalogDigest := plan.candidate.calleeCatalogDigest
    abiLayout := abi
    maxOuterRoles := maxOuterRolesV1
    maxFrameBytes := 4096
    handlers
  }

/-! ## Canonical render + sole mint -/

private def lowerHexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

private def encodeUInt64LowerHex16 (value : UInt64) : String :=
  Id.run do
    let mut n := value.toNat
    let mut digits : Array Char := #[]
    for _ in [0:16] do
      digits := digits.push (lowerHexDigit (n % 16))
      n := n / 16
    let mut out := ""
    for i in [0:16] do
      out := out.push digits[15 - i]!
    pure out

private def encodeUInt8LowerHex2 (value : UInt8) : String :=
  let n := value.toNat
  String.ofList [lowerHexDigit (n / 16), lowerHexDigit (n % 16)]

private def renderU64Source : CpiTokenU64SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt64LowerHex16 v}"

private def renderU8Source : CpiTokenU8SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt8LowerHex2 v}"

private def renderMeta (m : CpiTokenMetaV1) : String :=
  let sg := match m.signerGroupId with
    | none => "none"
    | some id => toString id
  s!"{m.metaIndex}:role{m.roleId}:local{m.localIndex}:w{m.cpiWritable}:s{m.cpiSigner}:sg{sg}"

private def renderPrincipal (b : CpiTokenPrincipalBindingV1) : String :=
  s!"arg{b.argIndex}:v{b.semanticValueId}:p{b.paramOrdinal}:role{b.roleId}:local{b.localIndex}"

private def renderOuter (o : CpiTokenOuterOnlyBindingV1) : String :=
  s!"oo{o.outerOnlyIndex}:role{o.roleId}:local{o.localIndex}:os{o.outerSigner}:ow{o.outerWritable}"

private def renderArgCheck : CpiTokenArgCheckV1 → String
  | .unusedPlaceholder => "unused"

private def renderKind : CpiTokenKindV1 → String
  | .transferChecked => "transferChecked"
  | .transferCheckedPda => "transferCheckedPda"

private def renderInvoke (i : CpiTokenInvokeV1) : String :=
  let metas := String.intercalate "," (i.metas.map renderMeta).toList
  let oos := String.intercalate "," (i.outerOnly.map renderOuter).toList
  let auth := match i.authority with
    | none => "none"
    | some b => renderPrincipal b
  let authPda := match i.authorityPda with
    | none => "none"
    | some b => renderPrincipal b
  let seedAuth := match i.seedAuthority with
    | none => "none"
    | some b => renderPrincipal b
  let seedTag := match i.seedTag with
    | none => "none"
    | some s => renderU64Source s
  let bump := match i.bump with
    | none => "none"
    | some s => renderU8Source s
  let sg := match i.signerGroupId with
    | none => "none"
    | some id => toString id
  let rule := match i.pdaRule with
    | none => "none"
    | some r => r
  s!"invokeToken:{i.siteId}:{renderKind i.kind}:{i.qn}:{i.packageId}:prog{i.programLocalIndex}:len{i.dataLen}:source[{renderPrincipal i.source}]:mint[{renderPrincipal i.mint}]:dest[{renderPrincipal i.destination}]:auth[{auth}]:authPda[{authPda}]:seedAuth[{seedAuth}]:seedTag[{seedTag}]:bump[{bump}]:amount[{renderU64Source i.amount}]:decimals[{renderU8Source i.decimals}]:metas[{metas}]:outer[{oos}]:sg{sg}:{rule}:infos{i.accountInfoCount}"

private def renderSiteCheck : CpiTokenSiteCheckV1 → String
  | .generic op => s!"generic:{preflightOpKindNameV1 op}"
  | .tokenAccountStateInitialized li => s!"tokenAccountStateInitialized:local{li}"
  | .tokenAccountMintEqualsRole acc mint =>
      s!"tokenAccountMintEqualsRole:local{acc}=mint{mint}"
  | .tokenAccountOwnerEqualsRole acc owner =>
      s!"tokenAccountOwnerEqualsRole:local{acc}=owner{owner}"
  | .tokenAccountDelegateNone li => s!"tokenAccountDelegateNone:local{li}"
  | .tokenMintInitialized li => s!"tokenMintInitialized:local{li}"
  | .tokenMintDecimalsEquals li src =>
      s!"tokenMintDecimalsEquals:local{li}:{renderU8Source src}"

private def renderBodyOp : CpiTokenBodyOpV1 → String
  | .loadParamU64 t off => s!"loadParamU64:{t}@{off}"
  | .loadParamU8 t off => s!"loadParamU8:{t}@{off}"
  | .loadLiteralU64 t v => s!"loadLiteralU64:{t}:{encodeUInt64LowerHex16 v}"
  | .loadLiteralU8 t v => s!"loadLiteralU8:{t}:{encodeUInt8LowerHex2 v}"
  | .stateLoadU64 t li off => s!"stateLoadU64:{t}:local{li}@{off}"
  | .checkedAddU64 d l r => s!"checkedAddU64:{d}:{l}:{r}"
  | .stateStoreU64 li off src wm marker =>
      s!"stateStoreU64:local{li}@{off}:src{src}:marker{wm}:{encodeUInt64LowerHex16 marker}"
  | .siteArgChecks sid checks =>
      let parts := String.intercalate ";" (checks.map renderArgCheck).toList
      s!"siteArgChecks:{sid}:[{parts}]"
  | .siteChecks sid ops =>
      let parts := String.intercalate ";" (ops.map renderSiteCheck).toList
      s!"siteChecks:{sid}:[{parts}]"
  | .invokeToken inv => renderInvoke inv
  | .returnU64 t => s!"returnU64:{t}"
  | .returnNone => "returnNone"

private def renderMode : HandlerModeV1 → String
  | .initialize => "initialize"
  | .entry => "entry"
  | .view => "view"

private def renderHandler (h : CpiTokenHandlerIRV1) : String :=
  let entry := String.intercalate ";" (h.entryGlobalOps.map preflightOpKindNameV1).toList
  let body := String.intercalate ";" (h.bodyOps.map renderBodyOp).toList
  s!"handler:{h.handlerId}:{h.callableId}:{h.name}:{renderMode h.mode}:roles{h.localRoleCount}:probe{h.probeIxDataLen}:temps{h.tempCount}:entry[{entry}]:body[{body}]"

private def renderCandidate (c : SolanaCpiTokenIRCandidateV1) : CompileResult String := do
  let planDig ← mapExcept (renderDigest c.sourcePlanDigest) "sourcePlanDigest"
  let irDig ← mapExcept (renderDigest c.sourceIrDigest) "sourceIrDigest"
  let profileDig ← mapExcept (renderDigest c.profileDigest) "profileDigest"
  let catalogDig ← mapExcept (renderDigest c.catalogDigest) "catalogDigest"
  let handlers := String.intercalate "\n" (c.handlers.map renderHandler).toList
  pure <|
    s!"schema={c.schema}\n" ++
    s!"sourcePlanDigest={planDig}\n" ++
    s!"sourceIrDigest={irDig}\n" ++
    s!"profileId={c.profileId}\n" ++
    s!"profileDigest={profileDig}\n" ++
    s!"catalogDigest={catalogDig}\n" ++
    s!"maxOuterRoles={c.maxOuterRoles}\n" ++
    s!"maxFrameBytes={c.maxFrameBytes}\n" ++
    handlers

/-- Validate Token siteChecks field joins against the following invokeToken.
    Public so focused tests can hand-mutate candidates and assert rejection
    without forging a private resolved carrier. -/
def validateSolanaCpiTokenIRCandidateV1
    (candidate : SolanaCpiTokenIRCandidateV1) : CompileResult Unit := do
  unless candidate.schema == tokenIrSchemaV1 do
    tFail s!"schema must be {tokenIrSchemaV1}"
  unless candidate.maxFrameBytes == 4096 do
    tFail "maxFrameBytes must be 4096"
  for h in candidate.handlers do
    unless h.localRoleCount ≤ maxOuterRolesV1 do
      tFail s!"handler {h.handlerId} localRoleCount exceeds cap"
    unless h.localRoleOrder.size == h.localRoleCount do
      tFail s!"handler {h.handlerId} localRoleOrder size diverged"
    let ops := h.bodyOps
    for i in [0:ops.size] do
      match ops[i]! with
      | .siteArgChecks sid _ =>
          let j := i + 1
          unless j + 1 < ops.size do
            tFail s!"siteArgChecks {sid} not followed by siteChecks+invoke"
          match ops[j]!, ops[j + 1]! with
          | .siteChecks sid2 _, .invokeToken inv =>
              unless sid2 == sid && inv.siteId == sid do
                tFail s!"siteArgChecks {sid} mismatched following site id"
          | _, _ =>
              tFail s!"siteArgChecks {sid} must be followed by siteChecks then invoke"
      | .siteChecks sid checks =>
          if i == 0 then
            tFail s!"siteChecks {sid} missing preceding siteArgChecks"
          else
            match ops[i - 1]! with
            | .siteArgChecks sid2 _ =>
                unless sid2 == sid do
                  tFail s!"siteChecks {sid} not preceded by matching siteArgChecks"
            | _ =>
                tFail s!"siteChecks {sid} missing immediately preceding siteArgChecks"
          let j := i + 1
          unless j < ops.size do
            tFail s!"siteChecks {sid} is not followed by invokeToken"
          match ops[j]! with
          | .invokeToken inv =>
              unless inv.siteId == sid do
                tFail s!"siteChecks {sid} mismatched invoke site {inv.siteId}"
              -- Exact Token field joins vs invoke Principal/decimals bindings.
              let ownerLocal : Nat :=
                match inv.authority, inv.authorityPda with
                | some a, none => a.localIndex
                | none, some a => a.localIndex
                | some a, some _ => a.localIndex
                | none, none => inv.source.localIndex
              let mut sawSourceState := false
              let mut sawSourceMint := false
              let mut sawSourceOwner := false
              let mut sawSourceDelegate := false
              let mut sawDestState := false
              let mut sawDestMint := false
              let mut sawMintInit := false
              let mut sawMintDecimals := false
              for c in checks do
                match c with
                | .generic _ => pure ()
                | .tokenAccountStateInitialized li =>
                    unless li < h.localRoleCount do
                      tFail s!"site {sid}: tokenAccountStateInitialized local out of range"
                    if li == inv.source.localIndex then sawSourceState := true
                    else if li == inv.destination.localIndex then sawDestState := true
                    else
                      tFail s!"site {sid}: tokenAccountStateInitialized local {li} not source/destination"
                | .tokenAccountMintEqualsRole accLi mintLi =>
                    unless accLi < h.localRoleCount && mintLi < h.localRoleCount do
                      tFail s!"site {sid}: tokenAccountMintEqualsRole local out of range"
                    unless mintLi == inv.mint.localIndex do
                      tFail s!"site {sid}: tokenAccountMintEqualsRole mint local must join invoke.mint"
                    if accLi == inv.source.localIndex then sawSourceMint := true
                    else if accLi == inv.destination.localIndex then sawDestMint := true
                    else
                      tFail s!"site {sid}: tokenAccountMintEqualsRole account local not source/destination"
                | .tokenAccountOwnerEqualsRole accLi ownerLi =>
                    unless accLi < h.localRoleCount && ownerLi < h.localRoleCount do
                      tFail s!"site {sid}: tokenAccountOwnerEqualsRole local out of range"
                    unless accLi == inv.source.localIndex do
                      tFail s!"site {sid}: tokenAccountOwnerEqualsRole only admits source account"
                    unless ownerLi == ownerLocal do
                      tFail s!"site {sid}: tokenAccountOwnerEqualsRole owner local must join authority/authorityPda"
                    sawSourceOwner := true
                | .tokenAccountDelegateNone li =>
                    unless li < h.localRoleCount do
                      tFail s!"site {sid}: tokenAccountDelegateNone local out of range"
                    unless li == inv.source.localIndex do
                      tFail s!"site {sid}: tokenAccountDelegateNone only admits source (frozen delegate=none)"
                    sawSourceDelegate := true
                | .tokenMintInitialized li =>
                    unless li < h.localRoleCount do
                      tFail s!"site {sid}: tokenMintInitialized local out of range"
                    unless li == inv.mint.localIndex do
                      tFail s!"site {sid}: tokenMintInitialized must join invoke.mint"
                    sawMintInit := true
                | .tokenMintDecimalsEquals li src =>
                    unless li < h.localRoleCount do
                      tFail s!"site {sid}: tokenMintDecimalsEquals local out of range"
                    unless li == inv.mint.localIndex do
                      tFail s!"site {sid}: tokenMintDecimalsEquals must join invoke.mint"
                    unless src == inv.decimals do
                      tFail s!"site {sid}: tokenMintDecimalsEquals source must exact-join invoke.decimals"
                    sawMintDecimals := true
              unless sawSourceState && sawSourceMint && sawDestState && sawDestMint &&
                  sawMintInit && sawMintDecimals do
                tFail s!"site {sid}: missing required Token field siteChecks (state/mint/decimals)"
              -- source owner+delegate required for transferChecked (authority) and Pda (authorityPda)
              unless sawSourceOwner && sawSourceDelegate do
                tFail s!"site {sid}: source must carry ownerEquals + delegate=none field checks"
          | _ =>
              tFail s!"siteChecks {sid} must be immediately followed by invokeToken"
      | .invokeToken inv =>
          unless inv.packageId == "token-classic-v1" do
            tFail s!"invokeToken site {inv.siteId} package must be token-classic-v1"
          unless inv.dataLen == 10 && inv.metas.size == 4 do
            tFail s!"invokeToken site {inv.siteId} dataLen/metas must be 10/4"
          unless inv.metas[0]!.roleId == inv.source.roleId &&
              inv.metas[0]!.localIndex == inv.source.localIndex &&
              inv.metas[0]!.cpiWritable == true &&
              inv.metas[0]!.cpiSigner == false &&
              inv.metas[1]!.roleId == inv.mint.roleId &&
              inv.metas[1]!.localIndex == inv.mint.localIndex &&
              inv.metas[1]!.cpiWritable == false &&
              inv.metas[1]!.cpiSigner == false &&
              inv.metas[2]!.roleId == inv.destination.roleId &&
              inv.metas[2]!.localIndex == inv.destination.localIndex &&
              inv.metas[2]!.cpiWritable == true &&
              inv.metas[2]!.cpiSigner == false do
            tFail s!"invokeToken site {inv.siteId} source/mint/destination meta join diverged"
          match inv.kind with
          | .transferChecked =>
              unless inv.qn == "solana.token.transferChecked" &&
                  inv.outerOnly.isEmpty && inv.signerGroupId.isNone &&
                  inv.pdaRule.isNone && inv.authority.isSome &&
                  inv.authorityPda.isNone && inv.seedAuthority.isNone &&
                  inv.seedTag.isNone && inv.bump.isNone do
                tFail s!"transferChecked site {inv.siteId} frozen shape diverged"
              let some auth := inv.authority |
                tFail s!"transferChecked site {inv.siteId} authority missing"
              unless inv.metas[3]!.roleId == auth.roleId &&
                  inv.metas[3]!.localIndex == auth.localIndex &&
                  inv.metas[3]!.cpiWritable == false &&
                  inv.metas[3]!.cpiSigner == true &&
                  inv.metas[3]!.signerGroupId.isNone do
                tFail s!"transferChecked site {inv.siteId} authority meta join diverged"
          | .transferCheckedPda =>
              unless inv.qn == "solana.token.transferCheckedPda" &&
                  inv.outerOnly.size == 1 && inv.signerGroupId == some 0 &&
                  inv.pdaRule == some "current-program-tagged-v1" &&
                  inv.authority.isNone && inv.authorityPda.isSome &&
                  inv.seedAuthority.isSome && inv.seedTag.isSome &&
                  inv.bump.isSome do
                tFail s!"transferCheckedPda site {inv.siteId} frozen shape diverged"
              let some authPda := inv.authorityPda |
                tFail s!"transferCheckedPda site {inv.siteId} authorityPda missing"
              let some seedAuth := inv.seedAuthority |
                tFail s!"transferCheckedPda site {inv.siteId} seedAuthority missing"
              unless inv.metas[3]!.roleId == authPda.roleId &&
                  inv.metas[3]!.localIndex == authPda.localIndex &&
                  inv.metas[3]!.cpiWritable == false &&
                  inv.metas[3]!.cpiSigner == true &&
                  inv.metas[3]!.signerGroupId == some 0 &&
                  inv.outerOnly[0]!.roleId == seedAuth.roleId &&
                  inv.outerOnly[0]!.localIndex == seedAuth.localIndex &&
                  inv.outerOnly[0]!.outerSigner == true &&
                  inv.outerOnly[0]!.outerWritable == false do
                tFail s!"transferCheckedPda site {inv.siteId} meta/outer join diverged"
              match inv.bump with
              | some (.literal 0) =>
                  tFail s!"transferCheckedPda site {inv.siteId} bump literal 0 rejected"
              | _ => pure ()
          if i < 2 then
            tFail s!"invokeToken site {inv.siteId} missing preceding siteArgChecks/siteChecks"
          else
            match ops[i - 2]!, ops[i - 1]! with
            | .siteArgChecks sidA _, .siteChecks sidC _ =>
                unless sidA == inv.siteId && sidC == inv.siteId do
                  tFail s!"invokeToken site {inv.siteId} preceding site id mismatch"
            | _, _ =>
                tFail s!"invokeToken site {inv.siteId} must be preceded by siteArgChecks→siteChecks"
      | _ => pure ()
  pure ()

/-- Sole mint of the #122 Token execution IR from Semantic-bound Plan. -/
def resolveSolanaCpiTokenIRV1
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult ResolvedSolanaCpiTokenIRV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    tFail "Token CPI IR requires activationDenied preflight carrier"
  let candidate ← projectTokenCandidate authority
  validateSolanaCpiTokenIRCandidateV1 candidate
  let text ← renderCandidate candidate
  let canonicalBytes := text.toUTF8
  let digest ← mapExcept
    (domainSeparatedSha256 tokenIrDigestDomainV1 canonicalBytes)
    "token-ir digest"
  pure ⟨authority, candidate, canonicalBytes, digest⟩

/-- transferChecked scratch: 16 data + 64 metas + 40 instr + 56*N infos = 120+56N. -/
def tokenCpiScratchTransferCheckedV1 (localRoleCount : Nat) : Nat :=
  120 + localRoleCount * 56

/-- transferCheckedPda scratch layout (see EmitCpiTokenSbpfV1):
    +0 data16, +16 seed0/24, +40 seedTag, +48 bump,
    +56 SolSignerSeed[4], +120 SolSignerSeeds, +136 Meta[4],
    +200 Instruction, +240 Infos, +240+56N keyOut, +272+56N bumpOut
    end = 280 + 56*N. -/
def tokenCpiScratchTransferCheckedPdaV1 (localRoleCount : Nat) : Nat :=
  280 + localRoleCount * 56

/-- Max site scratch across handlers. -/
def tokenMaxSiteScratchV1 (c : SolanaCpiTokenIRCandidateV1) : Nat :=
  Id.run do
    let mut maxB : Nat := 0
    for h in c.handlers do
      for op in h.bodyOps do
        match op with
        | .invokeToken inv =>
            let b := match inv.kind with
              | .transferChecked => tokenCpiScratchTransferCheckedV1 inv.accountInfoCount
              | .transferCheckedPda =>
                  tokenCpiScratchTransferCheckedPdaV1 inv.accountInfoCount
            if b > maxB then maxB := b
        | _ => pure ()
    pure maxB

end ProofForgeV2.Targets.Solana.CpiV1

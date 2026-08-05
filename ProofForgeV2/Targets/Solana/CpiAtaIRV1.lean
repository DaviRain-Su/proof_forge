/-
  ProofForgeV2.Targets.Solana.CpiAtaIRV1 — #123 classic ATA CPI IR.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole mint: `resolveSolanaCpiAtaIRV1`. Consumes only private Semantic-bound
  `SolanaCpiPreflightPlanV1`, freshly derives the validated generic CPI IR,
  and mints private `ResolvedSolanaCpiAtaIRV1`.

  * admits only `solana.ata.createIdempotent`;
  * single-block straight-line initializer/entry/view;
  * narrow public Principal/UInt64 + state/literal/checked add/return;
  * exact data byte `01`; six metas payer(w+s), ATA(w), wallet(ro), mint(ro),
    native System(ro), classic Token(ro); zero signer groups;
  * canonical address check seeds wallet/classic-Token/mint under the frozen
    classic ATA program; the resulting bump is not a caller signer group;
  * ATA pre-state is atomically either zero-lamport/zero-data System-owned or
    Token-owned 165B initialized with exact mint+wallet joins;
  * ATA and Token packages remain loader-v3/artifactBinding.absent/admitted=false;
    System remains the exact runtime-native package;
  * per site: siteArgChecks → siteChecks → invoke (source order);
  * rejects Token-2022, dynamic CPI, schedule, constants, invariants,
    multiblock control flow and loops.

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

def ataIrSchemaV1 : String := "proof-forge.solana.cpi-ata-ir.v1"
def ataIrDigestDomainV1 : String := "pf.solana.cpi-ata-ir.v1"

/-- UInt64 value sources retained for the narrow state/arithmetic body. -/
inductive CpiAtaU64SourceV1 where
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  | literal (value : UInt64)
  deriving BEq, Repr, Inhabited

/-- UInt8 source retained only for closed generic body decoding; ATA has no UInt8 arg. -/
inductive CpiAtaU8SourceV1 where
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  | literal (value : UInt8)
  deriving BEq, Repr, Inhabited

/-- One ordered ATA CPI meta binding to a handler-local role. -/
structure CpiAtaMetaV1 where
  metaIndex : Nat
  roleId : Nat
  localIndex : Nat
  cpiWritable : Bool
  cpiSigner : Bool
  signerGroupId : Option Nat
  deriving BEq, Repr, Inhabited

/-- Exact Semantic Principal → callable parameter → role → dense local join. -/
structure CpiAtaPrincipalBindingV1 where
  argIndex : Nat
  semanticValueId : Nat
  paramOrdinal : Nat
  roleId : Nat
  localIndex : Nat
  deriving BEq, Repr, Inhabited

/-- Outer-only account binding carrier; frozen ATA v1 requires this array empty. -/
structure CpiAtaOuterOnlyBindingV1 where
  outerOnlyIndex : Nat
  roleId : Nat
  localIndex : Nat
  outerSigner : Bool
  outerWritable : Bool
  deriving BEq, Repr, Inhabited

/-- Closed site-arg preflight (ATA v1 has no scalar call arguments). -/
inductive CpiAtaArgCheckV1 where
  | unusedPlaceholder
  deriving BEq, Repr, Inhabited

/-- Frozen ATA API kind. -/
inductive CpiAtaKindV1 where
  | createIdempotent
  deriving BEq, Repr, Inhabited

/-- Site-local classic ATA CreateIdempotent invoke. -/
structure CpiAtaInvokeV1 where
  siteId : Nat
  kind : CpiAtaKindV1
  qn : String
  packageId : String
  programLocalIndex : Nat
  dataLen : Nat
  payer : CpiAtaPrincipalBindingV1
  ata : CpiAtaPrincipalBindingV1
  wallet : CpiAtaPrincipalBindingV1
  mint : CpiAtaPrincipalBindingV1
  systemProgramLocalIndex : Nat
  tokenProgramLocalIndex : Nat
  metas : Array CpiAtaMetaV1
  outerOnly : Array CpiAtaOuterOnlyBindingV1
  signerGroupId : Option Nat
  pdaRule : Option String
  accountInfoCount : Nat
  deriving BEq, Repr

/-- Closed ATA site-time predicates. Generic preflight checks retain exact role
    owner/data/flags. The two custom checks bind canonical ATA derivation and
    the closed fresh-or-existing ATA pre-state directly to invoke roles. -/
inductive CpiAtaSiteCheckV1 where
  | generic (op : CpiPreflightOpV1)
  | ataAddressCanonical
      (ataLocal walletLocal tokenProgramLocal mintLocal ataProgramLocal : Nat)
  | ataAccountPrestateClosed
      (ataLocal walletLocal mintLocal systemProgramLocal tokenProgramLocal : Nat)
  | tokenMintInitialized (localIndex : Nat)
  deriving BEq, Repr

/-- Ordered body operations after handler-entry global preflight. -/
inductive CpiAtaBodyOpV1 where
  | loadParamU64 (tempId : Nat) (ixDataOffset : Nat)
  | loadParamU8 (tempId : Nat) (ixDataOffset : Nat)
  | loadLiteralU64 (tempId : Nat) (value : UInt64)
  | loadLiteralU8 (tempId : Nat) (value : UInt8)
  | stateLoadU64 (tempId : Nat) (stateLocalIndex : Nat) (byteOffset : Nat)
  | checkedAddU64 (dstTemp lhsTemp rhsTemp : Nat)
  | stateStoreU64 (stateLocalIndex : Nat) (byteOffset : Nat) (srcTemp : Nat)
    (writeInitializedMarker : Bool) (initializedMarker : UInt64)
  /-- Site-arg preflight (empty for ATA APIs; preserves siteArgChecks→siteChecks→invoke). -/
  | siteArgChecks (siteId : Nat) (checks : Array CpiAtaArgCheckV1)
  /-- Site-time account predicates (must run immediately before invoke). -/
  | siteChecks (siteId : Nat) (ops : Array CpiAtaSiteCheckV1)
  | invokeAta (invoke : CpiAtaInvokeV1)
  | returnU64 (srcTemp : Nat)
  | returnNone
  deriving BEq, Repr, Inhabited

structure CpiAtaHandlerIRV1 where
  handlerId : Nat
  callableId : Nat
  name : String
  mode : HandlerModeV1
  localRoleCount : Nat
  localRoleOrder : Array CpiIRRoleHandleV1
  accountParameterBindings : Array CpiPreflightAccountParamBindingV1
  probeIxDataLen : Nat
  entryGlobalOps : Array CpiPreflightOpV1
  bodyOps : Array CpiAtaBodyOpV1
  tempCount : Nat
  deriving BEq, Repr

structure SolanaCpiAtaIRCandidateV1 where
  schema : String
  sourcePlanDigest : Digest
  sourceIrDigest : Digest
  profileId : String
  profileDigest : Digest
  catalogDigest : Digest
  abiLayout : LoaderV3AbiLayoutV1
  maxOuterRoles : Nat
  maxFrameBytes : Nat
  handlers : Array CpiAtaHandlerIRV1
  deriving BEq

/-- Private resolved ATA IR. Sole mint from Semantic-bound preflight Plan. -/
structure ResolvedSolanaCpiAtaIRV1 where
  private mk ::
  authority : SolanaCpiPreflightPlanV1
  candidate : SolanaCpiAtaIRCandidateV1
  canonicalBytes : ByteArray
  digest : Digest

namespace ResolvedSolanaCpiAtaIRV1

def authorityOf (r : ResolvedSolanaCpiAtaIRV1) : SolanaCpiPreflightPlanV1 :=
  r.authority
def candidateOf (r : ResolvedSolanaCpiAtaIRV1) : SolanaCpiAtaIRCandidateV1 :=
  r.candidate
def digestOf (r : ResolvedSolanaCpiAtaIRV1) : Digest :=
  r.digest
def canonicalBytesOf (r : ResolvedSolanaCpiAtaIRV1) : ByteArray :=
  r.canonicalBytes

end ResolvedSolanaCpiAtaIRV1

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

private def requireAbsentLoaderPackage
    (packageId : String) (programId : SolanaPubkeyV1) :
    CompileResult FrozenCalleePackage := do
  let package ← match findCalleePackage? packageId with
    | some p => pure p
    | none => tFail s!"{packageId} missing from frozen callee catalog"
  unless package.packageId == packageId && package.programId == programId do
    tFail s!"{packageId} identity diverged"
  unless package.executionClass == .loaderV3Sbpf do
    tFail s!"{packageId} executionClass must be loaderV3Sbpf"
  match package.artifactBinding with
  | .absent => pure ()
  | .runtimeNative _ => tFail s!"{packageId} must retain artifactBinding.absent"
  unless package.admittedForMaterialization == false do
    tFail s!"{packageId} must remain admittedForMaterialization=false"
  pure package

private def requireAtaPackage : CompileResult FrozenCalleePackage :=
  requireAbsentLoaderPackage "ata-classic-v1" ataClassicProgramIdV1

private def requireTokenDependency : CompileResult FrozenCalleePackage :=
  requireAbsentLoaderPackage "token-classic-v1" tokenClassicProgramIdV1

private def requireSystemDependency : CompileResult FrozenCalleePackage := do
  let package ← match findCalleePackage? "system-v1" with
    | some p => pure p
    | none => tFail "system-v1 missing from frozen callee catalog"
  unless package.programId == systemProgramIdV1 &&
      package.executionClass == .nativeSystem &&
      package.admittedForMaterialization == false do
    tFail "system-v1 identity/execution/admission diverged"
  match package.artifactBinding with
  | .runtimeNative commit =>
      unless commit == agaveV400CommitV1 do
        tFail "system-v1 runtime-native commit diverged"
  | .absent => tFail "system-v1 must retain runtime-native binding"
  pure package

/-- ATA-aware owner resolution. -/
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
  | .closedPackages packages =>
      unless packages == #["system-v1", "token-classic-v1"] do
        tFail "ATA closedPackages owner must be exact [system-v1,token-classic-v1]"
      -- The OR owner check is emitted atomically by ataAccountPrestateClosed.
      pure #[]

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
  | .uninitializedOrIdempotentlyInitialized => pure ()
  | .uninitialized =>
      tFail "ATA CPI IR rejects standalone uninitialized accounts"
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
  | .classicTokenAccount .. =>
      tFail "ATA CPI IR rejects standalone classicTokenAccount constraints"
  | .classicTokenMint bytes state decimalsEqualsArg =>
      unless bytes == 82 do
        tFail s!"classicTokenMint bytes must be 82, got {bytes}"
      unless state == "initialized" && decimalsEqualsArg.isNone do
        tFail "ATA mint must be initialized with no decimals argument join"
      ops := ops.push (.checkExactDataLen localIndex 82)
  | .ataAccount mintEqualsArg ownerEqualsArg =>
      unless mintEqualsArg == "mint" && ownerEqualsArg == "wallet" do
        tFail "ATA account field joins must be mint/wallet"
      -- Closed owner/data/lamports alternatives are one custom atomic check.
      pure ()
  pure ops

private def resolveProvisioning (prov : ProvisioningPolicy) : CompileResult Unit := do
  match prov with
  | .none | .mustExist | .ataCreateIdempotent => pure ()
  | .systemCreateAccount =>
      tFail "ATA CPI IR rejects systemCreateAccount provisioning"

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
      tFail "ATA CPI IR requires public parameters only"
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
        s!"ATA CPI IR admits only public Principal/UInt64/UInt8 params, got '{p.name}'"
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
      s!"ATA CPI IR requires single-block straight-line callables (got {callable.blocks.size} blocks)"
  unless callable.entryBlock.toNat == 0 do
    tFail "ATA CPI IR requires entryBlock == 0"
  unless callable.loopBounds.isEmpty do
    tFail "ATA CPI IR rejects loopBounds (no back edges)"
  let blk ← getArr callable.blocks 0 "callable.blocks"
  unless blk.id.toNat == 0 do
    tFail "ATA CPI IR requires sole block id == 0"
  unless blk.params.isEmpty do
    tFail "ATA CPI IR rejects block parameters"
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
        tFail s!"site {site.siteId}: Principal arg '{argName}' missing for ATA field join"
  unless arg.spec.type_ == FrozenValueType.principal do
    tFail s!"site {site.siteId}: arg '{argName}' is not Principal"
  let roleId ← match arg.roleId with
    | some rid => pure rid
    | none =>
        tFail s!"site {site.siteId}: arg '{argName}' has no roleId for ATA field join"
  let li ← localIndexOfRole handles roleId
  unless li < handles.size do
    tFail s!"site {site.siteId}: arg '{argName}' localIndex out of range"
  pure li

private def fixedProgramLocal
    (handles : Array CpiIRRoleHandleV1) (packageId : String) :
    CompileResult Nat := do
  let handle ← match handles.find? (fun h =>
      match h.keyPolicy with
      | .fixedProgram p => p == packageId
      | _ => false) with
    | some h => pure h
    | none => tFail s!"fixed program role '{packageId}' missing from handler"
  unless handle.localIndex < handles.size do
    tFail s!"fixed program role '{packageId}' localIndex out of range"
  pure handle.localIndex

/-- Site-time predicates in frozen sitePredicates order. ATA target alternatives
    stay atomic so no candidate can silently weaken System-vs-Token ownership. -/
private def projectSiteChecks
    (mode : HandlerModeV1)
    (handles : Array CpiIRRoleHandleV1)
    (site : CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult (Array CpiAtaSiteCheckV1) := do
  let mut ops : Array CpiAtaSiteCheckV1 := #[]
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
    match pred.constraint.data with
    | .ataAccount mintArg ownerArg =>
        unless mintArg == "mint" && ownerArg == "wallet" do
          tFail s!"site {site.siteId}: ATA field joins must be mint/wallet"
        let walletLocal ← principalLocalOfArgName site handles ownerArg
        let mintLocal ← principalLocalOfArgName site handles mintArg
        let systemLocal ← fixedProgramLocal handles "system-v1"
        let tokenLocal ← fixedProgramLocal handles "token-classic-v1"
        let ataProgramLocal ← localIndexOfRole handles site.programRoleId
        ops := ops.push (.ataAddressCanonical handle.localIndex walletLocal
          tokenLocal mintLocal ataProgramLocal)
        ops := ops.push (.ataAccountPrestateClosed handle.localIndex walletLocal
          mintLocal systemLocal tokenLocal)
    | .classicTokenMint bytes state decimalsEq =>
        unless bytes == 82 && state == "initialized" && decimalsEq.isNone do
          tFail s!"site {site.siteId}: ATA mint shape must be 82/initialized/no-decimals"
        ops := ops.push (.tokenMintInitialized handle.localIndex)
    | .classicTokenAccount .. =>
        tFail s!"site {site.siteId}: standalone classic Token account unsupported"
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
    CompileResult CpiAtaPrincipalBindingV1 := do
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
    CompileResult CpiAtaU64SourceV1 := do
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
    CompileResult CpiAtaU8SourceV1 := do
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
    CompileResult (Array CpiAtaMetaV1) := do
  let mut metas : Array CpiAtaMetaV1 := #[]
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
    CompileResult (Array CpiAtaArgCheckV1) := do
  unless site.preflight.isEmpty do
    tFail s!"site {site.siteId}: ATA APIs require empty preflight"
  pure #[]

private def validateAtaSiteShape (site : CpiIRSiteV1) : CompileResult Unit := do
  unless site.packageId == "ata-classic-v1" do
    tFail s!"ATA CPI admits only ata-classic-v1, got '{site.packageId}' at site {site.siteId}"
  unless site.programKey == ataClassicProgramIdV1 do
    tFail s!"site {site.siteId}: ATA program key must be frozen classic ATA id"
  unless site.qn == "solana.ata.createIdempotent" do
    tFail s!"ATA CPI admits only solana.ata.createIdempotent, got '{site.qn}'"
  unless site.instructionCodec.length == 1 &&
      site.instructionCodec.segments == #[.hex "01"] do
    tFail s!"site {site.siteId}: ATA data must be exact single byte 01"
  match site.pda with
  | .addressCheckOnly rule targetArg walletArg mintArg =>
      unless rule == "ata-classic-v1" && targetArg == "ata" &&
          walletArg == "wallet" && mintArg == "mint" do
        tFail s!"site {site.siteId}: ATA addressCheckOnly args/rule diverged"
  | .none | .signer .. | .vaultPdaSigner _ =>
      tFail s!"site {site.siteId}: ATA requires addressCheckOnly ata-classic-v1"
  unless site.signerGroups.isEmpty do
    tFail s!"site {site.siteId}: ATA createIdempotent requires zero signer groups"
  unless site.outerOnlyAccounts.isEmpty do
    tFail s!"site {site.siteId}: ATA createIdempotent requires empty outer-only"
  unless site.metas.size == 6 do
    tFail s!"site {site.siteId}: ATA createIdempotent requires exactly six metas"
  unless site.args.size == 4 do
    tFail s!"site {site.siteId}: ATA createIdempotent requires exactly four args"
  unless site.preflight.isEmpty do
    tFail s!"site {site.siteId}: ATA createIdempotent requires empty scalar preflight"

private def projectAtaHandler
    (abi : LoaderV3AbiLayoutV1)
    (data : SemanticProgramDataV1)
    (planHandler : HandlerPlanV1)
    (handles : Array CpiIRRoleHandleV1)
    (sites : Array CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult CpiAtaHandlerIRV1 := do
  let _ataPkg ← requireAtaPackage
  let _tokenPkg ← requireTokenDependency
  let _systemPkg ← requireSystemDependency
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
    validateAtaSiteShape site

  let blk ← requireStraightLineCallable callable
  let (paramLayout, probeIxDataLen) ← buildParamIxLayout data.types callable
  let (bindings, entryGlobalOps) ←
    projectEntryGlobalOps abi planHandler.mode handles stateSchemas

  let mut tempOf : Array (Nat × Nat) := #[]
  let mut nextTemp : Nat := 0
  let mut body : Array CpiAtaBodyOpV1 := #[]

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
            tFail "ATA CPI IR admits only UInt64/UInt8 literals in body"
    | .stateLoad stateId =>
        let some vd := instr.result |
          tFail "stateLoad must produce a result"
        let (stateLocal, schema) ← match stateInfo? with
          | some s => pure s
          | none => tFail "stateLoad without state role"
        unless stateId.toNat == 0 do
          tFail "ATA CPI IR first slice admits only stateId 0"
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
          tFail "ATA CPI IR first slice admits only stateId 0"
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
            tFail "ATA CPI IR first slice admits only checked UInt64 add in body"
    | .externalCall effectId callee args =>
        let qnComps ← mapExcept (renderQualifiedNameComponents callee) "callee QN"
        let qn := String.intercalate "." qnComps.toList
        unless qn == "solana.ata.createIdempotent" do
          tFail s!"ATA CPI admits only solana.ata.createIdempotent, got '{qn}'"
        let site ← match sites.find? (fun s =>
            s.anchor.callableId == planHandler.callableId &&
              s.anchor.blockId == blk.id.toNat &&
              s.anchor.instructionIndex == instrIdx &&
              s.anchor.effectId == effectId.toNat) with
          | some s => pure s
          | none => tFail s!"ExternalCall at instr {instrIdx} has no matching CPI site anchor"
        unless site.qn == qn && site.packageId == "ata-classic-v1" do
          tFail "ATA site QN/package diverges from Semantic ExternalCall"
        unless args.size == 4 && site.args.size == 4 do
          tFail "createIdempotent requires exactly 4 Semantic and Plan args"
        let programLocal ← localIndexOfRole handles site.programRoleId
        unless site.programHandleIndex == programLocal do
          tFail s!"site {site.siteId} ATA program handle index diverged"
        let payerVid ← getArr args 0 "externalCall.args"
        let payerBinding ← resolvePrincipalAccountBinding data.types callable
          handles bindings site 0 payerVid
        let ataVid ← getArr args 1 "externalCall.args"
        let ataBinding ← resolvePrincipalAccountBinding data.types callable
          handles bindings site 1 ataVid
        let walletVid ← getArr args 2 "externalCall.args"
        let walletBinding ← resolvePrincipalAccountBinding data.types callable
          handles bindings site 2 walletVid
        let mintVid ← getArr args 3 "externalCall.args"
        let mintBinding ← resolvePrincipalAccountBinding data.types callable
          handles bindings site 3 mintVid
        let systemLocal ← fixedProgramLocal handles "system-v1"
        let tokenLocal ← fixedProgramLocal handles "token-classic-v1"
        let metas ← projectMetas handles site
        let meta0 ← getArr site.metas 0 s!"site {site.siteId}.metas"
        unless meta0.metaIndex == 0 && meta0.roleId == payerBinding.roleId &&
            meta0.localHandleIndex == payerBinding.localIndex &&
            meta0.spec.cpiWritable == true && meta0.spec.cpiSigner == true &&
            meta0.spec.outerSignerContribution == true &&
            meta0.spec.outerWritableContribution == true &&
            meta0.spec.signerGroupId.isNone do
          tFail s!"site {site.siteId}: payer meta must be writable outer/CPI signer"
        let meta1 ← getArr site.metas 1 s!"site {site.siteId}.metas"
        unless meta1.metaIndex == 1 && meta1.roleId == ataBinding.roleId &&
            meta1.localHandleIndex == ataBinding.localIndex &&
            meta1.spec.cpiWritable == true && meta1.spec.cpiSigner == false &&
            meta1.spec.outerSignerContribution == false &&
            meta1.spec.outerWritableContribution == true &&
            meta1.spec.signerGroupId.isNone do
          tFail s!"site {site.siteId}: ATA meta must be writable non-signer"
        let meta2 ← getArr site.metas 2 s!"site {site.siteId}.metas"
        unless meta2.metaIndex == 2 && meta2.roleId == walletBinding.roleId &&
            meta2.localHandleIndex == walletBinding.localIndex &&
            meta2.spec.cpiWritable == false && meta2.spec.cpiSigner == false &&
            meta2.spec.outerSignerContribution == false &&
            meta2.spec.outerWritableContribution == false &&
            meta2.spec.signerGroupId.isNone do
          tFail s!"site {site.siteId}: wallet meta must be readonly non-signer"
        let meta3 ← getArr site.metas 3 s!"site {site.siteId}.metas"
        unless meta3.metaIndex == 3 && meta3.roleId == mintBinding.roleId &&
            meta3.localHandleIndex == mintBinding.localIndex &&
            meta3.spec.cpiWritable == false && meta3.spec.cpiSigner == false &&
            meta3.spec.outerSignerContribution == false &&
            meta3.spec.outerWritableContribution == false &&
            meta3.spec.signerGroupId.isNone do
          tFail s!"site {site.siteId}: mint meta must be readonly non-signer"
        let meta4 ← getArr site.metas 4 s!"site {site.siteId}.metas"
        unless meta4.metaIndex == 4 && meta4.localHandleIndex == systemLocal &&
            meta4.spec.cpiWritable == false && meta4.spec.cpiSigner == false &&
            meta4.spec.outerSignerContribution == false &&
            meta4.spec.outerWritableContribution == false &&
            meta4.spec.signerGroupId.isNone do
          tFail s!"site {site.siteId}: System meta must be exact readonly fixed role"
        let meta5 ← getArr site.metas 5 s!"site {site.siteId}.metas"
        unless meta5.metaIndex == 5 && meta5.localHandleIndex == tokenLocal &&
            meta5.spec.cpiWritable == false && meta5.spec.cpiSigner == false &&
            meta5.spec.outerSignerContribution == false &&
            meta5.spec.outerWritableContribution == false &&
            meta5.spec.signerGroupId.isNone do
          tFail s!"site {site.siteId}: classic Token meta must be exact readonly fixed role"
        let argChecks ← projectSiteArgChecks site
        let siteOps ← projectSiteChecks planHandler.mode handles site stateSchemas
        body := body.push (.siteArgChecks site.siteId argChecks)
        body := body.push (.siteChecks site.siteId siteOps)
        body := body.push (.invokeAta {
          siteId := site.siteId
          kind := .createIdempotent
          qn
          packageId := site.packageId
          programLocalIndex := programLocal
          dataLen := 1
          payer := payerBinding
          ata := ataBinding
          wallet := walletBinding
          mint := mintBinding
          systemProgramLocalIndex := systemLocal
          tokenProgramLocalIndex := tokenLocal
          metas
          outerOnly := #[]
          signerGroupId := none
          pdaRule := some "ata-classic-v1"
          accountInfoCount := handles.size
        })
    | .constant _cid =>
        tFail "ATA CPI IR rejects Op.Constant (constants table support deferred)"
    | .unary .. =>
        tFail "ATA CPI IR rejects unary ops in first slice"
    | .pureCall .. =>
        tFail "ATA CPI IR rejects pureCall in first slice"
    | .construct .. | .fieldGet .. | .fieldSet .. | .indexGet .. | .indexSet ..
    | .variantTag .. | .variantPayload .. | .checkedCast ..
    | .contextRead .. | .envRead .. | .commit .. | .assert_ .. | .emit .. | .schedule .. =>
        tFail "ATA CPI IR rejects unsupported body op in first slice"

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
      tFail "ATA CPI IR requires return terminator only (straight-line)"

  let bodySiteIds :=
    body.foldl (init := ([] : List Nat)) fun acc op =>
      match op with
      | .invokeAta inv => acc ++ [inv.siteId]
      | _ => acc
  let planSiteIds := sites.map (·.siteId) |>.toList
  unless bodySiteIds == planSiteIds do
    tFail
      "ATA body invoke site order must equal Plan cpiSiteIds (source order)"

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

private def projectAtaCandidate
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult SolanaCpiAtaIRCandidateV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    tFail "ATA CPI IR requires activationDenied authority"
  let _ ← requireAtaPackage
  let _ ← requireTokenDependency
  let _ ← requireSystemDependency
  let plan := SolanaCpiPreflightPlanV1.planOf authority
  let compiled :=
    ResolvedSolanaCpiPreflightV1.compiledOf
      (SolanaCpiPreflightPlanV1.preflightOf authority)
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok v => pure v
    | .error _ =>
        tFail "ATA CPI IR: retained Semantic failed structure validation"
  unless data.constants.isEmpty do
    tFail "ATA CPI IR rejects nonempty constants table"
  unless data.invariants.isEmpty do
    tFail "ATA CPI IR rejects nonempty invariants"
  let ir ← deriveSolanaCpiIRV1 plan
  let abi := ir.candidate.abiLayout
  unless abi == frozenLoaderV3AbiLayoutV1 do
    tFail "ATA CPI IR requires frozen Loader V3 ABIv1 layout"
  let mut handlers : Array CpiAtaHandlerIRV1 := #[]
  for h in plan.candidate.handlers do
    let handles := ir.candidate.roleHandles.filter (fun x => x.handlerId == h.handlerId)
    unless handles.size == h.accountUses.size do
      tFail "handler local handle count mismatch"
    let sites := ir.candidate.sites.filter (fun s => s.handlerId == h.handlerId)
    unless sites.map (·.siteId) == h.cpiSiteIds do
      tFail "handler site order must equal Plan cpiSiteIds"
    let projected ← projectAtaHandler abi data h handles sites
      plan.candidate.stateSchemas
    handlers := handlers.push projected
  pure {
    schema := ataIrSchemaV1
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

private def renderU64Source : CpiAtaU64SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt64LowerHex16 v}"

private def renderU8Source : CpiAtaU8SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt8LowerHex2 v}"

private def renderMeta (m : CpiAtaMetaV1) : String :=
  let sg := match m.signerGroupId with
    | none => "none"
    | some id => toString id
  s!"{m.metaIndex}:role{m.roleId}:local{m.localIndex}:w{m.cpiWritable}:s{m.cpiSigner}:sg{sg}"

private def renderPrincipal (b : CpiAtaPrincipalBindingV1) : String :=
  s!"arg{b.argIndex}:v{b.semanticValueId}:p{b.paramOrdinal}:role{b.roleId}:local{b.localIndex}"

private def renderOuter (o : CpiAtaOuterOnlyBindingV1) : String :=
  s!"oo{o.outerOnlyIndex}:role{o.roleId}:local{o.localIndex}:os{o.outerSigner}:ow{o.outerWritable}"

private def renderArgCheck : CpiAtaArgCheckV1 → String
  | .unusedPlaceholder => "unused"

private def renderKind : CpiAtaKindV1 → String
  | .createIdempotent => "createIdempotent"

private def renderInvoke (i : CpiAtaInvokeV1) : String :=
  let metas := String.intercalate "," (i.metas.map renderMeta).toList
  let oos := String.intercalate "," (i.outerOnly.map renderOuter).toList
  let sg := match i.signerGroupId with
    | none => "none"
    | some id => toString id
  let rule := match i.pdaRule with
    | none => "none"
    | some r => r
  s!"invokeAta:{i.siteId}:{renderKind i.kind}:{i.qn}:{i.packageId}:prog{i.programLocalIndex}:len{i.dataLen}:payer[{renderPrincipal i.payer}]:ata[{renderPrincipal i.ata}]:wallet[{renderPrincipal i.wallet}]:mint[{renderPrincipal i.mint}]:systemLocal{i.systemProgramLocalIndex}:tokenLocal{i.tokenProgramLocalIndex}:metas[{metas}]:outer[{oos}]:sg{sg}:{rule}:infos{i.accountInfoCount}"

private def renderSiteCheck : CpiAtaSiteCheckV1 → String
  | .generic op => s!"generic:{preflightOpKindNameV1 op}"
  | .ataAddressCanonical ata wallet token mint program =>
      s!"ataAddressCanonical:ata{ata}:wallet{wallet}:token{token}:mint{mint}:program{program}"
  | .ataAccountPrestateClosed ata wallet mint system token =>
      s!"ataAccountPrestateClosed:ata{ata}:wallet{wallet}:mint{mint}:system{system}:token{token}"
  | .tokenMintInitialized li => s!"tokenMintInitialized:local{li}"

private def renderBodyOp : CpiAtaBodyOpV1 → String
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
  | .invokeAta inv => renderInvoke inv
  | .returnU64 t => s!"returnU64:{t}"
  | .returnNone => "returnNone"

private def renderMode : HandlerModeV1 → String
  | .initialize => "initialize"
  | .entry => "entry"
  | .view => "view"

private def renderHandler (h : CpiAtaHandlerIRV1) : String :=
  let entry := String.intercalate ";" (h.entryGlobalOps.map preflightOpKindNameV1).toList
  let body := String.intercalate ";" (h.bodyOps.map renderBodyOp).toList
  s!"handler:{h.handlerId}:{h.callableId}:{h.name}:{renderMode h.mode}:roles{h.localRoleCount}:probe{h.probeIxDataLen}:temps{h.tempCount}:entry[{entry}]:body[{body}]"

private def renderCandidate (c : SolanaCpiAtaIRCandidateV1) : CompileResult String := do
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

/-- Validate ATA custom checks against their following invoke. Public so
    focused tests can mutate structural candidates without forging authority. -/
def validateSolanaCpiAtaIRCandidateV1
    (candidate : SolanaCpiAtaIRCandidateV1) : CompileResult Unit := do
  unless candidate.schema == ataIrSchemaV1 do
    tFail s!"schema must be {ataIrSchemaV1}"
  unless candidate.maxOuterRoles == maxOuterRolesV1 &&
      candidate.maxFrameBytes == 4096 &&
      candidate.abiLayout == frozenLoaderV3AbiLayoutV1 do
    tFail "ATA IR caps/ABI must equal frozen v1"
  for h in candidate.handlers do
    unless h.localRoleCount ≤ maxOuterRolesV1 &&
        h.localRoleOrder.size == h.localRoleCount do
      tFail s!"handler {h.handlerId} local role shape diverged"
    for li in [0:h.localRoleOrder.size] do
      let role ← getArr h.localRoleOrder li "candidate local roles"
      unless role.localIndex == li do
        tFail s!"handler {h.handlerId} local roles are not dense"
    let ops := h.bodyOps
    for i in [0:ops.size] do
      match ops[i]! with
      | .siteArgChecks sid checks =>
          unless checks.isEmpty do
            tFail s!"siteArgChecks {sid} must be empty for ATA"
          unless i + 2 < ops.size do
            tFail s!"siteArgChecks {sid} not followed by siteChecks+invoke"
          match ops[i + 1]!, ops[i + 2]! with
          | .siteChecks sid2 _, .invokeAta inv =>
              unless sid2 == sid && inv.siteId == sid do
                tFail s!"siteArgChecks {sid} following site id diverged"
          | _, _ => tFail s!"siteArgChecks {sid} must precede siteChecks→invokeAta"
      | .siteChecks sid checks =>
          if i == 0 || i + 1 ≥ ops.size then
            tFail s!"siteChecks {sid} lacks adjacent guards/invoke"
          match ops[i - 1]!, ops[i + 1]! with
          | .siteArgChecks sid0 _, .invokeAta inv =>
              unless sid0 == sid && inv.siteId == sid do
                tFail s!"siteChecks {sid} adjacent site id diverged"
              let mut addressCount := 0
              let mut prestateCount := 0
              let mut mintInitCount := 0
              for c in checks do
                match c with
                | .generic _ => pure ()
                | .ataAddressCanonical ata wallet token mint program =>
                    unless ata < h.localRoleCount && wallet < h.localRoleCount &&
                        token < h.localRoleCount && mint < h.localRoleCount &&
                        program < h.localRoleCount do
                      tFail s!"site {sid}: ATA address-check local out of range"
                    unless ata == inv.ata.localIndex && wallet == inv.wallet.localIndex &&
                        token == inv.tokenProgramLocalIndex && mint == inv.mint.localIndex &&
                        program == inv.programLocalIndex do
                      tFail s!"site {sid}: ATA address-check does not exact-join invoke"
                    addressCount := addressCount + 1
                | .ataAccountPrestateClosed ata wallet mint system token =>
                    unless ata < h.localRoleCount && wallet < h.localRoleCount &&
                        mint < h.localRoleCount && system < h.localRoleCount &&
                        token < h.localRoleCount do
                      tFail s!"site {sid}: ATA prestate local out of range"
                    unless ata == inv.ata.localIndex && wallet == inv.wallet.localIndex &&
                        mint == inv.mint.localIndex &&
                        system == inv.systemProgramLocalIndex &&
                        token == inv.tokenProgramLocalIndex do
                      tFail s!"site {sid}: ATA prestate does not exact-join invoke"
                    prestateCount := prestateCount + 1
                | .tokenMintInitialized li =>
                    unless li == inv.mint.localIndex && li < h.localRoleCount do
                      tFail s!"site {sid}: mint initialized check does not join invoke.mint"
                    mintInitCount := mintInitCount + 1
              unless addressCount == 1 && prestateCount == 1 && mintInitCount == 1 do
                tFail s!"site {sid}: ATA requires exactly one address/prestate/mint-init check"
          | _, _ => tFail s!"siteChecks {sid} must be between siteArgChecks and invokeAta"
      | .invokeAta inv =>
          unless inv.kind == .createIdempotent &&
              inv.qn == "solana.ata.createIdempotent" &&
              inv.packageId == "ata-classic-v1" &&
              inv.dataLen == 1 && inv.metas.size == 6 &&
              inv.outerOnly.isEmpty && inv.signerGroupId.isNone &&
              inv.pdaRule == some "ata-classic-v1" &&
              inv.accountInfoCount == h.localRoleCount do
            tFail s!"invokeAta site {inv.siteId} frozen shape diverged"
          unless inv.programLocalIndex < h.localRoleCount &&
              inv.systemProgramLocalIndex < h.localRoleCount &&
              inv.tokenProgramLocalIndex < h.localRoleCount do
            tFail s!"invokeAta site {inv.siteId} fixed local out of range"
          let programRole ← getArr h.localRoleOrder inv.programLocalIndex "ATA program role"
          let systemRole ← getArr h.localRoleOrder inv.systemProgramLocalIndex "System role"
          let tokenRole ← getArr h.localRoleOrder inv.tokenProgramLocalIndex "Token role"
          match programRole.keyPolicy, systemRole.keyPolicy, tokenRole.keyPolicy with
          | .fixedProgram "ata-classic-v1", .fixedProgram "system-v1",
              .fixedProgram "token-classic-v1" => pure ()
          | _, _, _ => tFail s!"invokeAta site {inv.siteId} fixed-role identity diverged"
          let expected : Array (CpiAtaPrincipalBindingV1 × Bool × Bool) := #[
            (inv.payer, true, true),
            (inv.ata, true, false),
            (inv.wallet, false, false),
            (inv.mint, false, false)
          ]
          for mi in [0:4] do
            let (binding, writable, signer) := expected[mi]!
            let m := inv.metas[mi]!
            unless m.metaIndex == mi && m.roleId == binding.roleId &&
                m.localIndex == binding.localIndex &&
                m.cpiWritable == writable && m.cpiSigner == signer &&
                m.signerGroupId.isNone do
              tFail s!"invokeAta site {inv.siteId} principal meta {mi} diverged"
          let systemMeta := inv.metas[4]!
          let tokenMeta := inv.metas[5]!
          unless systemMeta.metaIndex == 4 &&
              systemMeta.localIndex == inv.systemProgramLocalIndex &&
              systemMeta.cpiWritable == false && systemMeta.cpiSigner == false &&
              systemMeta.signerGroupId.isNone &&
              tokenMeta.metaIndex == 5 &&
              tokenMeta.localIndex == inv.tokenProgramLocalIndex &&
              tokenMeta.cpiWritable == false && tokenMeta.cpiSigner == false &&
              tokenMeta.signerGroupId.isNone do
            tFail s!"invokeAta site {inv.siteId} fixed program metas diverged"
          if i < 2 then
            tFail s!"invokeAta site {inv.siteId} missing preceding checks"
          else
            match ops[i - 2]!, ops[i - 1]! with
            | .siteArgChecks sid0 _, .siteChecks sid1 _ =>
                unless sid0 == inv.siteId && sid1 == inv.siteId do
                  tFail s!"invokeAta site {inv.siteId} preceding site id mismatch"
            | _, _ => tFail s!"invokeAta site {inv.siteId} must follow checks"
      | _ => pure ()
  pure ()

/-- Sole mint of the #123 ATA execution IR from Semantic-bound Plan. -/
def resolveSolanaCpiAtaIRV1
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult ResolvedSolanaCpiAtaIRV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    tFail "ATA CPI IR requires activationDenied preflight carrier"
  let candidate ← projectAtaCandidate authority
  validateSolanaCpiAtaIRCandidateV1 candidate
  let text ← renderCandidate candidate
  let canonicalBytes := text.toUTF8
  let digest ← mapExcept
    (domainSeparatedSha256 ataIrDigestDomainV1 canonicalBytes)
    "ata-ir digest"
  pure ⟨authority, candidate, canonicalBytes, digest⟩

/-- ATA scratch: data16 + Seed[3]48 + keyOut32 + bumpOut8 +
    Meta[6]96 + Instruction40 + AccountInfo[56*N] = 240 + 56N. -/
def ataCpiScratchCreateIdempotentV1 (localRoleCount : Nat) : Nat :=
  240 + localRoleCount * 56

/-- Max site scratch across handlers. -/
def ataMaxSiteScratchV1 (c : SolanaCpiAtaIRCandidateV1) : Nat :=
  Id.run do
    let mut maxB : Nat := 0
    for h in c.handlers do
      for op in h.bodyOps do
        match op with
        | .invokeAta inv =>
            let b := ataCpiScratchCreateIdempotentV1 inv.accountInfoCount
            if b > maxB then maxB := b
        | _ => pure ()
    pure maxB

end ProofForgeV2.Targets.Solana.CpiV1

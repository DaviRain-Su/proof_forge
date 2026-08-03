/-
  ProofForgeV2.Targets.Solana.CpiSystemIRV1 — #121 System program CPI IR.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole mint: `resolveSolanaCpiSystemIRV1`. Consumes only private Semantic-bound
  `SolanaCpiPreflightPlanV1` (NOT `ResolvedSolanaCpiPreflightIRV1`, which
  rejects PDA/systemCreateAccount). Freshly derives/joins validated CpiIR and
  mints private `ResolvedSolanaCpiSystemIRV1`.

  * admits only `solana.system.transfer` and `solana.system.createPdaAccount`;
  * single-block straight-line initializer/entry/view;
  * narrow public Principal/UInt64/UInt8 + state/literal/checked add/return;
  * transfer: data `u32le(2)||u64le(lamports)` = 12B; metas payer writable
    outer/CPI signer, recipient writable non-signer; zero signer groups;
  * createPdaAccount: data `u32le(0)||lamports||space||currentProgramId32` = 52B;
    metas payer writable outer/CPI signer, pda writable CPI signer group0
    outer non-signer; seedAuthority outer-only readonly non-signer;
    space ≤ 4096; canonical recipe current-program-tagged-v1;
  * System package exact system-v1 / zero pubkey / runtime-native;
  * per site: siteArgChecks → siteChecks → invoke (source order);
  * rejects companion/Token/ATA/schedule/constants/invariants/multiblock/loops.

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

def systemIrSchemaV1 : String := "proof-forge.solana.cpi-system-ir.v1"
def systemIrDigestDomainV1 : String := "pf.solana.cpi-system-ir.v1"

/-- UInt64 value sources for lamports / space / seedTag. -/
inductive CpiSystemU64SourceV1 where
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  | literal (value : UInt64)
  deriving BEq, Repr, Inhabited

/-- UInt8 value sources for bump (literal 0 rejected at IR mint). -/
inductive CpiSystemU8SourceV1 where
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  | literal (value : UInt8)
  deriving BEq, Repr, Inhabited

/-- One CPI meta binding to a handler-local role. -/
structure CpiSystemMetaV1 where
  metaIndex : Nat
  roleId : Nat
  localIndex : Nat
  cpiWritable : Bool
  cpiSigner : Bool
  signerGroupId : Option Nat
  deriving BEq, Repr, Inhabited

/-- Exact Semantic Principal → callable parameter → role → dense local join. -/
structure CpiSystemPrincipalBindingV1 where
  argIndex : Nat
  semanticValueId : Nat
  paramOrdinal : Nat
  roleId : Nat
  localIndex : Nat
  deriving BEq, Repr, Inhabited

/-- Outer-only account binding (seedAuthority for createPdaAccount). -/
structure CpiSystemOuterOnlyBindingV1 where
  outerOnlyIndex : Nat
  roleId : Nat
  localIndex : Nat
  outerSigner : Bool
  outerWritable : Bool
  deriving BEq, Repr, Inhabited

/-- Closed site-arg preflight predicate (currently space ≤ 4096). -/
inductive CpiSystemArgCheckV1 where
  | uint64AtMost (argName : String) (source : CpiSystemU64SourceV1) (maxValue : Nat)
  deriving BEq, Repr, Inhabited

/-- System API kind. -/
inductive CpiSystemKindV1 where
  | transfer
  | createPdaAccount
  deriving BEq, Repr, Inhabited

/-- Site-local System invoke (transfer or createPdaAccount only). -/
structure CpiSystemInvokeV1 where
  siteId : Nat
  kind : CpiSystemKindV1
  qn : String
  packageId : String
  programLocalIndex : Nat
  dataLen : Nat
  payer : CpiSystemPrincipalBindingV1
  /-- transfer recipient; none for create. -/
  recipient : Option CpiSystemPrincipalBindingV1
  /-- create pda target; none for transfer. -/
  pda : Option CpiSystemPrincipalBindingV1
  /-- create seedAuthority; none for transfer. -/
  seedAuthority : Option CpiSystemPrincipalBindingV1
  seedTag : Option CpiSystemU64SourceV1
  bump : Option CpiSystemU8SourceV1
  lamports : CpiSystemU64SourceV1
  space : Option CpiSystemU64SourceV1
  metas : Array CpiSystemMetaV1
  outerOnly : Array CpiSystemOuterOnlyBindingV1
  /-- none for transfer; some 0 for create. -/
  signerGroupId : Option Nat
  /-- none for transfer; some current-program-tagged-v1 for create. -/
  pdaRule : Option String
  accountInfoCount : Nat
  deriving BEq, Repr

/-- Ordered body operations after handler-entry global preflight. -/
inductive CpiSystemBodyOpV1 where
  | loadParamU64 (tempId : Nat) (ixDataOffset : Nat)
  | loadParamU8 (tempId : Nat) (ixDataOffset : Nat)
  | loadLiteralU64 (tempId : Nat) (value : UInt64)
  | loadLiteralU8 (tempId : Nat) (value : UInt8)
  | stateLoadU64 (tempId : Nat) (stateLocalIndex : Nat) (byteOffset : Nat)
  | checkedAddU64 (dstTemp lhsTemp rhsTemp : Nat)
  | stateStoreU64 (stateLocalIndex : Nat) (byteOffset : Nat) (srcTemp : Nat)
    (writeInitializedMarker : Bool) (initializedMarker : UInt64)
  /-- Site-arg preflight (e.g. space ≤ 4096); must run before siteChecks. -/
  | siteArgChecks (siteId : Nat) (checks : Array CpiSystemArgCheckV1)
  /-- Site-time account predicates (must run immediately before invoke). -/
  | siteChecks (siteId : Nat) (ops : Array CpiPreflightOpV1)
  | invokeSystem (invoke : CpiSystemInvokeV1)
  | returnU64 (srcTemp : Nat)
  | returnNone
  deriving BEq, Repr, Inhabited

structure CpiSystemHandlerIRV1 where
  handlerId : Nat
  callableId : Nat
  name : String
  mode : HandlerModeV1
  localRoleCount : Nat
  localRoleOrder : Array CpiIRRoleHandleV1
  accountParameterBindings : Array CpiPreflightAccountParamBindingV1
  probeIxDataLen : Nat
  entryGlobalOps : Array CpiPreflightOpV1
  bodyOps : Array CpiSystemBodyOpV1
  tempCount : Nat
  deriving BEq, Repr

structure SolanaCpiSystemIRCandidateV1 where
  schema : String
  sourcePlanDigest : Digest
  sourceIrDigest : Digest
  profileId : String
  profileDigest : Digest
  catalogDigest : Digest
  abiLayout : LoaderV3AbiLayoutV1
  maxOuterRoles : Nat
  maxFrameBytes : Nat
  handlers : Array CpiSystemHandlerIRV1
  deriving BEq

/-- Private resolved System IR. Sole mint from Semantic-bound preflight Plan. -/
structure ResolvedSolanaCpiSystemIRV1 where
  private mk ::
  authority : SolanaCpiPreflightPlanV1
  candidate : SolanaCpiSystemIRCandidateV1
  canonicalBytes : ByteArray
  digest : Digest

namespace ResolvedSolanaCpiSystemIRV1

def authorityOf (r : ResolvedSolanaCpiSystemIRV1) : SolanaCpiPreflightPlanV1 :=
  r.authority
def candidateOf (r : ResolvedSolanaCpiSystemIRV1) : SolanaCpiSystemIRCandidateV1 :=
  r.candidate
def digestOf (r : ResolvedSolanaCpiSystemIRV1) : Digest :=
  r.digest
def canonicalBytesOf (r : ResolvedSolanaCpiSystemIRV1) : ByteArray :=
  r.canonicalBytes

end ResolvedSolanaCpiSystemIRV1

/-! ## Internals -/

private def sFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def mapExcept (e : Except String α) (ctx : String) : CompileResult α :=
  match e with
  | .ok v => pure v
  | .error msg => sFail s!"{ctx}: {msg}"

private def digestsEqual (left right : Digest) : Bool :=
  left.algorithm == right.algorithm && left.bytes == right.bytes

private def getArr (arr : Array α) (i : Nat) (ctx : String) : CompileResult α :=
  match arr[i]? with
  | some v => pure v
  | none => sFail s!"{ctx}: index {i} out of range"

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
    sFail s!"UInt64 valueBytes must be exact 8 bytes, got {bytes.size}"
  let mut n : Nat := 0
  for i in [0:8] do
    n := n + bytes[i]!.toNat * (Nat.pow 2 (8 * i))
  pure (UInt64.ofNat n)

private def decodeUInt8 (bytes : ByteArray) : CompileResult UInt8 := do
  unless bytes.size == 1 do
    sFail s!"UInt8 valueBytes must be exact 1 byte, got {bytes.size}"
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
  | .state _ | .accountParameter .. => none

private def requireSystemPackage : CompileResult FrozenCalleePackage := do
  match findCalleePackage? "system-v1" with
  | none => sFail "system-v1 missing from frozen callee catalog"
  | some package =>
      unless package.packageId == "system-v1" do
        sFail "system package id diverged"
      unless package.programId == systemProgramIdV1 do
        sFail "system-v1 program id must be the native zero pubkey"
      unless package.executionClass == .nativeSystem do
        sFail "system-v1 executionClass must be nativeSystem"
      match package.artifactBinding with
      | .runtimeNative commit =>
          unless commit == agaveV400CommitV1 do
            sFail "system-v1 runtime-native binding must pin agave v4.0.0 commit"
      | .absent =>
          sFail "system-v1 must be runtime-native (no System ELF artifact)"
      pure package

/-- System-aware owner resolution. -/
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
          sFail s!"owner fixedProgram package '{packageId}' missing from catalog"
  | .catalogExecutionClass =>
      let packageId ← match catalogPackageId? with
        | some id => pure id
        | none =>
            sFail "catalogExecutionClass owner requires a fixed-program package context"
      match findCalleePackage? packageId with
      | some package =>
          pure #[.checkOwnerExact localIndex
            (executionClassOwnerPubkeyV1 package.executionClass)]
      | none =>
          sFail s!"catalogExecutionClass package '{packageId}' missing from catalog"
  | .any => pure #[]
  | .closedPackages _ =>
      sFail "System CPI IR rejects closedPackages owner (Token/ATA deferred)"

private def resolveExecutableOps
    (localIndex : Nat) (exec : ExecutablePolicy) : Array CpiPreflightOpV1 :=
  match exec with
  | .required => #[.checkExecutableRequired localIndex]
  | .forbidden => #[.checkExecutableForbidden localIndex]

/-- Admit systemCreateAccount + uninitialized (create target); reject Token/ATA. -/
private def resolveDataAndInitOps
    (localIndex : Nat)
    (mode : HandlerModeV1)
    (keyPolicy : RoleKeyPolicyV1)
    (data : DataPolicy)
    (init : InitializationPolicy)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult (Array CpiPreflightOpV1) := do
  match init with
  | .uninitialized =>
      -- createPdaAccount target: exact empty data/lamports checked via data policy.
      pure ()
  | .canonicalPda =>
      pure ()
  | .uninitializedOrIdempotentlyInitialized =>
      sFail "System CPI IR rejects ATA initialization"
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
        | _ => sFail "proofForgeState data requires RoleKeyPolicyV1.state"
      let schema ← match findStateSchema? stateSchemas schemaId with
        | some s => pure s
        | none => sFail s!"proofForgeState schemaId {schemaId} missing"
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
      sFail "System CPI IR rejects classicTokenAccount data"
  | .classicTokenMint .. =>
      sFail "System CPI IR rejects classicTokenMint data"
  | .ataAccount .. =>
      sFail "System CPI IR rejects ataAccount data"
  pure ops

private def resolveProvisioning (prov : ProvisioningPolicy) : CompileResult Unit := do
  match prov with
  | .none | .mustExist | .systemCreateAccount => pure ()
  | .ataCreateIdempotent =>
      sFail "System CPI IR rejects ataCreateIdempotent provisioning"

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
    sFail s!"handler local role count {n} exceeds maxOuterRoles {maxOuterRolesV1}"
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
            sFail s!"fixedProgram package '{packageId}' missing from frozen catalog"
    | .accountParameter callableId paramOrdinal =>
        bindings := bindings.push {
          callableId
          paramOrdinal
          roleId := handle.roleId
          localIndex := i
        }
    | .state _ => pure ()
    let constraintOps ← projectConstraintOps i mode handle.keyPolicy
      handle.constraint stateSchemas
    ops := ops ++ constraintOps
    ops := ops.push (.checkEffectiveSigner i (effectiveSigner handle))
    ops := ops.push (.checkEffectiveWritable i (effectiveWritable handle))
  pure (bindings, ops)

private def projectSiteChecks
    (mode : HandlerModeV1)
    (handles : Array CpiIRRoleHandleV1)
    (site : CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult (Array CpiPreflightOpV1) := do
  let mut ops : Array CpiPreflightOpV1 := #[]
  for pred in site.sitePredicates do
    let handle ← match handles.find? (fun h => h.roleId == pred.roleId) with
      | some h => pure h
      | none =>
          sFail s!"site predicate roleId {pred.roleId} missing from handler locals"
    unless handle.localIndex < handles.size do
      sFail s!"site predicate roleId {pred.roleId} has out-of-range localIndex"
    let denseHandle ← getArr handles handle.localIndex "site predicate dense local handles"
    unless denseHandle.roleId == handle.roleId &&
        denseHandle.localIndex == handle.localIndex do
      sFail s!"site predicate roleId {pred.roleId} has non-dense local handle"
    let packageOverride : Option String :=
      match pred.source with
      | .callee => some site.packageId
      | .metaIndex _ | .outerOnlyIndex _ => none
    let predOps ← projectConstraintOps handle.localIndex mode handle.keyPolicy
      pred.constraint stateSchemas packageOverride
    ops := ops ++ predOps
  pure ops

/-- Non-Principal public params → packed probe offsets in declaration order. -/
private def buildParamIxLayout
    (types : Array TypeDeclV1) (callable : CallableV1) :
    CompileResult (Array (Nat × Nat × Nat) × Nat) := do
  let mut layout : Array (Nat × Nat × Nat) := #[]
  let mut offset : Nat := 8
  for (p, ord) in callable.params.zipIdx do
    unless p.visibility == VisibilityV1.public_ do
      sFail "System CPI IR requires public parameters only"
    if isAnonPrincipal types p.typeId then
      pure ()
    else if anonUintWidth? types p.typeId == some 64 then
      layout := layout.push (ord, offset, 64)
      offset := offset + 8
    else if anonUintWidth? types p.typeId == some 8 then
      layout := layout.push (ord, offset, 8)
      offset := offset + 1
    else
      sFail
        s!"System CPI IR admits only public Principal/UInt64/UInt8 params, got '{p.name}'"
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
    sFail
      s!"System CPI IR requires single-block straight-line callables (got {callable.blocks.size} blocks)"
  unless callable.entryBlock.toNat == 0 do
    sFail "System CPI IR requires entryBlock == 0"
  unless callable.loopBounds.isEmpty do
    sFail "System CPI IR rejects loopBounds (no back edges)"
  let blk ← getArr callable.blocks 0 "callable.blocks"
  unless blk.id.toNat == 0 do
    sFail "System CPI IR requires sole block id == 0"
  unless blk.params.isEmpty do
    sFail "System CPI IR rejects block parameters"
  pure blk

private def localIndexOfRole
    (handles : Array CpiIRRoleHandleV1) (roleId : Nat) : CompileResult Nat :=
  match handles.find? (fun h => h.roleId == roleId) with
  | some h => pure h.localIndex
  | none => sFail s!"roleId {roleId} missing from handler local roles"

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
    CompileResult CpiSystemPrincipalBindingV1 := do
  let paramOrdinal ← match directPublicPrincipalParamOrdinal? types callable vid with
    | some ord => pure ord
    | none =>
        sFail s!"site {site.siteId} arg {argIndex}: expected bare direct public Principal parameter"
  let arg ← getArr site.args argIndex s!"site {site.siteId}.args"
  unless arg.spec.type_ == FrozenValueType.principal &&
      arg.spec.source == ArgumentSource.bareDirectPublicPrincipalParameter do
    sFail s!"site {site.siteId} arg {argIndex}: frozen Principal source diverged"
  unless arg.semanticValueId == vid.toNat do
    sFail s!"site {site.siteId} arg {argIndex}: Semantic ValueId diverged from Plan binding"
  let roleId ← match arg.roleId with
    | some rid => pure rid
    | none => sFail s!"site {site.siteId} arg {argIndex}: Principal roleId missing"
  let handle ← match handles.find? (fun h => h.roleId == roleId) with
    | some h => pure h
    | none => sFail s!"site {site.siteId} arg {argIndex}: roleId {roleId} missing from handler"
  unless handle.localIndex < handles.size do
    sFail s!"site {site.siteId} arg {argIndex}: localIndex out of range"
  let denseHandle ← getArr handles handle.localIndex "handler dense local handles"
  unless denseHandle.roleId == roleId && denseHandle.localIndex == handle.localIndex do
    sFail s!"site {site.siteId} arg {argIndex}: local handle is not dense/exact"
  match handle.keyPolicy with
  | .accountParameter callableId boundOrdinal =>
      unless callableId == callable.id.toNat && boundOrdinal == paramOrdinal do
        sFail s!"site {site.siteId} arg {argIndex}: account role does not bind the exact callable parameter"
  | _ =>
      sFail s!"site {site.siteId} arg {argIndex}: Principal role is not accountParameter-bound"
  let paramBindings := bindings.filter (fun b =>
    b.callableId == callable.id.toNat && b.paramOrdinal == paramOrdinal)
  unless paramBindings.size == 1 do
    sFail s!"site {site.siteId} arg {argIndex}: expected exactly one preflight binding for the parameter"
  let exactBinding ← getArr paramBindings 0 "Principal preflight parameter binding"
  unless exactBinding.roleId == roleId &&
      exactBinding.localIndex == handle.localIndex do
    sFail s!"site {site.siteId} arg {argIndex}: preflight binding role/local index diverged"
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
    CompileResult CpiSystemU64SourceV1 := do
  match findLiteralU64? types callable vid with
  | some v => pure (.literal v)
  | none =>
      match directPublicU64ParamOrdinal? types callable vid with
      | some ord =>
          match ixOffsetOfParam? layout ord with
          | some (off, w) =>
              unless w == 64 do
                sFail s!"{ctx}: UInt64 param ordinal {ord} has wrong width slot"
              pure (.param ord off)
          | none =>
              sFail s!"{ctx}: UInt64 param ordinal {ord} missing from probe layout"
      | none =>
          sFail
            s!"{ctx}: admits only direct public UInt64 param or UInt64 literal"

private def resolveU8Source
    (types : Array TypeDeclV1) (callable : CallableV1)
    (layout : Array (Nat × Nat × Nat)) (vid : ValueIdV1) (ctx : String)
    (rejectZeroLiteral : Bool) :
    CompileResult CpiSystemU8SourceV1 := do
  match findLiteralU8? types callable vid with
  | some v =>
      if rejectZeroLiteral && v == 0 then
        sFail s!"{ctx}: bump literal 0 is rejected (canonical search is 255..1)"
      pure (.literal v)
  | none =>
      match directPublicU8ParamOrdinal? types callable vid with
      | some ord =>
          match ixOffsetOfParam? layout ord with
          | some (off, w) =>
              unless w == 8 do
                sFail s!"{ctx}: UInt8 param ordinal {ord} has wrong width slot"
              pure (.param ord off)
          | none =>
              sFail s!"{ctx}: UInt8 param ordinal {ord} missing from probe layout"
      | none =>
          sFail
            s!"{ctx}: admits only direct public UInt8 param or UInt8 literal"

private def projectMetas
    (handles : Array CpiIRRoleHandleV1) (site : CpiIRSiteV1) :
    CompileResult (Array CpiSystemMetaV1) := do
  let mut metas : Array CpiSystemMetaV1 := #[]
  for m in site.metas do
    let li ← localIndexOfRole handles m.roleId
    unless m.localHandleIndex == li do
      sFail s!"site {site.siteId} meta {m.metaIndex} local handle diverged"
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
    (_types : Array TypeDeclV1) (_callable : CallableV1)
    (_layout : Array (Nat × Nat × Nat))
    (site : CpiIRSiteV1)
    (spaceSrc? : Option CpiSystemU64SourceV1) :
    CompileResult (Array CpiSystemArgCheckV1) := do
  let mut checks : Array CpiSystemArgCheckV1 := #[]
  for pred in site.preflight do
    match pred with
    | .uint64AtMost argName maxValue =>
        unless argName == "space" do
          sFail s!"site {site.siteId}: unknown preflight arg '{argName}'"
        unless maxValue == maxPdaSpaceBytesV1 do
          sFail s!"site {site.siteId}: space cap must be {maxPdaSpaceBytesV1}"
        let src ← match spaceSrc? with
          | some s => pure s
          | none => sFail s!"site {site.siteId}: space source missing for uint64AtMost"
        -- Compile-time reject literal over cap.
        match src with
        | .literal v =>
            unless v.toNat ≤ maxValue do
              sFail
                s!"site {site.siteId}: space literal {v.toNat} exceeds cap {maxValue}"
        | .param .. => pure ()
        checks := checks.push (.uint64AtMost argName src maxValue)
  -- Guard: create must carry exact frozen space preflight.
  if site.qn == "solana.system.createPdaAccount" then
    unless checks.size == 1 do
      sFail s!"site {site.siteId}: createPdaAccount requires exact space preflight"
  else if site.qn == "solana.system.transfer" then
    unless checks.isEmpty && site.preflight.isEmpty do
      sFail s!"site {site.siteId}: transfer must have empty preflight"
  pure checks

private def projectSystemHandler
    (abi : LoaderV3AbiLayoutV1)
    (data : SemanticProgramDataV1)
    (planHandler : HandlerPlanV1)
    (handles : Array CpiIRRoleHandleV1)
    (sites : Array CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult CpiSystemHandlerIRV1 := do
  let _systemPkg ← requireSystemPackage
  let callable ← getArr data.callables planHandler.callableId "callables"
  unless callable.id.toNat == planHandler.callableId do
    sFail "handler callableId must equal Semantic callable.id"
  unless callable.blocks.size ≥ 1 do
    sFail "callable has no blocks"
  unless handles.size == planHandler.accountUses.size do
    sFail "handler local handle count must equal Plan accountUses size"
  for i in [0:handles.size] do
    let handle ← getArr handles i "handler local handles"
    let use ← getArr planHandler.accountUses i "handler accountUses"
    unless handle.handlerId == planHandler.handlerId &&
        handle.localIndex == i && use.position == i &&
        handle.roleId == use.roleId do
      sFail s!"handler {planHandler.handlerId} local handle order diverged at {i}"
  for site in sites do
    unless site.handlerId == planHandler.handlerId do
      sFail "site handlerId mismatch"
    unless site.packageId == "system-v1" do
      sFail
        s!"System CPI admits only system-v1, got '{site.packageId}' at site {site.siteId}"
    unless site.programKey == systemProgramIdV1 do
      sFail s!"site {site.siteId}: System program key must be zero pubkey"
    match site.qn with
    | "solana.system.transfer" =>
        unless site.pda == .none do
          sFail s!"transfer site {site.siteId} must have pda.none"
        unless site.signerGroups.isEmpty do
          sFail s!"transfer site {site.siteId} requires zero signer groups"
        unless site.outerOnlyAccounts.isEmpty do
          sFail s!"transfer site {site.siteId} requires empty outer-only"
        unless site.metas.size == 2 do
          sFail s!"transfer site {site.siteId} requires exactly two metas"
        unless site.args.size == 3 do
          sFail s!"transfer site {site.siteId} requires exactly three args"
        unless site.instructionCodec.length == 12 do
          sFail s!"transfer site {site.siteId} dataLen must be 12"
        unless site.preflight.isEmpty do
          sFail s!"transfer site {site.siteId} must have empty preflight"
    | "solana.system.createPdaAccount" =>
        match site.pda with
        | .signer rule targetArg seedAuthArg seedTagArg bumpArg signerArg =>
            unless rule == "current-program-tagged-v1" do
              sFail s!"site {site.siteId}: PDA rule must be current-program-tagged-v1"
            unless targetArg == "pda" && seedAuthArg == "seedAuthority" &&
                seedTagArg == "seedTag" && bumpArg == "bump" &&
                signerArg == "pda" do
              sFail s!"site {site.siteId}: PDA arg names must match frozen createPdaAccount"
        | .none =>
            sFail s!"createPdaAccount requires PDA signer use at site {site.siteId}"
        | .addressCheckOnly .. =>
            sFail s!"System CPI rejects addressCheckOnly at site {site.siteId}"
        unless site.signerGroups.size == 1 do
          sFail s!"site {site.siteId}: exact one signer group required"
        let group ← getArr site.signerGroups 0 s!"site {site.siteId}.signerGroups"
        unless group.id == 0 && group.metaArg == "pda" &&
            group.pdaRule == "current-program-tagged-v1" do
          sFail s!"site {site.siteId}: signer group must be id0/pda/current-program-tagged-v1"
        unless site.metas.size == 2 do
          sFail s!"site {site.siteId}: createPdaAccount requires exactly two metas"
        unless site.outerOnlyAccounts.size == 1 do
          sFail s!"site {site.siteId}: createPdaAccount requires exactly one outer-only"
        unless site.args.size == 7 do
          sFail s!"site {site.siteId}: createPdaAccount requires exactly seven args"
        unless site.instructionCodec.length == 52 do
          sFail s!"site {site.siteId}: createPdaAccount dataLen must be 52"
        unless site.preflight == #[.uint64AtMost "space" maxPdaSpaceBytesV1] do
          sFail s!"site {site.siteId}: createPdaAccount preflight must be space≤4096"
    | other =>
        sFail
          s!"System CPI admits only solana.system.transfer|createPdaAccount, got '{other}'"

  let blk ← requireStraightLineCallable callable
  let (paramLayout, probeIxDataLen) ← buildParamIxLayout data.types callable
  let (bindings, entryGlobalOps) ←
    projectEntryGlobalOps abi planHandler.mode handles stateSchemas

  let mut tempOf : Array (Nat × Nat) := #[]
  let mut nextTemp : Nat := 0
  let mut body : Array CpiSystemBodyOpV1 := #[]

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
          sFail "literal must produce a result"
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
            sFail "System CPI IR admits only UInt64/UInt8 literals in body"
    | .stateLoad stateId =>
        let some vd := instr.result |
          sFail "stateLoad must produce a result"
        let (stateLocal, schema) ← match stateInfo? with
          | some s => pure s
          | none => sFail "stateLoad without state role"
        unless stateId.toNat == 0 do
          sFail "System CPI IR first slice admits only stateId 0"
        unless schema.exactDataLen == 16 do
          sFail "stateLoad requires single UInt64 state layout"
        let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
        tempOf := tempOf'
        nextTemp := next'
        body := body.push (.stateLoadU64 t stateLocal 8)
    | .stateStore stateId value =>
        let (stateLocal, schema) ← match stateInfo? with
          | some s => pure s
          | none => sFail "stateStore without state role"
        unless stateId.toNat == 0 do
          sFail "System CPI IR first slice admits only stateId 0"
        let src ← match lookupTemp tempOf value.toNat with
          | some t => pure t
          | none =>
              match directPublicU64ParamOrdinal? data.types callable value with
              | some ord =>
                  match ixOffsetOfParam? paramLayout ord with
                  | some (off, w) =>
                      unless w == 64 do
                        sFail "stateStore value width diverged"
                      let (t, tempOf', next') := allocTemp tempOf nextTemp value.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadParamU64 t off)
                      pure t
                  | none => sFail "stateStore value param missing from probe layout"
              | none =>
                  match findLiteralU64? data.types callable value with
                  | some lit =>
                      let (t, tempOf', next') := allocTemp tempOf nextTemp value.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadLiteralU64 t lit)
                      pure t
                  | none =>
                      sFail s!"stateStore value ValueId {value} is not materialised"
        let writeMarker := planHandler.mode == .initialize
        body := body.push
          (.stateStoreU64 stateLocal 8 src writeMarker schema.initializedMarker)
    | .binary opKind lhs rhs =>
        let some vd := instr.result |
          sFail "binary must produce a result"
        match opKind with
        | BinaryOpV1.add =>
            let l ← match lookupTemp tempOf lhs.toNat with
              | some t => pure t
              | none => sFail s!"checkedAdd lhs ValueId {lhs} not materialised"
            let r ← match lookupTemp tempOf rhs.toNat with
              | some t => pure t
              | none => sFail s!"checkedAdd rhs ValueId {rhs} not materialised"
            let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
            tempOf := tempOf'
            nextTemp := next'
            body := body.push (.checkedAddU64 t l r)
        | _ =>
            sFail "System CPI IR first slice admits only checked UInt64 add in body"
    | .externalCall effectId callee args =>
        let qnComps ← mapExcept (renderQualifiedNameComponents callee) "callee QN"
        let qn := String.intercalate "." qnComps.toList
        unless qn == "solana.system.transfer" ||
            qn == "solana.system.createPdaAccount" do
          sFail
            s!"System CPI admits only system.transfer|createPdaAccount, got '{qn}'"
        let site ← match sites.find? (fun s =>
            s.anchor.callableId == planHandler.callableId &&
              s.anchor.blockId == blk.id.toNat &&
              s.anchor.instructionIndex == instrIdx &&
              s.anchor.effectId == effectId.toNat) with
          | some s => pure s
          | none =>
              sFail
                s!"ExternalCall at instr {instrIdx} has no matching CPI site anchor"
        unless site.qn == qn do
          sFail "site QN diverges from Semantic ExternalCall"
        unless site.packageId == "system-v1" do
          sFail "ExternalCall package must be system-v1"
        let programLocal ← localIndexOfRole handles site.programRoleId
        unless site.programHandleIndex == programLocal do
          sFail s!"site {site.siteId} program handle index diverged"
        let metas ← projectMetas handles site
        if qn == "solana.system.transfer" then
          unless args.size == 3 && site.args.size == 3 do
            sFail "transfer requires exactly 3 Semantic and Plan args"
          let payerVid ← getArr args 0 "externalCall.args"
          let payerBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 0 payerVid
          let recipientVid ← getArr args 1 "externalCall.args"
          let recipientBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 1 recipientVid
          let lamportsVid ← getArr args 2 "externalCall.args"
          let lamportsArg ← getArr site.args 2 s!"site {site.siteId}.args"
          unless lamportsArg.semanticValueId == lamportsVid.toNat &&
              lamportsArg.roleId.isNone &&
              lamportsArg.spec.type_ == FrozenValueType.uint64 do
            sFail s!"site {site.siteId} lamports binding diverged"
          let lamportsSrc ← resolveU64Source data.types callable paramLayout lamportsVid
            s!"site {site.siteId} lamports"
          -- Meta[0] payer writable + CPI signer (outer signer too)
          let meta0 ← getArr site.metas 0 s!"site {site.siteId}.metas"
          unless meta0.metaIndex == 0 &&
              meta0.roleId == payerBinding.roleId &&
              meta0.localHandleIndex == payerBinding.localIndex &&
              meta0.spec.cpiWritable == true &&
              meta0.spec.cpiSigner == true &&
              meta0.spec.outerSignerContribution == true &&
              meta0.spec.outerWritableContribution == true &&
              meta0.spec.signerGroupId.isNone do
            sFail s!"site {site.siteId} payer meta must be writable outer/CPI signer"
          -- Meta[1] recipient writable non-signer
          let meta1 ← getArr site.metas 1 s!"site {site.siteId}.metas"
          unless meta1.metaIndex == 1 &&
              meta1.roleId == recipientBinding.roleId &&
              meta1.localHandleIndex == recipientBinding.localIndex &&
              meta1.spec.cpiWritable == true &&
              meta1.spec.cpiSigner == false &&
              meta1.spec.outerSignerContribution == false &&
              meta1.spec.outerWritableContribution == true &&
              meta1.spec.signerGroupId.isNone do
            sFail s!"site {site.siteId} recipient meta must be writable outer non-signer"
          let argChecks ← projectSiteArgChecks data.types callable paramLayout site none
          let siteOps ← projectSiteChecks planHandler.mode handles site stateSchemas
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeSystem {
            siteId := site.siteId
            kind := .transfer
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 12
            payer := payerBinding
            recipient := some recipientBinding
            pda := none
            seedAuthority := none
            seedTag := none
            bump := none
            lamports := lamportsSrc
            space := none
            metas
            outerOnly := #[]
            signerGroupId := none
            pdaRule := none
            accountInfoCount := handles.size
          })
        else
          -- createPdaAccount
          unless args.size == 7 && site.args.size == 7 do
            sFail "createPdaAccount requires exactly 7 Semantic and Plan args"
          let payerVid ← getArr args 0 "externalCall.args"
          let payerBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 0 payerVid
          let pdaVid ← getArr args 1 "externalCall.args"
          let pdaBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 1 pdaVid
          let seedAuthVid ← getArr args 2 "externalCall.args"
          let seedAuthBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 2 seedAuthVid
          let seedTagVid ← getArr args 3 "externalCall.args"
          let seedTagArg ← getArr site.args 3 s!"site {site.siteId}.args"
          unless seedTagArg.semanticValueId == seedTagVid.toNat &&
              seedTagArg.roleId.isNone &&
              seedTagArg.spec.type_ == FrozenValueType.uint64 do
            sFail s!"site {site.siteId} seedTag binding diverged"
          let seedTagSrc ← resolveU64Source data.types callable paramLayout seedTagVid
            s!"site {site.siteId} seedTag"
          let bumpVid ← getArr args 4 "externalCall.args"
          let bumpArg ← getArr site.args 4 s!"site {site.siteId}.args"
          unless bumpArg.semanticValueId == bumpVid.toNat &&
              bumpArg.roleId.isNone &&
              bumpArg.spec.type_ == FrozenValueType.uint8 do
            sFail s!"site {site.siteId} bump binding diverged"
          let bumpSrc ← resolveU8Source data.types callable paramLayout bumpVid
            s!"site {site.siteId} bump" true
          let lamportsVid ← getArr args 5 "externalCall.args"
          let lamportsArg ← getArr site.args 5 s!"site {site.siteId}.args"
          unless lamportsArg.semanticValueId == lamportsVid.toNat &&
              lamportsArg.roleId.isNone &&
              lamportsArg.spec.type_ == FrozenValueType.uint64 do
            sFail s!"site {site.siteId} lamports binding diverged"
          let lamportsSrc ← resolveU64Source data.types callable paramLayout lamportsVid
            s!"site {site.siteId} lamports"
          let spaceVid ← getArr args 6 "externalCall.args"
          let spaceArg ← getArr site.args 6 s!"site {site.siteId}.args"
          unless spaceArg.semanticValueId == spaceVid.toNat &&
              spaceArg.roleId.isNone &&
              spaceArg.spec.type_ == FrozenValueType.uint64 do
            sFail s!"site {site.siteId} space binding diverged"
          let spaceSrc ← resolveU64Source data.types callable paramLayout spaceVid
            s!"site {site.siteId} space"
          -- Meta[0] payer: CPI + outer signer/writable exact (frozen createPdaAccount).
          let meta0 ← getArr site.metas 0 s!"site {site.siteId}.metas"
          unless meta0.metaIndex == 0 &&
              meta0.roleId == payerBinding.roleId &&
              meta0.localHandleIndex == payerBinding.localIndex &&
              meta0.spec.cpiWritable == true &&
              meta0.spec.cpiSigner == true &&
              meta0.spec.outerSignerContribution == true &&
              meta0.spec.outerWritableContribution == true &&
              meta0.spec.signerGroupId.isNone do
            sFail s!"site {site.siteId} payer meta must be CPI+outer writable signer (no group)"
          -- Meta[1] pda: writable CPI signer group 0, outer non-signer, outer writable
          let meta1 ← getArr site.metas 1 s!"site {site.siteId}.metas"
          unless meta1.metaIndex == 1 &&
              meta1.roleId == pdaBinding.roleId &&
              meta1.localHandleIndex == pdaBinding.localIndex &&
              meta1.spec.cpiWritable == true &&
              meta1.spec.cpiSigner == true &&
              meta1.spec.outerSignerContribution == false &&
              meta1.spec.outerWritableContribution == true &&
              meta1.spec.signerGroupId == some 0 do
            sFail s!"site {site.siteId} pda meta must be writable CPI signer group 0 outer non-signer writable"
          -- Outer-only seedAuthority: readonly non-signer
          let oo0 ← getArr site.outerOnlyAccounts 0 s!"site {site.siteId}.outerOnly"
          unless oo0.roleId == seedAuthBinding.roleId &&
              oo0.localHandleIndex == seedAuthBinding.localIndex &&
              oo0.spec.outerSignerContribution == false &&
              oo0.spec.outerWritableContribution == false do
            sFail s!"site {site.siteId} seedAuthority outer-only must be readonly non-signer"
          let outerOnly : Array CpiSystemOuterOnlyBindingV1 := #[{
            outerOnlyIndex := 0
            roleId := oo0.roleId
            localIndex := oo0.localHandleIndex
            outerSigner := oo0.spec.outerSignerContribution
            outerWritable := oo0.spec.outerWritableContribution
          }]
          let argChecks ← projectSiteArgChecks data.types callable paramLayout site
            (some spaceSrc)
          let siteOps ← projectSiteChecks planHandler.mode handles site stateSchemas
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeSystem {
            siteId := site.siteId
            kind := .createPdaAccount
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 52
            payer := payerBinding
            recipient := none
            pda := some pdaBinding
            seedAuthority := some seedAuthBinding
            seedTag := some seedTagSrc
            bump := some bumpSrc
            lamports := lamportsSrc
            space := some spaceSrc
            metas
            outerOnly
            signerGroupId := some 0
            pdaRule := some "current-program-tagged-v1"
            accountInfoCount := handles.size
          })
    | .constant _cid =>
        sFail "System CPI IR rejects Op.Constant (constants table support deferred)"
    | .unary .. =>
        sFail "System CPI IR rejects unary ops in first slice"
    | .pureCall .. =>
        sFail "System CPI IR rejects pureCall in first slice"
    | .construct .. | .fieldGet .. | .fieldSet .. | .indexGet .. | .indexSet ..
    | .variantTag .. | .variantPayload .. | .checkedCast ..
    | .contextRead .. | .commit .. | .assert_ .. | .emit .. | .schedule .. =>
        sFail "System CPI IR rejects unsupported body op in first slice"

  match blk.terminator with
  | .return_ none =>
      body := body.push .returnNone
  | .return_ (some vid) =>
      if isAnonUnit data.types (← match typeOfValueId? callable vid with
          | some t => pure t
          | none => sFail "return value has no type") then
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
                        sFail "return param width diverged"
                      let (t, tempOf', next') := allocTemp tempOf nextTemp vid.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadParamU64 t off)
                      pure t
                  | none => sFail "return param missing from probe layout"
              | none =>
                  match findLiteralU64? data.types callable vid with
                  | some lit =>
                      let (t, tempOf', next') := allocTemp tempOf nextTemp vid.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadLiteralU64 t lit)
                      pure t
                  | none =>
                      sFail s!"return ValueId {vid} is not materialised"
        body := body.push (.returnU64 src)
  | .jump .. | .branch .. | .switch .. | .revert .. | .trap _ =>
      sFail "System CPI IR requires return terminator only (straight-line)"

  let bodySiteIds :=
    body.foldl (init := ([] : List Nat)) fun acc op =>
      match op with
      | .invokeSystem inv => acc ++ [inv.siteId]
      | _ => acc
  let planSiteIds := sites.map (·.siteId) |>.toList
  unless bodySiteIds == planSiteIds do
    sFail
      "System body invoke site order must equal Plan cpiSiteIds (source order)"

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

private def projectSystemCandidate
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult SolanaCpiSystemIRCandidateV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    sFail "System CPI IR requires activationDenied authority"
  let _ ← requireSystemPackage
  let plan := SolanaCpiPreflightPlanV1.planOf authority
  let compiled :=
    ResolvedSolanaCpiPreflightV1.compiledOf
      (SolanaCpiPreflightPlanV1.preflightOf authority)
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok v => pure v
    | .error _ =>
        sFail "System CPI IR: retained Semantic failed structure validation"
  unless data.constants.isEmpty do
    sFail "System CPI IR rejects nonempty constants table"
  unless data.invariants.isEmpty do
    sFail "System CPI IR rejects nonempty invariants"
  let ir ← deriveSolanaCpiIRV1 plan
  let abi := ir.candidate.abiLayout
  unless abi == frozenLoaderV3AbiLayoutV1 do
    sFail "System CPI IR requires frozen Loader V3 ABIv1 layout"
  let mut handlers : Array CpiSystemHandlerIRV1 := #[]
  for h in plan.candidate.handlers do
    let handles := ir.candidate.roleHandles.filter (fun x => x.handlerId == h.handlerId)
    unless handles.size == h.accountUses.size do
      sFail "handler local handle count mismatch"
    let sites := ir.candidate.sites.filter (fun s => s.handlerId == h.handlerId)
    unless sites.map (·.siteId) == h.cpiSiteIds do
      sFail "handler site order must equal Plan cpiSiteIds"
    let projected ← projectSystemHandler abi data h handles sites
      plan.candidate.stateSchemas
    handlers := handlers.push projected
  pure {
    schema := systemIrSchemaV1
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

private def renderU64Source : CpiSystemU64SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt64LowerHex16 v}"

private def renderU8Source : CpiSystemU8SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt8LowerHex2 v}"

private def renderMeta (m : CpiSystemMetaV1) : String :=
  let sg := match m.signerGroupId with
    | none => "none"
    | some id => toString id
  s!"{m.metaIndex}:role{m.roleId}:local{m.localIndex}:w{m.cpiWritable}:s{m.cpiSigner}:sg{sg}"

private def renderPrincipal (b : CpiSystemPrincipalBindingV1) : String :=
  s!"arg{b.argIndex}:v{b.semanticValueId}:p{b.paramOrdinal}:role{b.roleId}:local{b.localIndex}"

private def renderOuter (o : CpiSystemOuterOnlyBindingV1) : String :=
  s!"oo{o.outerOnlyIndex}:role{o.roleId}:local{o.localIndex}:os{o.outerSigner}:ow{o.outerWritable}"

private def renderArgCheck : CpiSystemArgCheckV1 → String
  | .uint64AtMost name src maxV =>
      s!"uint64AtMost:{name}:{renderU64Source src}:max{maxV}"

private def renderKind : CpiSystemKindV1 → String
  | .transfer => "transfer"
  | .createPdaAccount => "createPdaAccount"

private def renderInvoke (i : CpiSystemInvokeV1) : String :=
  let metas := String.intercalate "," (i.metas.map renderMeta).toList
  let oos := String.intercalate "," (i.outerOnly.map renderOuter).toList
  let recip := match i.recipient with
    | none => "none"
    | some b => renderPrincipal b
  let pda := match i.pda with
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
  let space := match i.space with
    | none => "none"
    | some s => renderU64Source s
  let sg := match i.signerGroupId with
    | none => "none"
    | some id => toString id
  let rule := match i.pdaRule with
    | none => "none"
    | some r => r
  s!"invokeSystem:{i.siteId}:{renderKind i.kind}:{i.qn}:{i.packageId}:prog{i.programLocalIndex}:len{i.dataLen}:payer[{renderPrincipal i.payer}]:recipient[{recip}]:pda[{pda}]:seedAuth[{seedAuth}]:seedTag[{seedTag}]:bump[{bump}]:lamports[{renderU64Source i.lamports}]:space[{space}]:metas[{metas}]:outer[{oos}]:sg{sg}:{rule}:infos{i.accountInfoCount}"

private def renderBodyOp : CpiSystemBodyOpV1 → String
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
      let parts := String.intercalate ";" (ops.map preflightOpKindNameV1).toList
      s!"siteChecks:{sid}:[{parts}]"
  | .invokeSystem inv => renderInvoke inv
  | .returnU64 t => s!"returnU64:{t}"
  | .returnNone => "returnNone"

private def renderMode : HandlerModeV1 → String
  | .initialize => "initialize"
  | .entry => "entry"
  | .view => "view"

private def renderHandler (h : CpiSystemHandlerIRV1) : String :=
  let entry := String.intercalate ";" (h.entryGlobalOps.map preflightOpKindNameV1).toList
  let body := String.intercalate ";" (h.bodyOps.map renderBodyOp).toList
  s!"handler:{h.handlerId}:{h.callableId}:{h.name}:{renderMode h.mode}:roles{h.localRoleCount}:probe{h.probeIxDataLen}:temps{h.tempCount}:entry[{entry}]:body[{body}]"

private def renderCandidate (c : SolanaCpiSystemIRCandidateV1) : CompileResult String := do
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

/-- Sole mint of the #121 System execution IR from Semantic-bound Plan. -/
def resolveSolanaCpiSystemIRV1
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult ResolvedSolanaCpiSystemIRV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    sFail "System CPI IR requires activationDenied preflight carrier"
  let candidate ← projectSystemCandidate authority
  unless candidate.schema == systemIrSchemaV1 do
    sFail s!"schema must be {systemIrSchemaV1}"
  unless candidate.maxFrameBytes == 4096 do
    sFail "maxFrameBytes must be 4096"
  for h in candidate.handlers do
    unless h.localRoleCount ≤ maxOuterRolesV1 do
      sFail s!"handler {h.handlerId} localRoleCount exceeds cap"
    let ops := h.bodyOps
    for i in [0:ops.size] do
      match ops[i]! with
      | .siteArgChecks sid _ =>
          let j := i + 1
          unless j + 1 < ops.size do
            sFail s!"siteArgChecks {sid} not followed by siteChecks+invoke"
          match ops[j]!, ops[j + 1]! with
          | .siteChecks sid2 _, .invokeSystem inv =>
              unless sid2 == sid && inv.siteId == sid do
                sFail s!"siteArgChecks {sid} mismatched following site id"
          | _, _ =>
              sFail s!"siteArgChecks {sid} must be followed by siteChecks then invoke"
      | .siteChecks sid _ =>
          if i == 0 then
            sFail s!"siteChecks {sid} missing preceding siteArgChecks"
          else
            match ops[i - 1]! with
            | .siteArgChecks sid2 _ =>
                unless sid2 == sid do
                  sFail s!"siteChecks {sid} not preceded by matching siteArgChecks"
            | _ =>
                sFail s!"siteChecks {sid} missing immediately preceding siteArgChecks"
          let j := i + 1
          unless j < ops.size do
            sFail s!"siteChecks {sid} is not followed by invokeSystem"
          match ops[j]! with
          | .invokeSystem inv =>
              unless inv.siteId == sid do
                sFail s!"siteChecks {sid} mismatched invoke site {inv.siteId}"
          | _ =>
              sFail s!"siteChecks {sid} must be immediately followed by invokeSystem"
      | .invokeSystem inv =>
          unless inv.packageId == "system-v1" do
            sFail s!"invokeSystem site {inv.siteId} package must be system-v1"
          match inv.kind with
          | .transfer =>
              unless inv.qn == "solana.system.transfer" && inv.dataLen == 12 &&
                  inv.metas.size == 2 && inv.outerOnly.isEmpty &&
                  inv.signerGroupId.isNone && inv.pdaRule.isNone &&
                  inv.recipient.isSome && inv.pda.isNone &&
                  inv.seedAuthority.isNone && inv.space.isNone do
                sFail s!"transfer site {inv.siteId} frozen shape diverged"
              unless inv.metas[0]!.roleId == inv.payer.roleId &&
                  inv.metas[0]!.localIndex == inv.payer.localIndex &&
                  inv.metas[0]!.cpiWritable == true &&
                  inv.metas[0]!.cpiSigner == true do
                sFail s!"transfer site {inv.siteId} payer meta join diverged"
              let some recip := inv.recipient |
                sFail s!"transfer site {inv.siteId} recipient missing"
              unless inv.metas[1]!.roleId == recip.roleId &&
                  inv.metas[1]!.localIndex == recip.localIndex &&
                  inv.metas[1]!.cpiWritable == true &&
                  inv.metas[1]!.cpiSigner == false do
                sFail s!"transfer site {inv.siteId} recipient meta join diverged"
          | .createPdaAccount =>
              unless inv.qn == "solana.system.createPdaAccount" && inv.dataLen == 52 &&
                  inv.metas.size == 2 && inv.outerOnly.size == 1 &&
                  inv.signerGroupId == some 0 &&
                  inv.pdaRule == some "current-program-tagged-v1" &&
                  inv.recipient.isNone && inv.pda.isSome &&
                  inv.seedAuthority.isSome && inv.space.isSome &&
                  inv.seedTag.isSome && inv.bump.isSome do
                sFail s!"createPdaAccount site {inv.siteId} frozen shape diverged"
              let some pdaB := inv.pda |
                sFail s!"createPdaAccount site {inv.siteId} pda missing"
              let some seedAuth := inv.seedAuthority |
                sFail s!"createPdaAccount site {inv.siteId} seedAuthority missing"
              -- Retained meta flags (outer* on metas are project-time only; CPI flags rechecked here).
              -- Payer must be CPI writable+signer with no signer group; outer writable/signer
              -- were required at project join (outerWritableContribution=true exact).
              unless inv.metas[0]!.roleId == inv.payer.roleId &&
                  inv.metas[0]!.localIndex == inv.payer.localIndex &&
                  inv.metas[0]!.cpiWritable == true &&
                  inv.metas[0]!.cpiSigner == true &&
                  inv.metas[0]!.signerGroupId.isNone &&
                  inv.metas[1]!.roleId == pdaB.roleId &&
                  inv.metas[1]!.localIndex == pdaB.localIndex &&
                  inv.metas[1]!.cpiWritable == true &&
                  inv.metas[1]!.cpiSigner == true &&
                  inv.metas[1]!.signerGroupId == some 0 &&
                  inv.outerOnly[0]!.roleId == seedAuth.roleId &&
                  inv.outerOnly[0]!.localIndex == seedAuth.localIndex &&
                  inv.outerOnly[0]!.outerSigner == false &&
                  inv.outerOnly[0]!.outerWritable == false do
                sFail s!"createPdaAccount site {inv.siteId} meta/outer join diverged"
              match inv.bump with
              | some (.literal 0) =>
                  sFail s!"createPdaAccount site {inv.siteId} bump literal 0 rejected"
              | _ => pure ()
              match inv.space with
              | some (.literal v) =>
                  unless v.toNat ≤ maxPdaSpaceBytesV1 do
                    sFail s!"createPdaAccount site {inv.siteId} space literal exceeds 4096"
              | _ => pure ()
          if i < 2 then
            sFail s!"invokeSystem site {inv.siteId} missing preceding siteArgChecks/siteChecks"
          else
            match ops[i - 2]!, ops[i - 1]! with
            | .siteArgChecks sidA _, .siteChecks sidC _ =>
                unless sidA == inv.siteId && sidC == inv.siteId do
                  sFail s!"invokeSystem site {inv.siteId} preceding site id mismatch"
            | _, _ =>
                sFail s!"invokeSystem site {inv.siteId} must be preceded by siteArgChecks→siteChecks"
      | _ => pure ()
  let text ← renderCandidate candidate
  let canonicalBytes := text.toUTF8
  let digest ← mapExcept
    (domainSeparatedSha256 systemIrDigestDomainV1 canonicalBytes)
    "system-ir digest"
  pure ⟨authority, candidate, canonicalBytes, digest⟩

/-- Transfer scratch: 16 data + 32 metas + 40 instr + 56*N infos. -/
def systemCpiScratchTransferV1 (localRoleCount : Nat) : Nat :=
  88 + localRoleCount * 56

/-- CreatePda scratch: 64 data + seeds + metas + instr + infos + find outs.
    Layout: 296 + 56*N (see EmitCpiSystemSbpfV1). -/
def systemCpiScratchCreateV1 (localRoleCount : Nat) : Nat :=
  296 + localRoleCount * 56

/-- Max site scratch across handlers. -/
def systemMaxSiteScratchV1 (c : SolanaCpiSystemIRCandidateV1) : Nat :=
  Id.run do
    let mut maxB : Nat := 0
    for h in c.handlers do
      for op in h.bodyOps do
        match op with
        | .invokeSystem inv =>
            let b := match inv.kind with
              | .transfer => systemCpiScratchTransferV1 inv.accountInfoCount
              | .createPdaAccount => systemCpiScratchCreateV1 inv.accountInfoCount
            if b > maxB then maxB := b
        | _ => pure ()
    pure maxB

end ProofForgeV2.Targets.Solana.CpiV1

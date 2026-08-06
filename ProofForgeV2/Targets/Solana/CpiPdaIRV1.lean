/-
  ProofForgeV2.Targets.Solana.CpiPdaIRV1 — #120 PDA-signed companion CPI IR.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole mint: `resolveSolanaCpiPdaIRV1`. Consumes only private Semantic-bound
  `SolanaCpiPreflightPlanV1` (NOT `ResolvedSolanaCpiPreflightIRV1`, which
  rejects PDA). Freshly derives/joins validated CpiIR and mints private
  `ResolvedSolanaCpiPdaIRV1`.

  * admits only `solana.companion.invokeSigned`;
  * single-block straight-line initializer/entry/view;
  * narrow public UInt64 body subset equivalent to #119, plus UInt8 bump;
  * exact args: account/authorityPda/seedAuthority Principal, seedTag UInt64,
    bump UInt8, delta UInt64;
  * exact metas: account writable non-signer; authorityPda readonly CPI signer
    group 0 outer non-signer; seedAuthority outer-only business signer;
  * frozen PDA rule / signer group `current-program-tagged-v1`;
  * rejects bump literal 0; runtime rejects param 0;
  * rejects System/Token/ATA/schedule/dynamic/multiblock/typed returns.

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

def pdaIrSchemaV1 : String := "proof-forge.solana.cpi-pda-ir.v1"
def pdaIrDigestDomainV1 : String := "pf.solana.cpi-pda-ir.v1"

/-- UInt64 value sources for seedTag / delta. -/
inductive CpiPdaU64SourceV1 where
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  | literal (value : UInt64)
  deriving BEq, Repr, Inhabited

/-- UInt8 value sources for bump (literal 0 rejected at IR mint). -/
inductive CpiPdaU8SourceV1 where
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  | literal (value : UInt8)
  deriving BEq, Repr, Inhabited

/-- One CPI meta binding to a handler-local role. -/
structure CpiPdaMetaV1 where
  metaIndex : Nat
  roleId : Nat
  localIndex : Nat
  cpiWritable : Bool
  cpiSigner : Bool
  signerGroupId : Option Nat
  deriving BEq, Repr, Inhabited

/-- Exact Semantic Principal → callable parameter → role → dense local join. -/
structure CpiPdaPrincipalBindingV1 where
  argIndex : Nat
  semanticValueId : Nat
  paramOrdinal : Nat
  roleId : Nat
  localIndex : Nat
  deriving BEq, Repr, Inhabited

/-- Outer-only account binding (seedAuthority business signer). -/
structure CpiPdaOuterOnlyBindingV1 where
  outerOnlyIndex : Nat
  roleId : Nat
  localIndex : Nat
  outerSigner : Bool
  outerWritable : Bool
  deriving BEq, Repr, Inhabited

/-- Site-local PDA-signed invoke (companion.invokeSigned only). -/
structure CpiPdaInvokeV1 where
  siteId : Nat
  qn : String
  packageId : String
  programLocalIndex : Nat
  /-- Companion tag byte: always 2 for invokeSigned. -/
  tag : Nat
  dataLen : Nat
  account : CpiPdaPrincipalBindingV1
  authorityPda : CpiPdaPrincipalBindingV1
  seedAuthority : CpiPdaPrincipalBindingV1
  seedTag : CpiPdaU64SourceV1
  bump : CpiPdaU8SourceV1
  delta : CpiPdaU64SourceV1
  metas : Array CpiPdaMetaV1
  outerOnly : Array CpiPdaOuterOnlyBindingV1
  signerGroupId : Nat
  pdaRule : String
  accountInfoCount : Nat
  deriving BEq, Repr

/-- Ordered body operations after handler-entry global preflight. -/
inductive CpiPdaBodyOpV1 where
  | loadParamU64 (tempId : Nat) (ixDataOffset : Nat)
  | loadParamU8 (tempId : Nat) (ixDataOffset : Nat)
  | loadLiteralU64 (tempId : Nat) (value : UInt64)
  | loadLiteralU8 (tempId : Nat) (value : UInt8)
  | stateLoadU64 (tempId : Nat) (stateLocalIndex : Nat) (byteOffset : Nat)
  | checkedAddU64 (dstTemp lhsTemp rhsTemp : Nat)
  | stateStoreU64 (stateLocalIndex : Nat) (byteOffset : Nat) (srcTemp : Nat)
    (writeInitializedMarker : Bool) (initializedMarker : UInt64)
  | siteChecks (siteId : Nat) (ops : Array CpiPreflightOpV1)
  | invokeSigned (invoke : CpiPdaInvokeV1)
  | returnU64 (srcTemp : Nat)
  | returnNone
  deriving BEq, Repr, Inhabited

structure CpiPdaHandlerIRV1 where
  handlerId : Nat
  callableId : Nat
  name : String
  mode : HandlerModeV1
  localRoleCount : Nat
  localRoleOrder : Array CpiIRRoleHandleV1
  accountParameterBindings : Array CpiPreflightAccountParamBindingV1
  probeIxDataLen : Nat
  entryGlobalOps : Array CpiPreflightOpV1
  bodyOps : Array CpiPdaBodyOpV1
  tempCount : Nat
  deriving BEq, Repr

structure SolanaCpiPdaIRCandidateV1 where
  schema : String
  sourcePlanDigest : Digest
  sourceIrDigest : Digest
  profileId : String
  profileDigest : Digest
  catalogDigest : Digest
  abiLayout : LoaderV3AbiLayoutV1
  maxOuterRoles : Nat
  maxFrameBytes : Nat
  handlers : Array CpiPdaHandlerIRV1
  deriving BEq

/-- Private resolved PDA IR. Sole mint from Semantic-bound preflight Plan. -/
structure ResolvedSolanaCpiPdaIRV1 where
  private mk ::
  authority : SolanaCpiPreflightPlanV1
  candidate : SolanaCpiPdaIRCandidateV1
  canonicalBytes : ByteArray
  digest : Digest

namespace ResolvedSolanaCpiPdaIRV1

def authorityOf (r : ResolvedSolanaCpiPdaIRV1) : SolanaCpiPreflightPlanV1 :=
  r.authority
def candidateOf (r : ResolvedSolanaCpiPdaIRV1) : SolanaCpiPdaIRCandidateV1 :=
  r.candidate
def digestOf (r : ResolvedSolanaCpiPdaIRV1) : Digest :=
  r.digest
def canonicalBytesOf (r : ResolvedSolanaCpiPdaIRV1) : ByteArray :=
  r.canonicalBytes

end ResolvedSolanaCpiPdaIRV1

/-! ## Internals -/

private def pFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def mapExcept (e : Except String α) (ctx : String) : CompileResult α :=
  match e with
  | .ok v => pure v
  | .error msg => pFail s!"{ctx}: {msg}"

private def digestsEqual (left right : Digest) : Bool :=
  left.algorithm == right.algorithm && left.bytes == right.bytes

private def getArr (arr : Array α) (i : Nat) (ctx : String) : CompileResult α :=
  match arr[i]? with
  | some v => pure v
  | none => pFail s!"{ctx}: index {i} out of range"

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
    pFail s!"UInt64 valueBytes must be exact 8 bytes, got {bytes.size}"
  let mut n : Nat := 0
  for i in [0:8] do
    n := n + bytes[i]!.toNat * (Nat.pow 2 (8 * i))
  pure (UInt64.ofNat n)

private def decodeUInt8 (bytes : ByteArray) : CompileResult UInt8 := do
  unless bytes.size == 1 do
    pFail s!"UInt8 valueBytes must be exact 1 byte, got {bytes.size}"
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
  | .state _ | .accountParameter .. | .vaultPda | .handlerCaller | .vaultAta .. | .dstAta .. => none

/-- PDA-aware owner resolution (same as #119 for admitted owners). -/
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
          pFail s!"owner fixedProgram package '{packageId}' missing from catalog"
  | .catalogExecutionClass =>
      let packageId ← match catalogPackageId? with
        | some id => pure id
        | none =>
            pFail "catalogExecutionClass owner requires a fixed-program package context"
      match findCalleePackage? packageId with
      | some package =>
          pure #[.checkOwnerExact localIndex
            (executionClassOwnerPubkeyV1 package.executionClass)]
      | none =>
          pFail s!"catalogExecutionClass package '{packageId}' missing from catalog"
  | .any => pure #[]
  | .closedPackages _ =>
      pFail "PDA CPI IR rejects closedPackages owner (Token/ATA deferred)"

private def resolveExecutableOps
    (localIndex : Nat) (exec : ExecutablePolicy) : Array CpiPreflightOpV1 :=
  match exec with
  | .required => #[.checkExecutableRequired localIndex]
  | .forbidden => #[.checkExecutableForbidden localIndex]

/-- Admit `.canonicalPda` init (PDA verified at invoke time); reject Token/ATA. -/
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
      pFail "PDA CPI IR rejects uninitialized initialization"
  | .canonicalPda =>
      -- PDA address checked at site via sol_try_find_program_address.
      pure ()
  | .uninitializedOrIdempotentlyInitialized =>
      pFail "PDA CPI IR rejects ATA initialization"
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
        | _ => pFail "proofForgeState data requires RoleKeyPolicyV1.state"
      let schema ← match findStateSchema? stateSchemas schemaId with
        | some s => pure s
        | none => pFail s!"proofForgeState schemaId {schemaId} missing"
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
      | .existing | .any | .catalogPackageAdmitted | .canonicalPda => pure ()
      | _ => pure ()
  | .classicTokenAccount .. =>
      pFail "PDA CPI IR rejects classicTokenAccount data"
  | .classicTokenMint .. =>
      pFail "PDA CPI IR rejects classicTokenMint data"
  | .ataAccount .. =>
      pFail "PDA CPI IR rejects ataAccount data"
  pure ops

private def resolveProvisioning (prov : ProvisioningPolicy) : CompileResult Unit := do
  match prov with
  | .none | .mustExist => pure ()
  | .systemCreateAccount =>
      pFail "PDA CPI IR rejects systemCreateAccount provisioning"
  | .ataCreateIdempotent =>
      pFail "PDA CPI IR rejects ataCreateIdempotent provisioning"

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
    pFail s!"handler local role count {n} exceeds maxOuterRoles {maxOuterRolesV1}"
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
            pFail s!"fixedProgram package '{packageId}' missing from frozen catalog"
    | .accountParameter callableId paramOrdinal =>
        bindings := bindings.push {
          callableId
          paramOrdinal
          roleId := handle.roleId
          localIndex := i
        }
    | .state _ | .vaultPda | .handlerCaller | .vaultAta .. | .dstAta .. => pure ()
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
          pFail s!"site predicate roleId {pred.roleId} missing from handler locals"
    unless handle.localIndex < handles.size do
      pFail s!"site predicate roleId {pred.roleId} has out-of-range localIndex"
    let denseHandle ← getArr handles handle.localIndex "site predicate dense local handles"
    unless denseHandle.roleId == handle.roleId &&
        denseHandle.localIndex == handle.localIndex do
      pFail s!"site predicate roleId {pred.roleId} has non-dense local handle"
    let packageOverride : Option String :=
      match pred.source with
      | .callee => some site.packageId
      | .metaIndex _ | .outerOnlyIndex _ => none
    let predOps ← projectConstraintOps handle.localIndex mode handle.keyPolicy
      pred.constraint stateSchemas packageOverride
    ops := ops ++ predOps
  pure ops

/-- Non-Principal public params → packed probe offsets in declaration order:
    UInt64 uses 8 bytes and UInt8 uses exactly 1 byte. -/
private def buildParamIxLayout
    (types : Array TypeDeclV1) (callable : CallableV1) :
    CompileResult (Array (Nat × Nat × Nat) × Nat) := do
  -- layout entries: (paramOrdinal, ixOffset, widthBits)
  let mut layout : Array (Nat × Nat × Nat) := #[]
  let mut offset : Nat := 8
  for (p, ord) in callable.params.zipIdx do
    unless p.visibility == VisibilityV1.public_ do
      pFail "PDA CPI IR requires public parameters only"
    if isAnonPrincipal types p.typeId then
      pure ()
    else if anonUintWidth? types p.typeId == some 64 then
      layout := layout.push (ord, offset, 64)
      offset := offset + 8
    else if anonUintWidth? types p.typeId == some 8 then
      layout := layout.push (ord, offset, 8)
      offset := offset + 1
    else
      pFail
        s!"PDA CPI IR admits only public Principal/UInt64/UInt8 params, got '{p.name}'"
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
    pFail
      s!"PDA CPI IR requires single-block straight-line callables (got {callable.blocks.size} blocks)"
  unless callable.entryBlock.toNat == 0 do
    pFail "PDA CPI IR requires entryBlock == 0"
  unless callable.loopBounds.isEmpty do
    pFail "PDA CPI IR rejects loopBounds (no back edges)"
  let blk ← getArr callable.blocks 0 "callable.blocks"
  unless blk.id.toNat == 0 do
    pFail "PDA CPI IR requires sole block id == 0"
  unless blk.params.isEmpty do
    pFail "PDA CPI IR rejects block parameters"
  pure blk

private def localIndexOfRole
    (handles : Array CpiIRRoleHandleV1) (roleId : Nat) : CompileResult Nat :=
  match handles.find? (fun h => h.roleId == roleId) with
  | some h => pure h.localIndex
  | none => pFail s!"roleId {roleId} missing from handler local roles"

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
    CompileResult CpiPdaPrincipalBindingV1 := do
  let paramOrdinal ← match directPublicPrincipalParamOrdinal? types callable vid with
    | some ord => pure ord
    | none =>
        pFail s!"site {site.siteId} arg {argIndex}: expected bare direct public Principal parameter"
  let arg ← getArr site.args argIndex s!"site {site.siteId}.args"
  unless arg.spec.type_ == FrozenValueType.principal &&
      arg.spec.source == ArgumentSource.bareDirectPublicPrincipalParameter do
    pFail s!"site {site.siteId} arg {argIndex}: frozen Principal source diverged"
  unless arg.semanticValueId == vid.toNat do
    pFail s!"site {site.siteId} arg {argIndex}: Semantic ValueId diverged from Plan binding"
  let roleId ← match arg.roleId with
    | some rid => pure rid
    | none => pFail s!"site {site.siteId} arg {argIndex}: Principal roleId missing"
  let handle ← match handles.find? (fun h => h.roleId == roleId) with
    | some h => pure h
    | none => pFail s!"site {site.siteId} arg {argIndex}: roleId {roleId} missing from handler"
  unless handle.localIndex < handles.size do
    pFail s!"site {site.siteId} arg {argIndex}: localIndex out of range"
  let denseHandle ← getArr handles handle.localIndex "handler dense local handles"
  unless denseHandle.roleId == roleId && denseHandle.localIndex == handle.localIndex do
    pFail s!"site {site.siteId} arg {argIndex}: local handle is not dense/exact"
  match handle.keyPolicy with
  | .accountParameter callableId boundOrdinal =>
      unless callableId == callable.id.toNat && boundOrdinal == paramOrdinal do
        pFail s!"site {site.siteId} arg {argIndex}: account role does not bind the exact callable parameter"
  | _ =>
      pFail s!"site {site.siteId} arg {argIndex}: Principal role is not accountParameter-bound"
  let paramBindings := bindings.filter (fun b =>
    b.callableId == callable.id.toNat && b.paramOrdinal == paramOrdinal)
  unless paramBindings.size == 1 do
    pFail s!"site {site.siteId} arg {argIndex}: expected exactly one preflight binding for the parameter"
  let exactBinding ← getArr paramBindings 0 "Principal preflight parameter binding"
  unless exactBinding.roleId == roleId &&
      exactBinding.localIndex == handle.localIndex do
    pFail s!"site {site.siteId} arg {argIndex}: preflight binding role/local index diverged"
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
    CompileResult CpiPdaU64SourceV1 := do
  match findLiteralU64? types callable vid with
  | some v => pure (.literal v)
  | none =>
      match directPublicU64ParamOrdinal? types callable vid with
      | some ord =>
          match ixOffsetOfParam? layout ord with
          | some (off, w) =>
              unless w == 64 do
                pFail s!"{ctx}: UInt64 param ordinal {ord} has wrong width slot"
              pure (.param ord off)
          | none =>
              pFail s!"{ctx}: UInt64 param ordinal {ord} missing from probe layout"
      | none =>
          pFail
            s!"{ctx}: admits only direct public UInt64 param or UInt64 literal"

private def resolveU8Source
    (types : Array TypeDeclV1) (callable : CallableV1)
    (layout : Array (Nat × Nat × Nat)) (vid : ValueIdV1) (ctx : String)
    (rejectZeroLiteral : Bool) :
    CompileResult CpiPdaU8SourceV1 := do
  match findLiteralU8? types callable vid with
  | some v =>
      if rejectZeroLiteral && v == 0 then
        pFail s!"{ctx}: bump literal 0 is rejected (canonical search is 255..1)"
      pure (.literal v)
  | none =>
      match directPublicU8ParamOrdinal? types callable vid with
      | some ord =>
          match ixOffsetOfParam? layout ord with
          | some (off, w) =>
              unless w == 8 do
                pFail s!"{ctx}: UInt8 param ordinal {ord} has wrong width slot"
              pure (.param ord off)
          | none =>
              pFail s!"{ctx}: UInt8 param ordinal {ord} missing from probe layout"
      | none =>
          pFail
            s!"{ctx}: admits only direct public UInt8 param or UInt8 literal"

private def projectPdaHandler
    (abi : LoaderV3AbiLayoutV1)
    (data : SemanticProgramDataV1)
    (planHandler : HandlerPlanV1)
    (handles : Array CpiIRRoleHandleV1)
    (sites : Array CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult CpiPdaHandlerIRV1 := do
  let callable ← getArr data.callables planHandler.callableId "callables"
  unless callable.id.toNat == planHandler.callableId do
    pFail "handler callableId must equal Semantic callable.id"
  unless callable.blocks.size ≥ 1 do
    pFail "callable has no blocks"
  unless handles.size == planHandler.accountUses.size do
    pFail "handler local handle count must equal Plan accountUses size"
  for i in [0:handles.size] do
    let handle ← getArr handles i "handler local handles"
    let use ← getArr planHandler.accountUses i "handler accountUses"
    unless handle.handlerId == planHandler.handlerId &&
        handle.localIndex == i && use.position == i &&
        handle.roleId == use.roleId do
      pFail s!"handler {planHandler.handlerId} local handle order diverged at {i}"
  for site in sites do
    unless site.handlerId == planHandler.handlerId do
      pFail "site handlerId mismatch"
    unless site.qn == "solana.companion.invokeSigned" do
      pFail
        s!"PDA CPI first slice admits only solana.companion.invokeSigned, got '{site.qn}'"
    unless site.packageId == "companion-v1" do
      pFail
        s!"PDA CPI admits only companion-v1, got '{site.packageId}' at site {site.siteId}"
    match site.pda with
    | .signer rule targetArg seedAuthArg seedTagArg bumpArg signerArg =>
        unless rule == "current-program-tagged-v1" do
          pFail s!"site {site.siteId}: PDA rule must be current-program-tagged-v1"
        unless targetArg == "authorityPda" && seedAuthArg == "seedAuthority" &&
            seedTagArg == "seedTag" && bumpArg == "bump" &&
            signerArg == "authorityPda" do
          pFail s!"site {site.siteId}: PDA arg names must match frozen invokeSigned"
    | .none =>
        pFail s!"PDA CPI requires PDA signer use at site {site.siteId}"
    | .addressCheckOnly .. | .vaultPdaSigner _ =>
        pFail s!"PDA CPI rejects non-signer PDA use at site {site.siteId}"
    unless site.signerGroups.size == 1 do
      pFail s!"site {site.siteId}: exact one signer group required"
    let group ← getArr site.signerGroups 0 s!"site {site.siteId}.signerGroups"
    unless group.id == 0 && group.metaArg == "authorityPda" &&
        group.pdaRule == "current-program-tagged-v1" do
      pFail s!"site {site.siteId}: signer group must be id0/authorityPda/current-program-tagged-v1"
    unless site.preflight.isEmpty do
      pFail s!"PDA CPI rejects site preflight arg predicates at site {site.siteId}"
    unless site.metas.size == 2 do
      pFail s!"site {site.siteId}: invokeSigned requires exactly two metas"
    unless site.outerOnlyAccounts.size == 1 do
      pFail s!"site {site.siteId}: invokeSigned requires exactly one outer-only"
    unless site.args.size == 6 do
      pFail s!"site {site.siteId}: invokeSigned requires exactly six args"

  let blk ← requireStraightLineCallable callable
  let (paramLayout, probeIxDataLen) ← buildParamIxLayout data.types callable
  let (bindings, entryGlobalOps) ←
    projectEntryGlobalOps abi planHandler.mode handles stateSchemas

  let mut tempOf : Array (Nat × Nat) := #[]
  let mut nextTemp : Nat := 0
  let mut body : Array CpiPdaBodyOpV1 := #[]

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
          pFail "literal must produce a result"
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
            pFail "PDA CPI IR admits only UInt64/UInt8 literals in body"
    | .stateLoad stateId =>
        let some vd := instr.result |
          pFail "stateLoad must produce a result"
        let (stateLocal, schema) ← match stateInfo? with
          | some s => pure s
          | none => pFail "stateLoad without state role"
        unless stateId.toNat == 0 do
          pFail "PDA CPI IR first slice admits only stateId 0"
        unless schema.exactDataLen == 16 do
          pFail "stateLoad requires single UInt64 state layout"
        let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
        tempOf := tempOf'
        nextTemp := next'
        body := body.push (.stateLoadU64 t stateLocal 8)
    | .stateStore stateId value =>
        let (stateLocal, schema) ← match stateInfo? with
          | some s => pure s
          | none => pFail "stateStore without state role"
        unless stateId.toNat == 0 do
          pFail "PDA CPI IR first slice admits only stateId 0"
        let src ← match lookupTemp tempOf value.toNat with
          | some t => pure t
          | none =>
              match directPublicU64ParamOrdinal? data.types callable value with
              | some ord =>
                  match ixOffsetOfParam? paramLayout ord with
                  | some (off, w) =>
                      unless w == 64 do
                        pFail "stateStore value width diverged"
                      let (t, tempOf', next') := allocTemp tempOf nextTemp value.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadParamU64 t off)
                      pure t
                  | none => pFail "stateStore value param missing from probe layout"
              | none =>
                  match findLiteralU64? data.types callable value with
                  | some lit =>
                      let (t, tempOf', next') := allocTemp tempOf nextTemp value.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadLiteralU64 t lit)
                      pure t
                  | none =>
                      pFail s!"stateStore value ValueId {value} is not materialised"
        let writeMarker := planHandler.mode == .initialize
        body := body.push
          (.stateStoreU64 stateLocal 8 src writeMarker schema.initializedMarker)
    | .binary opKind lhs rhs =>
        let some vd := instr.result |
          pFail "binary must produce a result"
        match opKind with
        | BinaryOpV1.add =>
            let l ← match lookupTemp tempOf lhs.toNat with
              | some t => pure t
              | none => pFail s!"checkedAdd lhs ValueId {lhs} not materialised"
            let r ← match lookupTemp tempOf rhs.toNat with
              | some t => pure t
              | none => pFail s!"checkedAdd rhs ValueId {rhs} not materialised"
            let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
            tempOf := tempOf'
            nextTemp := next'
            body := body.push (.checkedAddU64 t l r)
        | _ =>
            pFail "PDA CPI IR first slice admits only checked UInt64 add in body"
    | .externalCall effectId callee args =>
        let qnComps ← mapExcept (renderQualifiedNameComponents callee) "callee QN"
        let qn := String.intercalate "." qnComps.toList
        unless qn == "solana.companion.invokeSigned" do
          pFail
            s!"PDA CPI admits only solana.companion.invokeSigned, got '{qn}'"
        let site ← match sites.find? (fun s =>
            s.anchor.callableId == planHandler.callableId &&
              s.anchor.blockId == blk.id.toNat &&
              s.anchor.instructionIndex == instrIdx &&
              s.anchor.effectId == effectId.toNat) with
          | some s => pure s
          | none =>
              pFail
                s!"ExternalCall at instr {instrIdx} has no matching CPI site anchor"
        unless site.qn == qn do
          pFail "site QN diverges from Semantic ExternalCall"
        unless site.packageId == "companion-v1" do
          pFail "ExternalCall package must be companion-v1"
        unless args.size == 6 && site.args.size == 6 do
          pFail "invokeSigned requires exactly 6 Semantic and Plan args"
        let accountVid ← getArr args 0 "externalCall.args"
        let accountBinding ← resolvePrincipalAccountBinding data.types callable
          handles bindings site 0 accountVid
        let authVid ← getArr args 1 "externalCall.args"
        let authBinding ← resolvePrincipalAccountBinding data.types callable
          handles bindings site 1 authVid
        let seedAuthVid ← getArr args 2 "externalCall.args"
        let seedAuthBinding ← resolvePrincipalAccountBinding data.types callable
          handles bindings site 2 seedAuthVid
        let seedTagVid ← getArr args 3 "externalCall.args"
        let seedTagArg ← getArr site.args 3 s!"site {site.siteId}.args"
        unless seedTagArg.semanticValueId == seedTagVid.toNat &&
            seedTagArg.roleId.isNone &&
            seedTagArg.spec.type_ == FrozenValueType.uint64 do
          pFail s!"site {site.siteId} seedTag binding diverged"
        let seedTagSrc ← resolveU64Source data.types callable paramLayout seedTagVid
          s!"site {site.siteId} seedTag"
        let bumpVid ← getArr args 4 "externalCall.args"
        let bumpArg ← getArr site.args 4 s!"site {site.siteId}.args"
        unless bumpArg.semanticValueId == bumpVid.toNat &&
            bumpArg.roleId.isNone &&
            bumpArg.spec.type_ == FrozenValueType.uint8 do
          pFail s!"site {site.siteId} bump binding diverged"
        let bumpSrc ← resolveU8Source data.types callable paramLayout bumpVid
          s!"site {site.siteId} bump" true
        let deltaVid ← getArr args 5 "externalCall.args"
        let deltaArg ← getArr site.args 5 s!"site {site.siteId}.args"
        unless deltaArg.semanticValueId == deltaVid.toNat && deltaArg.roleId.isNone &&
            deltaArg.spec.type_ == FrozenValueType.uint64 do
          pFail s!"site {site.siteId} delta binding diverged"
        let deltaSrc ← resolveU64Source data.types callable paramLayout deltaVid
          s!"site {site.siteId} delta"
        let programLocal ← localIndexOfRole handles site.programRoleId
        unless site.programHandleIndex == programLocal do
          pFail s!"site {site.siteId} program handle index diverged"
        -- Meta[0] = account (writable non-signer)
        let meta0 ← getArr site.metas 0 s!"site {site.siteId}.metas"
        unless meta0.metaIndex == 0 &&
            meta0.roleId == accountBinding.roleId &&
            meta0.localHandleIndex == accountBinding.localIndex &&
            meta0.spec.cpiWritable == true &&
            meta0.spec.cpiSigner == false &&
            meta0.spec.signerGroupId.isNone do
          pFail s!"site {site.siteId} account meta must be writable non-signer joined to account"
        -- Meta[1] = authorityPda (readonly CPI signer group 0, outer non-signer)
        let meta1 ← getArr site.metas 1 s!"site {site.siteId}.metas"
        unless meta1.metaIndex == 1 &&
            meta1.roleId == authBinding.roleId &&
            meta1.localHandleIndex == authBinding.localIndex &&
            meta1.spec.cpiWritable == false &&
            meta1.spec.cpiSigner == true &&
            meta1.spec.outerSignerContribution == false &&
            meta1.spec.signerGroupId == some 0 do
          pFail s!"site {site.siteId} authorityPda meta must be readonly CPI signer group 0 outer non-signer"
        let mut metas : Array CpiPdaMetaV1 := #[]
        for m in site.metas do
          let li ← localIndexOfRole handles m.roleId
          unless m.localHandleIndex == li do
            pFail s!"site {site.siteId} meta {m.metaIndex} local handle diverged"
          metas := metas.push {
            metaIndex := m.metaIndex
            roleId := m.roleId
            localIndex := li
            cpiWritable := m.spec.cpiWritable
            cpiSigner := m.spec.cpiSigner
            signerGroupId := m.spec.signerGroupId
          }
        -- Outer-only seedAuthority
        let oo0 ← getArr site.outerOnlyAccounts 0 s!"site {site.siteId}.outerOnly"
        unless oo0.roleId == seedAuthBinding.roleId &&
            oo0.localHandleIndex == seedAuthBinding.localIndex &&
            oo0.spec.outerSignerContribution == true &&
            oo0.spec.outerWritableContribution == false do
          pFail s!"site {site.siteId} seedAuthority outer-only must be business signer non-writable"
        let outerOnly : Array CpiPdaOuterOnlyBindingV1 := #[{
          outerOnlyIndex := 0
          roleId := oo0.roleId
          localIndex := oo0.localHandleIndex
          outerSigner := oo0.spec.outerSignerContribution
          outerWritable := oo0.spec.outerWritableContribution
        }]
        let siteOps ← projectSiteChecks planHandler.mode handles site stateSchemas
        body := body.push (.siteChecks site.siteId siteOps)
        body := body.push (.invokeSigned {
          siteId := site.siteId
          qn
          packageId := site.packageId
          programLocalIndex := programLocal
          tag := 2
          dataLen := site.instructionCodec.length
          account := accountBinding
          authorityPda := authBinding
          seedAuthority := seedAuthBinding
          seedTag := seedTagSrc
          bump := bumpSrc
          delta := deltaSrc
          metas
          outerOnly
          signerGroupId := 0
          pdaRule := "current-program-tagged-v1"
          accountInfoCount := handles.size
        })
    | .constant _cid =>
        pFail "PDA CPI IR rejects Op.Constant (constants table support deferred)"
    | .unary .. =>
        pFail "PDA CPI IR rejects unary ops in first slice"
    | .pureCall .. =>
        pFail "PDA CPI IR rejects pureCall in first slice"
    | .construct .. | .fieldGet .. | .fieldSet .. | .indexGet .. | .indexSet ..
    | .variantTag .. | .variantPayload .. | .checkedCast ..
    | .contextRead .. | .envRead .. | .commit .. | .assert_ .. | .emit .. | .schedule .. =>
        pFail "PDA CPI IR rejects unsupported body op in first slice"

  match blk.terminator with
  | .return_ none =>
      body := body.push .returnNone
  | .return_ (some vid) =>
      if isAnonUnit data.types (← match typeOfValueId? callable vid with
          | some t => pure t
          | none => pFail "return value has no type") then
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
                        pFail "return param width diverged"
                      let (t, tempOf', next') := allocTemp tempOf nextTemp vid.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadParamU64 t off)
                      pure t
                  | none => pFail "return param missing from probe layout"
              | none =>
                  match findLiteralU64? data.types callable vid with
                  | some lit =>
                      let (t, tempOf', next') := allocTemp tempOf nextTemp vid.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadLiteralU64 t lit)
                      pure t
                  | none =>
                      pFail s!"return ValueId {vid} is not materialised"
        body := body.push (.returnU64 src)
  | .jump .. | .branch .. | .switch .. | .revert .. | .trap _ =>
      pFail "PDA CPI IR requires return terminator only (straight-line)"

  let bodySiteIds :=
    body.foldl (init := ([] : List Nat)) fun acc op =>
      match op with
      | .invokeSigned inv => acc ++ [inv.siteId]
      | _ => acc
  let planSiteIds := sites.map (·.siteId) |>.toList
  unless bodySiteIds == planSiteIds do
    pFail
      "PDA body invoke site order must equal Plan cpiSiteIds (source order)"

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

private def projectPdaCandidate
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult SolanaCpiPdaIRCandidateV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    pFail "PDA CPI IR requires activationDenied authority"
  let plan := SolanaCpiPreflightPlanV1.planOf authority
  let compiled :=
    ResolvedSolanaCpiPreflightV1.compiledOf
      (SolanaCpiPreflightPlanV1.preflightOf authority)
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok v => pure v
    | .error _ =>
        pFail "PDA CPI IR: retained Semantic failed structure validation"
  unless data.constants.isEmpty do
    pFail "PDA CPI IR rejects nonempty constants table"
  unless data.invariants.isEmpty do
    pFail "PDA CPI IR rejects nonempty invariants"
  -- Fresh derive/join of validated CpiIR (not via ResolvedSolanaCpiPreflightIRV1).
  let ir ← deriveSolanaCpiIRV1 plan
  let abi := ir.candidate.abiLayout
  unless abi == frozenLoaderV3AbiLayoutV1 do
    pFail "PDA CPI IR requires frozen Loader V3 ABIv1 layout"
  let mut handlers : Array CpiPdaHandlerIRV1 := #[]
  for h in plan.candidate.handlers do
    let handles := ir.candidate.roleHandles.filter (fun x => x.handlerId == h.handlerId)
    unless handles.size == h.accountUses.size do
      pFail "handler local handle count mismatch"
    let sites := ir.candidate.sites.filter (fun s => s.handlerId == h.handlerId)
    unless sites.map (·.siteId) == h.cpiSiteIds do
      pFail "handler site order must equal Plan cpiSiteIds"
    let projected ← projectPdaHandler abi data h handles sites
      plan.candidate.stateSchemas
    handlers := handlers.push projected
  pure {
    schema := pdaIrSchemaV1
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

private def renderU64Source : CpiPdaU64SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt64LowerHex16 v}"

private def renderU8Source : CpiPdaU8SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt8LowerHex2 v}"

private def renderMeta (m : CpiPdaMetaV1) : String :=
  let sg := match m.signerGroupId with
    | none => "none"
    | some id => toString id
  s!"{m.metaIndex}:role{m.roleId}:local{m.localIndex}:w{m.cpiWritable}:s{m.cpiSigner}:sg{sg}"

private def renderPrincipal (b : CpiPdaPrincipalBindingV1) : String :=
  s!"arg{b.argIndex}:v{b.semanticValueId}:p{b.paramOrdinal}:role{b.roleId}:local{b.localIndex}"

private def renderOuter (o : CpiPdaOuterOnlyBindingV1) : String :=
  s!"oo{o.outerOnlyIndex}:role{o.roleId}:local{o.localIndex}:os{o.outerSigner}:ow{o.outerWritable}"

private def renderInvoke (i : CpiPdaInvokeV1) : String :=
  let metas := String.intercalate "," (i.metas.map renderMeta).toList
  let oos := String.intercalate "," (i.outerOnly.map renderOuter).toList
  s!"invokeSigned:{i.siteId}:{i.qn}:{i.packageId}:prog{i.programLocalIndex}:tag{i.tag}:len{i.dataLen}:account[{renderPrincipal i.account}]:auth[{renderPrincipal i.authorityPda}]:seedAuth[{renderPrincipal i.seedAuthority}]:seedTag[{renderU64Source i.seedTag}]:bump[{renderU8Source i.bump}]:delta[{renderU64Source i.delta}]:metas[{metas}]:outer[{oos}]:sg{i.signerGroupId}:{i.pdaRule}:infos{i.accountInfoCount}"

private def renderBodyOp : CpiPdaBodyOpV1 → String
  | .loadParamU64 t off => s!"loadParamU64:{t}@{off}"
  | .loadParamU8 t off => s!"loadParamU8:{t}@{off}"
  | .loadLiteralU64 t v => s!"loadLiteralU64:{t}:{encodeUInt64LowerHex16 v}"
  | .loadLiteralU8 t v => s!"loadLiteralU8:{t}:{encodeUInt8LowerHex2 v}"
  | .stateLoadU64 t li off => s!"stateLoadU64:{t}:local{li}@{off}"
  | .checkedAddU64 d l r => s!"checkedAddU64:{d}:{l}:{r}"
  | .stateStoreU64 li off src wm marker =>
      s!"stateStoreU64:local{li}@{off}:src{src}:marker{wm}:{encodeUInt64LowerHex16 marker}"
  | .siteChecks sid ops =>
      let parts := String.intercalate ";" (ops.map preflightOpKindNameV1).toList
      s!"siteChecks:{sid}:[{parts}]"
  | .invokeSigned inv => renderInvoke inv
  | .returnU64 t => s!"returnU64:{t}"
  | .returnNone => "returnNone"

private def renderMode : HandlerModeV1 → String
  | .initialize => "initialize"
  | .entry => "entry"
  | .view => "view"

private def renderHandler (h : CpiPdaHandlerIRV1) : String :=
  let entry := String.intercalate ";" (h.entryGlobalOps.map preflightOpKindNameV1).toList
  let body := String.intercalate ";" (h.bodyOps.map renderBodyOp).toList
  s!"handler:{h.handlerId}:{h.callableId}:{h.name}:{renderMode h.mode}:roles{h.localRoleCount}:probe{h.probeIxDataLen}:temps{h.tempCount}:entry[{entry}]:body[{body}]"

private def renderCandidate (c : SolanaCpiPdaIRCandidateV1) : CompileResult String := do
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

/-- Sole mint of the #120 PDA-signed execution IR from Semantic-bound Plan. -/
def resolveSolanaCpiPdaIRV1
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult ResolvedSolanaCpiPdaIRV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    pFail "PDA CPI IR requires activationDenied preflight carrier"
  let candidate ← projectPdaCandidate authority
  unless candidate.schema == pdaIrSchemaV1 do
    pFail s!"schema must be {pdaIrSchemaV1}"
  unless candidate.maxFrameBytes == 4096 do
    pFail "maxFrameBytes must be 4096"
  for h in candidate.handlers do
    unless h.localRoleCount ≤ maxOuterRolesV1 do
      pFail s!"handler {h.handlerId} localRoleCount exceeds cap"
    let ops := h.bodyOps
    for i in [0:ops.size] do
      match ops[i]! with
      | .siteChecks sid _ =>
          let j := i + 1
          unless j < ops.size do
            pFail s!"siteChecks {sid} is not followed by invokeSigned"
          match ops[j]! with
          | .invokeSigned inv =>
              unless inv.siteId == sid do
                pFail s!"siteChecks {sid} mismatched invoke site {inv.siteId}"
          | _ =>
              pFail s!"siteChecks {sid} must be immediately followed by invokeSigned"
      | .invokeSigned inv =>
          unless inv.metas.size == 2 && inv.outerOnly.size == 1 do
            pFail s!"invokeSigned site {inv.siteId} requires two metas and one outer-only"
          unless inv.account.argIndex == 0 && inv.authorityPda.argIndex == 1 &&
              inv.seedAuthority.argIndex == 2 do
            pFail s!"invokeSigned site {inv.siteId} Principal arg indices diverged"
          unless inv.metas[0]!.roleId == inv.account.roleId &&
              inv.metas[0]!.localIndex == inv.account.localIndex &&
              inv.metas[1]!.roleId == inv.authorityPda.roleId &&
              inv.metas[1]!.localIndex == inv.authorityPda.localIndex &&
              inv.outerOnly[0]!.roleId == inv.seedAuthority.roleId &&
              inv.outerOnly[0]!.localIndex == inv.seedAuthority.localIndex do
            pFail s!"invokeSigned site {inv.siteId} meta/outer-only Principal join diverged"
          unless inv.signerGroupId == 0 && inv.pdaRule == "current-program-tagged-v1" &&
              inv.tag == 2 && inv.dataLen == 9 do
            pFail s!"invokeSigned site {inv.siteId} frozen PDA/signer/tag shape diverged"
          match inv.bump with
          | .literal 0 =>
              pFail s!"invokeSigned site {inv.siteId} bump literal 0 rejected"
          | _ => pure ()
          if i == 0 then
            pFail s!"invokeSigned site {inv.siteId} missing preceding siteChecks"
          else
            match ops[i - 1]! with
            | .siteChecks sid _ =>
                unless sid == inv.siteId do
                  pFail s!"invokeSigned site {inv.siteId} not preceded by matching siteChecks"
            | _ =>
                pFail s!"invokeSigned site {inv.siteId} missing immediately preceding siteChecks"
      | _ => pure ()
  let text ← renderCandidate candidate
  let canonicalBytes := text.toUTF8
  let digest ← mapExcept
    (domainSeparatedSha256 pdaIrDigestDomainV1 canonicalBytes)
    "pda-ir digest"
  pure ⟨authority, candidate, canonicalBytes, digest⟩

/-- Exact signed scratch size: 256 + 56*N (see EmitCpiPdaSbpfV1 layout). -/
def pdaCpiScratchBytesV1 (localRoleCount : Nat) : Nat :=
  256 + localRoleCount * 56

/-- Max site scratch across handlers. -/
def pdaMaxSiteScratchV1 (c : SolanaCpiPdaIRCandidateV1) : Nat :=
  Id.run do
    let mut maxB : Nat := 0
    for h in c.handlers do
      for op in h.bodyOps do
        match op with
        | .invokeSigned inv =>
            let b := pdaCpiScratchBytesV1 inv.accountInfoCount
            if b > maxB then maxB := b
        | _ => pure ()
    pure maxB

end ProofForgeV2.Targets.Solana.CpiV1

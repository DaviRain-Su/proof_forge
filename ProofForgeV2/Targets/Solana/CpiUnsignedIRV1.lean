/-
  ProofForgeV2.Targets.Solana.CpiUnsignedIRV1 — #119 unsigned companion CPI IR.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Sole mint: `resolveSolanaCpiUnsignedIRV1`. Consumes only
  `ResolvedSolanaCpiPreflightIRV1` (Semantic-derived authority). Builds an
  ordered execution IR that:

  * keeps handler-entry global preflight checks separate from site-time
    predicates (predicates are never permanently hoisted past earlier body
    mutation / earlier CPI);
  * admits only single-block straight-line initializer/entry/view callables;
  * admits only `solana.companion.invoke` / `solana.companion.fail`;
  * lowers a narrow public UInt64 body subset:
    param / literal / stateLoad / checkedAdd / stateStore / externalCall /
    returnU64 / returnNone;
  * rejects System, PDA/signer groups, Token, ATA, schedule, typed returns,
    multi-block CFG, and dynamic CPI.

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

def unsignedIrSchemaV1 : String := "proof-forge.solana.cpi-unsigned-ir.v1"
def unsignedIrDigestDomainV1 : String := "pf.solana.cpi-unsigned-ir.v1"

/-- UInt64 value sources for CPI instruction-data segments (first slice). -/
inductive CpiUnsignedU64SourceV1 where
  /-- Direct public UInt64 parameter of the owning callable. -/
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  /-- Canonical UInt64 literal (exact 8-byte LE valueBytes). -/
  | literal (value : UInt64)
  deriving BEq, Repr, Inhabited

/-- One CPI meta binding to a handler-local role. -/
structure CpiUnsignedMetaV1 where
  metaIndex : Nat
  roleId : Nat
  localIndex : Nat
  cpiWritable : Bool
  cpiSigner : Bool
  deriving BEq, Repr, Inhabited

/-- Exact Semantic Principal → callable parameter → outer role join retained by
    the unsigned IR. The runtime key is synthesized from `localIndex`; this row
    prevents a ValueId from being silently rebound to a different role. -/
structure CpiUnsignedPrincipalBindingV1 where
  argIndex : Nat
  semanticValueId : Nat
  paramOrdinal : Nat
  roleId : Nat
  localIndex : Nat
  deriving BEq, Repr, Inhabited

/-- Site-local unsigned invoke description (companion-v1 only). -/
structure CpiUnsignedInvokeV1 where
  siteId : Nat
  qn : String
  packageId : String
  programLocalIndex : Nat
  /-- Companion tag byte: 0 = invoke, 1 = fail. -/
  tag : Nat
  dataLen : Nat
  delta : CpiUnsignedU64SourceV1
  principalBindings : Array CpiUnsignedPrincipalBindingV1
  metas : Array CpiUnsignedMetaV1
  /-- Full handler-local AccountInfo count (all roles, once each). -/
  accountInfoCount : Nat
  deriving BEq, Repr

/-- Ordered body operations after handler-entry global preflight. -/
inductive CpiUnsignedBodyOpV1 where
  /-- Materialise a UInt64 param from probe instruction data. -/
  | loadParamU64 (tempId : Nat) (ixDataOffset : Nat)
  /-- Materialise a UInt64 literal into a temp. -/
  | loadLiteralU64 (tempId : Nat) (value : UInt64)
  /-- Load UInt64 state field from role-local account data. -/
  | stateLoadU64 (tempId : Nat) (stateLocalIndex : Nat) (byteOffset : Nat)
  /-- Checked UInt64 add (overflow → Custom(0x1001) style fail). -/
  | checkedAddU64 (dstTemp lhsTemp rhsTemp : Nat)
  /-- Store UInt64 into state field (and ensure initialized marker if needed). -/
  | stateStoreU64 (stateLocalIndex : Nat) (byteOffset : Nat) (srcTemp : Nat)
    (writeInitializedMarker : Bool) (initializedMarker : UInt64)
  /-- Site-time predicates only (must run immediately before the matching invoke). -/
  | siteChecks (siteId : Nat) (ops : Array CpiPreflightOpV1)
  /-- Unsigned `sol_invoke_signed_c` with zero signer groups. -/
  | invokeUnsigned (invoke : CpiUnsignedInvokeV1)
  /-- Top-level success return of a UInt64 (sets return data). -/
  | returnU64 (srcTemp : Nat)
  /-- Top-level success with empty return data. -/
  | returnNone
  deriving BEq, Repr, Inhabited

/-- One handler's complete unsigned-CPI program. -/
structure CpiUnsignedHandlerIRV1 where
  handlerId : Nat
  callableId : Nat
  name : String
  mode : HandlerModeV1
  localRoleCount : Nat
  localRoleOrder : Array CpiIRRoleHandleV1
  accountParameterBindings : Array CpiPreflightAccountParamBindingV1
  /-- Exact probe instruction-data length (handlerId u64 + non-Principal UInt64 params). -/
  probeIxDataLen : Nat
  /-- Handler-entry global checks only (no site predicates). -/
  entryGlobalOps : Array CpiPreflightOpV1
  /-- Ordered body; siteChecks always immediately precede their invoke. -/
  bodyOps : Array CpiUnsignedBodyOpV1
  tempCount : Nat
  deriving BEq, Repr

/-- Public candidate (not yet validated). -/
structure SolanaCpiUnsignedIRCandidateV1 where
  schema : String
  sourcePlanDigest : Digest
  sourcePreflightIrDigest : Digest
  profileId : String
  profileDigest : Digest
  catalogDigest : Digest
  abiLayout : LoaderV3AbiLayoutV1
  maxOuterRoles : Nat
  maxFrameBytes : Nat
  handlers : Array CpiUnsignedHandlerIRV1
  deriving BEq

/-- Private resolved unsigned IR. Sole mint from resolved preflight IR authority. -/
structure ResolvedSolanaCpiUnsignedIRV1 where
  private mk ::
  authority : ResolvedSolanaCpiPreflightIRV1
  candidate : SolanaCpiUnsignedIRCandidateV1
  canonicalBytes : ByteArray
  digest : Digest

namespace ResolvedSolanaCpiUnsignedIRV1

def authorityOf (r : ResolvedSolanaCpiUnsignedIRV1) : ResolvedSolanaCpiPreflightIRV1 :=
  r.authority
def candidateOf (r : ResolvedSolanaCpiUnsignedIRV1) : SolanaCpiUnsignedIRCandidateV1 :=
  r.candidate
def digestOf (r : ResolvedSolanaCpiUnsignedIRV1) : Digest :=
  r.digest
def canonicalBytesOf (r : ResolvedSolanaCpiUnsignedIRV1) : ByteArray :=
  r.canonicalBytes

end ResolvedSolanaCpiUnsignedIRV1

/-! ## Internals -/

private def uFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def mapExcept (e : Except String α) (ctx : String) : CompileResult α :=
  match e with
  | .ok v => pure v
  | .error msg => uFail s!"{ctx}: {msg}"

private def digestsEqual (left right : Digest) : Bool :=
  left.algorithm == right.algorithm && left.bytes == right.bytes

private def getArr (arr : Array α) (i : Nat) (ctx : String) : CompileResult α :=
  match arr[i]? with
  | some v => pure v
  | none => uFail s!"{ctx}: index {i} out of range"

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
    uFail s!"UInt64 valueBytes must be exact 8 bytes, got {bytes.size}"
  let mut n : Nat := 0
  for i in [0:8] do
    n := n + bytes[i]!.toNat * (Nat.pow 2 (8 * i))
  pure (UInt64.ofNat n)

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

/-- Reuse #118 owner resolution (exact owner / current program / none). -/
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
          uFail s!"owner fixedProgram package '{packageId}' missing from catalog"
  | .catalogExecutionClass =>
      let packageId ← match catalogPackageId? with
        | some id => pure id
        | none =>
            uFail "catalogExecutionClass owner requires a fixed-program package context"
      match findCalleePackage? packageId with
      | some package =>
          pure #[.checkOwnerExact localIndex
            (executionClassOwnerPubkeyV1 package.executionClass)]
      | none =>
          uFail s!"catalogExecutionClass package '{packageId}' missing from catalog"
  | .any => pure #[]
  | .closedPackages _ =>
      uFail "unsigned CPI IR rejects closedPackages owner (Token/ATA deferred)"

private def resolveExecutableOps
    (localIndex : Nat) (exec : ExecutablePolicy) : Array CpiPreflightOpV1 :=
  match exec with
  | .required => #[.checkExecutableRequired localIndex]
  | .forbidden => #[.checkExecutableForbidden localIndex]

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
      uFail "unsigned CPI IR rejects uninitialized initialization"
  | .canonicalPda =>
      uFail "unsigned CPI IR rejects canonicalPda initialization (PDA deferred)"
  | .uninitializedOrIdempotentlyInitialized =>
      uFail "unsigned CPI IR rejects ATA initialization"
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
        | _ => uFail "proofForgeState data requires RoleKeyPolicyV1.state"
      let schema ← match findStateSchema? stateSchemas schemaId with
        | some s => pure s
        | none => uFail s!"proofForgeState schemaId {schemaId} missing"
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
      | .existing | .any | .catalogPackageAdmitted => pure ()
      | _ => pure ()
  | .classicTokenAccount .. =>
      uFail "unsigned CPI IR rejects classicTokenAccount data"
  | .classicTokenMint .. =>
      uFail "unsigned CPI IR rejects classicTokenMint data"
  | .ataAccount .. =>
      uFail "unsigned CPI IR rejects ataAccount data"
  pure ops

private def resolveProvisioning (prov : ProvisioningPolicy) : CompileResult Unit := do
  match prov with
  | .none | .mustExist => pure ()
  | .systemCreateAccount =>
      uFail "unsigned CPI IR rejects systemCreateAccount provisioning"
  | .ataCreateIdempotent =>
      uFail "unsigned CPI IR rejects ataCreateIdempotent provisioning"

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

/-- Handler-entry global checks only (site predicates excluded). -/
private def projectEntryGlobalOps
    (abi : LoaderV3AbiLayoutV1)
    (mode : HandlerModeV1)
    (handles : Array CpiIRRoleHandleV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult
      (Array CpiPreflightAccountParamBindingV1 × Array CpiPreflightOpV1) := do
  let n := handles.size
  unless n ≤ maxOuterRolesV1 do
    uFail s!"handler local role count {n} exceeds maxOuterRoles {maxOuterRolesV1}"
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
            uFail s!"fixedProgram package '{packageId}' missing from frozen catalog"
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
          uFail s!"site predicate roleId {pred.roleId} missing from handler locals"
    unless handle.localIndex < handles.size do
      uFail s!"site predicate roleId {pred.roleId} has out-of-range localIndex"
    let denseHandle ← getArr handles handle.localIndex "site predicate dense local handles"
    unless denseHandle.roleId == handle.roleId &&
        denseHandle.localIndex == handle.localIndex do
      uFail s!"site predicate roleId {pred.roleId} has non-dense local handle"
    let packageOverride : Option String :=
      match pred.source with
      | .callee => some site.packageId
      | .metaIndex _ | .outerOnlyIndex _ => none
    let predOps ← projectConstraintOps handle.localIndex mode handle.keyPolicy
      pred.constraint stateSchemas packageOverride
    ops := ops ++ predOps
  pure ops

private def companionTagOfQn (qn : String) : CompileResult Nat :=
  match qn with
  | "solana.companion.invoke" => pure 0
  | "solana.companion.fail" => pure 1
  | _ =>
      uFail
        s!"unsigned CPI first slice admits only solana.companion.invoke/.fail, got '{qn}'"

/-- Non-Principal public UInt64 params in declaration order → probe ix offsets
    after the 8-byte handlerId header. Principal params are omitted. -/
private def buildParamIxLayout
    (types : Array TypeDeclV1) (callable : CallableV1) :
    CompileResult (Array (Nat × Nat) × Nat) := do
  let mut layout : Array (Nat × Nat) := #[]
  let mut offset : Nat := 8
  for (p, ord) in callable.params.zipIdx do
    unless p.visibility == VisibilityV1.public_ do
      uFail "unsigned CPI IR requires public parameters only"
    if isAnonPrincipal types p.typeId then
      pure ()
    else if anonUintWidth? types p.typeId == some 64 then
      layout := layout.push (ord, offset)
      offset := offset + 8
    else
      uFail
        s!"unsigned CPI IR admits only public Principal or UInt64 params, got param '{p.name}'"
  pure (layout, offset)

private def ixOffsetOfParam?
    (layout : Array (Nat × Nat)) (paramOrdinal : Nat) : Option Nat :=
  Id.run do
    for (ord, off) in layout do
      if ord == paramOrdinal then return some off
    return none

private def requireStraightLineCallable
    (callable : CallableV1) : CompileResult BlockV1 := do
  unless callable.blocks.size == 1 do
    uFail
      s!"unsigned CPI IR requires single-block straight-line callables (got {callable.blocks.size} blocks)"
  unless callable.entryBlock.toNat == 0 do
    uFail "unsigned CPI IR requires entryBlock == 0"
  unless callable.loopBounds.isEmpty do
    uFail "unsigned CPI IR rejects loopBounds (no back edges)"
  let blk ← getArr callable.blocks 0 "callable.blocks"
  unless blk.id.toNat == 0 do
    uFail "unsigned CPI IR requires sole block id == 0"
  unless blk.params.isEmpty do
    uFail "unsigned CPI IR rejects block parameters"
  pure blk

private def localIndexOfRole
    (handles : Array CpiIRRoleHandleV1) (roleId : Nat) : CompileResult Nat :=
  match handles.find? (fun h => h.roleId == roleId) with
  | some h => pure h.localIndex
  | none => uFail s!"roleId {roleId} missing from handler local roles"

private def stateLocalAndSchema
    (handles : Array CpiIRRoleHandleV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult (Nat × StateSchemaV1) := do
  let mut found : Option (Nat × Nat) := none
  for h in handles do
    match h.keyPolicy with
    | .state sid =>
        match found with
        | some _ => uFail "unsigned CPI IR admits at most one state role"
        | none => found := some (h.localIndex, sid)
    | _ => pure ()
  match found with
  | none => uFail "unsigned CPI IR body requires a state role for stateLoad/Store"
  | some (localIdx, sid) =>
      match findStateSchema? stateSchemas sid with
      | some s =>
          -- First-slice single UInt64 field: header 8 + value 8.
          unless s.exactDataLen == 16 do
            uFail
              s!"unsigned CPI IR first slice admits only single UInt64 state (exactDataLen 16), got {s.exactDataLen}"
          pure (localIdx, s)
      | none => uFail s!"state schema {sid} missing"

private def findLiteralU64?
    (types : Array TypeDeclV1) (callable : CallableV1) (vid : ValueIdV1) :
    Option UInt64 :=
  Id.run do
    for blk in callable.blocks do
      for instr in blk.instructions do
        match instr.result, instr.op with
        | some vd, .literal tid bytes =>
            if vd.valueId == vid && anonUintWidth? types tid == some 64 then
              -- Decode LE without fail (transport already structure-gated).
              if bytes.size == 8 then
                let mut n : Nat := 0
                for i in [0:8] do
                  n := n + bytes[i]!.toNat * (Nat.pow 2 (8 * i))
                return some (UInt64.ofNat n)
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

private def directPublicPrincipalParamOrdinal?
    (types : Array TypeDeclV1) (callable : CallableV1) (vid : ValueIdV1) :
    Option Nat :=
  Id.run do
    for (p, i) in callable.params.zipIdx do
      if p.valueId == vid && p.visibility == VisibilityV1.public_ &&
          isAnonPrincipal types p.typeId then
        return some i
    return none

/-- Rejoin a Semantic Principal argument to the exact direct parameter, Plan
    argument role, dense handler-local handle, and preflight binding row. -/
private def resolvePrincipalAccountBinding
    (types : Array TypeDeclV1)
    (callable : CallableV1)
    (handles : Array CpiIRRoleHandleV1)
    (bindings : Array CpiPreflightAccountParamBindingV1)
    (site : CpiIRSiteV1)
    (argIndex : Nat)
    (vid : ValueIdV1) :
    CompileResult CpiUnsignedPrincipalBindingV1 := do
  let paramOrdinal ← match directPublicPrincipalParamOrdinal? types callable vid with
    | some ord => pure ord
    | none =>
        uFail s!"site {site.siteId} arg {argIndex}: expected bare direct public Principal parameter"
  let arg ← getArr site.args argIndex s!"site {site.siteId}.args"
  unless arg.spec.type_ == FrozenValueType.principal &&
      arg.spec.source == ArgumentSource.bareDirectPublicPrincipalParameter do
    uFail s!"site {site.siteId} arg {argIndex}: frozen Principal source diverged"
  unless arg.semanticValueId == vid.toNat do
    uFail s!"site {site.siteId} arg {argIndex}: Semantic ValueId diverged from Plan binding"
  let roleId ← match arg.roleId with
    | some rid => pure rid
    | none => uFail s!"site {site.siteId} arg {argIndex}: Principal roleId missing"
  let handle ← match handles.find? (fun h => h.roleId == roleId) with
    | some h => pure h
    | none => uFail s!"site {site.siteId} arg {argIndex}: roleId {roleId} missing from handler"
  unless handle.localIndex < handles.size do
    uFail s!"site {site.siteId} arg {argIndex}: localIndex out of range"
  let denseHandle ← getArr handles handle.localIndex "handler dense local handles"
  unless denseHandle.roleId == roleId && denseHandle.localIndex == handle.localIndex do
    uFail s!"site {site.siteId} arg {argIndex}: local handle is not dense/exact"
  match handle.keyPolicy with
  | .accountParameter callableId boundOrdinal =>
      unless callableId == callable.id.toNat && boundOrdinal == paramOrdinal do
        uFail s!"site {site.siteId} arg {argIndex}: account role does not bind the exact callable parameter"
  | _ =>
      uFail s!"site {site.siteId} arg {argIndex}: Principal role is not accountParameter-bound"
  let paramBindings := bindings.filter (fun b =>
    b.callableId == callable.id.toNat && b.paramOrdinal == paramOrdinal)
  unless paramBindings.size == 1 do
    uFail s!"site {site.siteId} arg {argIndex}: expected exactly one preflight binding for the parameter"
  let exactBinding ← getArr paramBindings 0 "Principal preflight parameter binding"
  unless exactBinding.roleId == roleId &&
      exactBinding.localIndex == handle.localIndex do
    uFail s!"site {site.siteId} arg {argIndex}: preflight binding role/local index diverged"
  pure {
    argIndex
    semanticValueId := vid.toNat
    paramOrdinal
    roleId
    localIndex := handle.localIndex
  }

private def resolveU64Source
    (types : Array TypeDeclV1) (callable : CallableV1)
    (layout : Array (Nat × Nat)) (vid : ValueIdV1) (ctx : String) :
    CompileResult CpiUnsignedU64SourceV1 := do
  match findLiteralU64? types callable vid with
  | some v => pure (.literal v)
  | none =>
      match directPublicU64ParamOrdinal? types callable vid with
      | some ord =>
          match ixOffsetOfParam? layout ord with
          | some off => pure (.param ord off)
          | none =>
              uFail s!"{ctx}: UInt64 param ordinal {ord} missing from probe layout"
      | none =>
          uFail
            s!"{ctx}: first-slice CPI numeric arg admits only direct public UInt64 param or UInt64 literal"

/-- Project one handler into unsigned IR. -/
private def projectUnsignedHandler
    (abi : LoaderV3AbiLayoutV1)
    (data : SemanticProgramDataV1)
    (planHandler : HandlerPlanV1)
    (handles : Array CpiIRRoleHandleV1)
    (sites : Array CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult CpiUnsignedHandlerIRV1 := do
  let callable ← getArr data.callables planHandler.callableId "callables"
  unless callable.id.toNat == planHandler.callableId do
    uFail "handler callableId must equal Semantic callable.id"
  unless callable.blocks.size ≥ 1 do
    uFail "callable has no blocks"
  unless handles.size == planHandler.accountUses.size do
    uFail "handler local handle count must equal Plan accountUses size"
  for i in [0:handles.size] do
    let handle ← getArr handles i "handler local handles"
    let use ← getArr planHandler.accountUses i "handler accountUses"
    unless handle.handlerId == planHandler.handlerId &&
        handle.localIndex == i && use.position == i &&
        handle.roleId == use.roleId do
      uFail s!"handler {planHandler.handlerId} local handle order diverged at {i}"
  -- Surface gates on sites attached to this handler.
  for site in sites do
    unless site.handlerId == planHandler.handlerId do
      uFail "site handlerId mismatch"
    match site.pda with
    | .none => pure ()
    | .signer .. | .addressCheckOnly .. | .vaultPdaSigner _ =>
        uFail s!"unsigned CPI IR rejects PDA at site {site.siteId}"
    unless site.signerGroups.isEmpty do
      uFail s!"unsigned CPI IR rejects signerGroups at site {site.siteId}"
    unless site.preflight.isEmpty do
      uFail s!"unsigned CPI IR rejects site preflight arg predicates at site {site.siteId}"
    unless site.packageId == "companion-v1" do
      uFail
        s!"unsigned CPI first slice admits only companion-v1, got '{site.packageId}' at site {site.siteId}"
    let _ ← companionTagOfQn site.qn

  let blk ← requireStraightLineCallable callable
  let (paramLayout, probeIxDataLen) ← buildParamIxLayout data.types callable
  let (bindings, entryGlobalOps) ←
    projectEntryGlobalOps abi planHandler.mode handles stateSchemas

  -- ValueId → tempId for materialised UInt64 values.
  -- NOTE: helpers take the maps as parameters — Lean `mut` is not captured by
  -- nested `let` closures (would permanently see the empty initial table).
  let mut tempOf : Array (Nat × Nat) := #[]  -- (valueId, tempId)
  let mut nextTemp : Nat := 0
  let mut body : Array CpiUnsignedBodyOpV1 := #[]

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

  -- Load every non-Principal UInt64 param into a temp at body start.
  for (ord, off) in paramLayout do
    let p ← getArr callable.params ord "callable.params"
    let (t, tempOf', next') := allocTemp tempOf nextTemp p.valueId.toNat
    tempOf := tempOf'
    nextTemp := next'
    body := body.push (.loadParamU64 t off)

  -- Optional state schema for stores/loads.
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

  -- Walk Semantic instructions in source order.
  for (instr, instrIdx) in blk.instructions.zipIdx do
    match instr.op with
    | .literal tid bytes =>
        let some vd := instr.result |
          uFail "literal must produce a result"
        unless anonUintWidth? data.types tid == some 64 do
          uFail "unsigned CPI IR admits only UInt64 literals in body"
        let v ← decodeUInt64LE bytes
        let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
        tempOf := tempOf'
        nextTemp := next'
        body := body.push (.loadLiteralU64 t v)
    | .stateLoad stateId =>
        let some vd := instr.result |
          uFail "stateLoad must produce a result"
        let (stateLocal, schema) ← match stateInfo? with
          | some s => pure s
          | none => uFail "stateLoad without state role"
        unless stateId.toNat == 0 do
          uFail "unsigned CPI IR first slice admits only stateId 0"
        unless schema.exactDataLen == 16 do
          uFail "stateLoad requires single UInt64 state layout"
        let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
        tempOf := tempOf'
        nextTemp := next'
        -- Header 8 bytes, first UInt64 field at offset 8.
        body := body.push (.stateLoadU64 t stateLocal 8)
    | .stateStore stateId value =>
        let (stateLocal, schema) ← match stateInfo? with
          | some s => pure s
          | none => uFail "stateStore without state role"
        unless stateId.toNat == 0 do
          uFail "unsigned CPI IR first slice admits only stateId 0"
        let src ← match lookupTemp tempOf value.toNat with
          | some t => pure t
          | none =>
              -- Allow direct param / just-emitted value: if missing, try materialise.
              match directPublicU64ParamOrdinal? data.types callable value with
              | some ord =>
                  match ixOffsetOfParam? paramLayout ord with
                  | some off =>
                      let (t, tempOf', next') := allocTemp tempOf nextTemp value.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadParamU64 t off)
                      pure t
                  | none => uFail "stateStore value param missing from probe layout"
              | none =>
                  match findLiteralU64? data.types callable value with
                  | some lit =>
                      let (t, tempOf', next') := allocTemp tempOf nextTemp value.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadLiteralU64 t lit)
                      pure t
                  | none =>
                      uFail s!"stateStore value ValueId {value} is not materialised"
        let writeMarker := planHandler.mode == .initialize
        body := body.push
          (.stateStoreU64 stateLocal 8 src writeMarker schema.initializedMarker)
    | .binary opKind lhs rhs =>
        let some vd := instr.result |
          uFail "binary must produce a result"
        match opKind with
        | BinaryOpV1.add =>
            let l ← match lookupTemp tempOf lhs.toNat with
              | some t => pure t
              | none => uFail s!"checkedAdd lhs ValueId {lhs} not materialised"
            let r ← match lookupTemp tempOf rhs.toNat with
              | some t => pure t
              | none => uFail s!"checkedAdd rhs ValueId {rhs} not materialised"
            let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
            tempOf := tempOf'
            nextTemp := next'
            body := body.push (.checkedAddU64 t l r)
        | _ =>
            uFail
              "unsigned CPI IR first slice admits only checked UInt64 add in body"
    | .externalCall effectId callee args =>
        -- Locate matching Plan/IR site by exact anchor.
        let qnComps ← mapExcept (renderQualifiedNameComponents callee) "callee QN"
        let qn := String.intercalate "." qnComps.toList
        let tag ← companionTagOfQn qn
        let site ← match sites.find? (fun s =>
            s.anchor.callableId == planHandler.callableId &&
              s.anchor.blockId == blk.id.toNat &&
              s.anchor.instructionIndex == instrIdx &&
              s.anchor.effectId == effectId.toNat) with
          | some s => pure s
          | none =>
              uFail
                s!"ExternalCall at instr {instrIdx} has no matching CPI site anchor"
        unless site.qn == qn do
          uFail "site QN diverges from Semantic ExternalCall"
        unless site.packageId == "companion-v1" do
          uFail "ExternalCall package must be companion-v1"
        unless args.size == 2 && site.args.size == 2 do
          uFail "companion invoke/fail require exactly 2 Semantic and Plan args"
        -- Arg0 Principal: exact ValueId → direct param ordinal → role → dense
        -- handler-local handle → preflight binding rejoin.
        let accountVid ← getArr args 0 "externalCall.args"
        let accountBinding ← resolvePrincipalAccountBinding data.types callable
          handles bindings site 0 accountVid
        let deltaVid ← getArr args 1 "externalCall.args"
        let deltaArg ← getArr site.args 1 s!"site {site.siteId}.args"
        unless deltaArg.semanticValueId == deltaVid.toNat && deltaArg.roleId.isNone &&
            deltaArg.spec.type_ == FrozenValueType.uint64 do
          uFail s!"site {site.siteId} delta binding diverged from Semantic arg"
        let deltaSrc ← resolveU64Source data.types callable paramLayout deltaVid
          s!"site {site.siteId} delta"
        let programLocal ← localIndexOfRole handles site.programRoleId
        unless site.programHandleIndex == programLocal do
          uFail s!"site {site.siteId} program handle index diverged"
        unless site.metas.size == 1 do
          uFail "companion invoke/fail require exactly one CPI meta"
        let accountMeta ← getArr site.metas 0 s!"site {site.siteId}.metas"
        unless accountMeta.metaIndex == 0 &&
            accountMeta.roleId == accountBinding.roleId &&
            accountMeta.localHandleIndex == accountBinding.localIndex do
          uFail s!"site {site.siteId} account meta does not join the Principal role"
        let mut metas : Array CpiUnsignedMetaV1 := #[]
        for m in site.metas do
          let li ← localIndexOfRole handles m.roleId
          unless m.localHandleIndex == li do
            uFail s!"site {site.siteId} meta {m.metaIndex} local handle diverged"
          metas := metas.push {
            metaIndex := m.metaIndex
            roleId := m.roleId
            localIndex := li
            cpiWritable := m.spec.cpiWritable
            cpiSigner := m.spec.cpiSigner
          }
        let siteOps ← projectSiteChecks planHandler.mode handles site stateSchemas
        body := body.push (.siteChecks site.siteId siteOps)
        body := body.push (.invokeUnsigned {
          siteId := site.siteId
          qn
          packageId := site.packageId
          programLocalIndex := programLocal
          tag
          dataLen := site.instructionCodec.length
          delta := deltaSrc
          principalBindings := #[accountBinding]
          metas
          accountInfoCount := handles.size
        })
    | .constant _cid =>
        uFail "unsigned CPI IR rejects Op.Constant (constants table support deferred)"
    | .unary .. =>
        uFail "unsigned CPI IR rejects unary ops in first slice"
    | .pureCall .. =>
        uFail "unsigned CPI IR rejects pureCall in first slice"
    | .construct .. | .fieldGet .. | .fieldSet .. | .indexGet .. | .indexSet ..
    | .variantTag .. | .variantPayload .. | .checkedCast ..
    | .contextRead .. | .envRead .. | .commit .. | .assert_ .. | .emit .. | .schedule .. =>
        uFail "unsigned CPI IR rejects unsupported body op in first slice"

  -- Terminator.
  match blk.terminator with
  | .return_ none =>
      body := body.push .returnNone
  | .return_ (some vid) =>
      if isAnonUnit data.types (← match typeOfValueId? callable vid with
          | some t => pure t
          | none => uFail "return value has no type") then
        body := body.push .returnNone
      else
        let src ← match lookupTemp tempOf vid.toNat with
          | some t => pure t
          | none =>
              match directPublicU64ParamOrdinal? data.types callable vid with
              | some ord =>
                  match ixOffsetOfParam? paramLayout ord with
                  | some off =>
                      let (t, tempOf', next') := allocTemp tempOf nextTemp vid.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadParamU64 t off)
                      pure t
                  | none => uFail "return param missing from probe layout"
              | none =>
                  match findLiteralU64? data.types callable vid with
                  | some lit =>
                      let (t, tempOf', next') := allocTemp tempOf nextTemp vid.toNat
                      tempOf := tempOf'
                      nextTemp := next'
                      body := body.push (.loadLiteralU64 t lit)
                      pure t
                  | none =>
                      uFail s!"return ValueId {vid} is not materialised"
        body := body.push (.returnU64 src)
  | .jump .. | .branch .. | .switch .. | .revert .. | .trap _ =>
      uFail "unsigned CPI IR requires return terminator only (straight-line)"

  -- Every Plan site for this handler must appear as an invoke in body order.
  let bodySiteIds :=
    body.foldl (init := ([] : List Nat)) fun acc op =>
      match op with
      | .invokeUnsigned inv => acc ++ [inv.siteId]
      | _ => acc
  let planSiteIds := sites.map (·.siteId) |>.toList
  unless bodySiteIds == planSiteIds do
    uFail
      "unsigned body invoke site order must equal Plan cpiSiteIds (source order)"

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

private def projectUnsignedCandidate
    (resolved : ResolvedSolanaCpiPreflightIRV1) :
    CompileResult SolanaCpiUnsignedIRCandidateV1 := do
  let planAuth := ResolvedSolanaCpiPreflightIRV1.authorityOf resolved
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf planAuth) do
    uFail "unsigned CPI IR requires activationDenied authority"
  let plan := SolanaCpiPreflightPlanV1.planOf planAuth
  let preflightCand := ResolvedSolanaCpiPreflightIRV1.candidateOf resolved
  let compiled :=
    ResolvedSolanaCpiPreflightV1.compiledOf
      (SolanaCpiPreflightPlanV1.preflightOf planAuth)
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok v => pure v
    | .error _ =>
        uFail "unsigned CPI IR: retained Semantic failed structure validation"
  unless data.constants.isEmpty do
    uFail "unsigned CPI IR rejects nonempty constants table"
  unless data.invariants.isEmpty do
    uFail "unsigned CPI IR rejects nonempty invariants"
  let ir ← deriveSolanaCpiIRV1 plan
  unless digestsEqual ir.digest preflightCand.sourceIrDigest do
    uFail "unsigned IR source preflight must join validated CPI IR digest"
  let abi := preflightCand.abiLayout
  unless abi == frozenLoaderV3AbiLayoutV1 do
    uFail "unsigned CPI IR requires frozen Loader V3 ABIv1 layout"
  let mut handlers : Array CpiUnsignedHandlerIRV1 := #[]
  for h in plan.candidate.handlers do
    let handles := ir.candidate.roleHandles.filter (fun x => x.handlerId == h.handlerId)
    unless handles.size == h.accountUses.size do
      uFail "handler local handle count mismatch"
    let sites := ir.candidate.sites.filter (fun s => s.handlerId == h.handlerId)
    unless sites.map (·.siteId) == h.cpiSiteIds do
      uFail "handler site order must equal Plan cpiSiteIds"
    let projected ← projectUnsignedHandler abi data h handles sites
      plan.candidate.stateSchemas
    handlers := handlers.push projected
  pure {
    schema := unsignedIrSchemaV1
    sourcePlanDigest := plan.digest
    sourcePreflightIrDigest := ResolvedSolanaCpiPreflightIRV1.digestOf resolved
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

private def renderU64Source : CpiUnsignedU64SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt64LowerHex16 v}"

private def renderMeta (m : CpiUnsignedMetaV1) : String :=
  s!"{m.metaIndex}:role{m.roleId}:local{m.localIndex}:w{m.cpiWritable}:s{m.cpiSigner}"

private def renderPrincipalBinding (b : CpiUnsignedPrincipalBindingV1) : String :=
  s!"arg{b.argIndex}:v{b.semanticValueId}:p{b.paramOrdinal}:role{b.roleId}:local{b.localIndex}"

private def renderInvoke (i : CpiUnsignedInvokeV1) : String :=
  let principals := String.intercalate "," (i.principalBindings.map renderPrincipalBinding).toList
  let metas := String.intercalate "," (i.metas.map renderMeta).toList
  s!"invoke:{i.siteId}:{i.qn}:{i.packageId}:prog{i.programLocalIndex}:tag{i.tag}:len{i.dataLen}:delta[{renderU64Source i.delta}]:principals[{principals}]:metas[{metas}]:infos{i.accountInfoCount}"

private def renderBodyOp : CpiUnsignedBodyOpV1 → String
  | .loadParamU64 t off => s!"loadParamU64:{t}@{off}"
  | .loadLiteralU64 t v => s!"loadLiteralU64:{t}:{encodeUInt64LowerHex16 v}"
  | .stateLoadU64 t li off => s!"stateLoadU64:{t}:local{li}@{off}"
  | .checkedAddU64 d l r => s!"checkedAddU64:{d}:{l}:{r}"
  | .stateStoreU64 li off src wm marker =>
      s!"stateStoreU64:local{li}@{off}:src{src}:marker{wm}:{encodeUInt64LowerHex16 marker}"
  | .siteChecks sid ops =>
      let parts := String.intercalate ";" (ops.map preflightOpKindNameV1).toList
      s!"siteChecks:{sid}:[{parts}]"
  | .invokeUnsigned inv => renderInvoke inv
  | .returnU64 t => s!"returnU64:{t}"
  | .returnNone => "returnNone"

private def renderMode : HandlerModeV1 → String
  | .initialize => "initialize"
  | .entry => "entry"
  | .view => "view"

private def renderHandler (h : CpiUnsignedHandlerIRV1) : String :=
  let entry := String.intercalate ";" (h.entryGlobalOps.map preflightOpKindNameV1).toList
  let body := String.intercalate ";" (h.bodyOps.map renderBodyOp).toList
  s!"handler:{h.handlerId}:{h.callableId}:{h.name}:{renderMode h.mode}:roles{h.localRoleCount}:probe{h.probeIxDataLen}:temps{h.tempCount}:entry[{entry}]:body[{body}]"

private def renderCandidate (c : SolanaCpiUnsignedIRCandidateV1) : CompileResult String := do
  let planDig ← mapExcept (renderDigest c.sourcePlanDigest) "sourcePlanDigest"
  let pfDig ← mapExcept (renderDigest c.sourcePreflightIrDigest) "sourcePreflightIrDigest"
  let profileDig ← mapExcept (renderDigest c.profileDigest) "profileDigest"
  let catalogDig ← mapExcept (renderDigest c.catalogDigest) "catalogDigest"
  let handlers := String.intercalate "\n" (c.handlers.map renderHandler).toList
  pure <|
    s!"schema={c.schema}\n" ++
    s!"sourcePlanDigest={planDig}\n" ++
    s!"sourcePreflightIrDigest={pfDig}\n" ++
    s!"profileId={c.profileId}\n" ++
    s!"profileDigest={profileDig}\n" ++
    s!"catalogDigest={catalogDig}\n" ++
    s!"maxOuterRoles={c.maxOuterRoles}\n" ++
    s!"maxFrameBytes={c.maxFrameBytes}\n" ++
    handlers

/-- Sole mint of the #119 unsigned execution IR from resolved preflight authority. -/
def resolveSolanaCpiUnsignedIRV1
    (authority : ResolvedSolanaCpiPreflightIRV1) :
    CompileResult ResolvedSolanaCpiUnsignedIRV1 := do
  let planAuth := ResolvedSolanaCpiPreflightIRV1.authorityOf authority
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf planAuth) do
    uFail "unsigned CPI IR requires activationDenied preflight carrier"
  let candidate ← projectUnsignedCandidate authority
  unless candidate.schema == unsignedIrSchemaV1 do
    uFail s!"schema must be {unsignedIrSchemaV1}"
  unless candidate.maxFrameBytes == 4096 do
    uFail "maxFrameBytes must be 4096"
  for h in candidate.handlers do
    unless h.localRoleCount ≤ maxOuterRolesV1 do
      uFail s!"handler {h.handlerId} localRoleCount exceeds cap"
    -- Static assembly shape: every siteChecks must immediately precede invoke.
    let ops := h.bodyOps
    for i in [0:ops.size] do
      match ops[i]! with
      | .siteChecks sid _ =>
          let j := i + 1
          unless j < ops.size do
            uFail s!"siteChecks {sid} is not followed by invokeUnsigned"
          match ops[j]! with
          | .invokeUnsigned inv =>
              unless inv.siteId == sid do
                uFail s!"siteChecks {sid} mismatched invoke site {inv.siteId}"
          | _ =>
              uFail s!"siteChecks {sid} must be immediately followed by invokeUnsigned"
      | .invokeUnsigned inv =>
          unless inv.principalBindings.size == 1 && inv.metas.size == 1 do
            uFail s!"invokeUnsigned site {inv.siteId} requires one Principal binding and one meta"
          let principal ← getArr inv.principalBindings 0 "invoke principalBindings"
          let metaBinding ← getArr inv.metas 0 "invoke metas"
          unless principal.argIndex == 0 && principal.roleId == metaBinding.roleId &&
              principal.localIndex == metaBinding.localIndex do
            uFail s!"invokeUnsigned site {inv.siteId} Principal/meta join diverged"
          if i == 0 then
            uFail s!"invokeUnsigned site {inv.siteId} missing preceding siteChecks"
          else
            match ops[i - 1]! with
            | .siteChecks sid _ =>
                unless sid == inv.siteId do
                  uFail s!"invokeUnsigned site {inv.siteId} not preceded by matching siteChecks"
            | _ =>
                uFail s!"invokeUnsigned site {inv.siteId} missing immediately preceding siteChecks"
      | _ => pure ()
  let text ← renderCandidate candidate
  let canonicalBytes := text.toUTF8
  let digest ← mapExcept
    (domainSeparatedSha256 unsignedIrDigestDomainV1 canonicalBytes)
    "unsigned-ir digest"
  pure ⟨authority, candidate, canonicalBytes, digest⟩

/-- Max CPI scratch bytes for a handler (ix data + metas + instruction + infos). -/
def unsignedCpiScratchBytesV1
    (localRoleCount : Nat) (maxMetas : Nat) (maxDataLen : Nat) : Nat :=
  let dataPad := ((maxDataLen + 15) / 16) * 16  -- 16B-aligned scratch slot
  let dataSlot := Nat.max 16 dataPad
  let metas := maxMetas * 16
  let instr := 40
  let infos := localRoleCount * 56
  dataSlot + metas + instr + infos

/-- Max site shape across handlers (for frame layout). -/
def unsignedMaxSiteScratchV1 (c : SolanaCpiUnsignedIRCandidateV1) : Nat :=
  Id.run do
    let mut maxB : Nat := 0
    for h in c.handlers do
      for op in h.bodyOps do
        match op with
        | .invokeUnsigned inv =>
            let b := unsignedCpiScratchBytesV1 inv.accountInfoCount inv.metas.size inv.dataLen
            if b > maxB then maxB := b
        | _ => pure ()
    pure maxB

end ProofForgeV2.Targets.Solana.CpiV1

/-
  ProofForgeV2.Targets.Solana.CpiPreflightIRV1 — #118 concrete preflight IR.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1` (shared with Contract/Plan/IR).

  Projects a validated CPI Plan/IR into an ordered program of **concrete
  executable checks only** (plus static account-parameter binding rows for
  inspection). Catalog execution-class owners are resolved into exact loader
  owner bytes at derivation. Site predicates are reified in site source order
  after global role checks. Unsupported PDA/signer-group/provisioning/Token/ATA
  surfaces fail closed at IR derivation (structurally valid Plan may still
  exist for inspection, but is preflight-emission-ineligible).

  Two carriers:
  * `ValidatedSolanaCpiPreflightIRV1` — public structural projection from any
    `ValidatedSolanaCpiPlanV1` (inspection / mutation tests).
  * `ResolvedSolanaCpiPreflightIRV1` — private authority whose sole mint
    consumes `SolanaCpiPreflightPlanV1`. The SBPF emitter accepts only this.

  No product materializer, OutputFile, invoke, or CPI boundary.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common

/-! ## Schema / digest domain -/

def preflightIrSchemaV1 : String := "proof-forge.solana.cpi-preflight-ir.v1"
def preflightIrDigestDomainV1 : String := "pf.solana.cpi-preflight-ir.v1"

/-! ## Static account-parameter binding (not a runtime equality check)

    Principal parameters are synthesized from role keys at the product ABI
    boundary. These rows document `(callableId, paramOrdinal, roleId, localIndex)`
    for inspection/handler binding tables only. -/

structure CpiPreflightAccountParamBindingV1 where
  callableId : Nat
  paramOrdinal : Nat
  roleId : Nat
  localIndex : Nat
  deriving BEq, Repr

/-! ## Concrete preflight operations (per handler)

    Only checks the emitter can lower to real SBPF instructions. Generic
    owner/data/init/provisioning policy DTOs are deliberately absent. -/

inductive CpiPreflightOpV1 where
  /-- Exact outer role count for this handler. -/
  | expectLocalRoleCount (count : Nat)
  /-- ABIv1 virtual-walk slot (marker/odl/bool/rent enforced by shared walker). -/
  | abiVirtualWalk (localIndex : Nat)
  /-- Account marker byte (also enforced by shared walker). -/
  | checkMarker (localIndex : Nat) (expected : Nat)
  /-- original_data_len wire value (also enforced by shared walker). -/
  | checkOriginalDataLen (localIndex : Nat) (expected : Nat)
  /-- Packed signer/writable/executable flag bytes ∈ {0,1}. -/
  | checkBoolFlagsInRange (localIndex : Nat)
  /-- rent_epoch == u64::MAX (also enforced by shared walker). -/
  | checkRentEpochMax (localIndex : Nat)
  /-- SIMD-0449 pointer-table entry (also enforced by shared walker). -/
  | checkPointerTableEntry (localIndex : Nat)
  /-- Pairwise-distinct 32-byte keys across local roles. -/
  | checkPairwiseDistinctKeys (localCount : Nat)
  /-- Exact 32-byte account key. -/
  | checkExactKey (localIndex : Nat) (rawKey : SolanaPubkeyV1)
  /-- Account owner == current program id (from input tail). -/
  | checkOwnerCurrentProgram (localIndex : Nat)
  /-- Account owner == exact 32-byte pubkey (fixed program or loader owner). -/
  | checkOwnerExact (localIndex : Nat) (rawOwner : SolanaPubkeyV1)
  /-- executable flag must be 1. -/
  | checkExecutableRequired (localIndex : Nat)
  /-- executable flag must be 0. -/
  | checkExecutableForbidden (localIndex : Nat)
  /-- Account data_len exact. -/
  | checkExactDataLen (localIndex : Nat) (bytes : Nat)
  /-- Optional exact lamports. -/
  | checkExactLamports (localIndex : Nat) (lamports : Nat)
  /-- State header u64 @ offset 0 must be zero (initializer). -/
  | checkStateHeaderZero (localIndex : Nat)
  /-- State header u64 @ offset 0 must equal initializedMarker (entry/view). -/
  | checkStateHeaderMarker (localIndex : Nat) (marker : UInt64)
  /-- Effective is_signer privilege. -/
  | checkEffectiveSigner (localIndex : Nat) (required : Bool)
  /-- Effective is_writable privilege. -/
  | checkEffectiveWritable (localIndex : Nat) (required : Bool)
  deriving BEq, Repr

/-- One handler's complete preflight program (local handles only). -/
structure CpiPreflightHandlerIRV1 where
  handlerId : Nat
  callableId : Nat
  name : String
  mode : HandlerModeV1
  localRoleCount : Nat
  /-- Exact local ABIv1 order: `localIndex == position` dense from 0. -/
  localRoleOrder : Array CpiIRRoleHandleV1
  /-- Static Principal-parameter binding rows (inspection only). -/
  accountParameterBindings : Array CpiPreflightAccountParamBindingV1
  ops : Array CpiPreflightOpV1
  deriving BEq, Repr

/-! ## Public candidate + private structural / resolved carriers -/

/-- Public inspection candidate (not yet validated). -/
structure SolanaCpiPreflightIRCandidateV1 where
  schema : String
  sourcePlanDigest : Digest
  sourceIrDigest : Digest
  profileId : String
  profileDigest : Digest
  catalogDigest : Digest
  abiLayout : LoaderV3AbiLayoutV1
  maxOuterRoles : Nat
  handlers : Array CpiPreflightHandlerIRV1
  deriving BEq

/-- Validated structural preflight IR (inspection / mutation tests).
    Constructor private; never mints OutputFile / product artifacts.
    **Not** emitter input — use `ResolvedSolanaCpiPreflightIRV1`. -/
structure ValidatedSolanaCpiPreflightIRV1 where
  private mk ::
  plan : ValidatedSolanaCpiPlanV1
  ir : ValidatedSolanaCpiIRV1
  candidate : SolanaCpiPreflightIRCandidateV1
  canonicalBytes : ByteArray
  digest : Digest

namespace ValidatedSolanaCpiPreflightIRV1

def planOf (v : ValidatedSolanaCpiPreflightIRV1) : ValidatedSolanaCpiPlanV1 :=
  v.plan
def irOf (v : ValidatedSolanaCpiPreflightIRV1) : ValidatedSolanaCpiIRV1 :=
  v.ir
def candidateOf (v : ValidatedSolanaCpiPreflightIRV1) : SolanaCpiPreflightIRCandidateV1 :=
  v.candidate
def canonicalBytesOf (v : ValidatedSolanaCpiPreflightIRV1) : ByteArray :=
  v.canonicalBytes
def digestOf (v : ValidatedSolanaCpiPreflightIRV1) : Digest :=
  v.digest

end ValidatedSolanaCpiPreflightIRV1

/-- Private resolved preflight IR: sole mint consumes `SolanaCpiPreflightPlanV1`.
    This is the only carrier the SBPF emitter accepts. -/
structure ResolvedSolanaCpiPreflightIRV1 where
  private mk ::
  authority : SolanaCpiPreflightPlanV1
  validated : ValidatedSolanaCpiPreflightIRV1

namespace ResolvedSolanaCpiPreflightIRV1

def authorityOf (r : ResolvedSolanaCpiPreflightIRV1) : SolanaCpiPreflightPlanV1 :=
  r.authority
def validatedOf (r : ResolvedSolanaCpiPreflightIRV1) : ValidatedSolanaCpiPreflightIRV1 :=
  r.validated
def candidateOf (r : ResolvedSolanaCpiPreflightIRV1) : SolanaCpiPreflightIRCandidateV1 :=
  r.validated.candidate
def digestOf (r : ResolvedSolanaCpiPreflightIRV1) : Digest :=
  r.validated.digest
def planOf (r : ResolvedSolanaCpiPreflightIRV1) : ValidatedSolanaCpiPlanV1 :=
  r.validated.plan

end ResolvedSolanaCpiPreflightIRV1

/-! ## Internal helpers -/

private def pfFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def mapExcept (e : Except String α) (ctx : String) : CompileResult α :=
  match e with
  | .ok v => pure v
  | .error msg => pfFail s!"{ctx}: {msg}"

private def digestsEqual (left right : Digest) : Bool :=
  left.algorithm == right.algorithm && left.bytes == right.bytes

private def lowerHexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

private def encodeLowerHex (bytes : ByteArray) : String :=
  bytes.foldl (fun result byte =>
    let value := byte.toNat
    (result.push (lowerHexDigit (value / 16))).push (lowerHexDigit (value % 16))) ""

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

private def effectiveSigner (h : CpiIRRoleHandleV1) : Bool :=
  h.directSignerContribution || h.outerSigner

private def effectiveWritable (h : CpiIRRoleHandleV1) : Bool :=
  h.directWritableContribution || h.outerWritable

private def findStateSchema?
    (schemas : Array StateSchemaV1) (schemaId : Nat) : Option StateSchemaV1 :=
  schemas.find? (fun s => s.schemaId == schemaId)

/-- Resolve owner policy into a concrete owner check (or none / reject).
    `catalogPackageId?` is the fixed-program package when the role/predicate
    is a catalog callee or fixed program; required for catalogExecutionClass. -/
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
          pfFail s!"owner fixedProgram package '{packageId}' missing from catalog"
  | .catalogExecutionClass =>
      let packageId ← match catalogPackageId? with
        | some id => pure id
        | none =>
            pfFail "catalogExecutionClass owner requires a fixed-program package context"
      match findCalleePackage? packageId with
      | some package =>
          pure #[.checkOwnerExact localIndex
            (executionClassOwnerPubkeyV1 package.executionClass)]
      | none =>
          pfFail s!"catalogExecutionClass package '{packageId}' missing from catalog"
  | .any =>
      pure #[]
  | .closedPackages _ =>
      pfFail
        "preflight IR rejects closedPackages owner (Token/ATA surface deferred)"

private def resolveExecutableOps
    (localIndex : Nat) (exec : ExecutablePolicy) : Array CpiPreflightOpV1 :=
  match exec with
  | .required => #[.checkExecutableRequired localIndex]
  | .forbidden => #[.checkExecutableForbidden localIndex]

/-- Resolve data + initialization into concrete length/header/lamports ops.
    Compile-time-only classifications produce zero ops. Unsupported surfaces
    fail closed. -/
private def resolveDataAndInitOps
    (localIndex : Nat)
    (mode : HandlerModeV1)
    (keyPolicy : RoleKeyPolicyV1)
    (data : DataPolicy)
    (init : InitializationPolicy)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult (Array CpiPreflightOpV1) := do
  -- Reject unsupported initialization alternatives early.
  match init with
  | .uninitialized =>
      pfFail "preflight IR rejects uninitialized initialization (provisioning deferred)"
  | .canonicalPda =>
      pfFail "preflight IR rejects canonicalPda initialization (PDA deferred)"
  | .uninitializedOrIdempotentlyInitialized =>
      pfFail
        "preflight IR rejects uninitializedOrIdempotentlyInitialized (ATA deferred)"
  | .initializerUninitializedOtherwiseInitialized
  | .initialized | .existing | .any | .catalogPackageAdmitted =>
      pure ()

  let mut ops : Array CpiPreflightOpV1 := #[]
  match data with
  | .notRead => pure ()
  | .catalogProgram => pure ()
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
        | _ =>
            pfFail "proofForgeState data requires RoleKeyPolicyV1.state"
      let schema ← match findStateSchema? stateSchemas schemaId with
        | some s => pure s
        | none => pfFail s!"proofForgeState schemaId {schemaId} missing"
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
      | .existing | .any | .catalogPackageAdmitted =>
          pure ()
      | _ =>
          -- Unreachable: rejected above.
          pure ()
  | .classicTokenAccount .. =>
      pfFail "preflight IR rejects classicTokenAccount data (Token deferred)"
  | .classicTokenMint .. =>
      pfFail "preflight IR rejects classicTokenMint data (Token deferred)"
  | .ataAccount .. =>
      pfFail "preflight IR rejects ataAccount data (ATA deferred)"

  -- Non-state initialized classification with non-state data adds no header op
  -- beyond what data already emitted (exactCounter length is enough).
  pure ops

private def resolveProvisioning
    (prov : ProvisioningPolicy) : CompileResult Unit := do
  match prov with
  | .none | .mustExist => pure ()
  | .systemCreateAccount =>
      pfFail "preflight IR rejects systemCreateAccount provisioning"
  | .ataCreateIdempotent =>
      pfFail "preflight IR rejects ataCreateIdempotent provisioning"

/-- Package id context for catalogExecutionClass / fixed-program owner on a handle. -/
private def packageContextOfKeyPolicy : RoleKeyPolicyV1 → Option String
  | .fixedProgram packageId => some packageId
  | .state _ | .accountParameter .. | .vaultPda | .handlerCaller
  | .vaultAta | .dstAta => none

/-- Project one AccountConstraint into concrete ops (role or site predicate). -/
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

/-! ## Sole expected projection -/

private def projectHandlerOps
    (abi : LoaderV3AbiLayoutV1)
    (mode : HandlerModeV1)
    (handles : Array CpiIRRoleHandleV1)
    (sites : Array CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult
      (Array CpiPreflightAccountParamBindingV1 × Array CpiPreflightOpV1) := do
  let n := handles.size
  unless n ≤ maxOuterRolesV1 do
    pfFail s!"handler local role count {n} exceeds maxOuterRoles {maxOuterRolesV1}"

  -- Site-level surface gates (#118 supported APIs only).
  for site in sites do
    match site.pda with
    | .none => pure ()
    | .signer .. | .addressCheckOnly .. | .vaultPdaSigner _ =>
        pfFail
          s!"preflight IR rejects non-none PDA use at site {site.siteId} (PDA deferred)"
    unless site.signerGroups.isEmpty do
      pfFail
        s!"preflight IR rejects non-empty signerGroups at site {site.siteId}"
    unless site.preflight.isEmpty do
      pfFail
        s!"preflight IR rejects site preflight arg predicates at site {site.siteId}"

  let mut bindings : Array CpiPreflightAccountParamBindingV1 := #[]
  let mut ops : Array CpiPreflightOpV1 := #[]
  ops := ops.push (.expectLocalRoleCount n)

  -- Full ABIv1 virtual walk + marker / originalDataLen / bool / rent per local.
  -- Shared walker executes these; ops document the contract for inspection.
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

  -- Per-role key + constraint + privileges.
  for handle in handles do
    let i := handle.localIndex
    match handle.keyPolicy with
    | .fixedProgram packageId =>
        match findCalleePackage? packageId with
        | some package =>
            ops := ops.push (.checkExactKey i package.programId)
        | none =>
            pfFail s!"fixedProgram package '{packageId}' missing from frozen catalog"
    | .accountParameter callableId paramOrdinal =>
        bindings := bindings.push {
          callableId
          paramOrdinal
          roleId := handle.roleId
          localIndex := i
        }
    | .state _schemaId | .vaultPda | .handlerCaller | .vaultAta | .dstAta =>
        pure ()
    let constraintOps ← projectConstraintOps i mode handle.keyPolicy
      handle.constraint stateSchemas
    ops := ops ++ constraintOps
    ops := ops.push (.checkEffectiveSigner i (effectiveSigner handle))
    ops := ops.push (.checkEffectiveWritable i (effectiveWritable handle))

  -- Site predicates reified in site source order after global role checks.
  for site in sites do
    for pred in site.sitePredicates do
      let localHandleIndex ← match handles.findIdx? (fun h => h.roleId == pred.roleId) with
        | some idx => pure idx
        | none =>
            pfFail s!"site predicate roleId {pred.roleId} missing from handler locals"
      let some handle := handles[localHandleIndex]? |
        pfFail "site predicate local handle missing"
      -- Callee predicates use the site package for catalogExecutionClass.
      let packageOverride : Option String :=
        match pred.source with
        | .callee => some site.packageId
        | .metaIndex _ | .outerOnlyIndex _ => none
      let predOps ← projectConstraintOps localHandleIndex mode handle.keyPolicy
        pred.constraint stateSchemas packageOverride
      ops := ops ++ predOps

  pure (bindings, ops)

private def projectHandler
    (abi : LoaderV3AbiLayoutV1)
    (handler : HandlerPlanV1)
    (allHandles : Array CpiIRRoleHandleV1)
    (allSites : Array CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult CpiPreflightHandlerIRV1 := do
  let handles := allHandles.filter (fun h => h.handlerId == handler.handlerId)
  unless handles.size == handler.accountUses.size do
    pfFail "handler local handle count must equal Plan accountUses size"
  for i in [0:handles.size] do
    match handles[i]?, handler.accountUses[i]? with
    | some h, some use =>
        unless h.localIndex == i && h.localIndex == use.position &&
            h.roleId == use.roleId do
          pfFail s!"handler {handler.handlerId} local order mismatch at {i}"
    | _, _ => pfFail "handler local order projection incomplete"
  let sites := allSites.filter (fun s => s.handlerId == handler.handlerId)
  unless sites.map (·.siteId) == handler.cpiSiteIds do
    pfFail s!"handler {handler.handlerId} site order must equal Plan cpiSiteIds"
  let (bindings, ops) ← projectHandlerOps abi handler.mode handles sites stateSchemas
  pure {
    handlerId := handler.handlerId
    callableId := handler.callableId
    name := handler.name
    mode := handler.mode
    localRoleCount := handles.size
    localRoleOrder := handles
    accountParameterBindings := bindings
    ops
  }

private def projectExpectedPreflightIR
    (plan : ValidatedSolanaCpiPlanV1)
    (ir : ValidatedSolanaCpiIRV1) :
    CompileResult SolanaCpiPreflightIRCandidateV1 := do
  unless digestsEqual ir.candidate.sourcePlanDigest plan.digest do
    pfFail "validated IR sourcePlanDigest must equal plan digest"
  let abi := ir.candidate.abiLayout
  unless abi == frozenLoaderV3AbiLayoutV1 do
    pfFail "preflight requires frozen Loader V3 ABIv1 layout from validated IR"
  let mut handlers : Array CpiPreflightHandlerIRV1 := #[]
  for h in plan.candidate.handlers do
    let projected ← projectHandler abi h ir.candidate.roleHandles
      ir.candidate.sites plan.candidate.stateSchemas
    handlers := handlers.push projected
  pure {
    schema := preflightIrSchemaV1
    sourcePlanDigest := plan.digest
    sourceIrDigest := ir.digest
    profileId := plan.candidate.profileId
    profileDigest := plan.candidate.profileDigest
    catalogDigest := plan.candidate.calleeCatalogDigest
    abiLayout := abi
    maxOuterRoles := maxOuterRolesV1
    handlers
  }

/-! ## Canonical render (deterministic; digest authority) -/

private def renderMode : HandlerModeV1 → String
  | .initialize => "initialize"
  | .entry => "entry"
  | .view => "view"

private def renderOp : CpiPreflightOpV1 → String
  | .expectLocalRoleCount count => s!"expectLocalRoleCount:{count}"
  | .abiVirtualWalk i => s!"abiVirtualWalk:{i}"
  | .checkMarker i expected => s!"checkMarker:{i}:{expected}"
  | .checkOriginalDataLen i expected => s!"checkOriginalDataLen:{i}:{expected}"
  | .checkBoolFlagsInRange i => s!"checkBoolFlagsInRange:{i}"
  | .checkRentEpochMax i => s!"checkRentEpochMax:{i}"
  | .checkPointerTableEntry i => s!"checkPointerTableEntry:{i}"
  | .checkPairwiseDistinctKeys n => s!"checkPairwiseDistinctKeys:{n}"
  | .checkExactKey i rawKey =>
      s!"checkExactKey:{i}:{encodeLowerHex (SolanaPubkeyV1.toBytes rawKey)}"
  | .checkOwnerCurrentProgram i => s!"checkOwnerCurrentProgram:{i}"
  | .checkOwnerExact i rawOwner =>
      s!"checkOwnerExact:{i}:{encodeLowerHex (SolanaPubkeyV1.toBytes rawOwner)}"
  | .checkExecutableRequired i => s!"checkExecutableRequired:{i}"
  | .checkExecutableForbidden i => s!"checkExecutableForbidden:{i}"
  | .checkExactDataLen i bytes => s!"checkExactDataLen:{i}:{bytes}"
  | .checkExactLamports i lamports => s!"checkExactLamports:{i}:{lamports}"
  | .checkStateHeaderZero i => s!"checkStateHeaderZero:{i}"
  | .checkStateHeaderMarker i marker =>
      s!"checkStateHeaderMarker:{i}:{encodeUInt64LowerHex16 marker}"
  | .checkEffectiveSigner i required => s!"checkEffectiveSigner:{i}:{required}"
  | .checkEffectiveWritable i required => s!"checkEffectiveWritable:{i}:{required}"

private def renderBinding (b : CpiPreflightAccountParamBindingV1) : String :=
  s!"{b.callableId}:{b.paramOrdinal}:{b.roleId}:{b.localIndex}"

private def renderHandle (h : CpiIRRoleHandleV1) : String :=
  s!"{h.handlerId}:{h.localIndex}:{h.roleId}:{h.name}:{effectiveSigner h}:{effectiveWritable h}"

private def renderHandler (h : CpiPreflightHandlerIRV1) : String :=
  let order := String.intercalate "," (h.localRoleOrder.map renderHandle).toList
  let binds := String.intercalate "," (h.accountParameterBindings.map renderBinding).toList
  let ops := String.intercalate ";" (h.ops.map renderOp).toList
  s!"handler:{h.handlerId}:{h.callableId}:{h.name}:{renderMode h.mode}:{h.localRoleCount}:[{order}]:binds[{binds}]:[{ops}]"

private def renderCandidate (c : SolanaCpiPreflightIRCandidateV1) : CompileResult String := do
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
    s!"abi.schema={c.abiLayout.schema}\n" ++
    s!"abi.marker={c.abiLayout.marker}\n" ++
    s!"abi.fullPrefixBytes={c.abiLayout.fullPrefixBytes}\n" ++
    s!"abi.originalDataLenEntryValue={c.abiLayout.originalDataLenEntryValue}\n" ++
    s!"abi.maxPermittedDataIncrease={c.abiLayout.maxPermittedDataIncrease}\n" ++
    s!"maxOuterRoles={c.maxOuterRoles}\n" ++
    handlers

private def encodeCandidateCanonical
    (c : SolanaCpiPreflightIRCandidateV1) : CompileResult ByteArray := do
  let text ← renderCandidate c
  pure text.toUTF8

/-! ## Structural validate + derive -/

/-- Sole structural preflight IR validation against Plan/IR projection. -/
def validateSolanaCpiPreflightIRV1
    (plan : ValidatedSolanaCpiPlanV1)
    (ir : ValidatedSolanaCpiIRV1)
    (candidate : SolanaCpiPreflightIRCandidateV1) :
    CompileResult ValidatedSolanaCpiPreflightIRV1 := do
  let expected ← projectExpectedPreflightIR plan ir
  unless candidate.schema == expected.schema do
    pfFail s!"schema must be exact {preflightIrSchemaV1}"
  unless digestsEqual candidate.sourcePlanDigest expected.sourcePlanDigest do
    pfFail "sourcePlanDigest must equal validated plan digest"
  unless digestsEqual candidate.sourceIrDigest expected.sourceIrDigest do
    pfFail "sourceIrDigest must equal validated IR digest"
  unless candidate.profileId == expected.profileId do
    pfFail "profileId must equal validated plan profileId"
  unless digestsEqual candidate.profileDigest expected.profileDigest do
    pfFail "profileDigest must equal validated plan profileDigest"
  unless digestsEqual candidate.catalogDigest expected.catalogDigest do
    pfFail "catalogDigest must equal validated plan calleeCatalogDigest"
  unless candidate.abiLayout == expected.abiLayout do
    pfFail "abiLayout must equal frozen Loader V3 ABIv1 layout"
  unless candidate.maxOuterRoles == expected.maxOuterRoles do
    pfFail s!"maxOuterRoles must be exact {maxOuterRolesV1}"
  unless candidate.handlers == expected.handlers do
    pfFail "handlers must equal sole plan/IR concrete preflight projection"
  unless candidate == expected do
    pfFail "candidate must equal sole expected preflight IR projection"
  for h in candidate.handlers do
    unless h.localRoleCount ≤ maxOuterRolesV1 do
      pfFail s!"handler {h.handlerId} localRoleCount exceeds maxOuterRoles"
    unless h.localRoleCount == h.localRoleOrder.size do
      pfFail s!"handler {h.handlerId} localRoleCount/order size mismatch"
  let canonicalBytes ← encodeCandidateCanonical candidate
  let digest ← mapExcept
    (domainSeparatedSha256 preflightIrDigestDomainV1 canonicalBytes)
    "preflight-ir digest"
  pure ⟨plan, ir, candidate, canonicalBytes, digest⟩

/-- Structural mint: project Plan→IR then concrete preflight, then validate.
    Inspection only — **not** emitter authority. -/
def deriveSolanaCpiPreflightIRV1
    (plan : ValidatedSolanaCpiPlanV1) :
    CompileResult ValidatedSolanaCpiPreflightIRV1 := do
  let ir ← deriveSolanaCpiIRV1 plan
  let expected ← projectExpectedPreflightIR plan ir
  validateSolanaCpiPreflightIRV1 plan ir expected

/-- Structural mint from an already-validated CPI IR carrier. -/
def deriveSolanaCpiPreflightIRFromValidatedIRV1
    (ir : ValidatedSolanaCpiIRV1) :
    CompileResult ValidatedSolanaCpiPreflightIRV1 := do
  let expected ← projectExpectedPreflightIR ir.plan ir
  validateSolanaCpiPreflightIRV1 ir.plan ir expected

/-- Sole resolved preflight IR mint. Consumes the #118 authority carrier
    `SolanaCpiPreflightPlanV1` (Semantic-derived Plan under exact capability).
    This is the only path that can feed the SBPF emitter. -/
def resolveSolanaCpiPreflightIRV1
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult ResolvedSolanaCpiPreflightIRV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    pfFail "resolved preflight IR requires activationDenied authority carrier"
  let plan := SolanaCpiPreflightPlanV1.planOf authority
  let validated ← deriveSolanaCpiPreflightIRV1 plan
  pure ⟨authority, validated⟩

/-- Op kind name for tests / inspection (stable strings). -/
def preflightOpKindNameV1 : CpiPreflightOpV1 → String
  | .expectLocalRoleCount .. => "expectLocalRoleCount"
  | .abiVirtualWalk .. => "abiVirtualWalk"
  | .checkMarker .. => "checkMarker"
  | .checkOriginalDataLen .. => "checkOriginalDataLen"
  | .checkBoolFlagsInRange .. => "checkBoolFlagsInRange"
  | .checkRentEpochMax .. => "checkRentEpochMax"
  | .checkPointerTableEntry .. => "checkPointerTableEntry"
  | .checkPairwiseDistinctKeys .. => "checkPairwiseDistinctKeys"
  | .checkExactKey .. => "checkExactKey"
  | .checkOwnerCurrentProgram .. => "checkOwnerCurrentProgram"
  | .checkOwnerExact .. => "checkOwnerExact"
  | .checkExecutableRequired .. => "checkExecutableRequired"
  | .checkExecutableForbidden .. => "checkExecutableForbidden"
  | .checkExactDataLen .. => "checkExactDataLen"
  | .checkExactLamports .. => "checkExactLamports"
  | .checkStateHeaderZero .. => "checkStateHeaderZero"
  | .checkStateHeaderMarker .. => "checkStateHeaderMarker"
  | .checkEffectiveSigner .. => "checkEffectiveSigner"
  | .checkEffectiveWritable .. => "checkEffectiveWritable"

end ProofForgeV2.Targets.Solana.CpiV1

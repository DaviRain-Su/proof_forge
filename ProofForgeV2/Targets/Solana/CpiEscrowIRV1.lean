/-
  ProofForgeV2.Targets.Solana.CpiEscrowIRV1 — #124/#125 composite CPI IR.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Shared composite core admits the five product APIs:
  * `solana.system.transfer` — unsigned native System transfer (12B);
  * `solana.system.createPdaAccount` — PDA vault provisioning;
  * `solana.token.transferChecked` — deposit (external authority);
  * `solana.token.transferCheckedPda` — authorized release / refund-cancel;
  * `solana.ata.createIdempotent` — optional vault ATA only via pinned contract.

  Two private wrappers (no conversion between them):
  * `ResolvedSolanaCpiEscrowIRV1` — #124 preactivation; sole mint
    `resolveSolanaCpiEscrowIRV1` from `SolanaCpiPreflightPlanV1`; packages
    remain admitted=false; activationDenied; fixed caller id all-0x59.
  * `ResolvedSolanaCpiProductIRV1` — #125 product; sole mint
    `resolveSolanaCpiProductIRV1` from `SolanaCpiProductPlanV1`; no
    preactivation banner/fixed caller id; not mintable from public Plan/IR.

  Public structural Plan/IR cannot mint either carrier. No OutputFile here.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiProductCapabilityV1
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

def escrowIrSchemaV1 : String := "proof-forge.solana.cpi-escrow-ir.v1"
def escrowIrDigestDomainV1 : String := "pf.solana.cpi-escrow-ir.v1"

/-- Fixed test-preactivation caller program id for #124 escrow lane (runtime pin).
    Assembly reads the real ABIv1 program id at SLOT_PROGRAM_ID; Mollusk tests
    load the ELF under this exact all-0x59 key. -/
def escrowCallerProgramIdBytesV1 : Array UInt8 :=
  Array.replicate 32 (UInt8.ofNat 0x59)

/-- UInt64 value sources for amount / seedTag. -/
inductive CpiEscrowU64SourceV1 where
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  | literal (value : UInt64)
  deriving BEq, Repr, Inhabited

/-- UInt8 value sources for decimals / bump (bump literal 0 rejected at IR mint). -/
inductive CpiEscrowU8SourceV1 where
  | param (paramOrdinal : Nat) (ixDataOffset : Nat)
  | literal (value : UInt8)
  deriving BEq, Repr, Inhabited

/-- One CPI meta binding to a handler-local role. -/
structure CpiEscrowMetaV1 where
  metaIndex : Nat
  roleId : Nat
  localIndex : Nat
  cpiWritable : Bool
  cpiSigner : Bool
  signerGroupId : Option Nat
  deriving BEq, Repr, Inhabited

/-- Exact Semantic Principal → callable parameter → role → dense local join. -/
structure CpiEscrowPrincipalBindingV1 where
  argIndex : Nat
  semanticValueId : Nat
  paramOrdinal : Nat
  roleId : Nat
  localIndex : Nat
  deriving BEq, Repr, Inhabited

/-- Outer-only account binding (seedAuthority for transferCheckedPda). -/
structure CpiEscrowOuterOnlyBindingV1 where
  outerOnlyIndex : Nat
  roleId : Nat
  localIndex : Nat
  outerSigner : Bool
  outerWritable : Bool
  deriving BEq, Repr, Inhabited

/-- Closed site-arg preflight (Token/ATA empty; System create carries space≤4096). -/
inductive CpiEscrowArgCheckV1 where
  | unusedPlaceholder
  | uint64AtMost (argName : String) (source : CpiEscrowU64SourceV1) (maxValue : Nat)
  deriving BEq, Repr, Inhabited

/-- Composite escrow/product API kind (frozen System/Token/ATA only).
    `#124` fixture uses createPdaAccount/Token/ATA; `#125` also admits
    system.transfer. Adding `.transfer` does not change render of other kinds. -/
inductive CpiEscrowKindV1 where
  | transfer
  | createPdaAccount
  | transferChecked
  | transferCheckedPda
  | createIdempotent
  /-- ADR-0029 B1: pf.assets.native.deposit — optional vault ensure + System
      transfer caller → vault (unsigned). -/
  | nativeDeposit
  /-- ADR-0029 B1: pf.assets.native.transfer — System transfer vault → dst
      with vault PDA invoke_signed. -/
  | nativeTransfer
  /-- ADR-0030 E1b: pf.assets.token.transfer — vault ATA → dst ATA via
      transferChecked with vault PDA authority; ATA idempotent ensure +
      transferCheckedPda. -/
  | pfAssetsTokenTransfer
  deriving BEq, Repr, Inhabited

/-- Site-local composite invoke. Family-specific Principal/scalar fields are Option
    and exact-joined by kind at IR mint / validate / emitter. -/
structure CpiEscrowInvokeV1 where
  siteId : Nat
  kind : CpiEscrowKindV1
  qn : String
  packageId : String
  programLocalIndex : Nat
  dataLen : Nat
  /-- Token transfer source; none for System/ATA. -/
  source : Option CpiEscrowPrincipalBindingV1
  /-- Token mint / ATA mint; none for System. -/
  mint : Option CpiEscrowPrincipalBindingV1
  /-- Token destination **or** system.transfer recipient; none for create/ATA. -/
  destination : Option CpiEscrowPrincipalBindingV1
  /-- transferChecked authority; none otherwise. -/
  authority : Option CpiEscrowPrincipalBindingV1
  /-- transferCheckedPda authorityPda OR createPda target; none otherwise. -/
  authorityPda : Option CpiEscrowPrincipalBindingV1
  /-- transferCheckedPda / createPda seedAuthority; none otherwise. -/
  seedAuthority : Option CpiEscrowPrincipalBindingV1
  /-- System transfer/create / ATA payer; none for Token-only. -/
  payer : Option CpiEscrowPrincipalBindingV1
  /-- createPdaAccount PDA target (alias of authorityPda when create); explicit. -/
  pda : Option CpiEscrowPrincipalBindingV1
  /-- ATA account principal. -/
  ata : Option CpiEscrowPrincipalBindingV1
  /-- ATA wallet principal. -/
  wallet : Option CpiEscrowPrincipalBindingV1
  seedTag : Option CpiEscrowU64SourceV1
  bump : Option CpiEscrowU8SourceV1
  amount : Option CpiEscrowU64SourceV1
  decimals : Option CpiEscrowU8SourceV1
  lamports : Option CpiEscrowU64SourceV1
  space : Option CpiEscrowU64SourceV1
  systemProgramLocalIndex : Option Nat
  tokenProgramLocalIndex : Option Nat
  metas : Array CpiEscrowMetaV1
  outerOnly : Array CpiEscrowOuterOnlyBindingV1
  signerGroupId : Option Nat
  pdaRule : Option String
  accountInfoCount : Nat
  deriving BEq, Repr

/-- Closed Token site-time predicate: generic preflight ops + exact SPL Token
    field joins. Field constructors carry dense localIndex (and value sources),
    never free-form strings — IR mint exact-joins against invoke Principal/
    decimals bindings. -/
inductive CpiEscrowSiteCheckV1 where
  | generic (op : CpiPreflightOpV1)
  /-- Token Account.state @ data[108] == 1 (Initialized; reject 0/2). -/
  | tokenAccountStateInitialized (localIndex : Nat)
  /-- Token Account.mint @ data[0..32] == mint role key. -/
  | tokenAccountMintEqualsRole (accountLocalIndex mintLocalIndex : Nat)
  /-- Token Account.owner @ data[32..64] == authority/authorityPda role key. -/
  | tokenAccountOwnerEqualsRole (accountLocalIndex ownerLocalIndex : Nat)
  /-- Token Account.delegate COption tag @ data[72..76] u32le == 0 (None). -/
  | tokenAccountDelegateNone (localIndex : Nat)
  /-- Mint.is_initialized @ data[45] == 1. -/
  | tokenMintInitialized (localIndex : Nat)
  /-- Mint.decimals @ data[44] == supplied decimals (param or literal). -/
  | tokenMintDecimalsEquals (localIndex : Nat) (decimals : CpiEscrowU8SourceV1)
  /-- Canonical ATA address seeds wallet/classic-Token/mint under ATA program. -/
  | ataAddressCanonical
      (ataLocal walletLocal tokenProgramLocal mintLocal ataProgramLocal : Nat)
  /-- Closed ATA pre-state: fresh System zero OR joined Token ATA. -/
  | ataAccountPrestateClosed
      (ataLocal walletLocal mintLocal systemProgramLocal tokenProgramLocal : Nat)
  deriving BEq, Repr

/-- Ordered body operations after handler-entry global preflight. -/
inductive CpiEscrowBodyOpV1 where
  | loadParamU64 (tempId : Nat) (ixDataOffset : Nat)
  | loadParamU8 (tempId : Nat) (ixDataOffset : Nat)
  | loadLiteralU64 (tempId : Nat) (value : UInt64)
  | loadLiteralU8 (tempId : Nat) (value : UInt8)
  | stateLoadU64 (tempId : Nat) (stateLocalIndex : Nat) (byteOffset : Nat)
  | checkedAddU64 (dstTemp lhsTemp rhsTemp : Nat)
  | stateStoreU64 (stateLocalIndex : Nat) (byteOffset : Nat) (srcTemp : Nat)
    (writeInitializedMarker : Bool) (initializedMarker : UInt64)
  /-- Site-arg preflight (empty for Token APIs; preserves siteArgChecks→siteChecks→invoke). -/
  | siteArgChecks (siteId : Nat) (checks : Array CpiEscrowArgCheckV1)
  /-- Site-time account predicates (must run immediately before invoke). -/
  | siteChecks (siteId : Nat) (ops : Array CpiEscrowSiteCheckV1)
  | invokeEscrow (invoke : CpiEscrowInvokeV1)
  /-- ADR-0030 E2-3: env-read (vault balance observation). Read-only,
      value-producing (allocates a temp). Native reads vault PDA lamports;
      token reads vault ATA token amount LE at data[64..72]. -/
  | envReadVaultBalance
      (tempId : Nat) (kind : EnvReadKindV1)
      (vaultLocal : Nat)
      (vaultAtaLocal mintLocal systemLocal tokenLocal ataLocal : Nat)
  | returnU64 (srcTemp : Nat)
  | returnNone
  deriving BEq, Repr, Inhabited

structure CpiEscrowHandlerIRV1 where
  handlerId : Nat
  callableId : Nat
  name : String
  mode : HandlerModeV1
  localRoleCount : Nat
  localRoleOrder : Array CpiIRRoleHandleV1
  accountParameterBindings : Array CpiPreflightAccountParamBindingV1
  probeIxDataLen : Nat
  entryGlobalOps : Array CpiPreflightOpV1
  bodyOps : Array CpiEscrowBodyOpV1
  tempCount : Nat
  deriving BEq, Repr

structure SolanaCpiEscrowIRCandidateV1 where
  schema : String
  sourcePlanDigest : Digest
  sourceIrDigest : Digest
  profileId : String
  profileDigest : Digest
  catalogDigest : Digest
  abiLayout : LoaderV3AbiLayoutV1
  maxOuterRoles : Nat
  maxFrameBytes : Nat
  handlers : Array CpiEscrowHandlerIRV1
  deriving BEq

/-- Private resolved composite escrow IR. Sole mint from Semantic-bound preflight Plan. -/
structure ResolvedSolanaCpiEscrowIRV1 where
  private mk ::
  authority : SolanaCpiPreflightPlanV1
  candidate : SolanaCpiEscrowIRCandidateV1
  canonicalBytes : ByteArray
  digest : Digest

namespace ResolvedSolanaCpiEscrowIRV1

def authorityOf (r : ResolvedSolanaCpiEscrowIRV1) : SolanaCpiPreflightPlanV1 :=
  r.authority
def candidateOf (r : ResolvedSolanaCpiEscrowIRV1) : SolanaCpiEscrowIRCandidateV1 :=
  r.candidate
def digestOf (r : ResolvedSolanaCpiEscrowIRV1) : Digest :=
  r.digest
def canonicalBytesOf (r : ResolvedSolanaCpiEscrowIRV1) : ByteArray :=
  r.canonicalBytes

end ResolvedSolanaCpiEscrowIRV1

/-- Private #125 product composite IR. Sole mint from product Plan authority.
    Shares candidate DTO with escrow core; no preflight conversion. -/
structure ResolvedSolanaCpiProductIRV1 where
  private mk ::
  authority : SolanaCpiProductPlanV1
  candidate : SolanaCpiEscrowIRCandidateV1
  canonicalBytes : ByteArray
  digest : Digest

namespace ResolvedSolanaCpiProductIRV1

def authorityOf (r : ResolvedSolanaCpiProductIRV1) : SolanaCpiProductPlanV1 :=
  r.authority
def candidateOf (r : ResolvedSolanaCpiProductIRV1) : SolanaCpiEscrowIRCandidateV1 :=
  r.candidate
def digestOf (r : ResolvedSolanaCpiProductIRV1) : Digest :=
  r.digest
def canonicalBytesOf (r : ResolvedSolanaCpiProductIRV1) : ByteArray :=
  r.canonicalBytes
def isProductArtifact (_ : ResolvedSolanaCpiProductIRV1) : Bool := true
def isTestPreactivation (_ : ResolvedSolanaCpiProductIRV1) : Bool := false

end ResolvedSolanaCpiProductIRV1

/-- Product IR schema (distinct domain from preactivation escrow IR). -/
def productIrSchemaV1 : String := "proof-forge.solana.cpi-product-ir.v1"
def productIrDigestDomainV1 : String := "pf.solana.cpi-product-ir.v1"

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
  | .state _ | .accountParameter .. | .vaultPda | .handlerCaller
  | .vaultAta | .dstAta => none

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

private def requireEscrowTokenPackage : CompileResult FrozenCalleePackage :=
  requireAbsentLoaderPackage "token-classic-v1" tokenClassicProgramIdV1

private def requireEscrowAtaPackage : CompileResult FrozenCalleePackage :=
  requireAbsentLoaderPackage "ata-classic-v1" ataClassicProgramIdV1

private def requireEscrowSystemPackage : CompileResult FrozenCalleePackage := do
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

/-- Convert Semantic EnvReadKeyV1 to Plan EnvReadKindV1. -/
private def envReadKindOfKey : EnvReadKeyV1 → EnvReadKindV1
  | .nativeVaultBalance => .nativeVaultBalance
  | .tokenVaultBalance => .tokenVaultBalance

private def renderEnvReadKind : EnvReadKindV1 → String
  | .nativeVaultBalance => "nativeVaultBalance"
  | .tokenVaultBalance => "tokenVaultBalance"

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
  | .closedPackages packages =>
      unless packages == #["system-v1", "token-classic-v1"] do
        tFail "Escrow closedPackages owner must be exact [system-v1,token-classic-v1]"
      -- ATA atomic OR owner is emitted by ataAccountPrestateClosed.
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
  | .uninitialized => pure ()
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
      -- are projected as CpiEscrowSiteCheckV1 at siteChecks (invoke-bound).
      unless bytes == 165 do
        tFail s!"classicTokenAccount bytes must be 165, got {bytes}"
      unless state == "initialized-not-frozen" do
        tFail s!"classicTokenAccount state must be initialized-not-frozen, got '{state}'"
      ops := ops.push (.checkExactDataLen localIndex 165)
  | .classicTokenMint bytes state _decimalsEqualsArg =>
      -- Generic layer: exact 82B only. is_initialized/decimals field joins are
      -- projected as CpiEscrowSiteCheckV1 at siteChecks with decimals source.
      unless bytes == 82 do
        tFail s!"classicTokenMint bytes must be 82, got {bytes}"
      unless state == "initialized" do
        tFail s!"classicTokenMint state must be initialized, got '{state}'"
      ops := ops.push (.checkExactDataLen localIndex 82)
  | .ataAccount mintEqualsArg ownerEqualsArg =>
      unless mintEqualsArg == "mint" &&
          (ownerEqualsArg == "wallet" || ownerEqualsArg == "vault" ||
           ownerEqualsArg == "dst") do
        tFail "ATA account field joins must be mint/(wallet|vault|dst)"
      -- Closed owner/data alternatives are one custom atomic check.
      pure ()
  pure ops

private def resolveProvisioning (prov : ProvisioningPolicy) : CompileResult Unit := do
  match prov with
  | .none | .mustExist | .systemCreateAccount | .ataCreateIdempotent => pure ()

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
      tFail "Escrow CPI IR requires public parameters only"
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
        s!"Escrow CPI IR admits only public Principal/UInt64/UInt8 params, got '{p.name}'"
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
      s!"Escrow CPI IR requires single-block straight-line callables (got {callable.blocks.size} blocks)"
  unless callable.entryBlock.toNat == 0 do
    tFail "Escrow CPI IR requires entryBlock == 0"
  unless callable.loopBounds.isEmpty do
    tFail "Escrow CPI IR rejects loopBounds (no back edges)"
  let blk ← getArr callable.blocks 0 "callable.blocks"
  unless blk.id.toNat == 0 do
    tFail "Escrow CPI IR requires sole block id == 0"
  unless blk.params.isEmpty do
    tFail "Escrow CPI IR rejects block parameters"
  pure blk

private def localIndexOfRole
    (handles : Array CpiIRRoleHandleV1) (roleId : Nat) : CompileResult Nat :=
  match handles.find? (fun h => h.roleId == roleId) with
  | some h => pure h.localIndex
  | none => tFail s!"roleId {roleId} missing from handler local roles"

/-- Resolve a synthetic vault/caller meta slot into a PrincipalBinding-shaped
    carrier (semanticValueId/paramOrdinal unused; set to 0). -/
private def resolveSyntheticMetaBinding
    (handles : Array CpiIRRoleHandleV1)
    (site : CpiIRSiteV1)
    (metaIndex : Nat)
    (want : MetaBinding)
    (wantKey : RoleKeyPolicyV1) :
    CompileResult CpiEscrowPrincipalBindingV1 := do
  let metaSlot ← getArr site.metas metaIndex s!"site {site.siteId}.metas"
  unless metaSlot.metaIndex == metaIndex do
    tFail s!"site {site.siteId} meta {metaIndex}: metaIndex diverged"
  unless metaSlot.spec.binding == want do
    tFail s!"site {site.siteId} meta {metaIndex}: expected synthetic binding"
  let handle ← match handles.find? (fun h => h.roleId == metaSlot.roleId) with
    | some h => pure h
    | none => tFail s!"site {site.siteId} meta {metaIndex}: role missing from handler"
  unless handle.keyPolicy == wantKey do
    tFail s!"site {site.siteId} meta {metaIndex}: role key policy diverged"
  unless handle.localIndex == metaSlot.localHandleIndex do
    tFail s!"site {site.siteId} meta {metaIndex}: local handle index diverged"
  pure {
    argIndex := metaIndex
    semanticValueId := 0
    paramOrdinal := 0
    roleId := metaSlot.roleId
    localIndex := handle.localIndex
  }


/-- Resolve a frozen Principal arg name → dense localIndex via site.args role join.
    ADR-0030 E1b: for vault ATA owner join, "vault" is a synthetic PDA role,
    not a parameter. Fall back to handler role lookup by keyPolicy. -/
private def principalLocalOfArgName
    (site : CpiIRSiteV1) (handles : Array CpiIRRoleHandleV1) (argName : String) :
    CompileResult Nat := do
  match site.args.find? (fun a => a.spec.name == argName) with
  | some arg =>
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
  | none =>
      match argName with
      | "vault" =>
          let h ← match handles.find? (fun r => r.keyPolicy == RoleKeyPolicyV1.vaultPda) with
          | some r => pure r
          | none => tFail s!"site {site.siteId}: vault PDA role missing for Token field join"
          pure h.localIndex
      | _ => tFail s!"site {site.siteId}: Principal arg '{argName}' missing for Token field join"

/-- Project one classic Token Account field join suite (closed). -/
private def projectClassicTokenAccountFields
    (site : CpiIRSiteV1)
    (handles : Array CpiIRRoleHandleV1)
    (localIndex : Nat)
    (mintEqualsArg : Option String)
    (ownerEqualsArg : Option String)
    (delegate : Option String) :
    CompileResult (Array CpiEscrowSiteCheckV1) := do
  let mut ops : Array CpiEscrowSiteCheckV1 := #[]
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
    (decimalsSrc : CpiEscrowU8SourceV1) :
    CompileResult (Array CpiEscrowSiteCheckV1) := do
  let mut ops : Array CpiEscrowSiteCheckV1 := #[]
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
    (decimalsSrc : CpiEscrowU8SourceV1) :
    CompileResult (Array CpiEscrowSiteCheckV1) := do
  let mut ops : Array CpiEscrowSiteCheckV1 := #[]
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
    | _ => pure ()
  pure ops

/-- Project site checks when no Token decimals source is required (System/ATA). -/
private def projectSiteChecksNoDecimals
    (mode : HandlerModeV1)
    (handles : Array CpiIRRoleHandleV1)
    (site : CpiIRSiteV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult (Array CpiEscrowSiteCheckV1) :=
  -- Use a dummy decimals source; mint decimals field joins only fire for Token mint
  -- with decimalsEqualsArg = some, which System/ATA never supply with a join.
  projectSiteChecks mode handles site stateSchemas (.literal 0)

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
    CompileResult CpiEscrowPrincipalBindingV1 := do
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
    CompileResult CpiEscrowU64SourceV1 := do
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
    CompileResult CpiEscrowU8SourceV1 := do
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
    CompileResult (Array CpiEscrowMetaV1) := do
  let mut metas : Array CpiEscrowMetaV1 := #[]
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
    (_types : Array TypeDeclV1) (_callable : CallableV1)
    (_layout : Array (Nat × Nat × Nat))
    (site : CpiIRSiteV1)
    (spaceSrc? : Option CpiEscrowU64SourceV1) :
    CompileResult (Array CpiEscrowArgCheckV1) := do
  if site.qn == "solana.system.createPdaAccount" then
    unless site.preflight == #[.uint64AtMost "space" maxPdaSpaceBytesV1] do
      tFail s!"site {site.siteId}: createPdaAccount preflight must be space≤4096"
    let spaceSrc ← match spaceSrc? with
      | some s => pure s
      | none => tFail s!"site {site.siteId}: space source missing for preflight"
    match spaceSrc with
    | .literal v =>
        unless v.toNat ≤ maxPdaSpaceBytesV1 do
          tFail s!"site {site.siteId}: space literal exceeds 4096"
    | .param .. => pure ()
    pure #[.uint64AtMost "space" spaceSrc maxPdaSpaceBytesV1]
  else
    unless site.preflight.isEmpty do
      tFail s!"site {site.siteId}: non-create APIs require empty preflight"
    pure #[]

private def validateEscrowSiteShape (site : CpiIRSiteV1) : CompileResult Unit := do
  match site.qn with
  | "solana.system.transfer" =>
      unless site.packageId == "system-v1" do
        tFail s!"system.transfer package must be system-v1"
      unless site.programKey == systemProgramIdV1 do
        tFail s!"site {site.siteId}: System program key must be zero id"
      unless site.instructionCodec.length == 12 do
        tFail s!"site {site.siteId}: system.transfer dataLen must be 12"
      unless site.pda == .none do
        tFail s!"system.transfer site {site.siteId} must have pda.none"
      unless site.signerGroups.isEmpty do
        tFail s!"system.transfer site {site.siteId} requires zero signer groups"
      unless site.outerOnlyAccounts.isEmpty do
        tFail s!"system.transfer site {site.siteId} requires empty outer-only"
      unless site.metas.size == 2 do
        tFail s!"system.transfer site {site.siteId} requires exactly two metas"
      unless site.args.size == 3 do
        tFail s!"system.transfer site {site.siteId} requires exactly three args"
      unless site.preflight.isEmpty do
        tFail s!"system.transfer site {site.siteId} must have empty preflight"
  | "solana.token.transferChecked" =>
      unless site.packageId == "token-classic-v1" do
        tFail s!"transferChecked package must be token-classic-v1"
      unless site.programKey == tokenClassicProgramIdV1 do
        tFail s!"site {site.siteId}: Token program key must be classic Token id"
      unless site.instructionCodec.length == 10 do
        tFail s!"site {site.siteId}: Token dataLen must be 10"
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
      unless site.packageId == "token-classic-v1" do
        tFail s!"transferCheckedPda package must be token-classic-v1"
      unless site.programKey == tokenClassicProgramIdV1 do
        tFail s!"site {site.siteId}: Token program key must be classic Token id"
      unless site.instructionCodec.length == 10 do
        tFail s!"site {site.siteId}: Token dataLen must be 10"
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
          tFail s!"transferCheckedPda rejects non-signer PDA use at site {site.siteId}"
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
  | "solana.system.createPdaAccount" =>
      unless site.packageId == "system-v1" do
        tFail s!"createPdaAccount package must be system-v1"
      unless site.programKey == systemProgramIdV1 do
        tFail s!"site {site.siteId}: System program key must be zero pubkey"
      unless site.instructionCodec.length == 52 do
        tFail s!"site {site.siteId}: createPdaAccount dataLen must be 52"
      match site.pda with
      | .signer rule targetArg seedAuthArg seedTagArg bumpArg signerArg =>
          unless rule == "current-program-tagged-v1" do
            tFail s!"site {site.siteId}: PDA rule must be current-program-tagged-v1"
          unless targetArg == "pda" && seedAuthArg == "seedAuthority" &&
              seedTagArg == "seedTag" && bumpArg == "bump" &&
              signerArg == "pda" do
            tFail s!"site {site.siteId}: PDA arg names must match frozen createPdaAccount"
      | .none =>
          tFail s!"createPdaAccount requires PDA signer use at site {site.siteId}"
      | .addressCheckOnly .. | .vaultPdaSigner _ =>
          tFail s!"createPdaAccount rejects non-signer PDA use at site {site.siteId}"
      unless site.signerGroups.size == 1 do
        tFail s!"site {site.siteId}: exact one signer group required"
      let group ← getArr site.signerGroups 0 s!"site {site.siteId}.signerGroups"
      unless group.id == 0 && group.metaArg == "pda" &&
          group.pdaRule == "current-program-tagged-v1" do
        tFail s!"site {site.siteId}: signer group must be id0/pda/current-program-tagged-v1"
      unless site.metas.size == 2 do
        tFail s!"site {site.siteId}: createPdaAccount requires exactly two metas"
      unless site.outerOnlyAccounts.size == 1 do
        tFail s!"site {site.siteId}: createPdaAccount requires exactly one outer-only"
      unless site.args.size == 7 do
        tFail s!"site {site.siteId}: createPdaAccount requires exactly seven args"
      unless site.preflight == #[.uint64AtMost "space" maxPdaSpaceBytesV1] do
        tFail s!"site {site.siteId}: createPdaAccount preflight must be space≤4096"
  | "solana.ata.createIdempotent" =>
      unless site.packageId == "ata-classic-v1" do
        tFail s!"createIdempotent package must be ata-classic-v1"
      unless site.programKey == ataClassicProgramIdV1 do
        tFail s!"site {site.siteId}: ATA program key must be frozen classic ATA id"
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
  | "pf.assets.native.deposit" =>
      unless site.packageId == "system-v1" do
        tFail s!"pf.assets.native.deposit package must be system-v1"
      unless site.programKey == systemProgramIdV1 do
        tFail s!"site {site.siteId}: System program key must be zero id"
      unless site.instructionCodec.length == 12 do
        tFail s!"site {site.siteId}: deposit dataLen must be 12"
      unless site.pda == .none do
        tFail s!"deposit site {site.siteId} must have pda.none (ensure is IR-owned)"
      unless site.signerGroups.isEmpty do
        tFail s!"deposit site {site.siteId} requires zero signer groups"
      unless site.outerOnlyAccounts.isEmpty do
        tFail s!"deposit site {site.siteId} requires empty outer-only"
      unless site.metas.size == 2 do
        tFail s!"deposit site {site.siteId} requires exactly two metas"
      unless site.args.size == 1 do
        tFail s!"deposit site {site.siteId} requires exactly one arg (amount)"
      unless site.preflight.isEmpty do
        tFail s!"deposit site {site.siteId} must have empty preflight"
  | "pf.assets.native.transfer" =>
      unless site.packageId == "system-v1" do
        tFail s!"pf.assets.native.transfer package must be system-v1"
      unless site.programKey == systemProgramIdV1 do
        tFail s!"site {site.siteId}: System program key must be zero id"
      unless site.instructionCodec.length == 12 do
        tFail s!"site {site.siteId}: native.transfer dataLen must be 12"
      match site.pda with
      | .vaultPdaSigner rule =>
          unless rule == vaultPdaRuleIdV1 do
            tFail s!"site {site.siteId}: vault PDA rule must be proof-forge:vault:v1"
      | .none | .signer .. | .addressCheckOnly .. =>
          tFail s!"native.transfer requires vaultPdaSigner at site {site.siteId}"
      unless site.signerGroups.size == 1 do
        tFail s!"site {site.siteId}: native.transfer requires exact one signer group"
      let group ← getArr site.signerGroups 0 s!"site {site.siteId}.signerGroups"
      unless group.id == 0 && group.metaArg == "vault" &&
          group.pdaRule == vaultPdaRuleIdV1 do
        tFail s!"site {site.siteId}: signer group must be id0/vault/proof-forge:vault:v1"
      unless site.metas.size == 2 do
        tFail s!"site {site.siteId}: native.transfer requires exactly two metas"
      unless site.outerOnlyAccounts.isEmpty do
        tFail s!"site {site.siteId}: native.transfer requires empty outer-only"
      unless site.args.size == 2 do
        tFail s!"site {site.siteId}: native.transfer requires dst + amount"
      unless site.preflight.isEmpty do
        tFail s!"native.transfer site {site.siteId} must have empty preflight"
  | "pf.assets.token.transfer" =>
      unless site.packageId == "token-classic-v1" do
        tFail s!"pf.assets.token.transfer package must be token-classic-v1"
      unless site.programKey == tokenClassicProgramIdV1 do
        tFail s!"site {site.siteId}: Token program key must be classic Token id"
      unless site.instructionCodec.length == 10 do
        tFail s!"site {site.siteId}: token.transfer dataLen must be 10"
      match site.pda with
      | .vaultPdaSigner rule =>
          unless rule == vaultPdaRuleIdV1 do
            tFail s!"site {site.siteId}: vault PDA rule must be proof-forge:vault:v1"
      | .none | .signer .. | .addressCheckOnly .. =>
          tFail s!"token.transfer requires vaultPdaSigner at site {site.siteId}"
      unless site.signerGroups.size == 1 do
        tFail s!"site {site.siteId}: token.transfer requires exact one signer group"
      let group ← getArr site.signerGroups 0 s!"site {site.siteId}.signerGroups"
      unless group.id == 0 && group.metaArg == "vault" &&
          group.pdaRule == vaultPdaRuleIdV1 do
        tFail s!"site {site.siteId}: signer group must be id0/vault/proof-forge:vault:v1"
      unless site.metas.size == 4 do
        tFail s!"site {site.siteId}: token.transfer requires exactly four metas"
      unless site.outerOnlyAccounts.isEmpty do
        tFail s!"site {site.siteId}: token.transfer requires empty outer-only"
      unless site.args.size == 3 do
        tFail s!"site {site.siteId}: token.transfer requires mint + dst + amount"
      unless site.preflight.isEmpty do
        tFail s!"token.transfer site {site.siteId} must have empty preflight"
  | other =>
      tFail
        s!"Escrow CPI admits only system.transfer|system.createPdaAccount|token.transferChecked|token.transferCheckedPda|ata.createIdempotent|pf.assets.native.deposit|pf.assets.native.transfer|pf.assets.token.transfer, got '{other}'"

private def projectEscrowHandler
    (abi : LoaderV3AbiLayoutV1)
    (data : SemanticProgramDataV1)
    (planHandler : HandlerPlanV1)
    (handles : Array CpiIRRoleHandleV1)
    (sites : Array CpiIRSiteV1)
    (envReadSites : Array EnvReadSitePlanV1)
    (stateSchemas : Array StateSchemaV1) :
    CompileResult CpiEscrowHandlerIRV1 := do
  let _tokenPkg ← requireEscrowTokenPackage
  let _ataPkg ← requireEscrowAtaPackage
  let _systemPkg ← requireEscrowSystemPackage
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
    validateEscrowSiteShape site

  let blk ← requireStraightLineCallable callable
  let (paramLayout, probeIxDataLen) ← buildParamIxLayout data.types callable
  let (bindings, entryGlobalOps) ←
    projectEntryGlobalOps abi planHandler.mode handles stateSchemas

  let mut tempOf : Array (Nat × Nat) := #[]
  let mut nextTemp : Nat := 0
  let mut body : Array CpiEscrowBodyOpV1 := #[]

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
            tFail "Escrow CPI IR admits only UInt64/UInt8 literals in body"
    | .stateLoad stateId =>
        let some vd := instr.result |
          tFail "stateLoad must produce a result"
        let (stateLocal, schema) ← match stateInfo? with
          | some s => pure s
          | none => tFail "stateLoad without state role"
        unless stateId.toNat == 0 do
          tFail "Escrow CPI IR first slice admits only stateId 0"
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
          tFail "Escrow CPI IR first slice admits only stateId 0"
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
            -- Escrow body only admits checked UInt64 add. UInt8/mixed/non-UInt64
            -- must fail closed here (not be mis-emitted as checkedAddU64).
            let lhsTy ← match typeOfValueId? callable lhs with
              | some t => pure t
              | none => tFail s!"checkedAdd lhs ValueId {lhs} has no type"
            let rhsTy ← match typeOfValueId? callable rhs with
              | some t => pure t
              | none => tFail s!"checkedAdd rhs ValueId {rhs} has no type"
            unless anonUintWidth? data.types lhsTy == some 64 &&
                anonUintWidth? data.types rhsTy == some 64 &&
                anonUintWidth? data.types vd.typeId == some 64 do
              tFail
                "Escrow CPI IR admits only anonymous UInt64 checked add (lhs/rhs/result)"
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
            tFail "Escrow CPI IR first slice admits only checked UInt64 add in body"
    | .envRead key args =>
        let some vd := instr.result |
          tFail "envRead must produce a result"
        unless anonUintWidth? data.types vd.typeId == some 64 do
          tFail "envRead result must be anonymous UInt64"
        -- Find the matching envRead site from the Plan
        let envSite ← match envReadSites.find? (fun s =>
          s.anchor.callableId == planHandler.callableId &&
            s.anchor.blockId == blk.id.toNat &&
            s.anchor.instructionIndex == instrIdx) with
        | some s => pure s
        | none =>
            tFail
              s!"envRead at instr {instrIdx} has no matching envRead site anchor"
        unless envSite.kind == envReadKindOfKey key do
          tFail "envRead site kind diverges from Semantic envRead key"
        -- Verify arg join
        match key with
        | .nativeVaultBalance =>
            unless args.isEmpty do
              tFail "nativeVaultBalance envRead takes zero args"
        | .tokenVaultBalance =>
            unless args.size == 1 do
              tFail "tokenVaultBalance envRead takes exactly one arg"
        -- Resolve local indices for the roles
        let vaultLocal ← localIndexOfRole handles envSite.vaultRoleId
        let vaultAtaLocal ← localIndexOfRole handles envSite.vaultAtaRoleId
        let mintLocal ← localIndexOfRole handles envSite.mintRoleId
        let systemLocal ← localIndexOfRole handles envSite.systemProgramRoleId
        let tokenLocal ← localIndexOfRole handles envSite.tokenProgramRoleId
        let ataLocal ← localIndexOfRole handles envSite.ataProgramRoleId
        let (t, tempOf', next') := allocTemp tempOf nextTemp vd.valueId.toNat
        tempOf := tempOf'
        nextTemp := next'
        body := body.push (.envReadVaultBalance t (envReadKindOfKey key) vaultLocal
          vaultAtaLocal mintLocal systemLocal tokenLocal ataLocal)
    | .externalCall effectId callee args =>
        let qnComps ← mapExcept (renderQualifiedNameComponents callee) "callee QN"
        let qn := String.intercalate "." qnComps.toList
        unless qn == "solana.token.transferChecked" ||
            qn == "solana.token.transferCheckedPda" ||
            qn == "solana.system.transfer" ||
            qn == "solana.system.createPdaAccount" ||
            qn == "solana.ata.createIdempotent" ||
            qn == "pf.assets.native.deposit" ||
            qn == "pf.assets.native.transfer" ||
            qn == "pf.assets.token.transfer" do
          tFail
            s!"Escrow CPI admits only system.transfer|system.createPdaAccount|token.transferChecked|token.transferCheckedPda|ata.createIdempotent|pf.assets.native.deposit|pf.assets.native.transfer|pf.assets.token.transfer, got '{qn}'"
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
        let programLocal ← localIndexOfRole handles site.programRoleId
        unless site.programHandleIndex == programLocal do
          tFail s!"site {site.siteId} program handle index diverged"
        let metas ← projectMetas handles site
        if qn == "pf.assets.native.deposit" then
          unless site.packageId == "system-v1" do
            tFail "pf.assets.native.deposit package must be system-v1"
          unless args.size == 1 && site.args.size == 1 do
            tFail "pf.assets.native.deposit requires exactly 1 Semantic and Plan arg"
          let callerB ← resolveSyntheticMetaBinding handles site 0
            MetaBinding.handlerCaller RoleKeyPolicyV1.handlerCaller
          let vaultB ← resolveSyntheticMetaBinding handles site 1
            MetaBinding.vaultPda RoleKeyPolicyV1.vaultPda
          let amountVid ← getArr args 0 "externalCall.args"
          let amountArg ← getArr site.args 0 s!"site {site.siteId}.args"
          unless amountArg.semanticValueId == amountVid.toNat &&
              amountArg.roleId.isNone &&
              amountArg.spec.type_ == FrozenValueType.uint64 do
            tFail s!"site {site.siteId} amount binding diverged"
          let amountSrc ← resolveU64Source data.types callable paramLayout amountVid
            s!"site {site.siteId} amount"
          let meta0 ← getArr site.metas 0 s!"site {site.siteId}.metas"
          unless meta0.roleId == callerB.roleId &&
              meta0.localHandleIndex == callerB.localIndex &&
              meta0.spec.cpiSigner == true &&
              meta0.spec.outerSignerContribution == true do
            tFail s!"site {site.siteId} deposit caller meta shape diverged"
          let meta1 ← getArr site.metas 1 s!"site {site.siteId}.metas"
          unless meta1.roleId == vaultB.roleId &&
              meta1.localHandleIndex == vaultB.localIndex &&
              meta1.spec.cpiWritable == true do
            tFail s!"site {site.siteId} deposit vault meta shape diverged"
          let argChecks ← projectSiteArgChecks data.types callable paramLayout site none
          let siteOps ← projectSiteChecksNoDecimals planHandler.mode handles site
            stateSchemas
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeEscrow {
            siteId := site.siteId
            kind := .nativeDeposit
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 12
            source := none
            mint := none
            destination := some vaultB
            authority := none
            authorityPda := none
            seedAuthority := none
            payer := some callerB
            pda := some vaultB
            ata := none
            wallet := none
            seedTag := none
            bump := none
            amount := none
            decimals := none
            lamports := some amountSrc
            space := none
            systemProgramLocalIndex := none
            tokenProgramLocalIndex := none
            metas
            outerOnly := #[]
            signerGroupId := none
            pdaRule := some vaultPdaRuleIdV1
            accountInfoCount := handles.size
          })
        else if qn == "pf.assets.native.transfer" then
          unless site.packageId == "system-v1" do
            tFail "pf.assets.native.transfer package must be system-v1"
          unless args.size == 2 && site.args.size == 2 do
            tFail "pf.assets.native.transfer requires exactly 2 Semantic and Plan args"
          let vaultB ← resolveSyntheticMetaBinding handles site 0
            MetaBinding.vaultPda RoleKeyPolicyV1.vaultPda
          let dstVid ← getArr args 0 "externalCall.args"
          let dstB ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 0 dstVid
          let amountVid ← getArr args 1 "externalCall.args"
          let amountArg ← getArr site.args 1 s!"site {site.siteId}.args"
          unless amountArg.semanticValueId == amountVid.toNat &&
              amountArg.roleId.isNone &&
              amountArg.spec.type_ == FrozenValueType.uint64 do
            tFail s!"site {site.siteId} amount binding diverged"
          let amountSrc ← resolveU64Source data.types callable paramLayout amountVid
            s!"site {site.siteId} amount"
          let meta0 ← getArr site.metas 0 s!"site {site.siteId}.metas"
          unless meta0.roleId == vaultB.roleId &&
              meta0.localHandleIndex == vaultB.localIndex &&
              meta0.spec.cpiSigner == true &&
              meta0.spec.signerGroupId == some 0 do
            tFail s!"site {site.siteId} vault payer meta shape diverged"
          let meta1 ← getArr site.metas 1 s!"site {site.siteId}.metas"
          unless meta1.roleId == dstB.roleId &&
              meta1.localHandleIndex == dstB.localIndex &&
              meta1.spec.cpiWritable == true do
            tFail s!"site {site.siteId} dst meta shape diverged"
          let argChecks ← projectSiteArgChecks data.types callable paramLayout site none
          let siteOps ← projectSiteChecksNoDecimals planHandler.mode handles site
            stateSchemas
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeEscrow {
            siteId := site.siteId
            kind := .nativeTransfer
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 12
            source := none
            mint := none
            destination := some dstB
            authority := none
            authorityPda := some vaultB
            seedAuthority := none
            payer := some vaultB
            pda := some vaultB
            ata := none
            wallet := none
            seedTag := none
            bump := none
            amount := none
            decimals := none
            lamports := some amountSrc
            space := none
            systemProgramLocalIndex := none
            tokenProgramLocalIndex := none
            metas
            outerOnly := #[]
            signerGroupId := some 0
            pdaRule := some vaultPdaRuleIdV1
            accountInfoCount := handles.size
          })
        else if qn == "pf.assets.token.transfer" then
          unless site.packageId == "token-classic-v1" do
            tFail "pf.assets.token.transfer package must be token-classic-v1"
          unless args.size == 3 && site.args.size == 3 do
            tFail "pf.assets.token.transfer requires exactly 3 Semantic and Plan args"
          let mintVid ← getArr args 0 "externalCall.args"
          let mintBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 0 mintVid
          let dstVid ← getArr args 1 "externalCall.args"
          let dstBinding ← resolvePrincipalAccountBinding data.types callable
            handles bindings site 1 dstVid
          let amountVid ← getArr args 2 "externalCall.args"
          let amountArg ← getArr site.args 2 s!"site {site.siteId}.args"
          unless amountArg.semanticValueId == amountVid.toNat &&
              amountArg.roleId.isNone &&
              amountArg.spec.type_ == FrozenValueType.uint64 do
            tFail s!"site {site.siteId} amount binding diverged"
          let amountSrc ← resolveU64Source data.types callable paramLayout amountVid
            s!"site {site.siteId} amount"
          -- Meta 0: vaultAta (source = vault ATA, writable, outer writable)
          let vaultAtaB ← resolveSyntheticMetaBinding handles site 0
            MetaBinding.vaultAta RoleKeyPolicyV1.vaultAta
          -- Meta 1: mint (readonly)
          let mintMeta ← getArr site.metas 1 s!"site {site.siteId}.metas"
          unless mintMeta.metaIndex == 1 &&
              mintMeta.roleId == mintBinding.roleId &&
              mintMeta.localHandleIndex == mintBinding.localIndex &&
              mintMeta.spec.cpiWritable == false &&
              mintMeta.spec.cpiSigner == false do
            tFail s!"site {site.siteId} mint meta must be readonly non-signer"
          -- Meta 2: dstAta (destination = dst ATA, writable)
          let dstAtaB ← resolveSyntheticMetaBinding handles site 2
            MetaBinding.dstAta RoleKeyPolicyV1.dstAta
          -- Meta 3: vaultPda (authority PDA signer, signer group 0)
          let vaultB ← resolveSyntheticMetaBinding handles site 3
            MetaBinding.vaultPda RoleKeyPolicyV1.vaultPda
          let meta3 ← getArr site.metas 3 s!"site {site.siteId}.metas"
          unless meta3.roleId == vaultB.roleId &&
              meta3.localHandleIndex == vaultB.localIndex &&
              meta3.spec.cpiSigner == true &&
              meta3.spec.signerGroupId == some 0 do
            tFail s!"site {site.siteId} vaultPda meta must be CPI signer group 0"
          -- Resolve handlerCaller (pf_caller) role for ATA ensure payer.
          -- Not a CPI meta on token.transfer; lookup by keyPolicy.
          let callerHandle ← match handles.find? (fun h =>
            h.keyPolicy == RoleKeyPolicyV1.handlerCaller) with
          | some h => pure h
          | none =>
              tFail s!"site {site.siteId}: handlerCaller role missing for ATA ensure payer"
          let callerB : CpiEscrowPrincipalBindingV1 := {
            argIndex := 0
            semanticValueId := 0
            paramOrdinal := 0
            roleId := callerHandle.roleId
            localIndex := callerHandle.localIndex
          }
          -- Fixed program locals for ATA ensure (System + Token metas).
          let systemLocal ← fixedProgramLocal handles "system-v1"
          let tokenLocal ← fixedProgramLocal handles "token-classic-v1"
          -- Decimals: fixed literal 9 (catalog/mint binding deferred)
          let decimalsSrc : CpiEscrowU8SourceV1 :=
            .literal pfAssetsTokenTransferDecimalsV1
          let argChecks ← projectSiteArgChecks data.types callable paramLayout site none
          let siteOpsAll ← projectSiteChecks planHandler.mode handles site stateSchemas
            decimalsSrc
          -- ADR-0028 §4.2 site-time discipline for ATA roles: the two ATA
          -- token-account predicates (165B/initialized/mintEq/ownerEq/
          -- delegateNone) must be checked AFTER each createIdempotent ensure,
          -- not pre-invoke — a fresh System-owned dst/vault ATA is only
          -- initialized by the ensure itself. The composite emitter re-emits
          -- these exact checks before transferCheckedPda; the pre-invoke
          -- siteChecks keep only generic/program/mint checks.
          let siteOps := siteOpsAll.filter fun op =>
            match op with
            | .tokenAccountStateInitialized l => l != vaultAtaB.localIndex && l != dstAtaB.localIndex
            | .tokenAccountMintEqualsRole a _ => a != vaultAtaB.localIndex && a != dstAtaB.localIndex
            | .tokenAccountOwnerEqualsRole a _ => a != vaultAtaB.localIndex && a != dstAtaB.localIndex
            | .tokenAccountDelegateNone l => l != vaultAtaB.localIndex && l != dstAtaB.localIndex
            | .generic (.checkExactDataLen l 165) => l != vaultAtaB.localIndex && l != dstAtaB.localIndex
            | .generic (.checkOwnerExact l _) => l != vaultAtaB.localIndex && l != dstAtaB.localIndex
            | _ => true
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeEscrow {
            siteId := site.siteId
            kind := .pfAssetsTokenTransfer
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 10
            source := some vaultAtaB
            mint := some mintBinding
            destination := some dstAtaB
            authority := none
            authorityPda := some vaultB
            seedAuthority := none
            payer := some callerB
            pda := some vaultB
            ata := none
            wallet := some dstBinding
            seedTag := none
            bump := none
            amount := some amountSrc
            decimals := some decimalsSrc
            lamports := none
            space := none
            systemProgramLocalIndex := some systemLocal
            tokenProgramLocalIndex := some tokenLocal
            metas
            outerOnly := #[]
            signerGroupId := some 0
            pdaRule := some vaultPdaRuleIdV1
            accountInfoCount := handles.size
          })
        else if qn == "solana.system.transfer" then
          unless site.packageId == "system-v1" do
            tFail "system.transfer package must be system-v1"
          unless args.size == 3 && site.args.size == 3 do
            tFail "system.transfer requires exactly 3 Semantic and Plan args"
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
            tFail s!"site {site.siteId} lamports binding diverged"
          let lamportsSrc ← resolveU64Source data.types callable paramLayout lamportsVid
            s!"site {site.siteId} lamports"
          let meta0 ← getArr site.metas 0 s!"site {site.siteId}.metas"
          unless meta0.metaIndex == 0 &&
              meta0.roleId == payerBinding.roleId &&
              meta0.localHandleIndex == payerBinding.localIndex &&
              meta0.spec.cpiWritable == true &&
              meta0.spec.cpiSigner == true &&
              meta0.spec.outerSignerContribution == true &&
              meta0.spec.outerWritableContribution == true &&
              meta0.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId} transfer payer meta shape diverged"
          let meta1 ← getArr site.metas 1 s!"site {site.siteId}.metas"
          unless meta1.metaIndex == 1 &&
              meta1.roleId == recipientBinding.roleId &&
              meta1.localHandleIndex == recipientBinding.localIndex &&
              meta1.spec.cpiWritable == true &&
              meta1.spec.cpiSigner == false &&
              meta1.spec.outerSignerContribution == false &&
              meta1.spec.outerWritableContribution == true &&
              meta1.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId} transfer recipient meta shape diverged"
          let argChecks ← projectSiteArgChecks data.types callable paramLayout site none
          let siteOps ← projectSiteChecksNoDecimals planHandler.mode handles site
            stateSchemas
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeEscrow {
            siteId := site.siteId
            kind := .transfer
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 12
            source := none
            mint := none
            destination := some recipientBinding
            authority := none
            authorityPda := none
            seedAuthority := none
            payer := some payerBinding
            pda := none
            ata := none
            wallet := none
            seedTag := none
            bump := none
            amount := none
            decimals := none
            lamports := some lamportsSrc
            space := none
            systemProgramLocalIndex := none
            tokenProgramLocalIndex := none
            metas
            outerOnly := #[]
            signerGroupId := none
            pdaRule := none
            accountInfoCount := handles.size
          })
        else if qn == "solana.token.transferChecked" then
          unless site.packageId == "token-classic-v1" do
            tFail "transferChecked package must be token-classic-v1"
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
          let argChecks ← projectSiteArgChecks data.types callable paramLayout site none
          let siteOps ← projectSiteChecks planHandler.mode handles site stateSchemas
            decimalsSrc
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeEscrow {
            siteId := site.siteId
            kind := .transferChecked
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 10
            source := some sourceBinding
            mint := some mintBinding
            destination := some destBinding
            authority := some authBinding
            authorityPda := none
            seedAuthority := none
            payer := none
            pda := none
            ata := none
            wallet := none
            seedTag := none
            bump := none
            amount := some amountSrc
            decimals := some decimalsSrc
            lamports := none
            space := none
            systemProgramLocalIndex := none
            tokenProgramLocalIndex := none
            metas
            outerOnly := #[]
            signerGroupId := none
            pdaRule := none
            accountInfoCount := handles.size
          })
        else if qn == "solana.token.transferCheckedPda" then
          unless site.packageId == "token-classic-v1" do
            tFail "transferCheckedPda package must be token-classic-v1"
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
          let oo0 ← getArr site.outerOnlyAccounts 0 s!"site {site.siteId}.outerOnly"
          unless oo0.roleId == seedAuthBinding.roleId &&
              oo0.localHandleIndex == seedAuthBinding.localIndex &&
              oo0.spec.outerSignerContribution == true &&
              oo0.spec.outerWritableContribution == false do
            tFail s!"site {site.siteId} seedAuthority outer-only must be outer signer non-writable"
          let outerOnly : Array CpiEscrowOuterOnlyBindingV1 := #[{
            outerOnlyIndex := 0
            roleId := oo0.roleId
            localIndex := oo0.localHandleIndex
            outerSigner := oo0.spec.outerSignerContribution
            outerWritable := oo0.spec.outerWritableContribution
          }]
          let argChecks ← projectSiteArgChecks data.types callable paramLayout site none
          let siteOps ← projectSiteChecks planHandler.mode handles site stateSchemas
            decimalsSrc
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeEscrow {
            siteId := site.siteId
            kind := .transferCheckedPda
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 10
            source := some sourceBinding
            mint := some mintBinding
            destination := some destBinding
            authority := none
            authorityPda := some authPdaBinding
            seedAuthority := some seedAuthBinding
            payer := none
            pda := none
            ata := none
            wallet := none
            seedTag := some seedTagSrc
            bump := some bumpSrc
            amount := some amountSrc
            decimals := some decimalsSrc
            lamports := none
            space := none
            systemProgramLocalIndex := none
            tokenProgramLocalIndex := none
            metas
            outerOnly
            signerGroupId := some 0
            pdaRule := some "current-program-tagged-v1"
            accountInfoCount := handles.size
          })
        else if qn == "solana.system.createPdaAccount" then
          unless site.packageId == "system-v1" do
            tFail "createPdaAccount package must be system-v1"
          unless args.size == 7 && site.args.size == 7 do
            tFail "createPdaAccount requires exactly 7 Semantic and Plan args"
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
            tFail s!"site {site.siteId} seedTag binding diverged"
          let seedTagSrc ← resolveU64Source data.types callable paramLayout seedTagVid
            s!"site {site.siteId} seedTag"
          let bumpVid ← getArr args 4 "externalCall.args"
          let bumpArg ← getArr site.args 4 s!"site {site.siteId}.args"
          unless bumpArg.semanticValueId == bumpVid.toNat &&
              bumpArg.roleId.isNone &&
              bumpArg.spec.type_ == FrozenValueType.uint8 do
            tFail s!"site {site.siteId} bump binding diverged"
          let bumpSrc ← resolveU8Source data.types callable paramLayout bumpVid
            s!"site {site.siteId} bump" true
          let lamportsVid ← getArr args 5 "externalCall.args"
          let lamportsArg ← getArr site.args 5 s!"site {site.siteId}.args"
          unless lamportsArg.semanticValueId == lamportsVid.toNat &&
              lamportsArg.roleId.isNone &&
              lamportsArg.spec.type_ == FrozenValueType.uint64 do
            tFail s!"site {site.siteId} lamports binding diverged"
          let lamportsSrc ← resolveU64Source data.types callable paramLayout lamportsVid
            s!"site {site.siteId} lamports"
          let spaceVid ← getArr args 6 "externalCall.args"
          let spaceArg ← getArr site.args 6 s!"site {site.siteId}.args"
          unless spaceArg.semanticValueId == spaceVid.toNat &&
              spaceArg.roleId.isNone &&
              spaceArg.spec.type_ == FrozenValueType.uint64 do
            tFail s!"site {site.siteId} space binding diverged"
          let spaceSrc ← resolveU64Source data.types callable paramLayout spaceVid
            s!"site {site.siteId} space"
          let meta0 ← getArr site.metas 0 s!"site {site.siteId}.metas"
          unless meta0.metaIndex == 0 &&
              meta0.roleId == payerBinding.roleId &&
              meta0.localHandleIndex == payerBinding.localIndex &&
              meta0.spec.cpiWritable == true &&
              meta0.spec.cpiSigner == true &&
              meta0.spec.outerSignerContribution == true &&
              meta0.spec.outerWritableContribution == true &&
              meta0.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId} payer meta must be writable outer/CPI signer"
          let meta1 ← getArr site.metas 1 s!"site {site.siteId}.metas"
          unless meta1.metaIndex == 1 &&
              meta1.roleId == pdaBinding.roleId &&
              meta1.localHandleIndex == pdaBinding.localIndex &&
              meta1.spec.cpiWritable == true &&
              meta1.spec.cpiSigner == true &&
              meta1.spec.outerSignerContribution == false &&
              meta1.spec.outerWritableContribution == true &&
              meta1.spec.signerGroupId == some 0 do
            tFail s!"site {site.siteId} pda meta must be writable CPI signer group 0 outer non-signer"
          let oo0 ← getArr site.outerOnlyAccounts 0 s!"site {site.siteId}.outerOnly"
          unless oo0.roleId == seedAuthBinding.roleId &&
              oo0.localHandleIndex == seedAuthBinding.localIndex &&
              oo0.spec.outerSignerContribution == false &&
              oo0.spec.outerWritableContribution == false do
            tFail s!"site {site.siteId} seedAuthority outer-only must be readonly non-signer"
          let outerOnly : Array CpiEscrowOuterOnlyBindingV1 := #[{
            outerOnlyIndex := 0
            roleId := oo0.roleId
            localIndex := oo0.localHandleIndex
            outerSigner := oo0.spec.outerSignerContribution
            outerWritable := oo0.spec.outerWritableContribution
          }]
          let argChecks ← projectSiteArgChecks data.types callable paramLayout site (some spaceSrc)
          let siteOps ← projectSiteChecksNoDecimals planHandler.mode handles site stateSchemas
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeEscrow {
            siteId := site.siteId
            kind := .createPdaAccount
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 52
            source := none
            mint := none
            destination := none
            authority := none
            authorityPda := none
            seedAuthority := some seedAuthBinding
            payer := some payerBinding
            pda := some pdaBinding
            ata := none
            wallet := none
            seedTag := some seedTagSrc
            bump := some bumpSrc
            amount := none
            decimals := none
            lamports := some lamportsSrc
            space := some spaceSrc
            systemProgramLocalIndex := none
            tokenProgramLocalIndex := none
            metas
            outerOnly
            signerGroupId := some 0
            pdaRule := some "current-program-tagged-v1"
            accountInfoCount := handles.size
          })
        else
          -- solana.ata.createIdempotent
          unless site.packageId == "ata-classic-v1" do
            tFail "createIdempotent package must be ata-classic-v1"
          unless args.size == 4 && site.args.size == 4 do
            tFail "createIdempotent requires exactly 4 Semantic and Plan args"
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
              meta4.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId}: System meta must be exact readonly fixed role"
          let meta5 ← getArr site.metas 5 s!"site {site.siteId}.metas"
          unless meta5.metaIndex == 5 && meta5.localHandleIndex == tokenLocal &&
              meta5.spec.cpiWritable == false && meta5.spec.cpiSigner == false &&
              meta5.spec.signerGroupId.isNone do
            tFail s!"site {site.siteId}: classic Token meta must be exact readonly fixed role"
          let argChecks ← projectSiteArgChecks data.types callable paramLayout site none
          let siteOps ← projectSiteChecksNoDecimals planHandler.mode handles site stateSchemas
          body := body.push (.siteArgChecks site.siteId argChecks)
          body := body.push (.siteChecks site.siteId siteOps)
          body := body.push (.invokeEscrow {
            siteId := site.siteId
            kind := .createIdempotent
            qn
            packageId := site.packageId
            programLocalIndex := programLocal
            dataLen := 1
            source := none
            mint := some mintBinding
            destination := none
            authority := none
            authorityPda := none
            seedAuthority := none
            payer := some payerBinding
            pda := none
            ata := some ataBinding
            wallet := some walletBinding
            seedTag := none
            bump := none
            amount := none
            decimals := none
            lamports := none
            space := none
            systemProgramLocalIndex := some systemLocal
            tokenProgramLocalIndex := some tokenLocal
            metas
            outerOnly := #[]
            signerGroupId := none
            pdaRule := some "ata-classic-v1"
            accountInfoCount := handles.size
          })
    | .constant _cid =>
        tFail "Escrow CPI IR rejects Op.Constant (constants table support deferred)"
    | .unary .. =>
        tFail "Escrow CPI IR rejects unary ops in first slice"
    | .pureCall .. =>
        tFail "Escrow CPI IR rejects pureCall in first slice"
    | .construct .. | .fieldGet .. | .fieldSet .. | .indexGet .. | .indexSet ..
    | .variantTag .. | .variantPayload .. | .checkedCast ..
    | .contextRead .. | .commit .. | .assert_ .. | .emit .. | .schedule .. =>
        tFail "Escrow CPI IR rejects unsupported body op in first slice"

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
      tFail "Escrow CPI IR requires return terminator only (straight-line)"

  let bodySiteIds :=
    body.foldl (init := ([] : List Nat)) fun acc op =>
      match op with
      | .invokeEscrow inv => acc ++ [inv.siteId]
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

/-- Shared composite projection from a validated Plan + retained Semantic.
    `irSchema` selects preactivation vs product IR identity strings. -/
private def projectEscrowCandidateFromPlan
    (plan : ValidatedSolanaCpiPlanV1)
    (compiled : CompiledSemanticV1)
    (irSchema : String) :
    CompileResult SolanaCpiEscrowIRCandidateV1 := do
  let _ ← requireEscrowTokenPackage
  let _ ← requireEscrowAtaPackage
  let _ ← requireEscrowSystemPackage
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok v => pure v
    | .error _ =>
        tFail "Escrow CPI IR: retained Semantic failed structure validation"
  unless data.constants.isEmpty do
    tFail "Escrow CPI IR rejects nonempty constants table"
  unless data.invariants.isEmpty do
    tFail "Escrow CPI IR rejects nonempty invariants"
  let ir ← deriveSolanaCpiIRV1 plan
  let abi := ir.candidate.abiLayout
  unless abi == frozenLoaderV3AbiLayoutV1 do
    tFail "Escrow CPI IR requires frozen Loader V3 ABIv1 layout"
  let mut handlers : Array CpiEscrowHandlerIRV1 := #[]
  for h in plan.candidate.handlers do
    let handles := ir.candidate.roleHandles.filter (fun x => x.handlerId == h.handlerId)
    unless handles.size == h.accountUses.size do
      tFail "handler local handle count mismatch"
    let sites := ir.candidate.sites.filter (fun s => s.handlerId == h.handlerId)
    unless sites.map (·.siteId) == h.cpiSiteIds do
      tFail "handler site order must equal Plan cpiSiteIds"
    let envReadSites := plan.candidate.envReadSites.filter
      (fun s => s.handlerId == h.handlerId)
    let projected ← projectEscrowHandler abi data h handles sites envReadSites
      plan.candidate.stateSchemas
    handlers := handlers.push projected
  pure {
    schema := irSchema
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

private def projectEscrowCandidate
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult SolanaCpiEscrowIRCandidateV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    tFail "Escrow CPI IR requires activationDenied authority"
  projectEscrowCandidateFromPlan
    (SolanaCpiPreflightPlanV1.planOf authority)
    (ResolvedSolanaCpiPreflightV1.compiledOf
      (SolanaCpiPreflightPlanV1.preflightOf authority))
    escrowIrSchemaV1

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

private def renderU64Source : CpiEscrowU64SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt64LowerHex16 v}"

private def renderU8Source : CpiEscrowU8SourceV1 → String
  | .param ord off => s!"param:{ord}@{off}"
  | .literal v => s!"lit:{encodeUInt8LowerHex2 v}"

private def renderMeta (m : CpiEscrowMetaV1) : String :=
  let sg := match m.signerGroupId with
    | none => "none"
    | some id => toString id
  s!"{m.metaIndex}:role{m.roleId}:local{m.localIndex}:w{m.cpiWritable}:s{m.cpiSigner}:sg{sg}"

private def renderPrincipal (b : CpiEscrowPrincipalBindingV1) : String :=
  s!"arg{b.argIndex}:v{b.semanticValueId}:p{b.paramOrdinal}:role{b.roleId}:local{b.localIndex}"

private def renderOuter (o : CpiEscrowOuterOnlyBindingV1) : String :=
  s!"oo{o.outerOnlyIndex}:role{o.roleId}:local{o.localIndex}:os{o.outerSigner}:ow{o.outerWritable}"

private def renderArgCheck : CpiEscrowArgCheckV1 → String
  | .unusedPlaceholder => "unused"
  | .uint64AtMost name src maxV =>
      s!"u64AtMost:{name}:{renderU64Source src}:max{maxV}"

private def renderKind : CpiEscrowKindV1 → String
  | .transfer => "transfer"
  | .createPdaAccount => "createPdaAccount"
  | .transferChecked => "transferChecked"
  | .transferCheckedPda => "transferCheckedPda"
  | .createIdempotent => "createIdempotent"
  | .nativeDeposit => "nativeDeposit"
  | .nativeTransfer => "nativeTransfer"
  | .pfAssetsTokenTransfer => "pfAssetsTokenTransfer"

private def renderOptPrincipal (b : Option CpiEscrowPrincipalBindingV1) : String :=
  match b with
  | none => "none"
  | some p => renderPrincipal p

private def renderOptU64 (s : Option CpiEscrowU64SourceV1) : String :=
  match s with
  | none => "none"
  | some v => renderU64Source v

private def renderOptU8 (s : Option CpiEscrowU8SourceV1) : String :=
  match s with
  | none => "none"
  | some v => renderU8Source v

private def renderInvoke (i : CpiEscrowInvokeV1) : String :=
  let metas := String.intercalate "," (i.metas.map renderMeta).toList
  let oos := String.intercalate "," (i.outerOnly.map renderOuter).toList
  let sg := match i.signerGroupId with
    | none => "none"
    | some id => toString id
  let rule := match i.pdaRule with
    | none => "none"
    | some r => r
  let sys := match i.systemProgramLocalIndex with | none => "none" | some n => toString n
  let tok := match i.tokenProgramLocalIndex with | none => "none" | some n => toString n
  s!"invokeEscrow:{i.siteId}:{renderKind i.kind}:{i.qn}:{i.packageId}:prog{i.programLocalIndex}:len{i.dataLen}:src[{renderOptPrincipal i.source}]:mint[{renderOptPrincipal i.mint}]:dst[{renderOptPrincipal i.destination}]:auth[{renderOptPrincipal i.authority}]:authPda[{renderOptPrincipal i.authorityPda}]:seedAuth[{renderOptPrincipal i.seedAuthority}]:payer[{renderOptPrincipal i.payer}]:pda[{renderOptPrincipal i.pda}]:ata[{renderOptPrincipal i.ata}]:wallet[{renderOptPrincipal i.wallet}]:seedTag[{renderOptU64 i.seedTag}]:bump[{renderOptU8 i.bump}]:amount[{renderOptU64 i.amount}]:decimals[{renderOptU8 i.decimals}]:lamports[{renderOptU64 i.lamports}]:space[{renderOptU64 i.space}]:sysLocal{sys}:tokLocal{tok}:metas[{metas}]:outer[{oos}]:sg{sg}:{rule}:infos{i.accountInfoCount}"

private def renderSiteCheck : CpiEscrowSiteCheckV1 → String
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
  | .ataAddressCanonical ata wallet token mint program =>
      s!"ataAddressCanonical:ata{ata}:wallet{wallet}:token{token}:mint{mint}:program{program}"
  | .ataAccountPrestateClosed ata wallet mint system token =>
      s!"ataAccountPrestateClosed:ata{ata}:wallet{wallet}:mint{mint}:system{system}:token{token}"

private def renderBodyOp : CpiEscrowBodyOpV1 → String
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
  | .invokeEscrow inv => renderInvoke inv
  | .envReadVaultBalance t kind vault vaultAta mint sys tok ata =>
      s!"envReadVaultBalance:{t}:{renderEnvReadKind kind}:vault{vault}:ata{vaultAta}:mint{mint}:sys{sys}:tok{tok}:ata{ata}"
  | .returnU64 t => s!"returnU64:{t}"
  | .returnNone => "returnNone"

private def renderMode : HandlerModeV1 → String
  | .initialize => "initialize"
  | .entry => "entry"
  | .view => "view"

private def renderHandler (h : CpiEscrowHandlerIRV1) : String :=
  let entry := String.intercalate ";" (h.entryGlobalOps.map preflightOpKindNameV1).toList
  let body := String.intercalate ";" (h.bodyOps.map renderBodyOp).toList
  s!"handler:{h.handlerId}:{h.callableId}:{h.name}:{renderMode h.mode}:roles{h.localRoleCount}:probe{h.probeIxDataLen}:temps{h.tempCount}:entry[{entry}]:body[{body}]"

private def renderCandidate (c : SolanaCpiEscrowIRCandidateV1) : CompileResult String := do
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

/-- Validate escrow custom checks against following invoke. Public so focused
    tests can mutate structural candidates without forging authority.
    Accepts preactivation (`escrowIrSchemaV1`) or product (`productIrSchemaV1`). -/
def validateSolanaCpiEscrowIRCandidateV1
    (candidate : SolanaCpiEscrowIRCandidateV1) : CompileResult Unit := do
  unless candidate.schema == escrowIrSchemaV1 ||
      candidate.schema == productIrSchemaV1 do
    tFail s!"schema must be {escrowIrSchemaV1} or {productIrSchemaV1}"
  unless candidate.maxOuterRoles == maxOuterRolesV1 &&
      candidate.maxFrameBytes == 4096 &&
      candidate.abiLayout == frozenLoaderV3AbiLayoutV1 do
    tFail "Escrow IR caps/ABI must equal frozen v1"
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
      | .siteArgChecks sid _checks =>
          unless i + 2 < ops.size do
            tFail s!"siteArgChecks {sid} not followed by siteChecks+invoke"
          match ops[i + 1]!, ops[i + 2]! with
          | .siteChecks sid2 _, .invokeEscrow inv =>
              unless sid2 == sid && inv.siteId == sid do
                tFail s!"siteArgChecks {sid} following site id diverged"
          | _, _ => tFail s!"siteArgChecks {sid} must precede siteChecks→invokeEscrow"
      | .siteChecks sid checks =>
          if i == 0 || i + 1 ≥ ops.size then
            tFail s!"siteChecks {sid} lacks adjacent guards/invoke"
          match ops[i - 1]!, ops[i + 1]! with
          | .siteArgChecks sid0 _, .invokeEscrow inv =>
              unless sid0 == sid && inv.siteId == sid do
                tFail s!"siteChecks {sid} adjacent site id diverged"
              match inv.kind with
              | .transferChecked | .transferCheckedPda =>
                  let some src := inv.source |
                    tFail s!"site {sid}: token invoke missing source"
                  let some mint := inv.mint |
                    tFail s!"site {sid}: token invoke missing mint"
                  let some dest := inv.destination |
                    tFail s!"site {sid}: token invoke missing destination"
                  let some decimals := inv.decimals |
                    tFail s!"site {sid}: token invoke missing decimals"
                  let ownerLocal ← match inv.kind, inv.authority, inv.authorityPda with
                    | .transferChecked, some a, none => pure a.localIndex
                    | .transferCheckedPda, none, some a => pure a.localIndex
                    | _, _, _ => tFail s!"site {sid}: authority binding diverged"
                  unless checks.any (fun
                      | .tokenAccountStateInitialized li => li == src.localIndex
                      | _ => false) do
                    tFail s!"site {sid}: missing source stateInitialized"
                  unless checks.any (fun
                      | .tokenAccountMintEqualsRole acc m =>
                          acc == src.localIndex && m == mint.localIndex
                      | _ => false) do
                    tFail s!"site {sid}: missing source mintEqualsRole"
                  unless checks.any (fun
                      | .tokenAccountOwnerEqualsRole acc o =>
                          acc == src.localIndex && o == ownerLocal
                      | _ => false) do
                    tFail s!"site {sid}: missing source ownerEqualsRole"
                  unless checks.any (fun
                      | .tokenAccountDelegateNone li => li == src.localIndex
                      | _ => false) do
                    tFail s!"site {sid}: missing source delegateNone"
                  unless checks.any (fun
                      | .tokenAccountStateInitialized li => li == dest.localIndex
                      | _ => false) do
                    tFail s!"site {sid}: missing destination stateInitialized"
                  unless checks.any (fun
                      | .tokenAccountMintEqualsRole acc m =>
                          acc == dest.localIndex && m == mint.localIndex
                      | _ => false) do
                    tFail s!"site {sid}: missing destination mintEqualsRole"
                  unless checks.any (fun
                      | .tokenMintInitialized li => li == mint.localIndex
                      | _ => false) do
                    tFail s!"site {sid}: missing mint initialized"
                  unless checks.any (fun
                      | .tokenMintDecimalsEquals li srcD =>
                          li == mint.localIndex && srcD == decimals
                      | _ => false) do
                    tFail s!"site {sid}: missing mint decimalsEquals"
              | .createIdempotent =>
                  let some ataB := inv.ata | tFail s!"site {sid}: ATA invoke missing ata"
                  let some walletB := inv.wallet | tFail s!"site {sid}: ATA invoke missing wallet"
                  let some mintB := inv.mint | tFail s!"site {sid}: ATA invoke missing mint"
                  let some sysL := inv.systemProgramLocalIndex |
                    tFail s!"site {sid}: ATA missing system local"
                  let some tokL := inv.tokenProgramLocalIndex |
                    tFail s!"site {sid}: ATA missing token local"
                  unless checks.any (fun
                      | .ataAddressCanonical ata wallet token mint program =>
                          ata == ataB.localIndex && wallet == walletB.localIndex &&
                          token == tokL && mint == mintB.localIndex &&
                          program == inv.programLocalIndex
                      | _ => false) do
                    tFail s!"site {sid}: ATA address-check does not exact-join invoke"
                  unless checks.any (fun
                      | .ataAccountPrestateClosed ata wallet mint system token =>
                          ata == ataB.localIndex && wallet == walletB.localIndex &&
                          mint == mintB.localIndex && system == sysL && token == tokL
                      | _ => false) do
                    tFail s!"site {sid}: ATA prestate does not exact-join invoke"
                  unless checks.any (fun
                      | .tokenMintInitialized li => li == mintB.localIndex
                      | _ => false) do
                    tFail s!"site {sid}: ATA mint initialized check missing"
              | .createPdaAccount | .transfer | .nativeDeposit | .nativeTransfer
              | .pfAssetsTokenTransfer =>
                  pure ()
          | _, _ => tFail s!"siteChecks {sid} must be between siteArgChecks and invokeEscrow"
      | .invokeEscrow inv =>
          unless inv.accountInfoCount == h.localRoleCount do
            tFail s!"invokeEscrow site {inv.siteId} accountInfoCount diverged"
          match inv.kind with
          | .transfer =>
              unless inv.qn == "solana.system.transfer" &&
                  inv.packageId == "system-v1" && inv.dataLen == 12 &&
                  inv.metas.size == 2 && inv.outerOnly.isEmpty &&
                  inv.signerGroupId.isNone && inv.pdaRule.isNone &&
                  inv.payer.isSome && inv.destination.isSome &&
                  inv.lamports.isSome do
                tFail s!"system.transfer site {inv.siteId} frozen shape diverged"
          | .transferChecked =>
              unless inv.qn == "solana.token.transferChecked" &&
                  inv.packageId == "token-classic-v1" && inv.dataLen == 10 &&
                  inv.metas.size == 4 && inv.outerOnly.isEmpty &&
                  inv.signerGroupId.isNone && inv.pdaRule.isNone &&
                  inv.source.isSome && inv.mint.isSome && inv.destination.isSome &&
                  inv.authority.isSome && inv.amount.isSome && inv.decimals.isSome do
                tFail s!"transferChecked site {inv.siteId} frozen shape diverged"
          | .transferCheckedPda =>
              unless inv.qn == "solana.token.transferCheckedPda" &&
                  inv.packageId == "token-classic-v1" && inv.dataLen == 10 &&
                  inv.metas.size == 4 && inv.outerOnly.size == 1 &&
                  inv.signerGroupId == some 0 &&
                  inv.pdaRule == some "current-program-tagged-v1" &&
                  inv.source.isSome && inv.mint.isSome && inv.destination.isSome &&
                  inv.authorityPda.isSome && inv.seedAuthority.isSome &&
                  inv.seedTag.isSome && inv.bump.isSome &&
                  inv.amount.isSome && inv.decimals.isSome do
                tFail s!"transferCheckedPda site {inv.siteId} frozen shape diverged"
              match inv.bump with
              | some (.literal 0) =>
                  tFail s!"transferCheckedPda site {inv.siteId} bump literal 0 rejected"
              | _ => pure ()
          | .createPdaAccount =>
              unless inv.qn == "solana.system.createPdaAccount" &&
                  inv.packageId == "system-v1" && inv.dataLen == 52 &&
                  inv.metas.size == 2 && inv.outerOnly.size == 1 &&
                  inv.signerGroupId == some 0 &&
                  inv.pdaRule == some "current-program-tagged-v1" &&
                  inv.payer.isSome && inv.pda.isSome && inv.seedAuthority.isSome &&
                  inv.seedTag.isSome && inv.bump.isSome &&
                  inv.lamports.isSome && inv.space.isSome do
                tFail s!"createPdaAccount site {inv.siteId} frozen shape diverged"
              match inv.bump with
              | some (.literal 0) =>
                  tFail s!"createPdaAccount site {inv.siteId} bump literal 0 rejected"
              | _ => pure ()
          | .createIdempotent =>
              unless inv.qn == "solana.ata.createIdempotent" &&
                  inv.packageId == "ata-classic-v1" && inv.dataLen == 1 &&
                  inv.metas.size == 6 && inv.outerOnly.isEmpty &&
                  inv.signerGroupId.isNone &&
                  inv.pdaRule == some "ata-classic-v1" &&
                  inv.payer.isSome && inv.ata.isSome && inv.wallet.isSome &&
                  inv.mint.isSome && inv.systemProgramLocalIndex.isSome &&
                  inv.tokenProgramLocalIndex.isSome do
                tFail s!"createIdempotent site {inv.siteId} frozen shape diverged"
          | .nativeDeposit =>
              unless inv.qn == "pf.assets.native.deposit" &&
                  inv.packageId == "system-v1" && inv.dataLen == 12 &&
                  inv.metas.size == 2 && inv.outerOnly.isEmpty &&
                  inv.signerGroupId.isNone &&
                  inv.pdaRule == some vaultPdaRuleIdV1 &&
                  inv.payer.isSome && inv.destination.isSome &&
                  inv.pda.isSome && inv.lamports.isSome do
                tFail s!"nativeDeposit site {inv.siteId} frozen shape diverged"
          | .nativeTransfer =>
              unless inv.qn == "pf.assets.native.transfer" &&
                  inv.packageId == "system-v1" && inv.dataLen == 12 &&
                  inv.metas.size == 2 && inv.outerOnly.isEmpty &&
                  inv.signerGroupId == some 0 &&
                  inv.pdaRule == some vaultPdaRuleIdV1 &&
                  inv.payer.isSome && inv.destination.isSome &&
                  inv.pda.isSome && inv.lamports.isSome do
                tFail s!"nativeTransfer site {inv.siteId} frozen shape diverged"
          | .pfAssetsTokenTransfer =>
              unless inv.qn == "pf.assets.token.transfer" &&
                  inv.packageId == "token-classic-v1" && inv.dataLen == 10 &&
                  inv.metas.size == 4 && inv.outerOnly.isEmpty &&
                  inv.signerGroupId == some 0 &&
                  inv.pdaRule == some vaultPdaRuleIdV1 &&
                  inv.source.isSome && inv.mint.isSome && inv.destination.isSome &&
                  inv.authorityPda.isSome && inv.pda.isSome &&
                  inv.amount.isSome && inv.decimals.isSome do
                tFail s!"pfAssetsTokenTransfer site {inv.siteId} frozen shape diverged"
          if i < 2 then
            tFail s!"invokeEscrow site {inv.siteId} missing preceding siteArgChecks/siteChecks"
          else
            match ops[i - 2]!, ops[i - 1]! with
            | .siteArgChecks sidA _, .siteChecks sidC _ =>
                unless sidA == inv.siteId && sidC == inv.siteId do
                  tFail s!"invokeEscrow site {inv.siteId} preceding site id mismatch"
            | _, _ =>
                tFail s!"invokeEscrow site {inv.siteId} must be preceded by siteArgChecks→siteChecks"
      | _ => pure ()
  pure ()

/-- Sole mint of the #124 composite escrow execution IR from Semantic-bound Plan. -/
def resolveSolanaCpiEscrowIRV1
    (authority : SolanaCpiPreflightPlanV1) :
    CompileResult ResolvedSolanaCpiEscrowIRV1 := do
  unless ResolvedSolanaCpiPreflightV1.activationDeniedOf
      (SolanaCpiPreflightPlanV1.preflightOf authority) do
    tFail "Escrow CPI IR requires activationDenied preflight carrier"
  let candidate ← projectEscrowCandidate authority
  validateSolanaCpiEscrowIRCandidateV1 candidate
  let text ← renderCandidate candidate
  let canonicalBytes := text.toUTF8
  let digest ← mapExcept
    (domainSeparatedSha256 escrowIrDigestDomainV1 canonicalBytes)
    "escrow-ir digest"
  pure ⟨authority, candidate, canonicalBytes, digest⟩

/-- Sole mint of the #125 product composite IR from product Plan authority.
    Public structural Plan/IR and preflight carriers cannot mint this. -/
def resolveSolanaCpiProductIRV1
    (authority : SolanaCpiProductPlanV1) :
    CompileResult ResolvedSolanaCpiProductIRV1 := do
  unless !ResolvedSolanaCpiProductCapabilityV1.activationDeniedOf
      (SolanaCpiProductPlanV1.capabilityOf authority) do
    tFail "Product CPI IR rejects activationDenied product capability"
  let plan := SolanaCpiProductPlanV1.planOf authority
  let compiled :=
    ResolvedSolanaCpiProductCapabilityV1.compiledOf
      (SolanaCpiProductPlanV1.capabilityOf authority)
  let candidate ← projectEscrowCandidateFromPlan plan compiled productIrSchemaV1
  validateSolanaCpiEscrowIRCandidateV1 candidate
  let text ← renderCandidate candidate
  let canonicalBytes := text.toUTF8
  let digest ← mapExcept
    (domainSeparatedSha256 productIrDigestDomainV1 canonicalBytes)
    "product-ir digest"
  pure ⟨authority, candidate, canonicalBytes, digest⟩

/-- system.transfer scratch: 16 data + 32 metas + 40 instr + 56*N infos = 88+56N. -/
def escrowCpiScratchTransferV1 (localRoleCount : Nat) : Nat :=
  88 + localRoleCount * 56

/-- transferChecked scratch: 16 data + 64 metas + 40 instr + 56*N infos = 120+56N. -/
def escrowCpiScratchTransferCheckedV1 (localRoleCount : Nat) : Nat :=
  120 + localRoleCount * 56

/-- transferCheckedPda scratch layout (see EmitCpiTokenSbpfV1):
    +0 data16, +16 seed0/24, +40 seedTag, +48 bump,
    +56 SolSignerSeed[4], +120 SolSignerSeeds, +136 Meta[4],
    +200 Instruction, +240 Infos, +240+56N keyOut, +272+56N bumpOut
    end = 280 + 56*N. -/
def escrowCpiScratchTransferCheckedPdaV1 (localRoleCount : Nat) : Nat :=
  280 + localRoleCount * 56

/-- createPdaAccount scratch exclusive end (see EmitCpiEscrowSbpfV1 layout):
    +0 data64, +64 seed0/24, +88 seedTag, +96 bump,
    +104 SolSignerSeed[4], +168 SolSignerSeeds, +184 Meta[2],
    +216 Instruction, +256 Infos[56*N], +256+56N keyOut32,
    +288+56N bumpOut1 → exclusive end = 289 + 56*N. -/
def escrowCpiScratchCreatePdaAccountV1 (localRoleCount : Nat) : Nat :=
  289 + localRoleCount * 56

/-- ATA createIdempotent scratch = 240 + 56*N. -/
def escrowCpiScratchCreateIdempotentV1 (localRoleCount : Nat) : Nat :=
  240 + localRoleCount * 56

/-- ADR-0030 E1b: pfAssetsTokenTransfer composite scratch. The Token
    transferCheckedPda step (step 6) has the largest exclusive end:
    +240 infos[56*N], +256+56N keyOut[32], +288+56N bumpOut[1] → 289+56N.
    ATA address find steps end at +129; ATA CPI steps end at 240+56N. -/
def escrowCpiScratchPfAssetsTokenTransferV1 (localRoleCount : Nat) : Nat :=
  289 + localRoleCount * 56

def escrowMaxSiteScratchV1 (c : SolanaCpiEscrowIRCandidateV1) : Nat :=
  Id.run do
    let mut maxB : Nat := 0
    for h in c.handlers do
      for op in h.bodyOps do
        match op with
        | .invokeEscrow inv =>
            let b := match inv.kind with
              | .transfer =>
                  escrowCpiScratchTransferV1 inv.accountInfoCount
              | .nativeDeposit | .nativeTransfer =>
                  -- vault ensure (create) + transfer / signed transfer share create scratch
                  escrowCpiScratchCreatePdaAccountV1 inv.accountInfoCount
              | .transferChecked =>
                  escrowCpiScratchTransferCheckedV1 inv.accountInfoCount
              | .transferCheckedPda =>
                  escrowCpiScratchTransferCheckedPdaV1 inv.accountInfoCount
              | .createPdaAccount =>
                  escrowCpiScratchCreatePdaAccountV1 inv.accountInfoCount
              | .createIdempotent =>
                  escrowCpiScratchCreateIdempotentV1 inv.accountInfoCount
              | .pfAssetsTokenTransfer =>
                  -- Composite ATA ensure ×2 + transferCheckedPda; the Token
                  -- step has the largest scratch end (289+56N).
                  escrowCpiScratchPfAssetsTokenTransferV1 inv.accountInfoCount
            if b > maxB then maxB := b
        | .envReadVaultBalance _ kind _ _ _ _ _ _ =>
            -- envRead scratch: vault PDA find (seed0+104+keyOut256+bumpOut288
            -- = 296) + ATA find for token (seeds136 = max 136). Native uses
            -- 296; token uses max(296, 136) = 296.
            let b := 296
            if b > maxB then maxB := b
        | _ => pure ()
    pure maxB

/-- Shared frame constants for escrow emitter (role table + temps).
    Exact numeric values match #118–#123 preflight layout without importing
    the preflight emitter module (avoids IR↔emit cycle). -/
def escrowRoleTableBytesV1 : Nat := 1024
def escrowRoleStrideV1 : Nat := 64
def escrowMaxRolesV1 : Nat := maxOuterRolesV1
def escrowTempBaseV1 : Nat := 1096
def escrowMaxTempsV1 : Nat := 16
def escrowTempRegionEndV1 : Nat := escrowTempBaseV1 + escrowMaxTempsV1 * 8
def escrowCpiBaseMinV1 : Nat := 1600
def escrowMaxFrameBytesV1 : Nat := 4096

end ProofForgeV2.Targets.Solana.CpiV1

/-
  Tests.Materialization.SolanaCpiPreflightV1 — #118 concrete preflight IR/emitter.

  Ordinary registered suite. Positive emission goes through real
  Loader→compile→resolve preflight→Semantic-derived Plan authority (state +
  system.transfer + companion.invoke multi-handler). Structural hand-built
  Plan may exercise pure projection/mutations but is type-ineligible for the
  emitter.

  Pins: loader-owner base58/raw, concrete state/site ops, exact-8 probe,
  wrap-guard text, no comment-only policy markers, deterministic text/digest.
-/
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.EmitCpiPreflightSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiPreflightV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectOk {α : Type} (result : Except String α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def expectPlanOk {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def expectPlanReject {α : Type} (result : CompileResult α)
    (label : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == "PF-PLAN-INVARIANT")
        s!"{label}: expected PF-PLAN-INVARIANT, got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly accepted"

private def expectPlanRejectContains {α : Type} (result : CompileResult α)
    (needle label : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == "PF-PLAN-INVARIANT" && error.message.contains needle)
        s!"{label}: expected PF-PLAN-INVARIANT containing '{needle}', got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly accepted"

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def digestDiff (left right : Digest) : Bool :=
  !(left.algorithm == right.algorithm && left.bytes == right.bytes)

private def packageRoleName (packageId : String) : String :=
  packageId.replace "-" "_" ++ "_program"

private def extensionHeader : String :=
  "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
  "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n"

private def wrapProgram (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  s!"program {name} where\n" ++
  extensionHeader ++
  body

/-- Multi-handler authority source: state + system.transfer + companion.invoke
    (init, two entries, no-call view). -/
private def multiHandlerSource : String :=
  wrapProgram "CpiPreflightMulti" <|
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry transfer(payer : Principal, recipient : Principal,\n" ++
    "      lamports : UInt64) : UInt64 do\n" ++
    "    call solana.system.transfer(payer, recipient, lamports)\n" ++
    "    return 0\n" ++
    "  entry invoke(account : Principal, delta : UInt64) : UInt64 do\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    return 0\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"

private def systemCreatePdaSource : String :=
  wrapProgram "CpiPreflightCreatePda" <|
    "  entry createPda(payer: Principal, pda: Principal,\n" ++
    "      seedAuthority: Principal, seedTag: UInt64, bump: UInt8,\n" ++
    "      lamports: UInt64, space: UInt64) : UInt64 do\n" ++
    "    call solana.system.createPdaAccount(payer, pda, seedAuthority,\n" ++
    "      seedTag, bump, lamports, space)\n" ++
    "    return 0\n"

private def companionInvokeSignedSource : String :=
  wrapProgram "CpiPreflightInvokeSigned" <|
    "  entry invokeSigned(account: Principal, authorityPda: Principal,\n" ++
    "      seedAuthority: Principal, seedTag: UInt64, bump: UInt8,\n" ++
    "      delta: UInt64) : UInt64 do\n" ++
    "    call solana.companion.invokeSigned(account, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    return 0\n"

private def tokenTransferCheckedSource : String :=
  wrapProgram "CpiPreflightToken" <|
    "  entry transferChecked(source: Principal, mint: Principal,\n" ++
    "      destination: Principal, authority: Principal,\n" ++
    "      amount: UInt64, decimals: UInt8) : UInt64 do\n" ++
    "    call solana.token.transferChecked(source, mint, destination,\n" ++
    "      authority, amount, decimals)\n" ++
    "    return 0\n"

private def ataCreateIdempotentSource : String :=
  wrapProgram "CpiPreflightAta" <|
    "  entry createIdempotent(payer: Principal, ata: Principal,\n" ++
    "      wallet: Principal, mint: Principal) : UInt64 do\n" ++
    "    call solana.ata.createIdempotent(payer, ata, wallet, mint)\n" ++
    "    return 0\n"

private unsafe def compileSource
    (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let (src, origins) ← match ← session.selectProgramV1WithOrigins
      source path moduleName none with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"load {moduleName}: {error.render}"
  match Compiler.compileProgramProductV1 src origins with
  | .ok compiled => pure compiled
  | .error _bundle =>
      throw <| IO.userError s!"compile {moduleName}: product compile failed"

private def cpiSelection : IO ResolvedBuildSelectionV1 :=
  expectPlanOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "select solana-sbpf-cpi-elf-v1"

private unsafe def authorityOf
    (session : Language.Loader.ParserSession)
    (source moduleName : String) : IO SolanaCpiPreflightPlanV1 := do
  let compiled ← compileSource session source moduleName
    s!"<cpi-preflight-{moduleName}>"
  let selection ← cpiSelection
  let preflight ← expectPlanOk (resolveSolanaCpiPreflightV1 selection compiled)
    s!"preflight {moduleName}"
  expectPlanOk (deriveSolanaCpiPlanFromPreflightV1 preflight)
    s!"derive {moduleName}"

/-- Test-only structural candidate from a frozen API (mirrors #117 helper).
    Type-ineligible for the emitter (no SolanaCpiPreflightPlanV1). -/
private def candidateForApi
    (api : FrozenApi) : Except String SolanaCpiPlanCandidateV1 := do
  let profileDigest ← expectedProfileDigestV1
  let catalogDigest ← expectedCatalogDigestV1
  let extensionRequirement ← expectedExtensionRequirementV1
  let package ← match findCalleePackage? api.fixedProgram with
    | some value => pure value
    | none => throw s!"missing package {api.fixedProgram}"

  let mut roles : Array AccountRoleSchemaV1 := #[]
  let mut argRoles : Array (String × Nat) := #[]
  for (arg, argIndex) in api.args.zipIdx do
    if arg.type_ == .principal then
      let roleId := roles.size
      roles := roles.push {
        roleId
        name := arg.name
        keyPolicy := .accountParameter 0 argIndex
        constraint := accountBoundRoleConstraintV1
        aliasPolicy := frozenAliasPolicyV1
      }
      argRoles := argRoles.push (arg.name, roleId)

  let mut fixedRoles : Array (String × Nat) := #[]
  let calleeRoleId := roles.size
  roles := roles.push {
    roleId := calleeRoleId
    name := packageRoleName api.fixedProgram
    keyPolicy := .fixedProgram api.fixedProgram
    constraint := calleeRoleConstraintV1
    aliasPolicy := frozenAliasPolicyV1
  }
  fixedRoles := fixedRoles.push (api.fixedProgram, calleeRoleId)
  for metaSpec in api.metas do
    match metaSpec.binding with
    | .arg _ => pure ()
    | .vaultPda | .handlerCaller | .vaultAta | .dstAta => pure ()
    | .fixedProgram packageId =>
        unless fixedRoles.any (fun pair => pair.1 == packageId) do
          let roleId := roles.size
          roles := roles.push {
            roleId
            name := packageRoleName packageId
            keyPolicy := .fixedProgram packageId
            constraint := calleeRoleConstraintV1
            aliasPolicy := frozenAliasPolicyV1
          }
          fixedRoles := fixedRoles.push (packageId, roleId)

  let mut args : Array CpiArgumentBindingV1 := #[]
  for (spec, valueId) in api.args.zipIdx do
    let roleId ← if spec.type_ == .principal then
      match argRoles.find? (fun pair => pair.1 == spec.name) with
      | some pair => pure (some pair.2)
      | none => throw s!"missing role for arg {spec.name}"
    else pure none
    args := args.push { spec, semanticValueId := valueId, roleId }

  let mut metas : Array CpiMetaPlanV1 := #[]
  for (spec, metaIndex) in api.metas.zipIdx do
    let roleId ← match spec.binding with
      | .arg name =>
          match argRoles.find? (fun pair => pair.1 == name) with
          | some pair => pure pair.2
          | none => throw s!"missing meta arg role {name}"
      | .fixedProgram packageId =>
          match fixedRoles.find? (fun pair => pair.1 == packageId) with
          | some pair => pure pair.2
          | none => throw s!"missing fixed meta role {packageId}"
      | .vaultPda | .handlerCaller | .vaultAta | .dstAta =>
          throw "synthetic vault/caller/ata meta not supported in L2 fixture helper"
    metas := metas.push { metaIndex, roleId, spec }

  let mut outerOnly : Array CpiOuterOnlyPlanV1 := #[]
  for spec in api.outerOnlyAccounts do
    let roleId ← match argRoles.find? (fun pair => pair.1 == spec.arg) with
      | some pair => pure pair.2
      | none => throw s!"missing outer-only role {spec.arg}"
    outerOnly := outerOnly.push { roleId, spec }

  let mut uses : Array HandlerAccountUseV1 := #[]
  for (role, position) in roles.zipIdx do
    let mut signer := false
    let mut writable := false
    for metaPlan in metas do
      if metaPlan.roleId == role.roleId then
        if metaPlan.spec.outerSignerContribution then signer := true
        if metaPlan.spec.outerWritableContribution then writable := true
    for outer in outerOnly do
      if outer.roleId == role.roleId then
        if outer.spec.outerSignerContribution then signer := true
        if outer.spec.outerWritableContribution then writable := true
    uses := uses.push {
      position
      roleId := role.roleId
      directSignerContribution := false
      directWritableContribution := false
      outerSigner := signer
      outerWritable := writable
    }

  let mut predicates : Array SiteAccountPredicateV1 := #[{
    source := .callee
    roleId := calleeRoleId
    constraint := calleeRoleConstraintV1
  }]
  for (metaPlan, index) in metas.zipIdx do
    predicates := predicates.push {
      source := .metaIndex index
      roleId := metaPlan.roleId
      constraint := metaPlan.spec.constraint
    }
  for (outer, index) in outerOnly.zipIdx do
    predicates := predicates.push {
      source := .outerOnlyIndex index
      roleId := outer.roleId
      constraint := outer.spec.constraint
    }

  let site : CpiSitePlanV1 := {
    siteId := 0
    handlerId := 0
    anchor := { callableId := 0, blockId := 0, instructionIndex := 0, effectId := 0 }
    qn := api.qn
    packageId := api.fixedProgram
    programRoleId := calleeRoleId
    programKey := package.programId
    args
    instructionCodec := api.instructionCodec
    metas
    outerOnlyAccounts := outerOnly
    accountInfoRoleIds := uses.map (·.roleId)
    signerGroups := api.signerGroups
    pda := api.pda
    preflight := api.preflight
    sitePredicates := predicates
    returnDataPolicy := propagateImmediatelyReturnDataPolicyV1
    failurePolicy := propagateImmediatelyFailurePolicyV1
  }
  pure {
    schema := planSchemaV1
    profileId := profileIdV1
    profileDigest
    extensionRequirement
    calleeCatalogDigest := catalogDigest
    programName := "CpiPreflightProbe"
    stateSchemas := #[]
    pdaRules := frozenPdaRulesV1
    accountRoles := roles
    handlers := #[{
      handlerId := 0
      callableId := 0
      name := "invoke"
      mode := .entry
      accountUses := uses
      cpiSiteIds := #[0]
    }]
    cpiSites := #[site]
    envReadSites := #[]
    contextReadSites := #[]
    computeAssumptions := frozenComputeAssumptionsV1
  }

/-- Single-state-role structural candidate (N=1). -/
private def oneRoleStateCandidate : Except String SolanaCpiPlanCandidateV1 := do
  let profileDigest ← expectedProfileDigestV1
  let catalogDigest ← expectedCatalogDigestV1
  let extensionRequirement ← expectedExtensionRequirementV1
  let layoutDigest ← domainSeparatedSha256 "pf.test.solana-preflight-layout.v1" "state".toUTF8
  unless layoutDigest.bytes.size == 32 do
    throw "layoutDigest must be 32 bytes"
  let marker : UInt64 := Id.run do
    let mut value : UInt64 := 0
    for index in [0:8] do
      value := UInt64.shiftLeft value 8 ||| layoutDigest.bytes[index]!.toUInt64
    pure value
  pure {
    schema := planSchemaV1
    profileId := profileIdV1
    profileDigest
    extensionRequirement
    calleeCatalogDigest := catalogDigest
    programName := "PreflightN1"
    stateSchemas := #[{
      schemaId := 0
      name := "state"
      exactDataLen := 16
      layoutDigest
      initializedMarker := marker
    }]
    pdaRules := frozenPdaRulesV1
    accountRoles := #[{
      roleId := 0
      name := "state"
      keyPolicy := .state 0
      constraint := stateRoleConstraintV1
      aliasPolicy := frozenAliasPolicyV1
    }]
    handlers := #[{
      handlerId := 0
      callableId := 0
      name := "probe"
      mode := .entry
      accountUses := #[{
        position := 0
        roleId := 0
        directSignerContribution := false
        directWritableContribution := true
        outerSigner := false
        outerWritable := true
      }]
      cpiSiteIds := #[]
    }]
    cpiSites := #[]
    envReadSites := #[]
    contextReadSites := #[]
    computeAssumptions := frozenComputeAssumptionsV1
  }

/-! ## Loader owner base58/raw pins -/

private def testLoaderOwnerPubkeys : IO Unit := do
  expect (SolanaPubkeyV1.toBytes loaderV3OwnerProgramIdV1 ==
      ByteArray.mk #[
        0x02, 0xa8, 0xf6, 0x91, 0x4e, 0x88, 0xa1, 0xb0,
        0xe2, 0x10, 0x15, 0x3e, 0xf7, 0x63, 0xae, 0x2b,
        0x00, 0xc2, 0xb9, 0x3d, 0x16, 0xc1, 0x24, 0xd2,
        0xc0, 0x53, 0x7a, 0x10, 0x04, 0x80, 0x00, 0x00])
    "Loader V3 owner raw bytes"
  expect (SolanaPubkeyV1.toBytes nativeLoaderOwnerProgramIdV1 ==
      ByteArray.mk #[
        0x05, 0x87, 0x84, 0xbf, 0x14, 0x8b, 0xa4, 0x28,
        0x2f, 0xb0, 0x12, 0x57, 0x48, 0x88, 0xa9, 0xf1,
        0x53, 0xa0, 0x7d, 0xad, 0xf7, 0x65, 0xc0, 0x45,
        0x5c, 0x9a, 0x97, 0x03, 0x80, 0x00, 0x00, 0x00])
    "Native Loader owner raw bytes"
  let loaderParsed ← expectOk (SolanaPubkeyV1.parseBase58 loaderV3OwnerBase58V1)
    "parse Loader V3 base58"
  let nativeParsed ← expectOk (SolanaPubkeyV1.parseBase58 nativeLoaderOwnerBase58V1)
    "parse Native Loader base58"
  expect (loaderParsed == loaderV3OwnerProgramIdV1)
    "Loader V3 base58 ↔ raw identity"
  expect (nativeParsed == nativeLoaderOwnerProgramIdV1)
    "Native Loader base58 ↔ raw identity"
  expect (SolanaPubkeyV1.toBase58 loaderV3OwnerProgramIdV1 == loaderV3OwnerBase58V1)
    "Loader V3 re-encode base58"
  expect (SolanaPubkeyV1.toBase58 nativeLoaderOwnerProgramIdV1 == nativeLoaderOwnerBase58V1)
    "Native Loader re-encode base58"
  expect (executionClassOwnerPubkeyV1 .loaderV3Sbpf == loaderV3OwnerProgramIdV1)
    "executionClass loaderV3Sbpf → Loader V3 owner"
  expect (executionClassOwnerPubkeyV1 .nativeSystem == nativeLoaderOwnerProgramIdV1)
    "executionClass nativeSystem → Native Loader owner"

/-! ## Authority multi-handler → resolved IR → concrete assembly -/

private unsafe def testAuthorityMultiHandlerEmission
    (session : Language.Loader.ParserSession) : IO Unit := do
  let authority ← authorityOf session multiHandlerSource "Tests.CpiPreflightMulti"
  let plan := SolanaCpiPreflightPlanV1.planOf authority
  let c := plan.candidate
  expect (c.handlers.size == 4) "init + transfer + invoke + get"
  expect (c.stateSchemas.size == 1) "one state schema"
  expect (c.cpiSites.size == 2) "transfer + invoke sites"
  let some schema := c.stateSchemas[0]? |
    throw <| IO.userError "missing state schema"

  let resolved ← expectPlanOk (resolveSolanaCpiPreflightIRV1 authority)
    "resolve preflight IR"
  let pf := ResolvedSolanaCpiPreflightIRV1.validatedOf resolved
  expect (pf.candidate.handlers.size == 4) "four preflight handlers"
  expect (pf.candidate.abiLayout == frozenLoaderV3AbiLayoutV1) "frozen ABI"

  -- Init handler: state header zero + exact data len + current-program owner.
  let some initH := pf.candidate.handlers.find? (·.mode == .initialize) |
    throw <| IO.userError "missing init handler"
  expect (initH.ops.any fun
    | .checkStateHeaderZero _ => true | _ => false)
    "init: checkStateHeaderZero"
  expect (initH.ops.any fun
    | .checkExactDataLen _ n => n == schema.exactDataLen | _ => false)
    "init: exact state data len"
  expect (initH.ops.any fun
    | .checkOwnerCurrentProgram _ => true | _ => false)
    "init: owner current program"
  expect (initH.ops.any fun
    | .checkExecutableForbidden _ => true | _ => false)
    "init: state executable forbidden"
  expect (!initH.ops.any fun
    | .checkStateHeaderMarker .. => true | _ => false)
    "init: no initialized marker check"

  -- View handler: state header marker (no CPI sites).
  let some viewH := pf.candidate.handlers.find? (·.mode == .view) |
    throw <| IO.userError "missing view handler"
  expect (viewH.ops.any fun
    | .checkStateHeaderMarker _ m => m == schema.initializedMarker | _ => false)
    "view: checkStateHeaderMarker"
  expect (viewH.ops.any fun
    | .checkOwnerCurrentProgram _ => true | _ => false)
    "view: owner current program"

  -- Transfer entry: Native Loader owner on system program + exact keys.
  let some xferH := pf.candidate.handlers.find? (·.name == "transfer") |
    throw <| IO.userError "missing transfer handler"
  expect (xferH.ops.any fun
    | .checkExactKey _ k => k == systemProgramIdV1 | _ => false)
    "transfer: system program exact key"
  expect (xferH.ops.any fun
    | .checkOwnerExact _ o => o == nativeLoaderOwnerProgramIdV1 | _ => false)
    "transfer: Native Loader owner for system program"
  expect (xferH.ops.any fun
    | .checkExactDataLen _ 0 => true | _ => false)
    "transfer: payer exactLength 0"
  expect (xferH.accountParameterBindings.size ≥ 2)
    "transfer: account-parameter bindings present"
  -- Principal params must not gain a fake exact-key check (Principal is
  -- synthesized from the role key at the ABI boundary).
  for b in xferH.accountParameterBindings do
    expect (!xferH.ops.any fun
      | .checkExactKey i _ => i == b.localIndex | _ => false)
      s!"transfer: no checkExactKey on param local {b.localIndex}"

  -- Invoke entry: Loader V3 owner + companion key + exactCounter 8.
  let some invH := pf.candidate.handlers.find? (·.name == "invoke") |
    throw <| IO.userError "missing invoke handler"
  expect (invH.ops.any fun
    | .checkExactKey _ k => k == companionProgramIdV1 | _ => false)
    "invoke: companion exact key"
  expect (invH.ops.any fun
    | .checkOwnerExact _ o => o == loaderV3OwnerProgramIdV1 | _ => false)
    "invoke: Loader V3 owner for companion program"
  expect (invH.ops.any fun
    | .checkExactDataLen _ 8 => true | _ => false)
    "invoke: companion counter exactLength 8"
  expect (invH.ops.any fun
    | .checkExecutableRequired _ => true | _ => false)
    "invoke: companion program executable required"

  -- No policy DTO residual kinds.
  let allKinds := pf.candidate.handlers.flatMap (fun h => h.ops.map preflightOpKindNameV1)
  expect (!allKinds.any (· == "deferredSitePredicate")) "no deferredSitePredicate"
  expect (!allKinds.any (· == "checkOwner")) "no generic checkOwner"
  expect (!allKinds.any (· == "checkData")) "no generic checkData"
  expect (!allKinds.any (· == "checkInitialization")) "no generic checkInitialization"
  expect (!allKinds.any (· == "checkProvisioning")) "no generic checkProvisioning"
  expect (!allKinds.any (· == "checkKeyPolicy")) "no generic checkKeyPolicy"

  -- Emit via resolved authority only.
  let asm ← expectPlanOk (emitCpiPreflightSbpfV1 resolved) "emit preflight asm"
  expect (!SolanaCpiPreflightAssemblyV1.isProductArtifact asm)
    "assembly is not a product artifact"
  expect (SolanaCpiPreflightAssemblyV1.isTestPreactivation asm)
    "assembly is test-preactivation"
  expect (SolanaCpiPreflightAssemblyV1.frameBytesOf asm == preflightFrameBytesV1)
    "frame bytes exact"
  expect (SolanaCpiPreflightAssemblyV1.frameBytesOf asm ≤ preflightMaxFrameBytesV1)
    "frame ≤ 4096"
  let text := SolanaCpiPreflightAssemblyV1.textOf asm
  expect (hasSubstr text "TEST-PREACTIVATION ONLY") "test-preactivation banner"
  expect (hasSubstr text "not a product artifact") "not product artifact banner"
  expect (hasSubstr text ".globl entrypoint") "probe entrypoint"
  expect (hasSubstr text "PROBE_IX_DATA_LEN, 8") "exact-8 probe equ"
  expect (hasSubstr text "jne r1, PROBE_IX_DATA_LEN, err_shape")
    "exact-8 probe check"
  expect (hasSubstr text "wrap-guard add") "wrap-guard text present"
  expect (hasSubstr text "cursor full prefix") "wrap-guard full prefix"
  expect (hasSubstr text "cursor data_len") "wrap-guard data_len"
  expect (hasSubstr text "cursor growth reserve") "wrap-guard growth"
  expect (hasSubstr text "cursor alignment pad" || hasSubstr text "alignment")
    "wrap-guard alignment path"
  expect (hasSubstr text
      "wrap-guard add-reg (cursor alignment pad)\n  lddw r0, 0xffffffffffffffff\n  sub64 r0, r3\n  jgt r5, r0, err_shape\n  add64 r5, r3")
    "alignment amount r3 survives reserved-r0 wrap scratch"
  expect (hasSubstr text
      "wrap-guard add 1 (padding byte)\n  lddw r0, 0xfffffffffffffffe\n  jgt r5, r0, err_shape\n  lddw r0, 0x1\n  add64 r5, r0\n  sub64 r3, 1")
    "zero-padding counter r3 survives reserved-r0 wrap scratch"
  expect (!hasSubstr text
      "lddw r3, 0xffffffffffffffff\n  sub64 r3, r3")
    "no amount/scratch self-alias"
  expect (hasSubstr text "cursor rent+8") "wrap-guard rent+8"
  expect (hasSubstr text "ix data pointer") "wrap-guard ix pointer"
  expect (hasSubstr text "program id +32") "wrap-guard program id"
  expect (hasSubstr text "pointer-table +8") "wrap-guard pointer table"
  expect (hasSubstr text "checkExactKey") "real exact key emission"
  expect (hasSubstr text "checkOwnerExact") "real owner exact emission"
  expect (hasSubstr text "checkOwnerCurrentProgram") "real current-program owner"
  expect (hasSubstr text "checkStateHeaderZero") "real state header zero"
  expect (hasSubstr text "checkStateHeaderMarker") "real state header marker"
  expect (hasSubstr text "checkExactDataLen") "real data len"
  expect (hasSubstr text "checkExecutableRequired") "real executable required"
  expect (hasSubstr text "checkExecutableForbidden") "real executable forbidden"
  expect (hasSubstr text "expectLocalRoleCount") "role count check"
  expect (hasSubstr text "pairwise distinct keys") "pairwise distinct"
  expect (hasSubstr text "ROLE_BASE") "role table"
  expect (hasSubstr text "ep_parse_role") "virtual walk parse loop"
  expect (hasSubstr text "ep_ptr_table") "pointer table"
  expect (!hasSubstr text "ACC0") "no ACC0"
  expect (!hasSubstr text "sol_invoke") "no sol_invoke"
  expect (!hasSubstr text "invoke_signed") "no invoke_signed"
  expect (!hasSubstr text "OutputFile") "no OutputFile"
  expect (!hasSubstr text "deferred-before-site") "no deferred policy comments"
  expect (!hasSubstr text "owner any local=") "no comment-only owner-any"
  expect (!hasSubstr text "; provisioning ") "no comment-only provisioning"
  expect (!hasSubstr text "; initialization ") "no comment-only initialization"
  expect (!hasSubstr text "; data notRead") "no comment-only notRead"
  expect (!hasSubstr text "; data catalogProgram") "no comment-only catalogProgram"
  -- Determinism.
  let asm2 ← expectPlanOk (emitCpiPreflightSbpfV1 resolved) "re-emit"
  expect (SolanaCpiPreflightAssemblyV1.textOf asm2 == text)
    "assembly text deterministic"
  let sections ← expectPlanOk (emitCpiPreflightHandlerSectionsV1 resolved)
    "handler sections only"
  let secText := SolanaCpiPreflightAssemblyV1.textOf sections
  expect (!hasSubstr secText ".globl entrypoint")
    "sections-only omits entrypoint"
  expect (!hasSubstr secText "ACC0") "sections no ACC0"
  -- Digest determinism of resolved IR.
  let resolved2 ← expectPlanOk (resolveSolanaCpiPreflightIRV1 authority)
    "re-resolve"
  expect (!digestDiff
      (ResolvedSolanaCpiPreflightIRV1.digestOf resolved)
      (ResolvedSolanaCpiPreflightIRV1.digestOf resolved2))
    "resolved preflight digest deterministic"

/-! ## Unsupported API preflight IR rejection (Plan may still validate) -/

private unsafe def testUnsupportedApiPreflightReject
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- createPda: PDA + systemCreateAccount + preflight arg predicate
  let authPda ← authorityOf session systemCreatePdaSource
    "Tests.CpiPreflightCreatePda"
  expectPlanRejectContains
    (resolveSolanaCpiPreflightIRV1 authPda) "PDA"
    "createPda preflight IR rejects PDA"
  -- Also structural path from validated Plan.
  let planPda := SolanaCpiPreflightPlanV1.planOf authPda
  expectPlanRejectContains
    (deriveSolanaCpiPreflightIRV1 planPda) "PDA"
    "createPda structural preflight rejects PDA"

  -- invokeSigned: PDA + signer groups
  let authSigned ← authorityOf session companionInvokeSignedSource
    "Tests.CpiPreflightInvokeSigned"
  expectPlanRejectContains
    (resolveSolanaCpiPreflightIRV1 authSigned) "PDA"
    "invokeSigned preflight IR rejects PDA"

  -- token: classicTokenAccount
  let authTok ← authorityOf session tokenTransferCheckedSource
    "Tests.CpiPreflightToken"
  expectPlanRejectContains
    (resolveSolanaCpiPreflightIRV1 authTok) "classicToken"
    "token preflight IR rejects classicToken"

  -- ATA: PDA address-check / closedPackages / ataAccount / ataCreateIdempotent.
  -- Site gate rejects non-none PDA first (addressCheckOnly); any of these
  -- closed surfaces is an honest preflight-emission rejection.
  let authAta ← authorityOf session ataCreateIdempotentSource
    "Tests.CpiPreflightAta"
  match resolveSolanaCpiPreflightIRV1 authAta with
  | .error error =>
      expect (error.code == "PF-PLAN-INVARIANT")
        s!"ATA preflight reject code: {error.render}"
      expect (
        error.message.contains "PDA" ||
        error.message.contains "ata" ||
        error.message.contains "ATA" ||
        error.message.contains "closedPackages" ||
        error.message.contains "ataCreate")
        s!"ATA preflight reject detail: {error.render}"
  | .ok _ => throw <| IO.userError "ATA preflight IR unexpectedly accepted"

/-! ## Structural companion.invoke projection (no emitter path) -/

private def testStructuralCompanionProjection : IO Unit := do
  let candidate ← expectOk (candidateForApi apiCompanionInvokeV1)
    "companion structural candidate"
  let plan ← expectPlanOk (validateSolanaCpiPlanV1 candidate) "companion plan"
  let pf ← expectPlanOk (deriveSolanaCpiPreflightIRV1 plan) "companion structural pf"
  let some h := pf.candidate.handlers[0]? |
    throw <| IO.userError "missing handler"
  expect (h.localRoleCount == 2) "account + companion program"
  expect (h.ops.any fun
    | .checkExactKey _ k => k == companionProgramIdV1 | _ => false)
    "structural: companion exact key"
  expect (h.ops.any fun
    | .checkOwnerExact _ o => o == loaderV3OwnerProgramIdV1 | _ => false)
    "structural: Loader V3 owner"
  expect (h.ops.any fun
    | .checkExactDataLen _ 8 => true | _ => false)
    "structural: exactCounter 8"
  expect (h.accountParameterBindings.size == 1)
    "structural: one account-parameter binding"
  -- Mutation reject.
  let c := pf.candidate
  let some h0 := c.handlers[0]? |
    throw <| IO.userError "handler missing"
  expectPlanReject (validateSolanaCpiPreflightIRV1 plan pf.ir
    { c with schema := "wrong" }) "schema drift"
  expectPlanReject (validateSolanaCpiPreflightIRV1 plan pf.ir
    { c with handlers := #[{ h0 with ops := h0.ops.pop }] }) "ops truncation"
  -- Hand-built ValidatedSolanaCpiPreflightIRV1 is not emitter input (type system:
  -- emitCpiPreflightSbpfV1 requires ResolvedSolanaCpiPreflightIRV1). Documented by
  -- absence of a public mint from ValidatedSolanaCpiPlanV1 into assembly.

/-! ## N=1 structural boundary; N=17 reject -/

private def testRoleCountBoundary : IO Unit := do
  expect (maxOuterRolesV1 == 16 && preflightMaxRolesV1 == 16)
    "product/walker max outer roles == 16"
  let cand1 ← expectOk oneRoleStateCandidate "N=1 candidate"
  let plan1 ← expectPlanOk (validateSolanaCpiPlanV1 cand1) "N=1 plan"
  let pf1 ← expectPlanOk (deriveSolanaCpiPreflightIRV1 plan1) "N=1 preflight"
  let some h1 := pf1.candidate.handlers[0]? |
    throw <| IO.userError "N=1: missing handler"
  expect (h1.localRoleCount == 1) "N=1: localRoleCount"
  expect (h1.ops[0]? == some (.expectLocalRoleCount 1))
    "N=1: expectLocalRoleCount op"
  expect (h1.ops.any fun
    | .checkOwnerCurrentProgram 0 => true | _ => false)
    "N=1: owner current program"
  expect (h1.ops.any fun
    | .checkExactDataLen 0 16 => true | _ => false)
    "N=1: exact data len 16"
  expect (h1.ops.any fun
    | .checkStateHeaderMarker 0 _ => true | _ => false)
    "N=1: entry mode state header marker"
  expect (h1.ops.any fun
    | .checkPairwiseDistinctKeys 1 => true | _ => false)
    "N=1: pairwise distinct op present"
  let bloated : CpiPreflightHandlerIRV1 := {
    h1 with
    localRoleCount := 17
    localRoleOrder := h1.localRoleOrder
    accountParameterBindings := #[]
    ops := #[.expectLocalRoleCount 17]
  }
  expectPlanReject (validateSolanaCpiPreflightIRV1 plan1 pf1.ir
    { pf1.candidate with handlers := #[bloated] })
    "mutated localRoleCount 17 rejected"
  expectPlanReject (validateSolanaCpiPreflightIRV1 plan1 pf1.ir
    { pf1.candidate with maxOuterRoles := 17 })
    "maxOuterRoles 17 rejected"

/-! ## Structural createPda preflight rejection (hand-built Plan) -/

private def testStructuralCreatePdaReject : IO Unit := do
  let candidate ← expectOk (candidateForApi apiSystemCreatePdaAccountV1)
    "createPda structural candidate"
  let plan ← expectPlanOk (validateSolanaCpiPlanV1 candidate) "createPda plan"
  -- Plan is structurally valid (#117) but preflight IR derivation fails closed.
  expectPlanRejectContains
    (deriveSolanaCpiPreflightIRV1 plan) "PDA"
    "structural createPda preflight rejects PDA"

/-! ## Structural system.transfer owner resolution -/

private def testStructuralSystemTransferOwners : IO Unit := do
  let candidate ← expectOk (candidateForApi apiSystemTransferV1)
    "system transfer candidate"
  let plan ← expectPlanOk (validateSolanaCpiPlanV1 candidate) "system transfer plan"
  let pf ← expectPlanOk (deriveSolanaCpiPreflightIRV1 plan) "system transfer pf"
  let some h := pf.candidate.handlers[0]? |
    throw <| IO.userError "missing transfer handler"
  expect (h.ops.any fun
    | .checkExactKey _ k => k == systemProgramIdV1 | _ => false)
    "system exact key"
  expect (h.ops.any fun
    | .checkOwnerExact _ o => o == nativeLoaderOwnerProgramIdV1 | _ => false)
    "Native Loader owner"
  expect (h.ops.any fun
    | .checkOwnerExact _ o => o == systemProgramIdV1 | _ => false)
    "payer owned by system program"
  expect (h.ops.any fun
    | .checkExactDataLen _ 0 => true | _ => false)
    "payer exactLength 0"

unsafe def run : IO Unit := do
  testLoaderOwnerPubkeys
  testStructuralCompanionProjection
  testStructuralCreatePdaReject
  testStructuralSystemTransferOwners
  testRoleCountBoundary
  let session ← Tests.Language.ParserSession.shared
  testAuthorityMultiHandlerEmission session
  testUnsupportedApiPreflightReject session
  IO.println "Tests.Materialization.SolanaCpiPreflightV1: ok"

end Tests.Materialization.SolanaCpiPreflightV1

import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiIdlV1
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Solana.PlanSchemaV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiPlanV1

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

private def exceptIsError : Except ε α → Bool
  | .ok _ => false
  | .error _ => true

/-- #117 starts with a strict raw-key carrier; base58 is presentation only and
    never creates a portable Principal conversion. -/
private def testStrictPubkeyCarrier : IO Unit := do
  let system ← expectOk (SolanaPubkeyV1.parseBase58
    "11111111111111111111111111111111") "parse System program"
  expect (SolanaPubkeyV1.toBytes system ==
    ByteArray.mk (Array.replicate 32 0)) "System program raw key"
  expect (SolanaPubkeyV1.toBase58 system ==
    "11111111111111111111111111111111") "System program base58 round-trip"
  let token ← expectOk (SolanaPubkeyV1.parseBase58
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA") "parse classic Token"
  expect (token == tokenClassicProgramIdV1) "classic Token raw key"
  let ata ← expectOk (SolanaPubkeyV1.parseBase58
    "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL") "parse classic ATA"
  expect (ata == ataClassicProgramIdV1) "classic ATA raw key"
  let companionWire := SolanaPubkeyV1.toBase58 companionProgramIdV1
  let companion ← expectOk (SolanaPubkeyV1.parseBase58 companionWire)
    "companion round-trip"
  expect (companion == companionProgramIdV1) "companion raw round-trip"
  for bad in #[
      "01111111111111111111111111111111",
      "1111111111111111111111111111111",
      "111111111111111111111111111111111",
      "111111111111111111111111111111111111111111111"] do
    expect (exceptIsError (SolanaPubkeyV1.parseBase58 bad))
      s!"strict base58 rejects '{bad}'"
  expect (exceptIsError (SolanaPubkeyV1.ofBytes
    (ByteArray.mk (Array.replicate 31 0)))) "31-byte key rejected"
  expect (exceptIsError (SolanaPubkeyV1.ofBytes
    (ByteArray.mk (Array.replicate 33 0)))) "33-byte key rejected"

private def testFrozenContractProjection : IO Unit := do
  expect (profileIdV1 == "solana-sbpf-cpi-elf-v1") "frozen profile id"
  expect (frozenCalleePackagesV1.size == 4) "four frozen packages"
  expect (frozenCalleePackagesV1.all fun package =>
    !package.admittedForMaterialization) "all packages remain inert"
  expect (frozenApisV1.size == 8) "eight frozen APIs"
  expect (frozenApiQnsV1 == #[
    "solana.companion.invoke",
    "solana.companion.fail",
    "solana.companion.invokeSigned",
    "solana.system.transfer",
    "solana.system.createPdaAccount",
    "solana.token.transferChecked",
    "solana.token.transferCheckedPda",
    "solana.ata.createIdempotent"]) "frozen API order"
  expect (frozenApisV1.map (·.instructionCodec.length) ==
    #[9, 9, 9, 12, 52, 10, 10, 1]) "frozen codec lengths"
  expect (frozenPdaRulesV1.size == 2) "two frozen PDA recipes"
  let some currentRule := frozenPdaRulesV1[0]? |
    throw <| IO.userError "missing current-program PDA rule"
  let some ataRule := frozenPdaRulesV1[1]? |
    throw <| IO.userError "missing ATA PDA rule"
  expect (currentRule.seeds.size == 4 && currentRule.signerEligible &&
    currentRule.search == .providedBumpMustEqualCanonical255Through1 &&
    ataRule.seeds.size == 3 && !ataRule.signerEligible &&
    ataRule.search == .canonical255Through1) "PDA seed/search recipes"
  let tokenTag ← expectOk (InstructionSegment.hexBytes (.hex "0c"))
    "decode Token tag"
  expect (tokenTag == ByteArray.mk #[0x0c]) "Token tag bytes"
  expect (exceptIsError (decodeHexBytesV1 "0g")) "malformed hex fails closed"

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

private def getE {α : Type} (values : Array α) (index : Nat)
    (label : String) : Except String α :=
  match values[index]? with
  | some value => pure value
  | none => throw s!"{label}: index {index} out of range"

private def packageRoleName (packageId : String) : String :=
  packageId.replace "-" "_" ++ "_program"

/-- Build a structurally exact one-handler candidate directly from the frozen
    target contract. This is test-only inspection data; product lowering stays
    inert until the later issues. -/
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
    programName := "CpiProbe"
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
    computeAssumptions := frozenComputeAssumptionsV1
  }

private def firstWordBE (bytes : ByteArray) : UInt64 := Id.run do
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := UInt64.shiftLeft value 8 ||| bytes[index]!.toUInt64
  return value

private def stateOnlyCandidate : Except String SolanaCpiPlanCandidateV1 := do
  let profileDigest ← expectedProfileDigestV1
  let catalogDigest ← expectedCatalogDigestV1
  let extensionRequirement ← expectedExtensionRequirementV1
  let layoutDigest ← domainSeparatedSha256 "pf.test.solana-state-layout.v1" "state".toUTF8
  let marker := firstWordBE layoutDigest.bytes
  pure {
    schema := planSchemaV1
    profileId := profileIdV1
    profileDigest
    extensionRequirement
    calleeCatalogDigest := catalogDigest
    programName := "StateProbe"
    stateSchemas := #[{
      schemaId := 0
      name := "state"
      exactDataLen := 16
      layoutDigest := layoutDigest
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
      name := "update"
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
    computeAssumptions := frozenComputeAssumptionsV1
  }

private def digestDiff (left right : Digest) : Bool :=
  !(left.algorithm == right.algorithm && left.bytes == right.bytes)

private def testPlanDeterminismAndAllApis : IO Unit := do
  for api in frozenApisV1 do
    let candidate ← expectOk (candidateForApi api) s!"candidate {api.qn}"
    let first ← expectPlanOk (validateSolanaCpiPlanV1 candidate)
      s!"validate {api.qn}"
    let second ← expectPlanOk (validateSolanaCpiPlanV1 candidate)
      s!"revalidate {api.qn}"
    expect (first.canonicalBytes == second.canonicalBytes)
      s!"{api.qn}: canonical bytes deterministic"
    expect (!first.canonicalBytes.isEmpty) s!"{api.qn}: canonical bytes nonempty"
    expect (!digestDiff first.digest second.digest) s!"{api.qn}: digest deterministic"
    let recomputed ← expectOk
      (domainSeparatedSha256 planDigestDomainV1 first.canonicalBytes)
      s!"{api.qn}: recompute digest"
    expect (!digestDiff first.digest recomputed) s!"{api.qn}: digest authority"
    expect (first.candidate == candidate) s!"{api.qn}: carrier retains candidate"
    expectPlanReject (checkSolanaCpiMaterializationEligibilityV1 first)
      s!"{api.qn}: package/profile remains inert"
  expect (apiSystemCreatePdaAccountV1.preflight ==
    #[.uint64AtMost "space" 4096]) "createPdaAccount exact 4096 preflight"

private def testPlanMutationAndNegativeMatrix : IO Unit := do
  let base ← expectOk (candidateForApi apiCompanionInvokeV1) "base candidate"
  let basePlan ← expectPlanOk (validateSolanaCpiPlanV1 base) "base plan"

  let renamed := { base with programName := "CpiProbeRenamed" }
  let renamedPlan ← expectPlanOk (validateSolanaCpiPlanV1 renamed) "renamed plan"
  expect (digestDiff basePlan.digest renamedPlan.digest) "programName binds digest"

  let some baseSite := base.cpiSites[0]? |
    throw <| IO.userError "base site missing"
  let effectSite := { baseSite with anchor := { baseSite.anchor with effectId := 7 } }
  let effectCandidate := { base with cpiSites := base.cpiSites.set! 0 effectSite }
  let effectPlan ← expectPlanOk (validateSolanaCpiPlanV1 effectCandidate)
    "effect-id mutation"
  expect (digestDiff basePlan.digest effectPlan.digest) "effectId binds digest"

  let unknownSite := { baseSite with qn := "solana.unknown.call" }
  expectPlanReject (validateSolanaCpiPlanV1
    { base with cpiSites := base.cpiSites.set! 0 unknownSite }) "unknown QN"

  let wrongProgram := { baseSite with programKey := systemProgramIdV1 }
  expectPlanReject (validateSolanaCpiPlanV1
    { base with cpiSites := base.cpiSites.set! 0 wrongProgram }) "program key mismatch"

  let wrongInfos := { baseSite with accountInfoRoleIds := #[1, 0] }
  expectPlanReject (validateSolanaCpiPlanV1
    { base with cpiSites := base.cpiSites.set! 0 wrongInfos }) "reordered AccountInfos"

  let wrongPreflight := { baseSite with preflight := #[.uint64AtMost "delta" 1] }
  expectPlanReject (validateSolanaCpiPlanV1
    { base with cpiSites := base.cpiSites.set! 0 wrongPreflight }) "preflight mismatch"

  let wrongPredicates := { baseSite with sitePredicates := #[] }
  expectPlanReject (validateSolanaCpiPlanV1
    { base with cpiSites := base.cpiSites.set! 0 wrongPredicates }) "site predicates missing"

  let some handler := base.handlers[0]? |
    throw <| IO.userError "base handler missing"
  let duplicateEffectSite := {
    baseSite with
    siteId := 1
    anchor := { baseSite.anchor with instructionIndex := 1 }
  }
  expectPlanRejectContains (validateSolanaCpiPlanV1 {
    base with
    handlers := #[{ handler with cpiSiteIds := #[0, 1] }]
    cpiSites := #[baseSite, duplicateEffectSite]
  }) "effectId" "duplicate callable-scoped effectId"
  let duplicateAnchorSite := {
    baseSite with
    siteId := 1
    anchor := { baseSite.anchor with effectId := 1 }
  }
  expectPlanRejectContains (validateSolanaCpiPlanV1 {
    base with
    handlers := #[{ handler with cpiSiteIds := #[0, 1] }]
    cpiSites := #[baseSite, duplicateAnchorSite]
  }) "strictly ordered" "duplicate semantic anchor rejected by source-order gate"
  let missingUses := handler.accountUses.extract 0 1
  expectPlanReject (validateSolanaCpiPlanV1
    { base with handlers := #[{ handler with accountUses := missingUses }] })
    "missing handler role"

  let some accountUse := handler.accountUses[0]? |
    throw <| IO.userError "account use missing"
  let weakUse := { accountUse with outerWritable := false }
  expectPlanReject (validateSolanaCpiPlanV1
    { base with handlers := #[{ handler with
      accountUses := handler.accountUses.set! 0 weakUse }] })
    "underspecified privilege"

  let some role1 := base.accountRoles[1]? |
    throw <| IO.userError "fixed role missing"
  let gapRole := { role1 with roleId := 2 }
  expectPlanReject (validateSolanaCpiPlanV1
    { base with accountRoles := base.accountRoles.set! 1 gapRole }) "gapped role ids"

  let stateBase ← expectOk stateOnlyCandidate "state candidate"
  let _ ← expectPlanOk (validateSolanaCpiPlanV1 stateBase) "state plan"
  let some schema := stateBase.stateSchemas[0]? |
    throw <| IO.userError "state schema missing"
  expect (schema.initializedMarker != 0) "state marker nonzero"
  expect (schema.initializedMarker == firstWordBE schema.layoutDigest.bytes)
    "state marker equals first 8 BE layoutDigest bytes"
  expectPlanReject (validateSolanaCpiPlanV1
    { stateBase with stateSchemas := #[{ schema with exactDataLen := 0 }] })
    "zero state layout"
  expectPlanReject (validateSolanaCpiPlanV1
    { stateBase with stateSchemas := #[{ schema with initializedMarker := 0 }] })
    "zero initializedMarker"
  expectPlanReject (validateSolanaCpiPlanV1
    { stateBase with stateSchemas :=
      #[{ schema with initializedMarker := schema.initializedMarker + 1 }] })
    "marker/digest mismatch"
  let some stateHandler := stateBase.handlers[0]? |
    throw <| IO.userError "state handler missing"
  let some stateUse := stateHandler.accountUses[0]? |
    throw <| IO.userError "state use missing"
  expectPlanReject (validateSolanaCpiPlanV1
    { stateBase with handlers := #[{ stateHandler with
      mode := .view
      accountUses := #[stateUse]
    }] }) "view state privilege mismatch"

  let some role0 := base.accountRoles[0]? |
    throw <| IO.userError "account role missing"
  let stateRole := { role0 with
    keyPolicy := .state 0
    constraint := stateRoleConstraintV1
  }
  let some stateSchema := stateBase.stateSchemas[0]? |
    throw <| IO.userError "state schema fixture missing"
  let stateUseForCall := { accountUse with directWritableContribution := true }
  let stateArgCandidate := { base with
    stateSchemas := #[stateSchema]
    accountRoles := base.accountRoles.set! 0 stateRole
    handlers := #[{ handler with
      accountUses := handler.accountUses.set! 0 stateUseForCall
    }]
  }
  expectPlanReject (validateSolanaCpiPlanV1 stateArgCandidate)
    "state Principal must not become an account-bound call arg"

/-- Mixed-invalid candidates pin the structural validator's documented phase
    order: identity → state/assumptions → roles → handlers → sites → privilege. -/
private def testPlanValidationPhaseOrder : IO Unit := do
  let base ← expectOk (candidateForApi apiCompanionInvokeV1) "phase base"
  let some site0 := base.cpiSites[0]? |
    throw <| IO.userError "phase site missing"
  let some handler0 := base.handlers[0]? |
    throw <| IO.userError "phase handler missing"
  let some use0 := handler0.accountUses[0]? |
    throw <| IO.userError "phase account use missing"
  let some role1 := base.accountRoles[1]? |
    throw <| IO.userError "phase role missing"
  let gapRoles := base.accountRoles.set! 1 { role1 with roleId := 2 }
  let badHandler := { handler0 with handlerId := 1 }
  let badSite := { site0 with qn := "solana.unknown.call" }
  let weakHandler := {
    handler0 with
    accountUses := handler0.accountUses.set! 0 {
      use0 with outerWritable := false
    }
  }

  expectPlanRejectContains (validateSolanaCpiPlanV1 {
    base with
    schema := "wrong"
    accountRoles := gapRoles
  }) "schema" "phase 1 identity precedes roles"
  expectPlanRejectContains (validateSolanaCpiPlanV1 {
    base with
    pdaRules := #[]
    accountRoles := gapRoles
  }) "pdaRules" "phase 2 assumptions precedes roles"
  expectPlanRejectContains (validateSolanaCpiPlanV1 {
    base with
    accountRoles := gapRoles
    handlers := #[badHandler]
  }) "roleIds" "phase 3 roles precedes handlers"
  expectPlanRejectContains (validateSolanaCpiPlanV1 {
    base with
    handlers := #[badHandler]
    cpiSites := #[badSite]
  }) "handlerIds" "phase 4 handlers precedes sites"
  expectPlanRejectContains (validateSolanaCpiPlanV1 {
    base with
    handlers := #[weakHandler]
    cpiSites := #[badSite]
  }) "not a frozen API" "phase 5 sites precedes privilege"
  expectPlanRejectContains (validateSolanaCpiPlanV1 {
    base with handlers := #[weakHandler]
  }) "outerWritable" "phase 6 privilege"

private def testHandlerLocalRoleSubsets : IO Unit := do
  let base ← expectOk (candidateForApi apiCompanionInvokeV1) "base candidate"
  let some role0 := base.accountRoles[0]? |
    throw <| IO.userError "base role0 missing"
  let role2 : AccountRoleSchemaV1 := { role0 with
    roleId := 2
    name := "second_account"
    keyPolicy := .accountParameter 1 0
  }
  let roles := base.accountRoles.push role2
  let some site0 := base.cpiSites[0]? |
    throw <| IO.userError "base site missing"
  let some arg0 := site0.args[0]? |
    throw <| IO.userError "base arg missing"
  let some meta0 := site0.metas[0]? |
    throw <| IO.userError "base meta missing"
  let site1 : CpiSitePlanV1 := {
    site0 with
    siteId := 1
    handlerId := 1
    anchor := {
      callableId := 1
      blockId := 0
      instructionIndex := 0
      effectId := 0
    }
    args := site0.args.set! 0 { arg0 with roleId := some 2 }
    metas := site0.metas.set! 0 { meta0 with roleId := 2 }
    accountInfoRoleIds := #[2, 1]
    sitePredicates := #[
      {
        source := .callee
        roleId := 1
        constraint := calleeRoleConstraintV1
      },
      {
        source := .metaIndex 0
        roleId := 2
        constraint := meta0.spec.constraint
      }
    ]
  }
  let handler1 : HandlerPlanV1 := {
    handlerId := 1
    callableId := 1
    name := "second"
    mode := .entry
    accountUses := #[
      {
        position := 0
        roleId := 2
        directSignerContribution := false
        directWritableContribution := false
        outerSigner := false
        outerWritable := true
      },
      {
        position := 1
        roleId := 1
        directSignerContribution := false
        directWritableContribution := false
        outerSigner := false
        outerWritable := false
      }
    ]
    cpiSiteIds := #[1]
  }
  let twoHandlers := { base with
    accountRoles := roles
    handlers := base.handlers.push handler1
    cpiSites := #[site0, site1]
  }
  let twoPlan ← expectPlanOk (validateSolanaCpiPlanV1 twoHandlers)
    "two handler-local role subsets; effectId resets per callable"
  let twoIr ← expectPlanOk (deriveSolanaCpiIRV1 twoPlan)
    "two handler-local IR"
  expect (twoIr.candidate.roleHandles.map (fun h =>
      (h.handlerId, h.localIndex, h.roleId)) == #[(0, 0, 0), (0, 1, 1),
        (1, 0, 2), (1, 1, 1)])
    "IR handles remain handler-local rather than global ACC slots"
  expect (twoIr.candidate.sites.map (fun s =>
      (s.handlerId, s.accountInfoRoleIds, s.accountInfoHandleIndices)) == #[
        (0, #[0, 1], #[0, 1]), (1, #[2, 1], #[0, 1])])
    "IR projects each Plan-owned AccountInfo sequence to local handles"
  let twoIdl ← expectPlanOk (deriveSolanaCpiIdlV1 twoPlan)
    "two handler-local IDL"
  expect (twoIdl.candidate.instructions.map (fun i =>
      i.accounts.map (·.roleId)) == #[#[0, 1], #[2, 1]])
    "IDL exposes per-handler role subsets only"

  let some handler1FirstUse := handler1.accountUses[0]? |
    throw <| IO.userError "handler1 first use missing"
  let foreignUse := { handler1FirstUse with roleId := 0 }
  let foreignHandler := { handler1 with
    accountUses := handler1.accountUses.set! 0 foreignUse
  }
  expectPlanReject (validateSolanaCpiPlanV1
    { twoHandlers with handlers := base.handlers.push foreignHandler })
    "handler cannot use another callable account role"
  let globalInfoSite := { site1 with accountInfoRoleIds := #[0, 1, 2] }
  expectPlanReject (validateSolanaCpiPlanV1
    { twoHandlers with cpiSites := #[site0, globalInfoSite] })
    "site AccountInfos cannot use global role universe"

private def opKindName : CpiIROperationV1 → String
  | .checkPreflight .. => "checkPreflight"
  | .checkPredicate .. => "checkPredicate"
  | .prepareInstruction .. => "prepareInstruction"
  | .prepareMeta .. => "prepareMeta"
  | .prepareFullAccountInfos .. => "prepareFullAccountInfos"
  | .prepareSignerGroup .. => "prepareSignerGroup"
  | .cpiBoundary .. => "cpiBoundary"

private def fieldTriple (f : CFieldLayoutV1) : String × Nat × Nat :=
  (f.name, f.offset, f.byteWidth)

/-- Plan → IR/IDL sole derive for all 8 frozen APIs, frozen ABIv1/C layouts,
    createPdaAccount operation order + handler-local indexes, and exact IDL
    projection pins (stateSchemas / programRole / codec / metas / outer-only /
    PDA / base58 / account role order). -/
private def testPlanToIrAndIdlProjection : IO Unit := do
  -- All 8 APIs (IR + IDL derive + exact IDL projections).
  for api in frozenApisV1 do
    let candidate ← expectOk (candidateForApi api) s!"ir/idl candidate {api.qn}"
    let plan ← expectPlanOk (validateSolanaCpiPlanV1 candidate)
      s!"ir/idl plan {api.qn}"
    let irFirst ← expectPlanOk (deriveSolanaCpiIRV1 plan)
      s!"derive IR {api.qn}"
    let irSecond ← expectPlanOk (deriveSolanaCpiIRV1 plan)
      s!"rederive IR {api.qn}"
    expect (irFirst.canonicalBytes == irSecond.canonicalBytes)
      s!"{api.qn}: IR canonical bytes deterministic"
    expect (!irFirst.canonicalBytes.isEmpty)
      s!"{api.qn}: IR canonical bytes nonempty"
    expect (!digestDiff irFirst.digest irSecond.digest)
      s!"{api.qn}: IR digest deterministic"
    let irRecomputed ← expectOk
      (domainSeparatedSha256 irDigestDomainV1 irFirst.canonicalBytes)
      s!"{api.qn}: recompute IR digest"
    expect (!digestDiff irFirst.digest irRecomputed)
      s!"{api.qn}: IR digest domain authority"
    expect (irFirst.candidate.abiLayout == frozenLoaderV3AbiLayoutV1)
      s!"{api.qn}: IR abiLayout frozen"
    expect (irFirst.candidate.cLayouts == frozenCpiIRCLayoutsV1)
      s!"{api.qn}: IR cLayouts frozen"
    expect (!digestDiff irFirst.candidate.sourcePlanDigest plan.digest)
      s!"{api.qn}: IR sourcePlanDigest == plan digest"
    expect (irFirst.candidate.profileId == plan.candidate.profileId &&
      !digestDiff irFirst.candidate.profileDigest plan.candidate.profileDigest &&
      !digestDiff irFirst.candidate.catalogDigest
        plan.candidate.calleeCatalogDigest)
      s!"{api.qn}: IR profile/catalog identity projection"
    expect (irFirst.candidate.stateSchemas == plan.candidate.stateSchemas &&
      irFirst.candidate.pdaRules == plan.candidate.pdaRules &&
      irFirst.candidate.computeAssumptions == plan.candidate.computeAssumptions)
      s!"{api.qn}: IR state/PDA/compute projection"

    let idlFirst ← expectPlanOk (deriveSolanaCpiIdlV1 plan)
      s!"derive IDL {api.qn}"
    let idlSecond ← expectPlanOk (deriveSolanaCpiIdlV1 plan)
      s!"rederive IDL {api.qn}"
    expect (idlFirst.canonicalBytes == idlSecond.canonicalBytes)
      s!"{api.qn}: IDL canonical bytes deterministic"
    expect (idlFirst.canonicalText == idlSecond.canonicalText)
      s!"{api.qn}: IDL canonical text deterministic"
    expect (!idlFirst.canonicalBytes.isEmpty)
      s!"{api.qn}: IDL canonical bytes nonempty"
    expect (idlFirst.candidate.stateSchemas == plan.candidate.stateSchemas)
      s!"{api.qn}: IDL stateSchemas projection"
    expect (idlFirst.candidate.pdaRules == frozenPdaRulesV1)
      s!"{api.qn}: IDL pdaRules projection"
    expect (idlFirst.candidate.profileId == profileIdV1)
      s!"{api.qn}: IDL profileId"
    expect (!digestDiff idlFirst.candidate.planDigest plan.digest)
      s!"{api.qn}: IDL planDigest == plan digest"
    let some package := findCalleePackage? api.fixedProgram |
      throw <| IO.userError s!"{api.qn}: missing package"
    let some idlSite := idlFirst.candidate.cpiSites[0]? |
      throw <| IO.userError s!"{api.qn}: missing IDL site"
    expect (idlSite.qn == api.qn) s!"{api.qn}: IDL site qn"
    expect (idlSite.packageId == api.fixedProgram)
      s!"{api.qn}: IDL packageId"
    expect (idlSite.programRoleName == packageRoleName api.fixedProgram)
      s!"{api.qn}: IDL programRoleName"
    expect (idlSite.programIdBase58 == SolanaPubkeyV1.toBase58 package.programId)
      s!"{api.qn}: IDL programId base58"
    expect (idlSite.instructionCodec == api.instructionCodec)
      s!"{api.qn}: IDL instructionCodec exact"
    expect (idlSite.metas.size == api.metas.size)
      s!"{api.qn}: IDL meta count"
    for i in [0:api.metas.size] do
      let some metaRow := idlSite.metas[i]? |
        throw <| IO.userError s!"{api.qn}: missing IDL meta {i}"
      let some expectedMeta := api.metas[i]? |
        throw <| IO.userError s!"{api.qn}: missing frozen meta {i}"
      expect (metaRow.spec == expectedMeta)
        s!"{api.qn}: IDL full meta spec[{i}]"
      expect (metaRow.metaIndex == i)
        s!"{api.qn}: IDL metaIndex[{i}]"
    expect (idlSite.outerOnlyAccounts.size == api.outerOnlyAccounts.size)
      s!"{api.qn}: IDL outer-only count"
    for i in [0:api.outerOnlyAccounts.size] do
      let some outerRow := idlSite.outerOnlyAccounts[i]? |
        throw <| IO.userError s!"{api.qn}: missing IDL outer-only {i}"
      let some expectedOuter := api.outerOnlyAccounts[i]? |
        throw <| IO.userError s!"{api.qn}: missing frozen outer-only {i}"
      expect (outerRow.spec == expectedOuter)
        s!"{api.qn}: IDL outer-only spec[{i}]"
      expect (outerRow.roleName == expectedOuter.arg)
        s!"{api.qn}: IDL outer-only roleName[{i}]"
    expect (idlSite.pda == api.pda) s!"{api.qn}: IDL PDA projection"
    expect (idlSite.signerGroups == api.signerGroups)
      s!"{api.qn}: IDL signerGroups"
    expect (idlSite.preflight == api.preflight)
      s!"{api.qn}: IDL preflight"
    let some instr := idlFirst.candidate.instructions[0]? |
      throw <| IO.userError s!"{api.qn}: missing IDL instruction"
    expect (instr.accounts.map (·.name) == idlSite.accountInfoRoleNames)
      s!"{api.qn}: instruction accounts order == site accountInfoRoleNames"
    expect (instr.accounts.map (·.name) == plan.candidate.accountRoles.map (·.name))
      s!"{api.qn}: account role order projection"
    for i in [0:instr.accounts.size] do
      let some row := instr.accounts[i]? |
        throw <| IO.userError s!"{api.qn}: missing IDL account {i}"
      let some role := plan.candidate.accountRoles[i]? |
        throw <| IO.userError s!"{api.qn}: missing Plan role {i}"
      let some use := plan.candidate.handlers[0]?.bind (fun h => h.accountUses[i]?) |
        throw <| IO.userError s!"{api.qn}: missing Plan account use {i}"
      expect (row.roleId == role.roleId && row.keyPolicy == role.keyPolicy &&
        row.constraint == role.constraint && row.aliasPolicy == role.aliasPolicy)
        s!"{api.qn}: IDL account role policy[{i}]"
      expect (row.directSignerContribution == use.directSignerContribution &&
        row.directWritableContribution == use.directWritableContribution &&
        row.outerSigner == use.outerSigner &&
        row.outerWritable == use.outerWritable)
        s!"{api.qn}: IDL account privilege provenance[{i}]"

  -- Frozen ABIv1 + C struct size/align/field pins (once).
  let abi := frozenLoaderV3AbiLayoutV1
  expect (abi.schema == "abiv1" && abi.loader == "loader-v3" &&
    abi.parser ==
      "overflow-checked-virtual-address-walk-not-contiguous-backing-buffer-walk" &&
    abi.fullPrefixBytes == 88 && abi.marker == 0xff)
    "abi schema/loader/parser/prefix/marker"
  expect (abi.isSignerOffset == 1 && abi.isWritableOffset == 2 &&
    abi.executableOffset == 3 && abi.originalDataLenOffset == 4 &&
    abi.keyOffset == 8 && abi.ownerOffset == 40 && abi.lamportsOffset == 72 &&
    abi.dataLenOffset == 80 && abi.maxPermittedDataIncrease == 10240)
    "abi field offsets"
  expect (abi.dataRegionRule == "direct-mapped-at-prefix-plus-88" &&
    abi.virtualCursorRule == "align8(data-address-plus-data-len-plus-10240)" &&
    abi.rentEpochRule == "u64-max-at-align8(data-end-plus-10240)" &&
    abi.instructionTail == #[
      "u64-le-instruction-data-len", "instruction-data",
      "current-program-id-32", "zero-pad-to-8",
      "account-marker-pointer-table"] &&
    abi.pointerTableLocation == "after-program-id-and-zero-padding" &&
    abi.pointerTableAlignment == 8 &&
    abi.pointerTableEntry == "u64-le-vm-address-of-role-marker" &&
    abi.pointerTableOneEntryPerOuterRole && abi.accountDataDirectMapping &&
    abi.directAccountPointersInProgramInput &&
    abi.virtualAddressSpaceAdjustments && abi.duplicateRecordBytes == 8 &&
    abi.originalDataLenEntryValue == 0) "abi rules/flags"
  let cl := frozenCpiIRCLayoutsV1
  expect (cl.instruction.name == "SolInstruction" &&
    cl.instruction.size == 40 && cl.instruction.align == 8 &&
    cl.instruction.fields.map fieldTriple == #[
      ("program_id_addr", 0, 8), ("accounts_addr", 8, 8),
      ("accounts_len", 16, 8), ("data_addr", 24, 8), ("data_len", 32, 8)])
    "SolInstruction layout"
  expect (cl.accountMeta.name == "SolAccountMeta" &&
    cl.accountMeta.size == 16 && cl.accountMeta.align == 8 &&
    cl.accountMeta.fields.map fieldTriple == #[
      ("pubkey_addr", 0, 8), ("is_writable", 8, 1),
      ("is_signer", 9, 1), ("zero_padding", 10, 6)])
    "SolAccountMeta layout"
  expect (cl.info.name == "SolAccountInfo" &&
    cl.info.size == 56 && cl.info.align == 8 &&
    cl.info.fields.map fieldTriple == #[
      ("key_addr", 0, 8), ("lamports_addr", 8, 8), ("data_len", 16, 8),
      ("data_addr", 24, 8), ("owner_addr", 32, 8), ("rent_epoch", 40, 8),
      ("is_signer", 48, 1), ("is_writable", 49, 1), ("executable", 50, 1),
      ("zero_padding", 51, 5)]) "SolAccountInfo layout"
  expect (cl.seed.name == "SolSignerSeed" &&
    cl.seed.size == 16 && cl.seed.align == 8 &&
    cl.seed.fields.map fieldTriple == #[("addr", 0, 8), ("len", 8, 8)])
    "SolSignerSeed layout"
  expect (cl.seeds.name == "SolSignerSeeds" &&
    cl.seeds.size == 16 && cl.seeds.align == 8 &&
    cl.seeds.fields.map fieldTriple == #[("addr", 0, 8), ("len", 8, 8)])
    "SolSignerSeeds layout"

  -- system.createPdaAccount: operations order + handler-local indexes.
  let api := apiSystemCreatePdaAccountV1
  let candidate ← expectOk (candidateForApi api) "createPda candidate"
  let plan ← expectPlanOk (validateSolanaCpiPlanV1 candidate) "createPda plan"
  let ir ← expectPlanOk (deriveSolanaCpiIRV1 plan) "createPda IR"
  let idl ← expectPlanOk (deriveSolanaCpiIdlV1 plan) "createPda IDL"
  expect (ir.candidate.roleHandles.size == 4)
    "createPda: four handler-local role handles"
  expect (ir.candidate.roleHandles.map (fun h =>
      (h.handlerId, h.localIndex, h.roleId, h.name)) == #[
    (0, 0, 0, "payer"),
    (0, 1, 1, "pda"),
    (0, 2, 2, "seedAuthority"),
    (0, 3, 3, "system_v1_program")])
    "createPda: handler-local handle indexes"
  for i in [0:ir.candidate.roleHandles.size] do
    let some handle := ir.candidate.roleHandles[i]? |
      throw <| IO.userError s!"createPda: missing role handle {i}"
    let some role := plan.candidate.accountRoles[i]? |
      throw <| IO.userError s!"createPda: missing role {i}"
    let some use := plan.candidate.handlers[0]?.bind (fun h => h.accountUses[i]?) |
      throw <| IO.userError s!"createPda: missing account use {i}"
    expect (handle.keyPolicy == role.keyPolicy &&
      handle.constraint == role.constraint &&
      handle.aliasPolicy == frozenAliasPolicyV1)
      s!"createPda: role handle policy {i}"
    expect (handle.directSignerContribution == use.directSignerContribution &&
      handle.directWritableContribution == use.directWritableContribution &&
      handle.outerSigner == use.outerSigner &&
      handle.outerWritable == use.outerWritable)
      s!"createPda: role handle privilege provenance {i}"
  let some irSite := ir.candidate.sites[0]? |
    throw <| IO.userError "createPda: missing IR site"
  expect (irSite.programRoleId == 3 && irSite.programHandleIndex == 3)
    "createPda: program role/handle is handler-local system slot"
  expect (irSite.accountInfoRoleIds == #[0, 1, 2, 3] &&
    irSite.accountInfoHandleIndices == #[0, 1, 2, 3])
    "createPda: exact Plan role ids map to full local AccountInfo handles"
  expect (irSite.metas.map (fun m =>
      (m.metaIndex, m.roleId, m.localHandleIndex)) == #[
    (0, 0, 0), (1, 1, 1)] &&
    irSite.metas.map (·.spec) == api.metas)
    "createPda: meta local handles and full specs"
  let some expectedOuterSpec := api.outerOnlyAccounts[0]? |
    throw <| IO.userError "createPda: missing frozen outer-only spec"
  expect (irSite.outerOnlyAccounts.map (fun o =>
      (o.roleId, o.localHandleIndex, o.spec)) == #[
    (2, 2, expectedOuterSpec)])
    "createPda: outer-only role/local handle/full spec"
  -- preflight → predicates → prepareInstruction → metas → full infos →
  -- signerGroup → cpiBoundary
  expect (ir.candidate.operations.map opKindName == #[
    "checkPreflight",
    "checkPredicate", "checkPredicate", "checkPredicate", "checkPredicate",
    "prepareInstruction",
    "prepareMeta", "prepareMeta",
    "prepareFullAccountInfos",
    "prepareSignerGroup",
    "cpiBoundary"])
    "createPda: operations order"
  let expectedPreflight : CpiIROperationV1 :=
    .checkPreflight 0 0 (.uint64AtMost "space" 4096)
  let expectedBoundary : CpiIROperationV1 := .cpiBoundary 0 3 1
  let expectedInfos : CpiIROperationV1 :=
    .prepareFullAccountInfos 0 #[0, 1, 2, 3]
  expect (ir.candidate.operations[0]? == some expectedPreflight)
    "createPda: first op preflight space≤4096"
  expect (ir.candidate.operations[ir.candidate.operations.size - 1]? ==
      some expectedBoundary)
    "createPda: last op cpiBoundary(0,3,1)"
  expect (ir.candidate.operations[ir.candidate.operations.size - 3]? ==
      some expectedInfos)
    "createPda: full AccountInfos op"

  let some idlSite := idl.candidate.cpiSites[0]? |
    throw <| IO.userError "createPda: missing IDL site"
  expect (idlSite.programRoleName == "system_v1_program")
    "createPda: IDL programRoleName"
  expect (idlSite.programIdBase58 == "11111111111111111111111111111111")
    "createPda: system program base58"
  expect (idlSite.instructionCodec.length == 52)
    "createPda: codec length 52"
  expect (idlSite.metas.map (·.roleName) == #["payer", "pda"])
    "createPda: meta role names"
  expect (idlSite.outerOnlyAccounts.map (·.roleName) == #["seedAuthority"])
    "createPda: outer-only seedAuthority"
  expect (idlSite.pda == api.pda) "createPda: PDA exact"
  expect (idlSite.accountInfoRoleNames ==
    #["payer", "pda", "seedAuthority", "system_v1_program"])
    "createPda: account role order"
  expect (idlSite.preflight == #[.uint64AtMost "space" 4096])
    "createPda: IDL preflight 4096"

  -- stateOnly candidate projects nonempty stateSchemas through IDL.
  let stateCand ← expectOk stateOnlyCandidate "stateOnly candidate"
  let statePlan ← expectPlanOk (validateSolanaCpiPlanV1 stateCand) "stateOnly plan"
  let stateIdl ← expectPlanOk (deriveSolanaCpiIdlV1 statePlan) "stateOnly IDL"
  expect (stateIdl.candidate.stateSchemas == statePlan.candidate.stateSchemas)
    "stateOnly: IDL stateSchemas exact"
  expect (stateIdl.candidate.stateSchemas.size == 1)
    "stateOnly: one state schema"
  expect (stateIdl.candidate.cpiSites.isEmpty)
    "stateOnly: no CPI sites"
  let stateIr ← expectPlanOk (deriveSolanaCpiIRV1 statePlan) "stateOnly IR"
  expect (stateIr.candidate.stateSchemas == statePlan.candidate.stateSchemas &&
    stateIr.candidate.sites.isEmpty && stateIr.candidate.operations.isEmpty)
    "stateOnly: state schema retained with empty IR sites/ops"
  expect (stateIr.candidate.roleHandles.map (fun h =>
      (h.localIndex, h.roleId, h.name, h.outerWritable)) == #[
    (0, 0, "state", true)])
    "stateOnly: single handler-local state handle"

/-- IR/IDL mutation negatives: any abi/layout/role/site/operations (IR) or
    state schema/site program id/codec/meta/outer-only/instruction accounts
    (IDL) drift is rejected by public validate. -/
private def testIrAndIdlMutationNegatives : IO Unit := do
  let base ← expectOk (candidateForApi apiSystemCreatePdaAccountV1)
    "mutation base candidate"
  let plan ← expectPlanOk (validateSolanaCpiPlanV1 base) "mutation base plan"
  let ir ← expectPlanOk (deriveSolanaCpiIRV1 plan) "mutation base IR"
  let idl ← expectPlanOk (deriveSolanaCpiIdlV1 plan) "mutation base IDL"
  let irCand := ir.candidate
  let idlCand := idl.candidate

  -- IR: Plan identity/state/PDA/compute projection drift.
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with profileId := "solana-sbpf-elf-v1" })
    "IR profileId drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with pdaRules := irCand.pdaRules.pop })
    "IR pdaRules drift"
  let computeBad := {
    irCand.computeAssumptions with
    maxOuterRoles := irCand.computeAssumptions.maxOuterRoles - 1
  }
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with computeAssumptions := computeBad })
    "IR compute assumptions drift"

  -- IR: abiLayout drift
  let abiBadPrefix := { irCand.abiLayout with fullPrefixBytes := 0 }
  let abiBadMarker := { irCand.abiLayout with marker := 0 }
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with abiLayout := abiBadPrefix })
    "IR abi fullPrefixBytes drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with abiLayout := abiBadMarker })
    "IR abi marker drift"

  -- IR: C layout drift
  let instrBadSize := { irCand.cLayouts.instruction with size := 41 }
  let metaBadAlign := { irCand.cLayouts.accountMeta with align := 4 }
  let cLayoutsBadInstr := { irCand.cLayouts with instruction := instrBadSize }
  let cLayoutsBadMeta := { irCand.cLayouts with accountMeta := metaBadAlign }
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with cLayouts := cLayoutsBadInstr })
    "IR instruction size drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with cLayouts := cLayoutsBadMeta })
    "IR accountMeta align drift"

  -- IR: roleHandles drift
  let some handle0 := irCand.roleHandles[0]? |
    throw <| IO.userError "IR handle0 missing"
  let handleRenamed := { handle0 with name := "renamed" }
  let handleConstraint := { handle0 with constraint := stateRoleConstraintV1 }
  let aliasBad := { handle0.aliasPolicy with outerRoleKeys := "allow" }
  let handleAlias := { handle0 with aliasPolicy := aliasBad }
  let handleDirect := {
    handle0 with
    directSignerContribution := !handle0.directSignerContribution
  }
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with roleHandles := irCand.roleHandles.set! 0 handleRenamed })
    "IR role handle name drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with roleHandles := irCand.roleHandles.set! 0 handleConstraint })
    "IR role handle constraint drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with roleHandles := irCand.roleHandles.set! 0 handleAlias })
    "IR role handle alias drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with roleHandles := irCand.roleHandles.set! 0 handleDirect })
    "IR role handle direct privilege drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with roleHandles := irCand.roleHandles.pop })
    "IR role handle truncated"

  -- IR: site drift
  let some site0 := irCand.sites[0]? |
    throw <| IO.userError "IR site0 missing"
  let siteBadProgram := { site0 with programHandleIndex := 0 }
  let siteBadProgramRole := { site0 with programRoleId := 0 }
  let siteBadInfoRoles := { site0 with accountInfoRoleIds := #[0, 1, 2] }
  let siteBadInfos := { site0 with accountInfoHandleIndices := #[0, 1, 2] }
  let siteBadQn := { site0 with qn := "solana.system.transfer" }
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with sites := #[siteBadProgram] })
    "IR site programHandleIndex drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with sites := #[siteBadProgramRole] })
    "IR site programRoleId drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with sites := #[siteBadInfoRoles] })
    "IR site accountInfoRoleIds drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with sites := #[siteBadInfos] })
    "IR site accountInfoHandleIndices drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with sites := #[siteBadQn] })
    "IR site qn drift"
  let some irMeta0 := site0.metas[0]? |
    throw <| IO.userError "IR site meta missing"
  let badIrMeta := {
    irMeta0 with spec := { irMeta0.spec with cpiWritable := !irMeta0.spec.cpiWritable }
  }
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with sites := #[{ site0 with metas := site0.metas.set! 0 badIrMeta }] })
    "IR site full meta spec drift"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with sites := #[{ site0 with outerOnlyAccounts := #[] }] })
    "IR site outer-only projection drift"

  -- IR: operations drift
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with operations := irCand.operations.pop })
    "IR operations truncated"
  expectPlanReject (validateSolanaCpiIRV1 plan
    { irCand with operations := #[] })
    "IR operations emptied"
  if h : irCand.operations.size ≥ 2 then
    let op0 := irCand.operations[0]
    let op1 := irCand.operations[1]
    let rest := irCand.operations.extract 2 irCand.operations.size
    let swapped := #[op1, op0] ++ rest
    expectPlanReject (validateSolanaCpiIRV1 plan
      { irCand with operations := swapped })
      "IR operations reordered"

  -- IDL: state schema drift (via stateOnly plan so schemas are nonempty)
  let stateCand ← expectOk stateOnlyCandidate "IDL mutation state candidate"
  let statePlan ← expectPlanOk (validateSolanaCpiPlanV1 stateCand)
    "IDL mutation state plan"
  let stateIdl ← expectPlanOk (deriveSolanaCpiIdlV1 statePlan)
    "IDL mutation state IDL"
  let stateIr ← expectPlanOk (deriveSolanaCpiIRV1 statePlan)
    "IR mutation state IR"
  let some schema0 := stateIdl.candidate.stateSchemas[0]? |
    throw <| IO.userError "state schema0 missing"
  let schemaLen := { schema0 with exactDataLen := 99 }
  let schemaName := { schema0 with name := "renamed" }
  expectPlanReject (validateSolanaCpiIdlV1 statePlan
    { stateIdl.candidate with stateSchemas := #[schemaLen] })
    "IDL state schema exactDataLen drift"
  expectPlanReject (validateSolanaCpiIdlV1 statePlan
    { stateIdl.candidate with stateSchemas := #[schemaName] })
    "IDL state schema name drift"
  expectPlanReject (validateSolanaCpiIRV1 statePlan
    { stateIr.candidate with stateSchemas := #[schemaLen] })
    "IR state schema exactDataLen drift"

  -- IDL: site program id / codec / meta / outer-only drift
  let some idlSite := idlCand.cpiSites[0]? |
    throw <| IO.userError "IDL site0 missing"
  let siteBadProgramId := {
    idlSite with
    programIdBase58 := SolanaPubkeyV1.toBase58 companionProgramIdV1
  }
  let siteBadCodec := {
    idlSite with
    instructionCodec := { idlSite.instructionCodec with length := 1 }
  }
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with cpiSites := #[siteBadProgramId] })
    "IDL site programIdBase58 drift"
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with cpiSites := #[siteBadCodec] })
    "IDL site codec length drift"
  let some meta0 := idlSite.metas[0]? |
    throw <| IO.userError "IDL meta0 missing"
  let metaRenamed := { meta0 with roleName := "renamed_meta" }
  let metaSpecFlipped := {
    meta0 with
    spec := { meta0.spec with cpiWritable := !meta0.spec.cpiWritable }
  }
  let siteMetaRenamed := {
    idlSite with metas := idlSite.metas.set! 0 metaRenamed
  }
  let siteMetaSpec := {
    idlSite with metas := idlSite.metas.set! 0 metaSpecFlipped
  }
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with cpiSites := #[siteMetaRenamed] })
    "IDL meta roleName drift"
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with cpiSites := #[siteMetaSpec] })
    "IDL meta full-spec drift"
  let siteOuterEmpty := { idlSite with outerOnlyAccounts := #[] }
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with cpiSites := #[siteOuterEmpty] })
    "IDL outer-only truncated"
  let some outer0 := idlSite.outerOnlyAccounts[0]? |
    throw <| IO.userError "IDL outer0 missing"
  let outerWrong := { outer0 with roleName := "wrong" }
  let siteOuterWrong := { idlSite with outerOnlyAccounts := #[outerWrong] }
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with cpiSites := #[siteOuterWrong] })
    "IDL outer-only roleName drift"

  -- IDL: instruction accounts drift
  let some instr0 := idlCand.instructions[0]? |
    throw <| IO.userError "IDL instruction0 missing"
  let instrTrunc := { instr0 with accounts := instr0.accounts.pop }
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with instructions := #[instrTrunc] })
    "IDL instruction accounts truncated"
  let some acc0 := instr0.accounts[0]? |
    throw <| IO.userError "IDL account0 missing"
  let accRenamed := { acc0 with name := "renamed_account" }
  let accPriv := { acc0 with outerWritable := !acc0.outerWritable }
  let accDirect := {
    acc0 with
    directWritableContribution := !acc0.directWritableContribution
  }
  let accAlias := {
    acc0 with
    aliasPolicy := { acc0.aliasPolicy with cpiSiteMetaKeys := "allow" }
  }
  let instrRenamed := {
    instr0 with accounts := instr0.accounts.set! 0 accRenamed
  }
  let instrPriv := {
    instr0 with accounts := instr0.accounts.set! 0 accPriv
  }
  let instrDirect := {
    instr0 with accounts := instr0.accounts.set! 0 accDirect
  }
  let instrAlias := {
    instr0 with accounts := instr0.accounts.set! 0 accAlias
  }
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with instructions := #[instrRenamed] })
    "IDL instruction account name drift"
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with instructions := #[instrPriv] })
    "IDL instruction account effective privilege drift"
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with instructions := #[instrDirect] })
    "IDL instruction account direct privilege drift"
  expectPlanReject (validateSolanaCpiIdlV1 plan
    { idlCand with instructions := #[instrAlias] })
    "IDL instruction account alias drift"

/-- Legacy `solana-sbpf-plan-v1` Counter engineering Plan digest + artifact
    SHA-256 pins. Namespace-qualified Solana surface avoids any CPI name clash. -/
private unsafe def testLegacyPlanProfileByteRegression : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← expectPlanOk (← session.selectProgramV1
    Examples.counterSourceText "<cpi-legacy-counter>"
    Examples.counterModuleNameV1 none) "legacy load Counter"
  let compiled ← expectPlanOk (Compiler.compileValidatedSourceV1 source)
    "legacy compile Counter"
  let selection ← expectPlanOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfPlanV1))
    "legacy select solana-sbpf-plan-v1"
  expect (selection.codegenProfile == CodegenProfileId.solanaSbpfPlanV1)
    "legacy profile is solana-sbpf-plan-v1"
  let capability ← expectPlanOk
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
    "legacy resolve capability"
  let plan ← expectPlanOk
    (Targets.Solana.planFromCapability capability) "legacy planFromCapability"
  let planDigest ← expectOk
    (Targets.Solana.engineeringSolanaPlanDigestV1 plan)
    "legacy engineeringSolanaPlanDigestV1"
  let planWire ← expectOk (renderDigest planDigest) "legacy plan digest wire"
  expect (planWire ==
    "sha256:a61ec3ebc5bbfe269036c5287598badc0cf8c7466b9cef8f904d9e96a235215d")
    s!"legacy Plan digest pin, got {planWire}"
  let files ← expectPlanOk
    (Targets.Solana.buildFromCapability capability)
    "legacy buildFromCapability"
  expect (files.map (·.path) == #["Counter.sbpf-plan", "Counter.idl.json"])
    s!"legacy files order, got {files.map (·.path)}"
  let some planFile := files.find? (·.path == "Counter.sbpf-plan") |
    throw <| IO.userError "legacy missing Counter.sbpf-plan"
  let some idlFile := files.find? (·.path == "Counter.idl.json") |
    throw <| IO.userError "legacy missing Counter.idl.json"
  let planSha ← expectOk (renderDigest (sha256Bytes planFile.contents.toUTF8))
    "legacy sbpf-plan sha"
  let idlSha ← expectOk (renderDigest (sha256Bytes idlFile.contents.toUTF8))
    "legacy idl sha"
  expect (planSha ==
    "sha256:993b59287c44e594bb620dac0a44855b6a868113a3cdae284247ac53a693af1c")
    s!"legacy Counter.sbpf-plan SHA-256 pin, got {planSha}"
  expect (idlSha ==
    "sha256:c146bd0b072371c4187e4b632f8aaf2af3b8631607f57e6794084c19c8ac1b57")
    s!"legacy Counter.idl.json SHA-256 pin, got {idlSha}"

unsafe def run : IO Unit := do
  testStrictPubkeyCarrier
  testFrozenContractProjection
  testPlanDeterminismAndAllApis
  testPlanMutationAndNegativeMatrix
  testPlanValidationPhaseOrder
  testHandlerLocalRoleSubsets
  testPlanToIrAndIdlProjection
  testIrAndIdlMutationNegatives
  testLegacyPlanProfileByteRegression
  IO.println "Tests.Materialization.SolanaCpiPlanV1: ok"

end Tests.Materialization.SolanaCpiPlanV1

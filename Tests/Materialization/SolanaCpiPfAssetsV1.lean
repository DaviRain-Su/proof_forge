/-
  Tests.Materialization.SolanaCpiPfAssetsV1 — ADR-0029 Phase B1 Solana lane.

  Pins:
    * QN gate: pf.assets catalog without declaration FC; async/token FC;
      non-catalog keeps product API filter;
    * vault PDA seeds recipe `proof-forge:vault:v1` + deposit/transfer site
      structure (role table, metas, signer groups);
    * dual extension: TipJar-shaped pf.assets-only program product Plan/IR/ELF
      assembly text contains vault ensure + transfer invoke;
    * deposit caller convention: exactly one outer signer.
-/
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiProductV1
import ProofForgeV2.Targets.Solana.CpiEscrowIRV1
import ProofForgeV2.Targets.Solana.EmitCpiEscrowSbpfV1
import ProofForgeV2.Targets.Solana.MaterializationV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.RequirementIdsV1
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiPfAssetsV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectPlanOk {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def expectPlanRejectContains {α : Type} (result : CompileResult α)
    (needle label : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.message.contains needle)
        s!"{label}: expected message containing '{needle}', got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly accepted"

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def pfAssetsHeader : String :=
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  "    digest \"sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9\"\n"

private def wrapProgram (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  s!"program {name} where\n" ++
  pfAssetsHeader ++
  body

private def tipJarLikeSource : String :=
  wrapProgram "TipJarPf" <|
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.native.deposit(amount)\n" ++
    "    call pf.assets.native.transfer(dst, amount)\n" ++
    "    tips := tips + amount\n" ++
    "    return tips\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"

private def noDeclTransferSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program NoDecl where\n" ++
  "  entry go(dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.native.transfer(dst, amount)\n" ++
  "    return amount\n"

private def asyncSource : String :=
  wrapProgram "AsyncOut" <|
    "  entry go(dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.native.transferAsync(dst, amount)\n" ++
    "    return amount\n"

private def tokenSource : String :=
  wrapProgram "TokenOut" <|
    "  entry go(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.token.transfer(mint, dst, amount)\n" ++
    "    return amount\n"

private def dualExtSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program DualExt where\n" ++
  "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
  "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  "    digest \"sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9\"\n" ++
  "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.native.deposit(amount)\n" ++
  "    call pf.assets.native.transfer(dst, amount)\n" ++
  "    return amount\n"

/-- ADR-0030 E2-3: native balanceOfSelf env-read source. A view that returns
    the vault PDA lamports. No ExternalCall sites — only envRead. -/
private def nativeBalanceSource : String :=
  wrapProgram "NativeBalance" <|
    "  view get() : UInt64 do\n" ++
    "    return pf.assets.native.balanceOfSelf()\n"

/-- ADR-0030 E2-3: token balanceOfSelf env-read source. A view that returns
    the vault ATA token amount for a given mint. -/
private def tokenBalanceSource : String :=
  wrapProgram "TokenBalance" <|
    "  view get(mint : Principal) : UInt64 do\n" ++
    "    return pf.assets.token.balanceOfSelf(mint)\n"

/-- ADR-0030 E2-3: envRead inside entry (not view) → fail closed. -/
private def envReadInEntrySource : String :=
  wrapProgram "EnvReadEntry" <|
    "  entry go() : UInt64 do\n" ++
    "    return pf.assets.native.balanceOfSelf()\n"

/-- ADR-0030 E2-3: envRead inside pureFn → fail closed. -/
private def envReadInPureFnSource : String :=
  wrapProgram "EnvReadPureFn" <|
    "  pureFn helper() : UInt64 do\n" ++
    "    return pf.assets.native.balanceOfSelf()\n"

/-- ADR-0030 E2-3: envRead without pf.assets declaration → fail closed. -/
private def envReadNoDeclSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program NoDeclBalance where\n" ++
  "  view get() : UInt64 do\n" ++
  "    return pf.assets.native.balanceOfSelf()\n"

/-- ADR-0031 S1 / ADR-0030 E3: context.caller on exact CPI profile — caller-only
    (no extension.pf-assets / sync-call ticket). Solana binds caller to the
    ABI-specified pf_caller signer role pubkey (NOT tx.origin). -/
private def contextCallerIsMeSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program CallerIsMe where\n" ++
  "  view isMe(who : Principal) : Bool do\n" ++
  "    return context.caller == who\n"

/-- Empty / no-call / no-env / no-caller program must not activate CPI product. -/
private def emptyNoCallerSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program EmptyNoCaller where\n" ++
  "  entry go() : UInt64 do\n" ++
  "    return 0\n"

/-- ADR-0031 S1: context.caller inside pureFn → fail closed. -/
private def contextCallerInPureFnSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program CallerPureFn where\n" ++
  "  pureFn helper(who : Principal) : Bool do\n" ++
  "    return context.caller == who\n" ++
  "  view get() : UInt64 do\n" ++
  "    return 0\n"

/-- ADR-0031 S1: context.unixTimeSeconds stays FC on CPI profile.
    Uses pf.assets so capability admits; Plan must still reject unixTime. -/
private def contextUnixTimeSource : String :=
  wrapProgram "UnixTimeView" <|
    "  view now() : UInt64 do\n" ++
    "    return context.unixTimeSeconds\n"

private unsafe def compileSource (text name : String) : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 text s!"<{name}>" s!"Examples.{name}" none with
  | .error e => throw <| IO.userError s!"{name} select failed: {e.render}"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .error e => throw <| IO.userError s!"{name} compile failed: {e.render}"
      | .ok c => pure c

private unsafe def productCapabilityOf (compiled : CompiledSemanticV1) :
    IO ResolvedEngineeringBuildV1 := do
  let selection ← expectPlanOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "build selection"
  expectPlanOk
    (resolveEngineeringRequirementsV1 selection compiled)
    "resolve engineering"

private unsafe def testContractPins : IO Unit := do
  expect (vaultPdaRuleIdV1 == "proof-forge:vault:v1") "vault rule id"
  expect (vaultPdaSeedHexV1 == "70726f6f662d666f7267653a7661756c743a7631")
    "vault seed hex"
  expect (isPfAssetsSolanaProductApiV1 "pf.assets.native.deposit") "deposit product"
  expect (isPfAssetsSolanaProductApiV1 "pf.assets.native.transfer") "transfer product"
  expect (!isPfAssetsSolanaProductApiV1 "pf.assets.native.transferAsync") "async not product"
  expect (isPfAssetsSolanaProductApiV1 "pf.assets.token.transfer") "token transfer product"
  expect (!isPfAssetsSolanaProductApiV1 "pf.assets.token.transferAsync") "token async not product"
  expect (isApprovedProductApiV1 "pf.assets.native.deposit") "approved additive"
  expect (activeProductApiQnsV1.size == 5) "docs five-QN pin intact"
  expect (findFrozenApi? "pf.assets.native.deposit").isSome "frozen deposit api"
  expect (findFrozenApi? "pf.assets.native.transfer").isSome "frozen transfer api"
  expect (findFrozenPdaRule? vaultPdaRuleIdV1).isSome "vault rule findable"
  expect (frozenPdaRulesV1.size == 2) "ADR-0028 two PDA recipes unchanged"

private unsafe def testTipJarProductPlanIrEmit : IO Unit := do
  let compiled ← compileSource tipJarLikeSource "TipJarPf"
  let cap ← productCapabilityOf compiled
  let plan ← expectPlanOk (productPlanFromCapabilityV1 cap) "product plan"
  let cand := SolanaCpiProductPlanV1.candidateOf plan
  expect (cand.programName == "TipJarPf") "program name"
  expect (cand.extensionRequirement.id == wireExtensionPfAssetsIdV1)
    "plan extension is pf.assets"
  expect (cand.cpiSites.size == 2) "deposit + transfer sites"
  let some dep := cand.cpiSites[0]? |
    throw <| IO.userError "missing deposit site"
  let some xfer := cand.cpiSites[1]? |
    throw <| IO.userError "missing transfer site"
  expect (dep.qn == "pf.assets.native.deposit") "site0 deposit"
  expect (xfer.qn == "pf.assets.native.transfer") "site1 transfer"
  expect (dep.packageId == "system-v1" && xfer.packageId == "system-v1")
    "both system-v1"
  expect (dep.metas.size == 2 && xfer.metas.size == 2) "two metas each"
  expect (dep.signerGroups.isEmpty) "deposit unsigned"
  expect (xfer.signerGroups.size == 1) "transfer signed"
  let some sg0 := xfer.signerGroups[0]? |
    throw <| IO.userError "missing signer group"
  expect (sg0.pdaRule == vaultPdaRuleIdV1) "vault rule on group"
  match xfer.pda with
  | .vaultPdaSigner rule =>
      expect (rule == vaultPdaRuleIdV1) "site pda vault rule"
  | _ => throw <| IO.userError "transfer site must carry vaultPdaSigner"
  let vaultRoles := cand.accountRoles.filter (fun r =>
    match r.keyPolicy with | .vaultPda => true | _ => false)
  expect (vaultRoles.size == 1) "exactly one vault role"
  let some vaultRole := vaultRoles[0]? |
    throw <| IO.userError "vault role missing"
  -- Entry admits System-fresh create OR current-program skip; owner is not a
  -- single currentProgram entry gate (that blocked first tip on unused vault).
  expect (vaultRole.constraint.owner == OwnerPolicy.any)
    "vault entry owner is .any (closed alternatives at ensure site-time)"
  expect (vaultRole.constraint.data == DataPolicy.exactLength 0)
    "vault entry exact empty data"
  expect (cand.accountRoles.any (fun r =>
      match r.keyPolicy with | .handlerCaller => true | _ => false))
    "caller role present"
  let tipH := cand.handlers.find? (·.name == "tip")
  let some tipHandler := tipH |
    throw <| IO.userError "tip handler missing"
  let outerSigners := tipHandler.accountUses.filter (·.outerSigner)
  expect (outerSigners.size == 1) "exactly one outer signer (caller)"
  -- Transfer site meta still requires current-program vault (post-ensure).
  let some xferVaultMeta := xfer.metas[0]? |
    throw <| IO.userError "transfer vault meta missing"
  expect (xferVaultMeta.spec.constraint.owner == OwnerPolicy.currentProgram)
    "transfer site vault meta keeps currentProgram owner"
  let ir ← expectPlanOk (productIrFromCapabilityV1 cap) "product IR"
  let irCand := ResolvedSolanaCpiProductIRV1.candidateOf ir
  let some tipIr := irCand.handlers.find? (·.name == "tip") |
    throw <| IO.userError "tip IR handler missing"
  expect (tipIr.bodyOps.any (fun
      | .invokeEscrow inv => inv.kind == .nativeDeposit
      | _ => false))
    "IR carries nativeDeposit invoke"
  expect (tipIr.bodyOps.any (fun
      | .invokeEscrow inv => inv.kind == .nativeTransfer
      | _ => false))
    "IR carries nativeTransfer invoke"
  -- Entry global ops must not hoist checkOwnerCurrentProgram on the vault role
  -- (that was Bug 1: first tip never reached ensure). Transfer siteChecks may.
  let vaultLocal? := tipIr.localRoleOrder.findSome? (fun h =>
    match h.keyPolicy with
    | .vaultPda => some h.localIndex
    | _ => none)
  let some vaultLi := vaultLocal? |
    throw <| IO.userError "vault localIndex missing on tip IR"
  let entryVaultOwnerCurrent := tipIr.entryGlobalOps.any (fun
    | .checkOwnerCurrentProgram li => li == vaultLi
    | _ => false)
  expect (!entryVaultOwnerCurrent)
    "entry must not checkOwnerCurrentProgram on vault (fresh System path)"
  let transferSiteOwnerCurrent := tipIr.bodyOps.any (fun
    | .siteChecks _ ops =>
        ops.any (fun
          | .generic (.checkOwnerCurrentProgram li) => li == vaultLi
          | _ => false)
    | _ => false)
  expect transferSiteOwnerCurrent
    "transfer siteChecks keep checkOwnerCurrentProgram on vault"
  let asm ← expectPlanOk (emitCpiProductSbpfV1 ir) "product assembly"
  let text := SolanaCpiProductAssemblyV1.textOf asm
  expect (hasSubstr text "nativeDeposit") "assembly mentions nativeDeposit"
  expect (hasSubstr text "nativeTransfer") "assembly mentions nativeTransfer"
  expect (hasSubstr text "proof-forge:vault:v1") "assembly vault seed comment"
  expect (hasSubstr text "sol_try_find_program_address") "find PDA"
  expect (hasSubstr text "sol_invoke_signed_c") "invoke signed"
  -- Bug 2 pin: ensure reads ROLE_DATA_LEN as scalar (jne r1, 0), never
  -- secondary-loads through the length as a pointer ([r1+0]).
  -- (Lamports still correctly do `ldxdw r3, [r1+0]` after ROLE_LAMPORTS.)
  expect
    (hasSubstr text
      "ldxdw r1, [r2 + ROLE_DATA_LEN]\n  jne r1, 0, err_shape")
    "ensure compares scalar ROLE_DATA_LEN to 0 (fail closed)"
  expect
    (!hasSubstr text
      "ldxdw r1, [r2 + ROLE_DATA_LEN]\n  ldxdw r3, [r1 + 0]")
    "ensure must not treat ROLE_DATA_LEN as a pointer (null-deref at data_len=0)"
  -- Closed alternatives: current-program XOR→skip, System zero-key, lamports=0.
  expect (hasSubstr text "SLOT_PROGRAM_ID")
    "ensure compares vault owner to current program"
  expect
    (hasSubstr text
      "ldxdw r1, [r2 + ROLE_LAMPORTS]\n  ldxdw r3, [r1 + 0]\n  jne r3, 0, err_shape")
    "ensure checks lamports==0 via pointer on fresh System create path"

private unsafe def testQnGateFailClosed : IO Unit := do
  -- catalog call without declaration freezes only sync-call (no extension row).
  -- Ordinary resolve on Solana CPI may accept sync-call alone; product
  -- capability / Plan still FC (no closed extension + QN gate).
  let compiled ← compileSource noDeclTransferSource "NoDecl"
  let selection ← expectPlanOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "selection"
  match resolveEngineeringRequirementsV1 selection compiled with
  | .error e =>
      -- Prefer exact extension unsupported if freeze somehow carried the row.
      expect
        (e.message.contains "extension.pf-assets" ||
          e.message.contains "extension.solana-cpi" ||
          e.message.contains "PF-REQ-UNSUPPORTED" ||
          e.code == "PF-REQ-UNSUPPORTED")
        s!"no-decl resolve error shape, got {e.render}"
  | .ok eng =>
      -- Capability requires solana.cpi and/or pf.assets.
      expectPlanRejectContains
        (productPlanFromCapabilityV1 eng)
        "extension"
        "no-decl product capability/plan FC"
  -- async with declaration: product plan FC at Phase scope (no token async).
  let cAsync ← compileSource asyncSource "AsyncOut"
  let capAsync ← productCapabilityOf cAsync
  expectPlanRejectContains (productPlanFromCapabilityV1 capAsync) "outside Phase"
    "AsyncOut plan FC"
  -- token.transfer with declaration: Plan/IR construct succeed; emit now
  -- produces composite assembly (ATA ensure x2 + transferCheckedPda).
  let cToken ← compileSource tokenSource "TokenOut"
  let capToken ← productCapabilityOf cToken
  let plan ← expectPlanOk (productPlanFromCapabilityV1 capToken) "token plan"
  let cand := SolanaCpiProductPlanV1.candidateOf plan
  expect (cand.cpiSites.size == 1) "token transfer one site"
  let some site := cand.cpiSites[0]? |
    throw <| IO.userError "missing token transfer site"
  expect (site.qn == "pf.assets.token.transfer") "site qn"
  expect (site.packageId == "token-classic-v1") "site package"
  expect (site.metas.size == 4) "token transfer four metas"
  let ir ← expectPlanOk (productIrFromCapabilityV1 capToken) "token IR"
  let irCand := ResolvedSolanaCpiProductIRV1.candidateOf ir
  let some h := irCand.handlers.find? (·.name == "go") |
    throw <| IO.userError "token IR handler missing"
  expect (h.bodyOps.any (fun
    | .invokeEscrow inv => inv.kind == .pfAssetsTokenTransfer
    | _ => false))
    "IR carries pfAssetsTokenTransfer invoke"
  -- Emit must now succeed (composite ATA ensure + transferCheckedPda).
  let asm ← expectPlanOk (emitCpiProductSbpfV1 ir) "token assembly"
  let text := SolanaCpiProductAssemblyV1.textOf asm
  expect (hasSubstr text "sol_invoke_signed_c") "token emit has invoke_signed_c"
  expect (hasSubstr text "sol_try_find_program_address") "token emit has find PDA"
  expect (hasSubstr text "proof-forge:vault:v1") "token emit has vault seed"
  expect (hasSubstr text "CreateIdempotent") "token emit has ATA ensure"
  expect (hasSubstr text "TokenInstruction::TransferChecked") "token emit has TransferChecked"
  expect (hasSubstr text "0x0c") "token emit has codec 0c"
  expect (hasSubstr text "step 1: find vault PDA") "token emit step 1"
  expect (hasSubstr text "step 6: Token transferCheckedPda") "token emit step 6"

private unsafe def testDualExtension : IO Unit := do
  let compiled ← compileSource dualExtSource "DualExt"
  let cap ← productCapabilityOf compiled
  let plan ← expectPlanOk (productPlanFromCapabilityV1 cap) "dual plan"
  let cand := SolanaCpiProductPlanV1.candidateOf plan
  -- Prefer solana.cpi.accounts when both present.
  expect (cand.extensionRequirement.id == wireExtensionSolanaCpiAccountsIdV1)
    "dual prefers solana.cpi.accounts on Plan field"
  expect (cand.cpiSites.size == 2) "dual still lowers two pf.assets sites"

/-- ADR-0030 E2-3: native balanceOfSelf Plan/IR/emit pins. -/
private unsafe def testNativeBalanceEnvRead : IO Unit := do
  let compiled ← compileSource nativeBalanceSource "NativeBalance"
  let cap ← productCapabilityOf compiled
  let plan ← expectPlanOk (productPlanFromCapabilityV1 cap) "native balance plan"
  let cand := SolanaCpiProductPlanV1.candidateOf plan
  -- No CPI sites; one envRead site
  expect (cand.cpiSites.isEmpty) "native balance: zero CPI sites"
  expect (cand.envReadSites.size == 1) "native balance: one envRead site"
  let some envSite := cand.envReadSites[0]? |
    throw <| IO.userError "native balance: envRead site missing"
  expect (envSite.kind == .nativeVaultBalance) "native balance: kind"
  expect (envSite.handlerId == 0) "native balance: handlerId 0 (get view)"
  -- Vault role must be present
  let vaultRoles := cand.accountRoles.filter (fun r =>
    match r.keyPolicy with | .vaultPda => true | _ => false)
  expect (vaultRoles.size == 1) "native balance: one vault role"
  let some vaultRole := vaultRoles[0]? |
    throw <| IO.userError "native balance: vault role missing"
  expect (envSite.vaultRoleId == vaultRole.roleId)
    "native balance: envRead vaultRoleId matches"
  -- Handler accountUses must include the vault role
  let some getHandler := cand.handlers.find? (·.name == "get") |
    throw <| IO.userError "native balance: get handler missing"
  expect (getHandler.mode == .view) "native balance: get is view"
  expect (getHandler.accountUses.any (·.roleId == vaultRole.roleId))
    "native balance: get handler includes vault role"
  -- IR
  let ir ← expectPlanOk (productIrFromCapabilityV1 cap) "native balance IR"
  let irCand := ResolvedSolanaCpiProductIRV1.candidateOf ir
  let some getIr := irCand.handlers.find? (·.name == "get") |
    throw <| IO.userError "native balance: get IR handler missing"
  expect (getIr.bodyOps.any (fun
    | .envReadVaultBalance _ kind _ _ _ _ _ _ => kind == .nativeVaultBalance
    | _ => false))
    "native balance: IR carries envReadVaultBalance native"
  expect (getIr.bodyOps.any (fun
    | .returnU64 _ => true
    | .returnNone => true
    | _ => false))
    "native balance: IR has return"
  -- Emit
  let asm ← expectPlanOk (emitCpiProductSbpfV1 ir) "native balance assembly"
  let text := SolanaCpiProductAssemblyV1.textOf asm
  expect (hasSubstr text "envReadVaultBalance: native") "native balance: assembly label"
  expect (hasSubstr text "sol_try_find_program_address") "native balance: find PDA"
  expect (hasSubstr text "proof-forge:vault:v1") "native balance: vault seed"
  expect (hasSubstr text "ROLE_LAMPORTS") "native balance: reads lamports"

/-- ADR-0030 E2-3: token balanceOfSelf Plan/IR/emit pins. -/
private unsafe def testTokenBalanceEnvRead : IO Unit := do
  let compiled ← compileSource tokenBalanceSource "TokenBalance"
  let cap ← productCapabilityOf compiled
  let plan ← expectPlanOk (productPlanFromCapabilityV1 cap) "token balance plan"
  let cand := SolanaCpiProductPlanV1.candidateOf plan
  expect (cand.cpiSites.isEmpty) "token balance: zero CPI sites"
  expect (cand.envReadSites.size == 1) "token balance: one envRead site"
  let some envSite := cand.envReadSites[0]? |
    throw <| IO.userError "token balance: envRead site missing"
  expect (envSite.kind == .tokenVaultBalance) "token balance: kind"
  -- Roles: vault, vaultAta, mint param, system-v1, token-classic-v1, ata-classic-v1
  let vaultRoles := cand.accountRoles.filter (fun r =>
    match r.keyPolicy with | .vaultPda => true | _ => false)
  expect (vaultRoles.size == 1) "token balance: one vault role"
  let vaultAtaRoles := cand.accountRoles.filter (fun r =>
    match r.keyPolicy with | .vaultAta => true | _ => false)
  expect (vaultAtaRoles.size == 1) "token balance: one vaultAta role"
  let mintRoles := cand.accountRoles.filter (fun r =>
    match r.keyPolicy with | .accountParameter _ _ => true | _ => false)
  expect (mintRoles.size == 1) "token balance: one mint param role"
  -- IR
  let ir ← expectPlanOk (productIrFromCapabilityV1 cap) "token balance IR"
  let irCand := ResolvedSolanaCpiProductIRV1.candidateOf ir
  let some getIr := irCand.handlers.find? (·.name == "get") |
    throw <| IO.userError "token balance: get IR handler missing"
  expect (getIr.bodyOps.any (fun
    | .envReadVaultBalance _ kind _ _ _ _ _ _ => kind == .tokenVaultBalance
    | _ => false))
    "token balance: IR carries envReadVaultBalance token"
  -- Emit
  let asm ← expectPlanOk (emitCpiProductSbpfV1 ir) "token balance assembly"
  let text := SolanaCpiProductAssemblyV1.textOf asm
  expect (hasSubstr text "envReadVaultBalance: token") "token balance: assembly label"
  expect (hasSubstr text "sol_try_find_program_address") "token balance: find PDA"
  expect (hasSubstr text "proof-forge:vault:v1") "token balance: vault seed"
  expect (hasSubstr text "find vault ATA") "token balance: ATA find"

/-- ADR-0030 E2-3: envRead fail-closed negatives. -/
private unsafe def testEnvReadFailClosed : IO Unit := do
  -- envRead in entry (not view) → Plan FC
  let cEntry ← compileSource envReadInEntrySource "EnvReadEntry"
  let capEntry ← productCapabilityOf cEntry
  expectPlanRejectContains (productPlanFromCapabilityV1 capEntry)
    "envRead" "envRead in entry must fail closed"
  -- envRead in pureFn → compile/select FC (effect-free op in effect-bearing pureFn
  -- is rejected at the Typed/Normalize boundary before Plan)
  let session2 ← Tests.Language.ParserSession.shared
  match ← session2.selectProgramV1 envReadInPureFnSource "<EnvReadPureFn>" "Examples.EnvReadPureFn" none with
  | .error e =>
      expect (e.render.contains "unsupported") "envRead pureFn should fail at compile"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .error e =>
          expect (e.render.contains "unsupported") "envRead pureFn compile should fail"
      | .ok _ =>
          throw <| IO.userError "envRead pureFn unexpectedly compiled"
  -- envRead without pf.assets declaration → compile FC
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 envReadNoDeclSource "<NoDeclBalance>" "Examples.NoDeclBalance" none with
  | .error e =>
      expect (e.render.contains "extension" || e.render.contains "pf.assets")
        s!"envRead no-decl should fail at compile, got {e.render}"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .error e =>
          expect (e.render.contains "extension" || e.render.contains "pf.assets")
            s!"envRead no-decl compile should fail, got {e.render}"
      | .ok _ =>
          throw <| IO.userError "envRead no-decl unexpectedly compiled"

/-- ADR-0031 S1 / ADR-0030 E3: context.caller Plan/IR/emit pins (caller-only).
    caller = ABI-specified pf_caller signer role (NOT tx.origin).
    who Principal stays T12 ix-data (9 leaves), not account-bound.
    Ordinary Principal ix params get validatePrincipalIx before comparison. -/
private unsafe def testContextCallerIsMe : IO Unit := do
  let compiled ← compileSource contextCallerIsMeSource "CallerIsMe"
  let cap ← productCapabilityOf compiled
  let plan ← expectPlanOk (productPlanFromCapabilityV1 cap) "caller plan"
  let cand := SolanaCpiProductPlanV1.candidateOf plan
  expect (cand.cpiSites.isEmpty) "caller: zero CPI sites"
  expect (cand.envReadSites.isEmpty) "caller: zero envRead sites"
  expect (cand.contextReadSites.size == 1) "caller: one contextRead site"
  -- Admission marker is exact wire-owned context.caller (not fake pf.assets).
  expect (cand.extensionRequirement.id == wireContextCallerIdV1)
    s!"caller: Plan admission marker is context.caller, got {cand.extensionRequirement.id}"
  expect (cand.extensionRequirement.id != wireExtensionPfAssetsIdV1)
    "caller: must not claim extension.pf-assets admission"
  let some ctxSite := cand.contextReadSites[0]? |
    throw <| IO.userError "caller: contextRead site missing"
  -- pf_caller role (sole outer role for isMe)
  let callerRoles := cand.accountRoles.filter (fun r =>
    match r.keyPolicy with | .handlerCaller => true | _ => false)
  expect (callerRoles.size == 1) "caller: one handlerCaller role"
  let some callerRole := callerRoles[0]? |
    throw <| IO.userError "caller: handlerCaller missing"
  expect (callerRole.name == "pf_caller") "caller: role name pf_caller"
  expect (ctxSite.callerRoleId == callerRole.roleId)
    "caller: site binds pf_caller roleId"
  -- who is T12 ix-data Principal — NOT an accountParameter role
  let whoRoles := cand.accountRoles.filter (fun r =>
    match r.keyPolicy with | .accountParameter _ _ => true | _ => false)
  expect (whoRoles.isEmpty)
    "caller: who Principal is T12 ix-data, not account-bound"
  expect (cand.accountRoles.size == 1)
    "caller: sole outer role is pf_caller"
  -- handler outerSigner
  let some isMeH := cand.handlers.find? (·.name == "isMe") |
    throw <| IO.userError "caller: isMe handler missing"
  expect (isMeH.accountUses.size == 1) "caller: one outer account use"
  let outerSigners := isMeH.accountUses.filter (·.outerSigner)
  expect (outerSigners.size == 1) "caller: exactly one outer signer"
  expect (outerSigners.any (fun u => u.roleId == ctxSite.callerRoleId))
    "caller: outerSigner is pf_caller"
  -- IR
  let ir ← expectPlanOk (productIrFromCapabilityV1 cap) "caller IR"
  let irCand := ResolvedSolanaCpiProductIRV1.candidateOf ir
  let some isMeIr := irCand.handlers.find? (·.name == "isMe") |
    throw <| IO.userError "caller: isMe IR handler missing"
  -- probe ix = handlerId(8) + Principal T12 9×u64 (72) = 80
  expect (isMeIr.probeIxDataLen == 80)
    s!"caller: probeIxDataLen 80 (handler+9-leaf Principal), got {isMeIr.probeIxDataLen}"
  -- who stays ix-lazy (no loadParamU64); caller materializes 9 leaves;
  -- principalLeafEqIx compares base vs ix; returnU64 Bool.
  let loadCount := isMeIr.bodyOps.foldl (fun n op =>
    match op with | .loadParamU64 .. => n + 1 | _ => n) 0
  expect (loadCount == 0)
    s!"caller: who is ix-lazy (0 param loads), got {loadCount}"
  -- validatePrincipalIx must precede business comparison (paramIx-derived).
  let vpixIdx? := isMeIr.bodyOps.findIdx? (fun op =>
    match op with | .validatePrincipalIx _ => true | _ => false)
  let eqIxIdx? := isMeIr.bodyOps.findIdx? (fun op =>
    match op with | .principalLeafEqIx .. => true | _ => false)
  let some vpixIdx := vpixIdx? |
    throw <| IO.userError "caller: IR missing validatePrincipalIx"
  let some eqIxIdx := eqIxIdx? |
    throw <| IO.userError "caller: IR missing principalLeafEqIx"
  expect (vpixIdx < eqIxIdx)
    s!"caller: validatePrincipalIx@{vpixIdx} must precede principalLeafEqIx@{eqIxIdx}"
  expect (isMeIr.bodyOps.any (fun op =>
    match op with
    | .validatePrincipalIx 8 => true
    | _ => false))
    "caller: validatePrincipalIx at who T12 offset 8 (after handlerId)"
  expect (isMeIr.bodyOps.any (fun op =>
    match op with
    | .contextReadCaller .. => true
    | _ => false))
    "caller: IR carries contextReadCaller (9-leaf materialize)"
  expect (isMeIr.bodyOps.any (fun op =>
    match op with
    | .principalLeafEqIx .. => true
    | _ => false))
    "caller: IR carries principalLeafEqIx (temps vs T12 ix)"
  expect (isMeIr.bodyOps.any (fun op =>
    match op with
    | .returnU64 _ => true
    | _ => false))
    "caller: IR returns Bool-as-UInt64"
  -- temp budget: caller 9 leaves + bool 1 = 10 ≤ 16
  expect (isMeIr.tempCount == 10)
    s!"caller: tempCount 10 (9 Principal leaves + Bool), got {isMeIr.tempCount}"
  expect (isMeIr.tempCount ≤ escrowMaxTempsV1)
    s!"caller: tempCount {isMeIr.tempCount} must be ≤ escrowMaxTempsV1={escrowMaxTempsV1}"
  -- Emit
  let asm ← expectPlanOk (emitCpiProductSbpfV1 ir) "caller assembly"
  let text := SolanaCpiProductAssemblyV1.textOf asm
  expect (hasSubstr text "contextReadCaller") "caller: assembly label"
  expect (hasSubstr text "not tx.origin") "caller: honesty comment in asm"
  expect (hasSubstr text "is_signer required") "caller: site-time signer check"
  expect (hasSubstr text "principalLeafEqIx") "caller: leaf-eq-ix label"
  expect (hasSubstr text "validatePrincipalIx") "caller: canonical Principal gate"
  expect (hasSubstr text "high-tail body bytes zero") "caller: high-tail zero comment"
  expect (hasSubstr text "jlt r1, 1, err_shape") "caller: len < 1 rejected"
  expect (hasSubstr text "jgt r1, 64, err_shape") "caller: len > 64 rejected"
  expect (hasSubstr text "ROLE_KEY") "caller: reads pf_caller key"
  expect (hasSubstr text "lddw r3, 32") "caller: materializes len=32 leaf"
  expect (hasSubstr text "checkEffectiveSigner")
    "caller: entry also enforces outerSigner"

/-- Empty/no-call/no-env/no-caller must not mint CPI product capability. -/
private unsafe def testEmptyProgramDoesNotActivateCpiLane : IO Unit := do
  let compiled ← compileSource emptyNoCallerSource "EmptyNoCaller"
  let selection ← expectPlanOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "empty selection"
  let eng ← expectPlanOk
    (resolveEngineeringRequirementsV1 selection compiled)
    "empty resolve engineering"
  -- Capability refine (via product plan entry) must reject: no extension,
  -- no sync-call, no context.caller.
  expectPlanRejectContains (productPlanFromCapabilityV1 eng)
    "context.caller"
    "empty program must not activate CPI product lane"

/-- ADR-0031 S1 fail-closed negatives. -/
private unsafe def testContextCallerFailClosed : IO Unit := do
  -- pureFn → FC at compile/Normalize (invariant/pureFn structure gate)
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 contextCallerInPureFnSource
      "<CallerPureFn>" "Examples.CallerPureFn" none with
  | .error e =>
      expect (e.render.contains "unsupported" || e.render.contains "context" ||
          e.render.contains "pureFn" || e.render.contains "PureFn")
        s!"caller pureFn should fail, got {e.render}"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .error e =>
          expect (e.render.contains "unsupported" || e.render.contains "context" ||
              e.render.contains "pureFn" || e.render.contains "PureFn" ||
              e.render.contains "invariant")
            s!"caller pureFn compile should fail, got {e.render}"
      | .ok _ =>
          throw <| IO.userError "caller pureFn unexpectedly compiled"
  -- unixTimeSeconds stays FC at Plan on CPI profile
  let cTime ← compileSource contextUnixTimeSource "UnixTimeView"
  let capTime ← productCapabilityOf cTime
  expectPlanRejectContains (productPlanFromCapabilityV1 capTime)
    "unixTimeSeconds" "unixTimeSeconds must stay FC on CPI profile"
  -- Legacy profiles (plan/elf) deep FC on ContextRead via LowerSemanticV1
  for profile in #[CodegenProfileId.solanaSbpfPlanV1,
      CodegenProfileId.solanaSbpfElfV1] do
    let selection ← expectPlanOk
      (resolveBuildSelectionV1 TargetId.solana (some profile))
      s!"legacy select {profile}"
    -- CallerIsMe freezes context.caller requirement (wire-owned). Legacy
    -- planFromCapability → LowerSemantic FC. No pf.assets ticket.
    let bareCaller :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      "program CallerLegacy where\n" ++
      "  view isMe(who : Principal) : Bool do\n" ++
      "    return context.caller == who\n"
    let compiled ← compileSource bareCaller "CallerLegacy"
    let eng ← expectPlanOk
      (resolveEngineeringRequirementsV1 selection compiled)
      s!"legacy resolve {profile}"
    match ProofForgeV2.Targets.Solana.planFromCapability eng with
    | .error e =>
        -- Deep FC: ContextRead key decline, or earlier Principal/Bool pilot
        -- shape gates on legacy LowerSemantic. Either way, no Plan carrier.
        expect
          (e.render.contains "ContextRead" || e.render.contains "context" ||
            e.render.contains "not admitted" || e.render.contains "unsupported" ||
            e.render.contains "PF-PLAN" || e.render.contains "plan" ||
            e.render.contains "profile")
          s!"legacy {profile}: expected Plan FC, got {e.render}"
    | .ok (.legacy _) =>
        throw <| IO.userError
          s!"legacy {profile}: must fail closed on context.caller, got .legacy Plan"
    | .ok (.cpi _) =>
        throw <| IO.userError
          s!"legacy {profile}: must not enter CPI Plan for context.caller"

unsafe def run : IO Unit := do
  testContractPins
  testTipJarProductPlanIrEmit
  testQnGateFailClosed
  testDualExtension
  testNativeBalanceEnvRead
  testTokenBalanceEnvRead
  testEnvReadFailClosed
  testContextCallerIsMe
  testEmptyProgramDoesNotActivateCpiLane
  testContextCallerFailClosed
  IO.println "Tests.Materialization.SolanaCpiPfAssetsV1: ok"

end Tests.Materialization.SolanaCpiPfAssetsV1

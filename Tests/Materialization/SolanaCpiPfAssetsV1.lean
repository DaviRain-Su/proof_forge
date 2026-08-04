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
  "  requires extension pf.assets version \"1.0.0\"\n" ++
  "    digest \"sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed\"\n"

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
  "  requires extension pf.assets version \"1.0.0\"\n" ++
  "    digest \"sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed\"\n" ++
  "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.native.deposit(amount)\n" ++
  "    call pf.assets.native.transfer(dst, amount)\n" ++
  "    return amount\n"

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
  expect (cand.accountRoles.any (fun r =>
      match r.keyPolicy with | .vaultPda => true | _ => false))
    "vault role present"
  expect (cand.accountRoles.any (fun r =>
      match r.keyPolicy with | .handlerCaller => true | _ => false))
    "caller role present"
  let tipH := cand.handlers.find? (·.name == "tip")
  let some tipHandler := tipH |
    throw <| IO.userError "tip handler missing"
  let outerSigners := tipHandler.accountUses.filter (·.outerSigner)
  expect (outerSigners.size == 1) "exactly one outer signer (caller)"
  let ir ← expectPlanOk (productIrFromCapabilityV1 cap) "product IR"
  let irCand := ResolvedSolanaCpiProductIRV1.candidateOf ir
  expect (irCand.handlers.any (fun h =>
      h.bodyOps.any (fun
        | .invokeEscrow inv =>
            inv.kind == .nativeDeposit || inv.kind == .nativeTransfer
        | _ => false)))
    "IR carries nativeDeposit/nativeTransfer invokes"
  let asm ← expectPlanOk (emitCpiProductSbpfV1 ir) "product assembly"
  let text := SolanaCpiProductAssemblyV1.textOf asm
  expect (hasSubstr text "nativeDeposit") "assembly mentions nativeDeposit"
  expect (hasSubstr text "nativeTransfer") "assembly mentions nativeTransfer"
  expect (hasSubstr text "proof-forge:vault:v1") "assembly vault seed comment"
  expect (hasSubstr text "sol_try_find_program_address") "find PDA"
  expect (hasSubstr text "sol_invoke_signed_c") "invoke signed"

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
  -- async / token with declaration: product plan FC at Phase B scope.
  for (src, name, needle) in #[
    (asyncSource, "AsyncOut", "outside Phase B"),
    (tokenSource, "TokenOut", "outside Phase B")
  ] do
    let c ← compileSource src name
    let cap ← productCapabilityOf c
    expectPlanRejectContains (productPlanFromCapabilityV1 cap) needle
      s!"{name} plan FC"

private unsafe def testDualExtension : IO Unit := do
  let compiled ← compileSource dualExtSource "DualExt"
  let cap ← productCapabilityOf compiled
  let plan ← expectPlanOk (productPlanFromCapabilityV1 cap) "dual plan"
  let cand := SolanaCpiProductPlanV1.candidateOf plan
  -- Prefer solana.cpi.accounts when both present.
  expect (cand.extensionRequirement.id == wireExtensionSolanaCpiAccountsIdV1)
    "dual prefers solana.cpi.accounts on Plan field"
  expect (cand.cpiSites.size == 2) "dual still lowers two pf.assets sites"

unsafe def run : IO Unit := do
  testContractPins
  testTipJarProductPlanIrEmit
  testQnGateFailClosed
  testDualExtension
  IO.println "Tests.Materialization.SolanaCpiPfAssetsV1: ok"

end Tests.Materialization.SolanaCpiPfAssetsV1

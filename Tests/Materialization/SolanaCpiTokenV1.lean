/-
  Tests.Materialization.SolanaCpiTokenV1 — #122 classic Token CPI IR/emitter.

  Authority path:
  Loader → product compile → preflight capability → Semantic Plan
  → Token IR (from SolanaCpiPreflightPlanV1; NOT ResolvedSolanaCpiPreflightIRV1)
  → Token emitter.

  Pins: transferChecked / transferCheckedPda only, 10B codec tag 0x0c,
  metas source/mint/destination/authority|authorityPda, seedAuthority outer
  signer for Pda, bump0 reject, classic Token package/program-id, frame cap,
  siteArgChecks → siteChecks → invoke order, Token-2022/System/companion/ATA/
  multi-block rejection, old-lane independence, #125 ordinary resolver + product
  Plan/IR success for approved Token closure (preactivation pins and
  isProductArtifact=false unchanged).
-/
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiProductV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.CpiPdaIRV1
import ProofForgeV2.Targets.Solana.CpiUnsignedIRV1
import ProofForgeV2.Targets.Solana.CpiSystemIRV1
import ProofForgeV2.Targets.Solana.CpiTokenIRV1
import ProofForgeV2.Targets.Solana.EmitCpiTokenSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiTokenV1

open ProofForgeV2
open ProofForgeV2.Core.Common
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
      expect (error.code == "PF-PLAN-INVARIANT" && error.message.contains needle)
        s!"{label}: expected PF-PLAN-INVARIANT containing '{needle}', got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly accepted"

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def countSubstr (haystack needle : String) : Nat :=
  (haystack.splitOn needle).length - 1

private def extensionHeader : String :=
  "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
  "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n"

private def wrapProgram (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  s!"program {name} where\n" ++
  extensionHeader ++
  body

/-- Combined transferChecked + transferCheckedPda fixture with state mutation. -/
private def tokenCpiSource : String :=
  wrapProgram "TokenCpi" <|
    "  state value : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    value := initial\n" ++
    "  entry transferChecked(source : Principal, mint : Principal,\n" ++
    "      destination : Principal, authority : Principal,\n" ++
    "      amount : UInt64, decimals : UInt8) : UInt64 do\n" ++
    "    value := value + 1\n" ++
    "    call solana.token.transferChecked(source, mint, destination,\n" ++
    "      authority, amount, decimals)\n" ++
    "    value := value + 2\n" ++
    "    return value\n" ++
    "  entry transferCheckedPda(source : Principal, mint : Principal,\n" ++
    "      destination : Principal, authorityPda : Principal,\n" ++
    "      seedAuthority : Principal, seedTag : UInt64, bump : UInt8,\n" ++
    "      amount : UInt64, decimals : UInt8) : UInt64 do\n" ++
    "    value := value + 1\n" ++
    "    call solana.token.transferCheckedPda(source, mint, destination,\n" ++
    "      authorityPda, seedAuthority, seedTag, bump, amount, decimals)\n" ++
    "    value := value + 2\n" ++
    "    return value\n" ++
    "  view inspect() : UInt64 do\n" ++
    "    return value\n"

private def transferOnlySource : String :=
  wrapProgram "TokenTransferOnly" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry transfer(source : Principal, mint : Principal,\n" ++
    "      destination : Principal, authority : Principal,\n" ++
    "      amount : UInt64, decimals : UInt8) : UInt64 do\n" ++
    "    call solana.token.transferChecked(source, mint, destination,\n" ++
    "      authority, amount, decimals)\n" ++
    "    return 0\n"

private def bumpZeroSource : String :=
  wrapProgram "TokenBumpZero" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry transferPda(source : Principal, mint : Principal,\n" ++
    "      destination : Principal, authorityPda : Principal,\n" ++
    "      seedAuthority : Principal, seedTag : UInt64,\n" ++
    "      amount : UInt64, decimals : UInt8) : UInt64 do\n" ++
    "    let bump : UInt8 := 0\n" ++
    "    call solana.token.transferCheckedPda(source, mint, destination,\n" ++
    "      authorityPda, seedAuthority, seedTag, bump, amount, decimals)\n" ++
    "    return 0\n"

private def companionSource : String :=
  wrapProgram "TokenRejectCompanion" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry invokeOnce(account : Principal, delta : UInt64) : UInt64 do\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    return value\n"

private def systemTransferSource : String :=
  wrapProgram "TokenRejectSystem" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry transfer(payer : Principal, recipient : Principal,\n" ++
    "      lamports : UInt64) : UInt64 do\n" ++
    "    call solana.system.transfer(payer, recipient, lamports)\n" ++
    "    return 0\n"

private def ataSource : String :=
  wrapProgram "TokenRejectAta" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry create(payer : Principal, ata : Principal,\n" ++
    "      wallet : Principal, mint : Principal) : UInt64 do\n" ++
    "    call solana.ata.createIdempotent(payer, ata, wallet, mint)\n" ++
    "    return 0\n"

private def multiBlockSource : String :=
  wrapProgram "TokenRejectBranch" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry branchy(source : Principal, mint : Principal,\n" ++
    "      destination : Principal, authority : Principal,\n" ++
    "      amount : UInt64, decimals : UInt8) : UInt64 do\n" ++
    "    if amount == 0 then\n" ++
    "      value := amount\n" ++
    "    else\n" ++
    "      value := 1\n" ++
    "    call solana.token.transferChecked(source, mint, destination,\n" ++
    "      authority, amount, decimals)\n" ++
    "    return value\n"

/-- Unknown Token-2022 QN must fail closed (no frozen API). -/
private def token2022Source : String :=
  wrapProgram "TokenReject2022" <|
    "  state value : UInt64\n" ++
    "  init() do\n" ++
    "    value := 0\n" ++
    "  entry transfer(source : Principal, mint : Principal,\n" ++
    "      destination : Principal, authority : Principal,\n" ++
    "      amount : UInt64, decimals : UInt8) : UInt64 do\n" ++
    "    call solana.token2022.transferChecked(source, mint, destination,\n" ++
    "      authority, amount, decimals)\n" ++
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
    "resolve CPI profile"

private unsafe def fullTokenChain
    (session : Language.Loader.ParserSession)
    (source moduleName path : String) :
    IO (ResolvedSolanaCpiTokenIRV1 × SolanaCpiTokenAssemblyV1) := do
  let compiled ← compileSource session source moduleName path
  let selection ← cpiSelection
  let preflight ← expectPlanOk
    (resolveSolanaCpiPreflightV1 selection compiled) "preflight"
  let plan ← expectPlanOk
    (deriveSolanaCpiPlanFromPreflightV1 preflight) "derive plan"
  let tok ← expectPlanOk
    (resolveSolanaCpiTokenIRV1 plan) "token IR"
  let asm ← expectPlanOk
    (emitCpiTokenSbpfV1 tok) "emit token"
  pure (tok, asm)

private unsafe def planOnly
    (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO SolanaCpiPreflightPlanV1 := do
  let compiled ← compileSource session source moduleName path
  let selection ← cpiSelection
  let preflight ← expectPlanOk
    (resolveSolanaCpiPreflightV1 selection compiled) "preflight"
  expectPlanOk (deriveSolanaCpiPlanFromPreflightV1 preflight) "derive plan"

/-- Plan derivation may itself fail closed for unknown QNs. -/
private unsafe def expectPlanOrCompileReject
    (session : Language.Loader.ParserSession)
    (source moduleName path needle label : String) : IO Unit := do
  let compiled ← try
    compileSource session source moduleName path
  catch e =>
    -- product compile may already reject unknown external QNs
    let msg := toString e
    expect (msg.contains needle || msg.contains "compile" || msg.contains "load")
      s!"{label}: unexpected compile error {msg}"
    return
  let selection ← cpiSelection
  match resolveSolanaCpiPreflightV1 selection compiled with
  | .error error =>
      expect (error.message.contains needle ||
          error.code == "PF-PLAN-INVARIANT" ||
          error.code == "PF-REQ-UNSUPPORTED" ||
          error.code == "PF-SRC-INVALID")
        s!"{label}: preflight reject without '{needle}': {error.render}"
  | .ok preflight =>
      match deriveSolanaCpiPlanFromPreflightV1 preflight with
      | .error error =>
          expect (error.message.contains needle || error.code == "PF-PLAN-INVARIANT")
            s!"{label}: plan reject without '{needle}': {error.render}"
      | .ok plan =>
          expectPlanRejectContains
            (resolveSolanaCpiTokenIRV1 plan) needle label

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  -- Positive combined chain.
  let (tok, asm) ← fullTokenChain session tokenCpiSource
    "Examples.TokenCpi" "runtime-tests/solana/fixtures/TokenCpi.lean"
  let cand := ResolvedSolanaCpiTokenIRV1.candidateOf tok
  expect (cand.schema == tokenIrSchemaV1) "schema proof-forge.solana.cpi-token-ir.v1"
  expect (cand.handlers.size == 4)
    "expected 4 handlers (init/transferChecked/transferCheckedPda/inspect)"

  -- Strict siteArgChecks → siteChecks → invoke order on every invoke.
  for h in cand.handlers do
    let ops := h.bodyOps
    for i in [0:ops.size] do
      match ops[i]! with
      | .invokeToken inv =>
          expect (i ≥ 2) s!"{h.name}: invoke without preceding ops"
          match ops[i - 2]!, ops[i - 1]! with
          | .siteArgChecks sidA _, .siteChecks sidC _ =>
              expect (sidA == inv.siteId && sidC == inv.siteId)
                s!"{h.name}: siteArgChecks/siteChecks/invoke site mismatch"
          | _, _ =>
              throw <| IO.userError
                s!"{h.name}: invoke not preceded by siteArgChecks→siteChecks"
      | _ => pure ()

  -- transferChecked exact Plan join / 10B codec / metas.
  let some transferHandler := cand.handlers.find? (fun h => h.name == "transferChecked") |
    throw <| IO.userError "missing transferChecked"
  expect (transferHandler.probeIxDataLen == 17)
    "transfer probe packs handlerId8 + amount8 + decimals1"
  let some tInv := transferHandler.bodyOps.findSome? (fun
      | .invokeToken i => some i
      | _ => none) |
    throw <| IO.userError "missing transferChecked invoke"
  expect (tInv.kind == .transferChecked &&
      tInv.qn == "solana.token.transferChecked" &&
      tInv.packageId == "token-classic-v1" && tInv.dataLen == 10)
    "transferChecked frozen qn/package/dataLen"
  expect (tInv.source.argIndex == 0 && tInv.mint.argIndex == 1 &&
      tInv.destination.argIndex == 2)
    "transferChecked Principal arg indices 0/1/2"
  let some auth := tInv.authority | throw <| IO.userError "authority missing"
  expect (auth.argIndex == 3) "authority arg index 3"
  expect (tInv.metas.size == 4 && tInv.outerOnly.isEmpty &&
      tInv.signerGroupId.isNone)
    "transferChecked four metas, zero outer-only, zero signer groups"
  expect (tInv.metas[0]!.roleId == tInv.source.roleId &&
      tInv.metas[0]!.localIndex == tInv.source.localIndex &&
      tInv.metas[0]!.cpiWritable == true && tInv.metas[0]!.cpiSigner == false)
    "meta[0] source writable non-signer"
  expect (tInv.metas[1]!.roleId == tInv.mint.roleId &&
      tInv.metas[1]!.cpiWritable == false && tInv.metas[1]!.cpiSigner == false)
    "meta[1] mint readonly"
  expect (tInv.metas[2]!.roleId == tInv.destination.roleId &&
      tInv.metas[2]!.cpiWritable == true && tInv.metas[2]!.cpiSigner == false)
    "meta[2] destination writable non-signer"
  expect (tInv.metas[3]!.roleId == auth.roleId &&
      tInv.metas[3]!.localIndex == auth.localIndex &&
      tInv.metas[3]!.cpiWritable == false && tInv.metas[3]!.cpiSigner == true &&
      tInv.metas[3]!.signerGroupId.isNone)
    "meta[3] authority CPI signer non-writable"

  -- Closed Token field siteChecks: exact localIndex joins (not string theater).
  let some tSiteChecks := transferHandler.bodyOps.findSome? (fun
      | .siteChecks _ ops => some ops
      | _ => none) |
    throw <| IO.userError "missing transferChecked siteChecks"
  let srcLi := tInv.source.localIndex
  let mintLi := tInv.mint.localIndex
  let destLi := tInv.destination.localIndex
  let authLi := auth.localIndex
  expect (tSiteChecks.any (fun
      | .tokenAccountStateInitialized li => li == srcLi
      | _ => false)) "source state@108==1 check present"
  expect (tSiteChecks.any (fun
      | .tokenAccountStateInitialized li => li == destLi
      | _ => false)) "destination state@108==1 check present"
  expect (tSiteChecks.any (fun
      | .tokenAccountMintEqualsRole acc m => acc == srcLi && m == mintLi
      | _ => false)) "source mintEqualsRole exact join"
  expect (tSiteChecks.any (fun
      | .tokenAccountMintEqualsRole acc m => acc == destLi && m == mintLi
      | _ => false)) "destination mintEqualsRole exact join"
  expect (tSiteChecks.any (fun
      | .tokenAccountOwnerEqualsRole acc o => acc == srcLi && o == authLi
      | _ => false)) "source ownerEqualsRole → authority exact join"
  expect (tSiteChecks.any (fun
      | .tokenAccountDelegateNone li => li == srcLi
      | _ => false)) "source delegate COption tag==0 present"
  expect (!tSiteChecks.any (fun
      | .tokenAccountDelegateNone li => li == destLi
      | _ => false)) "destination must NOT force delegate=none"
  expect (tSiteChecks.any (fun
      | .tokenMintInitialized li => li == mintLi
      | _ => false)) "mint is_initialized@45 present"
  expect (tSiteChecks.any (fun
      | .tokenMintDecimalsEquals li src => li == mintLi && src == tInv.decimals
      | _ => false)) "mint decimals@44 exact-joins invoke.decimals source"
  -- Generic owner Tokenkeg + exact len must also appear (via .generic).
  expect (tSiteChecks.any (fun
      | .generic (.checkExactDataLen li n) => li == srcLi && n == 165
      | _ => false)) "source generic exactDataLen 165"
  expect (tSiteChecks.any (fun
      | .generic (.checkExactDataLen li n) => li == mintLi && n == 82
      | _ => false)) "mint generic exactDataLen 82"
  expect (tSiteChecks.any (fun
      | .generic (.checkOwnerExact li _) => li == srcLi
      | _ => false)) "source generic owner exact (Tokenkeg)"
  expect (tSiteChecks.any (fun
      | .generic (.checkExecutableForbidden li) => li == srcLi
      | _ => false)) "source executable forbidden"

  -- transferCheckedPda exact 10B / PDA signer seam / seedAuthority outer signer.
  let some pdaHandler := cand.handlers.find? (fun h => h.name == "transferCheckedPda") |
    throw <| IO.userError "missing transferCheckedPda"
  expect (pdaHandler.probeIxDataLen == 26)
    "pda probe packs handlerId8+seedTag8+bump1+amount8+decimals1"
  let some pInv := pdaHandler.bodyOps.findSome? (fun
      | .invokeToken i => some i
      | _ => none) |
    throw <| IO.userError "missing transferCheckedPda invoke"
  expect (pInv.kind == .transferCheckedPda &&
      pInv.qn == "solana.token.transferCheckedPda" &&
      pInv.packageId == "token-classic-v1" && pInv.dataLen == 10)
    "transferCheckedPda frozen qn/package/dataLen"
  expect (pInv.signerGroupId == some 0 &&
      pInv.pdaRule == some "current-program-tagged-v1")
    "pda signer group / PDA rule"
  expect (pInv.metas.size == 4 && pInv.outerOnly.size == 1)
    "pda four metas + one outer-only"
  let some authPda := pInv.authorityPda |
    throw <| IO.userError "authorityPda binding missing"
  let some seedAuth := pInv.seedAuthority |
    throw <| IO.userError "seedAuthority binding missing"
  expect (pInv.metas[3]!.metaIndex == 3 &&
      pInv.metas[3]!.roleId == authPda.roleId &&
      pInv.metas[3]!.localIndex == authPda.localIndex &&
      pInv.metas[3]!.cpiWritable == false &&
      pInv.metas[3]!.cpiSigner == true &&
      pInv.metas[3]!.signerGroupId == some 0)
    "pda meta[3] authorityPda: CPI signer group 0, readonly"
  expect (pInv.outerOnly[0]!.outerOnlyIndex == 0 &&
      pInv.outerOnly[0]!.roleId == seedAuth.roleId &&
      pInv.outerOnly[0]!.localIndex == seedAuth.localIndex &&
      pInv.outerOnly[0]!.outerSigner == true &&
      pInv.outerOnly[0]!.outerWritable == false)
    "pda outer-only seedAuthority: outer signer non-writable exact"

  -- Pda siteChecks: source owner joins authorityPda (not seedAuthority).
  let some pSiteChecks := pdaHandler.bodyOps.findSome? (fun
      | .siteChecks _ ops => some ops
      | _ => none) |
    throw <| IO.userError "missing transferCheckedPda siteChecks"
  expect (pSiteChecks.any (fun
      | .tokenAccountOwnerEqualsRole acc o =>
          acc == pInv.source.localIndex && o == authPda.localIndex
      | _ => false)) "pda source ownerEqualsRole → authorityPda"
  expect (pSiteChecks.any (fun
      | .tokenMintDecimalsEquals li src =>
          li == pInv.mint.localIndex && src == pInv.decimals
      | _ => false)) "pda mint decimals source exact join"

  let text := SolanaCpiTokenAssemblyV1.textOf asm
  expect (hasSubstr text "call sol_invoke_signed_c")
    "assembly must call sol_invoke_signed_c"
  expect (hasSubstr text "call sol_set_return_data")
    "assembly must call sol_set_return_data"
  expect (hasSubstr text "call sol_try_find_program_address")
    "combined fixture must call find_program_address for transferCheckedPda"
  expect (hasSubstr text "0x6f662d666f6f7270") "seed0 limb0"
  expect (hasSubstr text "SEED0_LEN") "seed0 length equ"
  expect (hasSubstr text "0x0c") "TransferChecked tag 0x0c"
  expect (hasSubstr text "TokenInstruction::TransferChecked")
    "TransferChecked disc comment"
  -- Emitted exact field offsets (not comment-only theater).
  expect (hasSubstr text "tokenAccountStateInitialized") "asm state check banner"
  expect (hasSubstr text "ldxb r3, [r1 + 108]") "asm loads Token Account state @108"
  expect (hasSubstr text "jne r3, 1, err_shape") "asm rejects non-Initialized state"
  expect (hasSubstr text "tokenAccountMintEqualsRole") "asm mint field join banner"
  expect (hasSubstr text "tokenAccountOwnerEqualsRole") "asm owner field join banner"
  expect (hasSubstr text "ldxb r3, [r1 + 72]") "asm loads delegate COption tag @72"
  expect (hasSubstr text "tokenMintInitialized") "asm mint initialized banner"
  expect (hasSubstr text "ldxb r3, [r1 + 45]") "asm loads mint is_initialized @45"
  expect (hasSubstr text "tokenMintDecimalsEquals") "asm mint decimals banner"
  expect (hasSubstr text "ldxb r3, [r1 + 44]") "asm loads mint decimals @44"
  -- mint field compare uses peer ROLE_KEY loads (key equality loop).
  expect (hasSubstr text "ldxdw r5, [r2 + ROLE_KEY]")
    "asm loads peer role key for mint/owner field join"
  expect (!hasSubstr text "0xec01") "assembly must not contain 0xec01 stub"
  expect (!hasSubstr text "ACC0_") "assembly must not use ACC0 slots"
  expect (!hasSubstr text "callx") "assembly must not use callx"
  expect (hasSubstr text "TEST-PREACTIVATION ONLY") "preactivation banner"
  expect (hasSubstr text "not a product artifact") "product boundary banner"
  expect (hasSubstr text "site-time, not entry-hoisted") "site-time checks comment"
  expect (hasSubstr text "handler_1_transferChecked_token:") "transferChecked label"
  expect (hasSubstr text "handler_2_transferCheckedPda_token:")
    "transferCheckedPda label"
  expect (!SolanaCpiTokenAssemblyV1.isProductArtifact asm) "isProductArtifact=false"
  expect (SolanaCpiTokenAssemblyV1.isTestPreactivation asm) "isTestPreactivation=true"
  expect (SolanaCpiTokenAssemblyV1.frameBytesOf asm ≤ 4096) "frame ≤ 4096"
  expect (hasSubstr text "call sol_try_find_program_address\n  jne r0, 0, cpi_failed")
    "find status must propagate"
  expect (hasSubstr text "call sol_invoke_signed_c\n  jne r0, 0, cpi_failed")
    "invoke status must propagate"
  expect (hasSubstr text "jeq r4, 0, err_shape") "runtime bump-zero reject"
  let setReturnCalls := countSubstr text "call sol_set_return_data"
  let checkedSetReturnCalls :=
    countSubstr text "call sol_set_return_data\n  jne r0, 0, cpi_failed"
  expect (setReturnCalls == checkedSetReturnCalls)
    "every sol_set_return_data status must propagate through cpi_failed"

  -- Transfer-only path: no find_program_address.
  let (tOnly, tAsm) ← fullTokenChain session transferOnlySource
    "Examples.TokenTransferOnly"
    "runtime-tests/solana/fixtures/TokenTransferOnly.lean"
  let tText := SolanaCpiTokenAssemblyV1.textOf tAsm
  expect (hasSubstr tText "call sol_invoke_signed_c") "transfer-only invoke"
  expect (!hasSubstr tText "call sol_try_find_program_address")
    "transfer-only must not call find_program_address"
  let some tOnlyInv :=
      (ResolvedSolanaCpiTokenIRV1.candidateOf tOnly).handlers.findSome? (fun h =>
        h.bodyOps.findSome? (fun | .invokeToken i => some i | _ => none)) |
    throw <| IO.userError "transfer-only invoke missing"
  expect (tOnlyInv.dataLen == 10 && tOnlyInv.signerGroupId.isNone)
    "transfer-only zero signer groups / 10B"

  -- bump literal 0 rejected.
  let zeroPlan ← planOnly session bumpZeroSource
    "Examples.TokenBumpZero" "runtime-tests/solana/fixtures/TokenBumpZero.lean"
  expectPlanRejectContains
    (resolveSolanaCpiTokenIRV1 zeroPlan)
    "bump literal 0" "bump zero literal rejected by Token IR"

  -- companion rejected by Token IR.
  let companionPlan ← planOnly session companionSource
    "Examples.TokenRejectCompanion"
    "runtime-tests/solana/fixtures/TokenRejectCompanion.lean"
  expectPlanRejectContains
    (resolveSolanaCpiTokenIRV1 companionPlan)
    "token" "companion rejected by Token IR"

  -- system rejected by Token IR.
  let systemPlan ← planOnly session systemTransferSource
    "Examples.TokenRejectSystem"
    "runtime-tests/solana/fixtures/TokenRejectSystem.lean"
  expectPlanRejectContains
    (resolveSolanaCpiTokenIRV1 systemPlan)
    "token" "system transfer rejected by Token IR"

  -- ATA rejected by Token IR (or earlier plan/derive).
  let ataPlan ← planOnly session ataSource
    "Examples.TokenRejectAta"
    "runtime-tests/solana/fixtures/TokenRejectAta.lean"
  expectPlanRejectContains
    (resolveSolanaCpiTokenIRV1 ataPlan)
    "token" "ATA rejected by Token IR"

  -- multi-block rejected.
  let brPlan ← planOnly session multiBlockSource
    "Examples.TokenRejectBranch"
    "runtime-tests/solana/fixtures/TokenRejectBranch.lean"
  expectPlanRejectContains
    (resolveSolanaCpiTokenIRV1 brPlan)
    "single-block" "multi-block rejected by Token IR"

  -- Token-2022 / dynamic callee fail closed (plan or Token IR).
  expectPlanOrCompileReject session token2022Source
    "Examples.TokenReject2022"
    "runtime-tests/solana/fixtures/TokenReject2022.lean"
    "token" "Token-2022 QN rejected"

  -- Old-lane independence: transferCheckedPda rejected by preflight IR (classicToken).
  let pdaPlan ← planOnly session tokenCpiSource
    "Examples.TokenCpi" "runtime-tests/solana/fixtures/TokenCpi.lean"
  expectPlanRejectContains
    (resolveSolanaCpiPreflightIRV1 pdaPlan)
    "classicToken" "#118 preflight IR rejects classicToken data"

  -- PDA IR rejects token transferChecked.
  let transferPlan ← planOnly session transferOnlySource
    "Examples.TokenTransferOnly"
    "runtime-tests/solana/fixtures/TokenTransferOnly.lean"
  expectPlanRejectContains
    (resolveSolanaCpiPdaIRV1 transferPlan)
    "invokeSigned" "token transfer rejected by PDA IR"

  -- System IR rejects token transferChecked.
  expectPlanRejectContains
    (resolveSolanaCpiSystemIRV1 transferPlan)
    "system" "token transfer rejected by System IR"

  -- #125: ordinary product resolver admits sync; approved Token closure further
  -- mints product Plan/IR. Preactivation lane above remains independent.
  let resolverCompiled ← compileSource session tokenCpiSource
    "Examples.TokenCpi" "runtime-tests/solana/fixtures/TokenCpi.lean"
  let selection ← cpiSelection
  let capability ← expectPlanOk
    (resolveEngineeringRequirementsV1 selection resolverCompiled)
    "ordinary resolver admits TokenCpi sync"
  let _ ← expectPlanOk (productPlanFromCapabilityV1 capability)
    "product Plan succeeds for TokenCpi"
  let _ ← expectPlanOk (productIrFromCapabilityV1 capability)
    "product IR succeeds for TokenCpi"

  -- Frame / scratch non-overlap via public helpers.
  let maxScratch := tokenMaxSiteScratchV1 cand
  let pdaScratch := tokenCpiScratchTransferCheckedPdaV1 pInv.accountInfoCount
  expect (maxScratch == pdaScratch)
    "combined fixture max scratch dominated by transferCheckedPda layout"
  expect (maxScratch == 280 + pInv.accountInfoCount * 56)
    "pda scratch exact 280+56*N formula"
  let reserve := Nat.max maxScratch 240
  let expectedCpiBase :=
    Nat.max tokenCpiBaseMinV1 (tokenTempRegionEndV1 + reserve)
  let expectedFrame := expectedCpiBase + reserve
  expect (expectedCpiBase ≥ tokenTempRegionEndV1 + reserve)
    "CPI_BASE places scratch at/after temp-region end (no overlap)"
  expect (SolanaCpiTokenAssemblyV1.frameBytesOf asm == expectedFrame)
    s!"frameBytes exact {expectedFrame} from public helpers"
  expect (expectedFrame ≤ tokenMaxFrameBytesV1) "frame ≤ 4096 public cap"
  expect (hasSubstr text s!".equ CPI_BASE, {expectedCpiBase}")
    s!"emitted CPI_BASE equ matches computed {expectedCpiBase}"

  -- Classic Token package identity pins.
  expect (tokenClassicProgramIdV1 ==
      (match findCalleePackage? "token-classic-v1" with
       | some p => p.programId
       | none => systemProgramIdV1))
    "catalog token-classic-v1 program id joins frozen authority"
  match findCalleePackage? "token-classic-v1" with
  | some p =>
      expect (p.executionClass == .loaderV3Sbpf) "token executionClass loaderV3"
      expect (p.artifactBinding == .absent) "token artifactBinding absent"
      expect (p.admittedForMaterialization == false) "token not admitted"
  | none => throw <| IO.userError "token-classic-v1 missing from catalog"

  -- Hand-mutated candidate rejection via public validateSolanaCpiTokenIRCandidateV1
  -- (exact localIndex/source join; not substring theater).
  let replaceSiteChecks
      (body : Array CpiTokenBodyOpV1)
      (f : Array CpiTokenSiteCheckV1 → Array CpiTokenSiteCheckV1) :
      Array CpiTokenBodyOpV1 :=
    Id.run do
      let mut out : Array CpiTokenBodyOpV1 := Array.mkEmpty body.size
      for op in body do
        match op with
        | .siteChecks sid checks =>
            out := out.push (.siteChecks sid (f checks))
        | .siteArgChecks sid checks =>
            out := out.push (.siteArgChecks sid checks)
        | .invokeToken inv => out := out.push (.invokeToken inv)
        | .loadParamU64 t o => out := out.push (.loadParamU64 t o)
        | .loadParamU8 t o => out := out.push (.loadParamU8 t o)
        | .loadLiteralU64 t v => out := out.push (.loadLiteralU64 t v)
        | .loadLiteralU8 t v => out := out.push (.loadLiteralU8 t v)
        | .stateLoadU64 t li o => out := out.push (.stateLoadU64 t li o)
        | .checkedAddU64 d l r => out := out.push (.checkedAddU64 d l r)
        | .stateStoreU64 li o s wm m =>
            out := out.push (.stateStoreU64 li o s wm m)
        | .returnU64 t => out := out.push (.returnU64 t)
        | .returnNone => out := out.push .returnNone
      pure out

  let withMutatedTransferBody
      (f : Array CpiTokenSiteCheckV1 → Array CpiTokenSiteCheckV1) :
      SolanaCpiTokenIRCandidateV1 :=
    let body' := replaceSiteChecks transferHandler.bodyOps f
    let h' : CpiTokenHandlerIRV1 := {
      handlerId := transferHandler.handlerId
      callableId := transferHandler.callableId
      name := transferHandler.name
      mode := transferHandler.mode
      localRoleCount := transferHandler.localRoleCount
      localRoleOrder := transferHandler.localRoleOrder
      accountParameterBindings := transferHandler.accountParameterBindings
      probeIxDataLen := transferHandler.probeIxDataLen
      entryGlobalOps := transferHandler.entryGlobalOps
      bodyOps := body'
      tempCount := transferHandler.tempCount
    }
    let handlers' := cand.handlers.map (fun h =>
      if h.handlerId == transferHandler.handlerId then h' else h)
    {
      schema := cand.schema
      sourcePlanDigest := cand.sourcePlanDigest
      sourceIrDigest := cand.sourceIrDigest
      profileId := cand.profileId
      profileDigest := cand.profileDigest
      catalogDigest := cand.catalogDigest
      abiLayout := cand.abiLayout
      maxOuterRoles := cand.maxOuterRoles
      maxFrameBytes := cand.maxFrameBytes
      handlers := handlers'
    }

  -- 1) corrupt mintEqualsRole mint localIndex → destination
  let badCand1 := withMutatedTransferBody fun checks =>
    checks.map fun c =>
      match c with
      | .tokenAccountMintEqualsRole acc m =>
          if acc == srcLi then .tokenAccountMintEqualsRole acc destLi
          else .tokenAccountMintEqualsRole acc m
      | .generic op => .generic op
      | .tokenAccountStateInitialized li => .tokenAccountStateInitialized li
      | .tokenAccountOwnerEqualsRole a o => .tokenAccountOwnerEqualsRole a o
      | .tokenAccountDelegateNone li => .tokenAccountDelegateNone li
      | .tokenMintInitialized li => .tokenMintInitialized li
      | .tokenMintDecimalsEquals li s => .tokenMintDecimalsEquals li s
  expectPlanRejectContains
    (validateSolanaCpiTokenIRCandidateV1 badCand1)
    "mint local" "hand-mutated mintEqualsRole mint local rejected"

  -- 2) corrupt ownerEqualsRole owner local → destination
  let badCand2 := withMutatedTransferBody fun checks =>
    checks.map fun c =>
      match c with
      | .tokenAccountOwnerEqualsRole acc _o =>
          .tokenAccountOwnerEqualsRole acc destLi
      | .generic op => .generic op
      | .tokenAccountStateInitialized li => .tokenAccountStateInitialized li
      | .tokenAccountMintEqualsRole a m => .tokenAccountMintEqualsRole a m
      | .tokenAccountDelegateNone li => .tokenAccountDelegateNone li
      | .tokenMintInitialized li => .tokenMintInitialized li
      | .tokenMintDecimalsEquals li s => .tokenMintDecimalsEquals li s
  expectPlanRejectContains
    (validateSolanaCpiTokenIRCandidateV1 badCand2)
    "authority" "hand-mutated ownerEqualsRole rejected"

  -- 3) corrupt decimals source so it no longer joins invoke.decimals
  let badLit : UInt8 := UInt8.ofNat 99
  let badCand3 := withMutatedTransferBody fun checks =>
    checks.map fun c =>
      match c with
      | .tokenMintDecimalsEquals li _s =>
          .tokenMintDecimalsEquals li (.literal badLit)
      | .generic op => .generic op
      | .tokenAccountStateInitialized li => .tokenAccountStateInitialized li
      | .tokenAccountMintEqualsRole a m => .tokenAccountMintEqualsRole a m
      | .tokenAccountOwnerEqualsRole a o => .tokenAccountOwnerEqualsRole a o
      | .tokenAccountDelegateNone li => .tokenAccountDelegateNone li
      | .tokenMintInitialized li => .tokenMintInitialized li
  expectPlanRejectContains
    (validateSolanaCpiTokenIRCandidateV1 badCand3)
    "decimals" "hand-mutated mint decimals source rejected"

  -- 4) drop required source owner field check entirely
  let badCand4 := withMutatedTransferBody fun checks =>
    checks.filter fun c =>
      match c with
      | .tokenAccountOwnerEqualsRole .. => false
      | _ => true
  expectPlanRejectContains
    (validateSolanaCpiTokenIRCandidateV1 badCand4)
    "ownerEquals" "missing source ownerEquals field check rejected"

  -- Positive: pristine candidate still validates.
  match validateSolanaCpiTokenIRCandidateV1 cand with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError s!"pristine candidate must validate: {error.render}"

  IO.println "Tests.Materialization.SolanaCpiTokenV1: ok"

end Tests.Materialization.SolanaCpiTokenV1

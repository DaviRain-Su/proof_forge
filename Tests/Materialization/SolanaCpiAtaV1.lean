/-
  Tests.Materialization.SolanaCpiAtaV1 — #123 classic ATA CreateIdempotent.

  Authority path: Loader → product compile → preflight capability → Semantic
  Plan → private ATA IR → ATA emitter. This suite fixes the six metas, `01`
  codec, canonical wallet/Token/mint derivation, closed fresh-or-existing ATA
  state, package identities, test-preactivation boundary, and ordinary resolver
  fail-closed behavior.
-/
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.CpiTokenIRV1
import ProofForgeV2.Targets.Solana.CpiAtaIRV1
import ProofForgeV2.Targets.Solana.EmitCpiAtaSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiAtaV1

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

private def expectPlanReject {α : Type} (result : CompileResult α)
    (label : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == "PF-PLAN-INVARIANT")
        s!"{label}: expected PF-PLAN-INVARIANT, got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly accepted"

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def countSubstr (haystack needle : String) : Nat :=
  (haystack.splitOn needle).length - 1

private def extensionHeader : String :=
  "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
  "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n"

private def ataCpiSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program AtaCpi where\n" ++ extensionHeader ++
  "  state value : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    value := initial\n" ++
  "  entry createIdempotent(payer : Principal, ata : Principal,\n" ++
  "      wallet : Principal, mint : Principal) : UInt64 do\n" ++
  "    value := value + 1\n" ++
  "    call solana.ata.createIdempotent(payer, ata, wallet, mint)\n" ++
  "    value := value + 2\n" ++
  "    return value\n" ++
  "  entry createIdempotentThenOverflow(payer : Principal, ata : Principal,\n" ++
  "      wallet : Principal, mint : Principal) : UInt64 do\n" ++
  "    value := value + 1\n" ++
  "    call solana.ata.createIdempotent(payer, ata, wallet, mint)\n" ++
  "    value := value + 18446744073709551615\n" ++
  "    return value\n" ++
  "  view inspect() : UInt64 do\n" ++
  "    return value\n"

private unsafe def compileSource
    (session : Language.Loader.ParserSession) : IO CompiledSemanticV1 := do
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      ataCpiSource "runtime-tests/solana/fixtures/AtaCpi.lean"
      "Examples.AtaCpi" none with
    | .ok pair => pure pair
    | .error error => throw <| IO.userError s!"load ATA fixture: {error.render}"
  match Compiler.compileProgramProductV1 source origins with
  | .ok compiled => pure compiled
  | .error _ => throw <| IO.userError "product compile rejected AtaCpi"

private def cpiSelection : IO ResolvedBuildSelectionV1 :=
  expectPlanOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "resolve CPI profile"

private unsafe def fullChain
    (session : Language.Loader.ParserSession) :
    IO (CompiledSemanticV1 × SolanaCpiPreflightPlanV1 ×
      ResolvedSolanaCpiAtaIRV1 × SolanaCpiAtaAssemblyV1) := do
  let compiled ← compileSource session
  let selection ← cpiSelection
  let preflight ← expectPlanOk
    (resolveSolanaCpiPreflightV1 selection compiled) "preflight"
  let plan ← expectPlanOk
    (deriveSolanaCpiPlanFromPreflightV1 preflight) "derive plan"
  let ataIr ← expectPlanOk (resolveSolanaCpiAtaIRV1 plan) "ATA IR"
  let assembly ← expectPlanOk (emitCpiAtaSbpfV1 ataIr) "ATA emitter"
  pure (compiled, plan, ataIr, assembly)

private def replaceCreateBody
    (body : Array CpiAtaBodyOpV1)
    (checkMap : Array CpiAtaSiteCheckV1 → Array CpiAtaSiteCheckV1)
    (invokeMap : CpiAtaInvokeV1 → CpiAtaInvokeV1 := fun x => x) :
    Array CpiAtaBodyOpV1 :=
  body.map fun op =>
    match op with
    | .siteChecks sid checks => .siteChecks sid (checkMap checks)
    | .invokeAta inv => .invokeAta (invokeMap inv)
    | other => other

private def mutateHandler
    (candidate : SolanaCpiAtaIRCandidateV1) (handler : CpiAtaHandlerIRV1)
    (body : Array CpiAtaBodyOpV1) : SolanaCpiAtaIRCandidateV1 :=
  let changed : CpiAtaHandlerIRV1 := { handler with bodyOps := body }
  { candidate with handlers := candidate.handlers.map fun h =>
      if h.handlerId == handler.handlerId then changed else h }

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let (compiled, plan, resolved, assembly) ← fullChain session
  let candidate := ResolvedSolanaCpiAtaIRV1.candidateOf resolved
  expect (candidate.schema == ataIrSchemaV1) "ATA IR schema"
  expect (candidate.handlers.size == 4) "init + two entries + inspect"

  let some handler := candidate.handlers.find? (fun h => h.name == "createIdempotent") |
    throw <| IO.userError "createIdempotent handler missing"
  let some overflowHandler := candidate.handlers.find? (fun h =>
      h.name == "createIdempotentThenOverflow") |
    throw <| IO.userError "createIdempotentThenOverflow handler missing"
  expect (handler.probeIxDataLen == 8) "Principal args are account-bound, ix len is handler id only"
  expect (handler.localRoleCount == 8) "state+payer+ata+wallet+mint+ATA+System+Token roles"

  -- The rollback forcing handler must commit its first checked update, execute
  -- the real ATA CPI, then reach the second checked add/store. A runtime
  -- Custom(0x1001) alone would not prove this source order.
  let mut overflowAdds : Array Nat := #[]
  let mut overflowStores : Array Nat := #[]
  let mut overflowInvokes : Array Nat := #[]
  for (op, pos) in overflowHandler.bodyOps.zipIdx do
    match op with
    | .checkedAddU64 .. => overflowAdds := overflowAdds.push pos
    | .stateStoreU64 .. => overflowStores := overflowStores.push pos
    | .invokeAta _ => overflowInvokes := overflowInvokes.push pos
    | _ => pure ()
  expect (overflowAdds.size == 2 && overflowStores.size == 2 &&
      overflowInvokes.size == 1)
    "overflow handler exact add/store/invoke cardinality"
  let invokePos := overflowInvokes[0]!
  expect (overflowAdds[0]! < overflowStores[0]! &&
      overflowStores[0]! < invokePos &&
      invokePos < overflowAdds[1]! &&
      overflowAdds[1]! < overflowStores[1]!)
    "overflow handler must execute CPI between first commit and failing checked add"
  let some inv := handler.bodyOps.findSome? (fun
      | .invokeAta value => some value
      | _ => none) |
    throw <| IO.userError "ATA invoke missing"
  expect (inv.kind == .createIdempotent &&
      inv.qn == "solana.ata.createIdempotent" &&
      inv.packageId == "ata-classic-v1" && inv.dataLen == 1)
    "exact ATA API identity and one-byte codec"
  expect (inv.payer.argIndex == 0 && inv.ata.argIndex == 1 &&
      inv.wallet.argIndex == 2 && inv.mint.argIndex == 3)
    "Principal argument source order"
  expect (inv.metas.size == 6 && inv.outerOnly.isEmpty &&
      inv.signerGroupId.isNone && inv.pdaRule == some "ata-classic-v1")
    "six metas, no outer-only/signer group, address-check-only rule"
  let expectedFlags : Array (Bool × Bool) := #[
    (true, true), (true, false), (false, false),
    (false, false), (false, false), (false, false)
  ]
  for i in [0:6] do
    expect (inv.metas[i]!.metaIndex == i &&
        inv.metas[i]!.cpiWritable == expectedFlags[i]!.1 &&
        inv.metas[i]!.cpiSigner == expectedFlags[i]!.2 &&
        inv.metas[i]!.signerGroupId.isNone)
      s!"meta {i} flags/order"
  expect (inv.metas[0]!.localIndex == inv.payer.localIndex &&
      inv.metas[1]!.localIndex == inv.ata.localIndex &&
      inv.metas[2]!.localIndex == inv.wallet.localIndex &&
      inv.metas[3]!.localIndex == inv.mint.localIndex &&
      inv.metas[4]!.localIndex == inv.systemProgramLocalIndex &&
      inv.metas[5]!.localIndex == inv.tokenProgramLocalIndex)
    "six meta role joins"

  let some checks := handler.bodyOps.findSome? (fun
      | .siteChecks _ values => some values
      | _ => none) |
    throw <| IO.userError "ATA site checks missing"
  expect (checks.any (fun
      | .ataAddressCanonical ata wallet token mint programLocal =>
          ata == inv.ata.localIndex && wallet == inv.wallet.localIndex &&
          token == inv.tokenProgramLocalIndex && mint == inv.mint.localIndex &&
          programLocal == inv.programLocalIndex
      | _ => false)) "canonical ATA address check exact-joins invoke"
  expect (checks.any (fun
      | .ataAccountPrestateClosed ata wallet mint system token =>
          ata == inv.ata.localIndex && wallet == inv.wallet.localIndex &&
          mint == inv.mint.localIndex && system == inv.systemProgramLocalIndex &&
          token == inv.tokenProgramLocalIndex
      | _ => false)) "closed ATA pre-state check exact-joins invoke"
  expect (checks.any (fun
      | .tokenMintInitialized li => li == inv.mint.localIndex
      | _ => false)) "mint initialized check"
  expect (checks.any (fun
      | .generic (.checkExactDataLen li 0) => li == inv.payer.localIndex
      | _ => false)) "payer exact zero data"
  expect (checks.any (fun
      | .generic (.checkExactDataLen li 82) => li == inv.mint.localIndex
      | _ => false)) "mint exact 82 bytes"

  -- Every invoke must retain immediate siteArgChecks→siteChecks order.
  for h in candidate.handlers do
    for i in [0:h.bodyOps.size] do
      match h.bodyOps[i]! with
      | .invokeAta site =>
          expect (i ≥ 2) s!"{h.name}: invoke lacks adjacent checks"
          match h.bodyOps[i - 2]!, h.bodyOps[i - 1]! with
          | .siteArgChecks sid0 args, .siteChecks sid1 _ =>
              expect (args.isEmpty && sid0 == site.siteId && sid1 == site.siteId)
                s!"{h.name}: adjacent site ids/arg checks"
          | _, _ => throw <| IO.userError s!"{h.name}: malformed check order"
      | _ => pure ()

  let text := SolanaCpiAtaAssemblyV1.textOf assembly
  expect (countSubstr text "call sol_try_find_program_address" == 2)
    "one canonical ATA derivation per call handler"
  expect (countSubstr text "call sol_invoke_signed_c" == 2)
    "one real ATA CPI per call handler"
  expect (hasSubstr text "stxb [r9 + 0], r4                  ; CreateIdempotent")
    "exact data byte 01 emission"
  expect (hasSubstr text "ataAddressCanonical seeds=[wallet,classicToken,mint]")
    "ATA seed order banner"
  expect (hasSubstr text "ataAccountPrestateClosed") "closed pre-state emitted"
  expect (hasSubstr text "ldxb r3, [r1 + 108]") "existing ATA state byte checked"
  expect (hasSubstr text "ATA mint join") "existing ATA mint join emitted"
  expect (hasSubstr text "ATA wallet-owner join") "existing ATA wallet join emitted"
  expect (hasSubstr text "add64 r5, 104") "six-meta base offset"
  expect (hasSubstr text "lddw r4, 6\n  stxdw [r8 + 16], r4")
    "instruction accounts_len is six"
  expect (hasSubstr text "lddw r4, 0\n  lddw r5, 0\n  call sol_invoke_signed_c")
    "caller signer groups are exactly zero"
  expect (!hasSubstr text "current-program-tagged-v1")
    "ATA derivation is not caller-PDA signer recipe"
  expect (!hasSubstr text "0xec01" && !hasSubstr text "ACC0_" &&
      !hasSubstr text "callx") "no legacy/indirect call surface"
  expect (!SolanaCpiAtaAssemblyV1.isProductArtifact assembly &&
      SolanaCpiAtaAssemblyV1.isTestPreactivation assembly)
    "test-preactivation assembly boundary"
  let setCalls := countSubstr text "call sol_set_return_data"
  let checkedSetCalls := countSubstr text
    "call sol_set_return_data\n  jne r0, 0, cpi_failed"
  expect (setCalls == checkedSetCalls) "every return-data clear propagates status"

  let maxScratch := ataMaxSiteScratchV1 candidate
  expect (maxScratch == ataCpiScratchCreateIdempotentV1 inv.accountInfoCount &&
      maxScratch == 240 + inv.accountInfoCount * 56) "ATA scratch exact formula"
  let reserve := Nat.max maxScratch 240
  let cpiBase := Nat.max ataCpiBaseMinV1 (ataTempRegionEndV1 + reserve)
  expect (SolanaCpiAtaAssemblyV1.frameBytesOf assembly == cpiBase + reserve &&
      SolanaCpiAtaAssemblyV1.frameBytesOf assembly ≤ ataMaxFrameBytesV1)
    "ATA frame exact and within 4096"

  -- Package identities remain exact deny-state dependencies.
  for (id, key, cls) in #[
      ("ata-classic-v1", ataClassicProgramIdV1, ExecutionClass.loaderV3Sbpf),
      ("token-classic-v1", tokenClassicProgramIdV1, ExecutionClass.loaderV3Sbpf),
      ("system-v1", systemProgramIdV1, ExecutionClass.nativeSystem)] do
    let some package := findCalleePackage? id |
      throw <| IO.userError s!"missing package {id}"
    expect (package.programId == key && package.executionClass == cls &&
        package.admittedForMaterialization == false)
      s!"package {id} exact identity + denied admission"
  expect ((findCalleePackage? "ata-classic-v1").map (·.artifactBinding) == some .absent)
    "ATA catalog artifact remains absent"
  expect ((findCalleePackage? "token-classic-v1").map (·.artifactBinding) == some .absent)
    "Token catalog artifact remains absent"

  -- Hand-mutated structural candidates cannot self-certify.
  let badAddressBody := replaceCreateBody handler.bodyOps (fun values =>
    values.map fun value => match value with
      | .ataAddressCanonical ata wallet _token mint programLocal =>
          .ataAddressCanonical ata wallet inv.systemProgramLocalIndex mint programLocal
      | other => other)
  expectPlanReject
    (validateSolanaCpiAtaIRCandidateV1
      (mutateHandler candidate handler badAddressBody))
    "mutated ATA seed token role"

  let missingPrestateBody := replaceCreateBody handler.bodyOps (fun values =>
    values.filter fun value => match value with
      | .ataAccountPrestateClosed .. => false
      | _ => true)
  expectPlanReject
    (validateSolanaCpiAtaIRCandidateV1
      (mutateHandler candidate handler missingPrestateBody))
    "missing closed ATA prestate"

  let badRuleBody := replaceCreateBody handler.bodyOps (fun x => x)
    (fun value => { value with pdaRule := none })
  expectPlanReject
    (validateSolanaCpiAtaIRCandidateV1
      (mutateHandler candidate handler badRuleBody))
    "missing ATA pda rule"
  match validateSolanaCpiAtaIRCandidateV1 candidate with
  | .ok () => pure ()
  | .error error => throw <| IO.userError s!"pristine ATA candidate: {error.render}"

  -- The earlier generic/Token leaves remain independent and fail closed.
  expectPlanReject (resolveSolanaCpiPreflightIRV1 plan)
    "generic preflight IR rejects ATA alternatives"
  expectPlanReject (resolveSolanaCpiTokenIRV1 plan)
    "Token IR rejects ATA API"

  -- Ordinary product capability still rejects sync until composite #125.
  let selection ← cpiSelection
  match resolveEngineeringRequirementsV1 selection compiled with
  | .error error =>
      expect (error.code == "PF-REQ-UNSUPPORTED")
        s!"ordinary resolver must PF-REQ-UNSUPPORTED, got {error.render}"
  | .ok _ => throw <| IO.userError "ordinary resolver accepted ATA sync"

  IO.println "Tests.Materialization.SolanaCpiAtaV1: ok"

end Tests.Materialization.SolanaCpiAtaV1

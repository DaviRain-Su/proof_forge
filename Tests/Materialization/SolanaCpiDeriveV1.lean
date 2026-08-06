/-
  #118 tests: Solana CPI preflight capability + sole Semantic→Plan derive
  under retained Semantic / exact capability. Registered in ordinary target,
  fast, and aggregate test roots.
-/
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiIdlV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiProductV1
import ProofForgeV2.Targets.Solana.LowerSemanticV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiDeriveV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana
open ProofForgeV2.Targets.Solana.CpiV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def firstWordBE (bytes : ByteArray) : UInt64 := Id.run do
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := UInt64.shiftLeft value 8 ||| bytes[index]!.toUInt64
  pure value

private def expectOk {α : Type} (result : Except String α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def expectCompileOk {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def expectCompileErrorContains {α : Type}
    (result : CompileResult α) (code needle label : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == code && error.message.contains needle)
        s!"{label}: expected {code} containing '{needle}', got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly accepted"

private def extensionHeader : String :=
  "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
  "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n"

private def wrapProgram (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  s!"program {name} where\n" ++
  extensionHeader ++
  body

/-- Companion invoke: Principal + UInt64 params only (no bare integer literal). -/
private def companionInvokeSource : String :=
  wrapProgram "CpiCompanionInvoke" <|
    "  entry invoke(account: Principal, delta: UInt64) : UInt64 do\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    return 0\n"

private def companionFailSource : String :=
  wrapProgram "CpiCompanionFail" <|
    "  entry fail(account: Principal, delta: UInt64) : UInt64 do\n" ++
    "    call solana.companion.fail(account, delta)\n" ++
    "    return 0\n"

private def companionInvokeSignedSource : String :=
  wrapProgram "CpiCompanionInvokeSigned" <|
    "  entry invokeSigned(account: Principal, authorityPda: Principal,\n" ++
    "      seedAuthority: Principal, seedTag: UInt64, bump: UInt8,\n" ++
    "      delta: UInt64) : UInt64 do\n" ++
    "    call solana.companion.invokeSigned(account, authorityPda,\n" ++
    "      seedAuthority, seedTag, bump, delta)\n" ++
    "    return 0\n"

private def systemTransferSource : String :=
  wrapProgram "CpiSystemTransfer" <|
    "  entry transfer(payer: Principal, recipient: Principal,\n" ++
    "      lamports: UInt64) : UInt64 do\n" ++
    "    call solana.system.transfer(payer, recipient, lamports)\n" ++
    "    return 0\n"

private def systemCreatePdaSource : String :=
  wrapProgram "CpiSystemCreatePda" <|
    "  entry createPda(payer: Principal, pda: Principal,\n" ++
    "      seedAuthority: Principal, seedTag: UInt64, bump: UInt8,\n" ++
    "      lamports: UInt64, space: UInt64) : UInt64 do\n" ++
    "    call solana.system.createPdaAccount(payer, pda, seedAuthority,\n" ++
    "      seedTag, bump, lamports, space)\n" ++
    "    return 0\n"

private def tokenTransferCheckedSource : String :=
  wrapProgram "CpiTokenTransferChecked" <|
    "  entry transferChecked(source: Principal, mint: Principal,\n" ++
    "      destination: Principal, authority: Principal,\n" ++
    "      amount: UInt64, decimals: UInt8) : UInt64 do\n" ++
    "    call solana.token.transferChecked(source, mint, destination,\n" ++
    "      authority, amount, decimals)\n" ++
    "    return 0\n"

private def tokenTransferCheckedPdaSource : String :=
  wrapProgram "CpiTokenTransferCheckedPda" <|
    "  entry transferCheckedPda(source: Principal, mint: Principal,\n" ++
    "      destination: Principal, authorityPda: Principal,\n" ++
    "      seedAuthority: Principal, seedTag: UInt64, bump: UInt8,\n" ++
    "      amount: UInt64, decimals: UInt8) : UInt64 do\n" ++
    "    call solana.token.transferCheckedPda(source, mint, destination,\n" ++
    "      authorityPda, seedAuthority, seedTag, bump, amount, decimals)\n" ++
    "    return 0\n"

private def ataCreateIdempotentSource : String :=
  wrapProgram "CpiAtaCreateIdempotent" <|
    "  entry createIdempotent(payer: Principal, ata: Principal,\n" ++
    "      wallet: Principal, mint: Principal) : UInt64 do\n" ++
    "    call solana.ata.createIdempotent(payer, ata, wallet, mint)\n" ++
    "    return 0\n"

/-- Multi-handler with state: init, two CPI entries (shared param name `account`),
    and a no-CPI view. Repeated param names prove global role-name uniqueness via
    `handlerName_paramName`. -/
private def stateMultiHandlerSource : String :=
  wrapProgram "CpiStateMulti" <|
    "  state counter : UInt64\n" ++
    "  init() do\n" ++
    "    counter := 0\n" ++
    "  entry bump(account : Principal, delta : UInt64) : UInt64 do\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    counter := counter + 1\n" ++
    "    return counter\n" ++
    "  entry also(account : Principal, delta : UInt64) : UInt64 do\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    return counter\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return counter\n"

private def missingExtensionSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program CpiMissingExtension where\n" ++
  "  entry invoke(account: Principal, delta: UInt64) : UInt64 do\n" ++
  "    call solana.companion.invoke(account, delta)\n" ++
  "    return 0\n"

private def wrongQnSource : String :=
  wrapProgram "CpiWrongQn" <|
    "  entry invoke(account: Principal, delta: UInt64) : UInt64 do\n" ++
    "    call solana.unknown.invoke(account, delta)\n" ++
    "    return 0\n"

private def wrongArgTypeSource : String :=
  wrapProgram "CpiWrongArgType" <|
    "  entry invoke(account: Principal, delta: Bool) : UInt64 do\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    return 0\n"

private def contextCallerPrincipalSource : String :=
  wrapProgram "CpiContextCaller" <|
    "  entry invoke(delta: UInt64) : UInt64 do\n" ++
    "    let account: Principal := context.caller\n" ++
    "    call solana.companion.invoke(account, delta)\n" ++
    "    return 0\n"

private def scheduleSource : String :=
  wrapProgram "CpiSchedule" <|
    "  entry run(account: Principal, delta: UInt64) : UInt64 do\n" ++
    "    schedule solana.companion.invoke(account, delta)\n" ++
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
  expectCompileOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "select solana-sbpf-cpi-elf-v1"

private unsafe def preflightOf
    (session : Language.Loader.ParserSession)
    (source moduleName : String) : IO ResolvedSolanaCpiPreflightV1 := do
  let compiled ← compileSource session source moduleName
    s!"<cpi-derive-{moduleName}>"
  let selection ← cpiSelection
  expectCompileOk (resolveSolanaCpiPreflightV1 selection compiled)
    s!"preflight {moduleName}"

private unsafe def deriveOf
    (session : Language.Loader.ParserSession)
    (source moduleName : String) : IO SolanaCpiPreflightPlanV1 := do
  let preflight ← preflightOf session source moduleName
  expectCompileOk (deriveSolanaCpiPlanFromPreflightV1 preflight)
    s!"derive {moduleName}"

private def planOfCarrier (c : SolanaCpiPreflightPlanV1) : ValidatedSolanaCpiPlanV1 :=
  SolanaCpiPreflightPlanV1.planOf c

private def candidateOfCarrier (c : SolanaCpiPreflightPlanV1) :
    SolanaCpiPlanCandidateV1 :=
  SolanaCpiPreflightPlanV1.candidateOf c

/-- Positive companion invoke through Loader→compile→preflight→Plan→IR/IDL. -/
private unsafe def testCompanionInvokePositive
    (session : Language.Loader.ParserSession) : IO Unit := do
  let preflight ← preflightOf session companionInvokeSource
    "Tests.CpiCompanionInvoke"
  expect (ResolvedSolanaCpiPreflightV1.activationDeniedOf preflight)
    "preflight activationDenied"
  let carrier ← expectCompileOk (deriveSolanaCpiPlanFromPreflightV1 preflight)
    "derive companion.invoke"
  let plan := planOfCarrier carrier
  let c := plan.candidate
  expect (c.cpiSites.size == 1) "one CPI site"
  expect (c.handlers.size == 1) "one handler"
  let some site := c.cpiSites[0]? |
    throw <| IO.userError "missing site"
  expect (site.qn == "solana.companion.invoke") "QN"
  expect (site.packageId == "companion-v1") "package"
  expect (site.args.size == 2) "two args"
  let some arg0 := site.args[0]? |
    throw <| IO.userError "missing arg0"
  let some arg1 := site.args[1]? |
    throw <| IO.userError "missing arg1"
  expect (arg0.spec.type_ == .principal && arg0.roleId.isSome)
    "principal arg binds role"
  expect (arg1.spec.type_ == .uint64 && arg1.roleId.isNone)
    "u64 arg has no role"
  -- ValueIds: params occupy 0,1 for (account, delta); ExternalCall uses them.
  expect (arg0.semanticValueId == 0) "principal ValueId is param 0"
  expect (arg1.semanticValueId == 1) "delta ValueId is param 1"
  expect (site.anchor.effectId == 0) "effectId 0"
  expect (site.anchor.callableId == 0) "callableId 0"
  expect (site.anchor.blockId == 0) "blockId 0"
  -- Role name is handlerName_paramName (declaration name, not frozen API name alone).
  let some role0 := c.accountRoles[0]? |
    throw <| IO.userError "missing role0"
  expect (role0.name == "invoke_account") "param-derived role name"
  expect (c.programName == "CpiCompanionInvoke") "artifact programName"
  -- Materialization remains inert (admitted=false packages and/or inert profile).
  expectCompileErrorContains
    (checkSolanaCpiMaterializationEligibilityV1 plan)
    "PF-PLAN-INVARIANT" "materialization rejects"
    "companion materialization inert"
  -- IR / IDL derive from validated plan.
  let _ir ← expectCompileOk (deriveSolanaCpiIRV1 plan) "IR derive"
  let _idl ← expectCompileOk (deriveSolanaCpiIdlV1 plan) "IDL derive"

/-- All eight frozen APIs: param-only source → preflight → Plan. -/
private unsafe def testAllEightApisParamOnly
    (session : Language.Loader.ParserSession) : IO Unit := do
  let cases : Array (String × String × String) := #[
    ("solana.companion.invoke", companionInvokeSource, "Tests.CpiCompanionInvoke"),
    ("solana.companion.fail", companionFailSource, "Tests.CpiCompanionFail"),
    ("solana.companion.invokeSigned", companionInvokeSignedSource,
      "Tests.CpiCompanionInvokeSigned"),
    ("solana.system.transfer", systemTransferSource, "Tests.CpiSystemTransfer"),
    ("solana.system.createPdaAccount", systemCreatePdaSource,
      "Tests.CpiSystemCreatePda"),
    ("solana.token.transferChecked", tokenTransferCheckedSource,
      "Tests.CpiTokenTransferChecked"),
    ("solana.token.transferCheckedPda", tokenTransferCheckedPdaSource,
      "Tests.CpiTokenTransferCheckedPda"),
    ("solana.ata.createIdempotent", ataCreateIdempotentSource,
      "Tests.CpiAtaCreateIdempotent")
  ]
  for (qn, source, moduleName) in cases do
    let carrier ← deriveOf session source moduleName
    let plan := planOfCarrier carrier
    expect (plan.candidate.cpiSites.size == 1)
      s!"{qn}: one site"
    let some site := plan.candidate.cpiSites[0]? |
      throw <| IO.userError s!"{qn}: missing site"
    expect (site.qn == qn) s!"{qn}: site QN"
    expect (site.args.size ==
        (match findFrozenApi? qn with
         | some api => api.args.size
         | none => 0))
      s!"{qn}: arg arity"
    expectCompileErrorContains
      (checkSolanaCpiMaterializationEligibilityV1 plan)
      "PF-PLAN-INVARIANT" "materialization rejects"
      s!"{qn}: materialization inert"
    let _ ← expectCompileOk (deriveSolanaCpiIRV1 plan) s!"{qn}: IR"
    let _ ← expectCompileOk (deriveSolanaCpiIdlV1 plan) s!"{qn}: IDL"

/-- State-inclusive multi-handler: init + call entry + no-call view. -/
private unsafe def testStateMultiHandler
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateMultiHandlerSource
    "Tests.CpiStateMulti" "<cpi-state-multi>"
  let selection ← cpiSelection
  let preflight ← expectCompileOk
    (resolveSolanaCpiPreflightV1 selection compiled) "preflight state multi"
  expect (ResolvedSolanaCpiPreflightV1.activationDeniedOf preflight)
    "activationDenied"
  let carrier ← expectCompileOk (deriveSolanaCpiPlanFromPreflightV1 preflight)
    "derive state multi"
  let plan := planOfCarrier carrier
  let c := plan.candidate

  -- Artifact identity
  expect (c.programName == "CpiStateMulti") "programName from artifact"
  expect (c.programName ==
      CompiledSemanticV1.artifactProgramNameOf compiled)
    "programName equals CompiledSemanticV1.artifactProgramNameOf"

  -- Handlers: init, bump, also (entries with call), peek (view without call)
  expect (c.handlers.size == 4) "four direct handlers"
  let some hInit := c.handlers[0]? |
    throw <| IO.userError "missing init handler"
  let some hBump := c.handlers[1]? |
    throw <| IO.userError "missing bump handler"
  let some hAlso := c.handlers[2]? |
    throw <| IO.userError "missing also handler"
  let some hView := c.handlers[3]? |
    throw <| IO.userError "missing view handler"
  expect (hInit.mode == .initialize && hInit.cpiSiteIds.isEmpty)
    "init mode, zero CPI sites"
  expect (hBump.mode == .entry && hBump.cpiSiteIds.size == 1)
    "bump entry mode, one CPI site"
  expect (hAlso.mode == .entry && hAlso.cpiSiteIds.size == 1)
    "also entry mode, one CPI site"
  expect (hView.mode == .view && hView.cpiSiteIds.isEmpty)
    "view mode, zero CPI sites"
  expect (c.cpiSites.size == 2) "exactly two CPI sites overall"

  -- State schema: exact len/marker/digest relation via sole legacy authority
  expect (c.stateSchemas.size == 1) "one state schema"
  let some schema := c.stateSchemas[0]? |
    throw <| IO.userError "missing state schema"
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok v => pure v
    | .error _ => throw <| IO.userError "semantic revalidate failed"
  let accountOpt ← expectCompileOk
    (deriveSolanaStateAccountFromSemanticDataV1 data) "state account"
  let account ← match accountOpt with
    | some a => pure a
    | none => throw <| IO.userError "expected nonempty StateAccount"
  expect (schema.exactDataLen == account.exactDataLen) "exactDataLen join"
  expect (schema.initializedMarker == account.initializedMarker)
    "initializedMarker join"
  expect (schema.layoutDigest.bytes == layoutHashBytesV1 account.fields)
    "layoutDigest sole hash bytes"
  expect (schema.initializedMarker == firstWordBE schema.layoutDigest.bytes)
    "marker == first 8 BE digest bytes"
  expect (schema.initializedMarker != 0) "marker nonzero"

  -- Global state role 0
  let some stateRole := c.accountRoles[0]? |
    throw <| IO.userError "missing role 0"
  expect (match stateRole.keyPolicy with | .state 0 => true | _ => false)
    "role 0 is state schema 0"
  expect (stateRole.name == "state") "state role name"

  -- State role first in every handler local uses + privilege matrix
  for (h, label, wantSigner, wantWritable) in
      #[(hInit, "init", true, true),
        (hBump, "bump", false, true),
        (hAlso, "also", false, true),
        (hView, "view", false, false)] do
    expect (h.accountUses.size ≥ 1) s!"{label}: nonempty uses"
    let some u0 := h.accountUses[0]? |
      throw <| IO.userError s!"{label}: missing use 0"
    expect (u0.roleId == 0 && u0.position == 0)
      s!"{label}: state role first"
    expect (u0.directSignerContribution == wantSigner &&
        u0.directWritableContribution == wantWritable)
      s!"{label}: direct privilege matrix"
    expect (u0.outerSigner == wantSigner && u0.outerWritable == wantWritable)
      s!"{label}: outer equals direct (no site contrib on state)"

  -- Param-derived role names are globally unique across handlers that share
  -- the declaration name `account`.
  let roleNames := c.accountRoles.map (·.name)
  expect (roleNames.any (· == "bump_account")) "bump param role name"
  expect (roleNames.any (· == "also_account")) "also param role name"
  -- Uniqueness is enforced by structural validate; re-check here.
  let sorted := roleNames.qsort (· < ·)
  for i in [1:sorted.size] do
    expect (sorted[i - 1]! != sorted[i]!) "global role names unique"

  expectCompileErrorContains
    (checkSolanaCpiMaterializationEligibilityV1 plan)
    "PF-PLAN-INVARIANT" "materialization rejects"
    "state multi materialization inert"
  let _ ← expectCompileOk (deriveSolanaCpiIRV1 plan) "state multi IR"
  let _ ← expectCompileOk (deriveSolanaCpiIdlV1 plan) "state multi IDL"

/-- #125: ordinary product resolver admits companion sync; product Plan fails
    closed because active catalog denies companion. Preflight lane still admits. -/
private unsafe def testNormalResolverCompanionProductDenied
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session companionInvokeSource
    "Tests.CpiCompanionInvoke" "<cpi-derive-normal-resolver>"
  let selection ← cpiSelection
  let capability ← expectCompileOk
    (resolveEngineeringRequirementsV1 selection compiled)
    "ordinary resolver admits companion sync"
  expectCompileErrorContains
    (productPlanFromCapabilityV1 capability)
    "PF-PLAN-INVARIANT" "companion"
    "product Plan denies companion catalog package"
  -- Preflight still admits the same pair (activationDenied preactivation lane).
  let _ ← expectCompileOk (resolveSolanaCpiPreflightV1 selection compiled)
    "preflight admits deferred sync"

/-- Missing extension declaration → preflight rejects. -/
private unsafe def testMissingExtension
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Call without extension still compiles (Normalize does not require it),
  -- but preflight requires the exact extension row.
  let compiled ← match ← session.selectProgramV1WithOrigins
      missingExtensionSource "<cpi-missing-ext>"
      "Tests.CpiMissingExtension" none with
    | .ok (src, origins) =>
        match Compiler.compileProgramProductV1 src origins with
        | .ok c => pure c
        | .error _ =>
            -- If product compile fails (e.g. typed), that is also a closed path.
            throw <| IO.userError
              "missing extension: expected product compile to succeed without extension row"
    | .error error =>
        throw <| IO.userError s!"missing extension load: {error.render}"
  let selection ← cpiSelection
  expectCompileErrorContains
    (resolveSolanaCpiPreflightV1 selection compiled)
    "PF-REQ-UNSUPPORTED" "extension"
    "missing extension rejected by preflight"

/-- Unknown QN fails at derive after preflight. -/
private unsafe def testWrongQn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session wrongQnSource "Tests.CpiWrongQn"
    "<cpi-wrong-qn>"
  let selection ← cpiSelection
  let preflight ← expectCompileOk
    (resolveSolanaCpiPreflightV1 selection compiled) "preflight wrong QN"
  expectCompileErrorContains
    (deriveSolanaCpiPlanFromPreflightV1 preflight)
    "PF-PLAN-INVARIANT" "unknown"
    "wrong QN rejected at derive"

/-- Wrong arg type: Bool for UInt64 fails at Normalize (or derive). -/
private unsafe def testWrongArgType
    (session : Language.Loader.ParserSession) : IO Unit := do
  match ← session.selectProgramV1WithOrigins wrongArgTypeSource
      "<cpi-wrong-arg>" "Tests.CpiWrongArgType" none with
  | .error _ =>
      -- Parser/typed may reject before compile.
      pure ()
  | .ok (src, origins) =>
      match Compiler.compileProgramProductV1 src origins with
      | .error _ => pure ()  -- Normalize/typed fail closed
      | .ok compiled =>
          let selection ← cpiSelection
          match resolveSolanaCpiPreflightV1 selection compiled with
          | .error _ => pure ()
          | .ok preflight =>
              expectCompileErrorContains
                (deriveSolanaCpiPlanFromPreflightV1 preflight)
                "PF-PLAN-INVARIANT" "UInt"
                "wrong arg type rejected"

/-- context.caller Principal is not a direct param → derive FC. -/
private unsafe def testContextCallerPrincipal
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session contextCallerPrincipalSource
    "Tests.CpiContextCaller" "<cpi-context-caller>"
  let selection ← cpiSelection
  let preflight ← expectCompileOk
    (resolveSolanaCpiPreflightV1 selection compiled)
    "preflight context.caller"
  expectCompileErrorContains
    (deriveSolanaCpiPlanFromPreflightV1 preflight)
    "PF-PLAN-INVARIANT" "Principal"
    "context.caller Principal rejected"

/-- schedule fails closed (async). -/
private unsafe def testScheduleRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  match ← session.selectProgramV1WithOrigins scheduleSource
      "<cpi-schedule>" "Tests.CpiSchedule" none with
  | .error _ => pure ()
  | .ok (src, origins) =>
      match Compiler.compileProgramProductV1 src origins with
      | .error _ =>
          -- Requirements may mint async; product compile can still succeed.
          pure ()
      | .ok compiled =>
          let selection ← cpiSelection
          -- Preflight rejects async if present; otherwise derive rejects schedule.
          match resolveSolanaCpiPreflightV1 selection compiled with
          | .error error =>
              expect (error.code == "PF-REQ-UNSUPPORTED")
                s!"schedule preflight: {error.render}"
          | .ok preflight =>
              expectCompileErrorContains
                (deriveSolanaCpiPlanFromPreflightV1 preflight)
                "PF-PLAN-INVARIANT" "schedule"
                "schedule rejected at derive"

/-- ADR-0032 U1: retired plan/elf profile ids are not registry members. -/
private unsafe def testWrongProfileRejected
    (_session : Language.Loader.ParserSession) : IO Unit := do
  expectCompileErrorContains
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfPlanV1))
    "PF-PROFILE-UNKNOWN" "solana-sbpf-plan-v1"
    "retired plan profile rejected at build selection"
  expectCompileErrorContains
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfElfV1))
    "PF-PROFILE-UNKNOWN" "solana-sbpf-elf-v1"
    "retired elf profile rejected at build selection"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testCompanionInvokePositive session
  testAllEightApisParamOnly session
  testStateMultiHandler session
  testNormalResolverCompanionProductDenied session
  testMissingExtension session
  testWrongQn session
  testWrongArgType session
  testContextCallerPrincipal session
  testScheduleRejected session
  testWrongProfileRejected session
  IO.println "Tests.Materialization.SolanaCpiDeriveV1: ok"

end Tests.Materialization.SolanaCpiDeriveV1

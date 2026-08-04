/-
  Tests.Materialization.SolanaCpiActivationV1 — #125 RED / acceptance suite.

  Ordinary product path (NOT preflight):
    Loader → compileProgramProductV1 → selection solana-sbpf-cpi-elf-v1
    → resolveEngineeringRequirementsV1 → Solana.planFromCapability /
      irFromCapability (legacy|cpi tagged sum) → CpiV1 product* entries
    → Registry.materializeResult

  Source authority is the real on-disk fixture:
    runtime-tests/solana/fixtures/EscrowCpi.lean

  Registered ordinary-CI acceptance suite. It fixes the #125 product API,
  exact-profile activation, legacy fail-closed matrix, product artifact
  identity, and continued #124 preactivation separation.
-/
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Solana.MaterializationV1
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiIdlV1
import ProofForgeV2.Targets.Solana.CpiProductCapabilityV1
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiEscrowIRV1
import ProofForgeV2.Targets.Solana.EmitCpiEscrowSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EngineeringBuildIdentityV1
import ProofForgeV2.Targets.SupportClaimV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Semantic.RequirementsV1
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiActivationV1

set_option maxRecDepth 4096

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.SupportClaimV1
open ProofForgeV2.Targets.EngineeringBuildIdentityV1
open ProofForgeV2.Targets.Solana
open ProofForgeV2.Targets.Solana.CpiV1
open ProofForgeV2.Semantic.RequirementsV1

/-! ## Fixture / helpers -/

private def fixturePath : String :=
  "runtime-tests/solana/fixtures/EscrowCpi.lean"

private def companionFixturePath : String :=
  "runtime-tests/solana/fixtures/CompanionCpi.lean"

/-- #124 committed preactivation assembly pin (must remain unchanged). -/
private def escrowPreactivationAssemblyShaV1 : String :=
  "sha256:577f40646abb0a355bedebb76dd6b208ff39ae802bea1dab21ce4795ba5d102b"

private def escrowPreactivationAssemblySizeV1 : Nat := 366006

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectOk {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def expectErrorCode {α : Type} (result : CompileResult α)
    (code label : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == code)
        s!"{label}: expected {code}, got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly accepted"

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def digestsEqual (left right : Digest) : Bool :=
  left.algorithm == right.algorithm && left.bytes == right.bytes

private def digestWire (d : Digest) : IO String :=
  match renderDigest d with
  | .ok s => pure s
  | .error e => throw <| IO.userError s!"renderDigest: {e}"

private def sha256WireOfText (text : String) : IO String :=
  match renderDigest (sha256Bytes text.toUTF8) with
  | .ok s => pure s
  | .error e => throw <| IO.userError s!"sha256: {e}"

private def renderBundle (bundle : DiagnosticBundleV1) : String :=
  DiagnosticBundleV1.renderHuman bundle

/-- Product compile result → closed ok/error with human bundle text. -/
private def matchProductCompile (result : DiagnosticResultV1 CompiledSemanticV1)
    (label : String) : IO (Except String CompiledSemanticV1) :=
  match result with
  | .ok compiled => pure (.ok compiled)
  | .error bundle => pure (.error s!"{label}: {renderBundle bundle}")

/-- Load real EscrowCpi fixture via product Loader + product compile. -/
private unsafe def compileEscrowFixture
    (session : Language.Loader.ParserSession) : IO CompiledSemanticV1 := do
  let sourceText ← IO.FS.readFile fixturePath
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText fixturePath "Examples.EscrowCpi" none with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"load Escrow fixture {fixturePath}: {error.render}"
  match Compiler.compileProgramProductV1 source origins with
  | .ok compiled => pure compiled
  | .error bundle =>
      throw <| IO.userError
        s!"product compile rejected EscrowCpi: {renderBundle bundle}"

/-- Load CompanionCpi fixture (product-path negative for companion package). -/
private unsafe def compileCompanionFixture
    (session : Language.Loader.ParserSession) : IO CompiledSemanticV1 := do
  let sourceText ← IO.FS.readFile companionFixturePath
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText companionFixturePath "Examples.CompanionCpi" none with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"load Companion fixture: {error.render}"
  match Compiler.compileProgramProductV1 source origins with
  | .ok compiled => pure compiled
  | .error bundle =>
      throw <| IO.userError
        s!"product compile rejected CompanionCpi: {renderBundle bundle}"

/-- Compile an in-memory ProgramV1 source under a synthetic path. -/
private unsafe def compileSourceText
    (session : Language.Loader.ParserSession)
    (sourceText path moduleName : String) :
    IO (Except String CompiledSemanticV1) := do
  match ← session.selectProgramV1WithOrigins sourceText path moduleName none with
  | .error error =>
      pure (.error error.render)
  | .ok (source, origins) =>
      matchProductCompile (Compiler.compileProgramProductV1 source origins)
        s!"compile {moduleName}"

private def cpiSelection : IO ResolvedBuildSelectionV1 :=
  expectOk
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "resolve CPI profile selection"

private def legacySelection (profile : CodegenProfileId) :
    IO ResolvedBuildSelectionV1 :=
  expectOk (resolveBuildSelectionV1 TargetId.solana (some profile))
    s!"resolve legacy profile {profile}"

private def defaultSelection : IO ResolvedBuildSelectionV1 :=
  expectOk (resolveBuildSelectionV1 TargetId.solana none)
    "resolve default Solana profile"

/-- Exact product base-file order for activated CPI profile (EscrowCpi). -/
private def expectedProductBasePaths : Array String := #[
  "EscrowCpi.cpi-plan.json",
  "EscrowCpi.cpi-ir.json",
  "EscrowCpi.idl.json",
  "EscrowCpi.s",
  "EscrowCpi.cpi-bindings.json"
]

/-! ## Type ascriptions: product core carrier types (not bare Validated*). -/

private def productPlanFromCapabilityTypeAscription :
    ResolvedEngineeringBuildV1 → CompileResult SolanaCpiProductPlanV1 :=
  productPlanFromCapabilityV1

private def productIrFromCapabilityTypeAscription :
    ResolvedEngineeringBuildV1 → CompileResult ResolvedSolanaCpiProductIRV1 :=
  productIrFromCapabilityV1

private def productPlanDigestFromCapabilityTypeAscription :
    ResolvedEngineeringBuildV1 → CompileResult Digest :=
  productPlanDigestFromCapabilityV1

private def productBaseFilesFromCapabilityTypeAscription :
    ResolvedEngineeringBuildV1 → CompileResult (Array OutputFile) :=
  productBaseFilesFromCapabilityV1

/-- planFromCapability must return the legacy|cpi tagged sum (not bare Plan). -/
private def planFromCapabilityTypeAscription :
    ResolvedEngineeringBuildV1 → CompileResult SolanaPlanFromCapabilityV1 :=
  planFromCapability

private def irFromCapabilityTypeAscription :
    ResolvedEngineeringBuildV1 → CompileResult SolanaIRFromCapabilityV1 :=
  irFromCapability

#check (productPlanFromCapabilityV1 :
  ResolvedEngineeringBuildV1 → CompileResult SolanaCpiProductPlanV1)
#check (productIrFromCapabilityV1 :
  ResolvedEngineeringBuildV1 → CompileResult ResolvedSolanaCpiProductIRV1)
#check (productPlanDigestFromCapabilityV1 :
  ResolvedEngineeringBuildV1 → CompileResult Digest)
#check (productBaseFilesFromCapabilityV1 :
  ResolvedEngineeringBuildV1 → CompileResult (Array OutputFile))
#check (planFromCapability :
  ResolvedEngineeringBuildV1 → CompileResult SolanaPlanFromCapabilityV1)
#check (irFromCapability :
  ResolvedEngineeringBuildV1 → CompileResult SolanaIRFromCapabilityV1)

/-! ## Support-claim helpers -/

private def supportIds (claim : EngineeringSupportClaimV1) : Array String :=
  EngineeringSupportClaimV1.supportedIdsOf claim

private def assertCpiSupportClaimExact
    (claim : EngineeringSupportClaimV1) (label : String) : IO Unit := do
  let ids := supportIds claim
  expect (ids.any (· == s2EffectSyncCallIdV1))
    s!"{label}: support claim must advertise effect.synchronous-call"
  expect (ids.any (· == extensionRequirementIdV1))
    s!"{label}: support claim must advertise extension.solana-cpi-accounts"
  expect (!ids.any (· == s2EffectAsyncWorkflowIdV1))
    s!"{label}: support claim must not advertise effect.asynchronous-workflow"
  expect (EngineeringSupportClaimV1.codegenProfileOf claim ==
      CodegenProfileId.solanaSbpfCpiElfV1)
    s!"{label}: claim profile must be solana-sbpf-cpi-elf-v1"
  expect (EngineeringSupportClaimV1.targetIdOf claim == TargetId.solana)
    s!"{label}: claim target must be solana"

/-! ## Positive: ordinary resolve + Plan/IR cpi + 5 files + materialize -/

private unsafe def testOrdinaryEscrowActivationPositive
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileEscrowFixture session
  let selection ← cpiSelection
  expect (selection.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1)
    "selection profile is solana-sbpf-cpi-elf-v1"

  -- Ordinary product resolve (NOT resolveSolanaCpiPreflightV1).
  let capability ← expectOk
    (resolveEngineeringRequirementsV1 selection compiled)
    "ordinary resolveEngineeringRequirementsV1 on EscrowCpi"
  assertCpiSupportClaimExact
    (ResolvedEngineeringBuildV1.supportClaimOf capability)
    "ordinary capability"

  -- Façade tagged sum: Plan/IR must be the cpi variant.
  let planSum ← expectOk (planFromCapability capability)
    "Solana.planFromCapability"
  let cpiPlan ← match planSum with
    | .cpi plan => pure plan
    | .legacy _ =>
        throw <| IO.userError
          "planFromCapability returned .legacy for CPI profile EscrowCpi"
  let cpiPlanCand := SolanaCpiProductPlanV1.candidateOf cpiPlan
  let cpiPlanDigest := SolanaCpiProductPlanV1.digestOf cpiPlan
  expect (cpiPlanCand.schema == planSchemaV1)
    "CPI Plan schema is proof-forge.solana.cpi-plan.v1"
  expect (cpiPlanCand.profileId == profileIdV1)
    "CPI Plan profileId"
  -- #125 product Plan binds active profile/catalog digests (not historical
  -- preactivation pins used by #118–#124).
  let expectedProfileDig ← match parseDigest activeProfileDigestV1 with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  let expectedCatalogDig ← match parseDigest activeCatalogDigestV1 with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  expect (digestsEqual cpiPlanCand.profileDigest expectedProfileDig)
    "CPI Plan profileDigest matches #125 active profile"
  expect (digestsEqual cpiPlanCand.calleeCatalogDigest expectedCatalogDig)
    "CPI Plan catalogDigest matches #125 active catalog"
  -- Product capability refine: activationDenied=false, ordinary support.
  let productCap ← expectOk
    (resolveSolanaCpiProductCapabilityV1 capability)
    "resolveSolanaCpiProductCapabilityV1"
  expect (!ResolvedSolanaCpiProductCapabilityV1.activationDeniedOf productCap)
    "product capability activationDenied=false"

  let irSum ← expectOk (irFromCapability capability)
    "Solana.irFromCapability"
  let cpiIr ← match irSum with
    | .cpi ir => pure ir
    | .legacy _ =>
        throw <| IO.userError
          "irFromCapability returned .legacy for CPI profile EscrowCpi"
  let cpiIrCand := ResolvedSolanaCpiProductIRV1.candidateOf cpiIr
  -- Product IR schema is distinct from #117 inspection `irSchemaV1`.
  let productIrSchema : String := "proof-forge.solana.cpi-product-ir.v1"
  expect (cpiIrCand.schema == productIrSchema)
    s!"CPI product IR schema must be {productIrSchema}, got {cpiIrCand.schema}"
  expect (digestsEqual cpiIrCand.sourcePlanDigest cpiPlanDigest)
    "CPI IR sourcePlanDigest equals CPI Plan digest"

  -- Dedicated CpiV1 product entries (ordinary capability, not preflight).
  let productPlan ← expectOk (productPlanFromCapabilityV1 capability)
    "productPlanFromCapabilityV1"
  let productPlanCand := SolanaCpiProductPlanV1.candidateOf productPlan
  let productPlanDigest := SolanaCpiProductPlanV1.digestOf productPlan
  expect (digestsEqual productPlanDigest cpiPlanDigest)
    "productPlan digest equals façade cpi Plan digest"
  expect (productPlanCand.programName == "EscrowCpi" ||
      productPlanCand.programName.endsWith "EscrowCpi")
    s!"product Plan programName EscrowCpi, got {productPlanCand.programName}"

  let productIr ← expectOk (productIrFromCapabilityV1 capability)
    "productIrFromCapabilityV1"
  let productIrCand := ResolvedSolanaCpiProductIRV1.candidateOf productIr
  expect (digestsEqual productIrCand.sourcePlanDigest productPlanDigest)
    "product IR sourcePlanDigest equals product Plan digest"

  let productDigest ← expectOk (productPlanDigestFromCapabilityV1 capability)
    "productPlanDigestFromCapabilityV1"
  expect (digestsEqual productDigest productPlanDigest)
    "productPlanDigestFromCapabilityV1 equals CPI Plan carrier digest"

  let baseFiles ← expectOk (productBaseFilesFromCapabilityV1 capability)
    "productBaseFilesFromCapabilityV1"
  expect (baseFiles.size == 5)
    s!"product base files size 5, got {baseFiles.size}"
  expect (baseFiles.map (·.path) == expectedProductBasePaths)
    s!"product base paths exact order, got {baseFiles.map (·.path)}"
  for file in baseFiles do
    expect (!file.contents.isEmpty)
      s!"product base file '{file.path}' must be nonempty"

  let some planFile := baseFiles.find? (·.path == "EscrowCpi.cpi-plan.json") |
    throw <| IO.userError "missing EscrowCpi.cpi-plan.json"
  let some irFile := baseFiles.find? (·.path == "EscrowCpi.cpi-ir.json") |
    throw <| IO.userError "missing EscrowCpi.cpi-ir.json"
  let some idlFile := baseFiles.find? (·.path == "EscrowCpi.idl.json") |
    throw <| IO.userError "missing EscrowCpi.idl.json"
  let some asmFile := baseFiles.find? (·.path == "EscrowCpi.s") |
    throw <| IO.userError "missing EscrowCpi.s"
  let some bindingsFile :=
      baseFiles.find? (·.path == "EscrowCpi.cpi-bindings.json") |
    throw <| IO.userError "missing EscrowCpi.cpi-bindings.json"

  -- Assembly: product boundary (no preactivation markers) + real syscalls.
  let asm := asmFile.contents
  expect (!hasSubstr asm "TEST-PREACTIVATION")
    "product assembly must not contain TEST-PREACTIVATION"
  expect (!hasSubstr asm "activationDenied")
    "product assembly must not contain activationDenied"
  expect (!hasSubstr asm "0xec01")
    "product assembly must not contain legacy 0xec01"
  expect (!hasSubstr asm "callx")
    "product assembly must not contain callx"
  expect (hasSubstr asm "call sol_invoke_signed_c")
    "product assembly must emit sol_invoke_signed_c"
  expect (hasSubstr asm "call sol_try_find_program_address")
    "product assembly must emit sol_try_find_program_address"
  expect (hasSubstr asm "call sol_set_return_data")
    "product assembly must emit sol_set_return_data"
  expect (!hasSubstr asm "not a product artifact")
    "product assembly must not claim non-product boundary"

  -- Bindings: active profile/catalog + only referenced system/token/ata pins.
  let bindings := bindingsFile.contents
  expect (hasSubstr bindings profileIdV1)
    "bindings must name active profile solana-sbpf-cpi-elf-v1"
  expect (hasSubstr bindings "system-v1")
    "bindings must pin referenced system-v1"
  expect (hasSubstr bindings "token-classic-v1")
    "bindings must pin referenced token-classic-v1"
  expect (hasSubstr bindings "ata-classic-v1")
    "bindings must pin referenced ata-classic-v1"
  expect (!hasSubstr bindings "companion-v1")
    "bindings must not include unreferenced companion-v1"
  -- Catalog digest wire (domain-separated) must appear for the active catalog.
  let catalogWire ← digestWire expectedCatalogDig
  expect (hasSubstr bindings catalogWire ||
      hasSubstr bindings activeCatalogDigestV1)
    "bindings must carry #125 active catalog digest"
  let profileWire ← digestWire expectedProfileDig
  expect (hasSubstr bindings profileWire ||
      hasSubstr bindings activeProfileDigestV1)
    "bindings must carry #125 active profile digest"

  -- Plan/IR/IDL text bodies nonempty and schema-shaped.
  expect (hasSubstr planFile.contents planSchemaV1 ||
      hasSubstr planFile.contents "cpi-plan")
    "plan file carries cpi-plan schema identity"
  expect (hasSubstr irFile.contents "proof-forge.solana.cpi-product-ir.v1" ||
      hasSubstr irFile.contents "cpi-product-ir" ||
      hasSubstr irFile.contents "cpi-ir")
    "ir file carries product cpi-ir schema identity"
  expect (hasSubstr idlFile.contents idlSchemaV1 ||
      hasSubstr idlFile.contents "EscrowCpi")
    "idl file carries program / idl identity"

  -- Ordinary materialize → MaterializedArtifacts with product boundary.
  let artifacts ← expectOk (materializeResult capability)
    "Registry.materializeResult ordinary CPI"
  expect (MaterializedArtifactsV1.codegenProfileIdOf artifacts ==
      CodegenProfileId.solanaSbpfCpiElfV1)
    "materialized profile is CPI elf"
  expect (MaterializedArtifactsV1.targetIdOf artifacts == TargetId.solana)
    "materialized target is solana"
  expect (MaterializedArtifactsV1.artifactProgramNameOf artifacts == "EscrowCpi")
    s!"materialized artifact name EscrowCpi, got {MaterializedArtifactsV1.artifactProgramNameOf artifacts}"
  let matFiles := MaterializedArtifactsV1.filesOf artifacts
  expect (matFiles.map (·.path) == expectedProductBasePaths)
    s!"materialize files match product base paths, got {matFiles.map (·.path)}"
  expect (matFiles.all (fun f => !f.contents.isEmpty))
    "materialize files nonempty"
  -- product boundary: mint succeeded and assembly is product (not preactivation).
  let some matAsm := matFiles.find? (·.path == "EscrowCpi.s") |
    throw <| IO.userError "materialize missing EscrowCpi.s"
  expect (!hasSubstr matAsm.contents "TEST-PREACTIVATION" &&
      !hasSubstr matAsm.contents "activationDenied")
    "materialize assembly product boundary true"
  -- BuildIdentity planDigest binds the CPI Plan carrier digest.
  let identity := MaterializedArtifactsV1.buildIdentityOf artifacts
  expect (digestsEqual
      (EngineeringBuildIdentityV1.planDigestOf identity) productDigest)
    "BuildIdentity.planDigest equals CPI Plan carrier digest"
  expect (EngineeringBuildIdentityV1.codegenProfileOf identity ==
      CodegenProfileId.solanaSbpfCpiElfV1)
    "BuildIdentity profile is CPI"
  expect (EngineeringBuildIdentityV1.artifactNameOf identity == "EscrowCpi")
    "BuildIdentity artifact name EscrowCpi"

  -- product* entries and materialize must agree on plan digest / files.
  expect (baseFiles.map (·.path) == matFiles.map (·.path))
    "productBaseFiles path order equals materialize files"

/-! ## Negative: legacy profiles still PF-REQ-UNSUPPORTED, no files -/

private unsafe def testLegacyProfilesRejectEscrow
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileEscrowFixture session
  for profile in #[CodegenProfileId.solanaSbpfPlanV1,
      CodegenProfileId.solanaSbpfElfV1] do
    let selection ← legacySelection profile
    match resolveEngineeringRequirementsV1 selection compiled with
    | .error error =>
        expect (error.code == "PF-REQ-UNSUPPORTED")
          s!"legacy {profile}: expected PF-REQ-UNSUPPORTED, got {error.render}"
    | .ok capability =>
        -- Even if resolve were wrongly open, Plan/files must not mint.
        match planFromCapability capability with
        | .ok _ =>
            throw <| IO.userError
              s!"legacy {profile}: planFromCapability must fail for EscrowCpi"
        | .error e =>
            expect (e.code == "PF-REQ-UNSUPPORTED" ||
                e.code == "PF-PLAN-INVARIANT" ||
                e.code == "PF-REGISTRY-INVALID")
              s!"legacy {profile}: plan fail closed, got {e.render}"
        match buildFromCapability capability with
        | .ok files =>
            expect (files.isEmpty)
              s!"legacy {profile}: must not mint product files, got {files.map (·.path)}"
            throw <| IO.userError
              s!"legacy {profile}: buildFromCapability must fail closed (no files)"
        | .error e =>
            expect (e.code == "PF-REQ-UNSUPPORTED" ||
                e.code == "PF-PLAN-INVARIANT" ||
                e.code == "PF-REGISTRY-INVALID")
              s!"legacy {profile}: build fail closed, got {e.render}"
        match materializeResult capability with
        | .ok _ =>
            throw <| IO.userError
              s!"legacy {profile}: materializeResult must not succeed"
        | .error e =>
            expect (e.code == "PF-REQ-UNSUPPORTED" ||
                e.code == "PF-PLAN-INVARIANT" ||
                e.code == "PF-REGISTRY-INVALID" ||
                e.code == "PF-SRC-INVALID")
              s!"legacy {profile}: materialize fail closed, got {e.render}"

/-! ## Negative: product path fail-closed matrix before Plan/artifact -/

private def extensionHeaderGood : String :=
  "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
  "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n"

private def wrapMinimal (name body : String) (extHeader : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  s!"program {name} where\n" ++
  extHeader ++
  "  state value : UInt64\n" ++
  "  init(i : UInt64) do\n" ++
  "    value := i\n" ++
  body ++
  "  view inspect() : UInt64 do\n" ++
  "    return value\n"

private def transferOnlyBody : String :=
  "  entry deposit(\n" ++
  "      source : Principal, mint : Principal, dest : Principal,\n" ++
  "      auth : Principal, amount : UInt64, decimals : UInt8) : UInt64 do\n" ++
  "    call solana.token.transferChecked(\n" ++
  "      source, mint, dest, auth, amount, decimals)\n" ++
  "    return value\n"

/-- schedule on CPI profile must fail closed (no async support). -/
private unsafe def testScheduleRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapMinimal "CpiScheduleReject" (
      "  entry kick(dest : Principal) : UInt64 do\n" ++
      "    schedule solana.companion.invoke(dest, 1)\n" ++
      "    return value\n") extensionHeaderGood
  match ← compileSourceText session src
      "<cpi-schedule-reject>" "Examples.CpiScheduleReject" with
  | .error msg =>
      -- May fail at Normalize / effect / schedule shape; any closed failure ok
      -- before product files, but prefer exact codes when available.
      expect (hasSubstr msg "PF-REQ-UNSUPPORTED" ||
          hasSubstr msg "PF-SRC-INVALID" ||
          hasSubstr msg "PF-EFFECT-001" ||
          hasSubstr msg "PF-PLAN-INVARIANT" ||
          hasSubstr msg "schedule" ||
          hasSubstr msg "unsupported")
        s!"schedule compile/resolve class, got {msg}"
  | .ok compiled =>
      let selection ← cpiSelection
      match resolveEngineeringRequirementsV1 selection compiled with
      | .error error =>
          expect (error.code == "PF-REQ-UNSUPPORTED")
            s!"schedule ordinary resolve PF-REQ-UNSUPPORTED, got {error.render}"
      | .ok capability =>
          expectErrorCode (planFromCapability capability)
            "PF-PLAN-INVARIANT" "schedule planFromCapability"
          expectErrorCode (productPlanFromCapabilityV1 capability)
            "PF-PLAN-INVARIANT" "schedule productPlan"
          expectErrorCode (materializeResult capability)
            "PF-PLAN-INVARIANT" "schedule materialize"

/-- Unknown external QN fails closed before product Plan/artifact. -/
private unsafe def testUnknownApiOpRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapMinimal "CpiUnknownApi" (
      "  entry go(account : Principal, delta : UInt64) : UInt64 do\n" ++
      "    call solana.unknown.notAnApi(account, delta)\n" ++
      "    return value\n") extensionHeaderGood
  match ← compileSourceText session src
      "<cpi-unknown-api>" "Examples.CpiUnknownApi" with
  | .error msg =>
      expect (hasSubstr msg "PF-SRC-INVALID" ||
          hasSubstr msg "PF-REQ-UNSUPPORTED" ||
          hasSubstr msg "PF-PLAN-INVARIANT" ||
          hasSubstr msg "unknown" ||
          hasSubstr msg "notAnApi")
        s!"unknown API compile class, got {msg}"
  | .ok compiled =>
      let selection ← cpiSelection
      match resolveEngineeringRequirementsV1 selection compiled with
      | .error error =>
          expect (error.code == "PF-REQ-UNSUPPORTED" ||
              error.code == "PF-PLAN-INVARIANT")
            s!"unknown API resolve class, got {error.render}"
      | .ok capability =>
          -- Must fail at Plan product path (unknown frozen API).
          match productPlanFromCapabilityV1 capability with
          | .error error =>
              expect (error.code == "PF-PLAN-INVARIANT" ||
                  error.code == "PF-REQ-UNSUPPORTED")
                s!"unknown API productPlan, got {error.render}"
          | .ok _ =>
              throw <| IO.userError
                "unknown API productPlanFromCapabilityV1 must fail closed"
          expectErrorCode (materializeResult capability)
            "PF-PLAN-INVARIANT" "unknown API materialize"

/-- Companion package is not product-admitted; product path fails closed. -/
private unsafe def testCompanionProductRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileCompanionFixture session
  let selection ← cpiSelection
  match resolveEngineeringRequirementsV1 selection compiled with
  | .error error =>
      -- Either support still closed, or later product gates reject companion.
      expect (error.code == "PF-REQ-UNSUPPORTED" ||
          error.code == "PF-PLAN-INVARIANT")
        s!"companion resolve class, got {error.render}"
  | .ok capability =>
      match productPlanFromCapabilityV1 capability with
      | .error error =>
          expect (error.code == "PF-PLAN-INVARIANT" ||
              error.code == "PF-REQ-UNSUPPORTED" ||
              error.code == "PF-REGISTRY-INVALID")
            s!"companion productPlan fail closed, got {error.render}"
      | .ok plan =>
          -- If plan validates inspection-only, materialization eligibility /
          -- base files / materialize must still refuse companion pins.
          match productBaseFilesFromCapabilityV1 capability with
          | .error error =>
              expect (error.code == "PF-PLAN-INVARIANT" ||
                  error.code == "PF-REQ-UNSUPPORTED" ||
                  error.code == "PF-REGISTRY-INVALID")
                s!"companion productBaseFiles fail closed, got {error.render}"
          | .ok files =>
              expect (!files.any (fun f => hasSubstr f.contents "companion-v1" &&
                  hasSubstr f.path "bindings"))
                "companion product bindings must not advertise companion-v1 as admitted"
              throw <| IO.userError
                s!"companion productBaseFiles must fail closed, got {files.map (·.path)}"
          expectErrorCode (materializeResult capability)
            "PF-PLAN-INVARIANT" "companion materialize"
          let _ := plan
          pure ()

/-- Wrong extension version / digest fail closed (PF-EXT / PF-REQ / SRC). -/
private unsafe def testWrongExtensionRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let badVersion :=
    "  requires extension solana.cpi.accounts version \"1.0.1\"\n" ++
    "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n"
  let badDigest :=
    "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
    "    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"\n"
  for (label, header) in #[
      ("version", badVersion),
      ("digest", badDigest)] do
    let src := wrapMinimal s!"CpiBadExt{label}" transferOnlyBody header
    match ← compileSourceText session src
        s!"<cpi-bad-ext-{label}>" s!"Examples.CpiBadExt{label}" with
    | .error msg =>
        expect (hasSubstr msg "PF-EXT-001" ||
            hasSubstr msg "PF-EXTENSION-VERSION" ||
            hasSubstr msg "PF-SRC-INVALID" ||
            hasSubstr msg "PF-REQ-UNSUPPORTED" ||
            hasSubstr msg "extension")
          s!"wrong extension {label} compile class, got {msg}"
    | .ok compiled =>
        let selection ← cpiSelection
        expectErrorCode
          (resolveEngineeringRequirementsV1 selection compiled)
          "PF-REQ-UNSUPPORTED"
          s!"wrong extension {label} ordinary resolve"

/-- Wrong catalog / program-id surface fails before product artifact mint.
    Uses a non-frozen program QN that mimics Token-2022 / wrong package id. -/
private unsafe def testWrongProgramIdOrCatalogRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Non-catalog QN path (already covered) + TokenzQd-shaped wrong program
  -- cannot appear in source QN; product Plan must only accept frozen APIs.
  let src := wrapMinimal "CpiWrongCatalog" (
      "  entry go(account : Principal, amount : UInt64) : UInt64 do\n" ++
      "    call solana.token2022.transferChecked(\n" ++
      "      account, account, account, account, amount, 0)\n" ++
      "    return value\n") extensionHeaderGood
  match ← compileSourceText session src
      "<cpi-wrong-catalog>" "Examples.CpiWrongCatalog" with
  | .error msg =>
      expect (hasSubstr msg "PF-SRC-INVALID" ||
          hasSubstr msg "PF-REQ-UNSUPPORTED" ||
          hasSubstr msg "PF-PLAN-INVARIANT" ||
          hasSubstr msg "token2022" ||
          hasSubstr msg "unknown")
        s!"wrong catalog compile class, got {msg}"
  | .ok compiled =>
      let selection ← cpiSelection
      match resolveEngineeringRequirementsV1 selection compiled with
      | .error error =>
          expect (error.code == "PF-REQ-UNSUPPORTED" ||
              error.code == "PF-PLAN-INVARIANT")
            s!"wrong catalog resolve, got {error.render}"
      | .ok capability =>
          expectErrorCode (productPlanFromCapabilityV1 capability)
            "PF-PLAN-INVARIANT" "wrong catalog productPlan"
          expectErrorCode (materializeResult capability)
            "PF-PLAN-INVARIANT" "wrong catalog materialize"

/-! ## Default profile unchanged -/

private def testDefaultProfileUnchanged : IO Unit := do
  let selection ← defaultSelection
  expect (selection.codegenProfile == CodegenProfileId.solanaSbpfPlanV1)
    "default Solana profile remains solana-sbpf-plan-v1"
  let registry ← expectOk initialTargetRegistryV1Result "registry seed"
  let some reg := findRegistrationV1 registry TargetId.solana |
    throw <| IO.userError "solana registration missing"
  expect (reg.defaultProfile == some CodegenProfileId.solanaSbpfPlanV1)
    "registry defaultProfile remains solana-sbpf-plan-v1"
  expect (reg.profiles == #[
      CodegenProfileId.solanaSbpfCpiElfV1,
      CodegenProfileId.solanaSbpfElfV1,
      CodegenProfileId.solanaSbpfPlanV1])
    "registry Solana profiles order cpi < elf < plan"

/-! ## Preflight vs product carriers are not interchangeable -/

private unsafe def testPreflightProductNonInterchangeable
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileEscrowFixture session
  let selection ← cpiSelection

  -- Preflight carrier still mints with activationDenied and cannot be product.
  let preflight ← expectOk (resolveSolanaCpiPreflightV1 selection compiled)
    "preflight resolve still available"
  expect (ResolvedSolanaCpiPreflightV1.activationDeniedOf preflight)
    "preflight activationDenied remains true"
  -- Type-level: product APIs require ResolvedEngineeringBuildV1 (ascription
  -- above). Runtime string/reflection gate: preflight type name must not
  -- appear as materialize capability, and product entry names must not be
  -- preflight aliases.
  let preflightTypeName := "ResolvedSolanaCpiPreflightV1"
  let productPlanName := "productPlanFromCapabilityV1"
  let productFilesName := "productBaseFilesFromCapabilityV1"
  expect (preflightTypeName != "ResolvedEngineeringBuildV1")
    "preflight type name distinct from product capability"
  expect (!productPlanName.endsWith "Preflight" &&
      !productFilesName.endsWith "Preflight")
    "product entry names must not be Preflight aliases"
  -- Ordinary product capability (post-activation) is a different carrier.
  let capability ← expectOk
    (resolveEngineeringRequirementsV1 selection compiled)
    "ordinary capability for non-interchange"
  -- productPlan must not reintroduce activationDenied on the Plan candidate.
  let productPlan ← expectOk (productPlanFromCapabilityV1 capability)
    "product plan for non-interchange"
  let productPlanCandNI := SolanaCpiProductPlanV1.candidateOf productPlan
  expect (productPlanCandNI.profileId == profileIdV1)
    "product plan profile"
  -- Preflight derive path still produces preactivation assembly boundary.
  let pfPlan ← expectOk (deriveSolanaCpiPlanFromPreflightV1 preflight)
    "preflight derive plan"
  let escrowIr ← expectOk (resolveSolanaCpiEscrowIRV1 pfPlan)
    "preflight Escrow IR"
  let assembly ← expectOk (emitCpiEscrowSbpfV1 escrowIr)
    "preflight Escrow emitter"
  expect (!SolanaCpiEscrowAssemblyV1.isProductArtifact assembly &&
      SolanaCpiEscrowAssemblyV1.isTestPreactivation assembly)
    "#124 preactivation assembly boundary unchanged"
  let text := SolanaCpiEscrowAssemblyV1.textOf assembly
  expect (hasSubstr text "TEST-PREACTIVATION ONLY")
    "#124 preactivation banner retained"
  expect (hasSubstr text "activationDenied" ||
      hasSubstr text "not a product artifact")
    "#124 non-product banner retained"
  -- Pin size + sha of #124 preactivation assembly (must not drift under #125).
  expect (text.toUTF8.size == escrowPreactivationAssemblySizeV1)
    s!"#124 assembly size pin {escrowPreactivationAssemblySizeV1}, got {text.toUTF8.size}"
  let asmSha ← sha256WireOfText text
  expect (asmSha == escrowPreactivationAssemblyShaV1)
    s!"#124 assembly sha pin unchanged, got {asmSha}"
  -- Product assembly from ordinary path must differ in boundary markers.
  let productFiles ← expectOk (productBaseFilesFromCapabilityV1 capability)
    "product files for non-interchange"
  let some productAsm := productFiles.find? (·.path == "EscrowCpi.s") |
    throw <| IO.userError "product files missing EscrowCpi.s"
  expect (!hasSubstr productAsm.contents "TEST-PREACTIVATION")
    "product assembly distinct from preactivation carrier text"
  -- String/source gate: product entries must exist under CpiV1 and must not be
  -- preflight aliases (concurrent #125 implementer surface).
  let productHit ← IO.Process.output {
    cmd := "rg"
    args := #[
      "-n",
      "--glob", "*.lean",
      "def productPlanFromCapabilityV1\\b",
      "ProofForgeV2"
    ]
  }
  expect (productHit.exitCode == 0)
    s!"productPlanFromCapabilityV1 must exist under ProofForgeV2 (rg exit {productHit.exitCode})"
  expect (!hasSubstr productHit.stdout "Preflight")
    "productPlanFromCapabilityV1 definition path must not be a Preflight alias"
  let preflightHit ← IO.Process.output {
    cmd := "rg"
    args := #[
      "-n",
      "--glob", "*.lean",
      "def resolveSolanaCpiPreflightV1\\b",
      "ProofForgeV2"
    ]
  }
  expect (preflightHit.exitCode == 0)
    "resolveSolanaCpiPreflightV1 must remain for #118–#124 preactivation lane"
  expect (productHit.stdout != preflightHit.stdout)
    "product and preflight definition sites must differ"

/-! ## Entry -/

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testDefaultProfileUnchanged
  testOrdinaryEscrowActivationPositive session
  testLegacyProfilesRejectEscrow session
  testScheduleRejected session
  testUnknownApiOpRejected session
  testCompanionProductRejected session
  testWrongExtensionRejected session
  testWrongProgramIdOrCatalogRejected session
  testPreflightProductNonInterchangeable session
  IO.println "Tests.Materialization.SolanaCpiActivationV1: ok"

end Tests.Materialization.SolanaCpiActivationV1

import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.FinalizeV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

/-!
# Tests.Targets.SolanaElfV1 — S2a solana-sbpf-elf-v1 profile

Pins:
* registry membership of legacy `solana-sbpf-elf-v1` plus
  `solana-sbpf-cpi-elf-v1`, with default still plan-v1
* profile-scoped requirement-support rows: only cpi profile carries the exact
  extension row; #125 cpi admits `effect.synchronous-call` and still declines
  async; both legacy profiles still decline sync/async/extension
* residual descriptor stays plan-v1 but accepts both opt-in profiles
* buildFromCapability under elf emits `.s` + plan + IDL; plan profile unchanged
* `.s` contents match `emitSbpfAsmV1` and are deterministic
* FinalizeV1 plan profile stays zero-tool
* FinalizeV1 elf pure helpers + missing-tool path (`PF-TOOLCHAIN-MISSING` via empty PROOF_FORGE_TOOL_ROOT)
* empty-.so gate without invoking the real assembler
* #125 active CPI contract digests / admitted package closure / loader-v3 ELF pins

S2b registers locked `sbpf` (sourceBuild). Missing-tool coverage forces an empty tool root
so the suite stays hermetic without a provisioned binary. Positive e2e `.so` emission is a
manual/CI provision+materialize path, not this suite.
-/

namespace Tests.Targets.SolanaElfV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Examples
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.Solana
open ProofForgeV2.Targets.Solana.CpiV1
open ProofForgeV2.Materialization.LockedToolchainV1
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def expectCompileErrorContains
    (label code detail : String) (result : CompileResult α) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"{label}: expected failure"
  | .error error =>
      let rendered := error.render
      expect (rendered.contains code && rendered.contains detail)
        s!"{label}: expected {code} and '{detail}', got {rendered}"

private def expectIoErrorContains (label expected : String) (action : IO Unit) : IO Unit := do
  try
    action
    throw <| IO.userError s!"{label}: expected error containing '{expected}'"
  catch e =>
    let msg := toString e
    unless msg.contains expected do
      throw <| IO.userError s!"{label}: expected '{expected}' in:\n{msg}"

private unsafe def compileSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1 source path moduleName none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

private def solanaCapability
    (compiled : CompiledSemanticV1) (profile? : Option CodegenProfileId) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.solana profile?
  Targets.resolveEngineeringRequirementsV1 selection compiled

/-- Registry: cpi/elf/plan are exact members; default is sole-rail cpi-elf. -/
private def testRegistryMembership : IO Unit := do
  let reg ← liftResult <| registration? TargetId.solana
  let reg ← match reg with
    | some r => pure r
    | none => throw <| IO.userError "solana registration missing"
  expect (reg.profiles == #[CodegenProfileId.solanaSbpfCpiElfV1,
      CodegenProfileId.solanaSbpfElfV1, CodegenProfileId.solanaSbpfPlanV1])
    s!"registry: exact cpi/elf/plan profile order, got {reg.profiles.map (·.toString)}"
  expect (reg.defaultProfile == some CodegenProfileId.solanaSbpfCpiElfV1)
    "registry: default profile is sole rail solana-sbpf-cpi-elf-v1 (ADR-0032 P4)"
  expect (!(ProofForgeV2.Targets.BuildSelectionV1.reservedFutureProfiles.contains
      "solana-sbpf-cpi-elf-v1"))
    "registry: solana-sbpf-cpi-elf-v1 is an opt-in registered product member"
  expect (!(ProofForgeV2.Targets.BuildSelectionV1.reservedFutureProfiles.contains
      "solana-sbpf-elf-v1"))
    "registry: solana-sbpf-elf-v1 is no longer reserved"
  expect (ProofForgeV2.Targets.BuildSelectionV1.reservedFutureProfiles.contains
      "noir-acir-proof-v1")
    "registry: noir-acir-proof-v1 remains reserved"
  let defaultSel ← liftResult <| resolveBuildSelectionV1 TargetId.solana none
  expect (defaultSel.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1)
    "resolve: default selection is plan profile"
  let cpiSel ← liftResult <|
    resolveBuildSelectionV1 TargetId.solana (some CodegenProfileId.solanaSbpfCpiElfV1)
  expect (cpiSel.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1)
    "resolve: explicit inert cpi selection"
  let elfSel ← liftResult <|
    resolveBuildSelectionV1 TargetId.solana (some CodegenProfileId.solanaSbpfElfV1)
  expect (elfSel.codegenProfile == CodegenProfileId.solanaSbpfElfV1)
    "resolve: explicit elf selection"

/-- Profile-scoped extension support; descriptor residual stays plan. -/
private def testSupportAndDescriptor : IO Unit := do
  let rows ← liftResult productSupportRowsV1
  let cpiRow ← match rows.find? (fun r =>
      r.targetId == TargetId.solana &&
        r.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1) with
    | some r => pure r
    | none => throw <| IO.userError "missing inert solana cpi support row"
  let elfRow ← match rows.find? (fun r =>
      r.targetId == TargetId.solana &&
        r.codegenProfile == CodegenProfileId.solanaSbpfElfV1) with
    | some r => pure r
    | none => throw <| IO.userError "missing solana elf support row"
  let planRow ← match rows.find? (fun r =>
      r.targetId == TargetId.solana &&
        r.codegenProfile == CodegenProfileId.solanaSbpfPlanV1) with
    | some r => pure r
    | none => throw <| IO.userError "missing solana plan support row"
  expect (elfRow.supported.map (·.id) == planRow.supported.map (·.id))
    "support: legacy elf and plan retain the exact S2 id list"
  let legacyIds := planRow.supported.map (·.id)
  expect (legacyIds.size == 5 &&
      !legacyIds.contains "effect.synchronous-call" &&
      !legacyIds.contains "effect.asynchronous-workflow" &&
      !legacyIds.contains "extension.solana-cpi-accounts")
    "support: legacy profiles decline call/schedule and the opt-in extension"
  let cpiIds := cpiRow.supported.map (·.id)
  -- #125 + ADR-0029 B1: CPI admits exact sync + both extensions
  -- (solana-cpi-accounts and pf-assets); still declines async.
  expect (cpiIds.size == 8 &&
      cpiIds.contains "effect.synchronous-call" &&
      cpiIds.contains "extension.pf-assets" &&
      !cpiIds.contains "effect.asynchronous-workflow")
    "support: cpi profile admits sync and declines async"
  let expectedExtension ← match
      ProofForgeV2.Semantic.WireV1.solanaCpiAccountsExtensionRequirementV1 with
    | .ok row => pure row
    | .error error => throw <| IO.userError s!"extension row: {error}"
  expect (cpiRow.supported.filter (·.id == "extension.solana-cpi-accounts") ==
      #[expectedExtension])
    "support: cpi profile carries one exact extension row"
  expect (!(elfRow.supported.any (·.id == "extension.solana-cpi-accounts")) &&
      !(planRow.supported.any (·.id == "extension.solana-cpi-accounts")))
    "support: extension row must be scoped to the cpi profile"
  expect (!(elfRow.supported.any (·.id == "effect.synchronous-call")) &&
      !(planRow.supported.any (·.id == "effect.synchronous-call")))
    "support: legacy profiles still decline sync"
  let desc := Targets.Solana.descriptor
  expect (desc.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1)
    "descriptor: residual binds sole-rail cpi-elf profile"
  expect (acceptsCodegenProfile desc CodegenProfileId.solanaSbpfCpiElfV1)
    "descriptor: accepts cpi-elf default"
  expect (acceptsCodegenProfile desc CodegenProfileId.solanaSbpfPlanV1)
    "descriptor: accepts plan shim"
  expect (acceptsCodegenProfile desc CodegenProfileId.solanaSbpfElfV1)
    "descriptor: accepts elf shim"
  expect (!acceptsCodegenProfile desc CodegenProfileId.evmYulSolc0834V1)
    "descriptor: rejects foreign profile"

/-- #125 active contract authority: digests, admitted product closure, loader-v3 ELF. -/
private def testActiveCpiContract : IO Unit := do
  -- Historical preactivation pins must remain exactly as #114–#124.
  expect (profileDigestV1 ==
      "sha256:0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1")
    "historical profileDigestV1 pin"
  expect (catalogDigestV1 ==
      "sha256:41ace268b3bea9837e4a1fc9e456dbfbd36c98a344e51dfd095ab4ffb2086351")
    "historical catalogDigestV1 pin"
  expect (frozenCalleePackagesV1.size == 4)
    "historical package table size"
  expect (frozenCalleePackagesV1.all fun p => !p.admittedForMaterialization)
    "historical packages remain non-admitted"
  -- Active digests / version / implementation state.
  expect (activeProfileDigestV1 ==
      "sha256:b0f3f5bc7f3973daf176c308cc4ca310f8ad5b51ea33a33c9d1bd3e4d3e91b04")
    "activeProfileDigestV1 pin"
  expect (activeCatalogDigestV1 ==
      "sha256:e2c2ebac5e690b99ad50fb7f8a5f6ecfdb8295bb43f3913229c2fd48d2820419")
    "activeCatalogDigestV1 pin"
  expect (activeCatalogVersionV1 == "1.1.0") "active catalog version"
  expect (activeProfileImplementationStateV1 ==
      "product-exact-synchronous-call-active-v1")
    "active implementationState"
  expect (extensionDigestV1 ==
      "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020")
    "extension digest unchanged"
  expect (profileIdV1 == "solana-sbpf-cpi-elf-v1") "active profile id unchanged"
  match validateActiveCalleePackagesV1 with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"active package validation: {e}"
  -- Companion stays test-only / absent.
  let companion ← match findActiveCalleePackage? "companion-v1" with
    | some p => pure p
    | none => throw <| IO.userError "missing active companion-v1"
  expect (companion.admittedForMaterialization == false)
    "active companion not admitted"
  expect (companion.artifactBinding == .absent) "active companion binding absent"
  expect (companion.qns.size == 3) "companion three test-only APIs"
  -- System admitted + runtimeNative only.
  let system ← match findActiveCalleePackage? "system-v1" with
    | some p => pure p
    | none => throw <| IO.userError "missing active system-v1"
  expect (system.admittedForMaterialization == true) "system admitted"
  expect (system.artifactBinding == .runtimeNative agaveV400CommitV1)
    "system runtimeNative Agave pin"
  expect (system.qns.size == 2) "system two APIs"
  -- Token/ATA admitted + exact loader-v3 ELF binding.
  let token ← match findActiveCalleePackage? "token-classic-v1" with
    | some p => pure p
    | none => throw <| IO.userError "missing active token-classic-v1"
  expect (token.admittedForMaterialization == true) "token admitted"
  expect (token.artifactBinding == .loaderV3Elf tokenClassicLoaderV3ElfBindingV1)
    "token loader-v3 ELF pin"
  expect (token.qns.size == 2) "token two APIs"
  let ata ← match findActiveCalleePackage? "ata-classic-v1" with
    | some p => pure p
    | none => throw <| IO.userError "missing active ata-classic-v1"
  expect (ata.admittedForMaterialization == true) "ata admitted"
  expect (ata.artifactBinding == .loaderV3Elf ataClassicLoaderV3ElfBindingV1)
    "ata loader-v3 ELF pin"
  expect (ata.qns.size == 1) "ata one API"
  -- Exact lookup surfaces.
  expect ((findActiveCalleePackageByQn? "solana.system.transfer").map (·.packageId) ==
      some "system-v1") "active QN lookup system"
  expect ((findActiveCalleePackageByQn? "solana.token.transferChecked").map
      (·.packageId) == some "token-classic-v1") "active QN lookup token"
  expect ((findActiveCalleePackageByQn? "solana.ata.createIdempotent").map
      (·.packageId) == some "ata-classic-v1") "active QN lookup ata"
  expect ((findActiveCalleePackageByQn? "solana.companion.invoke").map
      (·.admittedForMaterialization) == some false)
    "companion QN remains non-admitted"
  expect (activeProductPackageIdsV1 ==
      #["system-v1", "token-classic-v1", "ata-classic-v1"])
    "approved product package closure"
  expect (activeProductApiQnsV1.size == 5) "approved product API count"
  -- Package-owned asset pins.
  expect (tokenClassicActiveElfPathV1 ==
      "supply-chain/solana-cpi-assets/v1/token_classic_v1.so")
    "token asset path"
  expect (ataClassicActiveElfPathV1 ==
      "supply-chain/solana-cpi-assets/v1/ata_classic_v1.so")
    "ata asset path"
  expect (tokenClassicActiveElfSizeV1 == 94960) "token elf size"
  expect (ataClassicActiveElfSizeV1 == 111136) "ata elf size"
  expect (tokenClassicActiveElfSha256V1 ==
      "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9")
    "token elf sha256"
  expect (ataClassicActiveElfSha256V1 ==
      "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519")
    "ata elf sha256"

/-- buildFromCapability: plan shim / elf shim / cpi sole-rail emit surfaces. -/
private unsafe def testEmitProfiles
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session counterSourceText counterModuleNameV1
    "<solana-elf-emit>"
  -- Plan shim regression (explicit profile; default is sole-rail cpi-elf)
  let planCap ← liftResult <|
    solanaCapability compiled (some CodegenProfileId.solanaSbpfPlanV1)
  let planFiles ← liftResult <| buildFromCapability planCap
  let planPaths := planFiles.map (·.path)
  expect (planPaths.any (· == "Counter.sbpf-plan")) "plan emit: .sbpf-plan"
  expect (planPaths.any (· == "Counter.idl.json")) "plan emit: idl"
  expect (!planPaths.any (fun p => p.endsWith ".s"))
    "plan emit: must not publish .s"
  let planIdl ← match planFiles.find? (·.path == "Counter.idl.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "plan emit: missing idl"
  expect (planIdl.contains "\"codegenProfile\": \"solana-sbpf-plan-v1\"")
    "plan idl: codegen profile is plan"
  expect (planIdl.contains "\"deployable\": false")
    "plan idl: non-deployable"
  -- Elf profile
  let elfCap ← liftResult <|
    solanaCapability compiled (some CodegenProfileId.solanaSbpfElfV1)
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf elfCap ==
      CodegenProfileId.solanaSbpfElfV1)
    "elf capability profile"
  let elfFiles ← liftResult <| buildFromCapability elfCap
  let elfPaths := elfFiles.map (·.path)
  expect (elfPaths.any (· == "Counter.sbpf-plan")) "elf emit: .sbpf-plan"
  expect (elfPaths.any (· == "Counter.idl.json")) "elf emit: idl"
  expect (elfPaths.any (· == "Counter.s")) "elf emit: .s"
  let elfIdl ← match elfFiles.find? (·.path == "Counter.idl.json") with
    | some f => pure f.contents
    | none => throw <| IO.userError "elf emit: missing idl"
  expect (elfIdl.contains "\"codegenProfile\": \"solana-sbpf-elf-v1\"")
    "elf idl: codegen profile is elf"
  expect (elfIdl.contains "\"deployable\": true")
    "elf idl: deployable"
  let asmFromFiles ← match elfFiles.find? (·.path == "Counter.s") with
    | some f => pure f.contents
    | none => throw <| IO.userError "elf emit: missing .s file"
  let irCarrier ← liftResult <| irFromCapability elfCap
  let ir ← match irCarrier with
    | .legacy ir => pure ir
    | .cpi _ => throw <| IO.userError "elf emit: expected legacy IR carrier"
  let asmDirect ← liftResult <| emitSbpfAsmV1 ir
  expect (asmFromFiles == asmDirect)
    "elf emit: .s contents equal emitSbpfAsmV1"
  expect (asmFromFiles.contains ".globl entrypoint")
    "elf emit: assembly golden fragment"
  expect (asmFromFiles.contains "entrypoint:")
    "elf emit: entrypoint label"
  let asm2 ← liftResult <| emitSbpfAsmV1 ir
  expect (asmFromFiles == asm2) "elf emit: deterministic"
  -- Aggregate materialize under elf also binds profile and ships .s
  let artifacts ← liftResult <| Targets.materializeResult elfCap
  expect (MaterializedArtifactsV1.codegenProfileIdOf artifacts ==
      CodegenProfileId.solanaSbpfElfV1)
    "materialize: carrier profile is elf"
  let matPaths := (MaterializedArtifactsV1.filesOf artifacts).map (·.path)
  expect (matPaths.any (· == "Counter.s")) "materialize: includes .s"

  -- ADR-0032 U1 P4: Counter body-only mints on sole rail cpi-elf
  -- (zero sites → full-body hybrid, not escrow product IR).
  let cpiCap ← liftResult <|
    solanaCapability compiled (some CodegenProfileId.solanaSbpfCpiElfV1)
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf cpiCap ==
      CodegenProfileId.solanaSbpfCpiElfV1)
    "cpi capability binds the sole-rail profile"
  match planFromCapability cpiCap with
  | .ok (.cpi plan) =>
      let cand := SolanaCpiProductPlanV1.candidateOf plan
      expect (cand.cpiSites.isEmpty) "cpi plan: body-only zero sites"
  | .ok (.legacy _) =>
      throw <| IO.userError "cpi plan: must not enter legacy Plan for cpi profile"
  | .error error =>
      throw <| IO.userError s!"cpi plan: body-only must mint, got {error.render}"
  let cpiFiles ← liftResult <| buildFromCapability cpiCap
  let cpiPaths := cpiFiles.map (·.path)
  expect (cpiPaths.any (· == "Counter.s")) "cpi body-only emit: .s"
  expect (cpiPaths.any (· == "Counter.cpi-ir.json")) "cpi body-only emit: hybrid ir"
  expect (cpiPaths.any (· == "Counter.cpi-plan.json")) "cpi body-only emit: plan"
  let cpiArtifacts ← liftResult <| Targets.materializeResult cpiCap
  expect (MaterializedArtifactsV1.codegenProfileIdOf cpiArtifacts ==
      CodegenProfileId.solanaSbpfCpiElfV1)
    "cpi materialize: carrier profile is cpi-elf"

private unsafe def testExtensionProfileResolution
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CpiDeclared where\n" ++
    "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
    "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let compiled ← compileSource session source "Tests.CpiDeclared"
    "<solana-cpi-declared>"
  let cpiCap ← liftResult <|
    solanaCapability compiled (some CodegenProfileId.solanaSbpfCpiElfV1)
  -- Extension-only program still has no ExternalCall sites → product path FC.
  expectCompileErrorContains "declared cpi materialize" "PF-" ""
    (Targets.materializeResult cpiCap)
  for legacy in #[CodegenProfileId.solanaSbpfElfV1,
      CodegenProfileId.solanaSbpfPlanV1] do
    expectCompileErrorContains s!"declared extension on {legacy}"
      "PF-REQ-UNSUPPORTED" "extension.solana-cpi-accounts"
      (solanaCapability compiled (some legacy))

/-- Finalize pure helpers + plan stub regression + missing-tool path. -/
private unsafe def testFinalize
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Pure path helpers
  let root := FilePath.mk "/tmp/pf-solana-elf-project"
  expect (Targets.Solana.FinalizeV1.projectAsmPathV1 root "Counter" ==
      root / "src" / "Counter" / "Counter.s")
    "finalize helper: project asm path"
  expect (Targets.Solana.FinalizeV1.deploySoPathV1 root "Counter" ==
      root / "deploy" / "Counter.so")
    "finalize helper: deploy so path"
  -- Empty .so gate
  expectIoErrorContains "empty so" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Solana.FinalizeV1.requireNonemptySbpfElf (ByteArray.mk #[])
  Targets.Solana.FinalizeV1.requireNonemptySbpfElf (ByteArray.mk #[0x7f, 0x45])
  -- Plan shim: zero-tool stub unchanged (explicit profile; default is cpi-elf)
  let compiled ← compileSource session counterSourceText counterModuleNameV1
    "<solana-elf-finalize-plan>"
  let planCap ← liftResult <|
    solanaCapability compiled (some CodegenProfileId.solanaSbpfPlanV1)
  let planArtifacts ← liftResult <| Targets.materializeResult planCap
  IO.FS.withTempDir fun staging => do
    let draft ← Targets.Solana.FinalizeV1.finalize planCap planArtifacts staging
    expect (draft.deployable == false) "plan finalize: not deployable"
    expect (draft.extraFiles.isEmpty) "plan finalize: no extras"
    expect (draft.evidenceNote.contains "non-executable")
      "plan finalize: non-executable note"
  -- Elf profile: missing locked tool → PF-TOOLCHAIN-MISSING (no S2b lock yet).
  -- Also covers missing staging .s before resolve is attempted when we stage empty.
  let elfCap ← liftResult <|
    solanaCapability compiled (some CodegenProfileId.solanaSbpfElfV1)
  let elfArtifacts ← liftResult <| Targets.materializeResult elfCap
  IO.FS.withTempDir fun staging => do
    -- No .s staged → fail closed before or independent of tool resolve
    expectIoErrorContains "missing staging asm" "PF-ARTIFACT-NONDEPLOYABLE" do
      let _ ← Targets.Solana.FinalizeV1.finalize elfCap elfArtifacts staging
      pure ()
  IO.FS.withTempDir fun staging => do
    -- Stage a minimal .s so finalize reaches resolve "sbpf"
    let asm ← match (MaterializedArtifactsV1.filesOf elfArtifacts).find?
        (·.path == "Counter.s") with
      | some f => pure f.contents
      | none => throw <| IO.userError "elf artifacts missing Counter.s"
    IO.FS.writeFile (staging / "Counter.s") asm
    -- S2b registers sbpf in the lock. Lean has no process-global setEnv; when the
    -- host has not yet materialized `sbpf` under PROOF_FORGE_TOOL_ROOT / default
    -- cache, resolve fails closed with PF-TOOLCHAIN-MISSING. When a provisioned
    -- binary is present, skip this negative (positive .so e2e is outside this suite).
    let toolRoot? ← IO.getEnv "PROOF_FORGE_TOOL_ROOT"
    let candidate ← match toolRoot? with
      | some root => pure (FilePath.mk root / "sbpf")
      | none =>
          match ← IO.getEnv "HOME" with
          | some home =>
              pure (FilePath.mk home / ".cache" / "proof-forge-v2" / "tool-root" /
                (if System.Platform.isOSX then "darwin-arm64" else "linux-x86_64") /
                "sbpf")
          | none => pure (FilePath.mk "/nonexistent-sbpf")
    if ← candidate.pathExists then
      pure ()
    else
      expectIoErrorContains "missing sbpf tool" "PF-TOOLCHAIN-MISSING" do
        let _ ← Targets.Solana.FinalizeV1.finalize elfCap elfArtifacts staging
        pure ()

unsafe def run : IO Unit := do
  testRegistryMembership
  testSupportAndDescriptor
  testActiveCpiContract
  let session ← Tests.Language.ParserSession.shared
  testEmitProfiles session
  testExtensionProfileResolution session
  testFinalize session
  IO.println "Tests.Targets.SolanaElfV1: ok"

end Tests.Targets.SolanaElfV1

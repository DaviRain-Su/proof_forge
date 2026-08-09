import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.StateCell
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
# Tests.Targets.SolanaElfV1 — ADR-0032 U1 sole rail `solana-sbpf-cpi-elf-v1`

Pins:
* registry sole member + default is cpi-elf; plan/elf shims not members
* support row only for cpi-elf (sync + extensions; no async)
* residual descriptor binds cpi-elf only
* body-only StateCell product emit (`.s` / hybrid IR / plan / bindings / ELF finalize path)
* empty-.so gate; active CPI contract digests / package closure pins
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

/-- Registry: sole cpi-elf member; retired plan/elf fail selection. -/
private def testRegistryMembership : IO Unit := do
  let reg ← liftResult <| registration? TargetId.solana
  let reg ← match reg with
    | some r => pure r
    | none => throw <| IO.userError "solana registration missing"
  expect (reg.profiles == #[CodegenProfileId.solanaSbpfCpiElfV1])
    s!"registry: sole rail cpi-elf only, got {reg.profiles.map (·.toString)}"
  expect (reg.defaultProfile == some CodegenProfileId.solanaSbpfCpiElfV1)
    "registry: default is solana-sbpf-cpi-elf-v1"
  expect (!(ProofForgeV2.Targets.BuildSelectionV1.reservedFutureProfiles.contains
      "solana-sbpf-cpi-elf-v1"))
    "registry: cpi-elf is a registered product member"
  let defaultSel ← liftResult <| resolveBuildSelectionV1 TargetId.solana none
  expect (defaultSel.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1)
    "resolve: default selection is sole rail"
  let cpiSel ← liftResult <|
    resolveBuildSelectionV1 TargetId.solana (some CodegenProfileId.solanaSbpfCpiElfV1)
  expect (cpiSel.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1)
    "resolve: explicit cpi selection"
  -- Retired shims are not registry members.
  expectCompileErrorContains "retired elf shim" "PF-" ""
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfElfV1))
  expectCompileErrorContains "retired plan shim" "PF-" ""
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfPlanV1))

/-- Sole-rail support row + descriptor. -/
private def testSupportAndDescriptor : IO Unit := do
  let rows ← liftResult productSupportRowsV1
  let cpiRow ← match rows.find? (fun r =>
      r.targetId == TargetId.solana &&
        r.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1) with
    | some r => pure r
    | none => throw <| IO.userError "missing solana cpi support row"
  expect (rows.find? (fun r =>
      r.targetId == TargetId.solana &&
        r.codegenProfile == CodegenProfileId.solanaSbpfElfV1)).isNone
    "support: retired elf row must be absent"
  expect (rows.find? (fun r =>
      r.targetId == TargetId.solana &&
        r.codegenProfile == CodegenProfileId.solanaSbpfPlanV1)).isNone
    "support: retired plan row must be absent"
  let cpiIds := cpiRow.supported.map (·.id)
  expect (cpiIds.size == 8 &&
      cpiIds.contains "effect.synchronous-call" &&
      cpiIds.contains "extension.pf-assets" &&
      cpiIds.contains "extension.solana-cpi-accounts" &&
      !cpiIds.contains "effect.asynchronous-workflow")
    "support: sole rail admits sync+extensions and declines async"
  let expectedExtension ← match
      ProofForgeV2.Semantic.WireV1.solanaCpiAccountsExtensionRequirementV1 with
    | .ok row => pure row
    | .error error => throw <| IO.userError s!"extension row: {error}"
  expect (cpiRow.supported.filter (·.id == "extension.solana-cpi-accounts") ==
      #[expectedExtension])
    "support: exact solana-cpi-accounts row"
  let desc := Targets.Solana.descriptor
  expect (desc.codegenProfile == CodegenProfileId.solanaSbpfCpiElfV1)
    "descriptor: residual binds sole-rail cpi-elf"
  expect (acceptsCodegenProfile desc CodegenProfileId.solanaSbpfCpiElfV1)
    "descriptor: accepts cpi-elf"
  expect (!acceptsCodegenProfile desc CodegenProfileId.solanaSbpfPlanV1)
    "descriptor: rejects retired plan shim"
  expect (!acceptsCodegenProfile desc CodegenProfileId.solanaSbpfElfV1)
    "descriptor: rejects retired elf shim"
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

/-- Sole-rail body-only StateCell emit + materialize. -/
private unsafe def testEmitProfiles
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleNameV1
    "<solana-elf-emit>"
  let cpiCap ← liftResult <| solanaCapability compiled none
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf cpiCap ==
      CodegenProfileId.solanaSbpfCpiElfV1)
    "default capability is sole rail"
  match planFromCapability cpiCap with
  | .ok (.cpi plan) =>
      let cand := SolanaCpiProductPlanV1.candidateOf plan
      expect (cand.cpiSites.isEmpty) "cpi plan: body-only zero sites"
  | .ok (.legacy _) =>
      throw <| IO.userError "cpi plan: must not mint legacy Plan on sole rail"
  | .error error =>
      throw <| IO.userError s!"cpi plan: body-only must mint, got {error.render}"
  let cpiFiles ← liftResult <| buildFromCapability cpiCap
  let cpiPaths := cpiFiles.map (·.path)
  expect (cpiPaths.any (· == "StateCell.s")) "emit: .s"
  expect (cpiPaths.any (· == "StateCell.cpi-ir.json")) "emit: hybrid ir"
  expect (cpiPaths.any (· == "StateCell.cpi-plan.json")) "emit: plan"
  expect (cpiPaths.any (· == "StateCell.idl.json")) "emit: idl"
  expect (cpiPaths.any (· == "StateCell.cpi-bindings.json")) "emit: bindings"
  let asmFromFiles ← match cpiFiles.find? (·.path == "StateCell.s") with
    | some f => pure f.contents
    | none => throw <| IO.userError "emit: missing .s"
  expect (asmFromFiles.contains ".globl entrypoint") "asm: entrypoint export"
  expect (asmFromFiles.contains "entrypoint:") "asm: entrypoint label"
  let cpiArtifacts ← liftResult <| Targets.materializeResult cpiCap
  expect (MaterializedArtifactsV1.codegenProfileIdOf cpiArtifacts ==
      CodegenProfileId.solanaSbpfCpiElfV1)
    "materialize: carrier is cpi-elf"
  -- Retired shims cannot resolve capability.
  expectCompileErrorContains "retired plan capability" "PF-" ""
    (solanaCapability compiled (some CodegenProfileId.solanaSbpfPlanV1))
  expectCompileErrorContains "retired elf capability" "PF-" ""
    (solanaCapability compiled (some CodegenProfileId.solanaSbpfElfV1))

/-- Extension-only without ExternalCall still body-only mints (no sites). -/
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
  -- Extension without sync still fails product capability refine
  -- (solana.cpi.accounts alone without sync stays FC).
  expectCompileErrorContains "declared extension without sync" "PF-" ""
    (Targets.materializeResult cpiCap)

/-- Finalize helpers + sole-rail missing-staging path. -/
private unsafe def testFinalize
    (session : Language.Loader.ParserSession) : IO Unit := do
  let root := FilePath.mk "/tmp/pf-solana-elf-project"
  expect (Targets.Solana.FinalizeV1.projectAsmPathV1 root "StateCell" ==
      root / "src" / "StateCell" / "StateCell.s")
    "finalize helper: project asm path"
  expect (Targets.Solana.FinalizeV1.deploySoPathV1 root "StateCell" ==
      root / "deploy" / "StateCell.so")
    "finalize helper: deploy so path"
  expectIoErrorContains "empty so" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Solana.FinalizeV1.requireNonemptySbpfElf (ByteArray.mk #[])
  Targets.Solana.FinalizeV1.requireNonemptySbpfElf (ByteArray.mk #[0x7f, 0x45])
  let compiled ← compileSource session stateCellSourceText stateCellModuleNameV1
    "<solana-elf-finalize-cpi>"
  let cpiCap ← liftResult <| solanaCapability compiled none
  let cpiArtifacts ← liftResult <| Targets.materializeResult cpiCap
  IO.FS.withTempDir fun staging => do
    -- Empty staging: product finalize requires recomputed base files on disk.
    expectIoErrorContains "missing staging product base" "PF-ARTIFACT-NONDEPLOYABLE" do
      let _ ← Targets.Solana.FinalizeV1.finalize cpiCap cpiArtifacts staging
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

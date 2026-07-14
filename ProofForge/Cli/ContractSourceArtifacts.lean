import Lean.Util.Path
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Idl
import ProofForge.Backend.Solana.Materialize
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.WasmHost.ModulePlan.Core
import ProofForge.Backend.WasmHost.ModulePlan.Lower
import ProofForge.Cli.Artifact
import ProofForge.Cli.ArrayUtil
import ProofForge.Cli.ContractLoader
import ProofForge.Cli.EmitWatArtifacts
import ProofForge.Cli.EvmArtifacts
import ProofForge.Cli.FileUtil
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.Options
import ProofForge.Cli.SolanaArtifacts
import ProofForge.Cli.SolanaCommands
import ProofForge.Cli.TargetJson
import ProofForge.Cli.Usage
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Cli.TokenLoader
import ProofForge.Cli.NftLoader
import ProofForge.Contract.SdkSchema
import ProofForge.Contract.Spec
import ProofForge.Contract.Token.NearSpec
import ProofForge.Frontend.ContractSpec.Normalize
import ProofForge.IR
import ProofForge.Target
import ProofForge.Target.ArtifactBundle
import ProofForge.Target.Preflight

open System
open ProofForge.Cli.JsonUtil

namespace ProofForge.Cli

unsafe def loadContractSpecForOptions (opts : CliOptions) (input : FilePath)
    (targetId : String) : IO ProofForge.Contract.ContractSpec :=
  if opts.nft then
    ProofForge.Cli.NftLoader.loadAndMaterializeNft input opts.root? opts.moduleName? targetId
  else
    ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?

/-- Materialize a NEAR contract exclusively through canonical Core and the
existing semantic NearModulePlan. Failures are terminal; there is no Legacy
EmitWat fallback. -/
def renderCanonicalSpecNearWat (spec : ProofForge.Contract.ContractSpec)
    (peerMap : ProofForge.Target.PeerMap.Map := ProofForge.Target.PeerMap.identity) :
    Except String String := do
  let adaptedSpec := { spec with
    module := ProofForge.Target.PeerMap.applyToModule spec.module peerMap }
  let bundle ← ProofForge.Frontend.ContractSpec.normalize adaptedSpec
  let checked ← match ProofForge.IR.Canonical.validateCanonical bundle.contract.contract with
    | .ok checked => .ok checked
    | .error error => .error s!"canonical: validation failed: {repr error}"
  let targetPlan ← match ProofForge.Target.resolveSpec ProofForge.Target.wasmNear spec with
    | .ok plan => .ok plan
    | .error error => .error error.render
  let capabilityPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-near", calls := checked.contract.requirements,
    metadata := targetPlan.metadata }
  let plan ← match ProofForge.Backend.WasmHost.ModulePlan.Core.buildFromCore checked capabilityPlan with
    | .ok plan => .ok plan
    | .error error => .error s!"canonical: NEAR plan failed: {error.message}"
  let wasm ← match ProofForge.Backend.WasmHost.ModulePlan.lowerFromPlan plan with
    | .ok wasm => .ok wasm
    | .error error => .error s!"canonical: NEAR lowering failed: {error.message}"
  return ProofForge.Compiler.Wasm.Printer.render wasm

structure CanonicalAuthoredWasmHostBuild where
  checked : ProofForge.IR.Canonical.CheckedCanonicalContract
  capabilityPlan : ProofForge.Target.CapabilityPlan
  modulePlan : ProofForge.Backend.WasmHost.ModulePlan.WasmHostModulePlan
  wat : String

/-- Direct public-source route for Wasm-host targets. The exchange values are
AuthoredContract, checked Canonical Core, and the target-owned module plan.
There is no ContractSpec/IR.Module conversion and no Legacy fallback. -/
def renderAuthoredWasmHostWat
    (profile : ProofForge.Target.TargetProfile)
    (targetMetadata : Array ProofForge.Target.TargetMetadata)
    (contract : ProofForge.Frontend.Authored.AuthoredContract) :
    Except String CanonicalAuthoredWasmHostBuild := do
  let bundle ← match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored contract with
    | .ok bundle => .ok bundle
    | .error error => .error s!"canonical: Authored normalization failed: {repr error}"
  let checked := bundle.contract
  let hostErrors :=
    ProofForge.Compiler.checkHostOpHandlers profile.id checked ++
    ProofForge.Compiler.checkInterfaceOpHandlers profile.id checked
  unless hostErrors.isEmpty do
    throw s!"canonical: unhandled target operation: {String.intercalate "; " hostErrors.toList}"
  let capabilityPlan ← match ProofForge.Target.requireCapabilityPlan profile {
      targetId := profile.id
      calls := checked.contract.requirements
      metadata := targetMetadata
    } with
    | .ok plan => .ok plan
    | .error diagnostic => .error s!"canonical: capability plan failed: {diagnostic.render}"
  let modulePlan ←
    match ProofForge.Backend.WasmHost.ModulePlan.Core.buildFromCore checked capabilityPlan with
    | .ok plan => .ok plan
    | .error error => .error s!"canonical: Wasm-host plan failed: {error.message}"
  let wasm ← match ProofForge.Backend.WasmHost.ModulePlan.lowerFromPlan modulePlan with
    | .ok wasm => .ok wasm
    | .error error => .error s!"canonical: Wasm-host lowering failed: {error.message}"
  return {
    checked
    capabilityPlan
    modulePlan
    wat := ProofForge.Compiler.Wasm.Printer.render wasm
  }

unsafe def compileContractSourceEvmBytecode (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let output := opts.output?.getD (input.withExtension "bin")
  let yulOutput := opts.yulOutput?.getD (defaultBytecodeYulOutput output)
  if opts.nft then
    let spec ← loadContractSpecForOptions opts input "evm"
    let opts ← match finalizeConstructorOptionsForSpec opts spec with
      | .ok opts => pure opts
      | .error msg => throw <| IO.userError msg
    let (yul, module) ← renderContractSpecEvmYul opts spec
    writeTextFile yulOutput yul
    let bytecode ← solcBytecode opts.solc yulOutput
    writeTextFile output (bytecode ++ "\n")
    let hydratedSpec := { spec with module := module }
    writeEvmContractSdkArtifactMetadata opts (leanBaseName input) {
      moduleName := hydratedSpec.name
      path? := some input.toString
      kind := "contract-sdk"
      leanElaborated := true
    } hydratedSpec module yulOutput output
  else
    let (source, constructorConfig) ← loadEvmSource input opts.root? opts.moduleName?
    match source with
    | .authored contract =>
        let (yul, plan) ← renderAuthoredEvmYul opts contract constructorConfig
        let opts ← match finalizeConstructorOptionsForParams opts
            (plan.constructorParams.map fun param => {
              name := param.name, abiType := param.abiType }) with
          | .ok opts => pure opts
          | .error msg => throw <| IO.userError msg
        writeTextFile yulOutput yul
        let bytecode ← solcOptimizedBytecode opts.solc yulOutput
        requireEvmRuntimeSize bytecode
        writeTextFile output (bytecode ++ "\n")
        writeEvmPlanArtifactMetadata opts input plan yulOutput output
    | .surfaceFixture contract =>
        let (yul, plan) ← renderSurfaceEvmYul opts contract constructorConfig
        let opts ← match finalizeConstructorOptionsForParams opts
            (plan.constructorParams.map fun param => {
              name := param.name, abiType := param.abiType }) with
          | .ok opts => pure opts
          | .error msg => throw <| IO.userError msg
        writeTextFile yulOutput yul
        let bytecode ← solcOptimizedBytecode opts.solc yulOutput
        requireEvmRuntimeSize bytecode
        writeTextFile output (bytecode ++ "\n")
        writeEvmPlanArtifactMetadata opts input plan yulOutput output
  IO.println s!"wrote {output}"
  return 0

unsafe def compileContractSourceYul (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let output := opts.output?.getD (defaultYulOutput input)
  let yul ← if opts.nft then do
      let spec ← loadContractSpecForOptions opts input "evm"
      let opts ← match finalizeConstructorOptionsForSpec opts spec with
        | .ok opts => pure opts
        | .error msg => throw <| IO.userError msg
      pure (← renderContractSpecEvmYul opts spec).fst
    else do
      let (source, constructorConfig) ← loadEvmSource input opts.root? opts.moduleName?
      match source with
      | .authored contract =>
          pure (← renderAuthoredEvmYul opts contract constructorConfig).fst
      | .surfaceFixture contract =>
          pure (← renderSurfaceEvmYul opts contract constructorConfig).fst
  writeTextFile output yul
  IO.println s!"wrote {output}"
  return 0

unsafe def compileContractSourceSbpf (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let defaultOutput := siblingPath input s!".{leanBaseName input}.s"
  if !opts.nft then
    let source ← ProofForge.Cli.ContractLoader.loadSource input opts.root? opts.moduleName?
    match source with
    | .authored contract =>
        return ← compileSolanaAuthoredSbpf opts defaultOutput (leanBaseName input) contract
    | .surfaceFixture contract =>
        return ← compileSolanaAuthoredSbpf opts defaultOutput (leanBaseName input) contract
  let spec ← loadContractSpecForOptions opts input "solana-sbpf-asm"
  let output := opts.output?.getD defaultOutput
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match renderCanonicalSpecSolanaAsm spec with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let sourceArtifactEntry ← artifactEntryJson input
      let asmDigest ← fileDigestAndBytes output
      -- PF-P1-03 / PF-P0-03: assembly intermediate only; ELF not claimed.
      let sourceIdentity : ProofForge.Target.ArtifactBundle.SourceIdentity := {
        moduleName := spec.name
        path? := some input.toString
        kind := "contract-source"
        leanElaborated := true
      }
      let sourceToolchain ←
        ProofForge.Target.ArtifactBundle.sourceElaborationToolchain sourceIdentity opts.root?
      let bundle : ProofForge.Target.ArtifactBundle.ArtifactBundle := {
        targetId := ProofForge.Backend.Solana.SbpfAsm.targetId
        source := sourceIdentity
        outputs := #[{
          kind := "sbpf-asm"
          role := .intermediate
          path? := some output.toString
          sha256? := some asmDigest.fst
          bytes? := some asmDigest.snd
        }]
        primaryOutput? := some "sbpf-asm"
        finalOutput? := none
        toolchain := sourceToolchain ++ #[{
          tool := "sbpf", stage := "final-deployable", available := false
        }]
        validations := #[
          { name := "contractSourceLowering", state := .passed },
          { name := "sbpfBuild", state := .notRun, detail? := some "--format s: ELF link not requested" }
        ]
      }
      let _ ← match ProofForge.Target.ArtifactBundle.validateHonesty bundle with
        | .ok () => pure ()
        | .error err => throw <| IO.userError s!"Solana ArtifactBundle honesty: {err.message}"
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("standardId", match opts.nftStandardId? "solana-sbpf-asm" with
          | some standardId => jsonString standardId | none => "null"),
        ("targetFamily", jsonString "solana"),
        ("storageBinding", jsonString ProofForge.Target.solanaSbpfAsm.storageBinding.id),
        ("materialization",
          ProofForge.Target.Materialize.Report.json
            (ProofForge.Target.Materialize.forSolana spec.module
              (ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlan plan))),
        ("crosscallMaterialization",
          ProofForge.Target.CrosscallMaterialize.Report.json
            (ProofForge.Target.CrosscallMaterialize.forProfile ProofForge.Target.solanaSbpfAsm)),
        ("preflight",
          ProofForge.Target.Preflight.Report.json
            (ProofForge.Target.Preflight.run ProofForge.Target.solanaSbpfAsm spec.module)),
        ("solanaMaterialization",
          ProofForge.Backend.Solana.Materialize.reportJson
            (ProofForge.Backend.Solana.Materialize.report spec.module
              (ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlan plan))),
        -- Assembly intermediate only (PF-P0-03): do not claim solana-elf.
        ("artifactKind", jsonString "solana-sbpf-asm"),
        ("fixture", jsonString (leanBaseName input)),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("sdkSchema", jsonString "proof-forge-sdk.json"),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("source", sourceArtifactEntry),
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("artifactBundle", ProofForge.Target.ArtifactBundle.ArtifactBundle.toJson bundle),
        ("validation", jsonObject #[
          ("contractSourceLowering", jsonString "passed"),
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          -- Honest intermediate: ELF not requested/run (was misleading "skipped").
          ("sbpfBuild", jsonString "notRun")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      if opts.fromNewSurface then
        let schemaDir := output.parent.getD (FilePath.mk ".")
        discard <| writeSdkSchemaFile
          ProofForge.Backend.Solana.SbpfAsm.targetId
          spec
          schemaDir
          #[
            ("artifactMetadata", metadataOutput),
            ("primary", output),
            ("manifest", manifestOutput),
            ("interface", idlOutput)
          ]
          #[("typescript", clientOutput)]
      return 0
  | .error error =>
      throw <| IO.userError error

unsafe def compileContractSourceEmitWat (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  -- Resolve before loading the source so unknown, hidden `*-core`, and
  -- non-EmitWat profiles fail without elaboration or artifact side effects.
  let resolved ← match resolveEmitWatTarget opts with
    | .ok resolved => pure resolved
    | .error msg => throw <| IO.userError msg
  let profile := resolved.1
  let outputDir ← match opts.output? with
    | some out =>
        if out.extension == "wat" then
          pure <| match out.parent with | some parent => parent | none => FilePath.mk "."
        else
          pure out
    | none =>
        throw <| IO.userError "contract source EmitWat build requires -o output directory (or .wat path)"
  let opts' := { opts with
    output? := some outputDir
    targetId? := some profile.id
  }
  if opts.nft then
    let spec ← ProofForge.Cli.NftLoader.loadAndMaterializeNft input opts.root?
      opts.moduleName? profile.id
    let plan ← match ProofForge.Target.resolveSpec profile spec with
      | .ok plan => pure plan
      | .error err => throw <| IO.userError err.render
    if profile.id == ProofForge.Target.wasmNear.id then
      let wat ← match renderCanonicalSpecNearWat spec opts.peerMap with
        | .ok wat => pure wat
        | .error error => throw <| IO.userError error
      let (watPath, wasmPath?) ← writeWatPackage outputDir spec.name.toLower wat
        (requireWasm := emitWatRequireWasm opts')
      writeEmitWatArtifactMetadata opts' profile.id spec.name.toLower {
        moduleName := spec.name
        path? := some input.toString
        kind := "legacy-nft-source"
        leanElaborated := true
      } spec.module outputDir watPath wasmPath?
      return 0
    else
      return ← compileEmitWatWithPlan opts' spec.name.toLower spec.module plan {
        moduleName := spec.name
        path? := some input.toString
        kind := "legacy-nft-source"
        leanElaborated := true
      }
  let source ← ProofForge.Cli.ContractLoader.loadSource input opts.root? opts.moduleName?
  let (contract, sourceKind) := match source with
    | .authored contract => (contract, "contract-source-authored")
    | .surfaceFixture contract => (contract, "internal-surface-fixture")
  let built ← match renderAuthoredWasmHostWat profile opts.peerMap.targetMetadata contract with
    | .ok built => pure built
    | .error error => throw <| IO.userError error
  let fixtureSlug := built.modulePlan.moduleName.toLower
  let (watPath, wasmPath?) ← writeWatPackage outputDir fixtureSlug built.wat
    (requireWasm := emitWatRequireWasm opts')
  writeCanonicalEmitWatArtifactMetadata opts' profile.id fixtureSlug {
    moduleName := built.modulePlan.moduleName
    path? := some input.toString
    kind := sourceKind
    leanElaborated := true
  } built.checked built.capabilityPlan built.modulePlan outputDir watPath wasmPath?
  return 0

end ProofForge.Cli

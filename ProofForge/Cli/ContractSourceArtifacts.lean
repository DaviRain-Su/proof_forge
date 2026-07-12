import Lean.Util.Path
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Idl
import ProofForge.Backend.Solana.Materialize
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Cli.Artifact
import ProofForge.Cli.ArrayUtil
import ProofForge.Cli.ContractLoader
import ProofForge.Cli.EmitWatArtifacts
import ProofForge.Cli.EvmArtifacts
import ProofForge.Cli.FileUtil
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.Options
import ProofForge.Cli.SolanaArtifacts
import ProofForge.Cli.TargetJson
import ProofForge.Cli.Usage
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Cli.TokenLoader
import ProofForge.Cli.NftLoader
import ProofForge.Contract.SdkSchema
import ProofForge.Contract.Spec
import ProofForge.Contract.Token.NearSpec
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
  let bundle ← match ProofForge.IR.Legacy.Adapter.adaptLegacy adaptedSpec with
    | .ok bundle => .ok bundle
    | .error error => .error s!"canonical: adapt failed: {repr error}"
  let checked ← match ProofForge.IR.Canonical.validateCanonical bundle.contract.contract with
    | .ok checked => .ok checked
    | .error error => .error s!"canonical: validation failed: {repr error}"
  let targetPlan ← match ProofForge.Target.resolveSpec ProofForge.Target.wasmNear spec with
    | .ok plan => .ok plan
    | .error error => .error error.render
  let capabilityPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-near", calls := checked.contract.requirements,
    metadata := targetPlan.metadata }
  let plan ← match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore checked capabilityPlan with
    | .ok plan => .ok plan
    | .error error => .error s!"canonical: NEAR plan failed: {error.message}"
  let wasm ← match ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan plan with
    | .ok wasm => .ok wasm
    | .error error => .error s!"canonical: NEAR lowering failed: {error.message}"
  return ProofForge.Compiler.Wasm.Printer.render wasm

unsafe def compileContractSourceEvmBytecode (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← loadContractSpecForOptions opts input "evm"
  let opts ← match finalizeConstructorOptionsForSpec opts spec with
    | .ok opts => pure opts
    | .error msg => throw <| IO.userError msg
  let output := opts.output?.getD (input.withExtension "bin")
  let yulOutput := opts.yulOutput?.getD (defaultBytecodeYulOutput output)
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
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

unsafe def compileContractSourceYul (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← loadContractSpecForOptions opts input "evm"
  let opts ← match finalizeConstructorOptionsForSpec opts spec with
    | .ok opts => pure opts
    | .error msg => throw <| IO.userError msg
  let output := opts.output?.getD (defaultYulOutput input)
  let (yul, _module) ← renderContractSpecEvmYul opts spec
  writeTextFile output yul
  IO.println s!"wrote {output}"
  return 0

unsafe def compileContractSourceSbpf (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← loadContractSpecForOptions opts input "solana-sbpf-asm"
  let output := opts.output?.getD (siblingPath input s!".{leanBaseName input}.s")
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

/-- Try loading a `ContractSpec` first; if that fails and the source defines a
    `TokenSpec`, materialize a target-appropriate `ContractSpec` from it.

    This lets authors run `proof-forge build --target wasm-near Token.lean`
    without `--token` when the source is a `TokenSpec` (P0-NEAR-1). -/
unsafe def tryLoadSpecOrTokenSpec
    (input : System.FilePath) (root? : Option System.FilePath)
    (moduleName? : Option Lean.Name) (targetId : String) :
    IO (Except String ProofForge.Contract.ContractSpec) := do
  try
    let spec ← ProofForge.Cli.ContractLoader.loadSpec input root? moduleName?
    pure (.ok spec)
  catch _ =>
    try
      let (_, tokenSpec) ← ProofForge.Cli.TokenLoader.loadToken input root? moduleName?
      if targetId == ProofForge.Target.wasmNear.id then
        pure (.ok (ProofForge.Contract.Token.NearSpec.specFor tokenSpec))
      else
        pure (.error s!"source defines a TokenSpec but target `{targetId}` has no TokenSpec auto-detect lane; use `--token`")
    catch err =>
      pure (.error s!"{err}")

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
  let spec ← if opts.nft then
      ProofForge.Cli.NftLoader.loadAndMaterializeNft input opts.root? opts.moduleName? profile.id
    else
      match (← tryLoadSpecOrTokenSpec input opts.root? opts.moduleName? profile.id) with
      | .ok spec => pure spec
      | .error err => throw <| IO.userError err
  let fixtureSlug := spec.name.toLower
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
  let plan ←
    match ProofForge.Target.resolveSpec profile spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  if profile.id == "wasm-near" then
    let wat ← match renderCanonicalSpecNearWat spec opts.peerMap with
      | .ok wat => pure wat
      | .error error => throw <| IO.userError error
    let (watPath, wasmPath?) ← writeWatPackage outputDir fixtureSlug wat
      (requireWasm := emitWatRequireWasm opts')
    writeEmitWatArtifactMetadata opts' profile.id fixtureSlug {
      moduleName := spec.name
      path? := some input.toString
      kind := "contract-sdk"
      leanElaborated := true
    } spec.module outputDir watPath wasmPath?
    return 0
  else
    compileEmitWatWithPlan opts' fixtureSlug spec.module plan {
      moduleName := spec.name
      path? := some input.toString
      kind := "contract-sdk"
      leanElaborated := true
    }

end ProofForge.Cli

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
import ProofForge.Contract.SdkSchema
import ProofForge.Contract.Spec
import ProofForge.IR
import ProofForge.Target
import ProofForge.Target.ArtifactBundle
import ProofForge.Target.Preflight

open System
open ProofForge.Cli.JsonUtil

namespace ProofForge.Cli

unsafe def compileContractSourceEvmBytecode (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let opts ← match finalizeConstructorOptionsForSpec opts spec with
    | .ok opts => pure opts
    | .error msg => throw <| IO.userError msg
  let output := opts.output?.getD (input.withExtension "bin")
  let yulOutput := opts.yulOutput?.getD (defaultBytecodeYulOutput output)
  let (yul, module) ← renderContractSpecEvmYul opts spec
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  writeTextFile output (bytecode ++ "\n")
  writeEvmContractSdkArtifactMetadata opts (leanBaseName input) {
    moduleName := spec.name
    path? := some input.toString
    kind := "contract-sdk"
    leanElaborated := true
  } spec module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

unsafe def compileContractSourceYul (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
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
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let output := opts.output?.getD (siblingPath input s!".{leanBaseName input}.s")
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
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
  | .error err =>
      throw <| IO.userError err.render

unsafe def compileContractSourceEmitWat (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let fixtureSlug := spec.name.toLower
  let outputDir ← match opts.output? with
    | some out =>
        if out.extension == "wat" then
          pure <| match out.parent with | some parent => parent | none => FilePath.mk "."
        else
          pure out
    | none =>
        throw <| IO.userError "contract source EmitWat build requires -o output directory (or .wat path)"
  -- PF-P0-04: resolve the requested Wasm-host profile (NEAR vs Soroban), never alias to NEAR.
  let targetId := opts.targetId?.getD ProofForge.Target.wasmNear.id
  let profile ←
    match ProofForge.Target.find? targetId with
    | some profile => pure profile
    | none =>
        throw <| IO.userError
          s!"unknown EmitWat target '{targetId}'; known targets: {String.intercalate ", " ProofForge.Target.knownIds.toList}"
  let opts' := { opts with
    output? := some outputDir
    targetId? := some profile.id
  }
  let plan ←
    match ProofForge.Target.resolveSpec profile spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  compileEmitWatWithPlan opts' fixtureSlug spec.module plan {
    moduleName := spec.name
    path? := some input.toString
    kind := "contract-sdk"
    leanElaborated := true
  }

end ProofForge.Cli

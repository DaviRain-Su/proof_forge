import Lean.Util.Path
import ProofForge.Backend.Solana.Idl
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
  writeEvmContractSdkArtifactMetadata opts (leanBaseName input) spec.name spec module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

unsafe def compileContractSourceYul (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
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
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
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
        ("validation", jsonObject #[
          ("contractSourceLowering", jsonString "passed"),
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending")
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
  let opts' := { opts with
    output? := some outputDir
    targetId? := opts.targetId? <|> some ProofForge.Target.wasmNear.id
  }
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.wasmNear spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  compileEmitWatWithPlan opts' fixtureSlug spec.module plan

end ProofForge.Cli

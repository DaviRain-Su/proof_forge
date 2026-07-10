import Lean.Util.Path
import ProofForge.Backend.WasmHost
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Cli.Artifact
import ProofForge.Cli.FileUtil
import ProofForge.Cli.IrJson
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.Options
import ProofForge.Contract.Client
import ProofForge.Contract.SdkSchema
import ProofForge.Contract.Spec.Json
import ProofForge.IR
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ContextProbe
import ProofForge.IR.Examples.ErrorRefProbe
import ProofForge.IR.Examples.HashProbe
import ProofForge.IR.Examples.MapProbe
import ProofForge.Target
import ProofForge.Target.ArtifactBundle
import ProofForge.Target.PeerMap
import ProofForge.Target.Preflight

open System
open ProofForge.Cli.JsonUtil

namespace ProofForge.Cli

def writeNearPackage (outputDir : FilePath) (pkg : ProofForge.Backend.WasmHost.IR.NearPackage) : IO Unit := do
  for file in pkg.files do
    let path := outputDir / file.path
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile path file.content

/-! ### EmitWat output (canonical IR → WAT → wasm) -/

def emitWatEntrypointJson (entrypoint : ProofForge.IR.Entrypoint) : String :=
  jsonObject #[
    ("name", jsonString entrypoint.name),
    ("params", jsonArray (entrypoint.params.map fun param =>
      jsonObject #[
        ("name", jsonString param.fst),
        ("type", valueTypeJson param.snd)
      ])),
    ("returns", valueTypeJson entrypoint.returns)
  ]

def defaultEmitWatArtifactOutput (outputDir : FilePath) : FilePath :=
  outputDir / "proof-forge-artifact.json"

def emitWatTargetId (opts : CliOptions) : String :=
  opts.targetId?.getD ProofForge.Target.wasmNear.id

def emitWatDeployManifestKind (targetId : String) : String :=
  if targetId == ProofForge.Target.wasmNear.id then
    "proof-forge-wasm-near-deploy-manifest"
  else
    "proof-forge-wasm-host-deploy-manifest"

def optionalExistingArtifactEntryJson (path? : Option FilePath) : IO (Option String) := do
  match path? with
  | none => return none
  | some path =>
      if ← path.pathExists then
        return some (← artifactEntryJson path)
      else
        return none

def optionalExistingArtifactEntryJsonRelativeTo
    (baseDir : FilePath)
    (path? : Option FilePath) : IO (Option String) := do
  match path? with
  | none => return none
  | some path =>
      if ← path.pathExists then
        return some (← artifactEntryJsonRelativeTo baseDir path)
      else
        return none

def writeEmitWatDeployManifest
    (deployOutput : FilePath)
    (targetId fixture sourceKind : String)
    (module : ProofForge.IR.Module)
    (watArtifact : String)
    (wasmArtifact? : Option String) : IO Unit := do
  let mut artifactFields : Array (String × String) := #[("wat", watArtifact)]
  if let some wasmArtifact := wasmArtifact? then
    artifactFields := artifactFields.push ("wasm", wasmArtifact)
  let manifest := jsonObject #[
    ("schemaVersion", "1"),
    ("kind", jsonString (emitWatDeployManifestKind targetId)),
    ("target", jsonString targetId),
    ("targetFamily", jsonString "wasmHost"),
    ("storageBinding", jsonString (match ProofForge.Target.storageBindingForTargetId? targetId with
      | some binding => binding.id
      | none => "unknown")),
    ("materialization",
      match ProofForge.Target.find? targetId with
      | some profile =>
          match ProofForge.Target.Materialize.forImplementedProfile profile module with
          | some report => ProofForge.Target.Materialize.Report.json report
          | none => ProofForge.Target.Materialize.Report.json
              (ProofForge.Target.Materialize.forWasmNear module)
      | none => ProofForge.Target.Materialize.Report.json
          (ProofForge.Target.Materialize.forWasmNear module)),
    ("crosscallMaterialization",
      match ProofForge.Target.find? targetId with
      | some profile =>
          ProofForge.Target.CrosscallMaterialize.Report.json
            (ProofForge.Target.CrosscallMaterialize.forProfile profile)
      | none =>
          ProofForge.Target.CrosscallMaterialize.Report.json
            (ProofForge.Target.CrosscallMaterialize.forProfile ProofForge.Target.wasmNear)),
    ("artifactKind", jsonString "wasm-deploy"),
    ("fixture", jsonString fixture),
    ("sourceKind", jsonString sourceKind),
    ("irVersion", if sourceKind == "portable-ir" then jsonString "portable-ir-v0" else "null"),
    ("sourceModule", jsonString module.name),
    ("capabilities", jsonStringArray (moduleCapabilityIds module)),
    ("abi", jsonObject #[
      ("entrypoints", jsonArray (module.entrypoints.map emitWatEntrypointJson))
    ]),
    ("artifacts", jsonObject artifactFields),
    ("deployment", jsonObject #[
      ("mode", jsonString "local-offline-host"),
      ("status", jsonString "not-broadcast"),
      ("localExecutor", jsonString "runtime/offline-host"),
      ("nearAccountId", if targetId == ProofForge.Target.wasmNear.id then "null" else "null"),
      ("nearSandbox", if targetId == ProofForge.Target.wasmNear.id then jsonString "not-generated" else "null"),
      ("note", jsonString (
        if targetId == ProofForge.Target.wasmStellarSoroban.id then
          "EmitWat Soroban Spike output is locally executable through runtime/offline-host; Stellar account deployment / contract-spec publish is not generated by this manifest."
        else
          "EmitWat target-first output is locally executable through runtime/offline-host; NEAR account deployment is not generated by this manifest."))
    ])
  ]
  if let some parent := deployOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile deployOutput (manifest ++ "\n")

/-- PF-P1-03: build an honest ArtifactBundle for EmitWat outputs. -/
def emitWatArtifactBundle
    (targetId : String) (module : ProofForge.IR.Module)
    (watPath : FilePath) (wasmPath? : Option FilePath)
    (watSha? wasmSha? : Option String)
    (watBytes? wasmBytes? : Option Nat) :
    ProofForge.Target.ArtifactBundle.ArtifactBundle :=
  open ProofForge.Target.ArtifactBundle in
  let source : SourceIdentity := {
    moduleName := module.name
    path? := none
    kind := "portable-ir"
  }
  let watOut : TypedOutput := {
    kind := "wat"
    role := .intermediate
    path? := some watPath.toString
    sha256? := watSha?
    bytes? := watBytes?
  }
  match wasmPath? with
  | some wasmPath =>
      let wasmOut : TypedOutput := {
        kind := "wasm"
        role := .finalDeployable
        path? := some wasmPath.toString
        sha256? := wasmSha?
        bytes? := wasmBytes?
      }
      {
        targetId := targetId
        source := source
        outputs := #[watOut, wasmOut]
        primaryOutput? := some "wasm"
        finalOutput? := some "wasm"
        toolchain := #[{ tool := "wat2wasm", stage := "final-deployable", available := true }]
        validations := #[{ name := "wat2wasm", state := .passed }]
      }
  | none =>
      {
        targetId := targetId
        source := source
        outputs := #[watOut]
        primaryOutput? := some "wat"
        finalOutput? := none
        toolchain := #[{ tool := "wat2wasm", stage := "final-deployable", available := false }]
        validations := #[{
          name := "wat2wasm"
          state := .unavailable
          detail? := some "final Wasm not produced; wat2wasm missing or skipped"
        }]
      }

def writeEmitWatArtifactMetadata
    (opts : CliOptions)
    (targetId fixture sourceKind : String)
    (module : ProofForge.IR.Module)
    (outputDir watPath : FilePath)
    (wasmPath? : Option FilePath) : IO Unit := do
  let metadataOutput := opts.artifactOutput?.getD (defaultEmitWatArtifactOutput outputDir)
  let schemaDir := metadataOutput.parent.getD outputDir
  let deployOutput := defaultDeployManifestOutput metadataOutput
  let watArtifact ← artifactEntryJsonRelativeTo schemaDir watPath
  let wasmArtifact? ← optionalExistingArtifactEntryJsonRelativeTo schemaDir wasmPath?
  let watDigest ← fileDigestAndBytes watPath
  let wasmDigest? ← match wasmPath? with
    | some p =>
        if ← p.pathExists then
          pure (some (← fileDigestAndBytes p))
        else
          pure none
    | none => pure none
  let bundle := emitWatArtifactBundle targetId module watPath
    (if wasmDigest?.isSome then wasmPath? else none)
    (some watDigest.fst)
    (wasmDigest?.map (·.fst))
    (some watDigest.snd)
    (wasmDigest?.map (·.snd))
  let _ ← match ProofForge.Target.ArtifactBundle.validateHonesty bundle with
    | .ok () => pure ()
    | .error err => throw <| IO.userError s!"EmitWat ArtifactBundle honesty: {err.message}"
  let spec := ProofForge.Contract.ContractSpec.fromIR module
  let (contractSpecOutput, nearClientOutput, unifiedClientOutput) ←
    if opts.fromNewSurface then
      writeWasmHostContractSidecars targetId outputDir spec
    else if targetId == ProofForge.Target.wasmStellarSoroban.id then
      pure (outputDir / s!"{spec.name}.contract-spec.json",
        outputDir / ProofForge.Contract.Client.sorobanWrapperPath,
        outputDir / "proof-forge-client.ts")
    else
      pure (outputDir / s!"{spec.name}.contract-spec.json",
        outputDir / ProofForge.Contract.Client.nearWrapperPath,
        outputDir / "proof-forge-client.ts")
  writeEmitWatDeployManifest deployOutput targetId fixture sourceKind module watArtifact wasmArtifact?
  let deployArtifact ← artifactEntryJsonRelativeTo schemaDir deployOutput
  let mut artifactFields : Array (String × String) := #[
    ("wat", watArtifact),
    ("deployManifest", deployArtifact)
  ]
  if let some wasmArtifact := wasmArtifact? then
    artifactFields := artifactFields.push ("wasm", wasmArtifact)
  -- PF-P1-03: never claim wat2wasm `passed` when Wasm is absent.
  let wat2wasmStatus :=
    match ProofForge.Target.ArtifactBundle.validationState? bundle "wat2wasm" with
    | some .passed => "passed"
    | some .failed => "failed"
    | some .unavailable => "unavailable"
    | some .notRun => "notRun"
    | none => "notRun"
  let materializationJson :=
    match ProofForge.Target.find? targetId with
    | some profile =>
        match ProofForge.Target.Materialize.forImplementedProfile profile module with
        | some report => ProofForge.Target.Materialize.Report.json report
        | none => ProofForge.Target.Materialize.Report.json
            (ProofForge.Target.Materialize.forWasmNear module)
    | none => ProofForge.Target.Materialize.Report.json
        (ProofForge.Target.Materialize.forWasmNear module)
  let crosscallJson :=
    match ProofForge.Target.find? targetId with
    | some profile =>
        ProofForge.Target.CrosscallMaterialize.Report.json
          (ProofForge.Target.CrosscallMaterialize.forProfile profile)
    | none =>
        ProofForge.Target.CrosscallMaterialize.Report.json
          (ProofForge.Target.CrosscallMaterialize.forProfile ProofForge.Target.wasmNear)
  let metadata := jsonObject #[
    ("schemaVersion", "1"),
    ("target", jsonString targetId),
    ("targetFamily", jsonString "wasmHost"),
    ("storageBinding", jsonString (match ProofForge.Target.storageBindingForTargetId? targetId with
      | some binding => binding.id
      | none => "unknown")),
    ("materialization", materializationJson),
    ("crosscallMaterialization", crosscallJson),
    ("preflight",
      match ProofForge.Target.find? targetId with
      | some profile =>
          ProofForge.Target.Preflight.Report.json
            (ProofForge.Target.Preflight.run profile module)
      | none =>
          ProofForge.Target.Preflight.Report.json
            (ProofForge.Target.Preflight.run ProofForge.Target.wasmNear module)),
    ("artifactKind", jsonString (if wasmArtifact?.isSome then "wasm" else "wat")),
    ("fixture", jsonString fixture),
    ("sourceKind", jsonString sourceKind),
    ("irVersion", if sourceKind == "portable-ir" then jsonString "portable-ir-v0" else "null"),
    ("sourceModule", jsonString module.name),
    ("sdkSchema", jsonString "proof-forge-sdk.json"),
    ("capabilities", jsonStringArray (moduleCapabilityIds module)),
    ("toolchain", jsonObject #[
      ("wat2wasm", jsonObject #[
        ("path", jsonString "wat2wasm"),
        ("version", "null")
      ])
    ]),
    ("abi", jsonObject #[
      ("entrypoints", jsonArray (module.entrypoints.map emitWatEntrypointJson))
    ]),
    ("artifacts", jsonObject artifactFields),
    ("artifactBundle", ProofForge.Target.ArtifactBundle.ArtifactBundle.toJson bundle),
    ("validation", jsonObject #[
      ("emitWat", jsonString "passed"),
      ("watGeneration", jsonString "passed"),
      ("wat2wasm", jsonString wat2wasmStatus),
      ("deployManifest", jsonString "passed"),
      ("offlineHost", jsonString "pending")
    ])
  ]
  if let some parent := metadataOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile metadataOutput (metadata ++ "\n")
  IO.println s!"wrote {metadataOutput}"
  if opts.fromNewSurface then
    let mut artifactPaths : Array (String × FilePath) := #[
      ("artifactMetadata", metadataOutput),
      ("primary", watPath),
      ("deployManifest", deployOutput),
      ("contractSpec", contractSpecOutput)
    ]
    if let some wasmPath := wasmPath? then
      if ← wasmPath.pathExists then
        artifactPaths := artifactPaths.push ("secondary", wasmPath)
    let watRel := (relativePathFromDir? schemaDir watPath).getD watPath.toString
    let deployRel := (relativePathFromDir? schemaDir deployOutput).getD deployOutput.toString
    let contractSpecRel := (relativePathFromDir? schemaDir contractSpecOutput).getD contractSpecOutput.toString
    let nearClientRel := (relativePathFromDir? schemaDir nearClientOutput).getD nearClientOutput.toString
    let wasmRel? := wasmPath?.bind (fun path => relativePathFromDir? schemaDir path)
    let viewMethods := module.entrypoints.filter (fun entrypoint => entrypoint.returns != .unit) |>.map (fun entrypoint => entrypoint.name)
    let callMethods := module.entrypoints.filter (fun entrypoint => entrypoint.returns == .unit) |>.map (fun entrypoint => entrypoint.name)
    let mut nearFields : Array ProofForge.Contract.SdkSchema.JsonField := #[
      ("wat", ProofForge.Contract.SdkSchema.Json.string watRel),
      ("deployManifest", ProofForge.Contract.SdkSchema.Json.string deployRel),
      ("contractSpec", ProofForge.Contract.SdkSchema.Json.string contractSpecRel),
      ("typescriptWrapper", ProofForge.Contract.SdkSchema.Json.string nearClientRel),
      ("offlineHost", ProofForge.Contract.SdkSchema.Json.string "runtime/offline-host"),
      ("wrapperBehavior", ProofForge.Contract.SdkSchema.Json.object #[
        ("viewMethods", ProofForge.Contract.SdkSchema.Json.stringArray viewMethods),
        ("callMethods", ProofForge.Contract.SdkSchema.Json.stringArray callMethods)
      ]),
      ("callOptions", ProofForge.Contract.SdkSchema.Json.object #[
        ("gas", ProofForge.Contract.SdkSchema.Json.string "optional"),
        ("deposit", ProofForge.Contract.SdkSchema.Json.string "optional")
      ])
    ]
    if let some wasmRel := wasmRel? then
      nearFields := nearFields.push ("wasm", ProofForge.Contract.SdkSchema.Json.string wasmRel)
    let extKey :=
      if targetId == "wasm-stellar-soroban" then "soroban" else "near"
    let nearExtension : ProofForge.Contract.SdkSchema.TargetExtension := {
      key := extKey
      targetId := targetId
      fields := nearFields
    }
    discard <| writeSdkSchemaFile targetId spec schemaDir artifactPaths #[
      ("typescript", unifiedClientOutput),
      ("nativeWrapper", nearClientOutput)
    ] (some nearExtension)

/-- Write WAT and optionally convert to Wasm.
`requireWasm = true` (default final build): wat2wasm failure/missing is fatal (PF-P0-08).
`requireWasm = false` (`--format wat` intermediate): WAT-only success is allowed. -/
def writeWatPackage (outputDir : FilePath) (name : String) (wat : String)
    (requireWasm : Bool := true) : IO (FilePath × Option FilePath) := do
  IO.FS.createDirAll outputDir
  let watPath := outputDir / s!"{name}.wat"
  IO.FS.writeFile watPath wat
  let wasmPath := outputDir / s!"{name}.wasm"
  try
    let r ← IO.Process.output { cmd := "wat2wasm", args := #[watPath.toString, "-o", wasmPath.toString] }
    if r.exitCode == 0 then
      IO.println s!"wrote EmitWat {name}.wat + {name}.wasm to {outputDir}"
      return (watPath, some wasmPath)
    else
      let msg := s!"wat2wasm exit {r.exitCode}: {r.stderr.trimAscii} (WAT at {watPath})"
      if requireWasm then
        throw <| IO.userError
          s!"final Wasm build requires wat2wasm success: {msg}; use --format wat for WAT-only intermediate"
      else
        IO.eprintln msg
        return (watPath, none)
  catch e =>
    if requireWasm then
      throw <| IO.userError
        s!"final Wasm build requires wat2wasm on PATH (failed: {e.toString}); install wabt or use --format wat"
    else
      IO.println s!"wrote EmitWat {name}.wat to {watPath} (wat2wasm unavailable; install wabt to build wasm)"
      return (watPath, none)

/-- Deploy peer map is **explicit** via CLI (`--peer` / `--peers-demo`).
Default is identity: logical ids stay as declared in Shared. -/
def emitWatPeerMap (opts : CliOptions) : ProofForge.Target.PeerMap.Map :=
  opts.peerMap

/-- Host bridge for EmitWat from `--target` (Soroban vs NEAR vs CosmWasm). -/
def emitWatBridge (opts : CliOptions) : ProofForge.Target.HostBridge :=
  match opts.targetId? with
  | some "wasm-stellar-soroban" => ProofForge.Target.HostBridge.soroban
  | some id =>
      if id == ProofForge.Target.wasmCosmWasm.id then
        ProofForge.Target.HostBridge.cosmWasm
      else
        ProofForge.Target.HostBridge.near
  | none => ProofForge.Target.HostBridge.near

def emitWatRequireWasm (opts : CliOptions) : Bool :=
  -- PF-P0-08: explicit --format wat is the WAT intermediate; default final build needs Wasm.
  !(opts.format? == some "wat")

def compileEmitWat (opts : CliOptions) (name : String) (mod : ProofForge.IR.Module) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "emitwat mode requires -o output directory"
  let bridge := emitWatBridge opts
  let peerMap := emitWatPeerMap opts
  -- Unified entry: WasmHost.EmitWat routes near / soroban / cosmWasm.
  match ProofForge.Backend.WasmHost.EmitWat.renderModule mod bridge peerMap with
  | .ok wat =>
      let (watPath, wasmPath?) ← writeWatPackage output name wat (requireWasm := emitWatRequireWasm opts)
      writeEmitWatArtifactMetadata opts (emitWatTargetId opts) name "portable-ir" mod output watPath wasmPath?
      return 0
  | .error e =>
      throw <| IO.userError e.message

def compileEmitWatWithPlan
    (opts : CliOptions)
    (name : String)
    (mod : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "emitwat mode requires -o output directory"
  let bridge := emitWatBridge opts
  let peerMap := emitWatPeerMap opts
  match ProofForge.Backend.WasmHost.EmitWat.renderModuleWithPlan mod plan bridge peerMap with
  | .ok wat =>
      let (watPath, wasmPath?) ← writeWatPackage output name wat (requireWasm := emitWatRequireWasm opts)
      writeEmitWatArtifactMetadata opts (emitWatTargetId opts) name "contract-sdk" mod
        output watPath wasmPath?
      return 0
  | .error err =>
      throw <| IO.userError err.message

def compileCounterEmitWat (opts : CliOptions) : IO UInt32 := compileEmitWat opts "counter" ProofForge.IR.Examples.Counter.module
def compileErrorRefEmitWat (opts : CliOptions) : IO UInt32 := compileEmitWat opts "error-ref" ProofForge.IR.Examples.ErrorRefProbe.module
def compileContextEmitWat  (opts : CliOptions) : IO UInt32 := compileEmitWat opts "context" ProofForge.IR.Examples.ContextProbe.module
def compileHashEmitWat     (opts : CliOptions) : IO UInt32 := compileEmitWat opts "hash" ProofForge.IR.Examples.HashProbe.module
def compileMapEmitWat      (opts : CliOptions) : IO UInt32 := compileEmitWat opts "map" ProofForge.IR.Examples.MapProbe.emitWatModule

end ProofForge.Cli

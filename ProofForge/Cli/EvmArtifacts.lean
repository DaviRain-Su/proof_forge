import Lean.Util.Path
import ProofForge.Backend.Evm.ConstructorInit
import ProofForge.Backend.Evm.Plan
import ProofForge.Cli.Artifact
import ProofForge.Cli.ArrayUtil
import ProofForge.Cli.ConstructorAbi
import ProofForge.Cli.Evm
import ProofForge.Cli.EvmAbi
import ProofForge.Cli.HexUtil
import ProofForge.Cli.IrJson
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.Options
import ProofForge.Cli.Process
import ProofForge.Contract.Client
import ProofForge.Contract.SdkSchema
import ProofForge.Contract.Spec.Json
import ProofForge.IR
import ProofForge.Target

open ProofForge.Cli.ConstructorAbi
open ProofForge.Cli.HexUtil
open ProofForge.Cli.JsonUtil
open System

namespace ProofForge.Cli

def renderContractSpecEvmYul (opts : CliOptions) (spec : ProofForge.Contract.ContractSpec) :
    IO (String × ProofForge.IR.Module) := do
  let module ← hydrateEvmSelectors opts.cast spec.module
  match ProofForge.Cli.Evm.renderYul module with
  | .ok yul => return (yul, module)
  | .error err => throw <| IO.userError err.render

def solcVersion? (solc : String) : IO (Option String) := do
  try
    let stdout ← runProcess solc #["--version"]
    for line in stdout.splitOn "\n" do
      let line := trimAsciiString line
      if line.startsWith "Version: " then
        return some (line.splitOn "Version: ")[1]!
    return none
  catch _ =>
    return none

/-- Parse `solc --version` output (e.g. "0.8.34+commit.80d5c536.Darwin.appleclang") into (major, minor, patch). -/
def parseSolcVersion (versionStr : String) : Option (Nat × Nat × Nat) :=
  match versionStr.splitOn "+" with
  | head :: _ =>
    match head.splitOn "." with
    | [maj, min, pat] =>
      match (maj.toNat?, min.toNat?, pat.toNat?) with
      | (some m, some n, some p) => some (m, n, p)
      | _ => none
    | _ => none
  | _ => none

/-- Construct the CBOR metadata tail appended to EVM bytecode.
    Format: `a1` (map 1) `64 73 6f 6c 63` (text "solc") `43 <major> <minor> <patch>` (bytes 3)
    followed by a 2-byte big-endian length of the CBOR portion. -/
def metadataCborTail (major minor patch : Nat) : String :=
  let cborLen := 10
  let hexByte (n : Nat) : String :=
    let h := Nat.toDigits 16 n
    match h with
    | [d] => "0" ++ d.toString
    | [d1, d2] => d1.toString ++ d2.toString
    | _ => "00"
  "a1" ++ "64736f6c63" ++ "43"
    ++ hexByte major ++ hexByte minor ++ hexByte patch
    ++ hexByte (cborLen / 256) ++ hexByte (cborLen % 256)

/-- Append solc CBOR metadata tail to bytecode hex string. -/
def appendSolcMetadata (solc : String) (bytecode : String) : IO String := do
  match (← solcVersion? solc) with
  | some versionStr =>
    match parseSolcVersion versionStr with
    | some (maj, min, pat) =>
      return bytecode ++ metadataCborTail maj min pat
    | none =>
      return bytecode
  | none =>
    return bytecode

def solcBytecode (solc : String) (yulFile : FilePath) : IO String := do
  let stdout ← runProcess solc #["--strict-assembly", yulFile.toString, "--bin"]
  let mut bytecode := ""
  for line in stdout.splitOn "\n" do
    let line := trimAsciiString line
    if isHexString line then
      bytecode := line
  if bytecode.isEmpty then
    throw <| IO.userError s!"solc did not emit bytecode for {yulFile}"
  appendSolcMetadata solc bytecode

def storageLayoutJson (module : ProofForge.IR.Module) : String :=
  let layout := ProofForge.Backend.Evm.Plan.storageLayout module
  let stateJson (s : ProofForge.Backend.Evm.Plan.StorageStatePlan) : String :=
    jsonObject #[
      ("id", jsonString s.id),
      ("slot", toString s.slot),
      ("span", toString s.span),
      ("kind", jsonString (match s.kind with
        | .scalar => "scalar"
        | .map _ _ => "map"
        | .array _ => "array"
        | .dynamicArray => "dynamicArray")),
      ("type", jsonString s.type.name),
      ("byteOffset", toString s.byteOffset),
      ("byteWidth", toString s.byteWidth)
    ]
  jsonObject #[
    ("states", jsonArray (layout.states.map stateJson))
  ]

partial def pushByteWidthFrom (value width : Nat) : Option Nat :=
  if width > 32 then
    none
  else if value < byteLimit width then
    some width
  else
    pushByteWidthFrom value (width + 1)

def pushByteWidth (value : Nat) : Option Nat :=
  pushByteWidthFrom value 1

def pushDataHex (value : Nat) : Except String String := do
  let some width := pushByteWidth value
    | .error s!"EVM initcode value {value} is too large for PUSH32"
  .ok (fixedHexBytes 1 (0x5f + width) ++ fixedHexBytes width value)

partial def initCodeOffsetWidth (sizePushWidth offsetWidth : Nat) : Except String Nat := do
  let headerBytes := 9 + 2 * sizePushWidth + offsetWidth
  let some requiredWidth := pushByteWidth headerBytes
    | .error s!"EVM initcode header offset {headerBytes} is too large for PUSH32"
  if requiredWidth == offsetWidth then
    .ok offsetWidth
  else
    initCodeOffsetWidth sizePushWidth requiredWidth

def deploymentInitCodeHex (runtimeBytecode constructorArgsHex : String) : Except String String := do
  let runtime := stripHexPrefix (trimAsciiString runtimeBytecode)
  let constructorArgs ← normalizeConstructorArgsHex constructorArgsHex
  if runtime.isEmpty then
    .error "EVM runtime bytecode must be non-empty before initcode generation"
  else if runtime.length % 2 != 0 then
    .error "EVM runtime bytecode hex must have an even number of digits before initcode generation"
  else if !runtime.all isHexChar then
    .error "EVM runtime bytecode must contain only hex digits before initcode generation"
  else
    let runtimeBytes := runtime.length / 2
    let some sizePushWidth := pushByteWidth runtimeBytes
      | .error s!"EVM runtime bytecode length {runtimeBytes} is too large for PUSH32 initcode"
    let offsetWidth ← initCodeOffsetWidth sizePushWidth 1
    let headerBytes := 9 + 2 * sizePushWidth + offsetWidth
    let sizePush ← pushDataHex runtimeBytes
    let offsetPush ← pushDataHex headerBytes
    .ok (sizePush ++ offsetPush ++ "600039" ++ sizePush ++ "6000f3" ++ runtime ++ constructorArgs)

def writeEvmInitCode
    (opts : CliOptions)
    (module? : Option ProofForge.IR.Module)
    (constructorInitBindings : Array ProofForge.Contract.EvmConstructorInitBinding)
    (bytecodeOutput : FilePath)
    (constructorArgsHex : String) : IO FilePath := do
  let runtimeBytecode ← IO.FS.readFile bytecodeOutput
  let runtimeTrimmed := trimAsciiString runtimeBytecode
  let argsTrimmed := stripHexPrefix (trimAsciiString constructorArgsHex)
  let argsByteLen := argsTrimmed.length / 2
  let specParams := opts.evmConstructorParams.map fun param =>
    { name := param.name, abiType := param.abiType : ProofForge.Contract.EvmConstructorParam }
  let initCode ←
    match module? with
    | some module =>
        if ProofForge.Backend.Evm.ConstructorInit.shouldUseDeployObject constructorInitBindings constructorArgsHex then
          match ProofForge.Backend.Evm.ConstructorInit.renderDeployObject
              module.name module specParams constructorInitBindings runtimeTrimmed argsByteLen with
          | .error err => throw <| IO.userError err.render
          | .ok deployYul =>
              let deployYulPath := bytecodeOutput.withExtension "deploy.yul"
              if let some parent := deployYulPath.parent then
                IO.FS.createDirAll parent
              IO.FS.writeFile deployYulPath (deployYul ++ "\n")
              let creationHex ← solcBytecode opts.solc deployYulPath
              pure (creationHex ++ argsTrimmed)
        else
          match deploymentInitCodeHex runtimeTrimmed constructorArgsHex with
          | .ok initCode => pure initCode
          | .error msg => throw <| IO.userError msg
    | none =>
        match deploymentInitCodeHex runtimeTrimmed constructorArgsHex with
        | .ok initCode => pure initCode
        | .error msg => throw <| IO.userError msg
  let initCodeOutput := defaultInitCodeOutput bytecodeOutput
  if let some parent := initCodeOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile initCodeOutput (initCode ++ "\n")
  IO.println s!"wrote {initCodeOutput} ({initCode.length} hex chars)"
  return initCodeOutput

def contractNameForFixture (fixture : String) : String :=
  if fixture.endsWith ".lean" then
    dropEndString fixture ".lean".length
  else if fixture.endsWith ".learn" then
    dropEndString fixture ".learn".length
  else
    fixture

def resolveEvmChainProfile? (profileId? : Option String) : IO (Option ProofForge.Target.EvmChainProfile) := do
  match profileId? with
  | none => return none
  | some profileId =>
      match ProofForge.Target.findEvmChainProfile? profileId with
      | some profile => return some profile
      | none =>
          let known := String.intercalate ", " ProofForge.Target.knownEvmChainProfileIds.toList
          throw <| IO.userError s!"unknown EVM chain profile `{profileId}`; known profiles: {known}"

def evmChainProfileJson (profile : ProofForge.Target.EvmChainProfile) : String :=
  jsonObject #[
    ("id", jsonString profile.id),
    ("targetId", jsonString profile.targetId),
    ("networkName", jsonString profile.networkName),
    ("chainId", toString profile.chainId),
    ("nativeCurrencySymbol", jsonString profile.nativeCurrencySymbol),
    ("rollupFamily", jsonStringOption profile.rollupFamily),
    ("dataAvailability", jsonStringOption profile.dataAvailability),
    ("rpcUrls", jsonStringArray profile.rpcUrls),
    ("websocketUrls", jsonStringArray profile.websocketUrls),
    ("sequencerUrls", jsonStringArray profile.sequencerUrls),
    ("blockExplorerUrl", jsonStringOption profile.blockExplorerUrl),
    ("verifier", jsonStringOption profile.verifier),
    ("verifierUrl", jsonStringOption profile.verifierUrl),
    ("notes", jsonStringArray profile.notes)
  ]

def evmChainProfileFieldJson (profile? : Option ProofForge.Target.EvmChainProfile) : String :=
  match profile? with
  | some profile => evmChainProfileJson profile
  | none => "null"

def constructorArgsJson (constructorArgsHex source : String) : IO String := do
  let normalized ←
    match normalizeConstructorArgsHex constructorArgsHex with
    | .ok hex => pure hex
    | .error msg => throw <| IO.userError msg
  if normalized.isEmpty then
    return jsonArray #[]
  else
    let digest ← sha256HexBytes normalized
    return jsonArray #[
      jsonObject #[
        ("encoding", jsonString "abi-encoded"),
        ("hex", jsonString s!"0x{normalized}"),
        ("bytes", toString (normalized.length / 2)),
        ("sha256", jsonString digest),
        ("source", jsonString source)
      ]
    ]

def evmDeploymentJson (profile? : Option ProofForge.Target.EvmChainProfile) : String :=
  let (profileId, chainId, networkName, rpcUrls, blockExplorerUrl, verifier, verifierUrl, reason) :=
    match profile? with
    | some profile =>
        (jsonString profile.id,
          toString profile.chainId,
          jsonString profile.networkName,
          jsonStringArray profile.rpcUrls,
          jsonStringOption profile.blockExplorerUrl,
          jsonStringOption profile.verifier,
          jsonStringOption profile.verifierUrl,
          jsonString "ProofForge emitted a chain-profile-aware deployment plan, but transaction signing and broadcast artifacts are not generated yet.")
    | none =>
        ("null",
          "null",
          "null",
          jsonArray #[],
          "null",
          "null",
          "null",
          jsonString "ProofForge EVM bytecode modes emit deployable initcode and runtime bytecode artifacts, but no EVM chain profile was selected and transaction broadcasting is not generated yet.")
  jsonObject #[
    ("profileId", profileId),
    ("chainId", chainId),
    ("networkName", networkName),
    ("rpcUrls", rpcUrls),
    ("blockExplorerUrl", blockExplorerUrl),
    ("verifier", verifier),
    ("verifierUrl", verifierUrl),
    ("address", "null"),
    ("broadcast", jsonString "not-generated"),
    ("broadcastArtifact", "null"),
    ("reason", reason),
    ("reference", jsonString "scripts/evm/foundry-smoke.sh")
  ]

def writeEvmDeployManifest
    (deployOutput : FilePath)
    (fixture sourceKind sourceModule : String)
    (capabilities : Array String)
    (entrypoints : Array String)
    (events : Array String)
    (methods : Array String)
    (chainProfile? : Option ProofForge.Target.EvmChainProfile)
    (constructorParams : Array ConstructorParamSpec)
    (sourceArtifact? : Option String)
    (yulArtifact bytecodeArtifact initCodeArtifact constructorArgs : String) : IO Unit := do
  let mut inputFields : Array (String × String) := #[
    ("yul", yulArtifact),
    ("bytecode", bytecodeArtifact),
    ("initCode", initCodeArtifact)
  ]
  if let some sourceArtifact := sourceArtifact? then
    inputFields := inputFields.push ("source", sourceArtifact)
  let manifest := jsonObject #[
    ("schemaVersion", "1"),
    ("kind", jsonString "proof-forge-evm-deploy-manifest"),
    ("target", jsonString "evm"),
    ("targetFamily", jsonString "evm"),
    ("artifactKind", jsonString "evm-initcode-deploy"),
    ("fixture", jsonString fixture),
    ("contractName", jsonString (contractNameForFixture fixture)),
    ("sourceKind", jsonString sourceKind),
    ("irVersion", if sourceKind == "portable-ir" then jsonString "portable-ir-v0" else "null"),
    ("sourceModule", jsonString sourceModule),
    ("chainProfile", evmChainProfileFieldJson chainProfile?),
    ("capabilities", jsonStringArray (dedupStrings capabilities)),
    ("abi", jsonObject #[
      ("constructor", constructorAbiJson constructorParams),
      ("entrypoints", jsonArray entrypoints),
      ("events", jsonArray events),
      ("methods", jsonArray methods)
    ]),
    ("creation", jsonObject #[
      ("mode", jsonString "init-code"),
      ("constructorArgs", constructorArgs),
      ("initCode", initCodeArtifact),
      ("runtimeBytecode", bytecodeArtifact)
    ]),
    ("inputs", jsonObject inputFields),
    ("deployment", evmDeploymentJson chainProfile?)
  ]
  if let some parent := deployOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile deployOutput (manifest ++ "\n")

def writeEvmArtifactMetadata
    (opts : CliOptions)
    (fixture sourceKind sourceModule : String)
    (capabilities : Array String)
    (entrypoints : Array String)
    (events : Array String)
    (methods : Array String)
    (source? : Option FilePath)
    (yulOutput bytecodeOutput : FilePath)
    (extraArtifacts : Array (String × String) := #[])
    (storageLayout? : Option String := none)
    (module? : Option ProofForge.IR.Module := none)
    (constructorInitBindings : Array ProofForge.Contract.EvmConstructorInitBinding := #[]) : IO Unit := do
  let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput bytecodeOutput)
  let deployOutput := defaultDeployManifestOutput metadataOutput
  let chainProfile? ← resolveEvmChainProfile? opts.evmChainProfile?
  let constructorArgs ← constructorArgsJson opts.evmConstructorArgsHex opts.evmConstructorArgsSource
  let initCodeOutput ← writeEvmInitCode opts module? constructorInitBindings bytecodeOutput opts.evmConstructorArgsHex
  let yulArtifact ← artifactEntryJson yulOutput
  let bytecodeArtifact ← artifactEntryJson bytecodeOutput
  let initCodeArtifact ← artifactEntryJson initCodeOutput
  let sourceArtifact? ← optionalArtifactEntryJson source?
  writeEvmDeployManifest
    deployOutput
    fixture
    sourceKind
    sourceModule
    capabilities
    entrypoints
    events
    methods
    chainProfile?
    opts.evmConstructorParams
    sourceArtifact?
    yulArtifact
    bytecodeArtifact
    initCodeArtifact
    constructorArgs
  let mut artifactFields : Array (String × String) := #[
    ("yul", yulArtifact),
    ("bytecode", bytecodeArtifact),
    ("initCode", initCodeArtifact),
    ("deployManifest", ← artifactEntryJson deployOutput)
  ]
  if let some sourceArtifact := sourceArtifact? then
    artifactFields := artifactFields.push ("source", sourceArtifact)
  for (name, artifact) in extraArtifacts do
    artifactFields := artifactFields.push (name, artifact)
  let solcVersionValue :=
    match (← solcVersion? opts.solc) with
    | some version => jsonString version
    | none => "null"
  -- EIP-170 contract code size limit: 24,576 bytes
  let contractSizeLimit := 24576
  let bytecodeContent ← IO.FS.readFile bytecodeOutput
  let bytecodeBytes := (trimAsciiString bytecodeContent).length / 2
  let contractSizeStatus :=
    if bytecodeBytes > contractSizeLimit then "exceeded"
    else "passed"
  let metadata := jsonObject #[
    ("schemaVersion", "1"),
    ("target", jsonString "evm"),
    ("targetFamily", jsonString "evm"),
    ("artifactKind", jsonString "evm-bytecode"),
    ("fixture", jsonString fixture),
    ("sourceKind", jsonString sourceKind),
    ("irVersion", if sourceKind == "portable-ir" then jsonString "portable-ir-v0" else "null"),
    ("sourceModule", jsonString sourceModule),
    ("sdkSchema", jsonString "proof-forge-sdk.json"),
    ("capabilities", jsonStringArray (dedupStrings capabilities)),
    ("toolchain", jsonObject #[
      ("solc", jsonObject #[
        ("path", jsonString opts.solc),
        ("version", solcVersionValue)
      ])
    ]),
    ("abi", jsonObject #[
      ("constructor", constructorAbiJson opts.evmConstructorParams),
      ("entrypoints", jsonArray entrypoints),
      ("events", jsonArray events),
      ("methods", jsonArray methods)
    ]),
    ("artifacts", jsonObject artifactFields),
    ("validation", jsonObject #[
      ("solcStrictAssembly", jsonString "passed"),
      ("bytecodeGeneration", jsonString "passed"),
      ("initCodeGeneration", jsonString "passed"),
      ("deployManifest", jsonString "passed"),
      ("contractSizeCheck", jsonObject #[
        ("status", jsonString contractSizeStatus),
        ("bytecodeBytes", toString bytecodeBytes),
        ("limit", toString contractSizeLimit)
      ])
    ]),
    ("storageLayout", match storageLayout? with
      | some json => json
      | none => "null")
  ]
  if let some parent := metadataOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile metadataOutput (metadata ++ "\n")
  IO.println s!"wrote {metadataOutput}"

def writeEvmModuleArtifactMetadata
    (opts : CliOptions)
    (fixture sourceKind sourceModule : String)
    (module : ProofForge.IR.Module)
    (yulOutput bytecodeOutput : FilePath)
    (extraArtifacts : Array (String × String) := #[])
    (constructorInitBindings : Array ProofForge.Contract.EvmConstructorInitBinding := #[]) : IO Unit := do
  let events ← eventAbisForModule opts.cast module
  let mut entrypoints := #[]
  for entrypoint in module.entrypoints do
    -- Skip fallback/receive from metadata — they don't have ABI selectors
    if entrypoint.kind == .fallback || entrypoint.kind == .receive then
      continue
    entrypoints := entrypoints.push (← liftExceptString (entrypointJson module entrypoint))
  writeEvmArtifactMetadata
    opts
    fixture
    sourceKind
    sourceModule
    (moduleCapabilityIds module)
    entrypoints
    (events.map eventAbiJson)
    #[]
    none
    yulOutput
    bytecodeOutput
    extraArtifacts
    (some (storageLayoutJson module))
    (some module)
    constructorInitBindings
  if opts.fromNewSurface then
    let schemaDir := bytecodeOutput.parent.getD (FilePath.mk ".")
    let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput bytecodeOutput)
    let deployOutput := defaultDeployManifestOutput metadataOutput
    let initOutput := defaultInitCodeOutput bytecodeOutput
    let spec := ProofForge.Contract.ContractSpec.fromIR module
    let unifiedClientOutput ← writeUnifiedEvmClient schemaDir spec fixture
    let mut artifactPaths : Array (String × FilePath) := #[
      ("artifactMetadata", metadataOutput),
      ("yul", yulOutput),
      ("primary", bytecodeOutput),
      ("secondary", initOutput),
      ("deployManifest", deployOutput)
    ]
    let contractSpecOutput := schemaDir / s!"{fixture}.contract-spec.json"
    if ← contractSpecOutput.pathExists then
      artifactPaths := artifactPaths.push ("contractSpec", contractSpecOutput)
    let nativeClientOutput := schemaDir / ProofForge.Contract.Client.evmAbiWrapperPath
    let mut clientPaths : Array (String × FilePath) := #[("typescript", unifiedClientOutput)]
    if ← nativeClientOutput.pathExists then
      clientPaths := clientPaths.push ("nativeWrapper", nativeClientOutput)
    discard <| writeSdkSchemaFile "evm" spec schemaDir artifactPaths clientPaths

def writeEvmContractSdkClientArtifacts
    (spec : ProofForge.Contract.ContractSpec)
    (bytecodeOutput : FilePath)
    (artifactBaseName : String) : IO (FilePath × FilePath × String × String) := do
  let specOutput := siblingPath bytecodeOutput s!"{artifactBaseName}.contract-spec.json"
  let clientOutput := siblingPath bytecodeOutput ProofForge.Contract.Client.evmAbiWrapperPath
  if let some parent := specOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile specOutput (ProofForge.Contract.Spec.Json.render spec ++ "\n")
  IO.println s!"wrote {specOutput}"
  if let some parent := clientOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile clientOutput (ProofForge.Contract.Client.renderEvmAbiWrapper spec artifactBaseName ++ "\n")
  IO.println s!"wrote {clientOutput}"
  let specArtifact ← artifactEntryJson specOutput
  let clientArtifact ← artifactEntryJson clientOutput
  return (specOutput, clientOutput, specArtifact, clientArtifact)

def writeEvmContractSdkArtifactMetadata
    (opts : CliOptions)
    (fixture sourceModule : String)
    (spec : ProofForge.Contract.ContractSpec)
    (module : ProofForge.IR.Module)
    (yulOutput bytecodeOutput : FilePath) : IO Unit := do
  let (_, _, specArtifact, clientArtifact) ←
    writeEvmContractSdkClientArtifacts spec bytecodeOutput fixture
  writeEvmModuleArtifactMetadata opts fixture "contract-sdk" sourceModule module yulOutput bytecodeOutput #[
    ("contractSpec", specArtifact),
    ("client", clientArtifact)
  ] spec.evmConstructorInitBindings

def writeEvmIrArtifactMetadata
    (opts : CliOptions)
    (fixture sourceModule : String)
    (module : ProofForge.IR.Module)
    (yulOutput bytecodeOutput : FilePath)
    (extraArtifacts : Array (String × String) := #[]) : IO Unit :=
  writeEvmModuleArtifactMetadata opts fixture "portable-ir" sourceModule module yulOutput bytecodeOutput extraArtifacts

def writeEvmLearnArtifactMetadata
    (opts : CliOptions)
    (fixture sourceModule : String)
    (input : FilePath)
    (module : ProofForge.IR.Module)
    (yulOutput bytecodeOutput : FilePath) : IO Unit := do
  let events ← eventAbisForModule opts.cast module
  let mut entrypoints := #[]
  for entrypoint in module.entrypoints do
    entrypoints := entrypoints.push (← liftExceptString (entrypointJson module entrypoint))
  writeEvmArtifactMetadata
    opts
    fixture
    "learn-source"
    sourceModule
    (moduleCapabilityIds module)
    entrypoints
    (events.map eventAbiJson)
    #[]
    (some input)
    yulOutput
    bytecodeOutput

end ProofForge.Cli

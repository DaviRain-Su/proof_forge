import Lean.Util.Path
import ProofForge.Cli.HexUtil
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.Options
import ProofForge.Cli.Process
import ProofForge.Contract.Client
import ProofForge.Contract.SdkSchema
import ProofForge.Contract.Spec
import ProofForge.Contract.Spec.Json
import ProofForge.Target

open ProofForge.Cli.HexUtil
open ProofForge.Cli.JsonUtil
open System

namespace ProofForge.Cli

def fileDigestAndBytes (path : FilePath) : IO (String × Nat) := do
  let script := "import hashlib, pathlib, sys; data = pathlib.Path(sys.argv[1]).read_bytes(); print(hashlib.sha256(data).hexdigest(), len(data))"
  let stdout ← runProcess "python3" #["-c", script, path.toString]
  match (trimAsciiString stdout).splitOn " " with
  | [digest, byteCount] =>
      let some bytes := byteCount.toNat?
        | throw <| IO.userError s!"python3 returned invalid byte count for {path}: {byteCount}"
      return (digest, bytes)
  | _ =>
      throw <| IO.userError s!"python3 returned invalid digest output for {path}: {trimAsciiString stdout}"

def sha256HexBytes (hex : String) : IO String := do
  let script := "import hashlib, sys; print(hashlib.sha256(bytes.fromhex(sys.argv[1])).hexdigest())"
  let digest := trimAsciiString (← runProcess "python3" #["-c", script, hex])
  if digest.length == 64 && digest.all isHexChar then
    return digest
  else
    throw <| IO.userError s!"python3 returned invalid SHA-256 digest for constructor args: {digest}"

def defaultArtifactOutput (bytecodeOutput : FilePath) : FilePath :=
  let fileName := FilePath.mk "proof-forge-artifact.json"
  match bytecodeOutput.parent with
  | some parent => parent / fileName
  | none => fileName

def defaultDeployManifestOutput (metadataOutput : FilePath) : FilePath :=
  let fileName := metadataOutput.fileName.getD metadataOutput.toString
  let deployName :=
    if fileName == "proof-forge-artifact.json" then
      "proof-forge-deploy.json"
    else if fileName.endsWith ".proof-forge-artifact.json" then
      s!"{dropEndString fileName ".proof-forge-artifact.json".length}.proof-forge-deploy.json"
    else
      s!"{fileName}.proof-forge-deploy.json"
  let deployFile := FilePath.mk deployName
  match metadataOutput.parent with
  | some parent => parent / deployFile
  | none => deployFile

def defaultInitCodeOutput (bytecodeOutput : FilePath) : FilePath :=
  bytecodeOutput.withExtension "init.bin"

def artifactEntryJson (path : FilePath) : IO String := do
  let (digest, bytes) ← fileDigestAndBytes path
  return jsonObject #[
    ("path", jsonString path.toString),
    ("sha256", jsonString digest),
    ("bytes", toString bytes)
  ]

def pathStringWithoutTrailingSlash (path : FilePath) : String :=
  let text := path.toString
  if text.endsWith "/" then
    dropEndString text 1
  else
    text

def relativePathFromDir? (dir path : FilePath) : Option String :=
  let dirText := pathStringWithoutTrailingSlash dir
  let pathText := path.toString
  let dirPrefix := dirText ++ "/"
  if pathText.length > dirPrefix.length && pathText.take dirPrefix.length == dirPrefix then
    some ((pathText.drop dirPrefix.length).toString)
  else
    match path.parent, path.fileName with
    | some parent, some fileName =>
        if pathStringWithoutTrailingSlash parent == dirText then some fileName else none
    | _, _ => none

def artifactEntryJsonRelativeTo (baseDir : FilePath) (path : FilePath) : IO String := do
  let some rel := relativePathFromDir? baseDir path
    | throw <| IO.userError s!"artifact reference {path} is not inside artifact directory {baseDir}"
  let (digest, bytes) ← fileDigestAndBytes path
  return jsonObject #[
    ("path", jsonString rel),
    ("sha256", jsonString digest),
    ("bytes", toString bytes)
  ]

def sdkFileRefFromPath (schemaDir : FilePath) (path : FilePath) : IO ProofForge.Contract.SdkSchema.FileRef := do
  let some rel := relativePathFromDir? schemaDir path
    | throw <| IO.userError s!"SDK schema reference {path} is not inside SDK directory {schemaDir}"
  ProofForge.Contract.SdkSchema.FileRef.fromRelative schemaDir.toString rel

def writeSdkSchemaFile
    (targetId : String)
    (spec : ProofForge.Contract.ContractSpec)
    (schemaDir : FilePath)
    (artifacts : Array (String × FilePath))
    (clients : Array (String × FilePath))
    (extension? : Option ProofForge.Contract.SdkSchema.TargetExtension := none) : IO FilePath := do
  let artifactRefs ← artifacts.mapM fun artifact => do
    let ref ← sdkFileRefFromPath schemaDir artifact.snd
    return (artifact.fst, ref)
  let clientRefs ← clients.mapM fun client => do
    let ref ← sdkFileRefFromPath schemaDir client.snd
    return (client.fst, ref)
  let json ←
    match ProofForge.Contract.SdkSchema.render targetId spec artifactRefs clientRefs extension? with
    | .ok json => pure json
    | .error err => throw <| IO.userError err
  let schemaOutput := schemaDir / "proof-forge-sdk.json"
  if let some parent := schemaOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile schemaOutput (json ++ "\n")
  IO.println s!"wrote {schemaOutput}"
  return schemaOutput

def writeUnifiedEvmClient
    (schemaDir : FilePath)
    (spec : ProofForge.Contract.ContractSpec)
    (artifactBaseName : String) : IO FilePath := do
  let output := schemaDir / "proof-forge-client.ts"
  if let some parent := output.parent then
    IO.FS.createDirAll parent
  let wrapper ← match ProofForge.Contract.Client.renderEvmAbiWrapper spec artifactBaseName with
    | .ok wrapper => pure wrapper
    | .error err => throw <| IO.userError s!"EVM client ABI: {err}"
  IO.FS.writeFile output (wrapper ++ "\n")
  IO.println s!"wrote {output}"
  return output

def writeNearContractSidecars
    (schemaDir : FilePath)
    (spec : ProofForge.Contract.ContractSpec) : IO (FilePath × FilePath × FilePath) := do
  let specOutput := schemaDir / s!"{spec.name}.contract-spec.json"
  let nearClientOutput := schemaDir / ProofForge.Contract.Client.nearWrapperPath
  let unifiedClientOutput := schemaDir / "proof-forge-client.ts"
  if let some parent := specOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile specOutput (ProofForge.Contract.Spec.Json.render spec ++ "\n")
  IO.println s!"wrote {specOutput}"
  let nearClient := ProofForge.Contract.Client.renderNearWrapper spec ++ "\n"
  if let some parent := nearClientOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile nearClientOutput nearClient
  IO.println s!"wrote {nearClientOutput}"
  if let some parent := unifiedClientOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile unifiedClientOutput nearClient
  IO.println s!"wrote {unifiedClientOutput}"
  return (specOutput, nearClientOutput, unifiedClientOutput)

/-- Wasm-host sidecars keyed by target (PF-P0-04): Soroban/CosmWasm must not emit NEAR wrappers. -/
def writeWasmHostContractSidecars
    (targetId : String)
    (schemaDir : FilePath)
    (spec : ProofForge.Contract.ContractSpec) : IO (FilePath × FilePath × FilePath) := do
  if targetId == ProofForge.Target.wasmStellarSoroban.id then
    let specOutput := schemaDir / s!"{spec.name}.contract-spec.json"
    let sorobanClientOutput := schemaDir / ProofForge.Contract.Client.sorobanWrapperPath
    let unifiedClientOutput := schemaDir / "proof-forge-client.ts"
    if let some parent := specOutput.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile specOutput (ProofForge.Contract.Spec.Json.render spec ++ "\n")
    IO.println s!"wrote {specOutput}"
    let client := ProofForge.Contract.Client.renderSorobanWrapper spec ++ "\n"
    if let some parent := sorobanClientOutput.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile sorobanClientOutput client
    IO.println s!"wrote {sorobanClientOutput}"
    if let some parent := unifiedClientOutput.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile unifiedClientOutput client
    IO.println s!"wrote {unifiedClientOutput}"
    return (specOutput, sorobanClientOutput, unifiedClientOutput)
  else if targetId == ProofForge.Target.wasmCosmWasm.id then
    let specOutput := schemaDir / s!"{spec.name}.contract-spec.json"
    let cwClientOutput := schemaDir / ProofForge.Contract.Client.cosmWasmWrapperPath
    let unifiedClientOutput := schemaDir / "proof-forge-client.ts"
    if let some parent := specOutput.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile specOutput (ProofForge.Contract.Spec.Json.render spec ++ "\n")
    IO.println s!"wrote {specOutput}"
    let client := ProofForge.Contract.Client.renderCosmWasmWrapper spec ++ "\n"
    if let some parent := cwClientOutput.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile cwClientOutput client
    IO.println s!"wrote {cwClientOutput}"
    if let some parent := unifiedClientOutput.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile unifiedClientOutput client
    IO.println s!"wrote {unifiedClientOutput}"
    return (specOutput, cwClientOutput, unifiedClientOutput)
  else
    writeNearContractSidecars schemaDir spec

def optionalArtifactEntryJson : Option FilePath → IO (Option String)
  | some path => do
      let artifact ← artifactEntryJson path
      return some artifact
  | none => return none

end ProofForge.Cli

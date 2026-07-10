import Init.Notation
import Init.System.IO
import ProofForge.Target.Registry
import ProofForge.Cli.EvmArtifacts
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.HexUtil

open System
open ProofForge.Cli.JsonUtil
open ProofForge.Cli.HexUtil

namespace ProofForge.Cli.Deploy

def defaultAnvilChainId : Nat := 31337

def deployUsage : String :=
  String.intercalate "\n" [
    "Usage:",
    "  proof-forge deploy --target evm --deploy-manifest PATH [options]",
    "",
    "Broadcast EVM initcode from a proof-forge-deploy.json manifest and record",
    "tx/receipt artifacts. Local Anvil uses the anvil-local chain profile;",
    "public testnet profiles default to plan-only unless --broadcast is set.",
    "",
    "Options:",
    "  --deploy-manifest PATH   proof-forge-deploy.json from `proof-forge build`",
    "  -o, --output PATH       deploy-run or deploy-plan output path",
    "  --evm-chain-profile ID  override chain profile (default: manifest profile)",
    "  --rpc-url URL           JSON-RPC endpoint (default: profile rpcUrls[0])",
    "  --private-key KEY       signing key for transaction broadcast (required; no default)",
    "  --deployer ADDRESS      expected deployer address metadata",
    "  --cast PATH             cast executable (default: cast)",
    "  --anvil PATH            anvil executable (default: anvil)",
    "  --start-anvil           start a local Anvil node when RPC is unreachable",
    "  --anvil-port PORT       Anvil port when --start-anvil is used",
    "  --broadcast             allow live broadcast on non-anvil chain profiles",
    "  --plan-only             emit deploy-plan only; skip transaction broadcast",
    "  --gas-limit GAS         maximum gas units for deploy/init/interaction transactions",
    "  --gas-price WEI         legacy gas price in wei",
    "  --max-fee-per-gas WEI   EIP-1559 max fee per gas in wei",
    "  --max-priority-fee-per-gas WEI  EIP-1559 max priority fee per gas in wei",
    "  --root DIR              project root for relative artifact paths",
  ]

structure DeployOptions where
  targetId : String := "evm"
  deployManifest : String := ""
  output? : Option String := none
  chainProfile? : Option String := none
  rpcUrl? : Option String := none
  privateKey? : Option String := none
  deployerAddress? : Option String := none
  castPath : String := "cast"
  anvilPath : String := "anvil"
  startAnvil : Bool := false
  anvilPort? : Option Nat := none
  broadcast : Bool := false
  planOnly : Bool := false
  gasLimit? : Option Nat := none
  gasPrice? : Option Nat := none
  maxFeePerGas? : Option Nat := none
  maxPriorityFeePerGas? : Option Nat := none
  root : String := "."
  deriving Inhabited

def joinPath (a b : String) : String :=
  if a.endsWith "/" then s!"{a}{b}" else s!"{a}/{b}"

def pathExists (path : String) : IO Bool := do
  try
    let _ ← IO.FS.readFile path
    return true
  catch _ =>
    return false

def runProcess (cmd : String) (args : Array String) (cwd? : Option String := none) : IO String := do
  let cwd? := cwd?.map FilePath.mk
  let output ← IO.Process.output { cmd := cmd, args := args, cwd := cwd? }
  if output.exitCode != 0 then
    let stderr := trimAsciiString output.stderr
    let detail := if stderr.isEmpty then trimAsciiString output.stdout else stderr
    throw <| IO.userError s!"{cmd} failed with exit code {output.exitCode}: {detail}"
  return output.stdout

def resolveEvmChainProfile (profileId : String) : IO ProofForge.Target.EvmChainProfile := do
  match ProofForge.Target.findEvmChainProfile? profileId with
  | some profile => pure profile
  | none =>
      let known := String.intercalate ", " ProofForge.Target.knownEvmChainProfileIds.toList
      throw <| IO.userError s!"unknown EVM chain profile `{profileId}`; known profiles: {known}"

def normalizeEvmAddress (value label : String) : Except String String := do
  let hex ← normalizeExactHexBytes value label 20
  return "0x" ++ hex

def resolveDeployerAddress
    (declared? : Option String) (transactionFrom : String) : Except String String := do
  let actual ← normalizeEvmAddress transactionFrom "creation transaction sender"
  match declared? with
  | none => return actual
  | some declared =>
      let expected ← normalizeEvmAddress declared "--deployer"
      if expected == actual then
        return actual
      else
        throw s!"--deployer {expected} does not match creation transaction sender {actual}"

def verifySigningDeployer
    (castPath privateKey : String) (declared? : Option String) : IO Unit := do
  let some declared := declared? | return
  let expected ← match normalizeEvmAddress declared "--deployer" with
  | .ok address => pure address
  | .error err => throw <| IO.userError err
  let signingOutput ← runProcess castPath #["wallet", "address", "--private-key", privateKey]
  let actual ← match normalizeEvmAddress signingOutput "signing key address" with
  | .ok address => pure address
  | .error err => throw <| IO.userError err
  if expected != actual then
    throw <| IO.userError
      s!"--deployer {expected} does not match signing key address {actual}; refusing to broadcast"

def deployNetworkKind (profile : ProofForge.Target.EvmChainProfile) : String :=
  if profile.id == "anvil-local" then "anvil" else "chain-profile"

def defaultDeployRunOutput (manifestPath : String) : String :=
  if manifestPath.endsWith ".proof-forge-deploy.json" then
    manifestPath.replace ".proof-forge-deploy.json" ".proof-forge-deploy-run.json"
  else
    s!"{manifestPath}.proof-forge-deploy-run.json"

def defaultDeployPlanOutput (manifestPath : String) : String :=
  if manifestPath.endsWith ".proof-forge-deploy.json" then
    manifestPath.replace ".proof-forge-deploy.json" ".proof-forge-deploy-plan.json"
  else
    s!"{manifestPath}.proof-forge-deploy-plan.json"

structure ManifestInfo where
  fixture : String
  contractName : String
  initCodePath : String
  runtimeBytecodePath : String
  chainProfileId : String
  chainIdText : String
  deriving Inhabited

def parseManifestInfoLine (line : String) : Option (String × String) :=
  match line.splitOn "=" with
  | [key, value] => some (key, value)
  | _ => none

def findProofForgeScriptRoot (root : String) : IO String := do
  let localCandidate := joinPath root "scripts/evm/read-deploy-manifest.py"
  if ← pathExists localCandidate then
    return root
  if let some srcPath ← IO.getEnv "LEAN_SRC_PATH" then
    for part in String.splitOn srcPath ":" do
      let candidate := joinPath part "scripts/evm/read-deploy-manifest.py"
      if ← pathExists candidate then
        return part
  return "."

def readManifestInfo (manifestPath : String) : IO ManifestInfo := do
  let scriptRoot ← findProofForgeScriptRoot "."
  let reader := joinPath scriptRoot "scripts/evm/read-deploy-manifest.py"
  let stdout ← runProcess "python3" #[reader, manifestPath]
  let mut info : ManifestInfo := {
    fixture := "",
    contractName := "",
    initCodePath := "",
    runtimeBytecodePath := "",
    chainProfileId := "",
    chainIdText := ""
  }
  for line in stdout.splitOn "\n" do
    let line := trimAsciiString line
    if line.isEmpty then
      continue
    match parseManifestInfoLine line with
    | none => continue
    | some ("fixture", value) => info := { info with fixture := value }
    | some ("contractName", value) => info := { info with contractName := value }
    | some ("initCodePath", value) => info := { info with initCodePath := value }
    | some ("runtimeBytecodePath", value) => info := { info with runtimeBytecodePath := value }
    | some ("chainProfileId", value) => info := { info with chainProfileId := value }
    | some ("chainIdText", value) => info := { info with chainIdText := value }
    | _ => continue
  if info.initCodePath.isEmpty then
    throw <| IO.userError s!"deploy manifest is missing inputs.initCode: {manifestPath}"
  if info.runtimeBytecodePath.isEmpty then
    throw <| IO.userError s!"deploy manifest is missing inputs.bytecode: {manifestPath}"
  return info

def resolveArtifactPath (root relPath : String) : String :=
  let path := FilePath.mk relPath
  if path.isAbsolute then
    relPath
  else
    joinPath root relPath

def rpcReachable? (castPath rpcUrl : String) : IO Bool := do
  try
    let _ ← runProcess castPath #["chain-id", "--rpc-url", rpcUrl]
    return true
  catch _ =>
    return false

def pickAnvilPort : IO Nat := do
  let stdout ← runProcess "python3" #[
    "-c",
    "import socket; s=socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1]); s.close()"
  ]
  match (trimAsciiString stdout).toNat? with
  | some port => pure port
  | none => throw <| IO.userError s!"failed to allocate Anvil port: {trimAsciiString stdout}"

def startAnvil (anvilPath castPath : String) (port chainId : Nat) (runDir : String) : IO Unit := do
  IO.FS.createDirAll runDir
  let child ← IO.Process.spawn {
    cmd := anvilPath
    args := #[
      "--host", "127.0.0.1",
      "--port", toString port,
      "--chain-id", toString chainId,
      "--accounts", "1",
      "--quiet"
    ]
    stdin := .null
    stdout := .null
    stderr := .null
    setsid := true
  }
  let rpcUrl := s!"http://127.0.0.1:{port}"
  for _ in [0:80] do
    if ← rpcReachable? castPath rpcUrl then
      return
    match ← child.tryWait with
    | some exitCode =>
        throw <| IO.userError
          s!"Anvil `{anvilPath}` exited with code {exitCode} before RPC became reachable at {rpcUrl}"
    | none => pure ()
    IO.sleep 250
  try
    child.kill
  catch _ =>
    pure ()
  throw <| IO.userError s!"Anvil did not become reachable at {rpcUrl}"

def expectChainId (castPath rpcUrl : String) (expected : Nat) : IO Unit := do
  let stdout ← runProcess castPath #["chain-id", "--rpc-url", rpcUrl]
  match (trimAsciiString stdout).toNat? with
  | some actual =>
      if actual != expected then
        throw <| IO.userError s!"RPC chain id {actual} does not match profile chain id {expected}"
  | none =>
      throw <| IO.userError s!"cast chain-id returned invalid output: {trimAsciiString stdout}"

def readInitCodeHex (path : String) : IO String := do
  let contents ← IO.FS.readFile path
  let hex := trimAsciiString contents
  if hex.isEmpty then
    throw <| IO.userError s!"init code file is empty: {path}"
  return hex

def extractJsonField (jsonPath field : String) : IO String := do
  let script := s!"import json, pathlib, sys; print(json.load(open(sys.argv[1], encoding='utf-8'))[{jsonString field}])"
  let stdout ← runProcess "python3" #["-c", script, jsonPath]
  return trimAsciiString stdout

def writeDeployPlan
    (root manifestPath initCodePath runtimePath rpcUrl output : String)
    (profile : ProofForge.Target.EvmChainProfile) : IO Unit := do
  let scriptRoot ← do
    if ← pathExists (joinPath root "scripts/evm/write-deploy-plan.py") then
      pure root
    else if let some srcPath ← IO.getEnv "LEAN_SRC_PATH" then
      let parts := String.splitOn srcPath ":"
      match parts.find? (fun part => part != "") with
      | some part => pure part
      | none => pure root
    else
      pure root
  let writer := joinPath scriptRoot "scripts/evm/write-deploy-plan.py"
  let _ ← runProcess "python3" #[
    writer,
    "--root", root,
    "--deploy-manifest", manifestPath,
    "--init-code", initCodePath,
    "--runtime-bytecode", runtimePath,
    "--rpc-url", rpcUrl,
    "--chain-profile-json", ProofForge.Cli.evmChainProfileJson profile,
    "--output", output
  ]
  let validator := joinPath scriptRoot "scripts/evm/validate-deploy-plan.py"
  let _ ← runProcess "python3" #[
    validator,
    "--root", root,
    "--expect-chain-profile", profile.id,
    "--expect-chain-id", toString profile.chainId,
    output
  ]

def writeDeployRun
    (root manifestPath initCodePath runtimePath rpcUrl : String)
    (profile : ProofForge.Target.EvmChainProfile)
    (anvilStarted : Bool)
    (deployer deployReceipt creationTx initializeReceipt output
     initialGet afterInitializeGet afterIncrementGet afterSecondIncrementGet : String) : IO Unit := do
  let scriptRoot ← do
    if ← pathExists (joinPath root "scripts/evm/write-deploy-run.py") then
      pure root
    else if let some srcPath ← IO.getEnv "LEAN_SRC_PATH" then
      let parts := String.splitOn srcPath ":"
      match parts.find? (fun part => part != "") with
      | some part => pure part
      | none => pure root
    else
      pure root
  let writer := joinPath scriptRoot "scripts/evm/write-deploy-run.py"
  let _ ← runProcess "python3" #[
    writer,
    "--root", root,
    "--rpc-url", rpcUrl,
    "--chain-profile-json", ProofForge.Cli.evmChainProfileJson profile,
    "--chain-id", toString profile.chainId,
    "--network-kind", deployNetworkKind profile,
    "--anvil-started-status", if anvilStarted then "passed" else "skipped",
    "--deployer", deployer,
    "--deploy-manifest", manifestPath,
    "--runtime-bytecode", runtimePath,
    "--init-code", initCodePath,
    "--deploy-receipt", deployReceipt,
    "--creation-transaction", creationTx,
    "--initialize-receipt", initializeReceipt,
    "--output", output,
    "--initial-get", initialGet,
    "--after-initialize-get", afterInitializeGet,
    "--after-increment-get", afterIncrementGet,
    "--after-second-increment-get", afterSecondIncrementGet
  ]

def validateDeployRun
    (root output chainProfileId chainId fixture : String) : IO Unit := do
  let scriptRoot ← do
    if ← pathExists (joinPath root "scripts/evm/validate-deploy-run.py") then
      pure root
    else if let some srcPath ← IO.getEnv "LEAN_SRC_PATH" then
      let parts := String.splitOn srcPath ":"
      match parts.find? (fun part => part != "") with
      | some part => pure part
      | none => pure root
    else
      pure root
  let validator := joinPath scriptRoot "scripts/evm/validate-deploy-run.py"
  let _ ← runProcess "python3" #[
    validator,
    "--root", root,
    "--expect-fixture", fixture,
    "--expect-chain-id", chainId,
    "--expect-chain-profile", chainProfileId,
    output
  ]

def shouldPlanOnly (profile : ProofForge.Target.EvmChainProfile) (opts : DeployOptions) : Bool :=
  opts.planOnly || (profile.id != "anvil-local" && !opts.broadcast)

structure BroadcastRpcResolution where
  rpcUrl : String
  anvilStarted : Bool

def resolveBroadcastRpc
    (opts : DeployOptions) (profile : ProofForge.Target.EvmChainProfile)
    (profileRpcUrl : String) : IO BroadcastRpcResolution := do
  if profile.id != "anvil-local" then
    return { rpcUrl := profileRpcUrl, anvilStarted := false }
  if ← rpcReachable? opts.castPath profileRpcUrl then
    return { rpcUrl := profileRpcUrl, anvilStarted := false }
  if !opts.startAnvil then
    throw <| IO.userError s!"RPC {profileRpcUrl} is unreachable; pass --start-anvil or --rpc-url for a running node"
  let port ← match opts.anvilPort? with
  | some port => pure port
  | none => pickAnvilPort
  let runDir := joinPath opts.root "build/anvil-deploy"
  let _ ← startAnvil opts.anvilPath opts.castPath port profile.chainId runDir
  return { rpcUrl := s!"http://127.0.0.1:{port}", anvilStarted := true }

def resolveBroadcastRpcUrl
    (opts : DeployOptions) (profile : ProofForge.Target.EvmChainProfile)
    (profileRpcUrl : String) : IO String := do
  return (← resolveBroadcastRpc opts profile profileRpcUrl).rpcUrl

def broadcastEvmDeploy (opts : DeployOptions) (profile : ProofForge.Target.EvmChainProfile)
    (info : ManifestInfo) (output : String) : IO UInt32 := do
  if !(← pathExists opts.deployManifest) then
    throw <| IO.userError s!"deploy manifest not found: {opts.deployManifest}"
  let initCodePath := resolveArtifactPath opts.root info.initCodePath
  let runtimePath := resolveArtifactPath opts.root info.runtimeBytecodePath
  if !(← pathExists initCodePath) then
    throw <| IO.userError s!"init code artifact not found: {initCodePath}"
  if !(← pathExists runtimePath) then
    throw <| IO.userError s!"runtime bytecode artifact not found: {runtimePath}"

  let profileRpcUrl ← match opts.rpcUrl? with
  | some url => pure url
  | none =>
      if profile.rpcUrls.isEmpty then
        throw <| IO.userError s!"chain profile `{profile.id}` has no rpcUrls; pass --rpc-url"
      else
        pure profile.rpcUrls[0]!

  if shouldPlanOnly profile opts then
    writeDeployPlan opts.root opts.deployManifest initCodePath runtimePath profileRpcUrl output profile
    IO.println s!"wrote deploy plan {output} for chain profile `{profile.id}`"
    IO.println "deploy: live broadcast skipped (use --broadcast with --rpc-url and --private-key to broadcast on public RPC)"
    return 0

  let privateKey ← match opts.privateKey? with
  | some key =>
      let key := trimAsciiString key
      if key.isEmpty then
        throw <| IO.userError
          "transaction broadcast requires an explicit --private-key KEY; use --plan-only to skip signing"
      pure key
  | none =>
      throw <| IO.userError
        "transaction broadcast requires an explicit --private-key KEY; use --plan-only to skip signing"
  verifySigningDeployer opts.castPath privateKey opts.deployerAddress?
  let rpcResolution ← resolveBroadcastRpc opts profile profileRpcUrl
  let rpcUrl := rpcResolution.rpcUrl
  let _ ← expectChainId opts.castPath rpcUrl profile.chainId

  if opts.gasPrice?.isSome && opts.maxFeePerGas?.isSome then
    throw <| IO.userError "--gas-price and --max-fee-per-gas are mutually exclusive; pass one or the other"

  let gasArgs : Array String := #[]
    ++ (match opts.gasLimit? with | some g => #["--gas-limit", toString g] | none => #[])
    ++ (match opts.maxFeePerGas? with
        | some fee => #["--gas-price", toString fee]
        | none =>
          match opts.gasPrice? with
          | some price => #["--gas-price", toString price]
          | none => #[])
    ++ (match opts.maxPriorityFeePerGas? with | some f => #["--priority-gas-price", toString f] | none => #[])

  let initHex ← readInitCodeHex initCodePath
  let runDir := joinPath opts.root "build/evm-deploy"
  IO.FS.createDirAll runDir
  let deployReceipt := joinPath runDir s!"{info.contractName}.cast-send.json"
  let creationTx := joinPath runDir s!"{info.contractName}.creation-transaction.json"
  let initializeReceipt := joinPath runDir s!"{info.contractName}.initialize-receipt.json"

  let receiptStdout ← runProcess opts.castPath (#[
    "send",
    "--rpc-url", rpcUrl,
    "--private-key", privateKey
  ] ++ gasArgs ++ #[
    "--create", s!"0x{initHex}",
    "--json"
  ])
  IO.FS.writeFile deployReceipt receiptStdout

  let txHash ← extractJsonField deployReceipt "transactionHash"
  let contractAddress ← extractJsonField deployReceipt "contractAddress"
  let creationStdout ← runProcess opts.castPath #["rpc", "--rpc-url", rpcUrl, "eth_getTransactionByHash", txHash]
  IO.FS.writeFile creationTx creationStdout
  let transactionFrom ← extractJsonField creationTx "from"
  let deployer ← match resolveDeployerAddress opts.deployerAddress? transactionFrom with
  | Except.ok address => pure address
  | Except.error err => throw <| IO.userError err

  let initialGet ← runProcess opts.castPath #["call", "--rpc-url", rpcUrl, contractAddress, "get()(uint256)"]
  let initializeStdout ← runProcess opts.castPath (#[
    "send",
    "--rpc-url", rpcUrl,
    "--private-key", privateKey
  ] ++ gasArgs ++ #[
    contractAddress,
    "initialize()",
    "--json"
  ])
  IO.FS.writeFile initializeReceipt initializeStdout
  let afterInitializeGet ← runProcess opts.castPath #["call", "--rpc-url", rpcUrl, contractAddress, "get()(uint256)"]
  let _ ← runProcess opts.castPath (#["send", "--rpc-url", rpcUrl, "--private-key", privateKey] ++ gasArgs ++ #[contractAddress, "increment()", "--json"])
  let afterIncrementGet ← runProcess opts.castPath #["call", "--rpc-url", rpcUrl, contractAddress, "get()(uint256)"]
  let _ ← runProcess opts.castPath (#["send", "--rpc-url", rpcUrl, "--private-key", privateKey] ++ gasArgs ++ #[contractAddress, "increment()", "--json"])
  let afterSecondIncrementGet ← runProcess opts.castPath #["call", "--rpc-url", rpcUrl, contractAddress, "get()(uint256)"]

  let deployedCode ← runProcess opts.castPath #["code", "--rpc-url", rpcUrl, contractAddress]
  let runtimeHex ← readInitCodeHex runtimePath
  let deployedBody := trimAsciiString deployedCode
  let deployedHex :=
    if deployedBody.startsWith "0x" then deployedBody.drop 2 |>.toString else deployedBody
  if trimAsciiString deployedHex != trimAsciiString runtimeHex then
    throw <| IO.userError s!"deployed runtime code does not match {runtimePath}"

  writeDeployRun
    opts.root
    opts.deployManifest
    initCodePath
    runtimePath
    rpcUrl
    profile
    rpcResolution.anvilStarted
    deployer
    deployReceipt
    creationTx
    initializeReceipt
    output
    (trimAsciiString initialGet)
    (trimAsciiString afterInitializeGet)
    (trimAsciiString afterIncrementGet)
    (trimAsciiString afterSecondIncrementGet)

  validateDeployRun opts.root output profile.id (toString profile.chainId) info.fixture

  IO.println s!"deploy: contract deployed to {contractAddress} on chain {profile.chainId}"
  IO.println s!"deploy: wrote deploy-run artifact {output}"
  return 0

def deployCommand (opts : DeployOptions) : IO UInt32 := do
  if opts.targetId != "evm" then
    throw <| IO.userError s!"deploy currently supports only --target evm, got `{opts.targetId}`"
  if opts.deployManifest.isEmpty then
    throw <| IO.userError "missing --deploy-manifest PATH"
  let info ← readManifestInfo opts.deployManifest
  let profileId ← match opts.chainProfile? with
  | some profileId => pure profileId
  | none =>
      if info.chainProfileId.isEmpty then
        throw <| IO.userError "deploy manifest has no chainProfile; pass --evm-chain-profile"
      else
        pure info.chainProfileId
  if !info.chainProfileId.isEmpty && opts.chainProfile?.isSome && info.chainProfileId != profileId then
    IO.eprintln s!"deploy: warning: manifest chain profile `{info.chainProfileId}` differs from CLI `{profileId}`"
  let profile ← resolveEvmChainProfile profileId
  let output ← match opts.output? with
  | some path => pure path
  | none =>
      if shouldPlanOnly profile opts then
        pure (defaultDeployPlanOutput opts.deployManifest)
      else
        pure (defaultDeployRunOutput opts.deployManifest)
  broadcastEvmDeploy opts profile info output

partial def parseDeployOptions (args : List String) (opts : DeployOptions := {}) : Except String DeployOptions :=
  match args with
  | [] => .ok opts
  | "--help" :: _ | "-h" :: _ => .error deployUsage
  | "--target" :: targetId :: rest => parseDeployOptions rest { opts with targetId := targetId }
  | "--target" :: [] => .error "missing value for --target"
  | "--deploy-manifest" :: path :: rest => parseDeployOptions rest { opts with deployManifest := path }
  | "--deploy-manifest" :: [] => .error "missing value for --deploy-manifest"
  | "-o" :: path :: rest => parseDeployOptions rest { opts with output? := some path }
  | "-o" :: [] => .error "missing value for -o"
  | "--output" :: path :: rest => parseDeployOptions rest { opts with output? := some path }
  | "--output" :: [] => .error "missing value for --output"
  | "--evm-chain-profile" :: profileId :: rest => parseDeployOptions rest { opts with chainProfile? := some profileId }
  | "--evm-chain-profile" :: [] => .error "missing value for --evm-chain-profile"
  | "--rpc-url" :: url :: rest => parseDeployOptions rest { opts with rpcUrl? := some url }
  | "--rpc-url" :: [] => .error "missing value for --rpc-url"
  | "--private-key" :: key :: rest => parseDeployOptions rest { opts with privateKey? := some key }
  | "--private-key" :: [] => .error "missing value for --private-key"
  | "--deployer" :: address :: rest => parseDeployOptions rest { opts with deployerAddress? := some address }
  | "--deployer" :: [] => .error "missing value for --deployer"
  | "--cast" :: path :: rest => parseDeployOptions rest { opts with castPath := path }
  | "--cast" :: [] => .error "missing value for --cast"
  | "--anvil" :: path :: rest => parseDeployOptions rest { opts with anvilPath := path }
  | "--anvil" :: [] => .error "missing value for --anvil"
  | "--start-anvil" :: rest => parseDeployOptions rest { opts with startAnvil := true }
  | "--anvil-port" :: portText :: rest =>
      match portText.toNat? with
      | some port => parseDeployOptions rest { opts with anvilPort? := some port }
      | none => .error s!"invalid --anvil-port value: {portText}"
  | "--anvil-port" :: [] => .error "missing value for --anvil-port"
  | "--broadcast" :: rest => parseDeployOptions rest { opts with broadcast := true }
  | "--plan-only" :: rest => parseDeployOptions rest { opts with planOnly := true }
  | "--gas-limit" :: gasText :: rest =>
      match gasText.toNat? with
      | some gas => parseDeployOptions rest { opts with gasLimit? := some gas }
      | none => .error s!"invalid --gas-limit value: {gasText}"
  | "--gas-limit" :: [] => .error "missing value for --gas-limit"
  | "--gas-price" :: priceText :: rest =>
      match priceText.toNat? with
      | some price => parseDeployOptions rest { opts with gasPrice? := some price }
      | none => .error s!"invalid --gas-price value: {priceText}"
  | "--gas-price" :: [] => .error "missing value for --gas-price"
  | "--max-fee-per-gas" :: feeText :: rest =>
      match feeText.toNat? with
      | some fee => parseDeployOptions rest { opts with maxFeePerGas? := some fee }
      | none => .error s!"invalid --max-fee-per-gas value: {feeText}"
  | "--max-fee-per-gas" :: [] => .error "missing value for --max-fee-per-gas"
  | "--max-priority-fee-per-gas" :: feeText :: rest =>
      match feeText.toNat? with
      | some fee => parseDeployOptions rest { opts with maxPriorityFeePerGas? := some fee }
      | none => .error s!"invalid --max-priority-fee-per-gas value: {feeText}"
  | "--max-priority-fee-per-gas" :: [] => .error "missing value for --max-priority-fee-per-gas"
  | "--root" :: root :: rest => parseDeployOptions rest { opts with root := root }
  | "--root" :: [] => .error "missing value for --root"
  | unknown :: _ => .error s!"unknown deploy option: {unknown}"

end ProofForge.Cli.Deploy

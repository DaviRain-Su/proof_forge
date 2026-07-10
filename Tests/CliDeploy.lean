import ProofForge.Cli.Deploy

namespace ProofForge.Tests.CliDeploy

def require (cond : Bool) (msg : String) : IO Unit :=
  unless cond do throw <| IO.userError msg

def captureError {alpha : Type} (action : IO alpha) : IO (Option String) := do
  try
    let _ ← action
    return none
  catch err =>
    return some (toString err)

def fixtureInfo : ProofForge.Cli.Deploy.ManifestInfo := {
  fixture := "Counter"
  contractName := "Counter"
  -- The broadcast guard must run after basic artifact existence validation but
  -- before any RPC or Anvil process. This tracked file is a harmless stand-in.
  initCodePath := "lean-toolchain"
  runtimeBytecodePath := "lean-toolchain"
  chainProfileId := "anvil-local"
  chainIdText := "31337"
}

def requireMissingExplicitKey
    (opts : ProofForge.Cli.Deploy.DeployOptions)
    (profile : ProofForge.Target.EvmChainProfile)
    (label : String) : IO Unit := do
  let error? ← captureError <|
    ProofForge.Cli.Deploy.broadcastEvmDeploy opts profile fixtureInfo "build/unused-deploy-run.json"
  match error? with
  | none => throw <| IO.userError s!"{label}: broadcast unexpectedly succeeded without --private-key"
  | some message =>
      require
        (message.contains "transaction broadcast requires an explicit --private-key KEY")
        s!"{label}: expected explicit private-key diagnostic, got: {message}"

def removeFileIfPresent (path : String) : IO Unit := do
  try
    IO.FS.removeFile path
  catch _ =>
    pure ()

def testStartAnvilDoesNotInterpretShellMetacharacters : IO Unit := do
  let marker := "build/cli-deploy-shell-injection-marker"
  removeFileIfPresent marker
  let maliciousExecutable :=
    "false; touch build/cli-deploy-shell-injection-marker; exit 7 #"
  let error? ← captureError <|
    ProofForge.Cli.Deploy.startAnvil
      maliciousExecutable "false" 1 31337 "build/cli-deploy-start-anvil-test"
  let markerCreated ← ProofForge.Cli.Deploy.pathExists marker
  removeFileIfPresent marker
  require error?.isSome
    "malicious --anvil executable path must fail to spawn"
  require (!markerCreated)
    "--anvil executable metacharacters must be passed as argv, never evaluated by a shell"

def testStartAnvilUsesConfiguredCast : IO Unit := do
  let testDir := "build/cli-deploy-configured-cast-test"
  let fakeCast := s!"{testDir}/fake-cast.sh"
  let fakeAnvil := s!"{testDir}/fake-anvil.sh"
  let state := s!"{testDir}/cast-state"
  let marker := s!"{testDir}/configured-cast-used"
  IO.FS.createDirAll testDir
  removeFileIfPresent state
  removeFileIfPresent marker
  IO.FS.writeFile fakeCast <|
    "#!/bin/sh\n" ++
    s!"if [ -f '{state}' ]; then\n" ++
    s!"  touch '{marker}'\n" ++
    "  echo 31337\n" ++
    "  exit 0\n" ++
    "fi\n" ++
    s!"touch '{state}'\n" ++
    "exit 1\n"
  IO.FS.writeFile fakeAnvil "#!/bin/sh\nsleep 2\n"
  let _ ← ProofForge.Cli.Deploy.runProcess "chmod" #["+x", fakeCast, fakeAnvil]
  let port ← ProofForge.Cli.Deploy.pickAnvilPort
  let profile ← ProofForge.Cli.Deploy.resolveEvmChainProfile "anvil-local"
  let rpcUrl := s!"http://127.0.0.1:{port}"
  let resolution ← ProofForge.Cli.Deploy.resolveBroadcastRpc {
    deployManifest := "lean-toolchain"
    castPath := fakeCast
    anvilPath := fakeAnvil
    startAnvil := true
    anvilPort? := some port
    root := "."
  } profile rpcUrl
  let configuredCastUsed ← ProofForge.Cli.Deploy.pathExists marker
  removeFileIfPresent state
  removeFileIfPresent marker
  require (resolution.rpcUrl == rpcUrl) "started Anvil RPC URL"
  require resolution.anvilStarted
    "deploy provenance must record an Anvil process started by this command"
  require configuredCastUsed
    "Anvil readiness must use the configured --cast executable"

def testPublicWriterProvenance : IO Unit := do
  let testDir := "build/cli-deploy-public-writer-test"
  let manifest := s!"{testDir}/deploy-manifest.json"
  let runtime := s!"{testDir}/runtime.bin"
  let initCode := s!"{testDir}/init.bin"
  let receipt := s!"{testDir}/receipt.json"
  let creationTx := s!"{testDir}/creation-transaction.json"
  let initializeReceipt := s!"{testDir}/initialize-receipt.json"
  let output := s!"{testDir}/deploy-run.json"
  IO.FS.createDirAll testDir
  IO.FS.writeFile runtime "00\n"
  IO.FS.writeFile initCode "6001600c60003960016000f300\n"
  let _ ← ProofForge.Cli.Deploy.runProcess "python3" #[
    "-c",
    "import hashlib,json,pathlib,sys; manifest,runtime,init_code=sys.argv[1:]; entry=lambda p:{'path':p,'sha256':hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest(),'bytes':len(pathlib.Path(p).read_bytes())}; profile={'id':'anvil-local','targetId':'evm','networkName':'Anvil Local','chainId':31337,'nativeCurrencySymbol':'ETH','rpcUrls':['http://127.0.0.1:8545'],'websocketUrls':[],'sequencerUrls':[],'notes':['test']}; data={'kind':'proof-forge-evm-deploy-manifest','fixture':'Counter','contractName':'Counter','chainProfile':profile,'deployment':{'profileId':'anvil-local','chainId':31337,'networkName':'Anvil Local','rpcUrls':['http://127.0.0.1:8545']},'abi':{'constructor':{'params':[],'encoding':'abi'}},'creation':{'constructorArgs':[]},'inputs':{'bytecode':entry(runtime),'initCode':entry(init_code)}}; pathlib.Path(manifest).write_text(json.dumps(data)+'\\n')",
    manifest, runtime, initCode
  ]
  IO.FS.writeFile receipt <|
    "{\"transactionHash\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"," ++
    "\"status\":\"0x1\",\"type\":\"0x2\"," ++
    "\"from\":\"0x1111111111111111111111111111111111111111\"," ++
    "\"to\":null,\"contractAddress\":\"0x2222222222222222222222222222222222222222\"," ++
    "\"blockHash\":\"0x2222222222222222222222222222222222222222222222222222222222222222\"," ++
    "\"blockNumber\":\"0x1\",\"gasUsed\":\"0x1\"," ++
    "\"cumulativeGasUsed\":\"0x1\",\"effectiveGasPrice\":\"0x1\"}\n"
  IO.FS.writeFile creationTx <|
    "{\"hash\":\"0x1111111111111111111111111111111111111111111111111111111111111111\"," ++
    "\"from\":\"0x1111111111111111111111111111111111111111\"," ++
    "\"to\":null," ++
    "\"blockHash\":\"0x2222222222222222222222222222222222222222222222222222222222222222\"," ++
    "\"blockNumber\":\"0x1\"," ++
    "\"input\":\"0x6001600c60003960016000f300\"}\n"
  IO.FS.writeFile initializeReceipt "{\"status\":\"0x1\"}\n"
  let profile ← ProofForge.Cli.Deploy.resolveEvmChainProfile "robinhood-chain-testnet"
  ProofForge.Cli.Deploy.writeDeployRun
    "." manifest initCode runtime
    "https://rpc.testnet.chain.robinhood.com"
    profile false
    "0x1111111111111111111111111111111111111111"
    receipt creationTx initializeReceipt output
    "0" "0" "1" "2"
  let provenance ← ProofForge.Cli.Deploy.runProcess "python3" #[
    "-c",
    "import json,sys; d=json.load(open(sys.argv[1])); print(d['chainProfile']['id'] + ':' + str(d['chainProfile']['chainId']) + '=' + d['network']['kind'] + '=' + d['validation']['anvilStarted'])",
    output
  ]
  require
    (ProofForge.Cli.HexUtil.trimAsciiString provenance ==
      "robinhood-chain-testnet:46630=chain-profile=skipped")
    "public deploy-run must record the resolved override profile and skipped Anvil startup"
  ProofForge.Cli.Deploy.validateDeployRun
    "." output "robinhood-chain-testnet" "46630" "Counter"

def testPlanWriterProfileOverride : IO Unit := do
  let testDir := "build/cli-deploy-plan-profile-override-test"
  let manifest := s!"{testDir}/deploy-manifest.json"
  let runtime := s!"{testDir}/runtime.bin"
  let initCode := s!"{testDir}/init.bin"
  let output := s!"{testDir}/deploy-plan.json"
  IO.FS.createDirAll testDir
  IO.FS.writeFile manifest <|
    "{\"kind\":\"proof-forge-evm-deploy-manifest\"," ++
    "\"fixture\":\"Counter\",\"contractName\":\"Counter\"," ++
    "\"chainProfile\":{\"id\":\"anvil-local\"}," ++
    "\"abi\":{\"constructor\":[]},\"creation\":{\"constructorArgs\":[]}}\n"
  IO.FS.writeFile runtime "00\n"
  IO.FS.writeFile initCode "00\n"
  let profile ← ProofForge.Cli.Deploy.resolveEvmChainProfile "robinhood-chain-testnet"
  ProofForge.Cli.Deploy.writeDeployPlan
    "." manifest initCode runtime
    "https://rpc.testnet.chain.robinhood.com" output profile
  let provenance ← ProofForge.Cli.Deploy.runProcess "python3" #[
    "-c",
    "import json,sys; d=json.load(open(sys.argv[1])); print(d['chainProfile']['id'] + ':' + str(d['chainProfile']['chainId']) + '=' + str(d['network']['chainId']))",
    output
  ]
  require
    (ProofForge.Cli.HexUtil.trimAsciiString provenance ==
      "robinhood-chain-testnet:46630=46630")
    "deploy plan must record the resolved override profile, not the manifest profile"

def testDeployerMismatchStopsBeforeBroadcast : IO Unit := do
  let testDir := "build/cli-deploy-deployer-preflight-test"
  let fakeCast := s!"{testDir}/fake-cast.sh"
  let sendMarker := s!"{testDir}/send-called"
  IO.FS.createDirAll testDir
  removeFileIfPresent sendMarker
  IO.FS.writeFile fakeCast <|
    "#!/bin/sh\n" ++
    "if [ \"$1\" = wallet ]; then\n" ++
    "  echo 0x1111111111111111111111111111111111111111\n" ++
    "  exit 0\n" ++
    "fi\n" ++
    "if [ \"$1\" = send ]; then\n" ++
    s!"  touch '{sendMarker}'\n" ++
    "fi\n" ++
    "exit 7\n"
  let _ ← ProofForge.Cli.Deploy.runProcess "chmod" #["+x", fakeCast]
  let profile ← ProofForge.Cli.Deploy.resolveEvmChainProfile "robinhood-chain-testnet"
  let error? ← captureError <|
    ProofForge.Cli.Deploy.broadcastEvmDeploy {
      deployManifest := "lean-toolchain"
      chainProfile? := some "robinhood-chain-testnet"
      rpcUrl? := some "https://example.invalid"
      privateKey? := some "opaque-test-key"
      deployerAddress? := some "0x2222222222222222222222222222222222222222"
      castPath := fakeCast
      broadcast := true
    } profile fixtureInfo "build/unused-deploy-run.json"
  let sendCalled ← ProofForge.Cli.Deploy.pathExists sendMarker
  removeFileIfPresent sendMarker
  match error? with
  | none => throw <| IO.userError "mismatched --deployer unexpectedly broadcast"
  | some message =>
      require (message.contains "does not match signing key address")
        s!"unexpected pre-broadcast deployer diagnostic: {message}"
  require (!sendCalled)
    "mismatched --deployer must fail before any cast send invocation"

def testDeployerResolution : IO Unit := do
  let actual := "  0xA111111111111111111111111111111111111111  "
  let normalized := "0xa111111111111111111111111111111111111111"
  match ProofForge.Cli.Deploy.resolveDeployerAddress none actual with
  | Except.ok address =>
      require (address == normalized)
        "deployer metadata must be derived and normalized from creation transaction.from"
  | Except.error err => throw <| IO.userError err
  match ProofForge.Cli.Deploy.resolveDeployerAddress
      (some "A111111111111111111111111111111111111111") actual with
  | Except.ok address =>
      require (address == normalized)
        "matching explicit --deployer must normalize to creation transaction.from"
  | Except.error err => throw <| IO.userError err
  match ProofForge.Cli.Deploy.resolveDeployerAddress
      (some "0xb222222222222222222222222222222222222222") actual with
  | Except.ok _ =>
      throw <| IO.userError "mismatched --deployer must not override creation transaction.from"
  | Except.error err =>
      require (err.contains "does not match creation transaction sender")
        s!"unexpected deployer mismatch diagnostic: {err}"
  match ProofForge.Cli.Deploy.resolveDeployerAddress none "not-an-address" with
  | Except.ok _ => throw <| IO.userError "malformed creation transaction.from must be rejected"
  | Except.error err =>
      require (err.contains "creation transaction sender")
        s!"unexpected malformed sender diagnostic: {err}"

def testNetworkKindFromProfile : IO Unit := do
  let localProfile ← ProofForge.Cli.Deploy.resolveEvmChainProfile "anvil-local"
  let publicProfile ← ProofForge.Cli.Deploy.resolveEvmChainProfile "robinhood-chain-testnet"
  require (ProofForge.Cli.Deploy.deployNetworkKind localProfile == "anvil")
    "anvil-local deploy-run network kind"
  require (ProofForge.Cli.Deploy.deployNetworkKind publicProfile == "chain-profile")
    "public profile deploy-run must not claim Anvil"
  let publicResolution ← ProofForge.Cli.Deploy.resolveBroadcastRpc {}
    publicProfile "https://rpc.testnet.chain.robinhood.com"
  require (!publicResolution.anvilStarted)
    "public profile broadcast must not report Anvil startup"
  let existingLocalResolution ← ProofForge.Cli.Deploy.resolveBroadcastRpc {
    castPath := "true"
    anvilPath := "false"
    startAnvil := true
  } localProfile "http://127.0.0.1:1"
  require (!existingLocalResolution.anvilStarted)
    "reachable local RPC must not report an Anvil process started by this command"

def main : IO UInt32 := do
  require
    (ProofForge.Cli.Deploy.deployUsage.contains
      "--private-key KEY       signing key for transaction broadcast (required; no default)")
    "deploy usage must mark --private-key as required with no default"
  require
    (!(ProofForge.Cli.Deploy.deployUsage.contains "default: Anvil test key"))
    "deploy usage must not advertise an implicit signing key"

  match ProofForge.Cli.Deploy.parseDeployOptions [
    "--target", "evm",
    "--deploy-manifest", "build/evm/Counter.proof-forge-deploy.json",
    "--evm-chain-profile", "anvil-local",
    "--start-anvil",
    "--root", "."
  ] with
  | Except.ok opts =>
      require (opts.targetId == "evm") "target parse"
      require (opts.deployManifest.endsWith "Counter.proof-forge-deploy.json") "manifest parse"
      require (opts.chainProfile? == some "anvil-local") "chain profile parse"
      require opts.startAnvil "start-anvil parse"
      require opts.privateKey?.isNone "parser must not synthesize a signing key"
  | Except.error err => throw <| IO.userError err

  match ProofForge.Cli.Deploy.parseDeployOptions [
    "--target", "evm",
    "--deploy-manifest", "build/evm/Counter.proof-forge-deploy.json",
    "--evm-chain-profile", "anvil-local",
    "--start-anvil",
    "--private-key", "test-only-explicit-key"
  ] with
  | Except.ok opts =>
      require (opts.privateKey? == some "test-only-explicit-key")
        "explicit private key parse"
  | Except.error err => throw <| IO.userError err

  match ProofForge.Cli.Deploy.parseDeployOptions [
    "--target", "evm",
    "--deploy-manifest", "build/evm/Counter.proof-forge-deploy.json",
    "--evm-chain-profile", "robinhood-chain-testnet",
    "--plan-only"
  ] with
  | Except.ok opts =>
      require opts.planOnly "plan-only parse"
      require (ProofForge.Cli.Deploy.shouldPlanOnly (← ProofForge.Cli.Deploy.resolveEvmChainProfile "robinhood-chain-testnet") opts)
        "testnet defaults to plan-only"
  | Except.error err => throw <| IO.userError err

  require (ProofForge.Cli.Deploy.defaultDeployRunOutput "build/evm/Counter.proof-forge-deploy.json"
    == "build/evm/Counter.proof-forge-deploy-run.json") "deploy-run default output"
  require (ProofForge.Cli.Deploy.defaultDeployPlanOutput "build/evm/Counter.proof-forge-deploy.json"
    == "build/evm/Counter.proof-forge-deploy-plan.json") "deploy-plan default output"

  let publicProfile ← ProofForge.Cli.Deploy.resolveEvmChainProfile "robinhood-chain-testnet"
  requireMissingExplicitKey {
    deployManifest := "lean-toolchain"
    chainProfile? := some "robinhood-chain-testnet"
    broadcast := true
    rpcUrl? := some "http://127.0.0.1:1"
    castPath := "false"
  } publicProfile "public-profile broadcast"

  let anvilProfile ← ProofForge.Cli.Deploy.resolveEvmChainProfile "anvil-local"
  requireMissingExplicitKey {
    deployManifest := "lean-toolchain"
    chainProfile? := some "anvil-local"
    startAnvil := true
    -- Vulnerable behavior proceeds to this command using a built-in Anvil
    -- key; fixed behavior must reject before invoking it.
    castPath := "true"
  } anvilProfile "start-anvil broadcast"

  testStartAnvilDoesNotInterpretShellMetacharacters
  testDeployerResolution
  testNetworkKindFromProfile
  testPublicWriterProvenance
  testPlanWriterProfileOverride
  testDeployerMismatchStopsBeforeBroadcast
  testStartAnvilUsesConfiguredCast

  IO.println "CliDeploy: ok"
  return 0

end ProofForge.Tests.CliDeploy

def main : IO UInt32 :=
  ProofForge.Tests.CliDeploy.main

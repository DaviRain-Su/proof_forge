import ProofForge.Cli.Deploy

namespace ProofForge.Tests.CliDeploy

def require (cond : Bool) (msg : String) : IO Unit :=
  unless cond do throw <| IO.userError msg

def main : IO UInt32 := do
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

  IO.println "CliDeploy: ok"
  return 0

end ProofForge.Tests.CliDeploy

def main : IO UInt32 :=
  ProofForge.Tests.CliDeploy.main

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

  match ProofForge.Cli.Deploy.parseDeployOptions [
    "--target", "evm",
    "--deploy-manifest", "build/evm/Counter.proof-forge-deploy.json",
    "--private-key", "0x1234"
  ] with
  | Except.ok opts => do
      let key ← ProofForge.Cli.Deploy.resolvePrivateKey opts
      require (key == "0x1234") "explicit private key resolution"
  | Except.error err => throw <| IO.userError err

  if (← IO.getEnv "PROOF_FORGE_DEPLOY_PRIVATE_KEY").isNone then
    try
      let _ ← ProofForge.Cli.Deploy.resolvePrivateKey {
        targetId := "evm",
        deployManifest := "build/evm/Counter.proof-forge-deploy.json"
      }
      require false "missing private key should error"
    catch e =>
      require (e.toString == "deploy requires --private-key KEY or the PROOF_FORGE_DEPLOY_PRIVATE_KEY environment variable")
        "missing private key error message"
  else
    pure ()

  match ProofForge.Cli.Deploy.parseDeployOptions [
    "--target", "evm",
    "--deploy-manifest", "build/evm/Counter.proof-forge-deploy.json",
    "--private-key", ""
  ] with
  | Except.ok emptyKeyOpts => do
      try
        let _ ← ProofForge.Cli.Deploy.resolvePrivateKey emptyKeyOpts
        require false "empty --private-key should error"
      catch e =>
        require (e.toString == "--private-key value is empty") "empty --private-key error message"
  | Except.error err => throw <| IO.userError err

  match ← IO.getEnv "PROOF_FORGE_DEPLOY_PRIVATE_KEY" with
  | some envKey =>
      if envKey.isEmpty then
        try
          let _ ← ProofForge.Cli.Deploy.resolvePrivateKey {
            targetId := "evm",
            deployManifest := "build/evm/Counter.proof-forge-deploy.json"
          }
          require false "empty env var should error"
        catch e =>
          require (e.toString == "PROOF_FORGE_DEPLOY_PRIVATE_KEY is set but empty") "empty env var error message"
      else
        match ProofForge.Cli.Deploy.parseDeployOptions [
          "--target", "evm",
          "--deploy-manifest", "build/evm/Counter.proof-forge-deploy.json"
        ] with
        | Except.ok opts => do
            let key ← ProofForge.Cli.Deploy.resolvePrivateKey opts
            require (key == envKey) "env var private key resolution"
        | Except.error err => throw <| IO.userError err
  | none =>
      pure ()

  -- Empty PROOF_FORGE_DEPLOY_PRIVATE_KEY env var is exercised in a subprocess
  -- because Lean cannot modify the current process environment at runtime.
  let emptyEnvTestPath := "build/cli-deploy-empty-env-test.lean"
  let emptyEnvSnippet := String.intercalate "\n" [
    "import ProofForge.Cli.Deploy",
    "",
    "def main : IO UInt32 := do",
    "  match ProofForge.Cli.Deploy.parseDeployOptions [",
    "    \"--target\", \"evm\",",
    "    \"--deploy-manifest\", \"build/evm/Counter.proof-forge-deploy.json\"",
    "  ] with",
    "  | Except.ok opts => do",
    "      try",
    "        let _ ← ProofForge.Cli.Deploy.resolvePrivateKey opts",
    "        IO.eprintln \"empty env var should error\"",
    "        return 1",
    "      catch e =>",
    "        if e.toString == \"PROOF_FORGE_DEPLOY_PRIVATE_KEY is set but empty\" then",
    "          IO.println \"CliDeploy empty env: ok\"",
    "          return 0",
    "        else",
    "          IO.eprintln s!\"unexpected error: {e.toString}\"",
    "          return 1",
    "  | Except.error err => do",
    "      IO.eprintln err",
    "      return 1"
  ]
  IO.FS.writeFile emptyEnvTestPath emptyEnvSnippet
  let emptyEnvOut ← IO.Process.output {
    cmd := "lake",
    args := #["env", "lean", "--run", emptyEnvTestPath],
    env := #[("PROOF_FORGE_DEPLOY_PRIVATE_KEY", some "")]
  }
  if emptyEnvOut.exitCode != 0 then
    IO.eprintln emptyEnvOut.stderr
    require false "empty env var private key resolution (subprocess)"
  else
    require (emptyEnvOut.stdout.trimAscii.toString == "CliDeploy empty env: ok") "empty env var subprocess output"

  IO.println "CliDeploy: ok"
  return 0

end ProofForge.Tests.CliDeploy

def main : IO UInt32 :=
  ProofForge.Tests.CliDeploy.main

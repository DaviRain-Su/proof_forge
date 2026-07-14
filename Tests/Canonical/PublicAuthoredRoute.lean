import Examples.Product.Counter
import ProofForge.Cli.ContractLoader
import ProofForge.Frontend.Authored

namespace ProofForge.Tests.Canonical.PublicAuthoredRoute

open Lean
open ProofForge.Frontend.Authored

def publicCounter : AuthoredContract :=
  Examples.Product.Counter.contract

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

unsafe def run : IO Unit := do
  let input := System.FilePath.mk "Examples/Product/Counter.lean"
  let (env, modName) <- ProofForge.Cli.ContractLoader.runTrustedLocalFrontend
    input (some (System.FilePath.mk ".")) none
  require (env.constants.contains (modName ++ `contract))
    "public Counter does not export contract : AuthoredContract"
  require (!(env.constants.contains (modName ++ `spec)))
    "public Counter still exports the retired ContractSpec source"
  require (!(env.constants.contains (modName ++ `module)))
    "public Counter still exports the retired IR.Module source"
  match <- ProofForge.Cli.ContractLoader.loadSourceFromEnv env modName with
  | .authored contract =>
      require (contract.name == publicCounter.name)
        "Loader changed the direct authored contract identity"
  | .surfaceFixture _ =>
      throw <| IO.userError "public Counter was loaded as an internal Surface fixture"
  IO.println "public-authored-route: ok"

end ProofForge.Tests.Canonical.PublicAuthoredRoute

unsafe def main : IO Unit :=
  ProofForge.Tests.Canonical.PublicAuthoredRoute.run

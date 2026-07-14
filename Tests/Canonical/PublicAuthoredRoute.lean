import Examples.Product.Counter
import Examples.Product.Ownable
import Examples.Product.Pausable
import Examples.Product.ValueVault
import ProofForge.Cli.ContractLoader
import ProofForge.Frontend.Authored

namespace ProofForge.Tests.Canonical.PublicAuthoredRoute

open Lean
open ProofForge.Frontend.Authored

def publicCounter : AuthoredContract :=
  Examples.Product.Counter.contract

def publicValueVault : AuthoredContract :=
  Examples.Product.ValueVault.contract

def publicOwnable : AuthoredContract :=
  Examples.Product.Ownable.contract

def publicPausable : AuthoredContract :=
  Examples.Product.Pausable.contract

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
  let vaultInput := System.FilePath.mk "Examples/Product/ValueVault.lean"
  let (vaultEnv, vaultModName) <- ProofForge.Cli.ContractLoader.runTrustedLocalFrontend
    vaultInput (some (System.FilePath.mk ".")) none
  require (vaultEnv.constants.contains (vaultModName ++ `contract))
    "public ValueVault does not export contract : AuthoredContract"
  require (!(vaultEnv.constants.contains (vaultModName ++ `spec)))
    "public ValueVault still exports the retired ContractSpec source"
  require (!(vaultEnv.constants.contains (vaultModName ++ `module)))
    "public ValueVault still exports the retired IR.Module source"
  match <- ProofForge.Cli.ContractLoader.loadSourceFromEnv vaultEnv vaultModName with
  | .authored contract =>
      require (contract.name == publicValueVault.name)
        "Loader changed the direct authored ValueVault identity"
  | .surfaceFixture _ =>
      throw <| IO.userError "public ValueVault was loaded as an internal Surface fixture"
  let ownableInput := System.FilePath.mk "Examples/Product/Ownable.lean"
  let (ownableEnv, ownableModName) <- ProofForge.Cli.ContractLoader.runTrustedLocalFrontend
    ownableInput (some (System.FilePath.mk ".")) none
  require (ownableEnv.constants.contains (ownableModName ++ `contract))
    "public Ownable does not export contract : AuthoredContract"
  require (!(ownableEnv.constants.contains (ownableModName ++ `spec)))
    "public Ownable still exports the retired ContractSpec source"
  require (!(ownableEnv.constants.contains (ownableModName ++ `module)))
    "public Ownable still exports the retired IR.Module source"
  match <- ProofForge.Cli.ContractLoader.loadSourceFromEnv ownableEnv ownableModName with
  | .authored contract =>
      require (contract.name == publicOwnable.name)
        "Loader changed the direct authored Ownable identity"
  | .surfaceFixture _ =>
      throw <| IO.userError "public Ownable was loaded as an internal Surface fixture"
  let pausableInput := System.FilePath.mk "Examples/Product/Pausable.lean"
  let (pausableEnv, pausableModName) <- ProofForge.Cli.ContractLoader.runTrustedLocalFrontend
    pausableInput (some (System.FilePath.mk ".")) none
  require (pausableEnv.constants.contains (pausableModName ++ `contract))
    "public Pausable does not export contract : AuthoredContract"
  require (!(pausableEnv.constants.contains (pausableModName ++ `spec)))
    "public Pausable still exports the retired ContractSpec source"
  require (!(pausableEnv.constants.contains (pausableModName ++ `module)))
    "public Pausable still exports the retired IR.Module source"
  match <- ProofForge.Cli.ContractLoader.loadSourceFromEnv pausableEnv pausableModName with
  | .authored contract =>
      require (contract.name == publicPausable.name)
        "Loader changed the direct authored Pausable identity"
  | .surfaceFixture _ =>
      throw <| IO.userError "public Pausable was loaded as an internal Surface fixture"
  IO.println "public-authored-route: ok"

end ProofForge.Tests.Canonical.PublicAuthoredRoute

unsafe def main : IO Unit :=
  ProofForge.Tests.Canonical.PublicAuthoredRoute.run

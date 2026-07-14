import ProofForge.Cli.ContractLoader
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Contract.Source
import ProofForge.Contract.SdkSchema

/-! Source loading tests retained while the single authoring frontend is cut over. -/

open ProofForge.Compiler
open ProofForge.Cli.ContractLoader

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

unsafe def load (path : String) : IO ProofForge.Compiler.LoadedContractSource :=
  loadSource path (some ".") none

unsafe def expectLoadError (path expected : String) : IO Unit := do
  try
    let _ ← load path
    throw <| IO.userError s!"{path}: expected `{expected}`"
  catch error =>
    unless error.toString.contains expected do
      throw <| IO.userError s!"{path}: wrong diagnostic: {error}"

def canonicalize (source : ProofForge.Compiler.LoadedContractSource) : IO ProofForge.IR.Canonical.CanonicalBundle :=
  match source.toCanonical .canonical with
  | Except.ok bundle => pure bundle
  | Except.error diagnostic => throw <| IO.userError diagnostic.message

def withoutResolvedSelectors
    (interface : ProofForge.IR.Canonical.InterfaceContract) :
    ProofForge.IR.Canonical.InterfaceContract :=
  { interface with
    entrypoints := interface.entrypoints.map fun entrypoint =>
      { entrypoint with selector? := none } }

unsafe def main : IO Unit := do
  let authoredCounter ← load "Examples/Product/Counter.lean"
  match authoredCounter with
  | .authored _ => pure ()
  | .surfaceFixture _ => throw <| IO.userError "authored Counter discovered as an internal Surface fixture"

  let surfaceCounter ← load "TestFixtures/SurfaceProducts/Counter.lean"
  match surfaceCounter with
  | .surfaceFixture _ => pure ()
  | .authored _ => throw <| IO.userError "internal Surface Counter discovered as an authored source"

  let authoredBundle ← canonicalize authoredCounter
  let surfaceBundle ← canonicalize surfaceCounter
  require (authoredBundle.contract.contract.module == surfaceBundle.contract.contract.module)
    "Counter Core module differs between product source and internal Surface fixture"
  require
      (withoutResolvedSelectors authoredBundle.contract.contract.interface ==
        withoutResolvedSelectors surfaceBundle.contract.contract.interface)
    "Counter interface shape differs between product source and internal Surface fixture"
  match surfaceCounter.toCanonical .legacy with
  | Except.error diagnostic =>
      require (diagnostic.message.contains "cannot request the Legacy pipeline")
        "wrong Surface fixture/Legacy diagnostic"
  | Except.ok _ => throw <| IO.userError "Surface fixture accepted the Legacy pipeline"

  let authoredVault ← load "Examples/Product/ValueVault.lean"
  match authoredVault with
  | .authored _ => pure ()
  | .surfaceFixture _ => throw <| IO.userError "authored ValueVault discovered as an internal Surface fixture"
  let authoredVaultBundle ← canonicalize authoredVault
  let surfaceVault ← canonicalize (← load "TestFixtures/SurfaceProducts/ValueVault.lean")
  require (surfaceVault.contract.contract.module.state.size == 6) "Surface ValueVault state drift"
  require (surfaceVault.contract.contract.module.functions.size == 7) "Surface ValueVault entrypoint drift"
  require (surfaceVault.contract.contract.module.events.size == 5) "Surface ValueVault event drift"
  require
      (authoredVaultBundle.contract.contract.module == surfaceVault.contract.contract.module)
    "ValueVault Core module differs between product source and internal Surface fixture"
  require
      (withoutResolvedSelectors authoredVaultBundle.contract.contract.interface ==
        withoutResolvedSelectors surfaceVault.contract.contract.interface)
    "ValueVault interface shape differs between product source and internal Surface fixture"

  let authoredOwnable <- load "Examples/Product/Ownable.lean"
  match authoredOwnable with
  | .authored _ => pure ()
  | .surfaceFixture _ =>
      throw (IO.userError "authored Ownable discovered as an internal Surface fixture")
  let authoredOwnableBundle <- canonicalize authoredOwnable
  require (authoredOwnableBundle.contract.contract.module.state.size == 2)
    "Authored Ownable state drift"
  require (authoredOwnableBundle.contract.contract.module.functions.size == 4)
    "Authored Ownable entrypoint drift"
  require (authoredOwnableBundle.contract.contract.module.events.size == 1)
    "Authored Ownable event drift"

  let authoredPausable <- load "Examples/Product/Pausable.lean"
  match authoredPausable with
  | .authored _ => pure ()
  | .surfaceFixture _ =>
      throw (IO.userError "authored Pausable discovered as an internal Surface fixture")
  let authoredPausableBundle <- canonicalize authoredPausable
  require (authoredPausableBundle.contract.contract.module.state.size == 1)
    "Authored Pausable state drift"
  require (authoredPausableBundle.contract.contract.module.functions.size == 3)
    "Authored Pausable entrypoint drift"
  require (authoredPausableBundle.contract.contract.module.events.isEmpty)
    "Authored Pausable event drift"

  let authoredGuard <- load "Examples/Product/ReentrancyGuard.lean"
  match authoredGuard with
  | .authored _ => pure ()
  | .surfaceFixture _ =>
      throw (IO.userError "authored ReentrancyGuard discovered as an internal Surface fixture")
  let authoredGuardBundle <- canonicalize authoredGuard
  require (authoredGuardBundle.contract.contract.module.state.size == 1)
    "Authored ReentrancyGuard state drift"
  require (authoredGuardBundle.contract.contract.module.functions.size == 3)
    "Authored ReentrancyGuard entrypoint drift"
  require (authoredGuardBundle.contract.contract.module.events.isEmpty)
    "Authored ReentrancyGuard event drift"

  let fixtureDir := "build/canonical/source-loader"
  IO.FS.createDirAll fixtureDir
  let ambiguousPath := fixtureDir ++ "/Ambiguous.lean"
  IO.FS.writeFile ambiguousPath <|
    "import ProofForge.Frontend.Authored\n" ++
    "import ProofForge.Frontend.Surface\n" ++
    "import Examples.Product.Counter\n" ++
    "import TestFixtures.SurfaceProducts.Counter\n" ++
    "def contract : ProofForge.Frontend.Authored.AuthoredContract := Examples.Product.Counter.contract\n" ++
    "def surfaceFixture : ProofForge.Frontend.Surface.SurfaceContract := TestFixtures.SurfaceProducts.Counter.surfaceFixture\n"
  let missingPath := fixtureDir ++ "/Missing.lean"
  IO.FS.writeFile missingPath "def marker : Nat := 1\n"
  expectLoadError ambiguousPath "ambiguousContractSource"
  expectLoadError missingPath "missingContractSource"

  require (ProofForge.Contract.SdkSchema.sourceVersion == "contract-source") "SDK source identity"
  require (ProofForge.Contract.Source.sourceDslVersion == "contract-source") "Source identity"

  IO.println "source-loader: ok"

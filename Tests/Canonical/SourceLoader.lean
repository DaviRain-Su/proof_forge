import ProofForge.Cli.ContractLoader
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Contract.Source
import ProofForge.Contract.SdkSchema

/-! Task 14 end-to-end versioned source loading tests. -/

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

unsafe def main : IO Unit := do
  let legacyCounter ← load "Examples/Product/Counter.lean"
  match legacyCounter with
  | .legacyV1 _ => pure ()
  | .surfaceV2 _ => throw <| IO.userError "legacy Counter discovered as Surface v2"

  let surfaceCounter ← load "Examples/Product/Canonical/Counter.lean"
  match surfaceCounter with
  | .surfaceV2 _ => pure ()
  | .legacyV1 _ => throw <| IO.userError "canonical Counter discovered as Legacy v1"

  let legacyBundle ← canonicalize legacyCounter
  let surfaceBundle ← canonicalize surfaceCounter
  require (legacyBundle.contract == surfaceBundle.contract)
    s!"v1 and v2 Counter checked canonical contracts differ:\nlegacy={repr legacyBundle.contract.contract}\nsurface={repr surfaceBundle.contract.contract}"
  match surfaceCounter.toCanonical .legacy with
  | Except.error diagnostic =>
      require (diagnostic.message.contains "cannot request the Legacy pipeline")
        "wrong Surface-v2/Legacy diagnostic"
  | Except.ok _ => throw <| IO.userError "Surface v2 accepted the Legacy pipeline"

  let legacyVault ← canonicalize (← load "Examples/Product/ValueVault.lean")
  let surfaceVault ← canonicalize (← load "Examples/Product/Canonical/ValueVault.lean")
  require (surfaceVault.contract.contract.module.state.size == 6) "Surface ValueVault state drift"
  require (surfaceVault.contract.contract.module.functions.size == 7) "Surface ValueVault entrypoint drift"
  require (surfaceVault.contract.contract.module.events.size == 5) "Surface ValueVault event drift"
  require (legacyVault.contract.contract.module == surfaceVault.contract.contract.module)
    s!"Surface ValueVault Core module differs from product ValueVault:\nlegacy={repr legacyVault.contract.contract.module}\nsurface={repr surfaceVault.contract.contract.module}"
  require (legacyVault.contract.contract.interface == surfaceVault.contract.contract.interface)
    "Surface ValueVault interface differs from product ValueVault"

  let fixtureDir := "build/canonical/source-loader"
  IO.FS.createDirAll fixtureDir
  let ambiguousPath := fixtureDir ++ "/Ambiguous.lean"
  IO.FS.writeFile ambiguousPath <|
    "import ProofForge.Contract.Spec\n" ++
    "import ProofForge.IR.Examples.Counter\n" ++
    "import Examples.Product.Canonical.Counter\n" ++
    "def spec : ProofForge.Contract.ContractSpec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module\n" ++
    "def contract := Examples.Product.Canonical.Counter.contract\n"
  let missingPath := fixtureDir ++ "/Missing.lean"
  IO.FS.writeFile missingPath "def marker : Nat := 1\n"
  expectLoadError ambiguousPath "ambiguousContractSource"
  expectLoadError missingPath "missingContractSource"

  require (ProofForge.Contract.SdkSchema.sourceVersionV1 == "contract_source-v1") "SDK v1 version"
  require (ProofForge.Contract.SdkSchema.sourceVersionV2 == "contract_source-v2") "SDK v2 version"
  require (ProofForge.Contract.Source.sourceDslVersion == "contract_source-v1") "Source v1 version"
  require (ProofForge.Contract.Source.sourceSurfaceVersion == "contract_source-v2") "Source v2 version"

  IO.println "source-loader: ok"

import ProofForge.Backend.Solana.Package
import ProofForge.Cli.ContractLoader
import ProofForge.Contract.Examples.Counter
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Learn
import ProofForge.Frontend.Authored.Canonicalize

namespace ProofForge.Tests.SharedContractSource

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireExcept {α : Type} (label : String) : Except String α → IO α
  | .ok value => pure value
  | .error err => throw <| IO.userError s!"{label}: {err}"

def reprModule (module : ProofForge.IR.Module) : String :=
  toString (repr module)

def requireSameModule (label : String)
    (actual expected : ProofForge.IR.Module) : IO Unit := do
  let actualRepr := reprModule actual
  let expectedRepr := reprModule expected
  require (actualRepr == expectedRepr)
    s!"{label} module mismatch\nactual:\n{actualRepr}\nexpected:\n{expectedRepr}"

def requireSameText (label actual expected : String) : IO Unit :=
  require (actual == expected)
    s!"{label} mismatch\nactual:\n{actual}\nexpected:\n{expected}"

def requireSameAnnotations (label : String)
    (actual expected : Array (String × String)) : IO Unit :=
  require (actual == expected)
    s!"{label} annotations mismatch\nactual:\n{actual}\nexpected:\n{expected}"

def parseLearnSpec (path : System.FilePath) : IO ProofForge.Contract.ContractSpec := do
  requireExcept s!"parse/lower {path}" (← ProofForge.Contract.Learn.parseAndLowerFile path)

unsafe def loadSharedSpec (path : System.FilePath) : IO ProofForge.Contract.ContractSpec :=
  ProofForge.Cli.ContractLoader.loadSpec path (some (System.FilePath.mk ".")) none

def packageFile (label path : String)
    (spec : ProofForge.Contract.ContractSpec) : IO String := do
  match ProofForge.Backend.Solana.Package.renderPackageForSpec label spec with
  | .ok pkg =>
      let some file := pkg.files.find? (fun file => file.path == path)
        | throw <| IO.userError s!"{label} package missing {path}"
      pure file.contents
  | .error err =>
      throw <| IO.userError s!"{label} Solana render failed: {err.render}"

unsafe def requireCounterDirectSource : IO Unit := do
  let source ← ProofForge.Cli.ContractLoader.loadSource
    "Examples/Product/Counter.lean" (some ".") none
  let contract ← match source with
    | .authored contract => pure contract
    | .surfaceFixture _ =>
        throw <| IO.userError "Product Counter loaded as an internal Surface fixture"
  require (contract.name == ProofForge.Contract.Examples.Counter.contract.name)
    "direct Counter contract identity mismatch"
  require (contract.quintInvariants.any (fun annotation =>
      annotation.name == "countBounded" && annotation.body == "count <= MAX_UINT"))
    "direct Counter lost countBounded quint_invariant"
  require (contract.quintLiveness.any (fun annotation =>
      annotation.name == "eventuallyPositive" && annotation.body == "eventually(count > 0)"))
    "direct Counter lost eventuallyPositive quint_liveness"
  let bundle ← match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"direct Counter normalization failed: {repr error}"
  require (bundle.contract.contract.module.state.size == 1)
    "direct Counter Canonical Core state drift"
  require (bundle.contract.contract.module.functions.size == 3)
    "direct Counter Canonical Core entrypoint drift"

unsafe def requireValueVaultEquivalence : IO Unit := do
  let shared ← loadSharedSpec "Examples/Product/ValueVault.lean"
  let learn ← parseLearnSpec "Examples/Backend/Learn/ValueVault.learn"
  requireSameModule "Shared ValueVault vs canonical contract_source"
    shared.module ProofForge.Contract.Examples.ValueVault.module
  requireSameAnnotations "Shared ValueVault vs canonical quint_invariant"
    shared.quintInvariants ProofForge.Contract.Examples.ValueVault.spec.quintInvariants
  requireSameModule "Legacy Learn ValueVault vs shared contract_source"
    learn.module shared.module
  let sharedManifest ← packageFile "shared-value-vault" "manifest.toml" shared
  let learnManifest ← packageFile "learn-value-vault" "manifest.toml" learn
  requireSameText "ValueVault Solana manifest shared-vs-learn" sharedManifest learnManifest

unsafe def main : IO UInt32 := do
  requireCounterDirectSource
  requireValueVaultEquivalence
  IO.println "shared-contract-source: ok"
  return 0

end ProofForge.Tests.SharedContractSource

unsafe def main : IO UInt32 :=
  ProofForge.Tests.SharedContractSource.main

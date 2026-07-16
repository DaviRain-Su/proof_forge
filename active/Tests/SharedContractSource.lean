import ProofForge.Backend.Solana.Package
import ProofForge.Cli.ContractLoader
import ProofForge.Contract.Examples.Counter
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Learn

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

unsafe def requireCounterEquivalence : IO Unit := do
  let shared ← loadSharedSpec "Examples/Product/Counter.lean"
  let evm ← loadSharedSpec "Examples/Backend/Evm/Contracts/Counter.lean"
  let solana ← loadSharedSpec "Examples/Backend/Solana/Counter.lean"
  let learn ← parseLearnSpec "Examples/Backend/Learn/Counter.learn"
  requireSameModule "Shared Counter vs canonical contract_source"
    shared.module ProofForge.Contract.Examples.Counter.module
  requireSameAnnotations "Shared Counter vs canonical quint_invariant"
    shared.quintInvariants ProofForge.Contract.Examples.Counter.spec.quintInvariants
  requireSameAnnotations "Shared Counter vs canonical quint_liveness"
    shared.quintLiveness ProofForge.Contract.Examples.Counter.spec.quintLiveness
  requireSameModule "EVM Counter compatibility wrapper vs shared contract_source"
    evm.module shared.module
  requireSameAnnotations "EVM Counter compatibility wrapper quint_invariant"
    evm.quintInvariants shared.quintInvariants
  requireSameAnnotations "EVM Counter compatibility wrapper quint_liveness"
    evm.quintLiveness shared.quintLiveness
  require (evm.constructorParams == #[{ name := "initial", abiType := "uint256" }])
    "EVM Counter wrapper lost constructor param metadata"
  require (evm.constructorInitBindings == #[
      { stateId := "count", paramName := "initial", kind := .scalarU64 }
    ])
    "EVM Counter wrapper lost constructor init binding metadata"
  requireSameModule "Solana Counter compatibility wrapper vs shared contract_source"
    solana.module shared.module
  requireSameAnnotations "Solana Counter compatibility wrapper quint_invariant"
    solana.quintInvariants shared.quintInvariants
  requireSameAnnotations "Solana Counter compatibility wrapper quint_liveness"
    solana.quintLiveness shared.quintLiveness
  requireSameModule "Legacy Learn Counter vs shared contract_source"
    learn.module shared.module

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
  requireCounterEquivalence
  requireValueVaultEquivalence
  IO.println "shared-contract-source: ok"
  return 0

end ProofForge.Tests.SharedContractSource

unsafe def main : IO UInt32 :=
  ProofForge.Tests.SharedContractSource.main

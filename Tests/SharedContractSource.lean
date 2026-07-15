import ProofForge.Cli.ContractLoader
import ProofForge.Contract.Examples.Counter
import ProofForge.Frontend.Authored.Canonicalize

namespace ProofForge.Tests.SharedContractSource

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

unsafe def requireCounterDirectSource : IO Unit := do
  let source ← ProofForge.Cli.ContractLoader.loadSource
    "Examples/Product/Counter.lean" (some ".") none
  let contract ← match source with
    | .authored contract => pure contract
    | .surfaceFixture _ =>
        throw <| IO.userError "Product Counter loaded as an internal Surface fixture"
    | .legacySpec _ =>
        throw <| IO.userError "expected AuthoredContract; got Legacy ContractSpec"
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

unsafe def requireValueVaultDirectSource : IO Unit := do
  let source ← ProofForge.Cli.ContractLoader.loadSource
    "Examples/Product/ValueVault.lean" (some ".") none
  let contract ← match source with
    | .authored contract => pure contract
    | .surfaceFixture _ =>
        throw <| IO.userError "Product ValueVault loaded as an internal Surface fixture"
    | .legacySpec _ =>
        throw <| IO.userError "expected AuthoredContract; got Legacy ContractSpec"
  require (contract.quintInvariants.size == 2)
    "direct ValueVault lost quint_invariant annotations"
  let bundle ← match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"direct ValueVault normalization failed: {repr error}"
  require (bundle.contract.contract.module.state.size == 6)
    "direct ValueVault Canonical Core state drift"
  require (bundle.contract.contract.module.functions.size == 7)
    "direct ValueVault Canonical Core entrypoint drift"
  require (bundle.contract.contract.module.events.size == 5)
    "direct ValueVault Canonical Core event drift"

unsafe def main : IO UInt32 := do
  requireCounterDirectSource
  requireValueVaultDirectSource
  IO.println "shared-contract-source: ok"
  return 0

end ProofForge.Tests.SharedContractSource

unsafe def main : IO UInt32 :=
  ProofForge.Tests.SharedContractSource.main

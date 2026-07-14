import Examples.Product.Canonical.FungibleToken
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.IR
import ProofForge.Frontend.Surface.Normalize

open ProofForge.Target

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  let contract := Examples.Product.Canonical.FungibleToken.contract
  let bundle ← match ProofForge.Frontend.Surface.normalizeSurface contract with
    | .ok bundle => pure bundle
    | .error error => throw (IO.userError s!"direct Token normalization failed: {repr error}")
  let capabilityPlan : CapabilityPlan := {
    targetId := "evm"
    calls := bundle.contract.contract.requirements
  }
  let plan ← match ProofForge.Backend.Evm.Plan.Core.buildFromCore
      bundle.contract capabilityPlan with
    | .ok plan => pure plan
    | .error error => throw (IO.userError s!"direct Token EVM plan failed: {error.message}")
  require (plan.entrypoints.size == 10 && plan.dispatch.entrypoints.size == 10)
    "direct Token feature filtering or dispatch count changed"
  for selector in #["18160ddd", "313ce567", "70a08231", "dd62ed3e",
      "a9059cbb", "095ea7b3", "23b872dd", "40c10f19", "42966c68"] do
    require (plan.dispatch.entrypoints.any (·.selector == selector))
      s!"direct Token lost selector {selector}"
  require (plan.storage.states.any (·.id == "balances") &&
      plan.storage.states.any (·.id == "allowances"))
    "direct Token lost balance or allowance storage"
  match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan plan with
  | .ok yul => do
    require (yul.contains "object \"PRF\"")
      "direct Token renderer lost the token symbol identity"
  | .error error => throw (IO.userError s!"direct Token render failed: {error.message}")
  IO.println "evm-direct-token: ok"

import Examples.Product.Canonical.Counter
import Examples.Product.Canonical.ValueVault
import Examples.Product.Canonical.RemoteCall
import Examples.Product.Canonical.Ownable
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.IR
import ProofForge.Frontend.Surface.Normalize

open ProofForge.IR.Canonical
open ProofForge.Target

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def planDirect
    (contract : ProofForge.Frontend.Surface.SurfaceContract) :
    IO ProofForge.Backend.Evm.Plan.ModulePlan := do
  let bundle ← match ProofForge.Frontend.Surface.normalizeSurface contract with
    | .ok bundle => pure bundle
    | .error error => throw (IO.userError s!"{contract.name} Surface normalization failed: {repr error}")
  let capabilityPlan : CapabilityPlan := {
    targetId := "evm"
    calls := bundle.contract.contract.requirements
  }
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore bundle.contract capabilityPlan with
  | .ok plan => pure plan
  | .error error => throw (IO.userError s!"direct EVM product planning failed: {error.message}")

private def checkProduct
    (contract : ProofForge.Frontend.Surface.SurfaceContract)
    (expectedEntrypoints : Nat) : IO Unit := do
  let plan ← planDirect contract
  require (plan.entrypoints.size == expectedEntrypoints)
    s!"{contract.name} EVM entrypoint count changed"
  require (plan.dispatch.entrypoints.size == expectedEntrypoints &&
      plan.dispatch.entrypoints.all (fun entrypoint => entrypoint.selector.length == 8))
    s!"{contract.name} direct EVM dispatch selectors are incomplete"
  match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan plan with
  | .ok yul =>
      require (yul.contains s!"object \"{contract.name}\"")
        s!"{contract.name} direct EVM renderer lost the product identity"
  | .error error => throw (IO.userError s!"direct EVM product render failed: {error.message}")

def main : IO Unit := do
  checkProduct Examples.Product.Canonical.Counter.contract 3
  checkProduct Examples.Product.Canonical.ValueVault.contract 7
  checkProduct Examples.Product.Canonical.RemoteCall.contract 3
  checkProduct Examples.Product.Canonical.Ownable.contract 4
  IO.println "evm-direct-products: ok"

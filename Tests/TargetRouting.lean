import Examples.Product.Counter
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Frontend.Authored.Canonicalize
import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.TargetRouting

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def hasCapability (plan : CapabilityPlan) (capability : Capability) : Bool :=
  plan.capabilities.any (fun candidate => candidate == capability)

def main : IO UInt32 := do
  let bundle ← match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored
      Examples.Product.Counter.contract with
    | .ok bundle => pure bundle
    | .error error =>
        throw <| IO.userError s!"direct Counter normalization failed: {repr error}"
  let core := bundle.contract.contract
  require (core.interface.contractName == "Counter")
    "direct Counter canonical name mismatch"
  require (core.module.state.size == 1 && core.module.functions.size == 3)
    "direct Counter canonical shape mismatch"
  require (core.materialization.stateSymbols.any (fun symbol => symbol.name == "count"))
    "direct Counter canonical state symbol missing count"
  require (core.interface.entrypoints.all (fun entrypoint => entrypoint.selector?.isNone))
    "portable Counter source should defer target selectors to EVM planning"

  let counterPlan ← match requireCapabilityPlan solanaSbpfAsm {
      targetId := solanaSbpfAsm.id
      calls := core.requirements
      metadata := #[]
    } with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError s!"direct Counter routing failed: {error.render}"
  require (counterPlan.targetId == solanaSbpfAsm.id) "Counter plan target id mismatch"
  require (hasCapability counterPlan .storageScalar) "Counter plan missing storage.scalar"
  match ProofForge.Backend.Solana.Plan.Core.buildFromCore bundle.contract counterPlan with
  | .error error => throw <| IO.userError s!"direct Counter Solana plan failed: {error.message}"
  | .ok targetPlan =>
      require (targetPlan.entrypoints.size == 3) "direct Counter Solana entrypoint drift"
      require (targetPlan.stateFields.any (fun field => field.id == "0"))
        "direct Counter Solana plan missing canonical state id 0"

  -- The explicit v1 fixture remains only for the not-yet-migrated crosscall
  -- diagnostic. It is not a Product Counter source or compatibility route.
  match resolveModule solanaSbpfAsm ProofForge.IR.Examples.CrosscallProbe.module with
  | .ok _ => throw <| IO.userError "Solana routing unexpectedly accepted crosscall without peer"
  | .error error =>
      let message := error.render
      require (message.contains "PortableHonesty" || message.contains "empty peer" ||
        message.contains "peer") s!"unexpected Solana routing diagnostic: {message}"

  IO.println "target-routing: ok"
  return 0

end ProofForge.Tests.TargetRouting

def main : IO UInt32 :=
  ProofForge.Tests.TargetRouting.main

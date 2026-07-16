import ProofForge.Contract.Examples.Counter
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.TargetRouting

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def hasCapability (plan : CapabilityPlan) (capability : Capability) : Bool :=
  plan.capabilities.any (fun c => c == capability)

def stateShape (module : ProofForge.IR.Module) :=
  module.state.map (fun state => (state.id, state.kind, state.type))

def portableEntrypointShape (module : ProofForge.IR.Module) :=
  module.entrypoints.map (fun entrypoint =>
    (entrypoint.name, entrypoint.params, entrypoint.returns))

def requireSameCounterShape : IO Unit := do
  let builderModule := ProofForge.Contract.Examples.Counter.module
  let irModule := ProofForge.IR.Examples.Counter.module
  require (builderModule.name == irModule.name) "Builder Counter module name mismatch"
  require (stateShape builderModule == stateShape irModule) "Builder Counter state shape mismatch"
  require (portableEntrypointShape builderModule == portableEntrypointShape irModule)
    "Builder Counter portable entrypoint shape mismatch"
  require (builderModule.entrypoints.all (fun entrypoint => entrypoint.selector?.isNone))
    "Builder Counter source should defer target selectors to emission"
  require (builderModule.capabilities == irModule.capabilities) "Builder Counter capabilities mismatch"

def main : IO UInt32 := do
  requireSameCounterShape

  let builderCounterPlan ←
    match resolveSpec solanaSbpfAsm ProofForge.Contract.Examples.Counter.spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"Builder Counter routing failed: {err.render}"
  require (builderCounterPlan.targetId == solanaSbpfAsm.id) "Builder Counter plan target id mismatch"
  require (hasCapability builderCounterPlan .storageScalar) "Builder Counter plan missing storage.scalar"

  let counterPlan ←
    match resolveModule solanaSbpfAsm ProofForge.IR.Examples.Counter.module with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"Counter routing failed: {err.render}"
  require (counterPlan.targetId == solanaSbpfAsm.id) "Counter plan target id mismatch"
  require (counterPlan.calls.size > 0) "Counter plan must include routed capability calls"
  require (hasCapability counterPlan .storageScalar) "Counter plan missing storage.scalar"

  -- Portable crosscall.invoke is supported on Solana (CPI); empty peer still fails closed.
  match resolveModule solanaSbpfAsm ProofForge.IR.Examples.CrosscallProbe.module with
  | .ok _ => throw <| IO.userError "Solana routing unexpectedly accepted crosscall without peer"
  | .error err =>
      let msg := err.render
      require (msg.contains "PortableHonesty" || msg.contains "empty peer" || msg.contains "peer")
        s!"unexpected Solana routing diagnostic: {msg}"

  IO.println "target-routing: ok"
  return 0

end ProofForge.Tests.TargetRouting

def main : IO UInt32 :=
  ProofForge.Tests.TargetRouting.main

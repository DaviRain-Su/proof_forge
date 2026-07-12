import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.Validate
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Legacy.Adapter
import ProofForge.Contract.Spec

open ProofForge.Backend.Stylus
open ProofForge.IR.Canonical

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let bundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"adaptLegacy failed: {repr e}"
  let capPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-arbitrum-stylus"
    calls := bundle.contract.contract.requirements
  }
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract capPlan with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"buildFromCore failed: {e.message}"
  require (plan.targetId == "wasm-arbitrum-stylus") "wrong Stylus target id"
  require (plan.moduleName == "Counter") "wrong module name"
  require (plan.abi.methods.map (fun method => method.name) == #["initialize", "increment", "get"])
    "Counter ABI method order changed"
  require (plan.abi.methods.all (fun method => method.selector.size == 4))
    "Stylus selectors must be four bytes"
  require (plan.storage.words.size == 1) "Counter must own one storage word"
  match plan.storage.words[0]? with
  | some word => require (word.type == .uint 64) "Counter state must remain uint64"
  | none => throw <| IO.userError "Counter storage word missing"
  require (plan.functions.size == 3) "Counter function plans missing"
  require (plan.hostOps.any (fun op => op.operation == .storageLoad)) "storage load HostOp missing"
  require (plan.hostOps.any (fun op => op.operation == .storageCache)) "storage cache HostOp missing"
  require (plan.hostOps.any (fun op => op.operation == .storageFlush)) "storage flush HostOp missing"
  require plan.resources.requiresStorageFlush "mutating Counter must require storage flush"
  match ProofForge.Backend.Stylus.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"validatePlan failed: {e.message}"
  IO.println "stylus-core-plan: ok"

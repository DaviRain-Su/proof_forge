import Examples.Product.StatusMessage
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Frontend.Authored.Canonicalize
import ProofForge.Target.Registry

namespace ProofForge.Tests.StatusMessageExample

open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.IR.Core
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def capabilityPlan (targetId : String)
    (bundle : ProofForge.IR.Canonical.CanonicalBundle) : CapabilityPlan := {
  targetId
  calls := bundle.contract.contract.requirements
}

def withEvmSelectors
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract) :
    IO ProofForge.IR.Canonical.CheckedCanonicalContract := do
  let entrypoints := checked.contract.interface.entrypoints.map fun entrypoint =>
    let selector? := match entrypoint.name with
      | "init" => some "e1c7392a"
      | "set_status" => some "086562c9"
      | "get_status" => some "d415a772"
      | _ => entrypoint.selector?
    { entrypoint with selector? }
  let canonical := { checked.contract with
    interface := { checked.contract.interface with entrypoints } }
  match ProofForge.IR.Canonical.validateCanonical canonical with
  | .ok hydrated => pure hydrated
  | .error error => throw <| IO.userError s!"EVM selector hydration failed: {repr error}"

def main : IO Unit := do
  let product := Examples.Product.StatusMessage.contract
  require (product.state.map (·.name) == #["version", "records"])
    "StatusMessage authored state drift"
  require (product.entrypoints.map (·.name) == #["init", "set_status", "get_status"])
    "StatusMessage authored entrypoint drift"
  require (product.events.map (·.name) == #["StatusSet"])
    "StatusMessage authored event drift"

  let bundle <- match normalizeAuthored product with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"StatusMessage normalization failed: {repr error}"
  let ops := bundle.contract.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap fun block => block.instructions.map (·.op)
  require (ops.any fun operation => match operation with
      | .contextRead .sender => true
      | _ => false)
    "StatusMessage caller did not remain target-neutral sender context"
  require (ops.any fun operation => match operation with
      | .pure (.cast .u64 _) => true
      | _ => false)
    "StatusMessage caller projection did not remain an explicit Core cast"
  require (ops.any fun operation => match operation with
      | .storageStore { path := #[.mapKey _], resultType := .u64, .. } _ => true
      | _ => false)
    "StatusMessage map write did not reach Core"
  require (ops.any fun operation => match operation with
      | .storageLoad { path := #[.mapKey _], resultType := .u64, .. } => true
      | _ => false)
    "StatusMessage map read did not reach Core"
  require (ops.any fun operation => match operation with
      | .emit _ _ => true
      | _ => false)
    "StatusMessage event did not reach Core"

  let evmChecked <- withEvmSelectors bundle.contract
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore evmChecked
      (capabilityPlan evm.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"EVM StatusMessage plan failed: {error.message}"
  match ProofForge.Backend.Solana.Plan.Core.buildFromCore bundle.contract
      (capabilityPlan solanaSbpfAsm.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"Solana StatusMessage plan failed: {error.message}"
  match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore bundle.contract
      (capabilityPlan wasmNear.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"NEAR StatusMessage plan failed: {error.message}"
  IO.println "status-message-example: ok"

end ProofForge.Tests.StatusMessageExample

def main : IO Unit :=
  ProofForge.Tests.StatusMessageExample.main

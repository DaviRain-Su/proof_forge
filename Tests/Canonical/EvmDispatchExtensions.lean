import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.EvmFallbackProbe
import ProofForge.IR.Legacy.Adapter
import ProofForge.Contract.Spec
import ProofForge.Target.InterfaceOps.Evm
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.IR

open ProofForge.IR.Canonical

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  let dispatchModule : ProofForge.IR.Module := {
    name := "EvmDispatchExtensions"
    state := #[]
    entrypoints := #[
      { ProofForge.IR.Examples.EvmFallbackProbe.entryFallback with body := #[] },
      { ProofForge.IR.Examples.EvmFallbackProbe.entryReceive with body := #[] }
    ]
  }
  let spec := ProofForge.Contract.ContractSpec.fromIR
    dispatchModule
  let checked <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok bundle => pure bundle.contract
    | .error error => throw (IO.userError s!"EVM dispatch adaptation failed: {repr error}")
  let ids := checked.contract.interfaceExtensions.map (·.id)
  require (ids.contains ProofForge.Target.InterfaceOps.Evm.fallbackDispatchId)
    "fallback did not normalize to the EVM interface extension"
  require (ids.contains ProofForge.Target.InterfaceOps.Evm.receiveDispatchId)
    "receive did not normalize to the EVM interface extension"
  require ((ProofForge.Compiler.checkInterfaceOpHandlers "evm" checked).isEmpty)
    "EVM rejected its dispatch interface extensions"
  require ((ProofForge.Compiler.checkInterfaceOpHandlers "wasm-near" checked).size == 2)
    "NEAR accepted EVM dispatch interface extensions"
  let capabilityPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "evm"
    calls := checked.contract.requirements
  }
  let plan <- match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capabilityPlan with
    | .ok plan => pure plan
    | .error error => throw (IO.userError s!"EVM dispatch planning failed: {error.message}")
  require (plan.dispatch.entrypoints.isEmpty &&
      plan.dispatch.fallbackFunction? == some "f_EvmDispatchExtensions_fallback" &&
      plan.dispatch.receiveFunction? == some "f_EvmDispatchExtensions_receive")
    "EVM dispatch extensions did not become target-owned dispatch functions"
  let duplicateExtensions : Array InterfaceExtension :=
    checked.contract.interfaceExtensions.map fun (extension : InterfaceExtension) =>
      if extension.id == ProofForge.Target.InterfaceOps.Evm.receiveDispatchId then
        { extension with id := ProofForge.Target.InterfaceOps.Evm.fallbackDispatchId }
      else extension
  let duplicateFallbackContract : CanonicalContract := {
    checked.contract with
    interfaceExtensions := duplicateExtensions
  }
  let duplicateFallbackChecked <- match validateCanonical duplicateFallbackContract with
    | .ok checked => pure checked
    | .error error => throw (IO.userError s!"duplicate fallback fixture failed canonical validation: {repr error}")
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore duplicateFallbackChecked capabilityPlan with
  | .error error =>
      require (error.message.contains "multiple fallback")
        "duplicate fallback diagnostic was not target-owned and explicit"
  | .ok _ => throw (IO.userError "EVM accepted multiple fallback entrypoints")
  let yul <- match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan plan with
    | .ok yul => pure yul
    | .error error => throw (IO.userError s!"EVM dispatch rendering failed: {error.message}")
  require (yul.contains "function f_EvmDispatchExtensions_fallback" &&
      yul.contains "function f_EvmDispatchExtensions_receive" &&
      yul.contains "f_EvmDispatchExtensions_fallback()" &&
      yul.contains "f_EvmDispatchExtensions_receive()")
    "canonical Yul omitted target-owned fallback/receive functions or calls"
  IO.println "evm-dispatch-extensions: ok"

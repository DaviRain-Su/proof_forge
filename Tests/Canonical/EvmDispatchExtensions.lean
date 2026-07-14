import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.EvmFallbackProbe
import ProofForge.IR.Legacy.Adapter
import ProofForge.Contract.Spec
import ProofForge.Target.InterfaceOps.Evm

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
  IO.println "evm-dispatch-extensions: ok"

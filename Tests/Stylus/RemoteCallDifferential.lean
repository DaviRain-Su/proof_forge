import Examples.Product.RemoteCall
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Contract.Spec
import ProofForge.Cli.EvmAbi
import ProofForge.IR.Legacy.Adapter

def main : IO Unit := do
  let hydrated <- ProofForge.Cli.hydrateEvmSelectors "cast" Examples.Product.RemoteCall.module
  let spec := ProofForge.Contract.ContractSpec.fromIR hydrated
  let bundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"adaptLegacy failed: {repr error}"
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract {
      targetId := "wasm-arbitrum-stylus", calls := bundle.contract.contract.requirements } with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"buildFromCore failed: {error.message}"
  if plan.functions.size != 3 then throw <| IO.userError "RemoteCall function count changed"
  if plan.calls.size != 2 then throw <| IO.userError "RemoteCall call envelopes missing"
  let some noArgs := plan.calls[0]? | throw <| IO.userError "nullary call envelope missing"
  let some withArgs := plan.calls[1]? | throw <| IO.userError "argument call envelope missing"
  if noArgs.mode != .call || !noArgs.arguments.isEmpty || noArgs.returnType != .uint 64 then
    throw <| IO.userError "nullary call envelope changed"
  if withArgs.paramTypes != #[.uint 64, .uint 64] || withArgs.arguments.size != 2 then
    throw <| IO.userError "typed call envelope changed"
  IO.println "stylus-remote-call-differential: ok"

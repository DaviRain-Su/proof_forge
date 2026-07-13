import Examples.Product.RemoteCall
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.DirectWasm.Imports
import ProofForge.Contract.Spec
import ProofForge.IR.Legacy.Adapter
import ProofForge.Target.PeerMap

def main : IO Unit := do
  let expectedImports := #[
    (.callContract, "call_contract", 6, 1),
    (.staticCallContract, "static_call_contract", 5, 1),
    (.delegateCallContract, "delegate_call_contract", 5, 1),
    (.readReturnData, "read_return_data", 3, 1)]
  for (operation, name, params, results) in expectedImports do
    let some hostImport := ProofForge.Backend.Stylus.DirectWasm.importForHostOp? operation
      | throw <| IO.userError s!"missing official Stylus HostIO import `{name}`"
    if hostImport.module_ != "vm_hooks" || hostImport.name != name ||
        hostImport.type.params.size != params || hostImport.type.results.size != results then
      throw <| IO.userError s!"Stylus HostIO import `{name}` signature drifted"
  let hydrated := { Examples.Product.RemoteCall.module with
    entrypoints := Examples.Product.RemoteCall.module.entrypoints.map fun entrypoint =>
      { entrypoint with selector? := match entrypoint.name with
        | "initialize" => some "8129fc1c"
        | "call_remote" => some "e8902e74"
        | "call_with_args" => some "728f8748"
        | _ => entrypoint.selector? } }
  let bound := ProofForge.Target.PeerMap.applyToModule hydrated <|
    ProofForge.Target.PeerMap.ofList [
      ("peer.callee", "0x2222222222222222222222222222222222222222")]
  let spec := ProofForge.Contract.ContractSpec.fromIR bound
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
  if noArgs.cachePolicy != .clear || withArgs.cachePolicy != .clear then
    throw <| IO.userError "mutating calls must clear the storage cache before HostIO"
  if withArgs.paramTypes != #[.uint 64, .uint 64] || withArgs.arguments.size != 2 then
    throw <| IO.userError "typed call envelope changed"
  for function in #["call_remote", "call_with_args"] do
    if !plan.hostOps.any (fun op => op.functionId == function && op.operation == .storageFlush) then
      throw <| IO.userError s!"{function} is missing its plan-owned pre-call storage flush"
  IO.println "stylus-remote-call-differential: ok"

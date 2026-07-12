import ProofForge.Backend.Stylus.DirectWasm.Lower

namespace ProofForge.Backend.Stylus.DirectWasm

open ProofForge.Backend.Stylus
open ProofForge.Compiler.Wasm

private def ensureHostOpsComplete (plan : StylusPlan) : Except LowerError Unit := do
  for hostOp in plan.hostOps do
    unless hostOp.support.directWasm == .implemented do
      let block := (plan.functions.find? (fun function => function.id == hostOp.functionId)).bind
        (fun function => function.blocks.find? (fun block => block.id == function.entryBlock))
      let blockId := block.map (fun block => block.id) |>.getD 0
      throw { message := s!"target={plan.targetId} function={hostOp.functionId} block={blockId} " ++
        s!"op={hostOp.id} capability={repr hostOp.operation} renderer=direct-wasm: " ++
        "HostOp renderer support is not implemented" }
    unless (importForHostOp? hostOp.operation).isSome do
      throw { message := s!"target={plan.targetId} function={hostOp.functionId} block=0 " ++
        s!"op={hostOp.id} capability={repr hostOp.operation} renderer=direct-wasm: " ++
        "HostOp import handler is not implemented" }

def lowerFromPlan (plan : StylusPlan) : Except LowerError Module := do
  validatePlan plan |>.mapError fun error => { message := error.message }
  ensureHostOpsComplete plan
  let imports <- selectImports plan.hostOps |>.mapError fun error => { message := error.message }
  let mut funcs := #[dispatcherFunction plan.abi]
  for function in plan.functions do funcs := funcs.push (← lowerFunction plan function)
  pure { imports, funcs, memory := some (← scratchMemory plan.resources.maxMemoryPages |>.mapError fun e => { message := e.message }) }

end ProofForge.Backend.Stylus.DirectWasm

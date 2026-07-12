import ProofForge.Backend.Stylus.DirectWasm.Lower

namespace ProofForge.Backend.Stylus.DirectWasm

open ProofForge.Backend.Stylus
open ProofForge.Compiler.Wasm

private def calldataPtr : Nat := 160

private def writeLiteral (ptr : Nat) (bytes : StylusBytes) : Array Insn :=
  bytes.mapIdx fun index byte =>
    .block_ (.mk #[.i32Const (ptr + index), .i32Const byte.toNat, .store "i32.store8" 0])

private def loadSelector : Array Insn := #[
  .i32Const calldataPtr, .load "i32.load8_u" 0, .i32Const 24, .plain "i32.shl",
  .i32Const (calldataPtr + 1), .load "i32.load8_u" 0, .i32Const 16, .plain "i32.shl", .plain "i32.or",
  .i32Const (calldataPtr + 2), .load "i32.load8_u" 0, .i32Const 8, .plain "i32.shl", .plain "i32.or",
  .i32Const (calldataPtr + 3), .load "i32.load8_u" 0, .plain "i32.or",
  .localSet "selector"
]

private def userEntrypoint (plan : StylusPlan) : Func :=
  let malformed := "stylus: malformed calldata".toUTF8.data
  let unknown := "stylus: unknown selector".toUTF8.data
  let dispatch := plan.abi.methods.map fun method =>
    .block_ (.mk #[
      .localGet "selector", .const .i32 (toString (selectorNat method.selector)), .plain "i32.eq",
      .if_ (.mk #[.call ("__pf_" ++ method.name), .return_]) .empty
    ])
  {
    name := "user_entrypoint"
    exportName := some "user_entrypoint"
    params := #[{ name := "args_len", type := .i32 }]
    results := #[.i32]
    locals := #[{ name := "selector", type := .i32 }]
    body := .mk <| #[
      .localGet "args_len", .i32Const 4, .plain "i32.ne",
      .if_ (.mk <| writeLiteral 32 malformed ++ #[.i32Const 32, .i32Const malformed.size,
        .call "write_result", .i32Const 1, .return_]) .empty,
      .i32Const calldataPtr, .call "read_args"
    ] ++ loadSelector ++ dispatch ++ writeLiteral 32 unknown ++ #[
      .i32Const 32, .i32Const unknown.size, .call "write_result", .i32Const 1]
  }

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
  for method in plan.abi.methods do
    unless method.params.isEmpty do
      throw { message := s!"target={plan.targetId} function={method.name} block=0 op=abi.params " ++
        "capability=calldata.decode renderer=direct-wasm: function parameters are not implemented" }
  let imports <- selectImports (plan.hostOps.push {
      id := "module.calldata", functionId := "user_entrypoint", operation := .calldataCopy,
      support := { rustSdk := .implemented, directWasm := .implemented } })
    |>.mapError fun error => { message := error.message }
  let mut funcs := #[dispatcherFunction plan.abi, userEntrypoint plan]
  for function in plan.functions do funcs := funcs.push (← lowerFunction plan function)
  pure { imports, funcs, memory := some (← scratchMemory plan.resources.maxMemoryPages |>.mapError fun e => { message := e.message }) }

end ProofForge.Backend.Stylus.DirectWasm

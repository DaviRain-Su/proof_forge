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

private def scalarParamWidth : StylusAbiType -> Except LowerError Nat
  | .bool => pure 1
  | .address => pure 20
  | .uint bits =>
      if bits > 0 && bits <= 128 && bits % 8 == 0 then pure (bits / 8)
      else throw { message := s!"direct Wasm ABI parameters require widths through uint128, received uint{bits}" }
  | type => throw { message := s!"direct Wasm ABI parameter is not a supported scalar: {repr type}" }

private def decodeParam (index width : Nat) : Array Insn := Id.run do
  let ptr := calldataPtr + 4 + index * 32 + (32 - width)
  if width > 8 then
    return #[.i64Const ptr]
  let mut insns := #[.i64Const 0]
  for byte in [0:width] do
    insns := insns ++ #[.i64Const 8, .plain "i64.shl", .i32Const (ptr + byte),
      .load "i32.load8_u" 0, .plain "i64.extend_i32_u", .plain "i64.or"]
  return insns

private def validateParam (index width : Nat) (type : StylusAbiType) : Array Insn := Id.run do
  let ptr := calldataPtr + 4 + index * 32
  let malformed := "stylus: malformed calldata".toUTF8.data
  let mut check : Array Insn := #[.i32Const 0]
  for byte in [0:(32 - width)] do
    check := check ++ #[.i32Const (ptr + byte), .load "i32.load8_u" 0, .plain "i32.or"]
  if type == .bool then
    check := check ++ #[.i32Const (ptr + 31), .load "i32.load8_u" 0, .i32Const 1, .plain "i32.gt_u",
      .plain "i32.or"]
  return check ++ #[.if_ (.mk <| writeLiteral 32 malformed ++ #[.i32Const 32,
    .i32Const malformed.size, .call "write_result", .i32Const 1, .return_]) .empty]

private def decodeU32BE (ptr : Nat) (name : String) : Array Insn := #[
  .i32Const ptr, .load "i32.load8_u" 0, .i32Const 24, .plain "i32.shl",
  .i32Const (ptr + 1), .load "i32.load8_u" 0, .i32Const 16, .plain "i32.shl", .plain "i32.or",
  .i32Const (ptr + 2), .load "i32.load8_u" 0, .i32Const 8, .plain "i32.shl", .plain "i32.or",
  .i32Const (ptr + 3), .load "i32.load8_u" 0, .plain "i32.or", .localSet name]

private def rejectIf (condition : Array Insn) : Array Insn :=
  let malformed := "stylus: malformed calldata".toUTF8.data
  condition ++ #[.if_ (.mk <| writeLiteral 32 malformed ++ #[.i32Const 32,
    .i32Const malformed.size, .call "write_result", .i32Const 1, .return_]) .empty]

private def dynamicParam (index headBytes maximum : Nat) : Array Insn := Id.run do
  let headPtr := calldataPtr + 4 + index * 32
  let offsetName := s!"abi_offset_{index}"
  let lengthName := s!"abi_length_{index}"
  let mut body : Array Insn := #[]
  let mut highOffset : Array Insn := #[.i32Const 0]
  for byte in [0:28] do
    highOffset := highOffset ++ #[.i32Const (headPtr + byte), .load "i32.load8_u" 0, .plain "i32.or"]
  body := body ++ rejectIf highOffset ++ decodeU32BE (headPtr + 28) offsetName
  body := body ++ rejectIf #[.localGet offsetName, .i32Const 31, .plain "i32.and"]
  body := body ++ rejectIf #[.localGet offsetName, .i32Const headBytes, .plain "i32.lt_u"]
  body := body ++ rejectIf #[.localGet offsetName, .i32Const 32, .plain "i32.add",
    .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
  let mut highLength : Array Insn := #[.i32Const 0]
  for byte in [0:28] do
    highLength := highLength ++ #[.localGet offsetName, .i32Const (calldataPtr + 4 + byte),
      .plain "i32.add", .load "i32.load8_u" 0, .plain "i32.or"]
  body := body ++ rejectIf highLength
  body := body ++ #[.localGet offsetName, .i32Const (calldataPtr + 4 + 28), .plain "i32.add",
    .load "i32.load8_u" 0, .i32Const 24, .plain "i32.shl",
    .localGet offsetName, .i32Const (calldataPtr + 4 + 29), .plain "i32.add", .load "i32.load8_u" 0,
    .i32Const 16, .plain "i32.shl", .plain "i32.or",
    .localGet offsetName, .i32Const (calldataPtr + 4 + 30), .plain "i32.add", .load "i32.load8_u" 0,
    .i32Const 8, .plain "i32.shl", .plain "i32.or",
    .localGet offsetName, .i32Const (calldataPtr + 4 + 31), .plain "i32.add", .load "i32.load8_u" 0,
    .plain "i32.or", .localSet lengthName]
  body := body ++ rejectIf #[.localGet lengthName, .i32Const maximum, .plain "i32.gt_u"]
  body := body ++ rejectIf #[.localGet offsetName, .i32Const 32, .plain "i32.add",
    .localGet lengthName, .i32Const 31, .plain "i32.add", .i32Const 4294967264, .plain "i32.and",
    .plain "i32.add", .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
  return body ++ #[.localGet offsetName, .i32Const (calldataPtr + 4 + 32), .plain "i32.add",
    .plain "i64.extend_i32_u", .localGet lengthName, .plain "i64.extend_i32_u"]

private def methodCall (plan : StylusPlan) (method : StylusAbiMethodPlan) : Except LowerError (Array Insn) := do
  let malformed := "stylus: malformed calldata".toUTF8.data
  let expected := 4 + method.params.size * 32
  let hasDynamic := method.params.any fun param => param.type.isDynamic
  let some function := plan.functions.find? (fun function => function.abiMethod == method.name)
    | throw { message := s!"direct Wasm ABI method `{method.name}` has no function plan" }
  let sizeCheck := if hasDynamic then "i32.lt_u" else "i32.ne"
  let mut body : Array Insn := #[.localGet "args_len", .i32Const expected, .plain sizeCheck,
    .if_ (.mk <| writeLiteral 32 malformed ++ #[.i32Const 32, .i32Const malformed.size,
      .call "write_result", .i32Const 1, .return_]) .empty]
  for h : index in [0:method.params.size] do
    let param := method.params[index]
    if param.type.isDynamic then
      let some functionParam := function.params[index]?
        | throw { message := s!"direct Wasm ABI method `{method.name}` parameter plan is missing" }
      let some maximum := functionParam.dynamicMaxLength?
        | throw { message := s!"direct Wasm ABI method `{method.name}` dynamic maximum is missing" }
      body := body ++ dynamicParam index (method.params.size * 32) maximum
    else
      let width <- scalarParamWidth param.type
      body := body ++ validateParam index width param.type ++ decodeParam index width
  pure <| body ++ #[.call ("__pf_" ++ method.name), .return_]

private def userEntrypoint (plan : StylusPlan) : Except LowerError Func := do
  let malformed := "stylus: malformed calldata".toUTF8.data
  let unknown := "stylus: unknown selector".toUTF8.data
  let mut dispatch := #[]
  for method in plan.abi.methods do
    dispatch := dispatch.push <| .block_ (.mk <| #[
      .localGet "selector", .const .i32 (toString (selectorNat method.selector)), .plain "i32.eq",
      .if_ (.mk (← methodCall plan method)) .empty
    ])
  let maxParams := plan.abi.methods.foldl (fun maximum method => max maximum method.params.size) 0
  let mut locals := #[{ name := "selector", type := ValType.i32 }]
  for index in [0:maxParams] do
    locals := locals ++ #[{ name := s!"abi_offset_{index}", type := .i32 },
      { name := s!"abi_length_{index}", type := .i32 }]
  pure {
    name := "user_entrypoint"
    exportName := some "user_entrypoint"
    params := #[{ name := "args_len", type := .i32 }]
    results := #[.i32]
    locals
    body := .mk <| #[
      .localGet "args_len", .i32Const 4, .plain "i32.lt_u",
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

private def wideResult? (plan : StylusPlan) : StylusOpPlan -> Option StylusValueId
  | .literal result (.uint 128) _ | .add result (.uint 128) ..
  | .sub result (.uint 128) .. | .mul result (.uint 128) .. | .div result (.uint 128) .. => some result
  | .storageLoad result wordId =>
      if plan.storage.words.any (fun word => word.id == wordId && word.type == .uint 128)
      then some result else none
  | .storagePathLoad result wordId _ =>
      if plan.storage.words.any (fun word => word.id == wordId && word.type == .uint 128)
      then some result else none
  | _ => none

private def ensureWideScratchFits (plan : StylusPlan) : Except LowerError Unit := do
  let limit := plan.resources.maxMemoryPages * wasmPageBytes
  for function in plan.functions do
    for block in function.blocks do
      for op in block.operations do
        if let some result := wideResult? plan op then
          let endOffset := wideScratchPtr result + 16
          if endOffset > limit then
            throw { message := s!"target={plan.targetId} function={function.id} block={block.id} " ++
              s!"op=wide-{result} capability=memory.scratch renderer=direct-wasm: " ++
              s!"wide scratch end {endOffset} exceeds memory limit {limit}" }

private def ensureDynamicLiteralScratchFits (plan : StylusPlan) : Except LowerError Unit := do
  let limit := plan.resources.maxMemoryPages * wasmPageBytes
  for function in plan.functions do
    for block in function.blocks do
      for op in block.operations do
        match op with
        | .literal result .bytes (.bytes value) =>
            if value.size > dynamicLiteralMaxBytes || dynamicLiteralPtr result + value.size > limit then
              throw { message := s!"target={plan.targetId} function={function.id} block={block.id} " ++
                s!"op=literal-{result} capability=memory.dynamic-literal renderer=direct-wasm: literal scratch exceeds bounds" }
        | .literal result .string (.string value) =>
            let size := value.toUTF8.data.size
            if size > dynamicLiteralMaxBytes || dynamicLiteralPtr result + size > limit then
              throw { message := s!"target={plan.targetId} function={function.id} block={block.id} " ++
                s!"op=literal-{result} capability=memory.dynamic-literal renderer=direct-wasm: literal scratch exceeds bounds" }
        | _ => pure ()

def lowerFromPlan (plan : StylusPlan) : Except LowerError Module := do
  validatePlan plan |>.mapError fun error => { message := error.message }
  ensureHostOpsComplete plan
  ensureWideScratchFits plan
  ensureDynamicLiteralScratchFits plan
  let imports <- selectImports (plan.hostOps.push {
      id := "module.calldata", functionId := "user_entrypoint", operation := .calldataCopy,
      support := { rustSdk := .implemented, directWasm := .implemented } })
    |>.mapError fun error => { message := error.message }
  let mut funcs := #[dispatcherFunction plan.abi, ← userEntrypoint plan]
  for function in plan.functions do funcs := funcs.push (← lowerFunction plan function)
  pure { imports, funcs, memory := some (← scratchMemory plan.resources.maxMemoryPages |>.mapError fun e => { message := e.message }) }

end ProofForge.Backend.Stylus.DirectWasm

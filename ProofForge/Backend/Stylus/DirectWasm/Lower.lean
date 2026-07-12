import ProofForge.Backend.Stylus.DirectWasm.Context
import ProofForge.Backend.Stylus.DirectWasm.Dispatch
import ProofForge.Backend.Stylus.Validate

namespace ProofForge.Backend.Stylus.DirectWasm

open ProofForge.Backend.Stylus
open ProofForge.Compiler.Wasm

structure LowerError where
  message : String
  deriving Repr, BEq

private def fail (message : String) : Except LowerError α :=
  .error { message }

private def valueLocal (id : StylusValueId) : String := s!"v{id}"

private def opName : StylusOpPlan -> String
  | .literal result .. => s!"literal-{result}"
  | .add result .. => s!"add-{result}"
  | .storageLoad result wordId => s!"storage-load-{wordId}-{result}"
  | .storageCache wordId value => s!"storage-cache-{wordId}-{value}"
  | .contextRead result _ operation => s!"context-{repr operation}-{result}"
  | .compare result _ operation .. => s!"compare-{repr operation}-{result}"
  | .assert_ condition _ => s!"assert-{condition}"

private def diagnostic (plan : StylusPlan) (function : StylusFunctionPlan)
    (block : StylusBlockPlan) (op : String) (capability reason : String) : LowerError := {
  message := s!"target={plan.targetId} function={function.id} block={block.id} op={op} " ++
    s!"capability={capability} renderer=direct-wasm: {reason}"
}

private def wordFor (plan : StylusPlan) (id : String) : Except LowerError StylusStorageWordPlan :=
  match plan.storage.words.find? (fun word => word.id == id) with
  | some word => pure word
  | none => fail s!"Stylus direct lowering references missing storage word `{id}`"

private def literalSlot (word : StylusStorageWordPlan) : Except LowerError Bytes :=
  match word.slot with
  | .literal bytes => normalizeWord bytes |>.mapError fun error => { message := error.message }
  | _ => fail s!"Stylus direct lowering has no slot-expression handler for `{word.id}`"

private def writeBytes (ptr : Nat) (bytes : Bytes) : Array Insn :=
  bytes.mapIdx fun index byte =>
    .block_ (.mk #[.i32Const (ptr + index), .i32Const byte.toNat, .store "i32.store8" 0])

private def clearWord (ptr : Nat) : Array Insn :=
  writeBytes ptr zeroWord

private def decodeUnsigned (ptr width : Nat) (result : String) : Array Insn := Id.run do
  let mut insns := #[.i64Const 0]
  for index in [0:width] do
    insns := insns ++ #[
      .i64Const 8, .plain "i64.shl",
      .i32Const (ptr + index), .load "i32.load8_u" 0, .plain "i64.extend_i32_u", .plain "i64.or"
    ]
  return insns.push (.localSet result)

private def encodeUnsigned (ptr width : Nat) (value : String) : Array Insn := Id.run do
  let mut insns := #[]
  for index in [0:width] do
    let shift := 8 * (width - 1 - index)
    insns := insns ++ #[
      .i32Const (ptr + index), .localGet value, .i64Const shift, .plain "i64.shr_u",
      .plain "i32.wrap_i64", .store "i32.store8" 0
    ]
  return insns

private def pointerBytesEqual (lhs rhs : String) (width : Nat) (result : String) : Array Insn := Id.run do
  let mut insns := #[.i64Const 1]
  for index in [0:width] do
    insns := insns ++ #[
      .localGet lhs, .plain "i32.wrap_i64", .i32Const index, .plain "i32.add", .load "i32.load8_u" 0,
      .localGet rhs, .plain "i32.wrap_i64", .i32Const index, .plain "i32.add", .load "i32.load8_u" 0,
      .plain "i32.eq", .plain "i64.extend_i32_u", .plain "i64.and"
    ]
  return insns.push (.localSet result)

private def nonPayablePrologue : Array Insn := Id.run do
  let mut check : Array Insn := #[.i32Const valuePtr, .call "msg_value", .i32Const 0]
  for index in [0:u256Bytes] do
    check := check ++ #[.i32Const (valuePtr + index), .load "i32.load8_u" 0, .plain "i32.or"]
  let message := "stylus: nonpayable".toUTF8.data
  return check ++ #[.if_ (.mk <| writeBytes 32 message ++ #[
    .i32Const 32, .i32Const message.size, .call "write_result", .i32Const 1, .return_]) .empty]

private def scalarWidth : StylusAbiType -> Except LowerError Nat
  | .bool => pure 1
  | .uint bits =>
      if bits > 0 && bits <= 64 && bits % 8 == 0 then pure (bits / 8)
      else fail s!"direct Counter scalar lowering supports uint widths through 64, received uint{bits}"
  | type => fail s!"direct Counter scalar lowering has no handler for `{repr type}`"

private def resultIds (op : StylusOpPlan) : Array StylusValueId :=
  match op with
  | .literal result .. | .add result .. | .storageLoad result ..
  | .contextRead result .. | .compare result .. => #[result]
  | .storageCache .. | .assert_ .. => #[]

private def functionLocals (function : StylusFunctionPlan) : Array Local := Id.run do
  let mut ids := #[]
  for block in function.blocks do
    for op in block.operations do
      for id in resultIds op do
        unless ids.contains id do ids := ids.push id
  return ids.map fun id => { name := valueLocal id, type := .i64 }

private def lowerOp (plan : StylusPlan) (function : StylusFunctionPlan)
    (block : StylusBlockPlan) (op : StylusOpPlan) : Except LowerError (Array Insn) := do
  match op with
  | .literal result type value =>
      match type, value with
      | .bool, .bool value => pure #[.i64Const (if value then 1 else 0), .localSet (valueLocal result)]
      | .uint bits, .uint value =>
          if bits <= 64 then pure #[.i64Const value, .localSet (valueLocal result)]
          else throw <| diagnostic plan function block (opName op) "literal" s!"uint{bits} is not implemented"
      | _, _ => throw <| diagnostic plan function block (opName op) "literal" "literal/type mismatch"
  | .add result type mode lhs rhs => do
      unless type == .uint 64 do
        throw <| diagnostic plan function block (opName op) "arithmetic.add"
          s!"direct arithmetic currently requires uint64, received {repr type}"
      let base := #[.localGet (valueLocal lhs), .localGet (valueLocal rhs), .plain "i64.add",
        .localSet (valueLocal result)]
      match mode with
      | .wrapping => pure base
      | .checked => pure <| base ++ #[
          .localGet (valueLocal result), .localGet (valueLocal lhs), .plain "i64.lt_u",
          .if_ (.mk <| writeBytes 32 "checked arithmetic overflow".toUTF8.data ++ #[
            .i32Const 32, .i32Const "checked arithmetic overflow".toUTF8.data.size,
            .call "write_result", .i32Const 1, .return_]) .empty]
  | .storageLoad result wordId => do
      let word <- wordFor plan wordId
      let slot <- literalSlot word
      let loadInsns := writeBytes 0 slot ++ #[.i32Const 0, .i32Const 32, .call "storage_load_bytes32"]
      match word.type with
      | .address => pure <| loadInsns ++ #[.i64Const 44, .localSet (valueLocal result)]
      | type =>
          let width <- scalarWidth type |>.mapError fun error =>
            diagnostic plan function block (opName op) "storage.load" error.message
          pure <| loadInsns ++ decodeUnsigned (64 - width) width (valueLocal result)
  | .storageCache wordId value => do
      let word <- wordFor plan wordId
      let slot <- literalSlot word
      let width <- scalarWidth word.type |>.mapError fun error =>
        diagnostic plan function block (opName op) "storage.cache" error.message
      pure <| writeBytes 0 slot ++ clearWord 32 ++ encodeUnsigned (64 - width) width (valueLocal value) ++
        #[.i32Const 0, .i32Const 32, .call "storage_cache_bytes32"]
  | .contextRead result type operation =>
      match type, operation with
      | .address, .msgSender => pure #[.i32Const senderPtr, .call "msg_sender", .i64Const senderPtr,
          .localSet (valueLocal result)]
      | .address, .contractAddress => pure #[.i32Const contractPtr, .call "contract_address",
          .i64Const contractPtr, .localSet (valueLocal result)]
      | .uint 256, .msgValue => pure #[.i32Const valuePtr, .call "msg_value", .i64Const valuePtr,
          .localSet (valueLocal result)]
      | .uint 64, .blockNumber => pure #[.call "block_number", .localSet (valueLocal result)]
      | .uint 64, .blockTimestamp => pure #[.call "block_timestamp", .localSet (valueLocal result)]
      | _, _ => throw (diagnostic plan function block (opName op) "context.read"
          (s!"unsupported context type/operation {repr type}/{repr operation}"))
  | .compare result type operation lhs rhs =>
      match type with
      | .address =>
          match operation with
          | .eq => pure <| pointerBytesEqual (valueLocal lhs) (valueLocal rhs) addressBytes (valueLocal result)
          | .ne => pure <| pointerBytesEqual (valueLocal lhs) (valueLocal rhs) addressBytes (valueLocal result) ++
              #[.localGet (valueLocal result), .plain "i64.eqz", .plain "i64.extend_i32_u",
                .localSet (valueLocal result)]
          | _ => throw (diagnostic plan function block (opName op) "compare.address"
              "address ordering is not implemented")
      | .bool | .uint _ =>
          let instruction := match operation with
            | .eq => "i64.eq" | .ne => "i64.ne" | .lt => "i64.lt_u"
            | .le => "i64.le_u" | .gt => "i64.gt_u" | .ge => "i64.ge_u"
          pure #[.localGet (valueLocal lhs), .localGet (valueLocal rhs), .plain instruction,
            .plain "i64.extend_i32_u", .localSet (valueLocal result)]
      | _ => throw <| diagnostic plan function block (opName op) "compare" s!"unsupported type {repr type}"
  | .assert_ condition message =>
      pure #[.localGet (valueLocal condition), .plain "i64.eqz",
        .if_ (.mk <| writeBytes 32 message.toUTF8.data ++ #[.i32Const 32, .i32Const message.toUTF8.data.size,
          .call "write_result", .i32Const 1, .return_]) .empty]

private def lowerReturn (plan : StylusPlan) (function : StylusFunctionPlan)
    (block : StylusBlockPlan) (values : Array StylusValueId) : Except LowerError (Array Insn) := do
  match values with
  | #[] => pure #[.i32Const 32, .i32Const 0, .call "write_result", .i32Const 0]
  | #[value] => do
      let some method := plan.abi.methods.find? (fun method => method.name == function.abiMethod)
        | throw <| diagnostic plan function block "terminator" "abi.result" "ABI method is missing"
      let some type := method.returns[0]?
        | throw <| diagnostic plan function block "terminator" "abi.result" "return type is missing"
      unless method.returns.size == 1 do
        throw <| diagnostic plan function block "terminator" "abi.result" "multiple returns are not implemented"
      let width <- scalarWidth type |>.mapError fun error =>
        diagnostic plan function block "terminator" "abi.result" error.message
      pure <| clearWord 32 ++ encodeUnsigned (64 - width) width (valueLocal value) ++
        #[.i32Const 32, .i32Const 32, .call "write_result", .i32Const 0]
  | _ => throw <| diagnostic plan function block "terminator" "abi.result" "multiple returns are not implemented"

private partial def lowerBlock (plan : StylusPlan) (function : StylusFunctionPlan)
    (blockId fuel : Nat) : Except LowerError (Array Insn) := do
  let some block := function.blocks.find? (fun block => block.id == blockId)
    | fail (s!"target={plan.targetId} function={function.id} block={blockId} op=cfg " ++
        "capability=cfg.target renderer=direct-wasm: missing target block")
  if fuel == 0 then
    throw <| diagnostic plan function block "cfg" "cfg.cycle" "cyclic CFG lowering requires loop normalization"
  let mut body := #[]
  for op in block.operations do body := body ++ (← lowerOp plan function block op)
  match block.terminator with
  | .return values =>
      let flush := if plan.hostOps.any (fun op => op.functionId == function.id &&
          op.operation == .storageFlush) then #[.i32Const 0, .call "storage_flush_cache"] else #[]
      pure <| body ++ flush ++ (← lowerReturn plan function block values)
  | .revert errorId =>
      let bytes := errorId.toUTF8.data
      pure <| body ++ writeBytes 32 bytes ++ #[.i32Const 32, .i32Const bytes.size,
        .call "write_result", .i32Const 1]
  | .jump target => pure <| body ++ (← lowerBlock plan function target (fuel - 1))
  | .branch condition onTrue onFalse =>
      pure <| body ++ #[.localGet (valueLocal condition), .plain "i64.eqz",
        .if_ (.mk (← lowerBlock plan function onFalse (fuel - 1)))
          (.mk (← lowerBlock plan function onTrue (fuel - 1)))]

def lowerFunction (plan : StylusPlan) (function : StylusFunctionPlan) : Except LowerError Func := do
  let some entry := function.blocks.find? (fun block => block.id == function.entryBlock)
    | fail (s!"target={plan.targetId} function={function.id} block={function.entryBlock} op=entry " ++
        "capability=cfg.entry renderer=direct-wasm: missing entry block")
  unless function.support.directWasm == .implemented do
    let op := entry.operations[0]?.map opName |>.getD "entry"
    throw <| diagnostic plan function entry op "function" "renderer support is not implemented"
  let some method := plan.abi.methods.find? (fun method => method.name == function.abiMethod)
    | throw <| diagnostic plan function entry "abi" "abi.method" "missing ABI method"
  let prologue := if method.payable then #[] else nonPayablePrologue
  let body := prologue ++ (← lowerBlock plan function function.entryBlock (function.blocks.size + 1))
  let functionName := "__pf_" ++ function.id
  pure {
    name := functionName
    exportName := some functionName
    results := #[.i32]
    locals := functionLocals function
    body := { insns := body }
  }

end ProofForge.Backend.Stylus.DirectWasm

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
private def widePtr (id : StylusValueId) : Nat := wideScratchPtr id

private def opName : StylusOpPlan -> String
  | .literal result .. => s!"literal-{result}"
  | .add result .. => s!"add-{result}"
  | .sub result .. => s!"sub-{result}"
  | .mul result .. => s!"mul-{result}"
  | .div result .. => s!"div-{result}"
  | .storageLoad result wordId => s!"storage-load-{wordId}-{result}"
  | .storageCache wordId value => s!"storage-cache-{wordId}-{value}"
  | .storagePathLoad result wordId _ => s!"storage-path-load-{wordId}-{result}"
  | .storagePathCache wordId _ value => s!"storage-path-cache-{wordId}-{value}"
  | .contextRead result _ operation => s!"context-{repr operation}-{result}"
  | .compare result _ operation .. => s!"compare-{repr operation}-{result}"
  | .assert_ condition _ => s!"assert-{condition}"
  | .emitEvent event _ => s!"emit-{event}"
  | .call result _ callId => s!"call-{callId}-{result}"

private def diagnostic (plan : StylusPlan) (function : StylusFunctionPlan)
    (block : StylusBlockPlan) (op : String) (capability reason : String) : LowerError := {
  message := s!"target={plan.targetId} function={function.id} block={block.id} op={op} " ++
    s!"capability={capability} renderer=direct-wasm: {reason}"
}

private def wordFor (plan : StylusPlan) (id : String) : Except LowerError StylusStorageWordPlan :=
  match plan.storage.words.find? (fun word => word.id == id) with
  | some word => pure word
  | none => fail s!"Stylus direct lowering references missing storage word `{id}`"

private def callFor (plan : StylusPlan) (id : String) : Except LowerError StylusCallPlan :=
  match plan.calls.find? (fun call => call.id == id) with
  | some call => pure call
  | none => fail s!"Stylus direct lowering references missing call envelope `{id}`"

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

private def rejectNonZeroPrefix (ptr width : Nat) (message : String) : Array Insn := Id.run do
  let mut check : Array Insn := #[.i32Const 0]
  for index in [0:width] do
    check := check ++ #[.i32Const (ptr + index), .load "i32.load8_u" 0, .plain "i32.or"]
  return check ++ #[.if_ (.mk <| writeBytes 32 message.toUTF8.data ++ #[.i32Const 32,
    .i32Const message.toUTF8.data.size, .call "write_result", .i32Const 1, .return_]) .empty]

private def copyPointerBytes (target : Nat) (source : String) (width : Nat) : Array Insn := Id.run do
  let mut insns := #[]
  for index in [0:width] do
    insns := insns ++ #[.i32Const (target + index), .localGet source, .plain "i32.wrap_i64",
      .i32Const index, .plain "i32.add", .load "i32.load8_u" 0, .store "i32.store8" 0]
  return insns

private def copyFixedBytes (target source width : Nat) : Array Insn := Id.run do
  let mut insns := #[]
  for index in [0:width] do
    insns := insns ++ #[.i32Const (target + index), .i32Const (source + index),
      .load "i32.load8_u" 0, .store "i32.store8" 0]
  return insns

private def natBytes (width value : Nat) : Bytes :=
  (List.range width).toArray.map fun index =>
    UInt8.ofNat ((value / (2 ^ (8 * (width - 1 - index)))) % 256)

private def addWide128 (result lhs rhs : StylusValueId) (mode : StylusOverflowMode) : Array Insn := Id.run do
  let target := widePtr result
  let mut insns : Array Insn := #[.i64Const 0, .localSet "wideCarry"]
  for reverseIndex in [0:16] do
    let index := 15 - reverseIndex
    insns := insns ++ #[
      .localGet (valueLocal lhs), .plain "i32.wrap_i64", .i32Const index, .plain "i32.add",
      .load "i32.load8_u" 0, .plain "i64.extend_i32_u",
      .localGet (valueLocal rhs), .plain "i32.wrap_i64", .i32Const index, .plain "i32.add",
      .load "i32.load8_u" 0, .plain "i64.extend_i32_u", .plain "i64.add",
      .localGet "wideCarry", .plain "i64.add", .localSet "wideTmp",
      .i32Const (target + index), .localGet "wideTmp", .plain "i32.wrap_i64", .store "i32.store8" 0,
      .localGet "wideTmp", .i64Const 8, .plain "i64.shr_u", .localSet "wideCarry"
    ]
  if mode == .checked then
    let message := "checked arithmetic overflow".toUTF8.data
    insns := insns ++ #[.localGet "wideCarry", .plain "i64.eqz",
      .if_ .empty (.mk <| writeBytes 32 message ++ #[.i32Const 32, .i32Const message.size,
        .call "write_result", .i32Const 1, .return_])]
  return insns ++ #[.i64Const target, .localSet (valueLocal result)]

private def compareWide128Ordering (result lhs rhs : StylusValueId)
    (operation : StylusCompareOp) : Array Insn := Id.run do
  let instruction := match operation with
    | .lt | .le => "i32.lt_u"
    | .gt | .ge => "i32.gt_u"
    | _ => "i32.eq"
  let mut insns : Array Insn := #[.i64Const 0, .localSet (valueLocal result),
    .i64Const 0, .localSet "wideDone"]
  for index in [0:16] do
    let load (value : StylusValueId) : Array Insn := #[.localGet (valueLocal value),
      .plain "i32.wrap_i64", .i32Const index, .plain "i32.add", .load "i32.load8_u" 0]
    let decide := load lhs ++ load rhs ++ #[.plain instruction, .plain "i64.extend_i32_u",
      .localSet (valueLocal result), .i64Const 1, .localSet "wideDone"]
    let compare := load lhs ++ load rhs ++ #[.plain "i32.ne", .if_ (.mk decide) .empty]
    insns := insns ++ #[.localGet "wideDone", .plain "i64.eqz", .if_ (.mk compare) .empty]
  if operation == .le || operation == .ge then
    insns := insns ++ #[.localGet "wideDone", .plain "i64.eqz",
      .if_ (.mk #[.i64Const 1, .localSet (valueLocal result)]) .empty]
  return insns

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

private def mappingSlot (word : StylusStorageWordPlan) (keys : Array StylusValueId) :
    Except LowerError (Array Insn) := do
  unless keys.size == word.keyTypes.size do fail s!"Stylus mapping `{word.id}` key arity mismatch"
  let base <- literalSlot word
  let mut insns := writeBytes 32 base
  for index in [0:keys.size] do
    let some key := keys[index]? | fail s!"Stylus mapping `{word.id}` key index is invalid"
    let some type := word.keyTypes[index]? | fail s!"Stylus mapping `{word.id}` key type is missing"
    insns := insns ++ clearWord 0
    match type with
    | .address => insns := insns ++ copyPointerBytes 12 (valueLocal key) 20
    | type =>
        let width <- scalarWidth type
        insns := insns ++ encodeUnsigned (32 - width) width (valueLocal key)
    insns := insns ++ #[.i32Const 0, .i32Const 64, .i32Const 32, .call "native_keccak256"]
  pure insns

private def resultIds (op : StylusOpPlan) : Array StylusValueId :=
  match op with
  | .literal result .. | .add result .. | .sub result .. | .mul result .. | .div result ..
  | .storageLoad result .. | .storagePathLoad result ..
  | .contextRead result .. | .compare result .. => #[result]
  | .call result .. => #[result]
  | .storageCache .. | .storagePathCache .. | .assert_ .. | .emitEvent .. => #[]

private def functionLocals (function : StylusFunctionPlan) : Array Local := Id.run do
  let mut ids := #[]
  for block in function.blocks do
    for op in block.operations do
      for id in resultIds op do
        unless ids.contains id || function.params.any (fun param => param.valueId == id) do ids := ids.push id
  let values := ids.map fun id => { name := valueLocal id, type := .i64 }
  let hasWideAdd := function.blocks.any fun block => block.operations.any fun op =>
    match op with | .add _ (.uint 128) .. => true | _ => false
  let hasWideOrdering := function.blocks.any fun block => block.operations.any fun op =>
    match op with
    | .compare _ (.uint 128) operation .. => operation != .eq && operation != .ne
    | _ => false
  let values := if hasWideAdd then values ++ #[{ name := "wideCarry", type := .i64 },
    { name := "wideTmp", type := .i64 }] else values
  let values := if hasWideOrdering then values.push { name := "wideDone", type := .i64 } else values
  let mut dynamicIds := #[]
  for block in function.blocks do
    for op in block.operations do
      match op with
      | .literal result .bytes _ | .literal result .string _ =>
          if !dynamicIds.contains result then dynamicIds := dynamicIds.push result
      | _ => pure ()
  let values := values ++ dynamicIds.map fun id => { name := dynamicLengthLocal id, type := .i64 }
  let hasCall := function.blocks.any fun block => block.operations.any fun op =>
    match op with | .call .. => true | _ => false
  return if hasCall then values ++ #[{ name := "callStatus", type := .i32 },
    { name := "callReturnLen", type := .i32 }] else values

private def lowerOp (plan : StylusPlan) (function : StylusFunctionPlan)
    (block : StylusBlockPlan) (op : StylusOpPlan) : Except LowerError (Array Insn) := do
  match op with
  | .literal result type value =>
      match type, value with
      | .bool, .bool value => pure #[.i64Const (if value then 1 else 0), .localSet (valueLocal result)]
      | .uint bits, .uint value =>
          if bits <= 64 then pure #[.i64Const value, .localSet (valueLocal result)]
          else if bits == 128 then pure <| writeBytes (widePtr result) (natBytes 16 value) ++
            #[.i64Const (widePtr result), .localSet (valueLocal result)]
          else throw <| diagnostic plan function block (opName op) "literal" s!"uint{bits} is not implemented"
      | .bytes, .bytes value =>
          if value.size > dynamicLiteralMaxBytes then
            throw <| diagnostic plan function block (opName op) "literal.bytes" "literal exceeds 256 bytes"
          pure <| writeBytes (dynamicLiteralPtr result) value ++ #[
            .i64Const (dynamicLiteralPtr result), .localSet (valueLocal result),
            .i64Const value.size, .localSet (dynamicLengthLocal result)]
      | .string, .string value =>
          let bytes := value.toUTF8.data
          if bytes.size > dynamicLiteralMaxBytes then
            throw <| diagnostic plan function block (opName op) "literal.string" "literal exceeds 256 bytes"
          pure <| writeBytes (dynamicLiteralPtr result) bytes ++ #[
            .i64Const (dynamicLiteralPtr result), .localSet (valueLocal result),
            .i64Const bytes.size, .localSet (dynamicLengthLocal result)]
      | _, _ => throw <| diagnostic plan function block (opName op) "literal" "literal/type mismatch"
  | .add result type mode lhs rhs => do
      if type == .uint 128 then
        pure (addWide128 result lhs rhs mode)
      else if type != .uint 64 then
        throw <| diagnostic plan function block (opName op) "arithmetic.add"
          s!"direct arithmetic currently requires uint64, received {repr type}"
      else
        let base := #[.localGet (valueLocal lhs), .localGet (valueLocal rhs), .plain "i64.add",
          .localSet (valueLocal result)]
        match mode with
        | .wrapping => pure base
        | .checked => pure <| base ++ #[
            .localGet (valueLocal result), .localGet (valueLocal lhs), .plain "i64.lt_u",
            .if_ (.mk <| writeBytes 32 "checked arithmetic overflow".toUTF8.data ++ #[
              .i32Const 32, .i32Const "checked arithmetic overflow".toUTF8.data.size,
              .call "write_result", .i32Const 1, .return_]) .empty]
  | .sub result type mode lhs rhs => do
      if type != .uint 64 then
        throw <| diagnostic plan function block (opName op) "arithmetic.sub" "direct subtraction requires uint64"
      let reject := #[.localGet (valueLocal lhs), .localGet (valueLocal rhs), .plain "i64.lt_u",
        .if_ (.mk <| writeBytes 32 "checked arithmetic overflow".toUTF8.data ++ #[.i32Const 32,
          .i32Const "checked arithmetic overflow".toUTF8.data.size, .call "write_result", .i32Const 1, .return_]) .empty]
      let base := #[.localGet (valueLocal lhs), .localGet (valueLocal rhs), .plain "i64.sub",
        .localSet (valueLocal result)]
      pure <| (if mode == .checked then reject else #[]) ++ base
  | .mul result type mode lhs rhs => do
      if type != .uint 64 then
        throw <| diagnostic plan function block (opName op) "arithmetic.mul" "direct multiplication requires uint64"
      let base := #[.localGet (valueLocal lhs), .localGet (valueLocal rhs), .plain "i64.mul",
        .localSet (valueLocal result)]
      let reject := #[.localGet (valueLocal rhs), .plain "i64.eqz", .plain "i32.eqz",
        .if_ (.mk #[.localGet (valueLocal result), .localGet (valueLocal rhs), .plain "i64.div_u",
          .localGet (valueLocal lhs), .plain "i64.ne",
          .if_ (.mk <| writeBytes 32 "checked arithmetic overflow".toUTF8.data ++ #[.i32Const 32,
            .i32Const "checked arithmetic overflow".toUTF8.data.size, .call "write_result", .i32Const 1, .return_]) .empty]) .empty]
      pure <| base ++ (if mode == .checked then reject else #[])
  | .div result type _ lhs rhs => do
      if type != .uint 64 then
        throw <| diagnostic plan function block (opName op) "arithmetic.div" "direct division requires uint64"
      let reject := #[.localGet (valueLocal rhs), .plain "i64.eqz",
        .if_ (.mk <| writeBytes 32 "division by zero".toUTF8.data ++ #[.i32Const 32,
          .i32Const "division by zero".toUTF8.data.size, .call "write_result", .i32Const 1, .return_]) .empty]
      pure <| reject ++ #[.localGet (valueLocal lhs), .localGet (valueLocal rhs), .plain "i64.div_u",
        .localSet (valueLocal result)]
  | .storageLoad result wordId => do
      let word <- wordFor plan wordId
      let slot <- literalSlot word
      let loadInsns := writeBytes 0 slot ++ #[.i32Const 0, .i32Const 32, .call "storage_load_bytes32"]
      match word.type with
      | .address => pure <| loadInsns ++ #[.i64Const 44, .localSet (valueLocal result)]
      | .uint 128 => pure <| loadInsns ++ copyFixedBytes (widePtr result) 48 16 ++
          #[.i64Const (widePtr result), .localSet (valueLocal result)]
      | type =>
          let width <- scalarWidth type |>.mapError fun error =>
            diagnostic plan function block (opName op) "storage.load" error.message
          pure <| loadInsns ++ decodeUnsigned (64 - width) width (valueLocal result)
  | .storageCache wordId value => do
      let word <- wordFor plan wordId
      let slot <- literalSlot word
      match word.type with
      | .uint 128 => pure <| writeBytes 0 slot ++ clearWord 32 ++
          copyPointerBytes 48 (valueLocal value) 16 ++
          #[.i32Const 0, .i32Const 32, .call "storage_cache_bytes32"]
      | _ =>
          let width <- scalarWidth word.type |>.mapError fun error =>
            diagnostic plan function block (opName op) "storage.cache" error.message
          pure <| writeBytes 0 slot ++ clearWord 32 ++ encodeUnsigned (64 - width) width (valueLocal value) ++
            #[.i32Const 0, .i32Const 32, .call "storage_cache_bytes32"]
  | .storagePathLoad result wordId keys => do
      let word <- wordFor plan wordId
      let slot <- mappingSlot word keys |>.mapError fun error =>
        diagnostic plan function block (opName op) "storage.mapping" error.message
      let load := slot ++ #[.i32Const 32, .i32Const 64, .call "storage_load_bytes32"]
      match word.type with
      | .uint 128 => pure <| load ++ copyFixedBytes (widePtr result) 80 16 ++
          #[.i64Const (widePtr result), .localSet (valueLocal result)]
      | type =>
          let width <- scalarWidth type |>.mapError fun error =>
            diagnostic plan function block (opName op) "storage.mapping" error.message
          pure <| load ++ decodeUnsigned (96 - width) width (valueLocal result)
  | .storagePathCache wordId keys value => do
      let word <- wordFor plan wordId
      let slot <- mappingSlot word keys |>.mapError fun error =>
        diagnostic plan function block (opName op) "storage.mapping" error.message
      match word.type with
      | .uint 128 => pure <| slot ++ clearWord 64 ++ copyPointerBytes 80 (valueLocal value) 16 ++
          #[.i32Const 32, .i32Const 64, .call "storage_cache_bytes32"]
      | type =>
          let width <- scalarWidth type |>.mapError fun error =>
            diagnostic plan function block (opName op) "storage.mapping" error.message
          pure <| slot ++ clearWord 64 ++ encodeUnsigned (96 - width) width (valueLocal value) ++
            #[.i32Const 32, .i32Const 64, .call "storage_cache_bytes32"]
  | .contextRead result type operation =>
      match type, operation with
      | .address, .msgSender => pure #[.i32Const senderPtr, .call "msg_sender", .i64Const senderPtr,
          .localSet (valueLocal result)]
      | .address, .contractAddress => pure #[.i32Const contractPtr, .call "contract_address",
          .i64Const contractPtr, .localSet (valueLocal result)]
      | .uint 256, .msgValue => pure #[.i32Const valuePtr, .call "msg_value", .i64Const valuePtr,
          .localSet (valueLocal result)]
      | .uint 128, .msgValue => pure <| #[.i32Const valuePtr, .call "msg_value"] ++
          (rejectNonZeroPrefix valuePtr 16 "stylus: msg.value exceeds uint128") ++
          #[.i64Const (valuePtr + 16), .localSet (valueLocal result)]
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
      | .uint 128 =>
          match operation with
          | .eq => pure <| pointerBytesEqual (valueLocal lhs) (valueLocal rhs) 16 (valueLocal result)
          | .ne => pure <| pointerBytesEqual (valueLocal lhs) (valueLocal rhs) 16 (valueLocal result) ++
              #[.localGet (valueLocal result), .plain "i64.eqz", .plain "i64.extend_i32_u",
                .localSet (valueLocal result)]
          | operation => pure (compareWide128Ordering result lhs rhs operation)
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
  | .emitEvent eventId values => do
      let some event := plan.events.find? (fun item => item.id == eventId)
        | throw <| diagnostic plan function block (opName op) "event.emit" "event plan is missing"
      if event.fields.size != values.size then
        throw <| diagnostic plan function block (opName op) "event.emit" "field/value arity mismatch"
      let topicCount := 1 + (event.fields.filter fun field => field.indexed).size
      if topicCount > 4 then
        throw <| diagnostic plan function block (opName op) "event.emit" "more than four topics"
      let signature := event.canonicalSignature.toUTF8.data
      let eventPtr := 256
      let mut insns := writeBytes eventPtr signature ++ #[.i32Const eventPtr,
        .i32Const signature.size, .i32Const eventPtr, .call "native_keccak256"]
      let mut topicIndex := 1
      let mut dataIndex := 0
      for index in [0:values.size] do
        let some value := values[index]?
          | throw <| diagnostic plan function block (opName op) "event.emit" "value index is invalid"
        let some field := event.fields[index]?
          | throw <| diagnostic plan function block (opName op) "event.emit" "field index is invalid"
        let width <- scalarWidth field.type |>.mapError fun error =>
          diagnostic plan function block (opName op) "event.emit" error.message
        let wordIndex := if field.indexed then topicIndex else topicCount + dataIndex
        insns := insns ++ clearWord (eventPtr + wordIndex * 32) ++
          encodeUnsigned (eventPtr + (wordIndex + 1) * 32 - width) width (valueLocal value)
        if field.indexed then topicIndex := topicIndex + 1 else dataIndex := dataIndex + 1
      pure <| insns ++ #[.i32Const eventPtr, .i32Const ((topicCount + dataIndex) * 32),
        .i32Const topicCount, .call "emit_log"]
  | .call result _ callId =>
      let call <- callFor plan callId |>.mapError fun error =>
        diagnostic plan function block (opName op) "crosscall" error.message
      if call.value?.isSome != call.valueType?.isSome then
        throw <| diagnostic plan function block (opName op) "crosscall.value" "value id/type mismatch"
      if call.paramTypes.size != call.arguments.size then
        throw <| diagnostic plan function block (opName op) "crosscall" "argument/type arity mismatch"
      let signature := call.canonicalSignature.toUTF8.data
      let mut insns := writeBytes callDataPtr signature ++ #[.i32Const callDataPtr,
        .i32Const signature.size, .i32Const callDataPtr, .call "native_keccak256"]
      for index in [0:call.arguments.size] do
        let some argument := call.arguments[index]?
          | throw <| diagnostic plan function block (opName op) "crosscall" "argument index is invalid"
        let some type := call.paramTypes[index]?
          | throw <| diagnostic plan function block (opName op) "crosscall" "argument type is missing"
        let width <- scalarWidth type |>.mapError fun error =>
          diagnostic plan function block (opName op) "crosscall.argument" error.message
        insns := insns ++ clearWord (callDataPtr + 4 + index * 32) ++
          encodeUnsigned (callDataPtr + 36 + index * 32 - width) width (valueLocal argument)
      insns := insns ++ clearWord callReturnLenPtr
      let calldataLen := 4 + call.arguments.size * 32
      let gas := match call.gas? with
        | some value => #[.localGet (valueLocal value)]
        | none => #[.i64Const 18446744073709551615]
      let valueInsns <- match (call.value?, call.valueType?) with
        | (some value, some (.uint 128)) =>
            pure <| copyPointerBytes (callValuePtr + 16) (valueLocal value) 16
        | (some value, some (.uint 256)) =>
            pure <| copyPointerBytes callValuePtr (valueLocal value) 32
        | (some value, some (.uint 64)) =>
            pure <| encodeUnsigned (callValuePtr + 24) 8 (valueLocal value)
        | (none, none) => pure #[]
        | (_, some type) =>
            throw <| diagnostic plan function block (opName op) "crosscall.value"
              s!"unsupported value type {repr type}"
        | _ =>
            throw <| diagnostic plan function block (opName op) "crosscall.value" "value id/type mismatch"
      let callInsns <- match call.mode with
        | .call =>
          pure <| clearWord callValuePtr ++ valueInsns ++ #[.localGet (valueLocal call.target), .plain "i32.wrap_i64",
              .i32Const callDataPtr, .i32Const calldataLen, .i32Const callValuePtr] ++ gas ++
              #[.i32Const callReturnLenPtr, .call "call_contract", .localSet "callStatus"]
        | .staticCall =>
          pure <| #[.localGet (valueLocal call.target), .plain "i32.wrap_i64",
            .i32Const callDataPtr, .i32Const calldataLen] ++ gas ++ #[.i32Const callReturnLenPtr,
            .call "static_call_contract", .localSet "callStatus"]
        | .delegateCall =>
          pure <| #[.localGet (valueLocal call.target), .plain "i32.wrap_i64",
            .i32Const callDataPtr, .i32Const calldataLen] ++ gas ++ #[.i32Const callReturnLenPtr,
            .call "delegate_call_contract", .localSet "callStatus"]
      let checkedInsns := insns ++ callInsns ++ #[.i32Const callReturnLenPtr, .load "i32.load" 0,
        .localSet "callReturnLen", .localGet "callReturnLen", .i32Const callReturnMaxBytes,
        .plain "i32.gt_u", .if_ (.mk <| writeBytes 32 "stylus: return data exceeds limit".toUTF8.data ++ #[
          .i32Const 32, .i32Const "stylus: return data exceeds limit".toUTF8.data.size,
          .call "write_result", .i32Const 1, .return_]) .empty]
      let copyReturn := #[.i32Const callReturnPtr, .i32Const 0, .localGet "callReturnLen",
        .call "read_return_data", .plain "drop"]
      let statusInsns := #[.localGet "callStatus", .if_ (.mk <| copyReturn ++ #[
        .i32Const callReturnPtr, .localGet "callReturnLen", .call "write_result",
        .i32Const 1, .return_]) .empty]
      if call.returnType != .uint 64 then
        throw <| diagnostic plan function block (opName op) "crosscall.return"
          s!"unsupported return type {repr call.returnType}"
      pure <| checkedInsns ++ statusInsns ++ #[.localGet "callReturnLen", .i32Const 32, .plain "i32.ne",
        .if_ (.mk <| writeBytes 32 "stylus: malformed return data".toUTF8.data ++ #[
          .i32Const 32, .i32Const "stylus: malformed return data".toUTF8.data.size,
          .call "write_result", .i32Const 1, .return_]) .empty] ++ copyReturn ++
        decodeUnsigned (callReturnPtr + 24) 8 (valueLocal result)

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
      match type with
      | .uint 128 => pure <| clearWord 32 ++ copyPointerBytes 48 (valueLocal value) 16 ++
          #[.i32Const 32, .i32Const 32, .call "write_result", .i32Const 0]
      | .bytes | .string => do
          let maximum := (function.params.find? (fun param => param.valueId == value)).bind
            (fun param => param.dynamicMaxLength?) |>.getD dynamicLiteralMaxBytes
          pure <| #[.i32Const 32, .i32Const 0, .i32Const (64 + maximum), .plain "memory.fill"] ++
            writeBytes 63 #[32] ++ encodeUnsigned 88 8 (dynamicLengthLocal value) ++ #[
              .i32Const 96, .localGet (valueLocal value), .plain "i32.wrap_i64",
              .localGet (dynamicLengthLocal value), .plain "i32.wrap_i64", .plain "memory.copy",
              .i32Const 32, .localGet (dynamicLengthLocal value), .plain "i32.wrap_i64",
              .i32Const 31, .plain "i32.add", .i32Const 4294967264, .plain "i32.and",
              .i32Const 64, .plain "i32.add", .call "write_result", .i32Const 0]
      | _ =>
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
  let params := function.params.foldl (fun params param =>
    let params := params.push { name := valueLocal param.valueId, type := .i64 }
    if param.dynamicMaxLength?.isSome then
      params.push { name := dynamicLengthLocal param.valueId, type := .i64 }
    else params) #[]
  pure {
    name := functionName
    exportName := some functionName
    params
    results := #[.i32]
    locals := functionLocals function
    body := { insns := body }
  }

end ProofForge.Backend.Stylus.DirectWasm

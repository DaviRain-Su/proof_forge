import ProofForge.Backend.Stylus.AbiLayout
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

private partial def validateStaticAggregate (wordIndex : Nat) : StylusAbiType ->
    Except LowerError (Array Insn × Nat)
  | .fixedArray element size => do
      let mut body := #[]
      let mut next := wordIndex
      for _ in [0:size] do
        let (checks, after) ← validateStaticAggregate next element
        body := body ++ checks
        next := after
      pure (body, next)
  | .tuple fields => do
      let mut body := #[]
      let mut next := wordIndex
      for field in fields do
        let (checks, after) ← validateStaticAggregate next field
        body := body ++ checks
        next := after
      pure (body, next)
  | type => do
      let width ← scalarParamWidth type
      pure (validateParam wordIndex width type, wordIndex + 1)

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
  body := body ++ rejectIf #[.localGet offsetName, .localGet "args_len", .i32Const 4,
    .plain "i32.sub", .plain "i32.gt_u"]
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

private def dynamicByteAddress (offsetName : String) (baseBias wordOffset byteOffset : Nat) : Array Insn := #[
  .localGet offsetName,
  .i32Const (calldataPtr + 4 + baseBias + wordOffset * 32 + byteOffset),
  .plain "i32.add"
]

private partial def validateDynamicStatic (offsetName : String) (baseBias wordOffset : Nat) :
    StylusAbiType -> Except LowerError (Array Insn × Nat)
  | .fixedArray element size => do
      let mut body := #[]
      let mut next := wordOffset
      for _ in [0:size] do
        let (checks, after) ← validateDynamicStatic offsetName baseBias next element
        body := body ++ checks
        next := after
      pure (body, next)
  | .tuple fields => do
      let mut body := #[]
      let mut next := wordOffset
      for field in fields do
        let (checks, after) ← validateDynamicStatic offsetName baseBias next field
        body := body ++ checks
        next := after
      pure (body, next)
  | type => do
      let width ← scalarParamWidth type
      let malformed := "stylus: malformed calldata".toUTF8.data
      let mut check : Array Insn := #[.i32Const 0]
      for byte in [0:(32 - width)] do
        check := check ++ dynamicByteAddress offsetName baseBias wordOffset byte ++
          #[.load "i32.load8_u" 0, .plain "i32.or"]
      if type == .bool then
        check := check ++ dynamicByteAddress offsetName baseBias wordOffset 31 ++
          #[.load "i32.load8_u" 0, .i32Const 1, .plain "i32.gt_u", .plain "i32.or"]
      pure (check ++ #[.if_ (.mk <| writeLiteral 32 malformed ++ #[.i32Const 32,
        .i32Const malformed.size, .call "write_result", .i32Const 1, .return_]) .empty], wordOffset + 1)

private def dynamicArrayParam (index headBytes maximum elementWords : Nat)
    (element : StylusAbiType) : Except LowerError (Array Insn) := do
  if maximum > 64 then
    throw { message := s!"direct Wasm dynamic-array maximum {maximum} exceeds static validation limit 64" }
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
    .localGet lengthName, .i32Const (elementWords * 32), .plain "i32.mul", .plain "i32.add",
    .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
  for item in [0:maximum] do
    let (checks, _) ← validateDynamicStatic offsetName 32 (item * elementWords) element
    body := body ++ #[.localGet lengthName, .i32Const item, .plain "i32.gt_u", .if_ (.mk checks) .empty]
  pure <| body ++ #[.localGet offsetName, .i32Const (calldataPtr + 4 + 32), .plain "i32.add",
    .plain "i64.extend_i32_u", .localGet lengthName, .plain "i64.extend_i32_u"]

private def dynamicBytesArrayParam (index headBytes maximumElements maximumChildLength : Nat) :
    Except LowerError (Array Insn) := do
  if maximumElements > 64 then
    throw { message := s!"direct Wasm dynamic-array maximum {maximumElements} exceeds recursive validation limit 64" }
  let headPtr := calldataPtr + 4 + index * 32
  let offsetName := s!"abi_offset_{index}"
  let lengthName := s!"abi_length_{index}"
  let childOffsetName := s!"abi_child_offset_{index}"
  let childLengthName := s!"abi_child_length_{index}"
  let mut body : Array Insn := #[]
  let mut highOffset : Array Insn := #[.i32Const 0]
  for byte in [0:28] do
    highOffset := highOffset ++ #[.i32Const (headPtr + byte), .load "i32.load8_u" 0, .plain "i32.or"]
  body := body ++ rejectIf highOffset ++ decodeU32BE (headPtr + 28) offsetName
  body := body ++ rejectIf #[.localGet offsetName, .i32Const 31, .plain "i32.and"]
  body := body ++ rejectIf #[.localGet offsetName, .i32Const headBytes, .plain "i32.lt_u"]
  body := body ++ rejectIf #[.localGet offsetName, .localGet "args_len", .i32Const 4,
    .plain "i32.sub", .plain "i32.gt_u"]
  body := body ++ rejectIf #[.localGet offsetName, .i32Const 32, .plain "i32.add",
    .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
  let mut highLength : Array Insn := #[.i32Const 0]
  for byte in [0:28] do highLength := highLength ++ #[.localGet offsetName,
    .i32Const (calldataPtr + 4 + byte), .plain "i32.add", .load "i32.load8_u" 0, .plain "i32.or"]
  body := body ++ rejectIf highLength
  body := body ++ #[.localGet offsetName, .i32Const (calldataPtr + 4 + 28), .plain "i32.add",
    .load "i32.load8_u" 0, .i32Const 24, .plain "i32.shl",
    .localGet offsetName, .i32Const (calldataPtr + 4 + 29), .plain "i32.add", .load "i32.load8_u" 0,
    .i32Const 16, .plain "i32.shl", .plain "i32.or",
    .localGet offsetName, .i32Const (calldataPtr + 4 + 30), .plain "i32.add", .load "i32.load8_u" 0,
    .i32Const 8, .plain "i32.shl", .plain "i32.or",
    .localGet offsetName, .i32Const (calldataPtr + 4 + 31), .plain "i32.add", .load "i32.load8_u" 0,
    .plain "i32.or", .localSet lengthName]
  body := body ++ rejectIf #[.localGet lengthName, .i32Const maximumElements, .plain "i32.gt_u"]
  body := body ++ rejectIf #[.localGet offsetName, .i32Const 32, .plain "i32.add",
    .localGet lengthName, .i32Const 32, .plain "i32.mul", .plain "i32.add",
    .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
  for item in [0:maximumElements] do
    let childWordBase := calldataPtr + 4 + 32 + item * 32
    let mut checks : Array Insn := #[]
    let mut highChild : Array Insn := #[.i32Const 0]
    for byte in [0:28] do highChild := highChild ++ #[.localGet offsetName,
      .i32Const (childWordBase + byte), .plain "i32.add", .load "i32.load8_u" 0, .plain "i32.or"]
    checks := checks ++ rejectIf highChild ++ #[.localGet offsetName, .i32Const (childWordBase + 28),
      .plain "i32.add", .load "i32.load8_u" 0, .i32Const 24, .plain "i32.shl",
      .localGet offsetName, .i32Const (childWordBase + 29), .plain "i32.add", .load "i32.load8_u" 0,
      .i32Const 16, .plain "i32.shl", .plain "i32.or",
      .localGet offsetName, .i32Const (childWordBase + 30), .plain "i32.add", .load "i32.load8_u" 0,
      .i32Const 8, .plain "i32.shl", .plain "i32.or",
      .localGet offsetName, .i32Const (childWordBase + 31), .plain "i32.add", .load "i32.load8_u" 0,
      .plain "i32.or", .localSet childOffsetName]
    checks := checks ++ rejectIf #[.localGet childOffsetName, .i32Const 31, .plain "i32.and"]
    checks := checks ++ rejectIf #[.localGet childOffsetName, .localGet lengthName,
      .i32Const 32, .plain "i32.mul", .plain "i32.lt_u"]
    checks := checks ++ rejectIf #[.localGet childOffsetName, .localGet "args_len",
      .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
    checks := checks ++ rejectIf #[.localGet offsetName, .i32Const 32, .plain "i32.add",
      .localGet childOffsetName, .plain "i32.add", .i32Const 32, .plain "i32.add",
      .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
    let childLengthBase := calldataPtr + 4 + 32 + 28
    let mut highChildLength : Array Insn := #[.i32Const 0]
    for byte in [0:28] do highChildLength := highChildLength ++ #[.localGet offsetName,
      .localGet childOffsetName, .plain "i32.add", .i32Const (calldataPtr + 4 + 32 + byte),
      .plain "i32.add", .load "i32.load8_u" 0, .plain "i32.or"]
    checks := checks ++ rejectIf highChildLength ++ #[.localGet offsetName, .localGet childOffsetName,
      .plain "i32.add", .i32Const childLengthBase, .plain "i32.add", .load "i32.load8_u" 0,
      .i32Const 24, .plain "i32.shl",
      .localGet offsetName, .localGet childOffsetName, .plain "i32.add", .i32Const (childLengthBase + 1),
      .plain "i32.add", .load "i32.load8_u" 0, .i32Const 16, .plain "i32.shl", .plain "i32.or",
      .localGet offsetName, .localGet childOffsetName, .plain "i32.add", .i32Const (childLengthBase + 2),
      .plain "i32.add", .load "i32.load8_u" 0, .i32Const 8, .plain "i32.shl", .plain "i32.or",
      .localGet offsetName, .localGet childOffsetName, .plain "i32.add", .i32Const (childLengthBase + 3),
      .plain "i32.add", .load "i32.load8_u" 0, .plain "i32.or", .localSet childLengthName]
    checks := checks ++ rejectIf #[.localGet childLengthName, .i32Const maximumChildLength, .plain "i32.gt_u"]
    checks := checks ++ rejectIf #[.localGet offsetName, .i32Const 32, .plain "i32.add",
      .localGet childOffsetName, .plain "i32.add", .i32Const 32, .plain "i32.add",
      .localGet childLengthName, .i32Const 31, .plain "i32.add", .i32Const 4294967264,
      .plain "i32.and", .plain "i32.add", .localGet "args_len", .i32Const 4,
      .plain "i32.sub", .plain "i32.gt_u"]
    body := body ++ #[.localGet lengthName, .i32Const item, .plain "i32.gt_u", .if_ (.mk checks) .empty]
  pure <| body ++ #[.localGet offsetName, .i32Const (calldataPtr + 4 + 32), .plain "i32.add",
    .plain "i64.extend_i32_u", .localGet lengthName, .plain "i64.extend_i32_u"]

private def dynamicTupleParam (index headBytes : Nat) (maximumLengths : Array Nat)
    (fields : Array StylusAbiType) :
    Except LowerError (Array Insn) := do
  let dynamicFields := fields.filter fun field => field.isDynamic
  for field in dynamicFields do
    match field with
    | .bytes | .string => pure ()
    | .dynamicArray element =>
        let _ <- staticAbiWords 2048 element |>.mapError fun error => { message := error.message }
    | _ => throw { message := "direct Wasm dynamic tuple child requires recursive bound planning" }
  unless dynamicFields.size == maximumLengths.size do
    throw { message := s!"direct Wasm dynamic tuple has {dynamicFields.size} dynamic fields but {maximumLengths.size} maxima" }
  let offsetName := s!"abi_offset_{index}"
  let extentName := s!"abi_tuple_extent_{index}"
  let headPtr := calldataPtr + 4 + index * 32
  let tupleHeadWords ← fields.foldlM (fun words (field : StylusAbiType) => do
    let width ← if field.isDynamic then pure 1 else staticAbiWords 2048 field
    checkedAdd "dynamic tuple head" 2048 words width) 0
    |>.mapError fun (error : AbiLayoutError) => { message := error.message }
  let tupleHeadBytes := tupleHeadWords * 32
  let mut body : Array Insn := #[]
  let mut highOffset : Array Insn := #[.i32Const 0]
  for byte in [0:28] do highOffset := highOffset ++ #[.i32Const (headPtr + byte),
    .load "i32.load8_u" 0, .plain "i32.or"]
  body := body ++ rejectIf highOffset ++ decodeU32BE (headPtr + 28) offsetName
  body := body ++ rejectIf #[.localGet offsetName, .i32Const 31, .plain "i32.and"]
  body := body ++ rejectIf #[.localGet offsetName, .i32Const headBytes, .plain "i32.lt_u"]
  body := body ++ rejectIf #[.localGet offsetName, .localGet "args_len", .i32Const 4,
    .plain "i32.sub", .plain "i32.gt_u"]
  body := body ++ rejectIf #[.localGet offsetName, .i32Const tupleHeadBytes, .plain "i32.add",
    .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
  let mut wordOffset := 0
  let mut dynamicIndex := 0
  for field in fields do
    if field.isDynamic then
      let childOffsetName := s!"abi_child_offset_{index}_{dynamicIndex}"
      let lengthName := s!"abi_child_length_{index}_{dynamicIndex}"
      let childBaseName := s!"abi_child_base_{index}_{dynamicIndex}"
      let maximum := maximumLengths[dynamicIndex]!
      let childPtrBase := calldataPtr + 4 + wordOffset * 32
      let mut highChild : Array Insn := #[.i32Const 0]
      for byte in [0:28] do highChild := highChild ++ #[.localGet offsetName,
        .i32Const (childPtrBase + byte), .plain "i32.add", .load "i32.load8_u" 0, .plain "i32.or"]
      body := body ++ rejectIf highChild ++ #[.localGet offsetName, .i32Const (childPtrBase + 28),
        .plain "i32.add", .load "i32.load8_u" 0, .i32Const 24, .plain "i32.shl",
        .localGet offsetName, .i32Const (childPtrBase + 29), .plain "i32.add", .load "i32.load8_u" 0,
        .i32Const 16, .plain "i32.shl", .plain "i32.or",
        .localGet offsetName, .i32Const (childPtrBase + 30), .plain "i32.add", .load "i32.load8_u" 0,
        .i32Const 8, .plain "i32.shl", .plain "i32.or",
        .localGet offsetName, .i32Const (childPtrBase + 31), .plain "i32.add", .load "i32.load8_u" 0,
        .plain "i32.or", .localSet childOffsetName]
      body := body ++ rejectIf #[.localGet childOffsetName, .i32Const 31, .plain "i32.and"]
      body := body ++ rejectIf #[.localGet childOffsetName, .i32Const tupleHeadBytes, .plain "i32.lt_u"]
      body := body ++ rejectIf #[.localGet childOffsetName, .localGet "args_len",
        .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
      body := body ++ rejectIf #[.localGet offsetName, .localGet childOffsetName, .plain "i32.add",
        .i32Const 32, .plain "i32.add", .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
      let lengthBase := calldataPtr + 4 + 28
      let mut highLength : Array Insn := #[.i32Const 0]
      for byte in [0:28] do highLength := highLength ++ #[.localGet offsetName,
        .localGet childOffsetName, .plain "i32.add", .i32Const (calldataPtr + 4 + byte),
        .plain "i32.add", .load "i32.load8_u" 0, .plain "i32.or"]
      body := body ++ rejectIf highLength
      body := body ++ #[.localGet offsetName, .localGet childOffsetName, .plain "i32.add",
        .i32Const lengthBase, .plain "i32.add", .load "i32.load8_u" 0, .i32Const 24, .plain "i32.shl",
        .localGet offsetName, .localGet childOffsetName, .plain "i32.add", .i32Const (lengthBase + 1),
        .plain "i32.add", .load "i32.load8_u" 0, .i32Const 16, .plain "i32.shl", .plain "i32.or",
        .localGet offsetName, .localGet childOffsetName, .plain "i32.add", .i32Const (lengthBase + 2),
        .plain "i32.add", .load "i32.load8_u" 0, .i32Const 8, .plain "i32.shl", .plain "i32.or",
        .localGet offsetName, .localGet childOffsetName, .plain "i32.add", .i32Const (lengthBase + 3),
        .plain "i32.add", .load "i32.load8_u" 0, .plain "i32.or", .localSet lengthName]
      body := body ++ rejectIf #[.localGet lengthName, .i32Const maximum, .plain "i32.gt_u"]
      match field with
      | .bytes | .string =>
          body := body ++ rejectIf #[.localGet offsetName, .localGet childOffsetName, .plain "i32.add",
            .i32Const 32, .plain "i32.add", .localGet lengthName, .i32Const 31, .plain "i32.add",
            .i32Const 4294967264, .plain "i32.and", .plain "i32.add",
            .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i32.gt_u"]
          body := body ++ #[.localGet childOffsetName, .i32Const 32, .plain "i32.add",
            .localGet lengthName, .i32Const 31, .plain "i32.add", .i32Const 4294967264,
            .plain "i32.and", .plain "i32.add", .localGet extentName, .plain "i32.gt_u",
            .if_ (.mk #[.localGet childOffsetName, .i32Const 32, .plain "i32.add",
              .localGet lengthName, .i32Const 31, .plain "i32.add", .i32Const 4294967264,
              .plain "i32.and", .plain "i32.add", .localSet extentName]) .empty]
      | .dynamicArray element =>
          if maximum > 64 then
            throw { message := s!"direct Wasm nested dynamic-array maximum {maximum} exceeds validation limit 64" }
          let elementWords <- staticAbiWords 2048 element |>.mapError fun error => { message := error.message }
          let stride := elementWords * 32
          body := body ++ rejectIf #[.localGet offsetName, .localGet childOffsetName, .plain "i32.add",
            .i32Const 32, .plain "i32.add", .localGet lengthName, .i32Const stride,
            .plain "i32.mul", .plain "i32.add", .localGet "args_len", .i32Const 4,
            .plain "i32.sub", .plain "i32.gt_u"]
          body := body ++ #[.localGet offsetName, .localGet childOffsetName,
            .plain "i32.add", .localSet childBaseName]
          for item in [0:maximum] do
            let (checks, _) <- validateDynamicStatic childBaseName 32 (item * elementWords) element
            body := body ++ #[.localGet lengthName, .i32Const item, .plain "i32.gt_u",
              .if_ (.mk checks) .empty]
          body := body ++ #[.localGet childOffsetName, .i32Const 32, .plain "i32.add",
            .localGet lengthName, .i32Const stride, .plain "i32.mul", .plain "i32.add",
            .localGet extentName, .plain "i32.gt_u", .if_ (.mk #[.localGet childOffsetName,
              .i32Const 32, .plain "i32.add", .localGet lengthName, .i32Const stride,
              .plain "i32.mul", .plain "i32.add", .localSet extentName]) .empty]
      | _ => throw { message := "direct Wasm dynamic tuple child requires recursive bound planning" }
      dynamicIndex := dynamicIndex + 1
      wordOffset := wordOffset + 1
    else
      let (checks, next) ← validateDynamicStatic offsetName 0 wordOffset field
      body := body ++ checks
      wordOffset := next
  pure <| #[.i32Const tupleHeadBytes, .localSet extentName] ++ body ++
    #[.localGet offsetName, .i32Const (calldataPtr + 4), .plain "i32.add",
      .plain "i64.extend_i32_u", .localGet extentName, .plain "i64.extend_i32_u"]

private def recursiveLocal (kind : String) (depth : Nat) : String :=
  s!"abi_recursive_{kind}_{depth}"

private def recursiveAddress (baseName : String) (bias : Nat) : Array Insn := #[
  .localGet baseName, .i32Const (calldataPtr + 4 + bias), .plain "i32.add"]

private def recursiveRangeCheck (baseName : String) (bias : Nat) : Array Insn :=
  rejectIf #[.localGet baseName, .plain "i64.extend_i32_u", .i64Const (bias + 32),
    .plain "i64.add", .localGet "args_len", .i32Const 4, .plain "i32.sub",
    .plain "i64.extend_i32_u", .plain "i64.gt_u"]

private def recursiveReadU32 (baseName : String) (bias : Nat) (output : String) : Array Insn := Id.run do
  let mut high : Array Insn := #[.i32Const 0]
  for byte in [0:28] do
    high := high ++ recursiveAddress baseName (bias + byte) ++
      #[.load "i32.load8_u" 0, .plain "i32.or"]
  recursiveRangeCheck baseName bias ++ rejectIf high ++
    recursiveAddress baseName (bias + 28) ++ #[.load "i32.load8_u" 0,
      .i32Const 24, .plain "i32.shl"] ++ recursiveAddress baseName (bias + 29) ++
    #[.load "i32.load8_u" 0, .i32Const 16, .plain "i32.shl", .plain "i32.or"] ++
    recursiveAddress baseName (bias + 30) ++ #[.load "i32.load8_u" 0,
      .i32Const 8, .plain "i32.shl", .plain "i32.or"] ++
    recursiveAddress baseName (bias + 31) ++ #[.load "i32.load8_u" 0,
      .plain "i32.or", .localSet output]

private def recursiveAbsoluteBound (baseName offsetName : String) (bias : Nat := 0) : Array Insn :=
  rejectIf #[.localGet baseName, .plain "i64.extend_i32_u", .localGet offsetName,
    .plain "i64.extend_i32_u", .plain "i64.add", .i64Const bias, .plain "i64.add",
    .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i64.extend_i32_u",
    .plain "i64.gt_u"]

private partial def validateRecursiveDynamicValue (type : StylusAbiType)
    (maximums : Array Nat) (policyIndex depth : Nat) :
    Except LowerError (Array Insn × Nat) := do
  let baseName := recursiveLocal "base" depth
  let offsetName := recursiveLocal "offset" depth
  let lengthName := recursiveLocal "length" depth
  let endName := recursiveLocal "end" depth
  match type with
  | .bytes | .string =>
      let some maximum := maximums[policyIndex]?
        | throw { message := s!"direct Wasm recursive policy {policyIndex} is missing" }
      let mut body := recursiveReadU32 baseName 0 lengthName
      body := body ++ rejectIf #[.localGet lengthName, .i32Const maximum, .plain "i32.gt_u"]
      body := body ++ rejectIf #[.localGet baseName, .plain "i64.extend_i32_u", .i64Const 32,
        .plain "i64.add", .localGet lengthName, .i32Const 31, .plain "i32.add",
        .i32Const 4294967264, .plain "i32.and", .plain "i64.extend_i32_u", .plain "i64.add",
        .localGet "args_len", .i32Const 4, .plain "i32.sub", .plain "i64.extend_i32_u",
        .plain "i64.gt_u"]
      body := body ++ #[.localGet baseName, .i32Const 32, .plain "i32.add",
        .localGet lengthName, .i32Const 31, .plain "i32.add", .i32Const 4294967264,
        .plain "i32.and", .plain "i32.add", .localSet endName]
      pure (body, policyIndex + 1)
  | .dynamicArray element =>
      let some maximum := maximums[policyIndex]?
        | throw { message := s!"direct Wasm recursive policy {policyIndex} is missing" }
      if maximum > 64 then
        throw { message := s!"direct Wasm recursive array maximum {maximum} exceeds validation limit 64" }
      let mut body := recursiveReadU32 baseName 0 lengthName
      body := body ++ rejectIf #[.localGet lengthName, .i32Const maximum, .plain "i32.gt_u"]
      if element.isDynamic then
        body := body ++ rejectIf #[.localGet baseName, .plain "i64.extend_i32_u", .i64Const 32,
          .plain "i64.add", .localGet lengthName, .plain "i64.extend_i32_u", .i64Const 32,
          .plain "i64.mul", .plain "i64.add", .localGet "args_len", .i32Const 4,
          .plain "i32.sub", .plain "i64.extend_i32_u", .plain "i64.gt_u"]
        body := body ++ #[.localGet baseName, .i32Const 32, .plain "i32.add",
          .localGet lengthName, .i32Const 32, .plain "i32.mul", .plain "i32.add",
          .localSet endName]
        let childPolicyStart := policyIndex + 1
        let expectedChildEnd := childPolicyStart + element.dynamicPolicyArity
        for item in [0:maximum] do
          let (childChecks, childPolicyEnd) <-
            validateRecursiveDynamicValue element maximums childPolicyStart (depth + 1)
          unless childPolicyEnd == expectedChildEnd do
            throw { message := "direct Wasm recursive array policy consumption changed" }
          let childBaseName := recursiveLocal "base" (depth + 1)
          let childEndName := recursiveLocal "end" (depth + 1)
          let mut checks := recursiveReadU32 baseName (32 + item * 32) offsetName
          checks := checks ++ rejectIf #[.localGet offsetName, .i32Const 31, .plain "i32.and"]
          checks := checks ++ rejectIf #[.localGet offsetName, .localGet lengthName,
            .i32Const 32, .plain "i32.mul", .plain "i32.lt_u"]
          checks := checks ++ recursiveAbsoluteBound baseName offsetName 32 ++ #[
            .localGet baseName, .i32Const 32, .plain "i32.add", .localGet offsetName,
            .plain "i32.add", .localSet childBaseName] ++ childChecks ++ #[
            .localGet childEndName, .localGet endName, .plain "i32.gt_u",
            .if_ (.mk #[.localGet childEndName, .localSet endName]) .empty]
          body := body ++ #[.localGet lengthName, .i32Const item, .plain "i32.gt_u",
            .if_ (.mk checks) .empty]
        pure (body, expectedChildEnd)
      else
        let elementWords <- staticAbiWords 2048 element |>.mapError fun error => { message := error.message }
        let stride := elementWords * 32
        body := body ++ rejectIf #[.localGet baseName, .plain "i64.extend_i32_u", .i64Const 32,
          .plain "i64.add", .localGet lengthName, .plain "i64.extend_i32_u", .i64Const stride,
          .plain "i64.mul", .plain "i64.add", .localGet "args_len", .i32Const 4,
          .plain "i32.sub", .plain "i64.extend_i32_u", .plain "i64.gt_u"]
        for item in [0:maximum] do
          let (checks, _) <- validateDynamicStatic baseName 32 (item * elementWords) element
          body := body ++ #[.localGet lengthName, .i32Const item, .plain "i32.gt_u",
            .if_ (.mk checks) .empty]
        body := body ++ #[.localGet baseName, .i32Const 32, .plain "i32.add",
          .localGet lengthName, .i32Const stride, .plain "i32.mul", .plain "i32.add",
          .localSet endName]
        pure (body, policyIndex + 1)
  | .tuple fields =>
      if fields.isEmpty then throw { message := "direct Wasm recursive tuple is empty" }
      let headWords <- fields.foldlM (fun words (field : StylusAbiType) => do
        let width <- if field.isDynamic then pure 1 else staticAbiWords 2048 field
        checkedAdd "direct recursive tuple head" 2048 words width) 0
        |>.mapError fun (error : AbiLayoutError) => { message := error.message }
      let headBytes := headWords * 32
      let mut body := rejectIf #[.localGet baseName, .plain "i64.extend_i32_u",
        .i64Const headBytes, .plain "i64.add", .localGet "args_len", .i32Const 4,
        .plain "i32.sub", .plain "i64.extend_i32_u", .plain "i64.gt_u"] ++ #[
        .localGet baseName, .i32Const headBytes, .plain "i32.add", .localSet endName]
      let mut wordOffset := 0
      let mut nextPolicy := policyIndex
      for field in fields do
        if field.isDynamic then
          let (childChecks, afterPolicy) <-
            validateRecursiveDynamicValue field maximums nextPolicy (depth + 1)
          let childBaseName := recursiveLocal "base" (depth + 1)
          let childEndName := recursiveLocal "end" (depth + 1)
          body := body ++ recursiveReadU32 baseName (wordOffset * 32) offsetName
          body := body ++ rejectIf #[.localGet offsetName, .i32Const 31, .plain "i32.and"]
          body := body ++ rejectIf #[.localGet offsetName, .i32Const headBytes, .plain "i32.lt_u"]
          body := body ++ recursiveAbsoluteBound baseName offsetName ++ #[
            .localGet baseName, .localGet offsetName, .plain "i32.add", .localSet childBaseName] ++
            childChecks ++ #[.localGet childEndName, .localGet endName, .plain "i32.gt_u",
              .if_ (.mk #[.localGet childEndName, .localSet endName]) .empty]
          nextPolicy := afterPolicy
          wordOffset := wordOffset + 1
        else
          let (checks, next) <- validateDynamicStatic baseName 0 wordOffset field
          body := body ++ checks
          wordOffset := next
      pure (body, nextPolicy)
  | .fixedArray element size =>
      if size == 0 then throw { message := "direct Wasm recursive fixed array is empty" }
      if element.isDynamic then
        validateRecursiveDynamicValue (.tuple (Array.replicate size element)) maximums policyIndex depth
      else
        let (body, next) <- validateDynamicStatic baseName 0 0 type
        pure (body ++ #[.localGet baseName, .i32Const (next * 32), .plain "i32.add",
          .localSet endName], policyIndex)
  | _ =>
      let (body, next) <- validateDynamicStatic baseName 0 0 type
      pure (body ++ #[.localGet baseName, .i32Const (next * 32), .plain "i32.add",
        .localSet endName], policyIndex)

private def recursiveDynamicParam (index headBytes rootMaximum : Nat)
    (childMaximums : Array Nat) (type : StylusAbiType) : Except LowerError (Array Insn) := do
  let maximums := match type with
    | .bytes | .string | .dynamicArray _ => #[rootMaximum] ++ childMaximums
    | _ => childMaximums
  unless maximums.size == type.dynamicPolicyArity do
    throw { message := s!"direct Wasm recursive type needs {type.dynamicPolicyArity} maxima but {maximums.size} were provided" }
  let rootBase := recursiveLocal "base" 0
  let rootLength := recursiveLocal "length" 0
  let rootEnd := recursiveLocal "end" 0
  let headPtr := calldataPtr + 4 + index * 32
  let mut highOffset : Array Insn := #[.i32Const 0]
  for byte in [0:28] do highOffset := highOffset ++ #[.i32Const (headPtr + byte),
    .load "i32.load8_u" 0, .plain "i32.or"]
  let mut body := rejectIf highOffset ++ decodeU32BE (headPtr + 28) rootBase
  body := body ++ rejectIf #[.localGet rootBase, .i32Const 31, .plain "i32.and"]
  body := body ++ rejectIf #[.localGet rootBase, .i32Const headBytes, .plain "i32.lt_u"]
  let (checks, nextPolicy) <- validateRecursiveDynamicValue type maximums 0 0
  unless nextPolicy == maximums.size do
    throw { message := "direct Wasm recursive policy consumption is incomplete" }
  body := body ++ checks
  match type with
  | .bytes | .string | .dynamicArray _ =>
      pure <| body ++ #[.localGet rootBase, .i32Const (calldataPtr + 4 + 32),
        .plain "i32.add", .plain "i64.extend_i32_u", .localGet rootLength,
        .plain "i64.extend_i32_u"]
  | _ =>
      pure <| body ++ #[.localGet rootBase, .i32Const (calldataPtr + 4), .plain "i32.add",
        .plain "i64.extend_i32_u", .localGet rootEnd, .localGet rootBase, .plain "i32.sub",
        .plain "i64.extend_i32_u"]

private def methodCall (plan : StylusPlan) (method : StylusAbiMethodPlan) : Except LowerError (Array Insn) := do
  let malformed := "stylus: malformed calldata".toUTF8.data
  let headWords ← abiHeadWords (plan.resources.maxMemoryPages * 2048) method.params
    |>.mapError fun error => { message := s!"direct Wasm ABI method `{method.name}`: {error.message}" }
  let expected := 4 + headWords * 32
  let hasDynamic := method.params.any fun param => param.type.isDynamic
  let some function := plan.functions.find? (fun function => function.abiMethod == method.name)
    | throw { message := s!"direct Wasm ABI method `{method.name}` has no function plan" }
  let sizeCheck := if hasDynamic then "i32.lt_u" else "i32.ne"
  let mut body : Array Insn := #[.localGet "args_len", .i32Const expected, .plain sizeCheck,
    .if_ (.mk <| writeLiteral 32 malformed ++ #[.i32Const 32, .i32Const malformed.size,
      .call "write_result", .i32Const 1, .return_]) .empty]
  let mut headIndex := 0
  for h : index in [0:method.params.size] do
    let param := method.params[index]
    if param.type.isDynamic then
      let some functionParam := function.params[index]?
        | throw { message := s!"direct Wasm ABI method `{method.name}` parameter plan is missing" }
      let some maximum := functionParam.dynamicMaxLength?
        | throw { message := s!"direct Wasm ABI method `{method.name}` dynamic maximum is missing" }
      body := body ++ (← recursiveDynamicParam headIndex (headWords * 32) maximum
        functionParam.dynamicFieldMaxLengths param.type)
      headIndex := headIndex + 1
    else if param.type matches .fixedArray .. | .tuple .. then
      let start := headIndex
      let (checks, next) ← validateStaticAggregate headIndex param.type
      body := body ++ checks ++ #[.i64Const (calldataPtr + 4 + start * 32)]
      headIndex := next
    else
      let width <- scalarParamWidth param.type
      body := body ++ validateParam headIndex width param.type ++ decodeParam headIndex width
      headIndex := headIndex + 1
  pure <| body ++ #[.call ("__pf_" ++ method.name), .return_]

private partial def recursiveDynamicDepth : StylusAbiType -> Nat
  | .bytes | .string => 1
  | .dynamicArray element => 1 + if element.isDynamic then recursiveDynamicDepth element else 0
  | .fixedArray element _ => 1 + if element.isDynamic then recursiveDynamicDepth element else 0
  | .tuple fields => 1 + fields.foldl (fun depth field => max depth
      (if field.isDynamic then recursiveDynamicDepth field else 0)) 0
  | _ => 1

private def userEntrypoint (plan : StylusPlan) : Except LowerError Func := do
  let malformed := "stylus: malformed calldata".toUTF8.data
  let unknown := "stylus: unknown selector".toUTF8.data
  let mut dispatch := #[]
  for method in plan.abi.methods do
    dispatch := dispatch.push <| .block_ (.mk <| #[
      .localGet "selector", .const .i32 (toString (selectorNat method.selector)), .plain "i32.eq",
      .if_ (.mk (← methodCall plan method)) .empty
    ])
  let mut maxParams := 0
  let mut maxDynamicChildren := 0
  let mut maxRecursiveDepth := 0
  for method in plan.abi.methods do
    let headWords ← abiHeadWords (plan.resources.maxMemoryPages * 2048) method.params
      |>.mapError fun error => { message := s!"direct Wasm ABI method `{method.name}`: {error.message}" }
    maxParams := max maxParams headWords
    for param in method.params do
      if param.type.isDynamic then
        maxRecursiveDepth := max maxRecursiveDepth (recursiveDynamicDepth param.type)
      match param.type with
      | .tuple fields =>
          maxDynamicChildren := max maxDynamicChildren (fields.countP fun field => field.isDynamic)
      | _ => pure ()
  let mut locals := #[{ name := "selector", type := ValType.i32 }]
  for index in [0:maxParams] do
    locals := locals ++ #[{ name := s!"abi_offset_{index}", type := .i32 },
      { name := s!"abi_length_{index}", type := .i32 },
      { name := s!"abi_child_offset_{index}", type := .i32 },
      { name := s!"abi_child_length_{index}", type := .i32 },
      { name := s!"abi_tuple_extent_{index}", type := .i32 }]
    for child in [0:maxDynamicChildren] do
      locals := locals ++ #[{ name := s!"abi_child_offset_{index}_{child}", type := .i32 },
        { name := s!"abi_child_length_{index}_{child}", type := .i32 },
        { name := s!"abi_child_base_{index}_{child}", type := .i32 }]
  for depth in [0:maxRecursiveDepth] do
    locals := locals ++ #[{ name := recursiveLocal "base" depth, type := .i32 },
      { name := recursiveLocal "offset" depth, type := .i32 },
      { name := recursiveLocal "length" depth, type := .i32 },
      { name := recursiveLocal "end" depth, type := .i32 }]
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

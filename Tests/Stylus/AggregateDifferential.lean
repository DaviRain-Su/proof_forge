import ProofForge.Backend.Stylus.AbiLayout
import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.Package
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Backend.Stylus.StorageLayout.Aggregate
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def requireWords (result : Except AbiLayoutError Nat) (expected : Nat) (message : String) : IO Unit :=
  match result with
  | .ok actual => require (actual == expected) message
  | .error error => throw <| IO.userError s!"{message}: {error.message}"

def word (value : Nat) : Array UInt8 :=
  (List.range 32).toArray.map fun index => UInt8.ofNat ((value / (2 ^ (8 * (31 - index)))) % 256)

def main : IO Unit := do
  let fixedPair := StylusAbiType.fixedArray (.uint 64) 2
  let nestedTuple := StylusAbiType.tuple #[.address, fixedPair, .tuple #[.bool, .uint 128]]
  requireWords (staticAbiWords 16 fixedPair) 2 "fixed-array ABI word layout changed"
  requireWords (staticAbiWords 16 nestedTuple) 5 "nested tuple ABI word layout changed"
  requireWords (ProofForge.Backend.Stylus.StorageLayout.Aggregate.staticStorageSlots 16 nestedTuple) 5
    "nested tuple storage slot layout changed"
  requireWords (abiHeadWords 16 #[
      { name := "pair", type := fixedPair },
      { name := "payload", type := .bytes },
      { name := "meta", type := nestedTuple }]) 8
    "mixed static/dynamic ABI head layout changed"
  for result in #[
      staticAbiWords 3 nestedTuple,
      staticAbiWords 16 (.fixedArray (.uint 64) 0),
      staticAbiWords 16 (.tuple #[]),
      staticAbiWords 16 (.fixedArray (.uint 64) 17),
      ProofForge.Backend.Stylus.StorageLayout.Aggregate.staticStorageSlots 16 .bytes] do
    match result with
    | .error _ => pure ()
    | .ok words => throw <| IO.userError s!"invalid aggregate layout was accepted as {words} words"

  let arrayArgs := word 32 ++ word 2 ++ word 7 ++ word 9
  let arraySlice <- match decodeDynamicArrayArgument arrayArgs 1 0 4 (.uint 64) with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.message
  require (arraySlice.dataOffset == 64 && arraySlice.length == 2 &&
      arraySlice.elementWords == 1 && arraySlice.endOffset == 128)
    "dynamic uint64 array layout changed"
  let tupleArrayArgs := word 32 ++ word 1 ++ word 1 ++ word 7 ++ word 9
  let tupleElement := StylusAbiType.tuple #[.address, fixedPair]
  let tupleArray <- match decodeDynamicArrayArgument tupleArrayArgs 1 0 2 tupleElement with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.message
  require (tupleArray.elementWords == 3 && tupleArray.endOffset == 160)
    "dynamic static-tuple array layout changed"
  let malformedArray := word 32 ++ word 2 ++ word 7 ++
    (#[UInt8.ofNat 1] ++ Array.replicate 31 0)
  for result in #[
      decodeDynamicArrayArgument arrayArgs 1 0 1 (.uint 64),
      decodeDynamicArrayArgument malformedArray 1 0 4 (.uint 64),
      decodeDynamicArrayArgument (word 32 ++ word 3 ++ word 7) 1 0 4 (.uint 64),
      decodeDynamicArrayArgument arrayArgs 1 0 4 (.dynamicArray (.uint 64))] do
    match result with
    | .error _ => pure ()
    | .ok _ => throw <| IO.userError "invalid dynamic-array ABI vector was accepted"

  let bytesArrayArgs := word 32 ++ word 2 ++ word 64 ++ word 128 ++
    word 2 ++ "hi".toUTF8.data ++ Array.replicate 30 0 ++
    word 5 ++ "world".toUTF8.data ++ Array.replicate 27 0
  let bytesArray <- match decodeDynamicBytesArrayArgument bytesArrayArgs 1 0 3 16 with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.message
  require (bytesArray.dataOffset == 64 && bytesArray.length == 2 &&
      bytesArray.children.size == 2 && bytesArray.children[0]!.length == 2 &&
      bytesArray.children[1]!.length == 5 && bytesArray.endOffset == 256)
    "dynamic bytes-array recursive layout changed"
  for result in #[
      decodeDynamicBytesArrayArgument (word 32 ++ word 2 ++ word 32 ++ word 128 ++
        Array.replicate 128 0) 1 0 3 16,
      decodeDynamicBytesArrayArgument (word 32 ++ word 1 ++ word 65 ++ Array.replicate 96 0) 1 0 3 16,
      decodeDynamicBytesArrayArgument (word 32 ++ word 1 ++ word 4294967264 ++
        Array.replicate 96 0) 1 0 3 16,
      decodeDynamicBytesArrayArgument (word 32 ++ word 1 ++ word 32 ++ word 17 ++
        Array.replicate 32 0) 1 0 3 16,
      decodeDynamicBytesArrayArgument (word 32 ++ word 2 ++ word 64 ++ word 128 ++
        word 0 ++ Array.replicate 32 0 ++ word 10 ++ Array.replicate 5 0) 1 0 3 16] do
    match result with
    | .error _ => pure ()
    | .ok _ => throw <| IO.userError "invalid dynamic bytes-array ABI vector was accepted"

  let twoTailArgs := word 32 ++ word 7 ++ word 96 ++ word 160 ++
    word 5 ++ "hello".toUTF8.data ++ Array.replicate 27 0 ++
    word 6 ++ "你好".toUTF8.data ++ Array.replicate 26 0
  let twoTail <- match decodeDynamicTupleArgument twoTailArgs 1 0
      #[.uint 64, .bytes, .string] #[64, 64] with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.message
  require (twoTail.headWords == 3 && twoTail.dynamicFields.size == 2 &&
      twoTail.dynamicFields[0]!.length == 5 && twoTail.dynamicFields[1]!.length == 6 &&
      twoTail.endOffset == 256) "multi-tail dynamic tuple layout changed"
  let nestedArrayTupleArgs := word 32 ++ word 7 ++ word 64 ++ word 2 ++ word 7 ++ word 9
  let nestedArrayTuple <- match decodeDynamicTupleArgument nestedArrayTupleArgs 1 0
      #[.uint 64, .dynamicArray (.uint 64)] #[3] with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.message
  require (nestedArrayTuple.headWords == 2 && nestedArrayTuple.dynamicFields.size == 1 &&
      nestedArrayTuple.dynamicFields[0]!.dataOffset == 128 &&
      nestedArrayTuple.dynamicFields[0]!.length == 2 && nestedArrayTuple.endOffset == 192)
    "nested dynamic-array tuple layout changed"
  for result in #[
      decodeDynamicTupleArgument twoTailArgs 1 0 #[.uint 64, .bytes, .string] #[64],
      decodeDynamicTupleArgument (word 32 ++ word 7 ++ word 64 ++ word 160 ++ word 0 ++
        Array.replicate 64 0) 1 0 #[.uint 64, .bytes, .string] #[64, 64],
      decodeDynamicTupleArgument twoTailArgs 1 0 #[.uint 64, .bytes, .string] #[4, 64],
      decodeDynamicTupleArgument nestedArrayTupleArgs 1 0
        #[.uint 64, .dynamicArray (.uint 64)] #[1],
      decodeDynamicTupleArgument (word 32 ++ word 7 ++ word 32 ++ Array.replicate 96 0) 1 0
        #[.uint 64, .dynamicArray (.uint 64)] #[3],
      decodeDynamicTupleArgument (word 32 ++ word 7 ++ word 64 ++ word 2 ++ word 7) 1 0
        #[.uint 64, .dynamicArray (.uint 64)] #[3],
      decodeDynamicTupleArgument twoTailArgs 1 0 #[.dynamicArray (.dynamicArray (.uint 64))] #[4]] do
    match result with
    | .error _ => pure ()
    | .ok _ => throw <| IO.userError "invalid multi-tail dynamic tuple vector was accepted"

  let empty := word 32 ++ word 0
  let emptySlice <- match decodeDynamicArgument empty 1 0 64 with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (emptySlice.dataOffset == 64 && emptySlice.length == 0 && emptySlice.paddedEnd == 64)
    "empty dynamic ABI slice changed"

  let hello := word 32 ++ word 5 ++ "hello".toUTF8.data ++ Array.replicate 27 0
  let helloSlice <- match decodeDynamicArgument hello 1 0 64 with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (helloSlice.dataOffset == 64 && helloSlice.length == 5 && helloSlice.paddedEnd == 96)
    "string tail layout changed"

  for (name, calldata, maximum) in #[
      ("unaligned", word 33 ++ word 0, 64),
      ("inside-head", word 0 ++ word 0, 64),
      ("missing-length", word 64, 64),
      ("truncated-tail", word 32 ++ word 33 ++ Array.replicate 32 0, 64),
      ("over-limit", word 32 ++ word 65 ++ Array.replicate 96 0, 64)] do
    match decodeDynamicArgument calldata 1 0 maximum with
    | .error _ => pure ()
    | .ok _ => throw <| IO.userError s!"{name} dynamic ABI vector was accepted"

  let support : RendererSupportPlan := { rustSdk := .implemented, directWasm := .implemented }
  let bytesMethod : StylusAbiMethodPlan := {
    name := "echoBytes", canonicalSignature := "echoBytes(bytes)", selector := #[0xde, 0xad, 0xbe, 0x01]
    params := #[{ name := "value", type := .bytes }], returns := #[.bytes], mutability := .view
  }
  let stringMethod : StylusAbiMethodPlan := {
    name := "echoString", canonicalSignature := "echoString(string)", selector := #[0xde, 0xad, 0xbe, 0x02]
    params := #[{ name := "value", type := .string }], returns := #[.string], mutability := .view
  }
  let fixedMethod : StylusAbiMethodPlan := {
    name := "acceptFixed", canonicalSignature := "acceptFixed(uint64[2])"
    selector := #[0xde, 0xad, 0xbe, 0x03]
    params := #[{ name := "value", type := fixedPair }], returns := #[fixedPair], mutability := .view
  }
  let tupleParam := StylusAbiType.tuple #[.address, fixedPair]
  let tupleMethod : StylusAbiMethodPlan := {
    name := "acceptTuple", canonicalSignature := "acceptTuple((address,uint64[2]))"
    selector := #[0xde, 0xad, 0xbe, 0x04]
    params := #[{ name := "value", type := tupleParam }], returns := #[tupleParam], mutability := .view
  }
  let mixedMethod : StylusAbiMethodPlan := {
    name := "echoMixed", canonicalSignature := "echoMixed(uint64[2],bytes)"
    selector := #[0xde, 0xad, 0xbe, 0x05]
    params := #[{ name := "pair", type := fixedPair }, { name := "payload", type := .bytes }]
    returns := #[.bytes], mutability := .view
  }
  let arrayMethod : StylusAbiMethodPlan := {
    name := "acceptArray", canonicalSignature := "acceptArray(uint64[])"
    selector := #[0xde, 0xad, 0xbe, 0x06]
    params := #[{ name := "values", type := .dynamicArray (.uint 64) }]
    returns := #[.dynamicArray (.uint 64)], mutability := .view
  }
  let tupleArrayMethod : StylusAbiMethodPlan := {
    name := "acceptTupleArray", canonicalSignature := "acceptTupleArray((address,uint64[2])[])"
    selector := #[0xde, 0xad, 0xbe, 0x07]
    params := #[{ name := "values", type := .dynamicArray tupleParam }]
    returns := #[.dynamicArray tupleParam], mutability := .view
  }
  let dynamicTuple := StylusAbiType.tuple #[.uint 64, .bytes]
  let dynamicTupleMethod : StylusAbiMethodPlan := {
    name := "acceptDynamicTuple", canonicalSignature := "acceptDynamicTuple((uint64,bytes))"
    selector := #[0xde, 0xad, 0xbe, 0x08]
    params := #[{ name := "value", type := dynamicTuple }], returns := #[], mutability := .view
  }
  let multiDynamicTuple := StylusAbiType.tuple #[.uint 64, .bytes, .string]
  let multiDynamicTupleMethod : StylusAbiMethodPlan := {
    name := "acceptMultiDynamicTuple"
    canonicalSignature := "acceptMultiDynamicTuple((uint64,bytes,string))"
    selector := #[0xde, 0xad, 0xbe, 0x09]
    params := #[{ name := "value", type := multiDynamicTuple }], returns := #[], mutability := .view
  }
  let bytesArrayMethod : StylusAbiMethodPlan := {
    name := "acceptBytesArray", canonicalSignature := "acceptBytesArray(bytes[])"
    selector := #[0xde, 0xad, 0xbe, 0x0a]
    params := #[{ name := "values", type := .dynamicArray .bytes }], returns := #[], mutability := .view
  }
  let nestedArrayTuple := StylusAbiType.tuple #[.uint 64, .dynamicArray (.uint 64)]
  let nestedArrayTupleMethod : StylusAbiMethodPlan := {
    name := "acceptNestedArrayTuple"
    canonicalSignature := "acceptNestedArrayTuple((uint64,uint64[]))"
    selector := #[0xde, 0xad, 0xbe, 0x0b]
    params := #[{ name := "value", type := nestedArrayTuple }], returns := #[], mutability := .view
  }
  let plan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "AggregateEcho"
    abi := { methods := #[bytesMethod, stringMethod, fixedMethod, tupleMethod, mixedMethod,
      arrayMethod, tupleArrayMethod, dynamicTupleMethod, multiDynamicTupleMethod,
      bytesArrayMethod, nestedArrayTupleMethod], errors := #[] },
    storage := { words := #[] }
    functions := #[
      { id := "echoBytes", abiMethod := "echoBytes", params := #[{
          valueId := 1, name := "value", type := .bytes, dynamicMaxLength? := some 64 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[1] }], support },
      { id := "echoString", abiMethod := "echoString", params := #[{
          valueId := 2, name := "value", type := .string, dynamicMaxLength? := some 64 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[2] }], support },
      { id := "acceptFixed", abiMethod := "acceptFixed", params := #[{
          valueId := 3, name := "value", type := fixedPair }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[3] }], support },
      { id := "acceptTuple", abiMethod := "acceptTuple", params := #[{
          valueId := 4, name := "value", type := tupleParam }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[4] }], support },
      { id := "echoMixed", abiMethod := "echoMixed", params := #[
          { valueId := 5, name := "pair", type := fixedPair },
          { valueId := 6, name := "payload", type := .bytes, dynamicMaxLength? := some 64 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[6] }], support },
      { id := "acceptArray", abiMethod := "acceptArray", params := #[{
          valueId := 7, name := "values", type := .dynamicArray (.uint 64), dynamicMaxLength? := some 4 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[7] }], support },
      { id := "acceptTupleArray", abiMethod := "acceptTupleArray", params := #[{
          valueId := 8, name := "values", type := .dynamicArray tupleParam, dynamicMaxLength? := some 2 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[8] }], support },
      { id := "acceptDynamicTuple", abiMethod := "acceptDynamicTuple", params := #[{
          valueId := 9, name := "value", type := dynamicTuple, dynamicMaxLength? := some 64
          dynamicFieldMaxLengths := #[64] }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[] }], support },
      { id := "acceptMultiDynamicTuple", abiMethod := "acceptMultiDynamicTuple", params := #[{
          valueId := 10, name := "value", type := multiDynamicTuple, dynamicMaxLength? := some 64,
          dynamicFieldMaxLengths := #[64, 64] }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[] }], support },
      { id := "acceptBytesArray", abiMethod := "acceptBytesArray", params := #[{
          valueId := 11, name := "values", type := .dynamicArray .bytes, dynamicMaxLength? := some 3,
          dynamicFieldMaxLengths := #[16] }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[] }], support },
      { id := "acceptNestedArrayTuple", abiMethod := "acceptNestedArrayTuple", params := #[{
          valueId := 12, name := "value", type := nestedArrayTuple, dynamicMaxLength? := some 64,
          dynamicFieldMaxLengths := #[3] }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[] }], support }
    ]
    events := #[], calls := #[]
    hostOps := #[
      { id := "bytes.value", functionId := "echoBytes", operation := .msgValue, support },
      { id := "bytes.result", functionId := "echoBytes", operation := .writeResult, support },
      { id := "string.value", functionId := "echoString", operation := .msgValue, support },
      { id := "string.result", functionId := "echoString", operation := .writeResult, support },
      { id := "fixed.value", functionId := "acceptFixed", operation := .msgValue, support },
      { id := "fixed.result", functionId := "acceptFixed", operation := .writeResult, support },
      { id := "tuple.value", functionId := "acceptTuple", operation := .msgValue, support },
      { id := "tuple.result", functionId := "acceptTuple", operation := .writeResult, support },
      { id := "mixed.value", functionId := "echoMixed", operation := .msgValue, support },
      { id := "mixed.result", functionId := "echoMixed", operation := .writeResult, support },
      { id := "array.value", functionId := "acceptArray", operation := .msgValue, support },
      { id := "array.result", functionId := "acceptArray", operation := .writeResult, support },
      { id := "tuple-array.value", functionId := "acceptTupleArray", operation := .msgValue, support },
      { id := "tuple-array.result", functionId := "acceptTupleArray", operation := .writeResult, support },
      { id := "dynamic-tuple.value", functionId := "acceptDynamicTuple", operation := .msgValue, support },
      { id := "dynamic-tuple.result", functionId := "acceptDynamicTuple", operation := .writeResult, support },
      { id := "multi-dynamic-tuple.value", functionId := "acceptMultiDynamicTuple", operation := .msgValue, support },
      { id := "multi-dynamic-tuple.result", functionId := "acceptMultiDynamicTuple", operation := .writeResult, support },
      { id := "bytes-array.value", functionId := "acceptBytesArray", operation := .msgValue, support },
      { id := "bytes-array.result", functionId := "acceptBytesArray", operation := .writeResult, support },
      { id := "nested-array-tuple.value", functionId := "acceptNestedArrayTuple", operation := .msgValue, support },
      { id := "nested-array-tuple.result", functionId := "acceptNestedArrayTuple", operation := .writeResult, support }
    ]
    resources := { maxMemoryPages := 1, requiresStorageFlush := false }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  let direct <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  let crate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  IO.FS.createDirAll "build/stylus/aggregate-differential"
  IO.FS.writeFile "build/stylus/aggregate-differential/echo.wat"
    (ProofForge.Compiler.Wasm.Printer.render direct)
  let cratePath := System.FilePath.mk "build/stylus/aggregate-differential/rust"
  if ← cratePath.pathExists then IO.FS.removeDirAll cratePath
  match ← ProofForge.Backend.Stylus.writeCrateAtomic crate cratePath with
  | .ok () => pure () | .error error => throw <| IO.userError error.message
  IO.println "stylus-aggregate-differential: ok"

import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus

def main : IO Unit := do
  let support : RendererSupportPlan := { rustSdk := .planned, directWasm := .implemented }
  let invokeMethod : StylusAbiMethodPlan := {
    name := "invoke", canonicalSignature := "invoke(address)", selector := #[0xca, 0x12, 0x00, 0x01]
    params := #[{ name := "target", type := .address }], returns := #[.uint 64]
  }
  let callbackMethod : StylusAbiMethodPlan := {
    name := "callback", canonicalSignature := "callback()", selector := #[0xca, 0x12, 0x00, 0x02]
    returns := #[.uint 64]
  }
  let revertMethod : StylusAbiMethodPlan := {
    name := "callbackRevert", canonicalSignature := "callbackRevert()", selector := #[0xca, 0x12, 0x00, 0x03]
  }
  let outerRevertMethod : StylusAbiMethodPlan := {
    name := "invokeThenRevert", canonicalSignature := "invokeThenRevert(address)",
    selector := #[0xca, 0x12, 0x00, 0x04], params := #[{ name := "target", type := .address }]
  }
  let staticMethod : StylusAbiMethodPlan := {
    name := "invokeStatic", canonicalSignature := "invokeStatic(address)"
    selector := #[0xca, 0x12, 0x00, 0x05], params := #[{ name := "target", type := .address }]
    returns := #[.uint 64], mutability := .view
  }
  let delegateMethod : StylusAbiMethodPlan := {
    name := "invokeDelegate", canonicalSignature := "invokeDelegate(address)"
    selector := #[0xca, 0x12, 0x00, 0x06], params := #[{ name := "target", type := .address }]
    returns := #[.uint 64], payable := true
  }
  let delegateCallbackMethod : StylusAbiMethodPlan := {
    name := "delegateCallback", canonicalSignature := "delegateCallback()"
    selector := #[0xca, 0x12, 0x00, 0x07], returns := #[.uint 64], payable := true
  }
  let invokeFunction : StylusFunctionPlan := {
    id := "invoke", abiMethod := "invoke", params := #[{ valueId := 1, name := "target", type := .address }]
    entryBlock := 0
    blocks := #[{
      id := 0
      operations := #[.literal 2 .string (.string "callback"), .call 3 (.uint 64) "call-3"]
      terminator := .return #[3]
    }]
    support
  }
  let callbackFunction : StylusFunctionPlan := {
    id := "callback", abiMethod := "callback", entryBlock := 0
    blocks := #[{
      id := 0
      operations := #[.literal 4 (.uint 64) (.uint 42), .storageCache "seen" 4]
      terminator := .return #[4]
    }]
    support
  }
  let revertFunction : StylusFunctionPlan := {
    id := "callbackRevert", abiMethod := "callbackRevert", entryBlock := 0
    blocks := #[{
      id := 0
      operations := #[.literal 5 (.uint 64) (.uint 99), .storageCache "seen" 5]
      terminator := .revert "callback reverted"
    }]
    support
  }
  let outerRevertFunction : StylusFunctionPlan := {
    id := "invokeThenRevert", abiMethod := "invokeThenRevert"
    params := #[{ valueId := 6, name := "target", type := .address }]
    entryBlock := 0
    blocks := #[{
      id := 0
      operations := #[.literal 7 .string (.string "callback"), .call 8 (.uint 64) "call-8"]
      terminator := .revert "outer reverted"
    }]
    support
  }
  let staticFunction : StylusFunctionPlan := {
    id := "invokeStatic", abiMethod := "invokeStatic"
    params := #[{ valueId := 9, name := "target", type := .address }]
    entryBlock := 0
    blocks := #[{
      id := 0
      operations := #[.literal 10 .string (.string "callback"), .call 11 (.uint 64) "call-11"]
      terminator := .return #[11]
    }]
    support
  }
  let delegateFunction : StylusFunctionPlan := {
    id := "invokeDelegate", abiMethod := "invokeDelegate"
    params := #[{ valueId := 12, name := "target", type := .address }]
    entryBlock := 0
    blocks := #[{
      id := 0
      operations := #[.literal 13 .string (.string "delegateCallback"), .call 14 (.uint 64) "call-14"]
      terminator := .return #[14]
    }]
    support
  }
  let delegateCallbackFunction : StylusFunctionPlan := {
    id := "delegateCallback", abiMethod := "delegateCallback", entryBlock := 0
    blocks := #[{ id := 0, operations := #[
      .contextRead 15 .address .msgSender, .storageCache "delegateSender" 15,
      .contextRead 16 (.uint 128) .msgValue, .storageCache "delegateValue" 16,
      .contextRead 17 .address .contractAddress, .storageCache "delegateContract" 17,
      .literal 18 (.uint 64) (.uint 42)], terminator := .return #[18] }], support
  }
  let plan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "ReentrantDirect"
    abi := { methods := #[invokeMethod, callbackMethod, revertMethod, outerRevertMethod,
      staticMethod, delegateMethod, delegateCallbackMethod], errors := #[] }
    storage := { words := #[{
      id := "seen", slot := .literal (Array.replicate 32 0), byteOffset := 24,
      byteWidth := 8, type := .uint 64
    }, {
      id := "delegateSender", slot := .literal (Array.replicate 31 0 ++ #[1]),
      byteOffset := 12, byteWidth := 20, type := .address
    }, {
      id := "delegateValue", slot := .literal (Array.replicate 31 0 ++ #[2]),
      byteOffset := 16, byteWidth := 16, type := .uint 128
    }, {
      id := "delegateContract", slot := .literal (Array.replicate 31 0 ++ #[3]),
      byteOffset := 12, byteWidth := 20, type := .address
    }] }
    functions := #[invokeFunction, callbackFunction, revertFunction, outerRevertFunction,
      staticFunction, delegateFunction, delegateCallbackFunction]
    events := #[], calls := #[{
      id := "call-3", mode := .call, canonicalSignature := "callback()", target := 1, method := 2,
      returnType := .uint 64, cachePolicy := .clear, support
    }, {
      id := "call-8", mode := .call, canonicalSignature := "callback()", target := 6, method := 7,
      returnType := .uint 64, cachePolicy := .clear, support
    }, {
      id := "call-11", mode := .staticCall, canonicalSignature := "callback()", target := 9, method := 10,
      returnType := .uint 64, cachePolicy := .flush, support
    }, {
      id := "call-14", mode := .delegateCall, canonicalSignature := "delegateCallback()",
      target := 12, method := 13, returnType := .uint 64, cachePolicy := .clear, support
    }]
    hostOps := #[
      { id := "invoke.value", functionId := "invoke", operation := .msgValue, support },
      { id := "invoke.flush", functionId := "invoke", operation := .storageFlush, support },
      { id := "invoke.keccak", functionId := "invoke", operation := .keccak256, support },
      { id := "invoke.call", functionId := "invoke", operation := .callContract, support },
      { id := "invoke.return", functionId := "invoke", operation := .readReturnData, support },
      { id := "invoke.result", functionId := "invoke", operation := .writeResult, support },
      { id := "callback.value", functionId := "callback", operation := .msgValue, support },
      { id := "callback.cache", functionId := "callback", operation := .storageCache, support },
      { id := "callback.flush", functionId := "callback", operation := .storageFlush, support },
      { id := "callback.result", functionId := "callback", operation := .writeResult, support },
      { id := "revert.value", functionId := "callbackRevert", operation := .msgValue, support },
      { id := "revert.cache", functionId := "callbackRevert", operation := .storageCache, support },
      { id := "revert.result", functionId := "callbackRevert", operation := .writeResult, support },
      { id := "outer.value", functionId := "invokeThenRevert", operation := .msgValue, support },
      { id := "outer.flush", functionId := "invokeThenRevert", operation := .storageFlush, support },
      { id := "outer.keccak", functionId := "invokeThenRevert", operation := .keccak256, support },
      { id := "outer.call", functionId := "invokeThenRevert", operation := .callContract, support },
      { id := "outer.return", functionId := "invokeThenRevert", operation := .readReturnData, support },
      { id := "outer.result", functionId := "invokeThenRevert", operation := .writeResult, support },
      { id := "static.value", functionId := "invokeStatic", operation := .msgValue, support },
      { id := "static.flush", functionId := "invokeStatic", operation := .storageFlush, support },
      { id := "static.keccak", functionId := "invokeStatic", operation := .keccak256, support },
      { id := "static.call", functionId := "invokeStatic", operation := .staticCallContract, support },
      { id := "static.return", functionId := "invokeStatic", operation := .readReturnData, support },
      { id := "static.result", functionId := "invokeStatic", operation := .writeResult, support },
      { id := "delegate.value", functionId := "invokeDelegate", operation := .msgValue, support },
      { id := "delegate.flush", functionId := "invokeDelegate", operation := .storageFlush, support },
      { id := "delegate.keccak", functionId := "invokeDelegate", operation := .keccak256, support },
      { id := "delegate.call", functionId := "invokeDelegate", operation := .delegateCallContract, support },
      { id := "delegate.return", functionId := "invokeDelegate", operation := .readReturnData, support },
      { id := "delegate.result", functionId := "invokeDelegate", operation := .writeResult, support },
      { id := "delegate-callback.sender", functionId := "delegateCallback", operation := .msgSender, support },
      { id := "delegate-callback.value", functionId := "delegateCallback", operation := .msgValue, support },
      { id := "delegate-callback.contract", functionId := "delegateCallback", operation := .contractAddress, support },
      { id := "delegate-callback.cache", functionId := "delegateCallback", operation := .storageCache, support },
      { id := "delegate-callback.result", functionId := "delegateCallback", operation := .writeResult, support }
    ]
    resources := { maxMemoryPages := 1, requiresStorageFlush := true }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  let module <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.message
  IO.FS.createDirAll "build/stylus/reentrant"
  IO.FS.writeFile "build/stylus/reentrant/reentrant.wat" (ProofForge.Compiler.Wasm.Printer.render module)
  IO.println "stylus-reentrant-direct: ok"

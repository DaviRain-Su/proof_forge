import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus

def main : IO Unit := do
  let support : RendererSupportPlan := { rustSdk := .planned, directWasm := .implemented }
  let method : StylusAbiMethodPlan := {
    name := "invoke", canonicalSignature := "invoke(address)", selector := #[0xca, 0x11, 0x00, 0x01]
    params := #[{ name := "target", type := .address }], returns := #[.uint 64], mutability := .view
  }
  let staticMethod : StylusAbiMethodPlan := { method with
    name := "invokeStatic", canonicalSignature := "invokeStatic(address)", selector := #[0xca, 0x11, 0x00, 0x02] }
  let delegateMethod : StylusAbiMethodPlan := { method with
    name := "invokeDelegate", canonicalSignature := "invokeDelegate(address)", selector := #[0xca, 0x11, 0x00, 0x03] }
  let argsMethod : StylusAbiMethodPlan := { method with
    name := "invokeArgs", canonicalSignature := "invokeArgs(address,uint64,uint64)",
    selector := #[0xca, 0x11, 0x00, 0x04], params := #[
      { name := "target", type := .address }, { name := "a", type := .uint 64 },
      { name := "b", type := .uint 64 }] }
  let valueMethod : StylusAbiMethodPlan := { method with
    name := "invokeValue", canonicalSignature := "invokeValue(address,uint128)",
    selector := #[0xca, 0x11, 0x00, 0x05], params := #[
      { name := "target", type := .address }, { name := "amount", type := .uint 128 }] }
  let plan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "RemoteCallDirect"
    abi := { methods := #[method, staticMethod, delegateMethod, argsMethod, valueMethod], errors := #[] }, storage := { words := #[] }
    functions := #[{
      id := "invoke", abiMethod := "invoke", params := #[{ valueId := 1, name := "target", type := .address }]
      entryBlock := 0
      blocks := #[{
        id := 0
        operations := #[
          StylusOpPlan.literal 2 StylusAbiType.string (StylusLiteralPlan.string "ping"),
          StylusOpPlan.call 3 (.uint 64) "call-3"
        ]
        terminator := .return #[3]
      }]
      support
    }, {
      id := "invokeStatic", abiMethod := "invokeStatic", params := #[{ valueId := 4, name := "target", type := .address }]
      entryBlock := 0, blocks := #[{ id := 0, operations := #[
        .literal 5 .string (.string "ping"), .call 6 (.uint 64) "call-6"], terminator := .return #[6] }], support
    }, {
      id := "invokeDelegate", abiMethod := "invokeDelegate", params := #[{ valueId := 7, name := "target", type := .address }]
      entryBlock := 0, blocks := #[{ id := 0, operations := #[
        .literal 8 .string (.string "ping"), .call 9 (.uint 64) "call-9"], terminator := .return #[9] }], support
    }, {
      id := "invokeArgs", abiMethod := "invokeArgs", params := #[
        { valueId := 10, name := "target", type := .address }, { valueId := 11, name := "a", type := .uint 64 },
        { valueId := 12, name := "b", type := .uint 64 }]
      entryBlock := 0, blocks := #[{ id := 0, operations := #[
        .literal 13 .string (.string "ping"), .call 14 (.uint 64) "call-14"], terminator := .return #[14] }], support
    }, {
      id := "invokeValue", abiMethod := "invokeValue", params := #[
        { valueId := 15, name := "target", type := .address }, { valueId := 16, name := "amount", type := .uint 128 }]
      entryBlock := 0, blocks := #[{ id := 0, operations := #[
        .literal 17 .string (.string "pay"), .call 18 (.uint 64) "call-18"], terminator := .return #[18] }], support
    }]
    events := #[], calls := #[{
      id := "call-3", mode := .call, canonicalSignature := "ping()", target := 1, method := 2,
      returnType := .uint 64, cachePolicy := .clear, support
    }, {
      id := "call-6", mode := .staticCall, canonicalSignature := "ping()", target := 4, method := 5,
      returnType := .uint 64, cachePolicy := .flush, support
    }, {
      id := "call-9", mode := .delegateCall, canonicalSignature := "ping()", target := 7, method := 8,
      returnType := .uint 64, cachePolicy := .clear, support
    }, {
      id := "call-14", mode := .call, canonicalSignature := "ping(uint64,uint64)", target := 10, method := 13,
      arguments := #[11, 12], paramTypes := #[.uint 64, .uint 64], returnType := .uint 64,
      cachePolicy := .clear, support
    }, {
      id := "call-18", mode := .call, canonicalSignature := "pay()", target := 15, method := 17,
      returnType := .uint 64, value? := some 16, valueType? := some (.uint 128),
      cachePolicy := .clear, support
    }]
    hostOps := #[
      { id := "invoke.value", functionId := "invoke", operation := .msgValue, support },
      { id := "invoke.flush", functionId := "invoke", operation := .storageFlush, support },
      { id := "invoke.keccak", functionId := "invoke", operation := .keccak256, support },
      { id := "invoke.call", functionId := "invoke", operation := .callContract, support },
      { id := "invoke.return", functionId := "invoke", operation := .readReturnData, support },
      { id := "invoke.result", functionId := "invoke", operation := .writeResult, support }
      , { id := "static.value", functionId := "invokeStatic", operation := .msgValue, support }
      , { id := "static.flush", functionId := "invokeStatic", operation := .storageFlush, support }
      , { id := "static.keccak", functionId := "invokeStatic", operation := .keccak256, support }
      , { id := "static.call", functionId := "invokeStatic", operation := .staticCallContract, support }
      , { id := "static.return", functionId := "invokeStatic", operation := .readReturnData, support }
      , { id := "static.result", functionId := "invokeStatic", operation := .writeResult, support }
      , { id := "delegate.value", functionId := "invokeDelegate", operation := .msgValue, support }
      , { id := "delegate.flush", functionId := "invokeDelegate", operation := .storageFlush, support }
      , { id := "delegate.keccak", functionId := "invokeDelegate", operation := .keccak256, support }
      , { id := "delegate.call", functionId := "invokeDelegate", operation := .delegateCallContract, support }
      , { id := "delegate.return", functionId := "invokeDelegate", operation := .readReturnData, support }
      , { id := "delegate.result", functionId := "invokeDelegate", operation := .writeResult, support }
      , { id := "args.value", functionId := "invokeArgs", operation := .msgValue, support }
      , { id := "args.flush", functionId := "invokeArgs", operation := .storageFlush, support }
      , { id := "args.keccak", functionId := "invokeArgs", operation := .keccak256, support }
      , { id := "args.call", functionId := "invokeArgs", operation := .callContract, support }
      , { id := "args.return", functionId := "invokeArgs", operation := .readReturnData, support }
      , { id := "args.result", functionId := "invokeArgs", operation := .writeResult, support }
      , { id := "pay.value", functionId := "invokeValue", operation := .msgValue, support }
      , { id := "pay.flush", functionId := "invokeValue", operation := .storageFlush, support }
      , { id := "pay.keccak", functionId := "invokeValue", operation := .keccak256, support }
      , { id := "pay.call", functionId := "invokeValue", operation := .callContract, support }
      , { id := "pay.return", functionId := "invokeValue", operation := .readReturnData, support }
      , { id := "pay.result", functionId := "invokeValue", operation := .writeResult, support }
    ]
    resources := { maxMemoryPages := 1, requiresStorageFlush := false }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  let module <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  IO.FS.createDirAll "build/stylus/remote-call"
  IO.FS.writeFile "build/stylus/remote-call/call.wat" (ProofForge.Compiler.Wasm.Printer.render module)
  IO.println "stylus-remote-call-direct: ok"

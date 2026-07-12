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
  let plan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "ReentrantDirect"
    abi := { methods := #[invokeMethod, callbackMethod, revertMethod, outerRevertMethod], errors := #[] }
    storage := { words := #[{
      id := "seen", slot := .literal (Array.replicate 32 0), byteOffset := 24,
      byteWidth := 8, type := .uint 64
    }] }
    functions := #[invokeFunction, callbackFunction, revertFunction, outerRevertFunction]
    events := #[], calls := #[{
      id := "call-3", mode := .call, canonicalSignature := "callback()", target := 1, method := 2,
      returnType := .uint 64, cachePolicy := .clear, support
    }, {
      id := "call-8", mode := .call, canonicalSignature := "callback()", target := 6, method := 7,
      returnType := .uint 64, cachePolicy := .clear, support
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
      { id := "outer.result", functionId := "invokeThenRevert", operation := .writeResult, support }
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

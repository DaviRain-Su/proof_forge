import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus

def support : RendererSupportPlan := { rustSdk := .implemented, directWasm := .implemented }

def main : IO Unit := do
  let method : StylusAbiMethodPlan := {
    name := "add", canonicalSignature := "add(uint128)", selector := #[0xaa, 0xbb, 0xcc, 0xdd]
    params := #[{ name := "amount", type := .uint 128 }], returns := #[.uint 128]
  }
  let literalMethod : StylusAbiMethodPlan := {
    name := "literal128", canonicalSignature := "literal128()", selector := #[0xde, 0xad, 0xbe, 0xef]
    returns := #[.uint 128], mutability := .view
  }
  let wrapMethod : StylusAbiMethodPlan := {
    name := "wrap", canonicalSignature := "wrap(uint128)", selector := #[0xca, 0xfe, 0xba, 0xbe]
    params := #[{ name := "amount", type := .uint 128 }], returns := #[.uint 128]
  }
  let plan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "WideArithmetic"
    abi := { methods := #[method, literalMethod, wrapMethod], errors := #[] }
    storage := { words := #[{
      id := "balance"
      slot := .literal (Array.replicate 32 0)
      byteWidth := 16
      type := .uint 128
    }] }
    functions := #[{
      id := "add", abiMethod := "add", params := #[{ valueId := 1, name := "amount", type := .uint 128 }]
      entryBlock := 0
      blocks := #[{
        id := 0
        operations := #[
        .storageLoad 2 "balance", .add 3 (.uint 128) .checked 2 1, .storageCache "balance" 3
        ]
        terminator := .return #[3]
      }]
      support
    }, {
      id := "literal128", abiMethod := "literal128", entryBlock := 0
      blocks := #[{
        id := 0
        operations := #[.literal 4 (.uint 128) (.uint 18446744073709551621)]
        terminator := .return #[4]
      }]
      support
    }, {
      id := "wrap", abiMethod := "wrap", params := #[{ valueId := 5, name := "amount", type := .uint 128 }]
      entryBlock := 0
      blocks := #[{
        id := 0
        operations := #[.storageLoad 6 "balance", .add 7 (.uint 128) .wrapping 6 5,
          .storageCache "balance" 7]
        terminator := .return #[7]
      }]
      support
    }]
    events := #[], calls := #[]
    hostOps := #[
      { id := "add.load", functionId := "add", operation := .storageLoad, support },
      { id := "add.cache", functionId := "add", operation := .storageCache, support },
      { id := "add.flush", functionId := "add", operation := .storageFlush, support },
      { id := "add.value", functionId := "add", operation := .msgValue, support },
      { id := "add.result", functionId := "add", operation := .writeResult, support },
      { id := "literal.value", functionId := "literal128", operation := .msgValue, support },
      { id := "literal.result", functionId := "literal128", operation := .writeResult, support },
      { id := "wrap.load", functionId := "wrap", operation := .storageLoad, support },
      { id := "wrap.cache", functionId := "wrap", operation := .storageCache, support },
      { id := "wrap.flush", functionId := "wrap", operation := .storageFlush, support },
      { id := "wrap.value", functionId := "wrap", operation := .msgValue, support },
      { id := "wrap.result", functionId := "wrap", operation := .writeResult, support }
    ]
    resources := { maxMemoryPages := 1, requiresStorageFlush := true }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  let module <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  IO.FS.createDirAll "build/stylus/wide-arithmetic"
  IO.FS.writeFile "build/stylus/wide-arithmetic/add.wat" (ProofForge.Compiler.Wasm.Printer.render module)
  let hugeMethod : StylusAbiMethodPlan := {
    name := "huge", canonicalSignature := "huge()", selector := #[0x01, 0x02, 0x03, 0x04]
    returns := #[.uint 128], mutability := .view
  }
  let hugePlan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "HugeScratch"
    abi := { methods := #[hugeMethod], errors := #[] }, storage := { words := #[] }
    functions := #[{
      id := "huge", abiMethod := "huge", entryBlock := 0
      blocks := #[{
        id := 0
        operations := #[.literal 3000 (.uint 128) (.uint 1)]
        terminator := .return #[3000]
      }]
      support
    }]
    events := #[], calls := #[]
    hostOps := #[
      { id := "huge.value", functionId := "huge", operation := .msgValue, support },
      { id := "huge.result", functionId := "huge", operation := .writeResult, support }
    ]
    resources := { maxMemoryPages := 1, requiresStorageFlush := false }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan hugePlan with
  | .error error =>
      if !error.message.contains "capability=memory.scratch" then
        throw <| IO.userError s!"unexpected scratch diagnostic: {error.message}"
  | .ok _ => throw <| IO.userError "wide scratch overflow was accepted"
  IO.println "stylus-wide-arithmetic: ok"

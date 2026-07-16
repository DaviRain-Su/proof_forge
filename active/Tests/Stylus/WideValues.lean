import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Backend.Stylus.Package
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def support : RendererSupportPlan := { rustSdk := .implemented, directWasm := .implemented }

def main : IO Unit := do
  let echoMethod : StylusAbiMethodPlan := {
    name := "echo128", canonicalSignature := "echo128(uint128)", selector := #[0x12, 0x34, 0x56, 0x78]
    params := #[{ name := "amount", type := .uint 128 }], returns := #[.uint 128], mutability := .view
  }
  let valueMethod : StylusAbiMethodPlan := {
    name := "value128", canonicalSignature := "value128()", selector := #[0x87, 0x65, 0x43, 0x21]
    returns := #[.uint 128], payable := true, mutability := .view
  }
  let lessMethod : StylusAbiMethodPlan := {
    name := "less128", canonicalSignature := "less128(uint128,uint128)", selector := #[0x11, 0x22, 0x33, 0x44]
    params := #[{ name := "lhs", type := .uint 128 }, { name := "rhs", type := .uint 128 }]
    returns := #[.bool], mutability := .view
  }
  let lessEqualMethod : StylusAbiMethodPlan := { lessMethod with
    name := "lessEqual128", canonicalSignature := "lessEqual128(uint128,uint128)",
    selector := #[0x11, 0x22, 0x33, 0x45] }
  let greaterMethod : StylusAbiMethodPlan := { lessMethod with
    name := "greater128", canonicalSignature := "greater128(uint128,uint128)",
    selector := #[0x11, 0x22, 0x33, 0x46] }
  let greaterEqualMethod : StylusAbiMethodPlan := { lessMethod with
    name := "greaterEqual128", canonicalSignature := "greaterEqual128(uint128,uint128)",
    selector := #[0x11, 0x22, 0x33, 0x47] }
  let plan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "WideValues"
    abi := { methods := #[echoMethod, valueMethod, lessMethod, lessEqualMethod,
      greaterMethod, greaterEqualMethod], errors := #[] }, storage := { words := #[] }
    functions := #[
      { id := "echo128", abiMethod := "echo128", params := #[{ valueId := 7, name := "amount", type := .uint 128 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[7] }], support },
      { id := "value128", abiMethod := "value128", entryBlock := 0
        blocks := #[{ id := 0, operations := #[.contextRead 8 (.uint 128) .msgValue], terminator := .return #[8] }]
        support },
      { id := "less128", abiMethod := "less128", params := #[
          { valueId := 9, name := "lhs", type := .uint 128 },
          { valueId := 10, name := "rhs", type := .uint 128 }]
        entryBlock := 0
        blocks := #[{
          id := 0
          operations := #[.compare 11 (.uint 128) .lt 9 10]
          terminator := .return #[11]
        }]
        support },
      { id := "lessEqual128", abiMethod := "lessEqual128", params := #[
          { valueId := 12, name := "lhs", type := .uint 128 }, { valueId := 13, name := "rhs", type := .uint 128 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[.compare 14 (.uint 128) .le 12 13], terminator := .return #[14] }], support },
      { id := "greater128", abiMethod := "greater128", params := #[
          { valueId := 15, name := "lhs", type := .uint 128 }, { valueId := 16, name := "rhs", type := .uint 128 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[.compare 17 (.uint 128) .gt 15 16], terminator := .return #[17] }], support },
      { id := "greaterEqual128", abiMethod := "greaterEqual128", params := #[
          { valueId := 18, name := "lhs", type := .uint 128 }, { valueId := 19, name := "rhs", type := .uint 128 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[.compare 20 (.uint 128) .ge 18 19], terminator := .return #[20] }], support }
    ]
    events := #[], calls := #[]
    hostOps := #[
      { id := "echo.result", functionId := "echo128", operation := .writeResult, support },
      { id := "echo.nonpayable", functionId := "echo128", operation := .msgValue, support },
      { id := "value.context", functionId := "value128", operation := .msgValue, support },
      { id := "value.result", functionId := "value128", operation := .writeResult, support },
      { id := "less.value", functionId := "less128", operation := .msgValue, support },
      { id := "less.result", functionId := "less128", operation := .writeResult, support },
      { id := "le.value", functionId := "lessEqual128", operation := .msgValue, support },
      { id := "le.result", functionId := "lessEqual128", operation := .writeResult, support },
      { id := "gt.value", functionId := "greater128", operation := .msgValue, support },
      { id := "gt.result", functionId := "greater128", operation := .writeResult, support },
      { id := "ge.value", functionId := "greaterEqual128", operation := .msgValue, support },
      { id := "ge.result", functionId := "greaterEqual128", operation := .writeResult, support }
    ]
    resources := { maxMemoryPages := 1, requiresStorageFlush := false }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  let module <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  let wat := ProofForge.Compiler.Wasm.Printer.render module
  require (wat.contains "(param $v7 i64)" && wat.contains "call $msg_value") "wide value lowering missing"
  let rust <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  let some lib := rust.find? "src/lib.rs" | throw <| IO.userError "Rust library missing"
  require (lib.contains "self.vm().msg_value().to::<u128>()") "Rust u128 msg.value conversion missing"
  IO.FS.createDirAll "build/stylus/wide-values"
  IO.FS.writeFile "build/stylus/wide-values/wide.wat" wat
  let cratePath := System.FilePath.mk "build/stylus/wide-values/rust"
  if ← cratePath.pathExists then IO.FS.removeDirAll cratePath
  match ← ProofForge.Backend.Stylus.writeCrateAtomic rust cratePath with
  | .ok () => pure () | .error error => throw <| IO.userError error.message
  IO.println "stylus-wide-values: ok"

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
  let plan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "WideValues"
    abi := { methods := #[echoMethod, valueMethod], errors := #[] }, storage := { words := #[] }
    functions := #[
      { id := "echo128", abiMethod := "echo128", params := #[{ valueId := 7, name := "amount", type := .uint 128 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[7] }], support },
      { id := "value128", abiMethod := "value128", entryBlock := 0
        blocks := #[{ id := 0, operations := #[.contextRead 8 (.uint 128) .msgValue], terminator := .return #[8] }]
        support }
    ]
    events := #[], calls := #[]
    hostOps := #[
      { id := "echo.result", functionId := "echo128", operation := .writeResult, support },
      { id := "echo.nonpayable", functionId := "echo128", operation := .msgValue, support },
      { id := "value.context", functionId := "value128", operation := .msgValue, support },
      { id := "value.result", functionId := "value128", operation := .writeResult, support }
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

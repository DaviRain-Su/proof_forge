import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  let method : StylusAbiMethodPlan := {
    name := "echo", canonicalSignature := "echo(uint64)", selector := #[0x62, 0x7f, 0x1c, 0x5a]
    params := #[{ name := "amount", type := .uint 64 }]
    returns := #[.uint 64], mutability := .view
  }
  let function : StylusFunctionPlan := {
    id := "echo", abiMethod := "echo", entryBlock := 0
    params := #[{ valueId := 7, name := "amount", type := .uint 64 }]
    blocks := #[{ id := 0, operations := #[], terminator := .return #[7] }]
    support := { rustSdk := .implemented, directWasm := .implemented }
  }
  let plan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "ScalarParams"
    abi := { methods := #[method], errors := #[] }, storage := { words := #[] }
    functions := #[function], events := #[], calls := #[]
    hostOps := #[{
      id := "echo.result"
      functionId := "echo"
      operation := .writeResult
      support := { rustSdk := .implemented, directWasm := .implemented }
    }, {
      id := "echo.nonpayable"
      functionId := "echo"
      operation := .msgValue
      support := { rustSdk := .implemented, directWasm := .implemented }
    }]
    resources := { maxMemoryPages := 1, requiresStorageFlush := false }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  let direct <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  let wat := ProofForge.Compiler.Wasm.Printer.render direct
  require (wat.contains "(param $v7 i64)") "direct function parameter missing"
  require (wat.contains "i32.const 36" && wat.contains "call $__pf_echo")
    "direct ABI parameter dispatch missing"
  IO.FS.createDirAll "build/stylus/scalar-params"
  IO.FS.writeFile "build/stylus/scalar-params/echo.wat" wat
  let rust <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  let some lib := rust.find? "src/lib.rs" | throw <| IO.userError "Rust library missing"
  require (lib.contains "pub fn echo(&self, amount: u64) -> u64") "Rust ABI parameter missing"
  IO.println "stylus-scalar-params: ok"

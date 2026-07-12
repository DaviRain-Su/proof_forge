import ProofForge.Backend.Stylus.Differential
import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Compiler.Wasm.Printer
import ProofForge.Contract.Spec
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Legacy.Adapter

open ProofForge.Backend.Stylus
open ProofForge.Backend.Stylus.DirectWasm

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def counterPlan : IO StylusPlan := do
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let bundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"{repr error}"
  match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract {
      targetId := "wasm-arbitrum-stylus", calls := bundle.contract.contract.requirements } with
  | .ok plan => pure plan
  | .error error => throw <| IO.userError error.message

def main : IO Unit := do
  let plan <- counterPlan
  let module <- match lowerFromPlan plan with
    | .ok module => pure module
    | .error error => throw <| IO.userError error.message
  let wat := ProofForge.Compiler.Wasm.Printer.render module
  require (wat.contains "storage_load_bytes32" && wat.contains "storage_cache_bytes32")
    "direct Counter module omitted storage HostIO"
  require (wat.contains "(export \"user_entrypoint\")" && wat.contains "read_args")
    "direct Counter module omitted the official Stylus entrypoint"
  require (wat.contains "i32.load8_u" && wat.contains "i32.store8")
    "direct Counter module did not preserve big-endian storage words"
  let some increment := plan.functions.find? (fun function => function.id == "increment")
    | throw <| IO.userError "Counter increment function missing"
  let checkedBlocks := increment.blocks.map fun block => { block with
    operations := block.operations.map fun
      | .add result type _ lhs rhs => .add result type .checked lhs rhs
      | op => op }
  let checkedPlan := { plan with functions := plan.functions.map fun function =>
    if function.id == "increment" then { function with blocks := checkedBlocks } else function }
  let checkedModule <- match lowerFromPlan checkedPlan with
    | .ok module => pure module
    | .error error => throw <| IO.userError error.message
  let checkedWat := ProofForge.Compiler.Wasm.Printer.render checkedModule
  require (checkedWat.contains "i64.lt_u" && checkedWat.contains "write_result" &&
      checkedWat.contains "return")
    "checked add did not emit an overflow guard"
  let some firstFunction := plan.functions[0]?
    | throw <| IO.userError "Counter function missing"
  let badFunction := { firstFunction with
    support := { firstFunction.support with directWasm := .planned } }
  let badPlan := { plan with functions := plan.functions.set! 0 badFunction }
  match lowerFromPlan badPlan with
  | .ok _ => throw <| IO.userError "incomplete direct renderer was accepted"
  | .error error => do
      for field in #[plan.targetId, badFunction.id, "block=", "op=", "capability=", "renderer=direct-wasm"] do
        require (error.message.contains field) s!"incomplete diagnostic omitted `{field}`: {error.message}"
  match runCounterDifferential plan with
  | .ok report => do
      require report.allMatched "Counter differential report contains a mismatch"
      require (report.scenarios == #["initial-read", "large-set", "increment", "unknown-selector",
        "malformed-calldata", "overflow"]) "Counter differential scenario set changed"
  | .error error => throw <| IO.userError error
  IO.FS.createDirAll "build/stylus/counter-differential"
  IO.FS.writeFile "build/stylus/counter-differential/counter.wat" wat
  IO.println "stylus-counter-differential: ok"

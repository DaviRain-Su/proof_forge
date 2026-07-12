import ProofForge.Backend.Stylus.DirectWasm.Dispatch
import ProofForge.Backend.WasmHost.WasmInterpreter
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Legacy.Adapter
import ProofForge.Contract.Spec

open ProofForge.Backend.Stylus
open ProofForge.Backend.Stylus.DirectWasm

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def isError : Except ε α -> Bool
  | .error _ => true | .ok _ => false

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let bundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok bundle => pure bundle | .error error => throw <| IO.userError s!"{repr error}"
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract {
      targetId := "wasm-arbitrum-stylus", calls := bundle.contract.contract.requirements } with
    | .ok plan => pure plan | .error error => throw <| IO.userError error.message
  for method in plan.abi.methods do
    match resolveMethod plan.abi method.selector with
    | .ok resolved => require (resolved.name == method.name) s!"selector mismatch for {method.name}"
    | .error error => throw <| IO.userError s!"valid selector rejected: {repr error}"
  match resolveMethod plan.abi #[0xff, 0xff, 0xff, 0xff] with
  | .error .unknownSelector => pure () | result => throw <| IO.userError s!"unknown selector: {repr result}"
  match resolveMethod plan.abi #[0x81, 0x29, 0xfc] with
  | .error .truncatedCalldata => pure () | result => throw <| IO.userError s!"truncated selector: {repr result}"
  let boolBad := (Array.replicate 31 0).push 2
  require (isError (decodeStaticWord .bool boolBad)) "non-canonical bool accepted"
  let addressBad := #[1] ++ Array.replicate 31 0
  require (isError (decodeStaticWord .address addressBad)) "address high bits accepted"
  require ((decodeStaticWord (.uint 256) (Array.replicate 32 0xff)).isOk) "U256 max rejected"
  let some firstMethod := plan.abi.methods[0]?
    | throw <| IO.userError "Counter ABI has no methods"
  let dynamicMethod := { firstMethod with
    params := #[{ name := "value", type := .bytes }] }
  require (isError (validateAbiCompleteness { plan.abi with methods := #[dynamicMethod] }))
    "dynamic ABI method was accepted before codec implementation"
  let module <- match abiDispatcherModule plan.abi with
    | .ok module => pure module | .error error => throw <| IO.userError error.message
  let some dispatcher := module.funcs[0]?
    | throw <| IO.userError "direct ABI module has no dispatcher"
  let mut index := 0
  for method in plan.abi.methods do
    match ProofForge.Backend.WasmHost.WasmInterpreter.evalFunc module dispatcher
        #[selectorNat method.selector] ProofForge.Backend.WasmHost.WasmInterpreter.defaultFuel {} with
    | .ok (_, state) => do
        require (state.valueStack.back? == some index)
          s!"Wasm dispatcher returned wrong method index for {method.name}"
    | .error error => throw <| IO.userError s!"Wasm dispatcher failed: {error}"
    index := index + 1
  IO.FS.createDirAll "build/stylus/direct-abi"
  IO.FS.writeFile "build/stylus/direct-abi/dispatch.wat" (ProofForge.Compiler.Wasm.Printer.render module)
  IO.println "stylus-direct-abi: ok"

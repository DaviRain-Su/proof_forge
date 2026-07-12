import ProofForge.Backend.Stylus.DirectWasm.Abi
import ProofForge.Compiler.Wasm.Printer

namespace ProofForge.Backend.Stylus.DirectWasm

open ProofForge.Backend.Stylus
open ProofForge.Compiler.Wasm

def resolveMethod (abi : StylusAbiPlan) (calldata : Bytes) : Except AbiError StylusAbiMethodPlan := do
  validateAbiCompleteness abi
  let selector <- calldataSelector calldata
  let some method := abi.methods.find? (fun method => method.selector == selector)
    | throw .unknownSelector
  let expected := 4 + method.params.size * 32
  if calldata.size != expected then throw .truncatedCalldata
  let mut index := 0
  for param in method.params do
    discard <| decodeStaticWord param.type (← abiWordAt calldata index)
    index := index + 1
  pure method

private def selectorCheck (index : Nat) : Insn :=
  .if_ (.mk #[.i32Const index, .localSet "result"]) .empty

def dispatcherFunction (abi : StylusAbiPlan) : Func := {
  name := "__pf_dispatch_selector"
  exportName := some "__pf_dispatch_selector"
  params := #[{ name := "selector", type := .i32 }]
  results := #[.i32]
  locals := #[{ name := "result", type := .i32 }]
  body := .mk <| #[.const .i32 "4294967295", .localSet "result"] ++
    abi.methods.mapIdx (fun index method => .block_ (.mk #[
      .localGet "selector", .const .i32 (toString (selectorNat method.selector)), .plain "i32.eq",
      selectorCheck index
    ])) ++ #[.localGet "result"]
}

def abiDispatcherModule (abi : StylusAbiPlan) (pages : Nat := 1) : Except DirectError Module := do
  match validateAbiCompleteness abi with
  | .error error => throw { message := s!"{repr error}" }
  | .ok () => pure ()
  pure { funcs := #[dispatcherFunction abi], memory := some (← scratchMemory pages) }

end ProofForge.Backend.Stylus.DirectWasm

import ProofForge.Backend.Stylus.DirectWasm.Memory

namespace ProofForge.Backend.Stylus.DirectWasm

open ProofForge.Compiler.Wasm

def addressBytes : Nat := 20
def u256Bytes : Nat := 32
/- Context values survive across storage operations, so they must not overlap
   the 0..96 transient storage key/value scratch region. -/
def senderPtr : Nat := 512
def valuePtr : Nat := senderPtr + addressBytes
def contractPtr : Nat := valuePtr + u256Bytes

private def contextImport (name : String) (params results : Array ValType := #[]) : Import := {
  module_ := "vm_hooks"
  name
  funcName := name
  type := { params, results }
}

def contextImports : Array Import := #[
  contextImport "msg_sender" #[.i32],
  contextImport "msg_value" #[.i32],
  contextImport "contract_address" #[.i32],
  contextImport "block_number" #[] #[.i64],
  contextImport "block_timestamp" #[] #[.i64]
]

private def pointerWrapper (name host : String) (ptr : Nat) : Func := {
  name
  exportName := some name
  results := #[.i32]
  body := .mk #[.i32Const ptr, .call host, .i32Const ptr]
}

private def scalarWrapper (name host : String) : Func := {
  name
  exportName := some name
  results := #[.i64]
  body := .mk #[.call host]
}

def contextModule (pages : Nat) : Except DirectError Module := do
  let memory <- scratchMemory pages
  if contractPtr + addressBytes > pages * wasmPageBytes then
    throw { message := "Stylus context scratch region exceeds declared memory pages" }
  pure {
    imports := contextImports
    funcs := #[
      pointerWrapper "__pf_msg_sender" "msg_sender" senderPtr,
      pointerWrapper "__pf_msg_value" "msg_value" valuePtr,
      pointerWrapper "__pf_contract_address" "contract_address" contractPtr,
      scalarWrapper "__pf_block_number" "block_number",
      scalarWrapper "__pf_block_timestamp" "block_timestamp"
    ]
    memory := some memory
  }

end ProofForge.Backend.Stylus.DirectWasm

import ProofForge.Backend.Stylus.Plan
import ProofForge.Compiler.Wasm.AST

namespace ProofForge.Backend.Stylus.DirectWasm

open ProofForge.Backend.Stylus
open ProofForge.Compiler.Wasm

structure DirectError where message : String deriving Repr, BEq

private def vmImport (name : String) (params : Array ValType) (results : Array ValType := #[]) : Import := {
  module_ := "vm_hooks", name, funcName := name, type := { params, results }
}

def importForHostOp? : StylusHostOp -> Option Import
  | .storageLoad => some (vmImport "storage_load_bytes32" #[.i32, .i32])
  | .storageCache => some (vmImport "storage_cache_bytes32" #[.i32, .i32])
  | .storageFlush => some (vmImport "storage_flush_cache" #[.i32])
  | .writeResult => some (vmImport "write_result" #[.i32, .i32])
  | .calldataCopy => some (vmImport "read_args" #[.i32])
  | .msgSender => some (vmImport "msg_sender" #[.i32])
  | .msgValue => some (vmImport "msg_value" #[.i32])
  | .contractAddress => some (vmImport "contract_address" #[.i32])
  | .blockNumber => some (vmImport "block_number" #[] #[.i64])
  | .blockTimestamp => some (vmImport "block_timestamp" #[] #[.i64])
  | .keccak256 => some (vmImport "native_keccak256" #[.i32, .i32, .i32])
  | .emitLog => some (vmImport "emit_log" #[.i32, .i32, .i32])
  | _ => none

def validateImports (candidates : Array Import) : Except DirectError (Array Import) := do
  let mut imports := #[]
  for candidate in candidates do
      match imports.find? (fun existing => existing.name == candidate.name) with
      | none => imports := imports.push candidate
      | some existing =>
          unless existing.module_ == candidate.module_ &&
              existing.type.params == candidate.type.params &&
              existing.type.results == candidate.type.results do
            throw { message := s!"inconsistent duplicate Stylus import `{candidate.name}`" }
  pure imports

def selectImports (ops : Array StylusHostOpPlan) : Except DirectError (Array Import) :=
  validateImports <| ops.filterMap fun op => importForHostOp? op.operation

end ProofForge.Backend.Stylus.DirectWasm

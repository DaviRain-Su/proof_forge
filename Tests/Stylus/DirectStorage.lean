import ProofForge.Backend.Stylus.DirectWasm.Storage
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Compiler.Wasm.Printer
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Legacy.Adapter
import ProofForge.Contract.Spec

open ProofForge.Backend.Stylus
open ProofForge.Backend.Stylus.DirectWasm

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let bundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok bundle => pure bundle | .error error => throw <| IO.userError s!"{repr error}"
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract {
      targetId := "wasm-arbitrum-stylus", calls := bundle.contract.contract.requirements } with
    | .ok plan => pure plan | .error error => throw <| IO.userError error.message
  let imports <- match selectImports plan.hostOps with
    | .ok imports => pure imports | .error error => throw <| IO.userError error.message
  let importNames := imports.map (·.name)
  for expected in #["storage_load_bytes32", "storage_cache_bytes32", "storage_flush_cache", "write_result",
      "msg_value"] do
    require (importNames.contains expected) s!"missing plan-selected import `{expected}`: {importNames}"
  require (importNames.size == 5) s!"unexpected plan-selected imports: {importNames}"
  require (imports.all (fun import_ => import_.module_ == "vm_hooks")) "imports must use vm_hooks"
  let inconsistent : ProofForge.Compiler.Wasm.Import := {
    module_ := "vm_hooks", name := "storage_load_bytes32", funcName := "storage_load_bytes32",
    type := { params := #[.i64] }
  }
  match validateImports (imports.push inconsistent) with
  | .ok _ => throw <| IO.userError "inconsistent duplicate import was accepted"
  | .error error => require (error.message.contains "inconsistent duplicate") "wrong duplicate diagnostic"
  match validateScratch 0 with
  | .ok () => throw <| IO.userError "zero-page scratch memory was accepted"
  | .error _ => pure ()
  match validateScratch 1 { keyPtr := 65520, valuePtr := 65552 } with
  | .ok () => throw <| IO.userError "out-of-page scratch memory was accepted"
  | .error _ => pure ()
  let module <- match storageHelperModule imports 1 with
    | .ok module => pure module | .error error => throw <| IO.userError error.message
  let wat := ProofForge.Compiler.Wasm.Printer.render module
  require (wat.contains "(import \"vm_hooks\" \"storage_load_bytes32\" (func $storage_load_bytes32 (param i32 i32)))")
    "storage_load_bytes32 signature changed"
  require (wat.contains "(import \"vm_hooks\" \"storage_cache_bytes32\" (func $storage_cache_bytes32 (param i32 i32)))")
    "storage_cache_bytes32 signature changed"
  require (wat.contains "(import \"vm_hooks\" \"storage_flush_cache\" (func $storage_flush_cache (param i32)))")
    "storage_flush_cache signature changed"
  require (wat.contains "(import \"vm_hooks\" \"write_result\" (func $write_result (param i32 i32)))")
    "write_result signature changed"
  require (wat.contains "(import \"vm_hooks\" \"msg_value\" (func $msg_value (param i32)))")
    "nonpayable msg_value signature changed"
  require (!wat.contains "storage_read" && !wat.contains "_get" && !wat.contains "env")
    "direct storage module leaked NEAR/Soroban imports"
  IO.FS.createDirAll "build/stylus/direct-storage"
  IO.FS.writeFile "build/stylus/direct-storage/storage.wat" wat
  let maximum := 2 ^ 256 - 1
  require (wordToNat (natToWord maximum) == maximum) "U256::MAX word roundtrip failed"
  let original := (List.range 32).toArray.map UInt8.ofNat
  let field := Array.replicate 8 0xff
  let updated <- match maskedUpdate original 8 8 field with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (updated.extract 0 8 == original.extract 0 8 && updated.extract 16 32 == original.extract 16 32)
    "packed update changed unrelated bytes"
  require (updated.extract 8 16 == field) "packed update missed selected bytes"
  let preimage <- match mappingPreimage (natToWord 7) (natToWord 3) with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (preimage.size == 64 && preimage.extract 0 32 == natToWord 7 && preimage.extract 32 64 == natToWord 3)
    "mapping slot preimage is not ABI-padded key followed by base slot"
  IO.println "stylus-direct-storage: ok"

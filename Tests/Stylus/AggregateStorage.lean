import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Backend.Stylus.StorageLayout.Aggregate
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus
open ProofForge.Backend.Stylus.StorageLayout.Aggregate

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def support : RendererSupportPlan := { rustSdk := .implemented, directWasm := .implemented }

def host (functionId suffix : String) (operation : StylusHostOp) : StylusHostOpPlan := {
  id := s!"{functionId}.{suffix}", functionId, operation, support
}

def setMethod : StylusAbiMethodPlan := {
  name := "setPayload", canonicalSignature := "setPayload(bytes)", selector := #[0xaa, 0xbb, 0xcc, 0x01]
  params := #[{ name := "value", type := .bytes }]
}

def getMethod : StylusAbiMethodPlan := {
  name := "getPayload", canonicalSignature := "getPayload()", selector := #[0xaa, 0xbb, 0xcc, 0x02]
  returns := #[.bytes], mutability := .view
}

def setFunction (maximum : Nat) : StylusFunctionPlan := {
  id := "setPayload", abiMethod := "setPayload"
  params := #[{ valueId := 1, name := "value", type := .bytes, dynamicMaxLength? := some maximum }]
  entryBlock := 0
  blocks := #[{ id := 0, operations := #[.storageDynamicCache "payload" 1 maximum], terminator := .return #[] }]
  support
}

def getFunction (loadResult maximum : Nat) : StylusFunctionPlan := {
  id := "getPayload", abiMethod := "getPayload", entryBlock := 0
  blocks := #[{ id := 0, operations := #[.storageDynamicLoad loadResult "payload" maximum], terminator := .return #[loadResult] }]
  support
}

def storagePlan (loadResult : StylusValueId := 2) (maximum : Nat := 64) : StylusPlan := {
  targetId := "wasm-arbitrum-stylus", moduleName := "AggregateStorage"
  abi := { methods := #[setMethod, getMethod], errors := #[] }
  storage := { words := #[{
    id := "payload", slot := .literal (Array.replicate 32 0), type := .bytes, byteWidth := 32
  }] }
  functions := #[setFunction maximum, getFunction loadResult maximum]
  events := #[], calls := #[]
  hostOps := #[
    host "setPayload" "load" .storageLoad, host "setPayload" "cache" .storageCache,
    host "setPayload" "flush" .storageFlush, host "setPayload" "hash" .keccak256,
    host "setPayload" "value" .msgValue, host "setPayload" "result" .writeResult,
    host "getPayload" "load" .storageLoad, host "getPayload" "hash" .keccak256,
    host "getPayload" "value" .msgValue, host "getPayload" "result" .writeResult
  ]
  resources := { maxMemoryPages := 1, requiresStorageFlush := true }
  artifacts := { solidityAbi := true, typescriptClient := true }
}

def main : IO Unit := do
  let short <- match planDynamicBytesWrite 256 64 64 "hello".toUTF8.data with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (short.rootWord.size == 32 && short.rootWord.extract 0 5 == "hello".toUTF8.data &&
      short.rootWord[31]? == some 10) "short dynamic storage root encoding changed"
  require (short.dataWords.isEmpty && short.clearDataWordIndices == #[0, 1])
    "long-to-short cleanup plan changed"
  let longValue := (List.range 40).toArray.map UInt8.ofNat
  let long <- match planDynamicBytesWrite 256 64 31 longValue with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (long.rootWord[31]? == some 81 && long.dataWords.size == 2 &&
      long.dataWords[1]!.extract 0 8 == longValue.extract 32 40)
    "long dynamic storage encoding changed"
  let array <- match planDynamicArrayStorage 256 8 3 (.tuple #[.uint 64, .address]) with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (array.elementSlots == 6 && array.lengthWord[31]? == some 3)
    "dynamic-array storage sizing changed"
  for rejected in #[
      planDynamicBytesWrite 256 0 0 #[],
      planDynamicBytesWrite 256 64 65 #[],
      planDynamicBytesWrite 256 64 0 (Array.replicate 65 0)] do
    match rejected with
    | .error _ => pure ()
    | .ok _ => throw <| IO.userError "invalid dynamic storage layout was accepted"

  let plan := storagePlan
  let module <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  let wat := ProofForge.Compiler.Wasm.Printer.render module
  require (wat.contains "storage_load_bytes32" && wat.contains "storage_cache_bytes32" &&
      wat.contains "native_keccak256" && wat.contains "storage_flush_cache")
    "direct Wasm dynamic storage host path is incomplete"
  let crate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  let some rust := crate.find? "src/lib.rs" | throw <| IO.userError "generated Rust source is missing"
  require (rust.contains "StorageBytes payload;" && rust.contains "get_bytes()" &&
      rust.contains "set_bytes(&v1)") "Rust SDK dynamic storage rendering changed"
  IO.FS.createDirAll "build/stylus/aggregate-storage/rust/src"
  IO.FS.writeFile "build/stylus/aggregate-storage/storage.wat" wat
  for file in crate.files do
    IO.FS.writeFile ("build/stylus/aggregate-storage/rust/" ++ file.path) file.content

  match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan (storagePlan 300 64) with
  | .error error => do
      require (error.message.contains "capability=memory.dynamic-storage")
        s!"unexpected dynamic storage memory diagnostic: {error.message}"
  | .ok _ => throw <| IO.userError "out-of-page dynamic storage scratch was accepted"
  match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan (storagePlan 2 257) with
  | .error error => do
      require (error.message.contains "invalid maximum 257")
        s!"unexpected dynamic storage maximum diagnostic: {error.message}"
  | .ok _ => throw <| IO.userError "oversized dynamic storage maximum was accepted"
  IO.println "stylus-aggregate-storage: ok"

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

def setTextMethod : StylusAbiMethodPlan := {
  name := "setText", canonicalSignature := "setText(string)", selector := #[0xaa, 0xbb, 0xcc, 0x03]
  params := #[{ name := "value", type := .string }]
}

def getTextMethod : StylusAbiMethodPlan := {
  name := "getText", canonicalSignature := "getText()", selector := #[0xaa, 0xbb, 0xcc, 0x04]
  returns := #[.string], mutability := .view
}

def setValuesMethod : StylusAbiMethodPlan := {
  name := "setValues", canonicalSignature := "setValues(uint64[])", selector := #[0xaa, 0xbb, 0xcc, 0x05]
  params := #[{ name := "value", type := .dynamicArray (.uint 64) }]
}

def getValuesMethod : StylusAbiMethodPlan := {
  name := "getValues", canonicalSignature := "getValues()", selector := #[0xaa, 0xbb, 0xcc, 0x06]
  returns := #[.dynamicArray (.uint 64)], mutability := .view
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

def setTextFunction (maximum : Nat) : StylusFunctionPlan := {
  id := "setText", abiMethod := "setText"
  params := #[{ valueId := 3, name := "value", type := .string, dynamicMaxLength? := some maximum }]
  entryBlock := 0
  blocks := #[{ id := 0, operations := #[.storageDynamicCache "text" 3 maximum], terminator := .return #[] }]
  support
}

def getTextFunction (maximum : Nat) : StylusFunctionPlan := {
  id := "getText", abiMethod := "getText", entryBlock := 0
  blocks := #[{ id := 0, operations := #[.storageDynamicLoad 4 "text" maximum], terminator := .return #[4] }]
  support
}

def setValuesFunction : StylusFunctionPlan := {
  id := "setValues", abiMethod := "setValues"
  params := #[{ valueId := 5, name := "value", type := .dynamicArray (.uint 64), dynamicMaxLength? := some 8 }]
  entryBlock := 0
  blocks := #[{ id := 0, operations := #[.storageArrayCache "values" 5 8], terminator := .return #[] }]
  support
}

def getValuesFunction : StylusFunctionPlan := {
  id := "getValues", abiMethod := "getValues", entryBlock := 0
  blocks := #[{ id := 0, operations := #[.storageArrayLoad 6 "values" 8], terminator := .return #[6] }]
  support
}

def storagePlan (loadResult : StylusValueId := 2) (maximum : Nat := 64) : StylusPlan := {
  targetId := "wasm-arbitrum-stylus", moduleName := "AggregateStorage"
  abi := { methods := #[setMethod, getMethod, setTextMethod, getTextMethod,
    setValuesMethod, getValuesMethod], errors := #[] }
  storage := { words := #[
    { id := "payload", slot := .literal (Array.replicate 32 0), type := .bytes, byteWidth := 32 },
    { id := "text", slot := .literal (Array.replicate 31 0 ++ #[1]), type := .string, byteWidth := 32 },
    { id := "values", slot := .literal (Array.replicate 31 0 ++ #[2]),
      type := .dynamicArray (.uint 64), byteWidth := 32 }
  ] }
  functions := #[setFunction maximum, getFunction loadResult maximum,
    setTextFunction maximum, getTextFunction maximum, setValuesFunction, getValuesFunction]
  events := #[], calls := #[]
  hostOps := #[
    host "setPayload" "load" .storageLoad, host "setPayload" "cache" .storageCache,
    host "setPayload" "flush" .storageFlush, host "setPayload" "hash" .keccak256,
    host "setPayload" "value" .msgValue, host "setPayload" "result" .writeResult,
    host "getPayload" "load" .storageLoad, host "getPayload" "hash" .keccak256,
    host "getPayload" "value" .msgValue, host "getPayload" "result" .writeResult,
    host "setText" "load" .storageLoad, host "setText" "cache" .storageCache,
    host "setText" "flush" .storageFlush, host "setText" "hash" .keccak256,
    host "setText" "value" .msgValue, host "setText" "result" .writeResult,
    host "getText" "load" .storageLoad, host "getText" "hash" .keccak256,
    host "getText" "value" .msgValue, host "getText" "result" .writeResult,
    host "setValues" "load" .storageLoad, host "setValues" "cache" .storageCache,
    host "setValues" "flush" .storageFlush, host "setValues" "hash" .keccak256,
    host "setValues" "value" .msgValue, host "setValues" "result" .writeResult,
    host "getValues" "load" .storageLoad, host "getValues" "hash" .keccak256,
    host "getValues" "value" .msgValue, host "getValues" "result" .writeResult
  ]
  resources := { maxMemoryPages := 1, requiresStorageFlush := true }
  artifacts := { solidityAbi := true, typescriptClient := true }
}

def scalarArraySetMethod (element : StylusAbiType) : StylusAbiMethodPlan := {
  name := "set", canonicalSignature := "set(values)", selector := #[0xca, 0xfe, 0x00, 0x01]
  params := #[{ name := "value", type := .dynamicArray element }]
}

def scalarArrayGetMethod (element : StylusAbiType) : StylusAbiMethodPlan := {
  name := "get", canonicalSignature := "get()", selector := #[0xca, 0xfe, 0x00, 0x02]
  returns := #[.dynamicArray element], mutability := .view
}

def scalarArraySetFunction (element : StylusAbiType) : StylusFunctionPlan := {
  id := "set", abiMethod := "set"
  params := #[{ valueId := 1, name := "value", type := .dynamicArray element, dynamicMaxLength? := some 8 }]
  entryBlock := 0
  blocks := #[{ id := 0, operations := #[.storageArrayCache "values" 1 8], terminator := .return #[] }]
  support
}

def scalarArrayGetFunction : StylusFunctionPlan := {
  id := "get", abiMethod := "get", entryBlock := 0
  blocks := #[{ id := 0, operations := #[.storageArrayLoad 2 "values" 8], terminator := .return #[2] }]
  support
}

def scalarArrayPlan (label : String) (element : StylusAbiType) : StylusPlan := {
  targetId := "wasm-arbitrum-stylus", moduleName := "Array" ++ label
  abi := { methods := #[scalarArraySetMethod element, scalarArrayGetMethod element], errors := #[] }
  storage := { words := #[{
    id := "values", slot := .literal (Array.replicate 32 0), type := .dynamicArray element, byteWidth := 32
  }] }
  functions := #[scalarArraySetFunction element, scalarArrayGetFunction]
  events := #[], calls := #[]
  hostOps := #[
    host "set" "load" .storageLoad, host "set" "cache" .storageCache,
    host "set" "flush" .storageFlush, host "set" "hash" .keccak256,
    host "set" "value" .msgValue, host "set" "result" .writeResult,
    host "get" "load" .storageLoad, host "get" "hash" .keccak256,
    host "get" "value" .msgValue, host "get" "result" .writeResult
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
  let array <- match planDynamicArrayStorage 256 8 3 (.uint 64) with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (array.elementByteWidth == 8 && array.density == 4 && array.dataWords == 1 &&
      array.lengthWord[31]? == some 3)
    "dynamic-array storage sizing changed"
  let addressArray <- match planDynamicArrayStorage 256 8 3 .address with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (addressArray.density == 1 && addressArray.dataWords == 3)
    "address dynamic-array storage density changed"
  match planDynamicArrayStorage 256 8 3 (.tuple #[.uint 64, .address]) with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "composite dynamic-array packing was accepted"
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
  require (rust.contains "StorageString text;" && rust.contains "get_string()" &&
      rust.contains "set_str(&v3)") "Rust SDK string storage rendering changed"
  require (rust.contains "uint64[] values;" && rust.contains "self.values.get(index)" &&
      rust.contains "self.values.push(U64::from(*item))" &&
      rust.contains "dynamic array length exceeds maximum" &&
      rust.contains "dynamic storage length exceeds maximum") "Rust SDK array storage rendering changed"
  let rustStorageTests := r#"

#[cfg(test)]
mod aggregate_storage_oracle {
    use super::*;
    use stylus_test::TestVM;

    fn word(value: U256) -> B256 {
        B256::from(value.to_be_bytes::<32>())
    }

    #[test]
    fn bytes_string_and_packed_array_lifecycles() {
        let vm = TestVM::new();
        let mut contract = AggregateStorage::from(&vm);

        assert_eq!(contract.setPayload(b"hello".to_vec()), Ok(()));
        assert_eq!(contract.getPayload(), Ok(b"hello".to_vec()));
        let long_bytes: Vec<u8> = (0..64).collect();
        assert_eq!(contract.setPayload(long_bytes.clone()), Ok(()));
        assert_eq!(contract.getPayload(), Ok(long_bytes));
        assert_eq!(contract.setPayload(b"bye".to_vec()), Ok(()));
        assert_eq!(contract.getPayload(), Ok(b"bye".to_vec()));

        assert_eq!(contract.setText(String::from("hello")), Ok(()));
        assert_eq!(contract.getText(), Ok(String::from("hello")));
        let long_text = "x".repeat(64);
        assert_eq!(contract.setText(long_text.clone()), Ok(()));
        assert_eq!(contract.getText(), Ok(long_text));
        assert_eq!(contract.setText(String::from("你好")), Ok(()));
        assert_eq!(contract.getText(), Ok(String::from("你好")));

        assert_eq!(contract.setValues(vec![1, 2, 3]), Ok(()));
        assert_eq!(contract.getValues(), Ok(vec![1, 2, 3]));
        let slot = U256::from(2);
        let base: U256 = vm.native_keccak256(&slot.to_be_bytes::<32>()).into();
        let packed = (U256::from(3) << 128) | (U256::from(2) << 64) | U256::from(1);
        assert_eq!(vm.snapshot().storage.get(&base), Some(&word(packed)));

        assert_eq!(contract.setValues(vec![10, 20, 30, 40, 50, 60, 70, 80]), Ok(()));
        assert_eq!(contract.getValues(), Ok(vec![10, 20, 30, 40, 50, 60, 70, 80]));
        assert_eq!(contract.setValues(vec![9]), Ok(()));
        assert_eq!(contract.getValues(), Ok(vec![9]));
        assert_eq!(vm.snapshot().storage.get(&base), Some(&word(U256::from(9))));
        assert_eq!(vm.snapshot().storage.get(&(base + U256::from(1))), Some(&B256::ZERO));
        assert_eq!(contract.setValues(vec![0; 9]),
            Err(b"dynamic array length exceeds maximum".to_vec()));

        vm.set_storage(slot, word(U256::from(9)));
        assert_eq!(contract.getValues(), Err(b"corrupt dynamic array length".to_vec()));
    }
}
"#
  IO.FS.createDirAll "build/stylus/aggregate-storage/rust/src"
  IO.FS.writeFile "build/stylus/aggregate-storage/storage.wat" wat
  for file in crate.files do
    let content := if file.path == "src/lib.rs" then file.content ++ rustStorageTests else file.content
    IO.FS.writeFile ("build/stylus/aggregate-storage/rust/" ++ file.path) content

  for (label, element) in #[
      ("bool", StylusAbiType.bool), ("uint16", .uint 16), ("uint128", .uint 128),
      ("address", .address)] do
    let variant := scalarArrayPlan label element
    let variantModule <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan variant with
      | .ok value => pure value | .error error => throw <| IO.userError s!"{label}: {error.message}"
    let variantCrate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate variant with
      | .ok value => pure value | .error error => throw <| IO.userError s!"{label}: {error.message}"
    let root := "build/stylus/aggregate-storage/scalars/" ++ label
    IO.FS.createDirAll (root ++ "/rust/src")
    IO.FS.writeFile (root ++ "/storage.wat") (ProofForge.Compiler.Wasm.Printer.render variantModule)
    for file in variantCrate.files do IO.FS.writeFile (root ++ "/rust/" ++ file.path) file.content
  match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan (scalarArrayPlan "uint256" (.uint 256)) with
  | .error error => do
      require (error.message.contains "unsupported element")
        s!"unexpected uint256[] storage diagnostic: {error.message}"
  | .ok _ => throw <| IO.userError "uint256[] storage exceeded the current public ABI boundary"
  match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan (scalarArrayPlan "bytes7" (.fixedBytes 7)) with
  | .error error => do
      require (error.message.contains "unsupported element")
        s!"unexpected bytes7[] storage diagnostic: {error.message}"
  | .ok _ => throw <| IO.userError "bytes7[] storage exceeded the current public ABI boundary"

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

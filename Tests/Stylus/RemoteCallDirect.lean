import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.Package
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus

def main : IO Unit := do
  let support : RendererSupportPlan := { rustSdk := .planned, directWasm := .implemented }
  let method : StylusAbiMethodPlan := {
    name := "invoke", canonicalSignature := "invoke(address)", selector := #[0xca, 0x11, 0x00, 0x01]
    params := #[{ name := "target", type := .address }], returns := #[.uint 64], mutability := .view
  }
  let staticMethod : StylusAbiMethodPlan := { method with
    name := "invokeStatic", canonicalSignature := "invokeStatic(address)", selector := #[0xca, 0x11, 0x00, 0x02] }
  let delegateMethod : StylusAbiMethodPlan := { method with
    name := "invokeDelegate", canonicalSignature := "invokeDelegate(address)", selector := #[0xca, 0x11, 0x00, 0x03] }
  let argsMethod : StylusAbiMethodPlan := { method with
    name := "invokeArgs", canonicalSignature := "invokeArgs(address,uint64,uint64)",
    selector := #[0xca, 0x11, 0x00, 0x04], params := #[
      { name := "target", type := .address }, { name := "a", type := .uint 64 },
      { name := "b", type := .uint 64 }] }
  let valueMethod : StylusAbiMethodPlan := { method with
    name := "invokeValue", canonicalSignature := "invokeValue(address,uint128)",
    selector := #[0xca, 0x11, 0x00, 0x05], params := #[
      { name := "target", type := .address }, { name := "amount", type := .uint 128 }] }
  let gasMethod : StylusAbiMethodPlan := { method with
    name := "invokeGas", canonicalSignature := "invokeGas(address,uint64)",
    selector := #[0xca, 0x11, 0x00, 0x06], params := #[
      { name := "target", type := .address }, { name := "gas", type := .uint 64 }] }
  let bytesMethod : StylusAbiMethodPlan := { method with
    name := "invokeBytes", canonicalSignature := "invokeBytes(address)",
    selector := #[0xca, 0x11, 0x00, 0x07], params := #[{ name := "target", type := .address }],
    returns := #[.bytes] }
  let plan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "RemoteCallDirect"
    abi := { methods := #[method, staticMethod, delegateMethod, argsMethod, valueMethod, gasMethod, bytesMethod], errors := #[] }, storage := { words := #[] }
    functions := #[{
      id := "invoke", abiMethod := "invoke", params := #[{ valueId := 1, name := "target", type := .address }]
      entryBlock := 0
      blocks := #[{
        id := 0
        operations := #[
          StylusOpPlan.literal 2 StylusAbiType.string (StylusLiteralPlan.string "ping"),
          StylusOpPlan.call 3 (.uint 64) "call-3"
        ]
        terminator := .return #[3]
      }]
      support
    }, {
      id := "invokeStatic", abiMethod := "invokeStatic", params := #[{ valueId := 4, name := "target", type := .address }]
      entryBlock := 0, blocks := #[{ id := 0, operations := #[
        .literal 5 .string (.string "ping"), .call 6 (.uint 64) "call-6"], terminator := .return #[6] }], support
    }, {
      id := "invokeDelegate", abiMethod := "invokeDelegate", params := #[{ valueId := 7, name := "target", type := .address }]
      entryBlock := 0, blocks := #[{ id := 0, operations := #[
        .literal 8 .string (.string "ping"), .call 9 (.uint 64) "call-9"], terminator := .return #[9] }], support
    }, {
      id := "invokeArgs", abiMethod := "invokeArgs", params := #[
        { valueId := 10, name := "target", type := .address }, { valueId := 11, name := "a", type := .uint 64 },
        { valueId := 12, name := "b", type := .uint 64 }]
      entryBlock := 0, blocks := #[{ id := 0, operations := #[
        .literal 13 .string (.string "ping"), .call 14 (.uint 64) "call-14"], terminator := .return #[14] }], support
    }, {
      id := "invokeValue", abiMethod := "invokeValue", params := #[
        { valueId := 15, name := "target", type := .address }, { valueId := 16, name := "amount", type := .uint 128 }]
      entryBlock := 0, blocks := #[{ id := 0, operations := #[
        .literal 17 .string (.string "pay"), .call 18 (.uint 64) "call-18"], terminator := .return #[18] }], support
    }, {
      id := "invokeGas", abiMethod := "invokeGas", params := #[
        { valueId := 19, name := "target", type := .address }, { valueId := 20, name := "gas", type := .uint 64 }]
      entryBlock := 0, blocks := #[{ id := 0, operations := #[
        .literal 21 .string (.string "ping"), .call 22 (.uint 64) "call-22"], terminator := .return #[22] }], support
    }, {
      id := "invokeBytes", abiMethod := "invokeBytes", params := #[{ valueId := 23, name := "target", type := .address }]
      entryBlock := 0, blocks := #[{ id := 0, operations := #[
        .literal 24 .string (.string "data"), .call 25 .bytes "call-25"], terminator := .return #[25] }], support
    }]
    events := #[], calls := #[{
      id := "call-3", mode := .call, canonicalSignature := "ping()", target := 1, method := 2,
      returnType := .uint 64, cachePolicy := .clear, support
    }, {
      id := "call-6", mode := .staticCall, canonicalSignature := "ping()", target := 4, method := 5,
      returnType := .uint 64, cachePolicy := .flush, support
    }, {
      id := "call-9", mode := .delegateCall, canonicalSignature := "ping()", target := 7, method := 8,
      returnType := .uint 64, cachePolicy := .clear, support
    }, {
      id := "call-14", mode := .call, canonicalSignature := "ping(uint64,uint64)", target := 10, method := 13,
      arguments := #[11, 12], paramTypes := #[.uint 64, .uint 64], returnType := .uint 64,
      cachePolicy := .clear, support
    }, {
      id := "call-18", mode := .call, canonicalSignature := "pay()", target := 15, method := 17,
      returnType := .uint 64, value? := some 16, valueType? := some (.uint 128),
      cachePolicy := .clear, support
    }, {
      id := "call-22", mode := .call, canonicalSignature := "ping()", target := 19, method := 21,
      returnType := .uint 64, gas? := some 20, cachePolicy := .clear, support
    }, {
      id := "call-25", mode := .call, canonicalSignature := "data()", target := 23, method := 24,
      returnType := .bytes, returnMaxLength? := some 64, cachePolicy := .clear, support
    }]
    hostOps := #[
      { id := "invoke.value", functionId := "invoke", operation := .msgValue, support },
      { id := "invoke.flush", functionId := "invoke", operation := .storageFlush, support },
      { id := "invoke.keccak", functionId := "invoke", operation := .keccak256, support },
      { id := "invoke.call", functionId := "invoke", operation := .callContract, support },
      { id := "invoke.return", functionId := "invoke", operation := .readReturnData, support },
      { id := "invoke.result", functionId := "invoke", operation := .writeResult, support }
      , { id := "static.value", functionId := "invokeStatic", operation := .msgValue, support }
      , { id := "static.flush", functionId := "invokeStatic", operation := .storageFlush, support }
      , { id := "static.keccak", functionId := "invokeStatic", operation := .keccak256, support }
      , { id := "static.call", functionId := "invokeStatic", operation := .staticCallContract, support }
      , { id := "static.return", functionId := "invokeStatic", operation := .readReturnData, support }
      , { id := "static.result", functionId := "invokeStatic", operation := .writeResult, support }
      , { id := "delegate.value", functionId := "invokeDelegate", operation := .msgValue, support }
      , { id := "delegate.flush", functionId := "invokeDelegate", operation := .storageFlush, support }
      , { id := "delegate.keccak", functionId := "invokeDelegate", operation := .keccak256, support }
      , { id := "delegate.call", functionId := "invokeDelegate", operation := .delegateCallContract, support }
      , { id := "delegate.return", functionId := "invokeDelegate", operation := .readReturnData, support }
      , { id := "delegate.result", functionId := "invokeDelegate", operation := .writeResult, support }
      , { id := "args.value", functionId := "invokeArgs", operation := .msgValue, support }
      , { id := "args.flush", functionId := "invokeArgs", operation := .storageFlush, support }
      , { id := "args.keccak", functionId := "invokeArgs", operation := .keccak256, support }
      , { id := "args.call", functionId := "invokeArgs", operation := .callContract, support }
      , { id := "args.return", functionId := "invokeArgs", operation := .readReturnData, support }
      , { id := "args.result", functionId := "invokeArgs", operation := .writeResult, support }
      , { id := "pay.value", functionId := "invokeValue", operation := .msgValue, support }
      , { id := "pay.flush", functionId := "invokeValue", operation := .storageFlush, support }
      , { id := "pay.keccak", functionId := "invokeValue", operation := .keccak256, support }
      , { id := "pay.call", functionId := "invokeValue", operation := .callContract, support }
      , { id := "pay.return", functionId := "invokeValue", operation := .readReturnData, support }
      , { id := "pay.result", functionId := "invokeValue", operation := .writeResult, support }
      , { id := "gas.value", functionId := "invokeGas", operation := .msgValue, support }
      , { id := "gas.flush", functionId := "invokeGas", operation := .storageFlush, support }
      , { id := "gas.keccak", functionId := "invokeGas", operation := .keccak256, support }
      , { id := "gas.call", functionId := "invokeGas", operation := .callContract, support }
      , { id := "gas.return", functionId := "invokeGas", operation := .readReturnData, support }
      , { id := "gas.result", functionId := "invokeGas", operation := .writeResult, support }
      , { id := "bytes.value", functionId := "invokeBytes", operation := .msgValue, support }
      , { id := "bytes.flush", functionId := "invokeBytes", operation := .storageFlush, support }
      , { id := "bytes.keccak", functionId := "invokeBytes", operation := .keccak256, support }
      , { id := "bytes.call", functionId := "invokeBytes", operation := .callContract, support }
      , { id := "bytes.return", functionId := "invokeBytes", operation := .readReturnData, support }
      , { id := "bytes.result", functionId := "invokeBytes", operation := .writeResult, support }
    ]
    resources := { maxMemoryPages := 1, requiresStorageFlush := false }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  let module <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  IO.FS.createDirAll "build/stylus/remote-call"
  IO.FS.writeFile "build/stylus/remote-call/call.wat" (ProofForge.Compiler.Wasm.Printer.render module)
  let implemented : RendererSupportPlan := { rustSdk := .implemented, directWasm := .implemented }
  let rustPlan := { plan with
    functions := plan.functions.map (fun function => { function with support := implemented })
    calls := plan.calls.map (fun call => { call with support := implemented })
    hostOps := plan.hostOps.map (fun hostOp => { hostOp with support := implemented }) }
  let crate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate rustPlan with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"Rust remote-call rendering failed: {error.message}"
  let parityTests := r#"
#[cfg(test)]
mod remote_parity {
    use super::*;
    use stylus_test::TestVM;

    fn word(value: u64) -> Vec<u8> {
        U256::from(value).to_be_bytes::<32>().to_vec()
    }

    fn selector(vm: &TestVM, signature: &[u8]) -> Vec<u8> {
        vm.native_keccak256(signature)[..4].to_vec()
    }

    #[test]
    fn call_modes_and_failures_match_direct_vectors() {
        let vm = TestVM::new();
        let contract = RemoteCallDirect::from(&vm);
        let target = Address::from([0x22; 20]);
        let ping = selector(&vm, b"ping()");
        vm.mock_call(target, ping.clone(), U256::ZERO, Ok(word(42)));
        vm.mock_static_call(target, ping.clone(), Ok(word(42)));
        vm.mock_delegate_call(target, ping.clone(), Ok(word(42)));
        assert_eq!(contract.invoke(target), Ok(42));
        assert_eq!(contract.invokeStatic(target), Ok(42));
        assert_eq!(contract.invokeDelegate(target), Ok(42));

        vm.mock_call(target, ping.clone(), U256::ZERO, Err(vec![0xde, 0xad, 0xbe, 0xef]));
        assert_eq!(contract.invoke(target), Err(vec![0xde, 0xad, 0xbe, 0xef]));
        vm.mock_call(target, ping, U256::ZERO, Ok(Vec::new()));
        assert_eq!(contract.invoke(target), Err(b"stylus: malformed return data".to_vec()));
    }

    #[test]
    fn calldata_value_and_gas_vectors_match_direct_vectors() {
        let vm = TestVM::new();
        let contract = RemoteCallDirect::from(&vm);
        let target = Address::from([0x22; 20]);
        let mut args = selector(&vm, b"ping(uint64,uint64)");
        args.extend_from_slice(&U256::from(42).to_be_bytes::<32>());
        args.extend_from_slice(&U256::from(7).to_be_bytes::<32>());
        vm.mock_call(target, args, U256::ZERO, Ok(word(42)));
        assert_eq!(contract.invokeArgs(target, 42, 7), Ok(42));

        let amount = (1_u128 << 64) + 42;
        vm.mock_call(target, selector(&vm, b"pay()"), U256::from(amount), Ok(word(42)));
        assert_eq!(contract.invokeValue(target, amount), Ok(42));
        vm.mock_call(target, selector(&vm, b"ping()"), U256::ZERO, Ok(word(42)));
        assert_eq!(contract.invokeGas(target, 12345), Ok(42));
    }

    #[test]
    fn dynamic_return_vectors_match_direct_vectors() {
        let vm = TestVM::new();
        let contract = RemoteCallDirect::from(&vm);
        let target = Address::from([0x22; 20]);
        let data = selector(&vm, b"data()");
        let mut hello = U256::from(32).to_be_bytes::<32>().to_vec();
        hello.extend_from_slice(&U256::from(5).to_be_bytes::<32>());
        hello.extend_from_slice(b"hello");
        hello.resize(96, 0);
        vm.mock_call(target, data.clone(), U256::ZERO, Ok(hello));
        assert_eq!(contract.invokeBytes(target), Ok(b"hello".to_vec()));

        let mut bad = U256::from(64).to_be_bytes::<32>().to_vec();
        bad.extend_from_slice(&U256::ZERO.to_be_bytes::<32>());
        vm.mock_call(target, data, U256::ZERO, Ok(bad));
        assert_eq!(contract.invokeBytes(target), Err(b"stylus: malformed dynamic return data".to_vec()));
    }
}
"#
  let crate := { crate with files := crate.files.map fun file =>
    if file.path == "src/lib.rs" then { file with content := file.content ++ parityTests } else file }
  let cratePath := System.FilePath.mk "build/stylus/remote-call/rust"
  if ← cratePath.pathExists then IO.FS.removeDirAll cratePath
  match ← ProofForge.Backend.Stylus.writeCrateAtomic crate cratePath with
  | .ok () => pure ()
  | .error error => throw <| IO.userError error.message
  IO.println "stylus-remote-call-direct: ok"

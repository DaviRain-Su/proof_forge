#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EventProbe IR to EVM runtime bytecode
# and validate log emission through Foundry recorded logs.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-event-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EventProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EventProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "event-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "event-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "event-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-event --format bytecode \
  --yul-output "$OUT_DIR/EventProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EventProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EventProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EventProbe \
  --expect-source-kind portable-ir \
  --expect-capability events.emit \
  --expect-entrypoint emit_value_event:2ae8cae3 \
  --expect-entrypoint emit_typed_scalar_event:989413a3 \
  --expect-entrypoint emit_indexed_event:bc07d04f \
  --expect-entrypoint emit_indexed_typed_scalar_event:b94b71db \
  --expect-entrypoint emit_two_indexed_event:2d00700c \
  --expect-entrypoint emit_three_indexed_event:e7d142d1 \
  --expect-entrypoint emit_pair_event:35361bda \
  --expect-entrypoint emit_storage_pair_event:65123829 \
  --expect-entrypoint emit_storage_array_event:99eb21de \
  --expect-entrypoint emit_array_event:393f7138 \
  --expect-entrypoint emit_pair_array_event:85611e74 \
  --expect-entrypoint emit_matrix_event:765f1e45 \
  --expect-entrypoint emit_pair_matrix_event:315aac0a \
  --expect-entrypoint emit_storage_pair_array_event:f31d3375 \
  --expect-entrypoint emit_indexed_pair_event:e027f054 \
  --expect-entrypoint emit_indexed_storage_pair_event:f4a27402 \
  --expect-entrypoint emit_indexed_storage_array_event:42a8056e \
  --expect-entrypoint emit_indexed_array_event:b7de5dd7 \
  --expect-entrypoint emit_indexed_storage_pair_array_event:45440e6c \
  --expect-entrypoint emit_indexed_pair_array_event:c1375f82 \
  --expect-entrypoint emit_indexed_matrix_event:6a843f41 \
  --expect-entrypoint emit_indexed_pair_matrix_event:d1b4d456 \
  --expect-event 'ValueEvent:ValueEvent(uint64)' \
  --expect-event 'TypedScalarEvent:TypedScalarEvent(bool,uint32,bytes32)' \
  --expect-event 'IndexedValue:IndexedValue(uint64,uint64)' \
  --expect-event 'IndexedTypedScalar:IndexedTypedScalar(bool,uint32,bytes32,uint64)' \
  --expect-event 'IndexedTwoValues:IndexedTwoValues(uint64,uint64,uint64)' \
  --expect-event 'IndexedThreeValues:IndexedThreeValues(uint64,uint64,uint64,uint64)' \
  --expect-event 'PairEvent:PairEvent((uint64,uint64))' \
  --expect-event 'StoragePairEvent:StoragePairEvent((uint64,uint64))' \
  --expect-event 'StorageArrayEvent:StorageArrayEvent(uint64[2])' \
  --expect-event 'ArrayEvent:ArrayEvent(uint64[2])' \
  --expect-event 'PairArrayEvent:PairArrayEvent((uint64,uint64)[2])' \
  --expect-event 'MatrixEvent:MatrixEvent(uint64[2][2])' \
  --expect-event 'PairMatrixEvent:PairMatrixEvent((uint64,uint64)[2][2])' \
  --expect-event 'StoragePairArrayEvent:StoragePairArrayEvent((uint64,uint64)[2])' \
  --expect-event 'IndexedPair:IndexedPair((uint64,uint64),uint64)' \
  --expect-event 'IndexedStoragePair:IndexedStoragePair((uint64,uint64),uint64)' \
  --expect-event 'IndexedStorageArray:IndexedStorageArray(uint64[2],uint64)' \
  --expect-event 'IndexedArray:IndexedArray(uint64[2],uint64)' \
  --expect-event 'IndexedStoragePairArray:IndexedStoragePairArray((uint64,uint64)[2],uint64)' \
  --expect-event 'IndexedPairArray:IndexedPairArray((uint64,uint64)[2],uint64)' \
  --expect-event 'IndexedMatrix:IndexedMatrix(uint64[2][2],uint64)' \
  --expect-event 'IndexedPairMatrix:IndexedPairMatrix((uint64,uint64)[2][2],uint64)' \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EventProbe.bin")"

rm -rf "$FORGE_DIR"
mkdir -p "$FORGE_DIR/test"

cat > "$FORGE_DIR/foundry.toml" <<'TOML'
[profile.default]
src = "src"
test = "test"
out = "out"
libs = ["lib"]
solc_version = "0.8.30"
optimizer = true
optimizer_runs = 200
via_ir = true
TOML

cat > "$FORGE_DIR/test/ProofForgeIREventSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

contract ProofForgeIREventSmokeTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool value) internal pure {
        require(value, "assertTrue failed");
    }

    function assertFalse(bool value) internal pure {
        require(!value, "assertFalse failed");
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "assertEq(uint256) failed");
    }

    function assertEq(address actual, address expected) internal pure {
        require(actual == expected, "assertEq(address) failed");
    }

    function assertEq(bytes32 actual, bytes32 expected) internal pure {
        require(actual == expected, "assertEq(bytes32) failed");
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function packed(uint64 a, uint64 b, uint64 c, uint64 d) internal pure returns (bytes32) {
        return bytes32(
            (uint256(a) << 192) |
            (uint256(b) << 128) |
            (uint256(c) << 64) |
            uint256(d)
        );
    }

    function testIREventEmitsNamedTopicAndData() public {
        address probe = address(uint160(0xE130));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_value_event(uint256)", 42));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256(bytes("ValueEvent(uint64)")));
        assertEq(abi.decode(logs[0].data, (uint256)), 42);
    }

    function testIRTypedScalarEventEmitsBoolU32AndHashData() public {
        address probe = address(uint160(0xE141));
        deployRuntime(hex"$probe_hex", probe);
        bytes32 root = packed(1, 2, 3, 4);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_typed_scalar_event(bool,uint32,bytes32)", true, uint32(17), root));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256(bytes("TypedScalarEvent(bool,uint32,bytes32)")));
        (bool flag, uint32 count, bytes32 decodedRoot) = abi.decode(logs[0].data, (bool, uint32, bytes32));
        assertTrue(flag);
        assertEq(uint256(count), 17);
        assertEq(decodedRoot, root);
    }

    function testIRTypedScalarEventRejectsMalformedBoolAndU32Calldata() public {
        address probe = address(uint160(0xE142));
        deployRuntime(hex"$probe_hex", probe);
        bytes4 selector = bytes4(keccak256("emit_typed_scalar_event(bool,uint32,bytes32)"));
        bytes32 root = packed(1, 2, 3, 4);

        (bool boolOk,) = probe.call(abi.encodeWithSelector(selector, uint256(2), uint32(17), root));
        assertFalse(boolOk);

        (bool u32Ok,) = probe.call(abi.encodeWithSelector(selector, true, uint256(type(uint32).max) + 1, root));
        assertFalse(u32Ok);
    }

    function testIRIndexedEventEmitsSignatureIndexedTopicAndData() public {
        address probe = address(uint160(0xE132));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_indexed_event(uint256,uint256)", 7, 99));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedValue(uint64,uint64)")));
        assertEq(logs[0].topics[1], bytes32(uint256(7)));
        assertEq(abi.decode(logs[0].data, (uint256)), 99);
    }

    function testIRIndexedTypedScalarEventEmitsBoolU32AndHashTopics() public {
        address probe = address(uint160(0xE143));
        deployRuntime(hex"$probe_hex", probe);
        bytes32 root = packed(5, 6, 7, 8);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_indexed_typed_scalar_event(bool,uint32,bytes32,uint256)", true, uint32(23), root, 99));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 4);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedTypedScalar(bool,uint32,bytes32,uint64)")));
        assertEq(logs[0].topics[1], bytes32(uint256(1)));
        assertEq(logs[0].topics[2], bytes32(uint256(23)));
        assertEq(logs[0].topics[3], root);
        assertEq(abi.decode(logs[0].data, (uint256)), 99);
    }

    function testIRTwoIndexedFieldsLowerToLog3() public {
        address probe = address(uint160(0xE13F));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_two_indexed_event(uint256,uint256,uint256)", 3, 4, 5));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedTwoValues(uint64,uint64,uint64)")));
        assertEq(logs[0].topics[1], bytes32(uint256(3)));
        assertEq(logs[0].topics[2], bytes32(uint256(4)));
        assertEq(abi.decode(logs[0].data, (uint256)), 5);
    }

    function testIRThreeIndexedFieldsLowerToLog4() public {
        address probe = address(uint160(0xE140));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_three_indexed_event(uint256,uint256,uint256,uint256)", 6, 7, 8, 9));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 4);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedThreeValues(uint64,uint64,uint64,uint64)")));
        assertEq(logs[0].topics[1], bytes32(uint256(6)));
        assertEq(logs[0].topics[2], bytes32(uint256(7)));
        assertEq(logs[0].topics[3], bytes32(uint256(8)));
        assertEq(abi.decode(logs[0].data, (uint256)), 9);
    }

    function testIRIndexedStructEventHashesAggregateTopic() public {
        address probe = address(uint160(0xE136));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_indexed_pair_event(uint256,uint256,uint256)", 11, 22, 99));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedPair((uint64,uint64),uint64)")));
        assertEq(logs[0].topics[1], keccak256(abi.encode(uint256(11), uint256(22))));
        assertEq(abi.decode(logs[0].data, (uint256)), 99);
    }

    function testIRIndexedStorageStructEventHashesAggregateTopic() public {
        address probe = address(uint160(0xE139));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_indexed_storage_pair_event(uint256,uint256,uint256)", 66, 77, 88));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedStoragePair((uint64,uint64),uint64)")));
        assertEq(logs[0].topics[1], keccak256(abi.encode(uint256(66), uint256(77))));
        assertEq(abi.decode(logs[0].data, (uint256)), 88);
    }

    function testIRIndexedStorageFixedArrayEventHashesAggregateTopic() public {
        address probe = address(uint160(0xE13D));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_indexed_storage_array_event(uint256,uint256,uint256)", 103, 104, 105));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedStorageArray(uint64[2],uint64)")));
        assertEq(logs[0].topics[1], keccak256(abi.encode(uint256(103), uint256(104))));
        assertEq(abi.decode(logs[0].data, (uint256)), 105);
    }

    function testIRIndexedFixedArrayEventHashesAggregateTopic() public {
        address probe = address(uint160(0xE138));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_indexed_array_event(uint256,uint256,uint256)", 33, 44, 55));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedArray(uint64[2],uint64)")));
        assertEq(logs[0].topics[1], keccak256(abi.encode(uint256(33), uint256(44))));
        assertEq(abi.decode(logs[0].data, (uint256)), 55);
    }

    function testIRIndexedNestedFixedArrayEventHashesAggregateTopic() public {
        address probe = address(uint160(0xE145));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_indexed_matrix_event(uint256,uint256,uint256,uint256,uint256)", 31, 32, 33, 34, 35));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedMatrix(uint64[2][2],uint64)")));
        assertEq(logs[0].topics[1], keccak256(abi.encode(uint256(31), uint256(32), uint256(33), uint256(34))));
        assertEq(abi.decode(logs[0].data, (uint256)), 35);
    }

    function testIRIndexedNestedStructArrayEventHashesAggregateTopic() public {
        address probe = address(uint160(0xE148));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_indexed_pair_matrix_event(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256)", 1, 2, 3, 4, 5, 6, 7, 8, 90));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedPairMatrix((uint64,uint64)[2][2],uint64)")));
        assertEq(logs[0].topics[1], keccak256(abi.encode(uint256(1), uint256(2), uint256(3), uint256(4), uint256(5), uint256(6), uint256(7), uint256(8))));
        assertEq(abi.decode(logs[0].data, (uint256)), 90);
    }

    function testIRIndexedStructArrayEventHashesAggregateTopic() public {
        address probe = address(uint160(0xE137));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_indexed_pair_array_event(uint256,uint256,uint256,uint256,uint256)", 1, 2, 3, 4, 77));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedPairArray((uint64,uint64)[2],uint64)")));
        assertEq(logs[0].topics[1], keccak256(abi.encode(uint256(1), uint256(2), uint256(3), uint256(4))));
        assertEq(abi.decode(logs[0].data, (uint256)), 77);
    }

    function testIRIndexedStorageStructArrayEventHashesAggregateTopic() public {
        address probe = address(uint160(0xE13E));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_indexed_storage_pair_array_event(uint256,uint256,uint256,uint256,uint256)", 11, 12, 13, 14, 15));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256(bytes("IndexedStoragePairArray((uint64,uint64)[2],uint64)")));
        assertEq(logs[0].topics[1], keccak256(abi.encode(uint256(11), uint256(12), uint256(13), uint256(14))));
        assertEq(abi.decode(logs[0].data, (uint256)), 15);
    }

    function testIRStructEventFlattensDataWords() public {
        address probe = address(uint160(0xE133));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_pair_event(uint256,uint256)", 11, 22));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256(bytes("PairEvent((uint64,uint64))")));
        (uint256 left, uint256 right) = abi.decode(logs[0].data, (uint256, uint256));
        assertEq(left, 11);
        assertEq(right, 22);
    }

    function testIRStorageStructEventFlattensDataWords() public {
        address probe = address(uint160(0xE13A));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_storage_pair_event(uint256,uint256)", 66, 77));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256(bytes("StoragePairEvent((uint64,uint64))")));
        (uint256 left, uint256 right) = abi.decode(logs[0].data, (uint256, uint256));
        assertEq(left, 66);
        assertEq(right, 77);
    }

    function testIRStorageFixedArrayEventFlattensDataWords() public {
        address probe = address(uint160(0xE13B));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_storage_array_event(uint256,uint256)", 101, 102));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256(bytes("StorageArrayEvent(uint64[2])")));
        (uint256 left, uint256 right) = abi.decode(logs[0].data, (uint256, uint256));
        assertEq(left, 101);
        assertEq(right, 102);
    }

    function testIRFixedArrayEventFlattensDataWords() public {
        address probe = address(uint160(0xE134));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_array_event(uint256,uint256)", 33, 44));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256(bytes("ArrayEvent(uint64[2])")));
        (uint256 left, uint256 right) = abi.decode(logs[0].data, (uint256, uint256));
        assertEq(left, 33);
        assertEq(right, 44);
    }

    function testIRNestedFixedArrayEventFlattensDataWords() public {
        address probe = address(uint160(0xE146));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_matrix_event(uint256,uint256,uint256,uint256)", 21, 22, 23, 24));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256(bytes("MatrixEvent(uint64[2][2])")));
        (uint256 a, uint256 b, uint256 c, uint256 d) = abi.decode(logs[0].data, (uint256, uint256, uint256, uint256));
        assertEq(a, 21);
        assertEq(b, 22);
        assertEq(c, 23);
        assertEq(d, 24);
    }

    function testIRStructArrayEventFlattensDataWords() public {
        address probe = address(uint160(0xE135));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_pair_array_event(uint256,uint256,uint256,uint256)", 1, 2, 3, 4));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256(bytes("PairArrayEvent((uint64,uint64)[2])")));
        (uint256 a, uint256 b, uint256 c, uint256 d) = abi.decode(logs[0].data, (uint256, uint256, uint256, uint256));
        assertEq(a, 1);
        assertEq(b, 2);
        assertEq(c, 3);
        assertEq(d, 4);
    }

    function testIRNestedStructArrayEventFlattensDataWords() public {
        address probe = address(uint160(0xE147));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_pair_matrix_event(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256)", 1, 2, 3, 4, 5, 6, 7, 8));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256(bytes("PairMatrixEvent((uint64,uint64)[2][2])")));
        (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f, uint256 g, uint256 h) =
            abi.decode(logs[0].data, (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256));
        assertEq(a, 1);
        assertEq(b, 2);
        assertEq(c, 3);
        assertEq(d, 4);
        assertEq(e, 5);
        assertEq(f, 6);
        assertEq(g, 7);
        assertEq(h, 8);
    }

    function testIRStorageStructArrayEventFlattensDataWords() public {
        address probe = address(uint160(0xE13C));
        deployRuntime(hex"$probe_hex", probe);

        vm.recordLogs();
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("emit_storage_pair_array_event(uint256,uint256,uint256,uint256)", 5, 6, 7, 8));
        assertTrue(ok);
        assertEq(result.length, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, probe);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256(bytes("StoragePairArrayEvent((uint64,uint64)[2])")));
        (uint256 a, uint256 b, uint256 c, uint256 d) = abi.decode(logs[0].data, (uint256, uint256, uint256, uint256));
        assertEq(a, 5);
        assertEq(b, 6);
        assertEq(c, 7);
        assertEq(d, 8);
    }

    function testIREventRejectsUnknownSelector() public {
        address probe = address(uint160(0xE131));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "event-ir-smoke: ProofForge metadata $METADATA_FILE"

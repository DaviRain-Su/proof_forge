#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmStorageStructProbe IR to EVM runtime
# bytecode and validate flat storage-struct slots through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-storage-struct-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Evm/EvmStorageStructProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmStorageStructProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "storage-struct-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "storage-struct-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "storage-struct-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-storage-struct --format bytecode \
  --yul-output "$OUT_DIR/EvmStorageStructProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmStorageStructProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmStorageStructProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmStorageStructProbe \
  --expect-source-kind portable-ir \
  --expect-capability storage.scalar \
  --expect-capability storage.array \
  --expect-capability data.fixed_array \
  --expect-capability data.struct \
  --expect-entrypoint struct_lifecycle:93ddf147 \
  --expect-entrypoint path_lifecycle:84c21205 \
  --expect-entrypoint array_struct_lifecycle:2d84bb06 \
  --expect-entrypoint return_points:d16ccd19 \
  --expect-entrypoint array_path_lifecycle:2991a157 \
  --expect-entrypoint typed_sum:2ec467be \
  --expect-entrypoint root_value:c42f8c06 \
  --expect-entrypoint whole_struct_write_sum:c1e31e63 \
  --expect-entrypoint whole_struct_return:cd13529b \
  --expect-entrypoint self_struct_storage_write:696ddaa7 \
  --expect-entrypoint read_point_x:db006782 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmStorageStructProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRStorageStructSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRStorageStructSmokeTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 constant ROOT_VALUE =
        hex"0000000000000001000000000000000200000000000000030000000000000004";

    struct Point {
        uint256 x;
        uint256 y;
    }

    function assertTrue(bool value) internal pure {
        require(value, "assertTrue failed");
    }

    function assertFalse(bool value) internal pure {
        require(!value, "assertFalse failed");
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "assertEq failed");
    }

    function assertEqBytes32(bytes32 actual, bytes32 expected) internal pure {
        require(actual == expected, "assertEqBytes32 failed");
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function readStorage(address target, uint256 slot) internal view returns (uint256) {
        return uint256(vm.load(target, bytes32(slot)));
    }

    function readStorageBytes32(address target, uint256 slot) internal view returns (bytes32) {
        return vm.load(target, bytes32(slot));
    }

    function callU256(address probe, bytes memory payload) internal returns (uint256) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (uint256));
    }

    function callBytes32(address probe, bytes memory payload) internal returns (bytes32) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (bytes32));
    }

    function callPair(address probe, bytes memory payload) internal returns (uint256, uint256) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (uint256, uint256));
    }

    function callPoints(address probe, bytes memory payload)
        internal
        returns (Point[2] memory points)
    {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        points = abi.decode(result, (Point[2]));
    }

    function testIRStorageStructScalarLifecycleUsesExpandedSlots() public {
        address probe = address(uint160(0xA320));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("struct_lifecycle()")), 18);
        assertEq(readStorage(probe, 0) >> 192, 111);
        assertEq(readStorage(probe, 1), 7);
        assertEq(readStorage(probe, 2), 11);
        assertEq(readStorage(probe, 3) >> 192, 222);
    }

    function testIRStorageStructScalarFieldPaths() public {
        address probe = address(uint160(0xA321));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("path_lifecycle()")), 48);
        assertEq(readStorage(probe, 1), 26);
        assertEq(readStorage(probe, 2), 22);
    }

    function testIRStorageStructArrayLifecycleUsesFlattenedSlots() public {
        address probe = address(uint160(0xA322));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("array_struct_lifecycle()")), 12);
        assertEq(readStorage(probe, 4), 3);
        assertEq(readStorage(probe, 5), 5);
        assertEq(readStorage(probe, 6), 7);
        assertEq(readStorage(probe, 7), 11);
    }

    function testIRStorageStructArrayReturnEncodesStorageFields() public {
        address probe = address(uint160(0xA32B));
        deployRuntime(hex"$probe_hex", probe);

        Point[2] memory points = callPoints(probe, abi.encodeWithSignature("return_points()"));
        assertEq(points[0].x, 29);
        assertEq(points[0].y, 31);
        assertEq(points[1].x, 37);
        assertEq(points[1].y, 41);
        assertEq(readStorage(probe, 4), 29);
        assertEq(readStorage(probe, 5), 31);
        assertEq(readStorage(probe, 6), 37);
        assertEq(readStorage(probe, 7), 41);
    }

    function testIRStorageStructArrayFieldPaths() public {
        address probe = address(uint160(0xA323));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("array_path_lifecycle()")), 23);
        assertEq(readStorage(probe, 5), 8);
        assertEq(readStorage(probe, 6), 15);
    }

    function testIRStorageStructTypedFields() public {
        address probe = address(uint160(0xA324));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("typed_sum()")), 34);
        assertEq(readStorage(probe, 8), 1);
        assertEq(readStorage(probe, 9), 33);
    }

    function testIRStorageStructHashField() public {
        address probe = address(uint160(0xA325));
        deployRuntime(hex"$probe_hex", probe);

        assertEqBytes32(callBytes32(probe, abi.encodeWithSignature("root_value()")), ROOT_VALUE);
        assertEqBytes32(readStorageBytes32(probe, 10), ROOT_VALUE);
    }

    function testIRStorageStructWholeWriteAndReadIntoLocal() public {
        address probe = address(uint160(0xA326));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("whole_struct_write_sum()")), 70);
        assertEq(readStorage(probe, 1), 30);
        assertEq(readStorage(probe, 2), 40);
    }

    function testIRStorageStructWholeReturnEncodesFields() public {
        address probe = address(uint160(0xA327));
        deployRuntime(hex"$probe_hex", probe);

        (uint256 x, uint256 y) = callPair(probe, abi.encodeWithSignature("whole_struct_return()"));
        assertEq(x, 8);
        assertEq(y, 13);
    }

    function testIRStorageStructWholeWriteSnapshotsRHS() public {
        address probe = address(uint160(0xA328));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("self_struct_storage_write()")), 705);
        assertEq(readStorage(probe, 1), 7);
        assertEq(readStorage(probe, 2), 5);
    }

    function testIRStorageStructArrayParameterizedReadAndBounds() public {
        address probe = address(uint160(0xA329));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("array_struct_lifecycle()")), 12);
        assertEq(callU256(probe, abi.encodeWithSignature("read_point_x(uint256)", 1)), 7);

        (bool readOk,) = probe.call(abi.encodeWithSignature("read_point_x(uint256)", 2));
        assertFalse(readOk);
    }

    function testIRStorageStructRejectsUnknownSelector() public {
        address probe = address(uint160(0xA32A));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "storage-struct-ir-smoke: ProofForge metadata $METADATA_FILE"

#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmStorageArrayProbe IR to EVM runtime
# bytecode and validate static storage-array slots through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-storage-array-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Evm/EvmStorageArrayProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmStorageArrayProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "storage-array-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "storage-array-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "storage-array-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-storage-array --format bytecode \
  --yul-output "$OUT_DIR/EvmStorageArrayProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmStorageArrayProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmStorageArrayProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmStorageArrayProbe \
  --expect-source-kind portable-ir \
  --expect-capability storage.scalar \
  --expect-capability storage.array \
  --expect-capability data.fixed_array \
  --expect-entrypoint storage_lifecycle:e4684b67 \
  --expect-entrypoint read_value:ac35feee \
  --expect-entrypoint write_value:5a6fd3b0 \
  --expect-entrypoint return_values:08b37751 \
  --expect-entrypoint path_lifecycle:84c21205 \
  --expect-entrypoint path_assign_lifecycle:bce9e77b \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmStorageArrayProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRStorageArraySmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRStorageArraySmokeTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool value) internal pure {
        require(value, "assertTrue failed");
    }

    function assertFalse(bool value) internal pure {
        require(!value, "assertFalse failed");
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "assertEq failed");
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function arraySlot(uint256 index) internal pure returns (bytes32) {
        return bytes32(uint256(1 + index));
    }

    function readStorage(address target, bytes32 slot) internal view returns (uint256) {
        return uint256(vm.load(target, slot));
    }

    function callU256(address probe, bytes memory payload) internal returns (uint256) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (uint256));
    }

    function callU256Array3(address probe, bytes memory payload)
        internal
        returns (uint256[3] memory values)
    {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        values = abi.decode(result, (uint256[3]));
    }

    function testIRStorageArrayLifecycleUsesContiguousSlots() public {
        address probe = address(uint160(0xA220));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("storage_lifecycle()")), 31);
        assertEq(readStorage(probe, bytes32(uint256(0))) >> 192, 111);
        assertEq(readStorage(probe, arraySlot(0)), 7);
        assertEq(readStorage(probe, arraySlot(1)), 11);
        assertEq(readStorage(probe, arraySlot(2)), 13);
        assertEq(readStorage(probe, bytes32(uint256(4))) >> 192, 222);
    }

    function testIRStorageArrayParameterizedReadWrite() public {
        address probe = address(uint160(0xA221));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("write_value(uint256,uint256)", 1, 44));
        assertTrue(ok);
        assertEq(result.length, 0);

        assertEq(callU256(probe, abi.encodeWithSignature("read_value(uint256)", 1)), 44);
        assertEq(readStorage(probe, arraySlot(1)), 44);
    }

    function testIRStorageArrayReturnValuesEncodesStorageElements() public {
        address probe = address(uint160(0xA226));
        deployRuntime(hex"$probe_hex", probe);

        uint256[3] memory values = callU256Array3(
            probe,
            abi.encodeWithSignature("return_values()")
        );
        assertEq(values[0], 17);
        assertEq(values[1], 19);
        assertEq(values[2], 23);
        assertEq(readStorage(probe, arraySlot(0)), 17);
        assertEq(readStorage(probe, arraySlot(1)), 19);
        assertEq(readStorage(probe, arraySlot(2)), 23);
    }

    function testIRStorageArrayIndexStoragePath() public {
        address probe = address(uint160(0xA224));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("path_lifecycle()")), 43);
        assertEq(readStorage(probe, arraySlot(0)), 21);
        assertEq(readStorage(probe, arraySlot(1)), 22);
    }

    function testIRStorageArrayIndexStoragePathCompoundAssignment() public {
        address probe = address(uint160(0xA225));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("path_assign_lifecycle()")), 15);
        assertEq(readStorage(probe, arraySlot(2)), 15);
    }

    function testIRStorageArrayRejectsOutOfBoundsIndex() public {
        address probe = address(uint160(0xA222));
        deployRuntime(hex"$probe_hex", probe);

        (bool readOk,) = probe.call(abi.encodeWithSignature("read_value(uint256)", 3));
        assertFalse(readOk);

        (bool writeOk,) = probe.call(abi.encodeWithSignature("write_value(uint256,uint256)", 3, 99));
        assertFalse(writeOk);
    }

    function testIRStorageArrayRejectsUnknownSelector() public {
        address probe = address(uint160(0xA223));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "storage-array-ir-smoke: ProofForge metadata $METADATA_FILE"

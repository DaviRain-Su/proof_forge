#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmTypedStorageProbe IR to EVM runtime
# bytecode and validate Bool scalar storage plus U32/Bool/Hash storage arrays.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-typed-storage-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmTypedStorageProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmTypedStorageProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "typed-storage-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "typed-storage-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "typed-storage-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-typed-storage --format bytecode \
  --yul-output "$OUT_DIR/EvmTypedStorageProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmTypedStorageProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmTypedStorageProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmTypedStorageProbe \
  --expect-source-kind portable-ir \
  --expect-capability storage.scalar \
  --expect-capability storage.array \
  --expect-capability data.fixed_array \
  --expect-capability assertions.check \
  --expect-entrypoint bool_scalar_lifecycle:06422075 \
  --expect-entrypoint typed_array_lifecycle:9f3c504b \
  --expect-entrypoint path_assign_u32:5ab2cb77 \
  --expect-entrypoint read_flag:afbe1175 \
  --expect-entrypoint write_limb:6a088e19 \
  --expect-entrypoint read_root:4994f441 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmTypedStorageProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRTypedStorageSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRTypedStorageSmokeTest {
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

    function assertEq(bytes32 actual, bytes32 expected) internal pure {
        require(actual == expected, "assertEq(bytes32) failed");
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function slot(uint256 index) internal pure returns (bytes32) {
        return bytes32(index);
    }

    function readStorage(address target, uint256 slotIndex) internal view returns (uint256) {
        return uint256(vm.load(target, slot(slotIndex)));
    }

    function packed(uint64 a, uint64 b, uint64 c, uint64 d) internal pure returns (bytes32) {
        return bytes32(
            (uint256(a) << 192) |
            (uint256(b) << 128) |
            (uint256(c) << 64) |
            uint256(d)
        );
    }

    function callU256(address probe, bytes memory payload) internal returns (uint256) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (uint256));
    }

    function callBool(address probe, bytes memory payload) internal returns (bool) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (bool));
    }

    function callBytes32(address probe, bytes memory payload) internal returns (bytes32) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (bytes32));
    }

    function testIRBoolScalarStorage() public {
        address probe = address(uint160(0xA340));
        deployRuntime(hex"$probe_hex", probe);

        assertTrue(callBool(probe, abi.encodeWithSignature("bool_scalar_lifecycle()")));
        assertEq(readStorage(probe, 0) & type(uint8).max, 1);
    }

    function testIRTypedStorageArraysUseContiguousWordSlots() public {
        address probe = address(uint160(0xA341));
        deployRuntime(hex"$probe_hex", probe);

        bytes32 rootA = packed(1, 2, 3, 4);
        bytes32 rootB = packed(5, 6, 7, 8);

        assertEq(callU256(probe, abi.encodeWithSignature("typed_array_lifecycle()")), 32);
        assertEq(readStorage(probe, 1), 7);
        assertEq(readStorage(probe, 2), 11);
        assertEq(readStorage(probe, 3), 13);
        assertEq(readStorage(probe, 4), 1);
        assertEq(readStorage(probe, 5), 0);
        assertEq(vm.load(probe, slot(6)), rootA);
        assertEq(vm.load(probe, slot(7)), rootB);
        assertEq(readStorage(probe, 8) & type(uint64).max, 999);

        assertTrue(callBool(probe, abi.encodeWithSignature("read_flag(uint256)", 0)));
        assertFalse(callBool(probe, abi.encodeWithSignature("read_flag(uint256)", 1)));
        assertEq(callBytes32(probe, abi.encodeWithSignature("read_root(uint256)", 1)), rootB);
    }

    function testIRU32ArrayStoragePathCompoundAssignment() public {
        address probe = address(uint160(0xA342));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("path_assign_u32()")), 30);
        assertEq(readStorage(probe, 1), 30);
    }

    function testIRU32ArrayWriteGuardsCalldataAndBounds() public {
        address probe = address(uint160(0xA343));
        deployRuntime(hex"$probe_hex", probe);

        (bool writeOk, bytes memory result) =
            probe.call(abi.encodeWithSignature("write_limb(uint256,uint32)", 1, uint256(type(uint32).max)));
        assertTrue(writeOk);
        assertEq(result.length, 0);
        assertEq(readStorage(probe, 2), uint256(type(uint32).max));

        (bool rangeOk,) =
            probe.call(abi.encodeWithSignature("write_limb(uint256,uint32)", 1, uint256(type(uint32).max) + 1));
        assertFalse(rangeOk);

        (bool boundsOk,) =
            probe.call(abi.encodeWithSignature("write_limb(uint256,uint32)", 3, 99));
        assertFalse(boundsOk);
    }

    function testIRTypedStorageArrayReadsRejectOutOfBoundsIndex() public {
        address probe = address(uint160(0xA344));
        deployRuntime(hex"$probe_hex", probe);

        (bool flagOk,) = probe.call(abi.encodeWithSignature("read_flag(uint256)", 2));
        assertFalse(flagOk);

        (bool rootOk,) = probe.call(abi.encodeWithSignature("read_root(uint256)", 2));
        assertFalse(rootOk);
    }

    function testIRTypedStorageRejectsUnknownSelector() public {
        address probe = address(uint160(0xA345));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "typed-storage-ir-smoke: ProofForge metadata $METADATA_FILE"

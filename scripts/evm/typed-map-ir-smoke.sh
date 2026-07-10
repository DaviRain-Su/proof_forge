#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmTypedMapProbe IR to EVM runtime
# bytecode and validate U32/Bool/Hash storage maps through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-typed-map-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmTypedMapProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmTypedMapProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "typed-map-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "typed-map-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "typed-map-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-typed-map --format bytecode \
  --yul-output "$OUT_DIR/EvmTypedMapProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmTypedMapProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmTypedMapProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmTypedMapProbe \
  --expect-source-kind portable-ir \
  --expect-capability storage.scalar \
  --expect-capability storage.map \
  --expect-capability assertions.check \
  --expect-entrypoint typed_map_lifecycle:e4e7feaf \
  --expect-entrypoint read_score:04395342 \
  --expect-entrypoint write_score:9dfe7834 \
  --expect-entrypoint contains_score:79b9741a \
  --expect-entrypoint read_flag:7c7d06af \
  --expect-entrypoint set_flag:481794a0 \
  --expect-entrypoint contains_flag:430d2c8d \
  --expect-entrypoint read_root:ca27ec99 \
  --expect-entrypoint set_root:86370059 \
  --expect-entrypoint contains_root:1f24b6db \
  --expect-entrypoint path_assign_score:a82c9bea \
  --expect-entrypoint nested_path_score:cb239774 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmTypedMapProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRTypedMapSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRTypedMapSmokeTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 constant MAP_PRESENCE_DOMAIN = 0x50524f4f465f464f5247455f4d41505f50524553454e4345;

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

    function mapSlot(uint256 key, uint256 slotIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, slotIndex));
    }

    function mapPresenceSlot(uint256 key, uint256 slotIndex) internal pure returns (bytes32) {
        bytes32 presenceBase = keccak256(abi.encode(slotIndex, MAP_PRESENCE_DOMAIN));
        return keccak256(abi.encode(key, uint256(presenceBase)));
    }

    function nestedMapSlot(uint256 outer, uint256 inner, uint256 slotIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(inner, uint256(mapSlot(outer, slotIndex))));
    }

    function nestedMapPresenceSlot(uint256 outer, uint256 inner, uint256 slotIndex) internal pure returns (bytes32) {
        bytes32 parentSlot = mapSlot(outer, slotIndex);
        bytes32 presenceBase = keccak256(abi.encode(uint256(parentSlot), MAP_PRESENCE_DOMAIN));
        return keccak256(abi.encode(inner, uint256(presenceBase)));
    }

    function mapSlotBool(bool key, uint256 slotIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, slotIndex));
    }

    function mapPresenceSlotBool(bool key, uint256 slotIndex) internal pure returns (bytes32) {
        bytes32 presenceBase = keccak256(abi.encode(slotIndex, MAP_PRESENCE_DOMAIN));
        return keccak256(abi.encode(key, uint256(presenceBase)));
    }

    function mapSlotBytes32(bytes32 key, uint256 slotIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, slotIndex));
    }

    function mapPresenceSlotBytes32(bytes32 key, uint256 slotIndex) internal pure returns (bytes32) {
        bytes32 presenceBase = keccak256(abi.encode(slotIndex, MAP_PRESENCE_DOMAIN));
        return keccak256(abi.encode(key, uint256(presenceBase)));
    }

    function packed(uint64 a, uint64 b, uint64 c, uint64 d) internal pure returns (bytes32) {
        return bytes32(
            (uint256(a) << 192) |
            (uint256(b) << 128) |
            (uint256(c) << 64) |
            uint256(d)
        );
    }

    function readStorage(address target, bytes32 slot) internal view returns (uint256) {
        return uint256(vm.load(target, slot));
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

    function testIRTypedMapLifecycleUsesWordMappingSlots() public {
        address probe = address(uint160(0xB450));
        deployRuntime(hex"$probe_hex", probe);

        bytes32 rootA = packed(1, 2, 3, 4);
        bytes32 rootB = packed(5, 6, 7, 8);

        assertEq(callU256(probe, abi.encodeWithSignature("typed_map_lifecycle()")), 31);
        assertEq(readStorage(probe, bytes32(uint256(3))) & type(uint64).max, 777);
        assertEq(readStorage(probe, mapSlot(7, 0)), 13);
        assertEq(readStorage(probe, mapSlot(8, 0)), 17);
        assertEq(readStorage(probe, mapPresenceSlot(7, 0)), 1);
        assertEq(readStorage(probe, mapPresenceSlot(8, 0)), 1);
        assertEq(readStorage(probe, mapSlotBool(true, 1)), 1);
        assertEq(readStorage(probe, mapSlotBool(false, 1)), 0);
        assertEq(readStorage(probe, mapPresenceSlotBool(true, 1)), 1);
        assertEq(readStorage(probe, mapPresenceSlotBool(false, 1)), 1);
        assertEq(vm.load(probe, mapSlotBytes32(rootA, 2)), rootB);
        assertEq(readStorage(probe, mapPresenceSlotBytes32(rootA, 2)), 1);
    }

    function testIRU32MapReadWriteGuardsCalldata() public {
        address probe = address(uint160(0xB451));
        deployRuntime(hex"$probe_hex", probe);

        uint256 maxU32 = uint256(type(uint32).max);
        assertEq(callU256(probe, abi.encodeWithSignature("read_score(uint32)", 99)), 0);
        assertFalse(callBool(probe, abi.encodeWithSignature("contains_score(uint32)", 99)));

        (bool writeOk, bytes memory result) =
            probe.call(abi.encodeWithSignature("write_score(uint32,uint32)", maxU32, maxU32));
        assertTrue(writeOk);
        assertEq(result.length, 0);
        assertEq(callU256(probe, abi.encodeWithSignature("read_score(uint32)", maxU32)), maxU32);
        assertTrue(callBool(probe, abi.encodeWithSignature("contains_score(uint32)", maxU32)));
        assertEq(readStorage(probe, mapSlot(maxU32, 0)), maxU32);
        assertEq(readStorage(probe, mapPresenceSlot(maxU32, 0)), 1);

        (bool keyRangeOk,) =
            probe.call(abi.encodeWithSignature("contains_score(uint32)", maxU32 + 1));
        assertFalse(keyRangeOk);

        (bool valueRangeOk,) =
            probe.call(abi.encodeWithSignature("write_score(uint32,uint32)", 1, maxU32 + 1));
        assertFalse(valueRangeOk);
    }

    function testIRBoolMapReadWriteAndMalformedBoolRejects() public {
        address probe = address(uint160(0xB452));
        deployRuntime(hex"$probe_hex", probe);

        assertFalse(callBool(probe, abi.encodeWithSignature("set_flag(bool,bool)", true, true)));
        assertTrue(callBool(probe, abi.encodeWithSignature("read_flag(bool)", true)));
        assertTrue(callBool(probe, abi.encodeWithSignature("contains_flag(bool)", true)));
        assertTrue(callBool(probe, abi.encodeWithSignature("set_flag(bool,bool)", true, false)));
        assertFalse(callBool(probe, abi.encodeWithSignature("read_flag(bool)", true)));
        assertTrue(callBool(probe, abi.encodeWithSignature("contains_flag(bool)", true)));
        assertEq(readStorage(probe, mapSlotBool(true, 1)), 0);
        assertEq(readStorage(probe, mapPresenceSlotBool(true, 1)), 1);

        (bool badKeyOk,) = probe.call(abi.encodeWithSelector(bytes4(0x430d2c8d), uint256(2)));
        assertFalse(badKeyOk);

        (bool badValueOk,) = probe.call(abi.encodeWithSelector(bytes4(0x481794a0), uint256(0), uint256(2)));
        assertFalse(badValueOk);
    }

    function testIRHashMapReadWriteAndRawSlot() public {
        address probe = address(uint160(0xB453));
        deployRuntime(hex"$probe_hex", probe);

        bytes32 rootA = packed(1, 2, 3, 4);
        bytes32 rootB = packed(5, 6, 7, 8);
        bytes32 rootC = packed(9, 10, 11, 12);
        bytes32 zero = bytes32(0);

        assertEq(callBytes32(probe, abi.encodeWithSignature("set_root(bytes32,bytes32)", rootA, rootB)), zero);
        assertEq(callBytes32(probe, abi.encodeWithSignature("read_root(bytes32)", rootA)), rootB);
        assertTrue(callBool(probe, abi.encodeWithSignature("contains_root(bytes32)", rootA)));
        assertEq(vm.load(probe, mapSlotBytes32(rootA, 2)), rootB);
        assertEq(readStorage(probe, mapPresenceSlotBytes32(rootA, 2)), 1);
        assertEq(callBytes32(probe, abi.encodeWithSignature("set_root(bytes32,bytes32)", rootA, rootC)), rootB);
        assertEq(callBytes32(probe, abi.encodeWithSignature("read_root(bytes32)", rootA)), rootC);
        assertTrue(callBool(probe, abi.encodeWithSignature("contains_root(bytes32)", rootA)));
        assertEq(vm.load(probe, mapSlotBytes32(rootA, 2)), rootC);
    }

    function testIRU32MapStoragePathCompoundAssignment() public {
        address probe = address(uint160(0xB454));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("path_assign_score()")), 30);
        assertEq(readStorage(probe, mapSlot(9, 0)), 30);
        assertEq(readStorage(probe, mapPresenceSlot(9, 0)), 1);
    }

    function testIRU32NestedMapStoragePathUsesTypedGuardsAndSlots() public {
        address probe = address(uint160(0xB456));
        deployRuntime(hex"$probe_hex", probe);

        uint256 maxU32 = uint256(type(uint32).max);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_path_score(uint32,uint32,uint32)", 1000, 1001, 41)), 46);
        assertEq(readStorage(probe, nestedMapSlot(1000, 1001, 0)), 46);
        assertEq(readStorage(probe, nestedMapPresenceSlot(1000, 1001, 0)), 1);
        assertEq(readStorage(probe, mapSlot(1000, 0)), 0);
        assertEq(readStorage(probe, mapPresenceSlot(1000, 0)), 0);

        (bool badOuterOk,) =
            probe.call(abi.encodeWithSelector(bytes4(0xcb239774), maxU32 + 1, uint256(1), uint256(2)));
        assertFalse(badOuterOk);

        (bool badInnerOk,) =
            probe.call(abi.encodeWithSelector(bytes4(0xcb239774), uint256(1), maxU32 + 1, uint256(2)));
        assertFalse(badInnerOk);

        (bool badValueOk,) =
            probe.call(abi.encodeWithSelector(bytes4(0xcb239774), uint256(1), uint256(2), maxU32 + 1));
        assertFalse(badValueOk);
    }

    function testIRTypedMapRejectsUnknownSelector() public {
        address probe = address(uint160(0xB455));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "typed-map-ir-smoke: ProofForge metadata $METADATA_FILE"

#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmDynamicArrayProbe IR to EVM runtime
# bytecode and verify dynamic storage array indexed read/write.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-dynamic-array-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Evm/EvmDynamicArrayProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmDynamicArrayProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found; skipping dynamic-array IR smoke"
  exit 0
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "solc not found; skipping dynamic-array IR smoke"
  exit 0
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-dynamic-array --format bytecode \
  --yul-output "$OUT_DIR/EvmDynamicArrayProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmDynamicArrayProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmDynamicArrayProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmDynamicArrayProbe \
  --expect-source-kind portable-ir \
  --expect-capability storage.array \
  --expect-entrypoint storage_lifecycle:e4684b67 \
  --expect-entrypoint read_value:ac35feee \
  --expect-entrypoint write_value:5a6fd3b0 \
  --expect-entrypoint path_assign_lifecycle:bce9e77b \
  --expect-entrypoint push_value:b408dd47 \
  --expect-entrypoint pop_value:12c62f71 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmDynamicArrayProbe.bin")"

rm -rf "$FORGE_DIR"
mkdir -p "$FORGE_DIR/test"

cat > "$FORGE_DIR/foundry.toml" <<'TOML'
[profile.default]
src = "test"
out = "out"
script = "script"
test = "test"
libs = ["lib"]
TOML

cat > "$FORGE_DIR/test/ProofForgeIRDynamicArraySmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRDynamicArraySmokeTest {
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

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function dynamicArraySlot(uint256 baseSlot, uint256 index) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encodePacked(baseSlot))) + index);
    }

    function callU256(address probe, bytes memory payload) internal returns (uint256) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (uint256));
    }

    function callVoid(address probe, bytes memory payload) internal {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        require(result.length == 0, "callVoid: unexpected return data");
    }

    function testIRDynamicArrayStorageLifecycle() public {
        address probe = address(uint160(0xB200));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("storage_lifecycle()")), 31);

        // Verify elements are stored at keccak256(0) + index
        assertEq(uint256(vm.load(probe, dynamicArraySlot(0, 0))), 7);
        assertEq(uint256(vm.load(probe, dynamicArraySlot(0, 1))), 11);
        assertEq(uint256(vm.load(probe, dynamicArraySlot(0, 2))), 13);
    }

    function testIRDynamicArrayReadWrite() public {
        address probe = address(uint160(0xB201));
        deployRuntime(hex"$probe_hex", probe);

        callVoid(probe, abi.encodeWithSignature("write_value(uint256,uint256)", 5, 99));
        assertEq(callU256(probe, abi.encodeWithSignature("read_value(uint256)", 5)), 99);
        assertEq(uint256(vm.load(probe, dynamicArraySlot(0, 5))), 99);
    }

    function testIRDynamicArrayPathAssignLifecycle() public {
        address probe = address(uint160(0xB202));
        deployRuntime(hex"$probe_hex", probe);

        // path_assign_lifecycle: write index 2 = 10, += 5, return
        assertEq(callU256(probe, abi.encodeWithSignature("path_assign_lifecycle()")), 15);
        assertEq(uint256(vm.load(probe, dynamicArraySlot(0, 2))), 15);
    }

    function testIRDynamicArrayPushAndPop() public {
        address probe = address(uint160(0xB204));
        deployRuntime(hex"$probe_hex", probe);

        // push 7, 11, 13
        callVoid(probe, abi.encodeWithSignature("push_value(uint256)", 7));
        callVoid(probe, abi.encodeWithSignature("push_value(uint256)", 11));
        callVoid(probe, abi.encodeWithSignature("push_value(uint256)", 13));

        assertEq(uint256(vm.load(probe, bytes32(0))), 3);
        assertEq(uint256(vm.load(probe, dynamicArraySlot(0, 0))), 7);
        assertEq(uint256(vm.load(probe, dynamicArraySlot(0, 1))), 11);
        assertEq(uint256(vm.load(probe, dynamicArraySlot(0, 2))), 13);

        // pop removes the last element and decrements length
        callVoid(probe, abi.encodeWithSignature("pop_value()"));
        assertEq(uint256(vm.load(probe, bytes32(0))), 2);

        // pop on empty array reverts
        address emptyProbe = address(uint160(0xB205));
        deployRuntime(hex"$probe_hex", emptyProbe);
        (bool ok,) = emptyProbe.call(abi.encodeWithSignature("pop_value()"));
        assertFalse(ok);
    }

    function testIRDynamicArrayRejectsUnknownSelector() public {
        address probe = address(uint160(0xB203));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "dynamic-array-ir-smoke: ProofForge metadata $METADATA_FILE"

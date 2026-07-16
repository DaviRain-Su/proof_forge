#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmStructArrayValueProbe IR to EVM runtime
# bytecode and validate local fixed arrays of flat structs through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-struct-array-value-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmStructArrayValueProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmStructArrayValueProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "struct-array-value-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "struct-array-value-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "struct-array-value-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-struct-array-value --format bytecode \
  --yul-output "$OUT_DIR/EvmStructArrayValueProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmStructArrayValueProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmStructArrayValueProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmStructArrayValueProbe \
  --expect-source-kind portable-ir \
  --expect-capability data.fixed_array \
  --expect-capability data.struct \
  --expect-capability assertions.check \
  --expect-entrypoint local_struct_array_sum:6dcefec0 \
  --expect-entrypoint dynamic_struct_array_pick:0601d7ac \
  --expect-entrypoint mutable_struct_array_update:bfa2eef8 \
  --expect-entrypoint static_struct_array_update:c8c9bc70 \
  --expect-entrypoint mixed_struct_array_fields:8c32c4da \
  --expect-entrypoint whole_struct_array_assign:cd4a0dc2 \
  --expect-entrypoint self_struct_array_assign:e5ea5747 \
  --expect-entrypoint nested_struct_array_sum:25daebe2 \
  --expect-entrypoint nested_struct_array_dynamic_pick:56d9da6f \
  --expect-entrypoint nested_struct_array_update:d29b2aa1 \
  --expect-entrypoint nested_struct_array_whole_assign:3bd4106e \
  --expect-entrypoint nested_struct_array_self_assign:cd232639 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmStructArrayValueProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRStructArrayValueSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract ProofForgeIRStructArrayValueSmokeTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool value) internal pure {
        require(value, "assertTrue failed");
    }

    function assertFalse(bool value) internal pure {
        require(!value, "assertFalse failed");
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "assertEq uint failed");
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function callBytes(address probe, bytes memory payload) internal returns (bytes memory) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return result;
    }

    function callU256(address probe, bytes memory payload) internal returns (uint256) {
        return abi.decode(callBytes(probe, payload), (uint256));
    }

    function testIRLocalStructArrayStaticFieldReads() public {
        address probe = address(uint160(0xA280));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("local_struct_array_sum()")), 100);
    }

    function testIRLocalStructArrayDynamicFieldReads() public {
        address probe = address(uint160(0xA281));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("dynamic_struct_array_pick(uint256)", 0)), 90);
        assertEq(callU256(probe, abi.encodeWithSignature("dynamic_struct_array_pick(uint256)", 1)), 110);
    }

    function testIRLocalStructArrayDynamicFieldUpdates() public {
        address probe = address(uint160(0xA282));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("mutable_struct_array_update(uint256)", 0)), 117);
        assertEq(callU256(probe, abi.encodeWithSignature("mutable_struct_array_update(uint256)", 1)), 127);
    }

    function testIRLocalStructArrayStaticFieldUpdates() public {
        address probe = address(uint160(0xA283));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("static_struct_array_update()")), 118);
    }

    function testIRLocalStructArrayMixedWordFields() public {
        address probe = address(uint160(0xA284));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("mixed_struct_array_fields()")), 12);
    }

    function testIRLocalStructArrayWholeAssignmentFromLocal() public {
        address probe = address(uint160(0xA285));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("whole_struct_array_assign()")), 60);
    }

    function testIRLocalStructArrayWholeAssignmentSnapshotsRHS() public {
        address probe = address(uint160(0xA286));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("self_struct_array_assign()")), 36);
    }

    function testIRNestedLocalStructArrayStaticFieldReads() public {
        address probe = address(uint160(0xA289));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_sum()")), 120);
    }

    function testIRNestedLocalStructArrayDynamicFieldReads() public {
        address probe = address(uint160(0xA28A));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_dynamic_pick(uint256,uint256)", 0, 0)), 90);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_dynamic_pick(uint256,uint256)", 0, 1)), 110);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_dynamic_pick(uint256,uint256)", 1, 0)), 130);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_dynamic_pick(uint256,uint256)", 1, 1)), 150);
    }

    function testIRNestedLocalStructArrayDynamicFieldUpdates() public {
        address probe = address(uint160(0xA28B));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_update(uint256,uint256)", 0, 0)), 137);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_update(uint256,uint256)", 0, 1)), 147);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_update(uint256,uint256)", 1, 0)), 157);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_update(uint256,uint256)", 1, 1)), 167);
    }

    function testIRNestedLocalStructArrayWholeAssignmentFromLocal() public {
        address probe = address(uint160(0xA28C));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_whole_assign()")), 180);
    }

    function testIRNestedLocalStructArrayWholeAssignmentSnapshotsRHS() public {
        address probe = address(uint160(0xA28D));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("nested_struct_array_self_assign()")), 8);
    }

    function testIRLocalStructArrayDynamicIndexesRejectOutOfBounds() public {
        address probe = address(uint160(0xA287));
        deployRuntime(hex"$probe_hex", probe);

        (bool readOk,) = probe.call(abi.encodeWithSignature("dynamic_struct_array_pick(uint256)", 2));
        assertFalse(readOk);

        (bool writeOk,) = probe.call(abi.encodeWithSignature("mutable_struct_array_update(uint256)", 2));
        assertFalse(writeOk);

        (bool nestedReadRowOk,) = probe.call(abi.encodeWithSignature("nested_struct_array_dynamic_pick(uint256,uint256)", 2, 0));
        assertFalse(nestedReadRowOk);

        (bool nestedReadColOk,) = probe.call(abi.encodeWithSignature("nested_struct_array_dynamic_pick(uint256,uint256)", 0, 2));
        assertFalse(nestedReadColOk);

        (bool nestedWriteRowOk,) = probe.call(abi.encodeWithSignature("nested_struct_array_update(uint256,uint256)", 2, 0));
        assertFalse(nestedWriteRowOk);

        (bool nestedWriteColOk,) = probe.call(abi.encodeWithSignature("nested_struct_array_update(uint256,uint256)", 0, 2));
        assertFalse(nestedWriteColOk);
    }

    function testIRLocalStructArrayRejectsUnknownSelector() public {
        address probe = address(uint160(0xA288));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "struct-array-value-ir-smoke: ProofForge metadata $METADATA_FILE"

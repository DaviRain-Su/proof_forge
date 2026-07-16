#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmArrayValueProbe IR to EVM runtime
# bytecode and validate local fixed-array values through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-array-value-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmArrayValueProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmArrayValueProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "array-value-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "array-value-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "array-value-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-array-value --format bytecode \
  --yul-output "$OUT_DIR/EvmArrayValueProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmArrayValueProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmArrayValueProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmArrayValueProbe \
  --expect-source-kind portable-ir \
  --expect-capability data.fixed_array \
  --expect-capability assertions.check \
  --expect-entrypoint local_sum:77bd09b1 \
  --expect-entrypoint direct_literal_index:7389a736 \
  --expect-entrypoint bool_guard:7c95ba13 \
  --expect-entrypoint u32_pick:a13f4ee0 \
  --expect-entrypoint hash_pick:211a2fc4 \
  --expect-entrypoint mutable_update:0cde63a1 \
  --expect-entrypoint mutable_mixed:70d82dc9 \
  --expect-entrypoint dynamic_pick:17e4f54c \
  --expect-entrypoint dynamic_update:f45e18ed \
  --expect-entrypoint whole_array_assign:d59d3191 \
  --expect-entrypoint nested_local_sum:c54814ec \
  --expect-entrypoint nested_mutable_update:69c5b925 \
  --expect-entrypoint nested_whole_array_assign:1c21ce7e \
  --expect-entrypoint nested_dynamic_pick:deb5ba01 \
  --expect-entrypoint nested_dynamic_row_pick:731f5daf \
  --expect-entrypoint nested_dynamic_update:bd33c419 \
  --expect-entrypoint nested_dynamic_row_update:69437a57 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmArrayValueProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRArrayValueSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract ProofForgeIRArrayValueSmokeTest {
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

    function assertEq(bytes32 actual, bytes32 expected) internal pure {
        require(actual == expected, "assertEq bytes32 failed");
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

    function testIRLocalFixedArrayU64Values() public {
        address probe = address(uint160(0xA260));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("local_sum()")), 20);
    }

    function testIRDirectFixedArrayLiteralIndex() public {
        address probe = address(uint160(0xA261));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("direct_literal_index()")), 6);
    }

    function testIRLocalFixedArrayBoolAndU32Values() public {
        address probe = address(uint160(0xA262));
        deployRuntime(hex"$probe_hex", probe);

        assertFalse(abi.decode(callBytes(probe, abi.encodeWithSignature("bool_guard()")), (bool)));
        assertEq(callU256(probe, abi.encodeWithSignature("u32_pick()")), 5);
    }

    function testIRLocalFixedArrayHashValues() public {
        address probe = address(uint160(0xA263));
        deployRuntime(hex"$probe_hex", probe);

        bytes32 expected = hex"0000000000000001000000000000000200000000000000030000000000000004";
        bytes32 actual = abi.decode(callBytes(probe, abi.encodeWithSignature("hash_pick()")), (bytes32));
        assertEq(actual, expected);
    }

    function testIRMutableLocalFixedArrayUpdates() public {
        address probe = address(uint160(0xA264));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("mutable_update()")), 37);
    }

    function testIRMutableLocalFixedArrayMixedWordUpdates() public {
        address probe = address(uint160(0xA265));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("mutable_mixed()")), 10);
    }

    function testIRLocalFixedArrayDynamicIndexReads() public {
        address probe = address(uint160(0xA266));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("dynamic_pick(uint256)", 1)), 17);
        assertEq(callU256(probe, abi.encodeWithSignature("dynamic_pick(uint256)", 2)), 21);
    }

    function testIRMutableLocalFixedArrayDynamicUpdates() public {
        address probe = address(uint160(0xA267));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("dynamic_update(uint256)", 1)), 23);
        assertEq(callU256(probe, abi.encodeWithSignature("dynamic_update(uint256)", 2)), 23);
    }

    function testIRLocalFixedArrayDynamicIndexesRejectOutOfBounds() public {
        address probe = address(uint160(0xA268));
        deployRuntime(hex"$probe_hex", probe);

        (bool readOk,) = probe.call(abi.encodeWithSignature("dynamic_pick(uint256)", 3));
        assertFalse(readOk);

        (bool writeOk,) = probe.call(abi.encodeWithSignature("dynamic_update(uint256)", 3));
        assertFalse(writeOk);
    }

    function testIRWholeLocalFixedArrayAssignmentSnapshotsRhs() public {
        address probe = address(uint160(0xA269));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("whole_array_assign()")), 94);
    }

    function testIRNestedLocalFixedArrayStaticReads() public {
        address probe = address(uint160(0xA26B));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("nested_local_sum()")), 8);
    }

    function testIRNestedMutableLocalFixedArrayStaticUpdates() public {
        address probe = address(uint160(0xA26C));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("nested_mutable_update()")), 24);
    }

    function testIRNestedWholeLocalFixedArrayAssignmentSnapshotsRhs() public {
        address probe = address(uint160(0xA26D));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("nested_whole_array_assign()")), 13581);
    }

    function testIRNestedLocalFixedArrayDynamicReads() public {
        address probe = address(uint160(0xA26E));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("nested_dynamic_pick(uint256,uint256)", 1, 0)), 5);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_dynamic_pick(uint256,uint256)", 0, 1)), 3);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_dynamic_row_pick(uint256)", 0)), 3);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_dynamic_row_pick(uint256)", 1)), 7);
    }

    function testIRNestedMutableLocalFixedArrayDynamicUpdates() public {
        address probe = address(uint160(0xA26F));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("nested_dynamic_update(uint256,uint256)", 1, 0)), 23);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_dynamic_update(uint256,uint256)", 0, 1)), 23);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_dynamic_row_update(uint256)", 0)), 23);
        assertEq(callU256(probe, abi.encodeWithSignature("nested_dynamic_row_update(uint256)", 1)), 23);
    }

    function testIRNestedLocalFixedArrayDynamicIndexesRejectOutOfBounds() public {
        address probe = address(uint160(0xA270));
        deployRuntime(hex"$probe_hex", probe);

        (bool readRowOk,) = probe.call(abi.encodeWithSignature("nested_dynamic_pick(uint256,uint256)", 2, 0));
        assertFalse(readRowOk);

        (bool readColOk,) = probe.call(abi.encodeWithSignature("nested_dynamic_pick(uint256,uint256)", 0, 2));
        assertFalse(readColOk);

        (bool readMixedOk,) = probe.call(abi.encodeWithSignature("nested_dynamic_row_pick(uint256)", 2));
        assertFalse(readMixedOk);

        (bool writeRowOk,) = probe.call(abi.encodeWithSignature("nested_dynamic_update(uint256,uint256)", 2, 0));
        assertFalse(writeRowOk);

        (bool writeColOk,) = probe.call(abi.encodeWithSignature("nested_dynamic_update(uint256,uint256)", 0, 2));
        assertFalse(writeColOk);

        (bool writeMixedOk,) = probe.call(abi.encodeWithSignature("nested_dynamic_row_update(uint256)", 2));
        assertFalse(writeMixedOk);
    }

    function testIRLocalFixedArrayRejectsUnknownSelector() public {
        address probe = address(uint160(0xA26A));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "array-value-ir-smoke: ProofForge metadata $METADATA_FILE"

#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmStructValueProbe IR to EVM runtime
# bytecode and validate flat local struct values through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-struct-value-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmStructValueProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmStructValueProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "struct-value-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "struct-value-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "struct-value-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-struct-value --format bytecode \
  --yul-output "$OUT_DIR/EvmStructValueProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmStructValueProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmStructValueProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmStructValueProbe \
  --expect-source-kind portable-ir \
  --expect-capability data.struct \
  --expect-capability assertions.check \
  --expect-entrypoint local_sum:77bd09b1 \
  --expect-entrypoint direct_literal_field:25e7fc3e \
  --expect-entrypoint bool_guard:7c95ba13 \
  --expect-entrypoint u32_pick:a13f4ee0 \
  --expect-entrypoint hash_pick:211a2fc4 \
  --expect-entrypoint mutable_point_update:c7096012 \
  --expect-entrypoint mutable_mixed_fields:b18f76a4 \
  --expect-entrypoint whole_struct_assign:b416b147 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmStructValueProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRStructValueSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract ProofForgeIRStructValueSmokeTest {
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

    function testIRLocalStructU64Fields() public {
        address probe = address(uint160(0xA270));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("local_sum()")), 20);
    }

    function testIRDirectStructLiteralField() public {
        address probe = address(uint160(0xA271));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("direct_literal_field()")), 6);
    }

    function testIRLocalStructBoolAndU32Fields() public {
        address probe = address(uint160(0xA272));
        deployRuntime(hex"$probe_hex", probe);

        assertFalse(abi.decode(callBytes(probe, abi.encodeWithSignature("bool_guard()")), (bool)));
        assertEq(callU256(probe, abi.encodeWithSignature("u32_pick()")), 5);
    }

    function testIRLocalStructHashFields() public {
        address probe = address(uint160(0xA273));
        deployRuntime(hex"$probe_hex", probe);

        bytes32 expected = hex"0000000000000001000000000000000200000000000000030000000000000004";
        bytes32 actual = abi.decode(callBytes(probe, abi.encodeWithSignature("hash_pick()")), (bytes32));
        assertEq(actual, expected);
    }

    function testIRMutableLocalStructFieldUpdates() public {
        address probe = address(uint160(0xA274));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("mutable_point_update()")), 27);
    }

    function testIRMutableLocalStructMixedFieldUpdates() public {
        address probe = address(uint160(0xA275));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("mutable_mixed_fields()")), 10);
    }

    function testIRWholeLocalStructAssignmentSnapshotsRhs() public {
        address probe = address(uint160(0xA276));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("whole_struct_assign()")), 81);
    }

    function testIRLocalStructRejectsUnknownSelector() public {
        address probe = address(uint160(0xA277));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "struct-value-ir-smoke: ProofForge metadata $METADATA_FILE"

#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmExpressionProbe IR to EVM runtime
# bytecode and validate scalar expression lowering through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-expression-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmExpressionProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmExpressionProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "expression-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "expression-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "expression-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-expression --format bytecode \
  --yul-output "$OUT_DIR/EvmExpressionProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmExpressionProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmExpressionProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmExpressionProbe \
  --expect-source-kind portable-ir \
  --expect-capability assertions.check \
  --expect-entrypoint arithmetic_u64:139ade38 \
  --expect-entrypoint bitwise_u64:2e124ba8 \
  --expect-entrypoint predicate_matrix:219a55f8 \
  --expect-entrypoint casts_and_u32:555e000e \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmExpressionProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRExpressionSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract ProofForgeIRExpressionSmokeTest {
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

    function callU256(address probe, bytes memory payload) internal returns (uint256) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (uint256));
    }

    function testIRArithmeticExpressions() public {
        address probe = address(uint160(0xE510));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("arithmetic_u64()")), 40);
    }

    function testIRBitwiseExpressions() public {
        address probe = address(uint160(0xE511));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("bitwise_u64()")), 11);
    }

    function testIRPredicateExpressions() public {
        address probe = address(uint160(0xE512));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("predicate_matrix()")), 8);
    }

    function testIRCastsAndU32Expressions() public {
        address probe = address(uint160(0xE513));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("casts_and_u32(uint32,bool)", uint32(7), true)), 50);
        assertEq(callU256(probe, abi.encodeWithSignature("casts_and_u32(uint32,bool)", uint32(7), false)), 48);
    }

    function testIRExpressionRejectsMalformedCalldata() public {
        address probe = address(uint160(0xE514));
        deployRuntime(hex"$probe_hex", probe);

        bytes4 selector = bytes4(0x555e000e);

        (bool shortOk,) = probe.call(abi.encodePacked(selector, uint256(7)));
        assertFalse(shortOk);

        (bool overflowU32Ok,) = probe.call(abi.encodePacked(
            selector,
            uint256(type(uint32).max) + 1,
            uint256(0)
        ));
        assertFalse(overflowU32Ok);

        (bool invalidBoolOk,) = probe.call(abi.encodePacked(
            selector,
            uint256(7),
            uint256(2)
        ));
        assertFalse(invalidBoolOk);
    }

    function testIRExpressionRejectsUnknownSelector() public {
        address probe = address(uint160(0xE515));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "expression-ir-smoke: ProofForge metadata $METADATA_FILE"

#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmLoopProbe IR to EVM runtime bytecode
# and validate bounded-loop lowering through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-loop-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmLoopProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmLoopProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "loop-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "loop-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "loop-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-loop --format bytecode \
  --yul-output "$OUT_DIR/EvmLoopProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmLoopProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmLoopProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmLoopProbe \
  --expect-source-kind portable-ir \
  --expect-capability storage.scalar \
  --expect-capability control.conditional \
  --expect-capability control.bounded_loop \
  --expect-entrypoint count_to_three:c4eff2de \
  --expect-entrypoint choose_with_early_return:d9b42937 \
  --expect-entrypoint loop_early_return:d11c9505 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmLoopProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRLoopSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRLoopSmokeTest {
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

    function callU256(address probe, bytes memory payload) internal returns (uint256) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (uint256));
    }

    function testIRBoundedLoopCountsToThree() public {
        address probe = address(uint160(0xE150));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("count_to_three()")), 3);
        assertEq(uint256(vm.load(probe, bytes32(uint256(0)))) & type(uint64).max, 3);
    }

    function testIRBranchLocalEarlyReturn() public {
        address probe = address(uint160(0xE152));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("choose_with_early_return(bool)", true)), 11);
        assertEq(uint256(vm.load(probe, bytes32(uint256(0)))) & type(uint64).max, 0);

        assertEq(callU256(probe, abi.encodeWithSignature("choose_with_early_return(bool)", false)), 99);
        assertEq(uint256(vm.load(probe, bytes32(uint256(0)))) & type(uint64).max, 99);

    }

    function testIRLoopLocalEarlyReturn() public {
        address probe = address(uint160(0xE153));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callU256(probe, abi.encodeWithSignature("loop_early_return()")), 0);
        assertEq(uint256(vm.load(probe, bytes32(uint256(0)))) & type(uint64).max, 100);
    }

    function testIRBoundedLoopRejectsUnknownSelector() public {
        address probe = address(uint160(0xE151));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "loop-ir-smoke: ProofForge metadata $METADATA_FILE"

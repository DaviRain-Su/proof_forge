#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmMemoryArrayProbe IR to EVM runtime
# bytecode and verify memory array new/set/get/length operations.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-memory-array-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmMemoryArrayProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmMemoryArrayProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found; install Foundry" >&2
  exit 1
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "solc not found; install solc" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-memory-array --format bytecode \
  --yul-output "$OUT_DIR/EvmMemoryArrayProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmMemoryArrayProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmMemoryArrayProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmMemoryArrayProbe \
  --expect-source-kind portable-ir \
  --expect-capability data.dynamic_array \
  --expect-entrypoint memory_lifecycle:351b36c7 \
  --expect-entrypoint memory_length:f748ed48 \
  --expect-entrypoint get_and_sum:c46232c0 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmMemoryArrayProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRMemoryArraySmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract ProofForgeIRMemoryArraySmokeTest {
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

    function testIRMemoryArrayLifecycle() public {
        address probe = address(uint160(0xB300));
        deployRuntime(hex"$probe_hex", probe);

        // memory_lifecycle: new u64[3], set {7,11,13}, return sum
        assertEq(callU256(probe, abi.encodeWithSignature("memory_lifecycle()")), 31);
    }

    function testIRMemoryArrayLength() public {
        address probe = address(uint160(0xB301));
        deployRuntime(hex"$probe_hex", probe);

        // memory_length: new u64[5], return length
        assertEq(callU256(probe, abi.encodeWithSignature("memory_length()")), 5);
    }

    function testIRMemoryArrayGetAndSum() public {
        address probe = address(uint160(0xB302));
        deployRuntime(hex"$probe_hex", probe);

        // get_and_sum(uint64,uint64,uint64): new u64[3], set {a,b,c}, return sum
        assertEq(callU256(probe, abi.encodeWithSignature("get_and_sum(uint256,uint256,uint256)", 7, 11, 13)), 31);
    }

    function testIRMemoryArrayRejectsUnknownSelector() public {
        address probe = address(uint160(0xB303));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "memory-array-ir-smoke: ProofForge metadata $METADATA_FILE"

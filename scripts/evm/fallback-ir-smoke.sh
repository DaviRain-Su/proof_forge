#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmFallbackProbe IR to EVM runtime
# bytecode and verify fallback/receive entrypoint dispatch.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-fallback-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Evm/EvmFallbackProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmFallbackProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found" >&2
  exit 1
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "solc not found" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-fallback --format bytecode \
  --yul-output "$OUT_DIR/EvmFallbackProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmFallbackProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmFallbackProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmFallbackProbe \
  --expect-source-kind portable-ir \
  --expect-capability storage.scalar \
  --expect-entrypoint increment:d09de08a \
  --expect-entrypoint getValue:20965255 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmFallbackProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRFallbackSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRFallbackSmokeTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function assertTrue(bool value) internal pure { require(value, "assertTrue"); }
    function assertFalse(bool value) internal pure { require(!value, "assertFalse"); }
    function assertEq(uint64 a, uint64 b) internal pure { require(a == b, "assertEq"); }

    address constant PROBE = address(uint160(0xF100));

    function setUp() public {
        deployRuntime(hex"${probe_hex}", PROBE);
    }

    function test_getValue_initial_zero() public {
        (bool ok, bytes memory ret) = PROBE.call(hex"20965255");
        assertTrue(ok);
        require(ret.length == 32, "should return one word");
        uint64 result = abi.decode(ret, (uint64));
        assertEq(result, 0);
    }

    function test_increment_succeeds() public {
        (bool ok,) = PROBE.call(hex"d09de08a");
        assertTrue(ok);
        (bool ok2, bytes memory ret) = PROBE.call(hex"20965255");
        assertTrue(ok2);
        uint64 result = abi.decode(ret, (uint64));
        assertEq(result, 1);
    }

    function test_unknown_selector_reverts() public {
        (bool ok,) = PROBE.call(hex"deadbeef");
        assertFalse(ok);
    }

    function test_empty_calldata_succeeds() public {
        // Empty calldata triggers receive path
        (bool ok,) = PROBE.call("");
        assertTrue(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "fallback-ir-smoke: ProofForge metadata $METADATA_FILE"
#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmAssignOpProbe IR to EVM runtime
# bytecode and validate local/scalar-storage compound assignment through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-assign-op-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Evm/EvmAssignOpProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmAssignOpProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "assign-op-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "assign-op-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "assign-op-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-assign-op --format bytecode \
  --yul-output "$OUT_DIR/EvmAssignOpProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmAssignOpProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmAssignOpProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmAssignOpProbe \
  --expect-source-kind portable-ir \
  --expect-capability storage.scalar \
  --expect-entrypoint compound_assignment:72250d96 \
  --expect-entrypoint compound_u32:1508c8ff \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmAssignOpProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRAssignOpSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRAssignOpSmokeTest {
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

    function readStorage(address target, uint256 slot) internal view returns (uint256) {
        return uint256(vm.load(target, bytes32(slot)));
    }

    function callU256(address probe, bytes memory payload) internal returns (uint256) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (uint256));
    }

    function testIRCompoundAssignmentUpdatesLocalAndStorage() public {
        address probe = address(uint160(0xA50F));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(
            callU256(probe, abi.encodeWithSignature("compound_assignment(uint256)", uint256(10))),
            58
        );
        assertEq(readStorage(probe, 0) >> 192, 58);
    }

    function testIRCompoundAssignmentSupportsU32Locals() public {
        address probe = address(uint160(0xA510));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(
            callU256(probe, abi.encodeWithSignature("compound_u32(uint32)", uint32(20))),
            11
        );
    }

    function testIRCompoundAssignmentRejectsUnknownSelector() public {
        address probe = address(uint160(0xA511));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "assign-op-ir-smoke: ProofForge metadata $METADATA_FILE"

#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable AssignmentProbe IR to EVM runtime bytecode
# and validate mutable local bindings plus local assignment through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-assignment-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/AssignmentProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/AssignmentProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "assignment-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "assignment-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "assignment-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture assignment --format bytecode \
  --yul-output "$OUT_DIR/AssignmentProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/AssignmentProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/AssignmentProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture AssignmentProbe \
  --expect-source-kind portable-ir \
  --expect-capability assertions.check \
  --expect-entrypoint reassignment:91a3e2ac \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/AssignmentProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRAssignmentSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract ProofForgeIRAssignmentSmokeTest {
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

    function testIRLocalAssignmentReturnsUpdatedValue() public {
        address probe = address(0xA551);
        deployRuntime(hex"$probe_hex", probe);

        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("reassignment(uint256)", uint256(5)));
        assertTrue(ok);
        assertEq(abi.decode(result, (uint256)), 12);
    }

    function testIRLocalAssignmentRevertsWhenGuardIsFalse() public {
        address probe = address(0xA552);
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) =
            probe.call(abi.encodeWithSignature("reassignment(uint256)", uint256(4)));
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "assignment-ir-smoke: ProofForge metadata $METADATA_FILE"

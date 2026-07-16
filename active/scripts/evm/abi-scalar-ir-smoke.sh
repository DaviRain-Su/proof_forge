#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable AbiScalarProbe IR to EVM runtime bytecode
# and validate scalar ABI calldata decoding through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-abi-scalar-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/AbiScalarProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/AbiScalarProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "abi-scalar-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "abi-scalar-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "abi-scalar-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture abi-scalar --format bytecode \
  --yul-output "$OUT_DIR/AbiScalarProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  --evm-chain-profile robinhood-chain-testnet \
  -o "$OUT_DIR/AbiScalarProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/AbiScalarProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture AbiScalarProbe \
  --expect-source-kind portable-ir \
  --expect-chain-profile robinhood-chain-testnet \
  --expect-chain-id 46630 \
  --expect-entrypoint mix:7f97495c \
  --expect-entrypoint same:c32c70b1 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/AbiScalarProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRAbiScalarSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract ProofForgeIRAbiScalarSmokeTest {
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

    function assertEq(bool actual, bool expected) internal pure {
        require(actual == expected, "assertEq(bool) failed");
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function callMix(address probe, uint256 base, uint32 delta, bool flag) internal returns (uint256) {
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("mix(uint256,uint32,bool)", base, delta, flag));
        assertTrue(ok);
        return abi.decode(result, (uint256));
    }

    function callSame(address probe, uint256 left, uint256 right) internal returns (bool) {
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("same(uint256,uint256)", left, right));
        assertTrue(ok);
        return abi.decode(result, (bool));
    }

    function testIRAbiScalarParameters() public {
        address probe = address(0xAB1);
        deployRuntime(hex"$probe_hex", probe);

        assertEq(callMix(probe, 10, 5, true), 16);
        assertEq(callMix(probe, 10, 5, false), 15);
        assertEq(callSame(probe, 7, 7), true);
        assertEq(callSame(probe, 7, 8), false);
    }

    function testIRAbiScalarRejectsMalformedCalldata() public {
        address probe = address(0xAB2);
        deployRuntime(hex"$probe_hex", probe);

        bytes4 mixSelector = bytes4(keccak256("mix(uint256,uint32,bool)"));

        (bool shortOk,) = probe.call(abi.encodePacked(mixSelector, uint256(10)));
        assertFalse(shortOk);

        (bool overflowU32Ok,) = probe.call(abi.encodePacked(
            mixSelector,
            uint256(10),
            uint256(type(uint32).max) + 1,
            uint256(0)
        ));
        assertFalse(overflowU32Ok);

        (bool invalidBoolOk,) = probe.call(abi.encodePacked(
            mixSelector,
            uint256(10),
            uint256(5),
            uint256(2)
        ));
        assertFalse(invalidBoolOk);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "abi-scalar-ir-smoke: ProofForge metadata $METADATA_FILE"

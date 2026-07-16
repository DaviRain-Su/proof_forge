#!/usr/bin/env bash
set -euo pipefail

# Compile the EvmArrayAbiProbe IR to EVM runtime bytecode
# and validate dynamic array ABI head-tail encoding through Foundry round-trip tests.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-array-abi-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmArrayAbiProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmArrayAbiProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "Foundry forge not found; install from https://getfoundry.sh" >&2
  exit 1
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "solc not found; install solc 0.8.x" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-array-abi --format bytecode \
  --yul-output "$OUT_DIR/EvmArrayAbiProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  --evm-chain-profile robinhood-chain-testnet \
  -o "$OUT_DIR/EvmArrayAbiProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmArrayAbiProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmArrayAbiProbe \
  --expect-source-kind portable-ir \
  --expect-chain-profile robinhood-chain-testnet \
  --expect-chain-id 46630 \
  --expect-entrypoint echo_array:c3b0874d \
  --expect-entrypoint sum_array:bc2d8fd1 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmArrayAbiProbe.bin")"

rm -rf "$FORGE_DIR"
mkdir -p "$FORGE_DIR/test"

cat > "$FORGE_DIR/foundry.toml" <<'TOML'
[profile.default]
src = "test"
out = "out"
script = "script"
libs = ["lib"]
TOML

cat > "$FORGE_DIR/test/ProofForgeIRArrayAbiSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract ProofForgeIRArrayAbiSmokeTest {
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

    function assertEq(uint256[] memory actual, uint256[] memory expected) internal pure {
        require(actual.length == expected.length, "assertEq(uint256[]) length failed");
        for (uint256 i = 0; i < actual.length; i++) {
            require(actual[i] == expected[i], "assertEq(uint256[]) element failed");
        }
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function callEchoArray(address probe, uint256[] memory data) internal returns (uint256[] memory) {
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("echo_array(uint256[])", data));
        assertTrue(ok);
        return abi.decode(result, (uint256[]));
    }

    function callSumArray(address probe, uint256[] memory data) internal returns (uint256) {
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("sum_array(uint256[])", data));
        assertTrue(ok);
        return abi.decode(result, (uint256));
    }

    function testIREchoArrayRoundTrip() public {
        address probe = address(0xDA1);
        deployRuntime(hex"$probe_hex", probe);

        uint256[] memory shortArr = new uint256[](3);
        shortArr[0] = 1;
        shortArr[1] = 2;
        shortArr[2] = 3;
        assertEq(callEchoArray(probe, shortArr), shortArr);

        uint256[] memory emptyArr = new uint256[](0);
        assertEq(callEchoArray(probe, emptyArr), emptyArr);

        uint256[] memory longArr = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            longArr[i] = i + 42;
        }
        assertEq(callEchoArray(probe, longArr), longArr);
    }

    function testIRSumArray() public {
        address probe = address(0xDA2);
        deployRuntime(hex"$probe_hex", probe);

        uint256[] memory arr = new uint256[](3);
        arr[0] = 10;
        arr[1] = 20;
        arr[2] = 30;
        assertEq(callSumArray(probe, arr), 60);
    }

    function testIRArrayAbiRejectsUnknownSelector() public {
        address probe = address(0xDA3);
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(abi.encodeWithSignature("nonexistent()"));
        assertFalse(ok);
    }

    function testIRArrayAbiRejectsMalformedCalldata() public {
        address probe = address(0xDA4);
        deployRuntime(hex"$probe_hex", probe);

        bytes4 selector = bytes4(keccak256("echo_array(uint256[])"));
        (bool shortOk,) = probe.call(abi.encodePacked(selector));
        assertFalse(shortOk);

        (bool badOffsetOk,) = probe.call(abi.encodePacked(
            selector,
            uint256(0xffff)
        ));
        assertFalse(badOffsetOk);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "array-abi-ir-smoke: ProofForge metadata $METADATA_FILE"

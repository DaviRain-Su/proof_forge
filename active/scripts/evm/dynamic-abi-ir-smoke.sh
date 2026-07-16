#!/usr/bin/env bash
set -euo pipefail

# Compile the EvmDynamicAbiProbe IR to EVM runtime bytecode
# and validate dynamic ABI head-tail encoding (bytes, string, address)
# through Foundry round-trip tests.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-dynamic-abi-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmDynamicAbiProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmDynamicAbiProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "error: forge not found on PATH" >&2
  exit 1
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "error: solc not found on PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-dynamic-abi --format bytecode \
  --yul-output "$OUT_DIR/EvmDynamicAbiProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  --evm-chain-profile robinhood-chain-testnet \
  -o "$OUT_DIR/EvmDynamicAbiProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmDynamicAbiProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmDynamicAbiProbe \
  --expect-source-kind portable-ir \
  --expect-chain-profile robinhood-chain-testnet \
  --expect-chain-id 46630 \
  --expect-entrypoint echo_bytes:1cc09e37 \
  --expect-entrypoint echo_string:41ccc945 \
  --expect-entrypoint transfer:a9059cbb \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmDynamicAbiProbe.bin")"

rm -rf "$FORGE_DIR"
mkdir -p "$FORGE_DIR/test"

cat > "$FORGE_DIR/foundry.toml" <<'TOML'
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
evm_version = "cancun"
TOML

cat > "$FORGE_DIR/test/ProofForgeIRDynamicAbiSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract ProofForgeIRDynamicAbiSmokeTest {
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

    function assertEq(bytes memory actual, bytes memory expected) internal pure {
        require(keccak256(actual) == keccak256(expected), "assertEq(bytes) failed");
    }

    function assertEq(string memory actual, string memory expected) internal pure {
        require(keccak256(bytes(actual)) == keccak256(bytes(expected)), "assertEq(string) failed");
    }

    function assertEq(bool actual, bool expected) internal pure {
        require(actual == expected, "assertEq(bool) failed");
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function callEchoBytes(address probe, bytes memory data) internal returns (bytes memory) {
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("echo_bytes(bytes)", data));
        assertTrue(ok);
        return abi.decode(result, (bytes));
    }

    function callEchoString(address probe, string memory data) internal returns (string memory) {
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("echo_string(string)", data));
        assertTrue(ok);
        return abi.decode(result, (string));
    }

    function callTransfer(address probe, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory result) =
            probe.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        assertTrue(ok);
        return abi.decode(result, (bool));
    }

    function testIREchoBytesRoundTrip() public {
        address probe = address(0xDA1);
        deployRuntime(hex"$probe_hex", probe);

        // Empty bytes
        assertEq(callEchoBytes(probe, ""), "");

        // Short bytes (fits in one word)
        assertEq(callEchoBytes(probe, hex"deadbeef"), hex"deadbeef");

        // Longer bytes (spans multiple words)
        bytes memory longData = new bytes(100);
        for (uint256 i = 0; i < 100; i++) {
            longData[i] = bytes1(uint8(i));
        }
        assertEq(callEchoBytes(probe, longData), longData);

        // Exactly 32 bytes (one full word)
        bytes memory exactWord = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            exactWord[i] = bytes1(uint8(i + 1));
        }
        assertEq(callEchoBytes(probe, exactWord), exactWord);

        // 33 bytes (one word + 1 byte)
        bytes memory wordPlusOne = new bytes(33);
        for (uint256 i = 0; i < 33; i++) {
            wordPlusOne[i] = bytes1(uint8(i + 1));
        }
        assertEq(callEchoBytes(probe, wordPlusOne), wordPlusOne);
    }

    function testIREchoStringRoundTrip() public {
        address probe = address(0xDA2);
        deployRuntime(hex"$probe_hex", probe);

        // Empty string
        assertEq(callEchoString(probe, ""), "");

        // Short string
        assertEq(callEchoString(probe, "hello"), "hello");

        // Longer string
        string memory longStr = "The quick brown fox jumps over the lazy dog!";
        assertEq(callEchoString(probe, longStr), longStr);

        // String with special characters
        string memory special = "Hello, \xe4\xb8\x96\xe7\x95\x8c!";  // "Hello, 世界!"
        assertEq(callEchoString(probe, special), special);
    }

    function testIRTransferAddressUint256() public {
        address probe = address(0xDA3);
        deployRuntime(hex"$probe_hex", probe);

        // Transfer to a specific address with a specific amount
        address to = address(0x1234);
        assertEq(callTransfer(probe, to, 1000), true);

        // Transfer to zero address
        assertEq(callTransfer(probe, address(0), 0), true);
    }

    function testIRDynamicAbiRejectsUnknownSelector() public {
        address probe = address(0xDA4);
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(abi.encodeWithSignature("nonexistent()"));
        assertFalse(ok);
    }

    function testIRDynamicAbiRejectsMalformedCalldata() public {
        address probe = address(0xDA5);
        deployRuntime(hex"$probe_hex", probe);

        // Short calldata (only selector, missing offset word for echo_bytes)
        bytes4 selector = bytes4(keccak256("echo_bytes(bytes)"));
        (bool shortOk,) = probe.call(abi.encodePacked(selector));
        assertFalse(shortOk);

        // Offset pointing beyond calldata
        (bool badOffsetOk,) = probe.call(abi.encodePacked(
            selector,
            uint256(0xffff)  // offset way beyond calldata end
        ));
        assertFalse(badOffsetOk);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "dynamic-abi-ir-smoke: ProofForge metadata $METADATA_FILE"
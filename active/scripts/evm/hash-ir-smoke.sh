#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmHashProbe IR to EVM runtime bytecode
# and validate Hash word packing, keccak lowering, ABI dispatch, and storage.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-hash-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmHashProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmHashProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "hash-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "hash-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "hash-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-hash --format bytecode \
  --yul-output "$OUT_DIR/EvmHashProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmHashProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmHashProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmHashProbe \
  --expect-source-kind portable-ir \
  --expect-capability crypto.hash \
  --expect-capability storage.scalar \
  --expect-entrypoint hash_literal:1214538f \
  --expect-entrypoint hash_pair:6b28555d \
  --expect-entrypoint pack_hash:5d6d411d \
  --expect-entrypoint hash_param:3db89466 \
  --expect-entrypoint store_hash:a9a07fbf \
  --expect-entrypoint read_root:e3dfebc3 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmHashProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRHashSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRHashSmokeTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool value) internal pure {
        require(value, "assertTrue failed");
    }

    function assertFalse(bool value) internal pure {
        require(!value, "assertFalse failed");
    }

    function assertEq(bytes32 actual, bytes32 expected) internal pure {
        require(actual == expected, "assertEq(bytes32) failed");
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function packed(uint64 a, uint64 b, uint64 c, uint64 d) internal pure returns (bytes32) {
        return bytes32(
            (uint256(a) << 192) |
            (uint256(b) << 128) |
            (uint256(c) << 64) |
            uint256(d)
        );
    }

    function callBytes32(address probe, bytes memory payload) internal returns (bytes32) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (bytes32));
    }

    function testIRHashKeccakAndPacking() public {
        address probe = address(uint160(0xE120));
        deployRuntime(hex"$probe_hex", probe);

        bytes32 left = packed(1, 2, 3, 4);
        bytes32 right = packed(5, 6, 7, 8);
        bytes32 input = packed(13, 14, 15, 16);

        assertEq(
            callBytes32(probe, abi.encodeWithSignature("hash_literal()")),
            keccak256(abi.encode(left))
        );
        assertEq(
            callBytes32(probe, abi.encodeWithSignature("hash_pair()")),
            keccak256(abi.encode(left, right))
        );
        assertEq(
            callBytes32(probe, abi.encodeWithSignature("pack_hash(uint256,uint256,uint256,uint256)", 9, 10, 11, 12)),
            packed(9, 10, 11, 12)
        );
        assertEq(
            callBytes32(probe, abi.encodeWithSignature("hash_param(bytes32)", input)),
            keccak256(abi.encode(input))
        );
    }

    function testIRHashScalarStorage() public {
        address probe = address(uint160(0xE121));
        deployRuntime(hex"$probe_hex", probe);

        bytes32 value = packed(21, 22, 23, 24);
        assertEq(callBytes32(probe, abi.encodeWithSignature("read_root()")), bytes32(0));
        assertEq(callBytes32(probe, abi.encodeWithSignature("store_hash(bytes32)", value)), value);
        assertEq(callBytes32(probe, abi.encodeWithSignature("read_root()")), value);
        assertEq(vm.load(probe, bytes32(uint256(0))), value);
    }

    function testIRHashRejectsUnknownSelector() public {
        address probe = address(uint160(0xE122));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "hash-ir-smoke: ProofForge metadata $METADATA_FILE"

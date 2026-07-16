#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmAbiAggregateProbe IR to EVM runtime
# bytecode and validate flat static aggregate ABI encoding through Foundry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-abi-aggregate-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmAbiAggregateProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmAbiAggregateProbe.proof-forge-artifact.json}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "abi-aggregate-ir-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "abi-aggregate-ir-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "abi-aggregate-ir-smoke: solc not found on PATH." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-abi-aggregate --format bytecode \
  --yul-output "$OUT_DIR/EvmAbiAggregateProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmAbiAggregateProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmAbiAggregateProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmAbiAggregateProbe \
  --expect-source-kind portable-ir \
  --expect-capability data.fixed_array \
  --expect-capability data.struct \
  --expect-entrypoint sum_pair:25508e13 \
  --expect-entrypoint sum_array:eb353b80 \
  --expect-entrypoint sum_matrix:da76e471 \
  --expect-entrypoint sum_pair_array:10e4c1da \
  --expect-entrypoint make_pair:ef51ff62 \
  --expect-entrypoint make_pair_array:617df171 \
  --expect-entrypoint make_matrix:b61c11b8 \
  --expect-entrypoint make_array:ffac5c16 \
  --expect-entrypoint sum_small:384e9976 \
  --expect-entrypoint sum_small_matrix:94f90bdd \
  --expect-entrypoint and_flags:1df89823 \
  --expect-entrypoint echo_hash_pair:5e248cf3 \
  --expect-entrypoint make_hash_pair:d3a9b1bd \
  --expect-entrypoint pick_hash:44d9885a \
  --expect-entrypoint make_hash_array:3fcd733b \
  --expect-entrypoint-abi 'sum_pair:sum_pair((uint256,uint256)):2:1' \
  --expect-entrypoint-abi 'sum_array:sum_array(uint256[3]):3:1' \
  --expect-entrypoint-abi 'sum_matrix:sum_matrix(uint256[2][2]):4:1' \
  --expect-entrypoint-abi 'sum_pair_array:sum_pair_array((uint256,uint256)[2]):4:1' \
  --expect-entrypoint-abi 'make_pair:make_pair(uint256,uint256):2:2' \
  --expect-entrypoint-abi 'make_pair_array:make_pair_array(uint256,uint256,uint256,uint256):4:4' \
  --expect-entrypoint-abi 'make_matrix:make_matrix(uint256,uint256,uint256,uint256):4:4' \
  --expect-entrypoint-abi 'make_array:make_array(uint256,uint256,uint256):3:3' \
  --expect-entrypoint-abi 'sum_small:sum_small(uint32[2]):2:1' \
  --expect-entrypoint-abi 'sum_small_matrix:sum_small_matrix(uint32[2][2]):4:1' \
  --expect-entrypoint-abi 'and_flags:and_flags((bool,bool)):2:1' \
  --expect-entrypoint-abi 'echo_hash_pair:echo_hash_pair((bytes32,bytes32)):2:1' \
  --expect-entrypoint-abi 'make_hash_pair:make_hash_pair(bytes32,bytes32):2:2' \
  --expect-entrypoint-abi 'pick_hash:pick_hash(bytes32[2]):2:1' \
  --expect-entrypoint-abi 'make_hash_array:make_hash_array(bytes32,bytes32):2:2' \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmAbiAggregateProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRAbiAggregateSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract ProofForgeIRAbiAggregateSmokeTest {
    struct Pair {
        uint256 left;
        uint256 right;
    }

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

    function assertEq(bytes32 actual, bytes32 expected) internal pure {
        require(actual == expected, "assertEq(bytes32) failed");
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function packed(uint64 a, uint64 b, uint64 c, uint64 d) internal pure returns (bytes32) {
        return bytes32((uint256(a) << 192) | (uint256(b) << 128) | (uint256(c) << 64) | uint256(d));
    }

    function callBytes(address probe, bytes memory payload) internal returns (bytes memory) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return result;
    }

    function callU256(address probe, bytes memory payload) internal returns (uint256) {
        return abi.decode(callBytes(probe, payload), (uint256));
    }

    function testIRAbiAggregateParameters() public {
        address probe = address(uint160(0xA280));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(
            callU256(probe, abi.encodeWithSignature("sum_pair((uint256,uint256))", uint256(7), uint256(8))),
            15
        );

        uint256[3] memory xs = [uint256(2), uint256(3), uint256(5)];
        assertEq(callU256(probe, abi.encodeWithSignature("sum_array(uint256[3])", xs)), 10);

        uint256[2][2] memory matrix;
        matrix[0][0] = 1;
        matrix[0][1] = 2;
        matrix[1][0] = 3;
        matrix[1][1] = 5;
        assertEq(callU256(probe, abi.encodeWithSignature("sum_matrix(uint256[2][2])", matrix)), 11);

        Pair[2] memory pairs;
        pairs[0] = Pair({left: 2, right: 3});
        pairs[1] = Pair({left: 5, right: 7});
        assertEq(callU256(probe, abi.encodeWithSignature("sum_pair_array((uint256,uint256)[2])", pairs)), 17);

        uint32[2] memory smalls = [uint32(17), uint32(19)];
        assertEq(callU256(probe, abi.encodeWithSignature("sum_small(uint32[2])", smalls)), 36);

        uint32[2][2] memory smallMatrix;
        smallMatrix[0][0] = 1;
        smallMatrix[0][1] = 2;
        smallMatrix[1][0] = 3;
        smallMatrix[1][1] = 4;
        assertEq(callU256(probe, abi.encodeWithSignature("sum_small_matrix(uint32[2][2])", smallMatrix)), 10);

        assertFalse(abi.decode(
            callBytes(probe, abi.encodeWithSignature("and_flags((bool,bool))", true, false)),
            (bool)
        ));

        bytes32 rootA = packed(1, 2, 3, 4);
        bytes32 rootB = packed(5, 6, 7, 8);
        assertEq(
            abi.decode(
                callBytes(probe, abi.encodeWithSignature("echo_hash_pair((bytes32,bytes32))", rootA, rootB)),
                (bytes32)
            ),
            rootB
        );

        bytes32[2] memory roots = [rootA, rootB];
        assertEq(
            abi.decode(callBytes(probe, abi.encodeWithSignature("pick_hash(bytes32[2])", roots)), (bytes32)),
            rootB
        );
    }

    function testIRAbiAggregateReturns() public {
        address probe = address(uint160(0xA281));
        deployRuntime(hex"$probe_hex", probe);

        bytes memory pairResult =
            callBytes(probe, abi.encodeWithSignature("make_pair(uint256,uint256)", uint256(21), uint256(34)));
        (uint256 left, uint256 right) = abi.decode(pairResult, (uint256, uint256));
        assertEq(left, 21);
        assertEq(right, 34);

        uint256[3] memory ys = abi.decode(
            callBytes(
                probe,
                abi.encodeWithSignature("make_array(uint256,uint256,uint256)", uint256(5), uint256(8), uint256(13))
            ),
            (uint256[3])
        );
        assertEq(ys[0], 5);
        assertEq(ys[1], 8);
        assertEq(ys[2], 13);

        Pair[2] memory pairs = abi.decode(
            callBytes(
                probe,
                abi.encodeWithSignature(
                    "make_pair_array(uint256,uint256,uint256,uint256)",
                    uint256(1),
                    uint256(1),
                    uint256(2),
                    uint256(3)
                )
            ),
            (Pair[2])
        );
        assertEq(pairs[0].left, 1);
        assertEq(pairs[0].right, 1);
        assertEq(pairs[1].left, 2);
        assertEq(pairs[1].right, 3);

        uint256[2][2] memory matrix = abi.decode(
            callBytes(
                probe,
                abi.encodeWithSignature(
                    "make_matrix(uint256,uint256,uint256,uint256)",
                    uint256(8),
                    uint256(13),
                    uint256(21),
                    uint256(34)
                )
            ),
            (uint256[2][2])
        );
        assertEq(matrix[0][0], 8);
        assertEq(matrix[0][1], 13);
        assertEq(matrix[1][0], 21);
        assertEq(matrix[1][1], 34);

        bytes32 rootA = packed(21, 22, 23, 24);
        bytes32 rootB = packed(34, 35, 36, 37);
        bytes memory hashPairResult =
            callBytes(probe, abi.encodeWithSignature("make_hash_pair(bytes32,bytes32)", rootA, rootB));
        (bytes32 leftHash, bytes32 rightHash) = abi.decode(hashPairResult, (bytes32, bytes32));
        assertEq(leftHash, rootA);
        assertEq(rightHash, rootB);

        bytes32[2] memory hashes = abi.decode(
            callBytes(probe, abi.encodeWithSignature("make_hash_array(bytes32,bytes32)", rootA, rootB)),
            (bytes32[2])
        );
        assertEq(hashes[0], rootA);
        assertEq(hashes[1], rootB);
    }

    function testIRAbiAggregateRejectsMalformedCalldata() public {
        address probe = address(uint160(0xA282));
        deployRuntime(hex"$probe_hex", probe);

        bytes4 sumArraySelector = bytes4(keccak256("sum_array(uint256[3])"));
        (bool shortArrayOk,) = probe.call(abi.encodePacked(sumArraySelector, uint256(1)));
        assertFalse(shortArrayOk);

        bytes4 sumMatrixSelector = bytes4(keccak256("sum_matrix(uint256[2][2])"));
        (bool shortMatrixOk,) = probe.call(abi.encodePacked(
            sumMatrixSelector,
            uint256(1),
            uint256(2),
            uint256(3)
        ));
        assertFalse(shortMatrixOk);

        bytes4 sumPairArraySelector = bytes4(keccak256("sum_pair_array((uint256,uint256)[2])"));
        (bool shortPairArrayOk,) = probe.call(abi.encodePacked(
            sumPairArraySelector,
            uint256(1),
            uint256(2),
            uint256(3)
        ));
        assertFalse(shortPairArrayOk);

        bytes4 sumSmallSelector = bytes4(keccak256("sum_small(uint32[2])"));
        (bool overflowU32Ok,) = probe.call(abi.encodePacked(
            sumSmallSelector,
            uint256(type(uint32).max) + 1,
            uint256(1)
        ));
        assertFalse(overflowU32Ok);

        bytes4 smallMatrixSelector = bytes4(keccak256("sum_small_matrix(uint32[2][2])"));
        (bool overflowU32MatrixOk,) = probe.call(abi.encodePacked(
            smallMatrixSelector,
            uint256(1),
            uint256(type(uint32).max) + 1,
            uint256(3),
            uint256(4)
        ));
        assertFalse(overflowU32MatrixOk);

        bytes4 pickHashSelector = bytes4(keccak256("pick_hash(bytes32[2])"));
        (bool shortHashArrayOk,) = probe.call(abi.encodePacked(
            pickHashSelector,
            packed(1, 2, 3, 4)
        ));
        assertFalse(shortHashArrayOk);

        bytes4 flagsSelector = bytes4(keccak256("and_flags((bool,bool))"));
        (bool invalidBoolOk,) = probe.call(abi.encodePacked(flagsSelector, uint256(2), uint256(1)));
        assertFalse(invalidBoolOk);

        (bool unknownOk,) = probe.call(hex"ffffffff");
        assertFalse(unknownOk);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "abi-aggregate-ir-smoke: ProofForge metadata $METADATA_FILE"

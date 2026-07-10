#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmPackedStorageProbe IR to EVM runtime
# bytecode and verify Solidity-style storage packing (small scalars sharing slots).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-packed-storage-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmPackedStorageProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmPackedStorageProbe.proof-forge-artifact.json}"

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
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-packed-storage --format bytecode \
  --yul-output "$OUT_DIR/EvmPackedStorageProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmPackedStorageProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmPackedStorageProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmPackedStorageProbe \
  --expect-source-kind portable-ir \
  --expect-capability storage.scalar \
  --expect-capability assertions.check \
  --expect-entrypoint packed_slot0_lifecycle:de0edef5 \
  --expect-entrypoint packed_slot1_lifecycle:c8fb82aa \
  --expect-entrypoint packed_slot2_lifecycle:329510c2 \
  --expect-entrypoint packed_slot3_lifecycle:e077025f \
  --expect-entrypoint packed_assign_op:d1a61f5e \
  --expect-entrypoint packed_assign_op_wraps:9641cb4f \
  --expect-entrypoint packed_nested_checked_overflow_reverts:48bedaed \
  --expect-entrypoint packed_mixed_overflow_reverts:a691f1b1 \
  --expect-entrypoint packed_nested_wrapping_preserves_neighbors:baa34f4a \
  --expect-entrypoint packed_checked_mul_zero_rhs_succeeds:ffb3ca34 \
  --expect-entrypoint packed_assign_op_overflow_reverts:ab0efcd6 \
  --expect-entrypoint packed_checked_write_overflow_reverts:2b19bf56 \
  "$METADATA_FILE"

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmPackedStorageProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRPackedStorageSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRPackedStorageSmokeTest {
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

    function slot(uint256 index) internal pure returns (bytes32) {
        return bytes32(index);
    }

    function readStorage(address target, uint256 slotIndex) internal view returns (uint256) {
        return uint256(vm.load(target, slot(slotIndex)));
    }

    function callU256(address probe, bytes memory payload) internal returns (uint256) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (uint256));
    }

    function callBool(address probe, bytes memory payload) internal returns (bool) {
        (bool ok, bytes memory result) = probe.call(payload);
        assertTrue(ok);
        return abi.decode(result, (bool));
    }

    // Storage layout (Solidity-style packing):
    // Slot 0: flag(bool,1B,off0) + counter(u8,1B,off1) + tag(u32,4B,off2) + value(u64,8B,off6) + big(u128,16B,off14) = 30B
    // Slot 1: owner(address,20B,off0) + active(bool,1B,off20) + total(u64,8B,off21) = 29B
    // Slot 2: reserve(u32,4B,off0) + spare(u8,1B,off4) + done(bool,1B,off5) = 6B

    function testIRPackedSlot0Lifecycle() public {
        address probe = address(uint160(0xB100));
        deployRuntime(hex"$probe_hex", probe);

        // packed_slot0_lifecycle writes flag=true, counter=200, tag=1000, value=99999
        // then updates counter=42 and verifies no aliasing
        assertEq(callU256(probe, abi.encodeWithSignature("packed_slot0_lifecycle()")), 99999);

        // Verify packed storage: slot 0 contains flag(1B@0) + counter(1B@1) + tag(4B@2) + value(8B@6) + big(16B@14)
        uint256 s0 = readStorage(probe, 0);
        // flag at byte 0: shift 0 bits
        assertEq(s0 & 0xFF, 1);
        // counter at byte 1: shift 8 bits
        assertEq((s0 >> 8) & 0xFF, 42);
        // tag at byte 2: shift 16 bits, 4 bytes
        assertEq((s0 >> 16) & 0xFFFFFFFF, 1000);
        // value at byte 6: shift 48 bits, 8 bytes
        assertEq((s0 >> 48) & 0xFFFFFFFFFFFFFFFF, 99999);
    }

    function testIRPackedSlot1Lifecycle() public {
        address probe = address(uint160(0xB101));
        deployRuntime(hex"$probe_hex", probe);

        // packed_slot1_lifecycle writes flag=true, counter=42, then big=u128_max, verifies no aliasing, updates big=1
        assertEq(callU256(probe, abi.encodeWithSignature("packed_slot1_lifecycle()")), 1);

        // Verify big (u128) at slot 0, byte 14: shift 112 bits
        uint256 s0 = readStorage(probe, 0);
        assertEq((s0 >> 112) & ((uint256(1) << 128) - 1), 1);
        // Verify flag and counter are still set (no aliasing from big write)
        assertEq(s0 & 0xFF, 1);
        assertEq((s0 >> 8) & 0xFF, 42);
    }

    function testIRPackedSlot2Lifecycle() public {
        address probe = address(uint160(0xB102));
        deployRuntime(hex"$probe_hex", probe);

        // packed_slot2_lifecycle writes owner and active, toggles active, verifies owner untouched
        assertTrue(callBool(probe, abi.encodeWithSignature("packed_slot2_lifecycle()")));

        // Verify active (bool) at slot 1, byte 20: shift 160 bits
        uint256 s1 = readStorage(probe, 1);
        assertEq(s1 & ((uint256(1) << 160) - 1), uint160(0x1111111122222222333333334444444455555555));
        assertEq((s1 >> 160) & 0xFF, 1);
    }

    function testIRPackedSlot3Lifecycle() public {
        address probe = address(uint160(0xB103));
        deployRuntime(hex"$probe_hex", probe);

        // packed_slot3_lifecycle writes total, reserve, spare, done; updates spare and verifies no aliasing
        assertEq(callU256(probe, abi.encodeWithSignature("packed_slot3_lifecycle()")), 500000);

        // Verify packed storage at slot 2: reserve(4B@0) + spare(1B@4) + done(1B@5)
        uint256 s2 = readStorage(probe, 2);
        // reserve at byte 0: shift 0 bits
        assertEq(s2 & 0xFFFFFFFF, 7777);
        // spare at byte 4: shift 32 bits
        assertEq((s2 >> 32) & 0xFF, 1);
        // done at byte 5: shift 40 bits
        assertEq((s2 >> 40) & 0xFF, 1);

        uint256 s1 = readStorage(probe, 1);
        assertEq((s1 >> 168) & 0xFFFFFFFFFFFFFFFF, 500000);
    }

    function testIRPackedAssignOp() public {
        address probe = address(uint160(0xB104));
        deployRuntime(hex"$probe_hex", probe);

        // packed_assign_op: counter=10, counter+=5→15, counter*=2→30; tag=42, tag+=8→50
        assertEq(callU256(probe, abi.encodeWithSignature("packed_assign_op()")), 30);

        // Verify counter at slot 0, byte 1: shift 8 bits
        uint256 s0 = readStorage(probe, 0);
        assertEq((s0 >> 8) & 0xFF, 30);
        // Verify tag at slot 0, byte 2: shift 16 bits
        assertEq((s0 >> 16) & 0xFFFFFFFF, 50);
    }

    function testIRPackedWrappingWriteDoesNotCorruptNeighbors() public {
        address probe = address(uint160(0xB105));
        deployRuntime(hex"$probe_hex", probe);

        assertFalse(callBool(probe, abi.encodeWithSignature("packed_assign_op_wraps()")));
        uint256 s0 = readStorage(probe, 0);
        assertEq(s0 & 0xFF, 0);
        assertEq((s0 >> 8) & 0xFF, 0);
        assertEq((s0 >> 16) & 0xFFFFFFFF, 0x12345678);
    }

    function testIRPackedNestedCheckedRejectsInnerOverflow() public {
        address probe = address(uint160(0xB10D));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(
            abi.encodeWithSignature("packed_nested_checked_overflow_reverts()")
        );
        assertFalse(ok);
        assertEq(readStorage(probe, 0), 0);
    }

    function testIRPackedMixedRejectsCheckedInnerOverflow() public {
        address probe = address(uint160(0xB10E));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(
            abi.encodeWithSignature("packed_mixed_overflow_reverts()")
        );
        assertFalse(ok);
        assertEq(readStorage(probe, 0), 0);
    }

    function testIRPackedNestedWrappingDoesNotCorruptNeighbors() public {
        address probe = address(uint160(0xB10F));
        deployRuntime(hex"$probe_hex", probe);

        assertFalse(callBool(
            probe,
            abi.encodeWithSignature("packed_nested_wrapping_preserves_neighbors()")
        ));
        uint256 s0 = readStorage(probe, 0);
        assertEq(s0 & 0xFF, 0);
        assertEq((s0 >> 8) & 0xFF, 255);
        assertEq((s0 >> 16) & 0xFFFFFFFF, 0x12345678);
    }

    function testIRPackedCheckedMulZeroRhsSucceeds() public {
        address probe = address(uint160(0xB110));
        deployRuntime(hex"$probe_hex", probe);

        assertFalse(callBool(
            probe,
            abi.encodeWithSignature("packed_checked_mul_zero_rhs_succeeds()")
        ));
        uint256 s0 = readStorage(probe, 0);
        assertEq(s0 & 0xFF, 0);
        assertEq((s0 >> 8) & 0xFF, 0);
        assertEq((s0 >> 16) & 0xFFFFFFFF, 0x12345678);
    }

    function testIRPackedCheckedAssignOpRejectsFieldOverflow() public {
        address probe = address(uint160(0xB106));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(abi.encodeWithSignature("packed_assign_op_overflow_reverts()"));
        assertFalse(ok);
        assertEq(readStorage(probe, 0), 0);
    }

    function testIRPackedCheckedWriteRejectsFieldOverflow() public {
        address probe = address(uint160(0xB107));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(abi.encodeWithSignature("packed_checked_write_overflow_reverts()"));
        assertFalse(ok);
        assertEq(readStorage(probe, 0), 0);
    }

    function testIRPackedCheckedLiteralWriteRejectsFieldOverflow() public {
        address probe = address(uint160(0xB109));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(
            abi.encodeWithSignature("packed_checked_literal_write_overflow_reverts()")
        );
        assertFalse(ok);
        assertEq(readStorage(probe, 0), 0);
    }

    function testIRPackedCheckedLocalWriteRejectsFieldOverflow() public {
        address probe = address(uint160(0xB10A));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(
            abi.encodeWithSignature("packed_checked_local_write_overflow_reverts()")
        );
        assertFalse(ok);
        assertEq(readStorage(probe, 0), 0);
    }

    function testIRPackedCanonicalU8CalldataWrites() public {
        address probe = address(uint160(0xB10B));
        deployRuntime(hex"$probe_hex", probe);

        assertEq(
            callU256(
                probe,
                abi.encodeWithSignature("packed_checked_write_param(uint8)", uint8(255))
            ),
            255
        );
        assertEq((readStorage(probe, 0) >> 8) & 0xFF, 255);
    }

    function testIRPackedRejectsNonCanonicalU8Calldata() public {
        address probe = address(uint160(0xB10C));
        deployRuntime(hex"$probe_hex", probe);

        bytes memory payload = abi.encodePacked(
            bytes4(0xc1244eee),
            bytes32(uint256(256))
        );
        (bool ok,) = probe.call(payload);
        assertFalse(ok);
        assertEq(readStorage(probe, 0), 0);
    }

    function testIRPackedStorageRejectsUnknownSelector() public {
        address probe = address(uint160(0xB108));
        deployRuntime(hex"$probe_hex", probe);

        (bool ok,) = probe.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "packed-storage-ir-smoke: ProofForge metadata $METADATA_FILE"

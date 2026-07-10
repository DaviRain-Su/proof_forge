#!/usr/bin/env bash
set -euo pipefail

# Compile the hand-written portable EvmErrorsProbe IR to EVM runtime
# bytecode and verify revert/revertWithError lowering.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${IR_EVM_OUT_DIR:-$ROOT/build/ir}"
FORGE_DIR="${IR_EVM_FORGE_DIR:-$ROOT/build/foundry-ir-errors-smoke}"
GOLDEN_FILE="${IR_EVM_GOLDEN:-$ROOT/Examples/Backend/Evm/EvmErrorsProbe.golden.yul}"
METADATA_FILE="${IR_EVM_METADATA:-$OUT_DIR/EvmErrorsProbe.proof-forge-artifact.json}"
SPEC_FILE="$OUT_DIR/EvmErrorsProbe.contract-spec.json"
CLIENT_FILE="$OUT_DIR/proof-forge-evm-abi.ts"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found" >&2
  exit 1
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "solc not found" >&2
  exit 1
fi

if ! command -v cast >/dev/null 2>&1; then
  echo "cast not found" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" emit --target evm --fixture evm-errors --format bytecode \
  --yul-output "$OUT_DIR/EvmErrorsProbe.yul" \
  --artifact-output "$METADATA_FILE" \
  -o "$OUT_DIR/EvmErrorsProbe.bin"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$OUT_DIR/EvmErrorsProbe.yul"
fi

python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
  --root "$ROOT" \
  --expect-fixture EvmErrorsProbe \
  --expect-source-kind portable-ir \
  --expect-capability assertions.check \
  --expect-entrypoint revertPlain:e6023528 \
  --expect-entrypoint revertWithMessage:185c38a4 \
  --expect-entrypoint revertWithErrorRef:b34aafd2 \
  --expect-entrypoint revertCustomError:c5159795 \
  --expect-entrypoint revertCustomErrorArgs:1cff28dd \
  --expect-entrypoint guardedRevert:0ff6ea62 \
  --expect-entrypoint conditionalRevert:194fd609 \
  --expect-entrypoint normalPath:a3f05111 \
  "$METADATA_FILE"

custom_error_selector="$(cast sig 'InsufficientBalance(uint64,uint64)')"
[[ "${custom_error_selector#0x}" == "9432a7ee" ]] || {
  echo "unexpected InsufficientBalance selector: $custom_error_selector" >&2
  exit 1
}

python3 - "$SPEC_FILE" "$CLIENT_FILE" <<'PY'
import json
import sys
from pathlib import Path

spec_path, client_path = map(Path, sys.argv[1:])
spec_text = spec_path.read_text()
spec = json.loads(spec_text)
entry = next(
    item for item in spec["errors"]
    if item.get("soliditySelector") == "9432a7ee"
)
assert entry["solidityArgTypes"] == ["uint64", "uint64"]
assert "solidityArgWords" not in spec_text

client = client_path.read_text()
assert "decodeProofForgeRevertDetails" in client
assert "AbiCoder.defaultAbiCoder().decode(argTypes" in client
assert "solidityArgWords" not in client
print("custom-error spec/client schema: ok")
PY

probe_hex="$(tr -d '\n' < "$OUT_DIR/EvmErrorsProbe.bin")"

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

cat > "$FORGE_DIR/test/ProofForgeIRErrorsSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract ProofForgeIRErrorsSmokeTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function assertTrue(bool value) internal pure { require(value, "assertTrue"); }
    function assertFalse(bool value) internal pure { require(!value, "assertFalse"); }

    address constant PROBE = address(uint160(0xE100));

    function setUp() public {
        deployRuntime(hex"${probe_hex}", PROBE);
    }

    function test_revertPlain_reverts() public {
        (bool ok,) = PROBE.call(hex"e6023528");
        assertFalse(ok);
    }

    function test_revertWithMessage_reverts() public {
        (bool ok,) = PROBE.call(hex"185c38a4");
        assertFalse(ok);
    }

    function test_revertWithErrorRef_reverts() public {
        (bool ok,) = PROBE.call(hex"b34aafd2");
        assertFalse(ok);
    }

    // PF-P2-02: Solidity custom-error selector surface (no-args CustomError).
    function test_revertCustomError_selector() public {
        (bool ok, bytes memory ret) = PROBE.call(hex"c5159795");
        assertFalse(ok);
        require(ret.length == 4, "custom error should be 4-byte selector");
        bytes4 sel;
        assembly {
            sel := mload(add(ret, 32))
        }
        require(sel == bytes4(0x09caebf3), "unexpected custom error selector");
    }

    // E1.1: custom error with ABI static args — InsufficientBalance(uint64,uint64).
    function test_revertCustomErrorArgs_selector_and_words() public {
        (bool ok, bytes memory ret) = PROBE.call(hex"1cff28dd");
        assertFalse(ok);
        // 4-byte selector + 2 × 32-byte ABI words
        require(ret.length == 68, "custom error args should be 4+64 bytes");
        bytes4 sel;
        uint64 available;
        uint64 required;
        assembly {
            sel := mload(add(ret, 32))
            // ABI words start at ret+4 (after selector); load as full words then cast
            available := mload(add(ret, 36))
            required := mload(add(ret, 68))
        }
        require(sel == bytes4(0x9432a7ee), "unexpected InsufficientBalance selector");
        require(available == 9007199254740993, "available arg word mismatch");
        require(required == 3, "required arg word mismatch");
    }

    function test_guardedRevert_false_reverts() public {
        (bool ok,) = PROBE.call(abi.encodeWithSignature("guardedRevert(bool)", false));
        assertFalse(ok);
    }

    function test_guardedRevert_true_succeeds() public {
        (bool ok,) = PROBE.call(abi.encodeWithSignature("guardedRevert(bool)", true));
        assertTrue(ok);
    }

    function test_conditionalRevert_true_reverts() public {
        (bool ok,) = PROBE.call(abi.encodeWithSignature("conditionalRevert(bool)", true));
        assertFalse(ok);
    }

    function test_conditionalRevert_false_succeeds() public {
        (bool ok,) = PROBE.call(abi.encodeWithSignature("conditionalRevert(bool)", false));
        assertTrue(ok);
    }

    function test_normalPath_returns_zero() public {
        (bool ok, bytes memory ret) = PROBE.call(hex"a3f05111");
        assertTrue(ok);
        require(ret.length == 32, "should return one word");
        uint64 result = abi.decode(ret, (uint64));
        assertEq(result, 0);
    }

    function assertEq(uint64 a, uint64 b) internal pure { require(a == b, "assertEq"); }

    function test_unknownSelector_reverts() public {
        (bool ok,) = PROBE.call(hex"ffffffff");
        assertFalse(ok);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

echo "errors-ir-smoke: ProofForge metadata $METADATA_FILE"

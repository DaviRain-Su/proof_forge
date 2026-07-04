#!/usr/bin/env bash
set -euo pipefail

# Compile the ProofForge EVM examples and run smoke tests with Foundry.
#
# This intentionally uses Forge's mature local EVM test runner, `vm.etch`
# for fast runtime checks, and one direct `create` initcode deployment check
# rather than a hand-rolled JSON-RPC harness.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${EVM_OUT_DIR:-$ROOT/build/evm}"
FORGE_DIR="${EVM_FORGE_DIR:-$ROOT/build/foundry-smoke}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "foundry-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "foundry-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

"$ROOT/scripts/evm/build-examples.sh"

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

cat > "$FORGE_DIR/test/ProofForgeSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function deal(address who, uint256 newBalance) external;
    function prank(address msgSender) external;
}

contract ProofForgeSmokeTest {
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

    function deployInitCode(bytes memory initCode) internal returns (address deployed) {
        assembly {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(deployed != address(0), "create failed");
    }

    function assertCounterLifecycle(address counter) internal {
        (bool initOk,) = counter.call(abi.encodeWithSignature("initialize()"));
        assertTrue(initOk);

        (bool ok0, bytes memory r0) = counter.call(abi.encodeWithSignature("get()"));
        assertTrue(ok0);
        assertEq(abi.decode(r0, (uint256)), 0);

        (bool ok1,) = counter.call(abi.encodeWithSignature("increment()"));
        assertTrue(ok1);

        (bool ok2, bytes memory r2) = counter.call(abi.encodeWithSignature("get()"));
        assertTrue(ok2);
        assertEq(abi.decode(r2, (uint256)), 1);

        (bool ok3,) = counter.call(abi.encodeWithSignature("increment()"));
        assertTrue(ok3);

        (bool ok4, bytes memory r4) = counter.call(abi.encodeWithSignature("get()"));
        assertTrue(ok4);
        assertEq(abi.decode(r4, (uint256)), 2);
    }

    function testCounterLifecycle() public {
        address counter = address(0xCAFE);
        deployRuntime(hex"$(cat "$OUT_DIR/Counter.bin")", counter);
        assertCounterLifecycle(counter);
    }

    function testCounterInitCodeDeploysRuntime() public {
        address counter = deployInitCode(hex"$(cat "$OUT_DIR/Counter.init.bin")");
        assertCounterLifecycle(counter);
    }

    function testArrayExample() public {
        address arrayExample = address(0xA7);
        deployRuntime(hex"$(cat "$OUT_DIR/ArrayExample.bin")", arrayExample);

        (bool ok0, bytes memory r0) = arrayExample.call(abi.encodeWithSignature("sizeOf3()"));
        assertTrue(ok0);
        assertEq(abi.decode(r0, (uint256)), 3);

        (bool ok1, bytes memory r1) = arrayExample.call(abi.encodeWithSignature("getElem()"));
        assertTrue(ok1);
        assertEq(abi.decode(r1, (uint256)), 20);

        (bool ok2, bytes memory r2) = arrayExample.call(abi.encodeWithSignature("sumOf3()"));
        assertTrue(ok2);
        assertEq(abi.decode(r2, (uint256)), 60);
    }

    function testSimpleTokenLifecycle() public {
        address token = address(0x70C);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        deployRuntime(hex"$(cat "$OUT_DIR/SimpleToken.bin")", token);

        vm.prank(alice);
        (bool ok0,) = token.call(abi.encodeWithSignature("init(uint256)", uint256(1_000_000)));
        assertTrue(ok0);

        (bool ok1, bytes memory r1) = token.call(abi.encodeWithSignature("getOwner()"));
        assertTrue(ok1);
        assertEq(abi.decode(r1, (uint256)), uint256(uint160(alice)));

        (bool ok2, bytes memory r2) = token.call(abi.encodeWithSignature("totalSupply()"));
        assertTrue(ok2);
        assertEq(abi.decode(r2, (uint256)), 1_000_000);

        vm.prank(alice);
        (bool ok3,) = token.call(abi.encodeWithSignature("transfer(uint256,uint256)", uint256(uint160(bob)), uint256(300_000)));
        assertTrue(ok3);

        (, bytes memory aliceBal) = token.call(abi.encodeWithSignature("balanceOf(uint256)", uint256(uint160(alice))));
        assertEq(abi.decode(aliceBal, (uint256)), 700_000);

        (, bytes memory bobBal) = token.call(abi.encodeWithSignature("balanceOf(uint256)", uint256(uint160(bob))));
        assertEq(abi.decode(bobBal, (uint256)), 300_000);

        vm.prank(bob);
        (bool reverted,) = token.call(abi.encodeWithSignature("transfer(uint256,uint256)", uint256(uint160(alice)), uint256(999_999)));
        assertFalse(reverted);
    }

    function testOwnableLifecycle() public {
        address ownable = address(0x0551);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        deployRuntime(hex"$(cat "$OUT_DIR/Ownable.bin")", ownable);

        vm.prank(alice);
        (bool initOk,) = ownable.call(abi.encodeWithSignature("init()"));
        assertTrue(initOk);

        (bool ownerOk, bytes memory ownerResult) = ownable.call(abi.encodeWithSignature("owner()"));
        assertTrue(ownerOk);
        assertEq(abi.decode(ownerResult, (uint256)), uint256(uint160(alice)));

        vm.prank(alice);
        (bool transferOk,) = ownable.call(abi.encodeWithSignature("transferOwnership(uint256)", uint256(uint160(bob))));
        assertTrue(transferOk);

        (bool ownerBobOk, bytes memory ownerBobResult) = ownable.call(abi.encodeWithSignature("owner()"));
        assertTrue(ownerBobOk);
        assertEq(abi.decode(ownerBobResult, (uint256)), uint256(uint160(bob)));

        vm.prank(bob);
        (bool renounceOk,) = ownable.call(abi.encodeWithSignature("renounceOwnership()"));
        assertTrue(renounceOk);

        (bool ownerZeroOk, bytes memory ownerZeroResult) = ownable.call(abi.encodeWithSignature("owner()"));
        assertTrue(ownerZeroOk);
        assertEq(abi.decode(ownerZeroResult, (uint256)), 0);
    }

    function testPausableLifecycle() public {
        address pausable = address(0xFA5E);
        deployRuntime(hex"$(cat "$OUT_DIR/Pausable.bin")", pausable);

        (bool paused0Ok, bytes memory paused0) = pausable.call(abi.encodeWithSignature("paused()"));
        assertTrue(paused0Ok);
        assertEq(abi.decode(paused0, (uint256)), 0);

        (bool pauseOk,) = pausable.call(abi.encodeWithSignature("pause()"));
        assertTrue(pauseOk);

        (bool paused1Ok, bytes memory paused1) = pausable.call(abi.encodeWithSignature("paused()"));
        assertTrue(paused1Ok);
        assertEq(abi.decode(paused1, (uint256)), 1);

        (bool unpauseOk,) = pausable.call(abi.encodeWithSignature("unpause()"));
        assertTrue(unpauseOk);

        (bool paused2Ok, bytes memory paused2) = pausable.call(abi.encodeWithSignature("paused()"));
        assertTrue(paused2Ok);
        assertEq(abi.decode(paused2, (uint256)), 0);
    }

    function testVerifiedVaultLifecycle() public {
        address vault = address(0x7A17);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        deployRuntime(hex"$(cat "$OUT_DIR/VerifiedVault.bin")", vault);

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        vm.prank(alice);
        (bool initOk,) = vault.call(abi.encodeWithSignature("init()"));
        assertTrue(initOk);

        (bool ownerOk, bytes memory ownerResult) = vault.call(abi.encodeWithSignature("getOwner()"));
        assertTrue(ownerOk);
        assertEq(abi.decode(ownerResult, (uint256)), uint256(uint160(alice)));

        vm.prank(alice);
        (bool depositAliceOk,) = vault.call{value: 1000}(abi.encodeWithSignature("deposit()"));
        assertTrue(depositAliceOk);

        vm.prank(bob);
        (bool depositBobOk,) = vault.call{value: 500}(abi.encodeWithSignature("deposit()"));
        assertTrue(depositBobOk);

        (bool reservesOk, bytes memory reservesResult) = vault.call(abi.encodeWithSignature("reserves()"));
        assertTrue(reservesOk);
        assertEq(abi.decode(reservesResult, (uint256)), 1500);

        (bool sharesOk, bytes memory sharesResult) = vault.call(abi.encodeWithSignature("totalShares()"));
        assertTrue(sharesOk);
        assertEq(abi.decode(sharesResult, (uint256)), 1500);

        vm.prank(alice);
        (bool withdrawOk,) = vault.call(abi.encodeWithSignature("withdraw(uint256)", uint256(300)));
        assertTrue(withdrawOk);

        (bool reservesAfterOk, bytes memory reservesAfterResult) = vault.call(abi.encodeWithSignature("reserves()"));
        assertTrue(reservesAfterOk);
        assertEq(abi.decode(reservesAfterResult, (uint256)), 1200);

        (bool aliceBalanceOk, bytes memory aliceBalanceResult) =
            vault.call(abi.encodeWithSignature("balanceOf(uint256)", uint256(uint160(alice))));
        assertTrue(aliceBalanceOk);
        assertEq(abi.decode(aliceBalanceResult, (uint256)), 700);

        vm.prank(alice);
        (bool overdraftOk,) = vault.call(abi.encodeWithSignature("withdraw(uint256)", uint256(999)));
        assertFalse(overdraftOk);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv

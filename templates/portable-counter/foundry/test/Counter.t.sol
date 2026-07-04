// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ProofForgeHex} from "../src/ProofForgeHex.sol";

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract CounterTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant RUNTIME_PATH = "../build/evm/Counter.bin";
    string internal constant INIT_PATH = "../build/evm/Counter.init.bin";

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "assertEq failed");
    }

    function assertTrue(bool value) internal pure {
        require(value, "assertTrue failed");
    }

    function deployRuntime(address target) internal {
        bytes memory runtime = ProofForgeHex.readHexFile(RUNTIME_PATH);
        vm.etch(target, runtime);
    }

    function deployInitCode() internal returns (address deployed) {
        bytes memory initCode = ProofForgeHex.readHexFile(INIT_PATH);
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
    }

    function testRuntimeBytecodeFromStablePath() public {
        address counter = address(0xC0FFEE);
        deployRuntime(counter);
        assertCounterLifecycle(counter);
    }

    function testInitCodeFromStablePath() public {
        address counter = deployInitCode();
        assertCounterLifecycle(counter);
    }
}

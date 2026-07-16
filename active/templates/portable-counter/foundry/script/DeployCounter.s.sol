// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ProofForgeHex} from "../src/ProofForgeHex.sol";

contract DeployCounter {
    string internal constant INIT_PATH = "../build/evm/Counter.init.bin";

    function run() external returns (address deployed) {
        bytes memory initCode = ProofForgeHex.readHexFile(INIT_PATH);
        assembly {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(deployed != address(0), "create failed");
    }
}

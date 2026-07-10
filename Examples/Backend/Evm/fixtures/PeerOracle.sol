// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// PF-P2-03 peer oracle: remote_call(a,b) returns a+b (42+7 → 49).
/// Matches Foundry PeerOracle in scripts/evm/foundry-smoke.sh.
contract PeerOracle {
    function remote_call(uint256 a, uint256 b) external pure returns (uint256) {
        return a + b;
    }
}

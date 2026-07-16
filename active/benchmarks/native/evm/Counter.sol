// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title Native Counter — hand-written Solidity reference for benchmark comparison.
/// @notice Mirrors ProofForge Counter: initialize() → increment() → get().
///         No constructor logic; initialize sets count to 0 (matching PF lifecycle).
contract Counter {
    uint64 public count;

    function initialize() external {
        count = 0;
    }

    function increment() external {
        count = count + 1;
    }

    function get() external view returns (uint64) {
        return count;
    }
}

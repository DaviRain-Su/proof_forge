// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title Native Pausable - independent Solidity reference for CMP-3e.
/// @notice The policy is intentionally unauthenticated; ownership is a separate concern.
contract Pausable {
    uint64 public paused;

    error AlreadyPaused();
    error NotPaused();

    function pause() external {
        if (paused != 0) revert AlreadyPaused();
        paused = 1;
    }

    function unpause() external {
        if (paused == 0) revert NotPaused();
        paused = 0;
    }
}

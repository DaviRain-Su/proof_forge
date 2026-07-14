// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title Native ReentrancyGuard - independent Solidity reference for CMP-3f.
/// @notice This models only the portable lock-state policy, not target call-stack theory.
contract ReentrancyGuard {
    uint64 public locked;

    error ReentrantCall();
    error LockNotHeld();

    function acquire() external {
        if (locked != 0) revert ReentrantCall();
        locked = 1;
    }

    function release() external {
        if (locked == 0) revert LockNotHeld();
        locked = 0;
    }
}

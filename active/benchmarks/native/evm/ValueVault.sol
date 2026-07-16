// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title Native ValueVault — hand-written Solidity reference for bm-value-vault.
/// @notice Mirrors the portable lifecycle used by the B1 matrix:
///         initialize(initial) → get_balance → deposit(amount) → get_balance.
contract ValueVault {
    uint64 public balance;
    uint64 public released;
    uint64 public fees;
    uint64 public last_value;
    uint64 public last_checkpoint;
    uint64 public operations;

    function initialize(uint64 initial) external {
        balance = initial;
        released = 0;
        fees = 0;
        last_value = initial;
        last_checkpoint = uint64(block.number);
        operations = 1;
    }

    function deposit(uint64 amount) external {
        balance = balance + amount;
        last_value = amount;
        operations = operations + 1;
    }

    function get_balance() external view returns (uint64) {
        return balance;
    }
}

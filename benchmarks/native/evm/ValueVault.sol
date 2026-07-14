// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title Independent native ValueVault reference.
/// @notice Implements the portable CMP-3 lifecycle without importing generated
///         ProofForge artifacts or compiler code.
contract ValueVault {
    uint64 private balance;
    uint64 private released;
    uint64 private fees;
    uint64 private last_value;
    uint64 private last_checkpoint;
    uint64 private operations;

    event VaultInitialized(uint64 initial, uint64 checkpoint);
    event ValueDeposited(uint64 amount, uint64 balance, uint64 operations);
    event ValueCharged(uint64 gross, uint64 fee, uint64 net, uint64 balance);
    event ValueReleased(uint64 amount, uint64 balance, uint64 released);
    event ValueSnapshot(uint64 balance, uint64 released, uint64 fees, uint64 checkpoint);

    function initialize(uint64 initial) external {
        balance = initial;
        released = 0;
        fees = 0;
        last_value = initial;
        last_checkpoint = uint64(block.number);
        operations = 1;
        emit VaultInitialized(initial, last_checkpoint);
    }

    function deposit(uint64 amount) external {
        balance = balance + amount;
        last_value = amount;
        operations = operations + 1;
        emit ValueDeposited(amount, balance, operations);
    }

    function charge_fee(uint64 gross, uint64 fee_bps) external {
        uint64 fee = (gross * fee_bps) / 10_000;
        uint64 net = gross - fee;
        balance = balance + net;
        fees = fees + fee;
        last_value = net;
        operations = operations + 1;
        emit ValueCharged(gross, fee, net, balance);
    }

    function release(uint64 amount) external {
        balance = balance - amount;
        released = released + amount;
        last_value = amount;
        operations = operations + 1;
        emit ValueReleased(amount, balance, released);
    }

    function snapshot() external returns (uint64) {
        last_checkpoint = uint64(block.number);
        emit ValueSnapshot(balance, released, fees, last_checkpoint);
        return balance;
    }

    function get_balance() external view returns (uint64) {
        return balance;
    }

    function get_net_value() external view returns (uint64) {
        return balance - fees;
    }
}

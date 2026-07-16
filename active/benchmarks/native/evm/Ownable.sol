// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title Native Ownable — hand-written Solidity reference for bm-ownable.
/// @notice Mirrors portable Ownable: init → owner → transferOwnership → renounceOwnership.
contract Ownable {
    address public owner;

    error AlreadyInitialized();
    error NotOwner();
    error ZeroAddress();

    function init() external {
        if (owner != address(0)) revert AlreadyInitialized();
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert NotOwner();
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    function renounceOwnership() external {
        if (msg.sender != owner) revert NotOwner();
        owner = address(0);
    }
}

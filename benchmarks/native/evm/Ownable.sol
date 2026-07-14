// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title Native Ownable — hand-written Solidity reference for bm-ownable.
/// @notice Mirrors portable Ownable: init → owner → transferOwnership → renounceOwnership.
contract Ownable {
    address public owner;
    bool private initialized;

    error AlreadyInitialized();
    error NotOwner();
    error ZeroAddress();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function init() external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        emit OwnershipTransferred(address(0), msg.sender);
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert NotOwner();
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function renounceOwnership() external {
        if (msg.sender != owner) revert NotOwner();
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }
}

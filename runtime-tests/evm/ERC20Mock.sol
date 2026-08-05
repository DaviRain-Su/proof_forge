// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title ERC20Mock — minimal ERC-20 mock for ADR-0030 E1a runtime gate.
/// @notice Compiled with locked solc 0.8.34. Supports mint/balanceOf/transfer
///         with both standard (bool return) and USDT-style (no return) paths.
///         Used by the main-agent Anvil differential to verify TokenJar's
///         `pf.assets.token.transfer` lowering (dynamic callee, return-value
///         predicate, failure propagation).
contract ERC20Mock {
    string public constant name = "ERC20Mock";
    string public constant symbol = "MCK";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    // Toggle for USDT-style no-return behavior (returndatasize == 0).
    bool public noReturnMode;

    // Toggle for returning false instead of reverting on insufficient balance.
    bool public returnFalseMode;

    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor() {
        noReturnMode = false;
        returnFalseMode = false;
    }

    /// @notice Set USDT-style no-return mode (transfer returns nothing).
    function setNoReturnMode(bool enabled) external {
        noReturnMode = enabled;
    }

    /// @notice Set false-return mode (transfer returns false on failure
    ///         instead of reverting).
    function setReturnFalseMode(bool enabled) external {
        returnFalseMode = enabled;
    }

    /// @notice Mint tokens to an account.
    function mint(address to, uint256 amount) external {
        require(to != address(0), "ERC20: mint to zero address");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice Standard ERC-20 transfer with configurable return behavior.
    /// @dev Standard path: returns true on success.
    ///      USDT path (noReturnMode): returns nothing on success.
    ///      False-return path (returnFalseMode): returns false on insufficient
    ///      balance (instead of reverting).
    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "ERC20: transfer to zero address");
        uint256 fromBal = balanceOf[msg.sender];
        if (fromBal < amount) {
            if (returnFalseMode) {
                return false;
            }
            revert("ERC20: insufficient balance");
        }
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        if (noReturnMode) {
            // USDT-style: return nothing (returndatasize == 0).
            assembly {
                return(0, 0)
            }
        }
        return true;
    }
}
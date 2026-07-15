// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title Native StatusMessage - independent Solidity reference for CMP-3h.
contract StatusMessage {
    uint64 public version;
    mapping(uint64 => uint64) private records;

    event StatusSet(uint64 indexed account, uint64 status);

    function init() external {
        version = 1;
    }

    function set_status(uint64 status) external {
        uint64 who = uint64(uint160(msg.sender));
        records[who] = status;
        emit StatusSet(who, status);
    }

    function get_status(uint64 who) external view returns (uint64) {
        return records[who];
    }
}

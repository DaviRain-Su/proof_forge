// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title Native ArrayExample - independent Solidity reference for CMP-3g.
contract ArrayExample {
    error ArrayIndexOutOfBounds();

    function sizeOf3() external pure returns (uint64) {
        return 3;
    }

    function getElem() external pure returns (uint64) {
        uint64[3] memory xs = [uint64(10), uint64(20), uint64(30)];
        return xs[1];
    }

    function sumOf3() external pure returns (uint64) {
        uint64[3] memory xs = [uint64(10), uint64(20), uint64(30)];
        return xs[0] + xs[1] + xs[2];
    }

    function outOfBounds() external pure returns (uint64) {
        uint64[3] memory xs = [uint64(10), uint64(20), uint64(30)];
        uint256 index = 3;
        if (index >= xs.length) revert ArrayIndexOutOfBounds();
        return xs[index];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function projectRoot() external view returns (string memory);
    function readFile(string calldata path) external view returns (string memory);
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

library ProofForgeHex {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function readHexFile(string memory relativePath) internal view returns (bytes memory runtime) {
        string memory path = string.concat(VM.projectRoot(), "/", relativePath);
        bytes memory raw = trimAscii(bytes(VM.readFile(path)));
        require(raw.length > 0, "empty hex artifact");
        require(raw.length % 2 == 0, "invalid hex artifact length");
        runtime = new bytes(raw.length / 2);
        for (uint256 i = 0; i < raw.length / 2; ++i) {
            runtime[i] = bytes1(fromHexChar(uint8(raw[2 * i])) * 16 + fromHexChar(uint8(raw[2 * i + 1])));
        }
    }

    function trimAscii(bytes memory input) private pure returns (bytes memory) {
        uint256 start = 0;
        uint256 end = input.length;
        while (start < end && isAsciiSpace(uint8(input[start]))) {
            start++;
        }
        while (end > start && isAsciiSpace(uint8(input[end - 1]))) {
            end--;
        }
        bytes memory trimmed = new bytes(end - start);
        for (uint256 i = start; i < end; ++i) {
            trimmed[i - start] = input[i];
        }
        return trimmed;
    }

    function isAsciiSpace(uint8 charCode) private pure returns (bool) {
        return charCode == uint8(bytes1(" ")) || charCode == uint8(bytes1("\t"))
            || charCode == uint8(bytes1("\n")) || charCode == uint8(bytes1("\r"));
    }

    function fromHexChar(uint8 charCode) private pure returns (uint8) {
        if (charCode >= uint8(bytes1("0")) && charCode <= uint8(bytes1("9"))) {
            return charCode - uint8(bytes1("0"));
        }
        if (charCode >= uint8(bytes1("a")) && charCode <= uint8(bytes1("f"))) {
            return 10 + charCode - uint8(bytes1("a"));
        }
        if (charCode >= uint8(bytes1("A")) && charCode <= uint8(bytes1("F"))) {
            return 10 + charCode - uint8(bytes1("A"));
        }
        revert("invalid hex digit");
    }
}

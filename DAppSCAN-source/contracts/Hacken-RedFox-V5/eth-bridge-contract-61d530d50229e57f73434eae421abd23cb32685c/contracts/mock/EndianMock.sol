pragma solidity ^0.6.0;

import "../libraries/Endian.sol";

contract EndianMock {
    function reverse64(uint64 input) public pure returns (uint64 v) {
        return Endian.reverse64(input);
    }
    function reverse32(uint32 input) public pure returns (uint32 v) {
        return Endian.reverse32(input);
    }
    function reverse16(uint16 input) public pure returns (uint16 v) {
        return Endian.reverse16(input);
    }
}
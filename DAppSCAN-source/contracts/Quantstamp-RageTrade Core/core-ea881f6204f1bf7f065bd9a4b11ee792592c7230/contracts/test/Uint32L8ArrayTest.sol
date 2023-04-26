// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';

contract Uint32L8ArrayTest {
    using Uint32L8ArrayLib for uint32[8];

    uint32[8] array;

    // EXPOSING LIBRARY METHODS

    function include(uint32 element) external {
        array.include(element);
    }

    function exclude(uint32 element) external {
        array.exclude(element);
    }

    // DEBUG METHODS

    function getter(uint8 index) public view returns (uint32) {
        return array[index];
    }

    function getterAll() public view returns (uint32[8] memory) {
        return array;
    }

    function length() public view returns (uint8 len) {
        for (uint256 i = 0; i < 8; i++) {
            if (array[i] != 0) {
                len++;
            }
            if (array[i] == 0) {
                break;
            }
        }
    }

    function setter(uint8 index, uint32 element) public {
        array[index] = element;
    }

    function exists(uint32 element) public view returns (bool) {
        return array.exists(element);
    }

    function numberOfNonZeroElements() public view returns (uint256) {
        return array.numberOfNonZeroElements();
    }
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Uint48L5ArrayLib } from '../libraries/Uint48L5Array.sol';

contract Uint48L5ArrayTest {
    using Uint48L5ArrayLib for uint48[5];

    uint48[5] array;

    // EXPOSING LIBRARY METHODS

    function include(uint48 element) external {
        array.include(element);
    }

    function exclude(uint48 element) external {
        array.exclude(element);
    }

    // DEBUG METHODS

    function getter(uint8 index) public view returns (uint48) {
        return array[index];
    }

    function getterAll() public view returns (uint48[5] memory) {
        return array;
    }

    function length() public view returns (uint8 len) {
        for (uint256 i = 0; i < 5; i++) {
            if (array[i] != 0) {
                len++;
            }
            if (array[i] == 0) {
                break;
            }
        }
    }

    function setter(uint8 index, uint48 element) public {
        array[index] = element;
    }

    function exists(uint48 element) public view returns (bool) {
        return array.exists(element);
    }

    function numberOfNonZeroElements() public view returns (uint256) {
        return array.numberOfNonZeroElements();
    }
}

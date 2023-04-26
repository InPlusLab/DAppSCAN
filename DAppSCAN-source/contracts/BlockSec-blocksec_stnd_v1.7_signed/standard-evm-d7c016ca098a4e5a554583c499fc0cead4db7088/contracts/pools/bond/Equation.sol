// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

contract Equation {
    function fx(uint256 x) external pure returns (uint256 bondPrice) {
        if(x < 1e8) {
            return 1e24/x*x;
        } else {
            return sqrt(x);
        }
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
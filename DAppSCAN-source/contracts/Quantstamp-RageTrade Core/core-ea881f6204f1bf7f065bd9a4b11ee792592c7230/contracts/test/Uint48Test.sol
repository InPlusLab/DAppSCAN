// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Uint48Lib } from '../libraries/Uint48.sol';

contract Uint48Test {
    function assertConcat(int24 val1, int24 val2) external pure returns (uint48 concatenated) {
        concatenated = concat(val1, val2);
        (int24 val1_, int24 val2_) = Uint48Lib.unconcat(concatenated);
        assert(val1_ == val1);
        assert(val2_ == val2);
    }

    function concat(int24 val1, int24 val2) public pure returns (uint48 concatenated) {
        concatenated = Uint48Lib.concat(val1, val2);
    }
}

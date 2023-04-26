// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import {
    LimaToken
} from "./LimaToken.sol";

contract LimaTokenV2 is LimaToken {

    function newFunction() public pure returns(uint256) {
        return 1;
    }
}

// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../oz_modified/ICHIERC20.sol";

contract USDToken is ICHIERC20 {

    constructor() {
        initERC20("USD Token", "USDTest");
        _mint(msg.sender, 1000 * 10 ** 18);
    }
}

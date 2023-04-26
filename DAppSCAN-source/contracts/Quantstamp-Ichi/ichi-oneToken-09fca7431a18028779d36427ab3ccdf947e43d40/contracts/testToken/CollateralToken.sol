// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../oz_modified/ICHIERC20.sol";

contract CollateralToken is ICHIERC20 {

    constructor() {
        initERC20("Collateral Token", "CTTest");
        _mint(msg.sender, 1000 * 10 ** 18);
    }

}

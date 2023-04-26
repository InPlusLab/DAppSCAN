// SPDX-License-Identifier: https://github.com/lendroidproject/protocol.2.0/blob/master/LICENSE.md
pragma solidity 0.7.4;


import "./MockERC20.sol";


contract MockLSTWETHUNIV2 is MockERC20 {

    constructor () MockERC20("LST ETH Uniswap V2 Pool Token", "LST_WETH_UNI_V2") {}
}

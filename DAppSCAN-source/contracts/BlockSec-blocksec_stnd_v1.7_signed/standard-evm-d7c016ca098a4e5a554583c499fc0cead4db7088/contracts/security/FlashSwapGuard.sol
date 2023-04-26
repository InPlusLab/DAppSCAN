// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "../uniswapv2/interfaces/IUniswapV2Pair.sol";

/// UniswapV2Oracle guard for flash swap
contract FlashSwapGuard {
    modifier noFlashSwap(address pair) {
        require(IUniswapV2Pair(pair).lastUpdate() != block.number, "FlashSwapGuard: FlashSwap");
        _;
    }
}

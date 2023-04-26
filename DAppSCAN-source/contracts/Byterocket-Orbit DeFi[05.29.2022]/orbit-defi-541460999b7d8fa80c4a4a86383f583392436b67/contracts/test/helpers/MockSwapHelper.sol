// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '../../helpers/SwapHelper.sol';

contract MockSwapHelper {
    ///@notice call to getRatioFromRange of SwapHelper library
    ///@param tickPool tick of the pool
    ///@param tickLower lower tick of position
    ///@param tickUpper upper tick of position
    ///@return uint256 ratioE18 = amount1/amount0 * 1e18
    function getRatioFromRange(
        int24 tickPool,
        int24 tickLower,
        int24 tickUpper
    ) public pure returns (uint256) {
        return SwapHelper.getRatioFromRange(tickPool, tickLower, tickUpper);
    }

    ///@notice call to calcAmountToSwap of SwapHelper library
    ///@param tickPool tick of the pool
    ///@param tickLower lower tick of position
    ///@param tickUpper upper tick of position
    ///@param amount0In amount of token0 available
    ///@param amount1In amount of token1 available
    ///@return uint256 amountToSwap = amount of token to be swapped
    ///@return bool amount0In = true if token0 is swapped for token1, false if token1 is swapped for token1
    function calcAmountToSwap(
        int24 tickPool,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0In,
        uint256 amount1In
    ) public pure returns (uint256, bool) {
        return SwapHelper.calcAmountToSwap(tickPool, tickLower, tickUpper, amount0In, amount1In);
    }
}

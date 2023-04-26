// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface ISwapToPositionRatio {
    ///@notice input the decoder expects
    ///@param token0Address address of first token of the pool
    ///@param token1Address address of second token of the pool
    ///@param fee fee tier of the pool
    ///@param amount0In actual token0 amount to be deposited
    ///@param amount1In actual token1 amount to be deposited
    ///@param tickLower lower tick of position
    ///@param tickUpper upper tick of position
    struct SwapToPositionInput {
        address token0Address;
        address token1Address;
        uint24 fee;
        uint256 amount0In;
        uint256 amount1In;
        int24 tickLower;
        int24 tickUpper;
    }

    function swapToPositionRatio(SwapToPositionInput memory inputs)
        external
        returns (uint256 amount0Out, uint256 amount1Out);
}

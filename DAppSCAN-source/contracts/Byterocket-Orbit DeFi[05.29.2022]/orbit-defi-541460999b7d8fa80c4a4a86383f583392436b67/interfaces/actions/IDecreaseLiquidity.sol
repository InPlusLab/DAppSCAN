// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface IDecreaseLiquidity {
    function decreaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    )
        external
        returns (
            uint128 liquidityToDecrease,
            uint256 amount0,
            uint256 amount1
        );
}

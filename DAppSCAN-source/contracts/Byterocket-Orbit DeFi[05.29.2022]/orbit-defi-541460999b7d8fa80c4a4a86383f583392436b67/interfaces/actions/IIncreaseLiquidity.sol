// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface IIncreaseLiquidity {
    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external;
}

// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

interface ICrossroadCallee
{
    function crossroadCall(
        address sender,
        uint256 amountIn,
        uint256 amountOut,
        uint256 amountReward,
        bytes calldata callbackData
        ) external;
}

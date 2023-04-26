// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

interface ISwapCallee {
    function SwapCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}
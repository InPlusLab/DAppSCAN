// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '../Arth/IIncentive.sol';

/**
 * @title  A Uniswap Router for tokens involving ARTH.
 * @author Original code written by FEI Protocol. Code modified by MahaDAO.
 */
interface IUniswapSwapRouter {
    function buyARTHForETH(
        uint256 minReward,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    function buyARTHForERC20(
        address token,
        uint256 amountIn,
        uint256 minReward,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function sellARTHForETH(
        uint256 maxPenalty,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function sellARTHForERC20(
        address token,
        uint256 maxPenalty,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}

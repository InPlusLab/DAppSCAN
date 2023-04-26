// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

interface IUniswapV2Migrator {
    function migrate(
        address token,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external;
}

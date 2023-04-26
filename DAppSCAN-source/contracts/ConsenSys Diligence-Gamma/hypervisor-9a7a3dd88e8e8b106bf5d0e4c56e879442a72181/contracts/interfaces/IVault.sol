// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.7.6;

interface IVault {
    function deposit(
        uint256,
        uint256,
        address,
        address
    ) external returns (uint256);

    function withdraw(
        uint256,
        address,
        address,
        uint256,
        uint256
    ) external returns (uint256, uint256);

    function rebalance(
        int24 _baseLower,
        int24 _baseUpper,
        int24 _limitLower,
        int24 _limitUpper,
        address feeRecipient,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external;

    function getTotalAmounts() external view returns (uint256, uint256);

    event Deposit(
        address indexed sender,
        address indexed to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    event Withdraw(
        address indexed sender,
        address indexed to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    event Rebalance(
        int24 tick,
        uint256 totalAmount0,
        uint256 totalAmount1,
        uint256 feeAmount0,
        uint256 feeAmount1,
        uint256 totalSupply
    );
}

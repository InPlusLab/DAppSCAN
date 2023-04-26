// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

interface ILiquidityProtectionService {
    event Blocked(address pool, address trader, string trap);

    function getLiquidityPool(address tokenA, address tokenB)
    external view returns(address);

    function LiquidityAmountTrap_preValidateTransfer(
        address from, address to, uint amount,
        address counterToken, uint8 trapBlocks, uint128 trapAmount)
    external returns(bool passed);

    function FirstBlockTrap_preValidateTransfer(
        address from, address to, uint amount, address counterToken)
    external returns(bool passed);

    function LiquidityPercentTrap_preValidateTransfer(
        address from, address to, uint amount,
        address counterToken, uint8 trapBlocks, uint64 trapPercent)
    external returns(bool passed);

    function LiquidityActivityTrap_preValidateTransfer(
        address from, address to, uint amount,
        address counterToken, uint8 trapBlocks, uint8 trapCount)
    external returns(bool passed);

    function isBlocked(address counterToken, address who)
    external view returns(bool);
}

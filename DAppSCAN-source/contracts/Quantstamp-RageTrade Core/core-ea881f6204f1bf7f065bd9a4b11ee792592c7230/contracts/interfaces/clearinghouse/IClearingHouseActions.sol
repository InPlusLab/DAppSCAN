// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';

interface IClearingHouseActions is IClearingHouseStructures {
    /// @notice creates a new account and adds it to the accounts map
    /// @return newAccountId - serial number of the new account created
    function createAccount() external returns (uint256 newAccountId);

    /// @notice deposits 'amount' of token associated with 'poolId'
    /// @param accountId account id
    /// @param collateralId truncated address of token to deposit
    /// @param amount amount of token to deposit
    function updateMargin(
        uint256 accountId,
        uint32 collateralId,
        int256 amount
    ) external;

    /// @notice creates a new account and deposits 'amount' of token associated with 'poolId'
    /// @param collateralId truncated address of collateral token to deposit
    /// @param amount amount of token to deposit
    /// @return newAccountId - serial number of the new account created
    function createAccountAndAddMargin(uint32 collateralId, uint256 amount) external returns (uint256 newAccountId);

    /// @notice withdraws 'amount' of settlement token from the profit made
    /// @param accountId account id
    /// @param amount amount of token to withdraw
    function updateProfit(uint256 accountId, int256 amount) external;

    /// @notice settles the profit/loss made with the settlement token collateral deposits
    /// @param accountId account id
    function settleProfit(uint256 accountId) external;

    /// @notice swaps token associated with 'poolId' by 'amount' (Long if amount>0 else Short)
    /// @param accountId account id
    /// @param poolId truncated address of token to withdraw
    /// @param swapParams swap parameters
    function swapToken(
        uint256 accountId,
        uint32 poolId,
        SwapParams memory swapParams
    ) external returns (int256 vTokenAmountOut, int256 vQuoteAmountOut);

    /// @notice updates range order of token associated with 'poolId' by 'liquidityDelta' (Adds if amount>0 else Removes)
    /// @notice also can be used to update limitOrderType
    /// @param accountId account id
    /// @param poolId truncated address of token to withdraw
    /// @param liquidityChangeParams liquidity change parameters
    function updateRangeOrder(
        uint256 accountId,
        uint32 poolId,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external returns (int256 vTokenAmountOut, int256 vQuoteAmountOut);

    /// @notice keeper call to remove a limit order
    /// @dev checks the position of current price relative to limit order and checks limitOrderType
    /// @param accountId account id
    /// @param poolId truncated address of token to withdraw
    /// @param tickLower liquidity change parameters
    /// @param tickUpper liquidity change parameters
    function removeLimitOrder(
        uint256 accountId,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper
    ) external;

    /// @notice keeper call for liquidation of range position
    /// @dev removes all the active range positions and gives liquidator a percent of notional amount closed + fixedFee
    /// @param accountId account id
    function liquidateLiquidityPositions(uint256 accountId) external;

    /// @notice keeper call for liquidation of token position
    /// @dev transfers the fraction of token position at a discount to current price to liquidators account and gives liquidator some fixedFee
    /// @param targetAccountId account id
    /// @param poolId truncated address of token to withdraw
    /// @return keeperFee - amount of fees transferred to keeper
    function liquidateTokenPosition(uint256 targetAccountId, uint32 poolId) external returns (int256 keeperFee);
}

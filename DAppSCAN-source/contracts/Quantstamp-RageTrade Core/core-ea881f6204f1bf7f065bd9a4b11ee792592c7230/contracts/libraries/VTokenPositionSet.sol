// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';

import { Account } from './Account.sol';
import { AddressHelper } from './AddressHelper.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { Protocol } from './Protocol.sol';
import { PriceMath } from './PriceMath.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { SignedMath } from './SignedMath.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

/// @title VToken position set functions
library VTokenPositionSet {
    using AddressHelper for address;
    using FullMath for uint256;
    using PriceMath for uint256;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using SignedMath for int256;
    using Uint32L8ArrayLib for uint32[8];

    using LiquidityPositionSet for LiquidityPosition.Set;
    using Protocol for Protocol.Info;
    using VTokenPosition for VTokenPosition.Info;
    using VTokenPositionSet for VTokenPosition.Set;

    error VPS_IncorrectUpdate();
    error VPS_DeactivationFailed(uint32 poolId);
    error VPS_TokenInactive(uint32 poolId);

    /**
     *  Internal methods
     */

    /// @notice activates token with address 'vToken' if not already active
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    function activate(VTokenPosition.Set storage set, uint32 poolId) internal {
        set.active.include(poolId);
    }

    /// @notice deactivates token with address 'vToken'
    /// @dev ensures that the balance is 0 and there are not range positions active otherwise throws an error
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    function deactivate(VTokenPosition.Set storage set, uint32 poolId) internal {
        if (set.positions[poolId].balance != 0 || !set.positions[poolId].liquidityPositions.isEmpty()) {
            revert VPS_DeactivationFailed(poolId);
        }

        set.active.exclude(poolId);
    }

    /// @notice updates token balance, net trader position and vQuote balance
    /// @dev realizes funding payment to vQuote balance
    /// @dev activates the token if not already active
    /// @dev deactivates the token if the balance = 0 and there are no range positions active
    /// @dev IMP: ensure that the global states are updated using zeroSwap or directly through some interaction with pool wrapper
    /// @param set VTokenPositionSet
    /// @param balanceAdjustments platform constants
    /// @param poolId id of the rage trade pool
    /// @param accountId account identifier, used for emitting event
    /// @param protocol platform constants
    function update(
        VTokenPosition.Set storage set,
        uint256 accountId,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal {
        set.realizeFundingPayment(accountId, poolId, protocol);
        set.active.include(poolId);

        VTokenPosition.Info storage _VTokenPosition = set.positions[poolId];
        _VTokenPosition.balance += balanceAdjustments.vTokenIncrease;
        _VTokenPosition.netTraderPosition += balanceAdjustments.traderPositionIncrease;

        set.vQuoteBalance += balanceAdjustments.vQuoteIncrease;

        if (_VTokenPosition.balance == 0 && _VTokenPosition.liquidityPositions.active[0] == 0) {
            set.deactivate(poolId);
        }
    }

    /// @notice realizes funding payment to vQuote balance
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param accountId account identifier, used for emitting event
    /// @param protocol platform constants
    function realizeFundingPayment(
        VTokenPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal {
        set.realizeFundingPayment(accountId, poolId, protocol.pools[poolId].vPoolWrapper);
    }

    /// @notice realizes funding payment to vQuote balance
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param accountId account identifier, used for emitting event
    /// @param wrapper VPoolWrapper to override the set wrapper
    function realizeFundingPayment(
        VTokenPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        IVPoolWrapper wrapper
    ) internal {
        VTokenPosition.Info storage position = set.positions[poolId];
        int256 extrapolatedSumAX128 = wrapper.getSumAX128();

        int256 fundingPayment = position.unrealizedFundingPayment(wrapper);
        set.vQuoteBalance += fundingPayment;

        position.sumALastX128 = extrapolatedSumAX128;

        emit Account.TokenPositionFundingPaymentRealized(accountId, poolId, fundingPayment, extrapolatedSumAX128);
    }

    /// @notice swaps tokens (Long and Short) with input in token amount / vQuote amount
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param swapParams parameters for swap
    /// @param protocol platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vQuoteAmountOut - vQuote amount coming out of pool
    function swapToken(
        VTokenPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        IClearingHouseStructures.SwapParams memory swapParams,
        Protocol.Info storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        return set.swapToken(accountId, poolId, swapParams, protocol.vPoolWrapper(poolId), protocol);
    }

    /// @notice swaps tokens (Long and Short) with input in token amount
    /// @dev activates inactive vToe
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param vTokenAmount amount of the token
    /// @param protocol platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vQuoteAmountOut - vQuote amount coming out of pool
    function swapTokenAmount(
        VTokenPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        int256 vTokenAmount,
        Protocol.Info storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        return
            set.swapToken(
                accountId,
                poolId,
                /// @dev 0 means no price limit and false means amount mentioned is token amount
                IClearingHouseStructures.SwapParams({
                    amount: vTokenAmount,
                    sqrtPriceLimit: 0,
                    isNotional: false,
                    isPartialAllowed: false,
                    settleProfit: false
                }),
                protocol.vPoolWrapper(poolId),
                protocol
            );
    }

    /// @notice swaps tokens (Long and Short) with input in token amount / vQuote amount
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param swapParams parameters for swap
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param protocol platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vQuoteAmountOut - vQuote amount coming out of pool
    function swapToken(
        VTokenPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        IClearingHouseStructures.SwapParams memory swapParams,
        IVPoolWrapper wrapper,
        Protocol.Info storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        IVPoolWrapper.SwapResult memory swapResult = wrapper.swap(
            swapParams.amount < 0,
            swapParams.isNotional ? swapParams.amount : -swapParams.amount,
            swapParams.sqrtPriceLimit
        );

        // change direction basis uniswap to balance increase
        vTokenAmountOut = -swapResult.vTokenIn;
        vQuoteAmountOut = -swapResult.vQuoteIn;

        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments = IClearingHouseStructures
            .BalanceAdjustments(vQuoteAmountOut, vTokenAmountOut, vTokenAmountOut);

        set.update(accountId, balanceAdjustments, poolId, protocol);

        emit Account.TokenPositionChanged(
            accountId,
            poolId,
            vTokenAmountOut,
            vQuoteAmountOut,
            swapResult.sqrtPriceX96Start,
            swapResult.sqrtPriceX96End
        );
    }

    /// @notice function to liquidate all liquidity positions
    /// @param set VTokenPositionSet
    /// @param protocol platform constants
    /// @return notionalAmountClosed - value of net token position coming out (in notional) of all the ranges closed
    function liquidateLiquidityPositions(
        VTokenPosition.Set storage set,
        uint256 accountId,
        Protocol.Info storage protocol
    ) internal returns (uint256 notionalAmountClosed) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(accountId, set.active[i], protocol);
        }
    }

    /// @notice function to liquidate liquidity positions for a particular token
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param protocol platform constants
    /// @return notionalAmountClosed - value of net token position coming out (in notional) of all the ranges closed
    function liquidateLiquidityPositions(
        VTokenPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal returns (uint256 notionalAmountClosed) {
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments;

        set.getTokenPosition(poolId, false).liquidityPositions.closeAllLiquidityPositions(
            accountId,
            poolId,
            balanceAdjustments,
            protocol
        );

        set.update(accountId, balanceAdjustments, poolId, protocol);

        // returns notional value of token position closed
        return protocol.getNotionalValue(poolId, balanceAdjustments.traderPositionIncrease);
    }

    /// @notice function for liquidity add/remove
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param liquidityChangeParams includes tickLower, tickUpper, liquidityDelta, limitOrderType
    /// @return vTokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @return vQuoteAmountOut amount of vQuote tokens that account received (positive) or paid (negative)
    function liquidityChange(
        VTokenPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams,
        Protocol.Info storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        VTokenPosition.Info storage vTokenPosition = set.getTokenPosition(poolId, true);

        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments;

        vTokenPosition.liquidityPositions.liquidityChange(
            accountId,
            poolId,
            liquidityChangeParams,
            balanceAdjustments,
            protocol
        );

        set.update(accountId, balanceAdjustments, poolId, protocol);

        if (liquidityChangeParams.closeTokenPosition) {
            set.swapTokenAmount(accountId, poolId, -balanceAdjustments.traderPositionIncrease, protocol);
        }

        return (balanceAdjustments.vTokenIncrease, balanceAdjustments.vQuoteIncrease);
    }

    /// @notice function to remove an eligible limit order
    /// @dev checks whether the current price is on the correct side of the range based on the type of limit order (None, Low, High)
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param protocol platform constants
    function removeLimitOrder(
        VTokenPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper,
        Protocol.Info storage protocol
    ) internal {
        VTokenPosition.Info storage vTokenPosition = set.getTokenPosition(poolId, false);

        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments;
        int24 currentTick = protocol.getVirtualCurrentTick(poolId);

        vTokenPosition.liquidityPositions.removeLimitOrder(
            accountId,
            poolId,
            currentTick,
            tickLower,
            tickUpper,
            balanceAdjustments,
            protocol
        );

        set.update(accountId, balanceAdjustments, poolId, protocol);
    }

    /**
     *  Internal view methods
     */

    /// @notice returns account market value of active positions
    /// @param set VTokenPositionSet
    /// @param protocol platform constants
    /// @return accountMarketValue
    function getAccountMarketValue(VTokenPosition.Set storage set, Protocol.Info storage protocol)
        internal
        view
        returns (int256 accountMarketValue)
    {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 poolId = set.active[i];
            if (poolId == 0) break;
            // IVToken vToken = protocol[poolId].vToken;
            VTokenPosition.Info storage position = set.positions[poolId];

            (, uint256 virtualPriceX128) = protocol.getTwapPricesWithDeviationCheck(poolId);
            uint160 virtualSqrtPriceX96 = virtualPriceX128.toSqrtPriceX96();
            //Value of token position for current vToken
            accountMarketValue += position.marketValue(poolId, virtualPriceX128, protocol);

            //Value of all active range position for the current vToken
            accountMarketValue += position.liquidityPositions.marketValue(virtualSqrtPriceX96, poolId, protocol);
        }

        // Value of the vQuote token balance
        accountMarketValue += set.vQuoteBalance;
    }

    function getInfo(VTokenPosition.Set storage set)
        internal
        view
        returns (int256 vQuoteBalance, IClearingHouseStructures.VTokenPositionView[] memory vTokenPositions)
    {
        vQuoteBalance = set.vQuoteBalance;

        uint256 numberOfTokenPositions = set.active.numberOfNonZeroElements();
        vTokenPositions = new IClearingHouseStructures.VTokenPositionView[](numberOfTokenPositions);

        for (uint256 i = 0; i < numberOfTokenPositions; i++) {
            vTokenPositions[i].poolId = set.active[i];
            vTokenPositions[i].balance = set.positions[set.active[i]].balance;
            vTokenPositions[i].netTraderPosition = set.positions[set.active[i]].netTraderPosition;
            vTokenPositions[i].sumALastX128 = set.positions[set.active[i]].sumALastX128;
            vTokenPositions[i].liquidityPositions = set.positions[set.active[i]].liquidityPositions.getInfo();
        }
    }

    /// @notice returns the long and short side risk for range positions of a particular token
    /// @param set VTokenPositionSet
    /// @param isInitialMargin specifies to use initial margin factor (true) or maintainance margin factor (false)
    /// @param poolId id of the rage trade pool
    /// @param protocol platform constants
    /// @return longSideRisk - risk if the token price goes down
    /// @return shortSideRisk - risk if the token price goes up
    function getLongShortSideRisk(
        VTokenPosition.Set storage set,
        bool isInitialMargin,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal view returns (int256 longSideRisk, int256 shortSideRisk) {
        VTokenPosition.Info storage position = set.positions[poolId];

        (, uint256 virtualPriceX128) = protocol.getTwapPricesWithDeviationCheck(poolId);
        uint160 virtualSqrtPriceX96 = virtualPriceX128.toSqrtPriceX96();

        uint16 marginRatio = protocol.getMarginRatioBps(poolId, isInitialMargin);

        int256 tokenPosition = position.balance;
        int256 longSideRiskRanges = position.liquidityPositions.longSideRisk(virtualSqrtPriceX96).toInt256();

        longSideRisk = SignedMath
            .max(position.netTraderPosition.mulDiv(virtualPriceX128, FixedPoint128.Q128) + longSideRiskRanges, 0)
            .mulDiv(marginRatio, 1e4);

        shortSideRisk = SignedMath.max(-tokenPosition, 0).mulDiv(virtualPriceX128, FixedPoint128.Q128).mulDiv(
            marginRatio,
            1e4
        );
        return (longSideRisk, shortSideRisk);
    }

    function getNetPosition(
        VTokenPosition.Set storage set,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal view returns (int256 netPosition) {
        if (!set.active.exists(poolId)) return 0;
        VTokenPosition.Info storage tokenPosition = set.positions[poolId];
        return tokenPosition.getNetPosition(poolId, protocol);
    }

    /// @notice returns the long and short side risk for range positions of a particular token
    /// @param set VTokenPositionSet
    /// @param isInitialMargin specifies to use initial margin factor (true) or maintainance margin factor (false)
    /// @param protocol platform constants
    /// @return requiredMargin - required margin value based on the current active positions
    function getRequiredMargin(
        VTokenPosition.Set storage set,
        bool isInitialMargin,
        Protocol.Info storage protocol
    ) internal view returns (int256 requiredMargin) {
        int256 longSideRiskTotal;
        int256 shortSideRiskTotal;
        int256 longSideRisk;
        int256 shortSideRisk;
        for (uint8 i = 0; i < set.active.length; i++) {
            if (set.active[i] == 0) break;
            uint32 poolId = set.active[i];
            (longSideRisk, shortSideRisk) = set.getLongShortSideRisk(isInitialMargin, poolId, protocol);

            if (protocol.isPoolCrossMargined(poolId)) {
                longSideRiskTotal += longSideRisk;
                shortSideRiskTotal += shortSideRisk;
            } else {
                requiredMargin += SignedMath.max(longSideRisk, shortSideRisk);
            }
        }

        requiredMargin += SignedMath.max(longSideRiskTotal, shortSideRiskTotal);
    }

    /// @notice get or create token position
    /// @dev activates inactive vToken if isCreateNew is true else reverts
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param createNew if 'vToken' is inactive then activates (true) else reverts with TokenInactive(false)
    /// @return position - VTokenPosition corresponding to 'vToken'
    function getTokenPosition(
        VTokenPosition.Set storage set,
        uint32 poolId,
        bool createNew
    ) internal returns (VTokenPosition.Info storage position) {
        if (createNew) {
            set.activate(poolId);
        } else if (!set.active.exists(poolId)) {
            revert VPS_TokenInactive(poolId);
        }

        position = set.positions[poolId];
    }

    /// @notice returns true if the set does not have any token position active
    /// @param set VTokenPositionSet
    /// @return True if there are no active positions
    function isEmpty(VTokenPosition.Set storage set) internal view returns (bool) {
        return set.active.isEmpty();
    }

    /// @notice returns true if range position is active for 'vToken'
    /// @param set VTokenPositionSet
    /// @param poolId poolId of the vToken
    /// @return isRangeActive
    function isTokenRangeActive(VTokenPosition.Set storage set, uint32 poolId) internal returns (bool isRangeActive) {
        VTokenPosition.Info storage vTokenPosition = set.getTokenPosition(poolId, false);
        isRangeActive = !vTokenPosition.liquidityPositions.isEmpty();
    }
}

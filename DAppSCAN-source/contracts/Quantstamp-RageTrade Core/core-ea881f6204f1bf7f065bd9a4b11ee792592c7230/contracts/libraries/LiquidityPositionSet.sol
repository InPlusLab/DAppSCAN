// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { Account } from './Account.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { Uint48Lib } from './Uint48.sol';
import { Uint48L5ArrayLib } from './Uint48L5Array.sol';
import { Protocol } from './Protocol.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

/// @title Liquidity position set functions
library LiquidityPositionSet {
    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for LiquidityPosition.Set;
    using Protocol for Protocol.Info;
    using Uint48Lib for int24;
    using Uint48Lib for uint48;
    using Uint48L5ArrayLib for uint48[5];

    error LPS_IllegalTicks(int24 tickLower, int24 tickUpper);
    error LPS_DeactivationFailed(int24 tickLower, int24 tickUpper, uint256 liquidity);
    error LPS_InactiveRange();

    /**
     *  Internal methods
     */

    function activate(
        LiquidityPosition.Set storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (LiquidityPosition.Info storage position) {
        if (tickLower > tickUpper) {
            revert LPS_IllegalTicks(tickLower, tickUpper);
        }

        uint48 positionId;
        set.active.include(positionId = tickLower.concat(tickUpper));
        position = set.positions[positionId];

        if (!position.isInitialized()) {
            position.initialize(tickLower, tickUpper);
        }
    }

    function deactivate(LiquidityPosition.Set storage set, LiquidityPosition.Info storage position) internal {
        if (position.liquidity != 0) {
            revert LPS_DeactivationFailed(position.tickLower, position.tickUpper, position.liquidity);
        }

        set.active.exclude(position.tickLower.concat(position.tickUpper));
    }

    function liquidityChange(
        LiquidityPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        LiquidityPosition.Info storage position = set.activate(
            liquidityChangeParams.tickLower,
            liquidityChangeParams.tickUpper
        );

        position.limitOrderType = liquidityChangeParams.limitOrderType;

        set.liquidityChange(
            accountId,
            poolId,
            position,
            liquidityChangeParams.liquidityDelta,
            balanceAdjustments,
            protocol
        );
    }

    function liquidityChange(
        LiquidityPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        LiquidityPosition.Info storage position,
        int128 liquidity,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        position.liquidityChange(accountId, poolId, liquidity, balanceAdjustments, protocol);

        emit Account.TokenPositionChangedDueToLiquidityChanged(
            accountId,
            poolId,
            position.tickLower,
            position.tickUpper,
            balanceAdjustments.vTokenIncrease
        );

        if (position.liquidity == 0) {
            set.deactivate(position);
        }
    }

    function closeLiquidityPosition(
        LiquidityPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        LiquidityPosition.Info storage position,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        set.liquidityChange(accountId, poolId, position, -int128(position.liquidity), balanceAdjustments, protocol);
    }

    function removeLimitOrder(
        LiquidityPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        LiquidityPosition.Info storage position = set.getLiquidityPosition(tickLower, tickUpper);
        position.checkValidLimitOrderRemoval(currentTick);
        set.closeLiquidityPosition(accountId, poolId, position, balanceAdjustments, protocol);
    }

    function closeAllLiquidityPositions(
        LiquidityPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        LiquidityPosition.Info storage position;

        while (set.active[0] != 0) {
            IClearingHouseStructures.BalanceAdjustments memory balanceAdjustmentsCurrent;

            position = set.positions[set.active[0]];

            set.closeLiquidityPosition(accountId, poolId, position, balanceAdjustmentsCurrent, protocol);

            balanceAdjustments.vQuoteIncrease += balanceAdjustmentsCurrent.vQuoteIncrease;
            balanceAdjustments.vTokenIncrease += balanceAdjustmentsCurrent.vTokenIncrease;
            balanceAdjustments.traderPositionIncrease += balanceAdjustmentsCurrent.traderPositionIncrease;
        }
    }

    /**
     *  Internal view methods
     */

    function getLiquidityPosition(
        LiquidityPosition.Set storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (LiquidityPosition.Info storage position) {
        if (tickLower > tickUpper) {
            revert LPS_IllegalTicks(tickLower, tickUpper);
        }

        uint48 positionId = Uint48Lib.concat(tickLower, tickUpper);
        position = set.positions[positionId];

        if (!position.isInitialized()) revert LPS_InactiveRange();
        return position;
    }

    function getInfo(LiquidityPosition.Set storage set)
        internal
        view
        returns (IClearingHouseStructures.LiquidityPositionView[] memory liquidityPositions)
    {
        uint256 numberOfTokenPositions = set.active.numberOfNonZeroElements();
        liquidityPositions = new IClearingHouseStructures.LiquidityPositionView[](numberOfTokenPositions);

        for (uint256 i = 0; i < numberOfTokenPositions; i++) {
            liquidityPositions[i].limitOrderType = set.positions[set.active[i]].limitOrderType;
            liquidityPositions[i].tickLower = set.positions[set.active[i]].tickLower;
            liquidityPositions[i].tickUpper = set.positions[set.active[i]].tickUpper;
            liquidityPositions[i].liquidity = set.positions[set.active[i]].liquidity;
            liquidityPositions[i].vTokenAmountIn = set.positions[set.active[i]].vTokenAmountIn;
            liquidityPositions[i].sumALastX128 = set.positions[set.active[i]].sumALastX128;
            liquidityPositions[i].sumBInsideLastX128 = set.positions[set.active[i]].sumBInsideLastX128;
            liquidityPositions[i].sumFpInsideLastX128 = set.positions[set.active[i]].sumFpInsideLastX128;
            liquidityPositions[i].sumFeeInsideLastX128 = set.positions[set.active[i]].sumFeeInsideLastX128;
        }
    }

    function getNetPosition(LiquidityPosition.Set storage set, uint160 sqrtPriceCurrent)
        internal
        view
        returns (int256 netPosition)
    {
        uint256 numberOfTokenPositions = set.active.numberOfNonZeroElements();

        for (uint256 i = 0; i < numberOfTokenPositions; i++) {
            netPosition += set.positions[set.active[i]].netPosition(sqrtPriceCurrent);
        }
    }

    function isEmpty(LiquidityPosition.Set storage set) internal view returns (bool) {
        return set.active.isEmpty();
    }

    function isPositionActive(
        LiquidityPosition.Set storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (bool) {
        return set.active.exists(tickLower.concat(tickUpper));
    }

    function longSideRisk(LiquidityPosition.Set storage set, uint160 valuationPriceX96)
        internal
        view
        returns (uint256 risk)
    {
        for (uint256 i = 0; i < set.active.length; i++) {
            uint48 id = set.active[i];
            risk += set.positions[id].longSideRisk(valuationPriceX96);
        }
    }

    function marketValue(
        LiquidityPosition.Set storage set,
        uint160 sqrtPriceCurrent,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal view returns (int256 marketValue_) {
        marketValue_ = set.marketValue(sqrtPriceCurrent, protocol.vPoolWrapper(poolId));
    }

    /// @notice Get the total market value of all active liquidity positions in the set.
    /// @param set: Collection of active liquidity positions
    /// @param sqrtPriceCurrent: Current price of the virtual asset
    /// @param wrapper: address of the wrapper contract, passed once to avoid multiple sloads for wrapper
    function marketValue(
        LiquidityPosition.Set storage set,
        uint160 sqrtPriceCurrent,
        IVPoolWrapper wrapper
    ) internal view returns (int256 marketValue_) {
        for (uint256 i = 0; i < set.active.length; i++) {
            uint48 id = set.active[i];
            if (id == 0) break;
            marketValue_ += set.positions[id].marketValue(sqrtPriceCurrent, wrapper);
        }
    }

    function maxNetPosition(LiquidityPosition.Set storage set) internal view returns (uint256 risk) {
        for (uint256 i = 0; i < set.active.length; i++) {
            uint48 id = set.active[i];
            risk += set.positions[id].maxNetPosition();
        }
    }
}

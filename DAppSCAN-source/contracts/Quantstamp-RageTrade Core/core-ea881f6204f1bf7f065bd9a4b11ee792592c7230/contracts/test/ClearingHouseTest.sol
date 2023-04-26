// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account } from '../libraries/Account.sol';
import { CollateralDeposit } from '../libraries/CollateralDeposit.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { SignedFullMath } from '../libraries/SignedFullMath.sol';
import { AddressHelper } from '../libraries/AddressHelper.sol';
import { Protocol } from '../libraries/Protocol.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IClearingHouseEnums } from '../interfaces/clearinghouse/IClearingHouseEnums.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { ClearingHouse } from '../protocol/clearinghouse/ClearingHouse.sol';

contract ClearingHouseTest is ClearingHouse {
    using AddressHelper for address;
    using AddressHelper for IVToken;
    using SignedFullMath for int256;

    using Account for Account.Info;
    using CollateralDeposit for CollateralDeposit.Set;
    using LiquidityPositionSet for LiquidityPosition.Set;
    using LiquidityPosition for LiquidityPosition.Info;
    using Protocol for Protocol.Info;
    using VTokenPositionSet for VTokenPosition.Set;
    using VTokenPosition for VTokenPosition.Info;

    function getTruncatedTokenAddress(IVToken vToken) external pure returns (uint32) {
        return vToken.truncate();
    }

    function cleanPositions(uint256 accountId) external {
        VTokenPosition.Set storage set = accounts[accountId].tokenPositions;
        VTokenPosition.Info storage tokenPosition;
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments;

        set.vQuoteBalance = 0;

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 poolId = set.active[i];
            if (poolId == 0) break;
            tokenPosition = set.positions[poolId];
            balanceAdjustments = IClearingHouseStructures.BalanceAdjustments(
                0,
                -tokenPosition.balance,
                -tokenPosition.netTraderPosition
            );
            set.update(accountId, balanceAdjustments, poolId, protocol);
        }
    }

    function cleanDeposits(uint256 accountId) external {
        accounts[accountId].tokenPositions.liquidateLiquidityPositions(accountId, protocol);

        CollateralDeposit.Set storage set = accounts[accountId].collateralDeposits;
        uint256 deposit;

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 collateralId = set.active[i];
            if (collateralId == 0) break;
            deposit = set.deposits[collateralId];
            set.decreaseBalance(collateralId, deposit);
        }
    }

    function getTokenAddressInVTokens(IVToken vToken) external view returns (IVToken vTokenInIVTokenes) {
        return protocol.pools[vToken.truncate()].vToken;
    }

    function getAccountOwner(uint256 accountId) external view returns (address owner) {
        return accounts[accountId].owner;
    }

    // function getAccountNumInTokenPositionSet(uint256 accountId) external view returns (uint256 accountIdInTokenSet) {
    //     return accounts[accountId].tokenPositions.accountId;
    // }

    function getAccountDepositBalance(uint256 accountId, IVToken vToken) external view returns (uint256 balance) {
        balance = accounts[accountId].collateralDeposits.deposits[vToken.truncate()];
    }

    function getAccountOpenTokenPosition(uint256 accountId, IVToken vToken)
        external
        view
        returns (int256 balance, int256 netTraderPosition)
    {
        VTokenPosition.Info storage vTokenPosition = accounts[accountId].tokenPositions.positions[vToken.truncate()];
        balance = vTokenPosition.balance;
        netTraderPosition = vTokenPosition.netTraderPosition;
    }

    function getAccountQuoteBalance(uint256 accountId) external view returns (int256 balance) {
        return accounts[accountId].tokenPositions.vQuoteBalance;
    }

    function getAccountLiquidityPositionNum(uint256 accountId, address vToken) external view returns (uint8 num) {
        LiquidityPosition.Set storage liquidityPositionSet = accounts[accountId]
            .tokenPositions
            .positions[vToken.truncate()]
            .liquidityPositions;

        for (num = 0; num < liquidityPositionSet.active.length; num++) {
            if (liquidityPositionSet.active[num] == 0) break;
        }
    }

    function getAccountTokenPositionFunding(uint256 accountId, IVToken vToken)
        external
        view
        returns (int256 fundingPayment)
    {
        VTokenPosition.Info storage vTokenPosition = accounts[accountId].tokenPositions.positions[vToken.truncate()];

        IVPoolWrapper wrapper = protocol.vPoolWrapper(vToken.truncate());

        fundingPayment = vTokenPosition.unrealizedFundingPayment(wrapper);
    }

    function getAccountLiquidityPositionFundingAndFee(
        uint256 accountId,
        address vToken,
        uint8 num
    ) external view returns (int256 fundingPayment, uint256 unrealizedLiquidityFee) {
        LiquidityPosition.Set storage liquidityPositionSet = accounts[accountId]
            .tokenPositions
            .positions[vToken.truncate()]
            .liquidityPositions;
        LiquidityPosition.Info storage liquidityPosition = liquidityPositionSet.positions[
            liquidityPositionSet.active[num]
        ];

        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside = protocol
            .vPoolWrapper(vToken.truncate())
            .getExtrapolatedValuesInside(liquidityPosition.tickLower, liquidityPosition.tickUpper);

        fundingPayment = liquidityPosition.unrealizedFundingPayment(
            wrapperValuesInside.sumAX128,
            wrapperValuesInside.sumFpInsideX128
        );

        unrealizedLiquidityFee = liquidityPosition.unrealizedFees(wrapperValuesInside.sumFeeInsideX128);
    }

    function getAccountLiquidityPositionDetails(
        uint256 accountId,
        address vToken,
        uint8 num
    )
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            IClearingHouseEnums.LimitOrderType limitOrderType,
            uint128 liquidity,
            int256 sumALastX128,
            int256 sumBInsideLastX128,
            int256 sumFpInsideLastX128,
            uint256 sumFeeInsideLastX128
        )
    {
        LiquidityPosition.Set storage liquidityPositionSet = accounts[accountId]
            .tokenPositions
            .positions[vToken.truncate()]
            .liquidityPositions;
        LiquidityPosition.Info storage liquidityPosition = liquidityPositionSet.positions[
            liquidityPositionSet.active[num]
        ];

        return (
            liquidityPosition.tickLower,
            liquidityPosition.tickUpper,
            liquidityPosition.limitOrderType,
            liquidityPosition.liquidity,
            liquidityPosition.sumALastX128,
            liquidityPosition.sumBInsideLastX128,
            liquidityPosition.sumFpInsideLastX128,
            liquidityPosition.sumFeeInsideLastX128
        );
    }

    function getAccountValueAndRequiredMargin(uint256 accountId, bool isInitialMargin)
        external
        view
        returns (int256 accountMarketValue, int256 requiredMargin)
    {
        return accounts[accountId].getAccountValueAndRequiredMargin(isInitialMargin, protocol);
    }
}

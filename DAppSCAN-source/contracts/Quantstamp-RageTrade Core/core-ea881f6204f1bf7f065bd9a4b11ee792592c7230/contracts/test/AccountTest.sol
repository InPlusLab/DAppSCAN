// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account } from '../libraries/Account.sol';
import { AddressHelper } from '../libraries/AddressHelper.sol';
import { CollateralDeposit } from '../libraries/CollateralDeposit.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { Protocol } from '../libraries/Protocol.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';

import { IClearingHouseEnums } from '../interfaces/clearinghouse/IClearingHouseEnums.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVQuote } from '../interfaces/IVQuote.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract AccountTest {
    using AddressHelper for address;
    using AddressHelper for IERC20;
    using AddressHelper for IVToken;

    using Account for Account.Info;
    using VTokenPosition for VTokenPosition.Info;
    using VTokenPositionSet for VTokenPosition.Set;
    using LiquidityPositionSet for LiquidityPosition.Set;
    using CollateralDeposit for CollateralDeposit.Set;

    mapping(uint256 => Account.Info) accounts;
    Protocol.Info public protocol;
    uint256 public fixFee;

    uint256 public numAccounts;

    constructor() {}

    function setAccountStorage(
        IClearingHouseStructures.LiquidationParams calldata liquidationParams,
        uint256 minRequiredMargin,
        uint256 removeLimitOrderFee,
        uint256 minimumOrderNotional,
        uint256 fixFee_,
        address settlementToken
    ) external {
        protocol.liquidationParams = liquidationParams;
        protocol.minRequiredMargin = minRequiredMargin;
        protocol.removeLimitOrderFee = removeLimitOrderFee;
        protocol.minimumOrderNotional = minimumOrderNotional;
        protocol.settlementToken = IERC20(settlementToken);
        fixFee = fixFee_;
    }

    function registerPool(IClearingHouseStructures.Pool calldata poolInfo) external {
        uint32 poolId = poolInfo.vToken.truncate();

        // pool will not be registered twice by the rage trade factory
        assert(protocol.pools[poolId].vToken.isZero());

        protocol.pools[poolId] = poolInfo;
    }

    function setVQuoteAddress(IVQuote _vQuote) external {
        protocol.vQuote = _vQuote;
    }

    function createAccount() external {
        Account.Info storage newAccount = accounts[numAccounts];
        newAccount.owner = msg.sender;
        // newAccount.tokenPositions.accountId = numAccounts;
        numAccounts++;
    }

    function cleanPositions(uint256 accountId) external {
        accounts[accountId].tokenPositions.liquidateLiquidityPositions(accountId, protocol);
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

    function initToken(address vToken) external {
        protocol.pools[vToken.truncate()].vToken = IVToken(vToken);
    }

    function initCollateral(
        IERC20 cToken,
        IOracle oracle,
        uint32 twapDuration
    ) external {
        IClearingHouseStructures.Collateral memory collateral = IClearingHouseStructures.Collateral(
            cToken,
            IClearingHouseStructures.CollateralSettings(oracle, twapDuration, true)
        );
        protocol.collaterals[collateral.token.truncate()] = collateral;
    }

    function addMargin(
        uint256 accountId,
        address realTokenAddress,
        uint256 amount
    ) external {
        accounts[accountId].updateMargin(realTokenAddress.truncate(), int256(amount), protocol, false);
    }

    function removeMargin(
        uint256 accountId,
        address realTokenAddress,
        uint256 amount
    ) external {
        accounts[accountId].updateMargin(realTokenAddress.truncate(), -int256(amount), protocol, true);
    }

    function updateProfit(uint256 accountId, int256 amount) external {
        accounts[accountId].updateProfit(amount, protocol, true);
    }

    function swapTokenAmount(
        uint256 accountId,
        address vToken,
        int256 amount
    ) external {
        accounts[accountId].swapToken(
            vToken.truncate(),
            IClearingHouseStructures.SwapParams(amount, 0, false, false, false),
            protocol,
            true
        );
    }

    function swapTokenNotional(
        uint256 accountId,
        address vToken,
        int256 amount
    ) external {
        accounts[accountId].swapToken(
            vToken.truncate(),
            IClearingHouseStructures.SwapParams(amount, 0, true, false, false),
            protocol,
            true
        );
    }

    function liquidityChange(
        uint256 accountId,
        address vToken,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams
    ) external {
        accounts[accountId].liquidityChange(vToken.truncate(), liquidityChangeParams, protocol, true);
    }

    function liquidateLiquidityPositions(uint256 accountId)
        external
        returns (
            int256 keeperFee,
            int256 insuranceFundFee,
            int256 accountMarketValue
        )
    {
        return accounts[accountId].liquidateLiquidityPositions(fixFee, protocol);
    }

    function liquidateTokenPosition(uint256 accountId, address vToken) external {
        accounts[accountId].liquidateTokenPosition(vToken.truncate(), fixFee, protocol);
    }

    function removeLimitOrder(
        uint256 accountId,
        address vToken,
        int24 tickLower,
        int24 tickUpper,
        uint256 removeLimitOrderFee
    ) external {
        accounts[accountId].removeLimitOrder(vToken.truncate(), tickLower, tickUpper, removeLimitOrderFee, protocol);
    }

    function getAccountDepositBalance(uint256 accountId, address vToken) external view returns (uint256) {
        return accounts[accountId].collateralDeposits.deposits[vToken.truncate()];
    }

    function getAccountTokenDetails(uint256 accountId, address vToken)
        external
        view
        returns (
            int256 balance,
            int256 netTraderPosition,
            int256 sumALast
        )
    {
        VTokenPosition.Info storage vTokenPosition = accounts[accountId].tokenPositions.positions[vToken.truncate()];
        return (vTokenPosition.balance, vTokenPosition.netTraderPosition, vTokenPosition.sumALastX128);
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
            int256 vTokenAmountIn,
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
            liquidityPosition.vTokenAmountIn,
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
        (accountMarketValue, requiredMargin) = accounts[accountId].getAccountValueAndRequiredMargin(
            isInitialMargin,
            protocol
        );
    }

    function getAccountProfit(uint256 accountId) external view returns (int256 profit) {
        return accounts[accountId].tokenPositions.getAccountMarketValue(protocol);
    }
}

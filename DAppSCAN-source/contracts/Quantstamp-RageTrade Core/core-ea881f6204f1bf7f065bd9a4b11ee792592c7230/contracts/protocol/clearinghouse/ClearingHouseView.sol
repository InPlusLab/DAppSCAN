// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IClearingHouseView } from '../../interfaces/clearinghouse/IClearingHouseView.sol';
import { IVQuote } from '../../interfaces/IVQuote.sol';
import { IVToken } from '../../interfaces/IVToken.sol';

import { Account } from '../../libraries/Account.sol';
import { AddressHelper } from '../../libraries/AddressHelper.sol';
import { Protocol } from '../../libraries/Protocol.sol';

import { ClearingHouseStorage } from './ClearingHouseStorage.sol';

import { Extsload } from '../../utils/Extsload.sol';

abstract contract ClearingHouseView is IClearingHouse, ClearingHouseStorage, Extsload {
    using Account for Account.Info;
    using AddressHelper for address;
    using AddressHelper for IVToken;
    using Protocol for Protocol.Info;

    /// @inheritdoc IClearingHouseView
    function getAccountInfo(uint256 accountId)
        public
        view
        returns (
            address owner,
            int256 vQuoteBalance,
            CollateralDepositView[] memory collateralDeposits,
            VTokenPositionView[] memory tokenPositions
        )
    {
        return accounts[accountId].getInfo(protocol);
    }

    /// @inheritdoc IClearingHouseView
    function getAccountMarketValueAndRequiredMargin(uint256 accountId, bool isInitialMargin)
        public
        view
        returns (int256 marketValue, int256 requiredMargin)
    {
        (marketValue, requiredMargin) = accounts[accountId].getAccountValueAndRequiredMargin(isInitialMargin, protocol);
    }

    /// @inheritdoc IClearingHouseView
    function getAccountNetProfit(uint256 accountId) public view returns (int256 accountNetProfit) {
        accountNetProfit = accounts[accountId].getAccountPositionProfits(protocol);
    }

    /// @inheritdoc IClearingHouseView
    function getAccountNetTokenPosition(uint256 accountId, uint32 poolId) public view returns (int256 netPosition) {
        return accounts[accountId].getNetPosition(poolId, protocol);
    }

    /// @inheritdoc IClearingHouseView
    function getCollateralInfo(uint32 collateralId) public view returns (Collateral memory) {
        return protocol.collaterals[collateralId];
    }

    /// @inheritdoc IClearingHouseView
    function getPoolInfo(uint32 poolId) public view returns (Pool memory) {
        return protocol.pools[poolId];
    }

    /// @inheritdoc IClearingHouseView
    function getProtocolInfo()
        public
        view
        returns (
            IERC20 settlementToken,
            IVQuote vQuote,
            LiquidationParams memory liquidationParams,
            uint256 minRequiredMargin,
            uint256 removeLimitOrderFee,
            uint256 minimumOrderNotional
        )
    {
        settlementToken = protocol.settlementToken;
        vQuote = protocol.vQuote;
        liquidationParams = protocol.liquidationParams;
        minRequiredMargin = protocol.minRequiredMargin;
        removeLimitOrderFee = protocol.removeLimitOrderFee;
        minimumOrderNotional = protocol.minimumOrderNotional;
    }

    /// @inheritdoc IClearingHouseView
    function getRealTwapPriceX128(uint32 poolId) public view returns (uint256 realPriceX128) {
        realPriceX128 = protocol.getRealTwapPriceX128(poolId);
    }

    /// @inheritdoc IClearingHouseView
    function getVirtualTwapPriceX128(uint32 poolId) public view returns (uint256 virtualPriceX128) {
        virtualPriceX128 = protocol.getVirtualTwapPriceX128(poolId);
    }

    /// @inheritdoc IClearingHouseView
    function isPoolIdAvailable(uint32 poolId) external view returns (bool) {
        return protocol.pools[poolId].vToken.isZero();
    }
}

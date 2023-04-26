// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Protocol } from '../../libraries/Protocol.sol';
import { AddressHelper } from '../../libraries/AddressHelper.sol';

import { IClearingHouseStructures } from '../../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVQuote } from '../../interfaces/IVQuote.sol';
import { IVToken } from '../../interfaces/IVToken.sol';

abstract contract AccountProtocolInfoMock {
    using AddressHelper for address;

    Protocol.Info public protocol;

    uint256 public fixFee;

    function setAccountStorage(
        IClearingHouseStructures.LiquidationParams calldata _liquidationParams,
        uint256 _minRequiredMargin,
        uint256 _removeLimitOrderFee,
        uint256 _minimumOrderNotional,
        uint256 _fixFee
    ) external {
        protocol.liquidationParams = _liquidationParams;
        protocol.minRequiredMargin = _minRequiredMargin;
        protocol.removeLimitOrderFee = _removeLimitOrderFee;
        protocol.minimumOrderNotional = _minimumOrderNotional;
        fixFee = _fixFee;
    }

    function registerPool(IClearingHouseStructures.Pool calldata poolInfo) external virtual {
        uint32 poolId = address(poolInfo.vToken).truncate();

        // this check is not present here as the tests change some things.
        // this method is only used in these tests:
        // AccountBasic, AccountRealistic, MarketValueAndReqMargin, VTokenPositionSet
        // assert(address(protocol.pools[poolId].vToken).eq(address(0)));

        protocol.pools[poolId] = poolInfo;
    }

    function setVQuoteAddress(IVQuote _vQuote) external {
        protocol.vQuote = _vQuote;
    }
}

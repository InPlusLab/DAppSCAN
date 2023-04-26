// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { Account } from './Account.sol';
import { Protocol } from './Protocol.sol';
import { AddressHelper } from './AddressHelper.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';

/// @title Collateral deposit set functions
library CollateralDeposit {
    using AddressHelper for address;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using Uint32L8ArrayLib for uint32[8];

    error InsufficientCollateralBalance();

    struct Set {
        // Fixed length array of collateralId = collateralAddress.truncate()
        // Supports upto 8 different collaterals in an account.
        // Collision is possible, i.e. collateralAddress1.truncate() == collateralAddress2.truncate()
        // However the possibility is 1/2**32, which is negligible.
        // There are checks that prevent use of a different collateralAddress for a given collateralId.
        // If there is a geniune collision, a wrapper for the ERC20 token can deployed such that
        // there are no collisions with wrapper and the wrapped ERC20 can be used as collateral.
        uint32[8] active; // array of collateralIds
        mapping(uint32 => uint256) deposits; // collateralId => deposit amount
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    function getBalance(CollateralDeposit.Set storage set, uint32 collateralId) internal view returns (uint256) {
        return set.deposits[collateralId];
    }

    /// @notice Increase the deposit amount of a given collateralId
    /// @param set CollateralDepositSet of the account
    /// @param collateralId The collateralId of the collateral to increase the deposit amount of
    /// @param amount The amount to increase the deposit amount of the collateral by
    function increaseBalance(
        CollateralDeposit.Set storage set,
        uint32 collateralId,
        uint256 amount
    ) internal {
        set.active.include(collateralId);

        set.deposits[collateralId] += amount;
    }

    /// @notice Decrease the deposit amount of a given collateralId
    /// @param set CollateralDepositSet of the account
    /// @param collateralId The collateralId of the collateral to decrease the deposit amount of
    /// @param amount The amount to decrease the deposit amount of the collateral by
    function decreaseBalance(
        CollateralDeposit.Set storage set,
        uint32 collateralId,
        uint256 amount
    ) internal {
        if (set.deposits[collateralId] < amount) revert InsufficientCollateralBalance();
        set.deposits[collateralId] -= amount;

        if (set.deposits[collateralId] == 0) {
            set.active.exclude(collateralId);
        }
    }

    /// @notice Get the market value of all the collateral deposits in settlementToken denomination
    /// @param set CollateralDepositSet of the account
    /// @param protocol Global protocol state
    /// @return The market value of all the collateral deposits in settlementToken denomination
    function marketValue(CollateralDeposit.Set storage set, Protocol.Info storage protocol)
        internal
        view
        returns (int256)
    {
        int256 accountMarketValue;
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 collateralId = set.active[i];

            if (collateralId == 0) break;
            IClearingHouseStructures.Collateral storage collateral = protocol.collaterals[collateralId];

            accountMarketValue += set.deposits[collateralId].toInt256().mulDiv(
                collateral.settings.oracle.getTwapPriceX128(collateral.settings.twapDuration),
                FixedPoint128.Q128
            );
        }
        return accountMarketValue;
    }

    /// @notice Get information about all the collateral deposits
    /// @param set CollateralDepositSet of the account
    /// @param protocol Global protocol state
    /// @return collateralDeposits Information about all the collateral deposits
    function getInfo(CollateralDeposit.Set storage set, Protocol.Info storage protocol)
        internal
        view
        returns (IClearingHouseStructures.CollateralDepositView[] memory collateralDeposits)
    {
        uint256 numberOfTokenPositions = set.active.numberOfNonZeroElements();
        collateralDeposits = new IClearingHouseStructures.CollateralDepositView[](numberOfTokenPositions);

        for (uint256 i = 0; i < numberOfTokenPositions; i++) {
            collateralDeposits[i].collateral = protocol.collaterals[set.active[i]].token;
            collateralDeposits[i].balance = set.deposits[set.active[i]];
        }
    }
}

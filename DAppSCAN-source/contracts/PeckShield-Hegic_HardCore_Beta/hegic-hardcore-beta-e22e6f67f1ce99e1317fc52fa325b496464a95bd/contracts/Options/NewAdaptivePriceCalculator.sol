pragma solidity 0.8.6;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2021 Hegic Protocol
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

import "./SimplePriceCalculator.sol";
import "../Pool/IHegicOperationalTreasury.sol";
import "../Pool/IHegicStrategy.sol";

/**
 * @author 0mllwntrmt3
 * @title Hegic Protocol V8888 Price Calculator Contract
 * @notice The contract that calculates the options prices (the premiums)
 * that are adjusted through the `ImpliedVolRate` parameter.
 **/

contract NewAdaptivePriceCalculator is PriceCalculator {
    IHegicOperationalTreasury public immutable pool;
    IHegicStrategy public strategy;

    uint256 internal constant PRICE_MODIFIER_DECIMALS = 1e8;
    // uint256 public utilizationRate = 0;

    uint256 public utilizationRate = 1e8;

    constructor(
        uint256 initialRate,
        AggregatorV3Interface _priceProvider,
        IHegicOperationalTreasury _pool
    ) PriceCalculator(initialRate, _priceProvider) {
        pool = _pool;
    }

    function setStrategy(IHegicStrategy _strategy) external onlyOwner {
        strategy = _strategy;
    }

    /**
     * @notice Calculates and prices in the time value of the option
     * @param amount Option size
     * @param period The option period in seconds (1 days <= period <= 90 days)
     * @return fee The premium size to be paid
     **/
    function _calculatePeriodFee(uint256 amount, uint256 period)
        internal
        view
        override
        returns (uint256 fee)
    {
        return
            (super._calculatePeriodFeeS(amount, period) *
                _priceModifier(amount, period)) / PRICE_MODIFIER_DECIMALS;
    }

    /**
     * @notice Calculates `periodFee` of the option
     * @param amount The option size
     **/
    function _priceModifier(uint256 amount, uint256 period)
        internal
        view
        returns (uint256 iv)
    {
        uint256 poolBalance = strategy.lockedLimit();
        if (poolBalance == 0) return PRICE_MODIFIER_DECIMALS;

        uint256 lockedAmount =
            strategy.getLockedByStrategy() + _lockedAmount(amount, period);
        uint256 utilization = (lockedAmount * 100e8) / poolBalance;

        if (utilization < 40e8) return PRICE_MODIFIER_DECIMALS;

        return
            PRICE_MODIFIER_DECIMALS +
            (PRICE_MODIFIER_DECIMALS * (utilization - 40e8) * utilizationRate) /
            60e16;
    }

    function _lockedAmount(uint256 amount, uint256 period)
        internal
        view
        returns (uint256)
    {
        return super.calculatePremiumS(period, amount, 0);
    }

    function setUtilizationRate(uint256 value) external onlyOwner {
        utilizationRate = value;
    }
}

// contract AdaptivePutPriceCalculator is AdaptivePriceCalculator {
//     uint256 private immutable SpotDecimals;
//     uint256 private constant TokenDecimals = 1e6;
//
//     constructor(
//         uint256 initialRate,
//         AggregatorV3Interface _priceProvider,
//         IHegicOperationalTreasury _pool,
//         uint8 spotDecimals
//     ) AdaptivePriceCalculator(initialRate, _priceProvider, _pool) {
//         SpotDecimals = 10**spotDecimals;
//     }
//
//     function _lockedAmount(uint256 amount)
//         internal
//         view
//         override
//         returns (uint256)
//     {
//         return
//             (amount *
//                 pool.collateralizationRatio() *
//                 _currentPrice() *
//                 TokenDecimals) /
//             SpotDecimals /
//             1e8 /
//             100;
//     }
// }

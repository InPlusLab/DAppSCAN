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

import "../Interfaces/Interfaces.sol";
import "../utils/Math.sol";

/**
 * @author 0mllwntrmt3
 * @title Hegic Protocol V8888 Price Calculator Contract
 * @notice The contract that calculates the options prices (the premiums)
 * that are adjusted through the `ImpliedVolRate` parameter.
 **/

contract PriceCalculator is IPriceCalculator, IPremiumCalculator, Ownable {
    using HegicMath for uint256;

    uint256 public impliedVolRate;
    uint256 internal immutable priceDecimals;
    uint256 internal constant IVL_DECIMALS = 1e18;
    uint256 public settlementFeeShare = 20;
    uint256 public maxPeriod = 30 days;

    AggregatorV3Interface public priceProvider;

    constructor(uint256 initialRate, AggregatorV3Interface _priceProvider) {
        priceProvider = _priceProvider;
        impliedVolRate = initialRate;
        priceDecimals = 10**priceProvider.decimals();
    }

    /**
     * @notice Used for adjusting the options prices (the premiums)
     * while balancing the asset's implied volatility rate.
     * @param value New IVRate value
     **/
    function setImpliedVolRate(uint256 value) external onlyOwner {
        impliedVolRate = value;
    }

    /**
     * @notice Used for adjusting the options prices (the premiums)
     * while balancing the asset's implied volatility rate.
     * @param value New settlementFeeShare value
     **/
    function setSettlementFeeShare(uint256 value) external onlyOwner {
        require(value <= 100, "The value is too large");
        settlementFeeShare = value;
    }

    function setMaxPeriod(uint256 value) external onlyOwner {
        maxPeriod = value;
    }

    /**
     * @notice Used for calculating the options prices
     * @param period The option period in seconds (1 days <= period <= 90 days)
     * @param amount The option size
     * @param strike The option strike
     * @return settlementFee The part of the premium that
     * is distributed among the HEGIC staking participants
     * @return premium The part of the premium that
     * is distributed among the liquidity providers
     **/
    function calculateTotalPremium(
        uint256 period,
        uint256 amount,
        uint256 strike
    ) public view override returns (uint256 settlementFee, uint256 premium) {
        uint256 currentPrice = _currentPrice();
        if (strike == 0) strike = currentPrice;
        require(period <= maxPeriod, "PriceCalculator: Period is too long");
        require(
            strike == currentPrice,
            "Only ATM options are currently available"
        );
        uint256 total = _calculatePeriodFee(amount, period);
        settlementFee = (total * settlementFeeShare) / 100;
        premium = total - settlementFee;
    }

    function calculatePremium(
        uint256 period,
        uint256 amount,
        uint256 strike
    ) public view override returns (uint256 premium) {
        require(period >= 1 days, "HegicStrategy: The period is too short");
        require(period <= 30 days, "HegicStrategy: The period is too long");
        return _calculatePeriodFee(amount, period);
    }

    function calculatePremiumS(
        uint256 period,
        uint256 amount,
        uint256 strike
    ) public view returns (uint256 premium) {
        require(period >= 1 days, "HegicStrategy: The period is too short");
        require(period <= 30 days, "HegicStrategy: The period is too long");
        return _calculatePeriodFeeS(amount, period);
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
        virtual
        returns (uint256 fee)
    {
        return
            (amount * impliedVolRate * period.sqrt()) /
            // priceDecimals /
            IVL_DECIMALS;
    }

    function _calculatePeriodFeeS(uint256 amount, uint256 period)
        internal
        view
        virtual
        returns (uint256 fee)
    {
        return
            (amount * impliedVolRate * period.sqrt()) /
            // priceDecimals /
            IVL_DECIMALS;
    }

    /**
     * @notice Used for requesting the current price of the asset
     * using the ChainLink data feeds contracts.
     * See https://feeds.chain.link/
     * @return price Price
     **/
    function _currentPrice() internal view returns (uint256 price) {
        (, int256 latestPrice, , , ) = priceProvider.latestRoundData();
        price = uint256(latestPrice);
    }
}

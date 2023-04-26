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

contract PriceCalculatorUtilization is IPriceCalculator, Ownable {
    using HegicMath for uint256;

    uint256 public impliedVolRate;
    uint256 internal constant PRICE_DECIMALS = 1e8;
    uint256 internal constant PRICE_MODIFIER_DECIMALS = 1e8;
    uint256 public utilizationRate = 0;
    uint256 public settlementFeeShare = 24;
    AggregatorV3Interface public priceProvider;
    IHegicPool pool;

    constructor(
        uint256 initialRate,
        AggregatorV3Interface _priceProvider,
        IHegicPool _pool
    ) {
        pool = _pool;
        priceProvider = _priceProvider;
        impliedVolRate = initialRate;
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
     * @param value New IVRate value
     **/
    function setSettlementFeeShare(uint256 value) external onlyOwner {
        require(value <= 100, "The value is too large");
        settlementFeeShare = value;
    }

    /**
     * @notice Used for updating utilizationRate value
     * @param value New utilizationRate value
     **/
    function setUtilizationRate(uint256 value) external onlyOwner {
        utilizationRate = value;
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
        require(
            strike == currentPrice,
            "Only ATM options are currently available"
        );
        uint256 total = _calculatePeriodFee(amount, period);
        settlementFee = (total * settlementFeeShare) / 100;
        premium = total - settlementFee;
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
            (amount * _priceModifier(amount, period, pool)) /
            PRICE_DECIMALS /
            PRICE_MODIFIER_DECIMALS;
    }

    /**
     * @notice Calculates `periodFee` of the option
     * @param amount The option size
     * @param period The option period in seconds (1 days <= period <= 90 days)
     **/
    function _priceModifier(
        uint256 amount,
        uint256 period,
        IHegicPool pool
    ) internal view returns (uint256 iv) {
        uint256 poolBalance = pool.totalBalance();
        require(poolBalance > 0, "Pool Error: The pool is empty");
        iv = impliedVolRate * period.sqrt();

        uint256 lockedAmount = pool.lockedAmount() + amount;
        uint256 utilization = (lockedAmount * 100e8) / poolBalance;

        if (utilization > 40e8) {
            iv += (iv * (utilization - 40e8) * utilizationRate) / 40e16;
        }
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

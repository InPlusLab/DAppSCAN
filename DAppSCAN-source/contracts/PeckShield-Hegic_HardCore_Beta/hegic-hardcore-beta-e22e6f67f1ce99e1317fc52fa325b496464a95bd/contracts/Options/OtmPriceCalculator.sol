pragma solidity 0.8.6;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2022 Hegic Protocol
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

contract OtmPriceCalculator is IPremiumCalculator, Ownable {
    using HegicMath for uint256;

    uint256 public impliedVolRate0;
    uint256 public impliedVolRate1;
    uint256 public border = 20;
    uint256 public strikePercentage;
    // uint256 internal immutable priceDecimals;
    uint256 internal constant IVL_DECIMALS = 1e18;
    uint256 public settlementFeeShare = 0;
    uint256 public maxPeriod = 45 days;
    uint256 public minPeriod = 7 days;
    uint8 roundedDecimals;
    AggregatorV3Interface public priceProvider;

    constructor(uint256 initialRate0, uint256 initialRate1, uint256 percentage, AggregatorV3Interface _priceProvider, uint8 _roundedDecimals) {
        priceProvider = _priceProvider;
        impliedVolRate0 = initialRate0;
        impliedVolRate1 = initialRate1;
        strikePercentage = percentage;
        roundedDecimals = _roundedDecimals;
        // priceDecimals = 10**priceProvider.decimals();
    }

    /**
     * @notice Used for setting the period point after which
     * the price will be calculated with a different IVRate
     * @param value The day number of the border
     **/
    function setBorder(uint256 value) external onlyOwner {
        border = value;
    }

    /**
     * @notice Used for setting the strike prices
     * for out-of-the-money options/strategies e.g.
     * 110 = market price + 10% (OTM call option);
     * 90 = market price - 10% (OTM put option)
     * @param value The strike price from the current market price
     **/
    function setStrikePercentage(uint256 value) external onlyOwner {
       strikePercentage = value;
    }

    /**
     * @notice Used for adjusting the options prices (the premiums)
     * while balancing the asset's implied volatility rate.
     * @param value New IVRate value
     **/
    
    function setImpliedVolRate0(uint256 value) external onlyOwner {
        impliedVolRate0 = value;
    }

    /**
     * @notice Used for adjusting the options prices (the premiums)
     * while balancing the asset's implied volatility rate.
     * @param value New IVRate value
     **/
    function setImpliedVolRate1(uint256 value) external onlyOwner {
        impliedVolRate1 = value;
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
     * @return premium The part of the premium that
     * is distributed among the liquidity providers
     **/
    function calculatePremium(
        uint256 period,
        uint256 amount,
        uint256 strike
    ) public view override returns (uint256 premium) {
        uint256 currentPrice = _currentPrice();
        uint256 otmStrike = round(currentPrice * strikePercentage / 100, roundedDecimals);
        // uint256 remainder = otmStrike % 100e8;
        // uint256 roundedStrike;
        // remainder >= 50e8 ?

        // roundedStrike = (otmStrike/1e10+1)*1e10 :
        // roundedStrike = otmStrike/1e10*1e10;

        require(period <= maxPeriod, "PriceCalculator: Period is too long");
        require(period >= minPeriod, "PriceCalculator: Period is too short");

        require(
            strike == otmStrike,
            "invalid strike"
        );
        return _calculatePeriodFee(amount, period, strike);
    }

    function round(uint value, uint8 decimals) public pure returns (uint roundedValue) {
      uint a = value / 10 ** (decimals -1);
      if(a%10 < 5) return a / 10 * 10**decimals;
      return (a / 10 + 1) * 10**decimals;
    }

    function _calculatePeriodFee(uint256 amount, uint256 period, uint256 strike)
        internal
        view
        virtual
        returns (uint256 fee)
    {
      if (period < 86400 * border) {
        return
            (amount * impliedVolRate0 * period.sqrt()) /
            IVL_DECIMALS;
      } else {
        return
            ( amount * impliedVolRate1 * period.sqrt()) /
            IVL_DECIMALS;
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

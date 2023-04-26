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

import "./HegicStrategy.sol";
import "../Interfaces/Interfaces.sol";

contract HegicStrategyStrip is HegicStrategy {
    // uint256 private immutable spotDecimals; // 1e18
    uint256 private constant TOKEN_DECIMALS = 1e6; // 1e6

    constructor(
        IHegicOperationalTreasury _pool,
        AggregatorV3Interface _priceProvider,
        IPremiumCalculator _pricer,
        uint8 _spotDecimals,
        uint256 limit
    ) HegicStrategy(_pool, _priceProvider, _pricer, 10, limit, _spotDecimals) {
    }

    function _profitOf(uint256 optionID)
        internal
        view
        override
        returns (uint256 amount)
    {
        StrategyData memory data = strategyData[optionID];
        uint256 currentPrice = _currentPrice();
        if (currentPrice > data.strike) {
            return _profitOfCall(data);
        } else if (currentPrice < data.strike) {
            return _profitOfPut(data);
        }
        return 0;
    }

    function _profitOfPut(StrategyData memory data)
        internal
        view
        returns (uint256 amount)
    {
        uint256 currentPrice = _currentPrice();
        return
            ((data.strike - currentPrice) *
                (2 * data.amount) *
                TOKEN_DECIMALS) /
            spotDecimals /
            1e8;
    }

    function _profitOfCall(StrategyData memory data)
        internal
        view
        returns (uint256 amount)
    {
        uint256 currentPrice = _currentPrice();
        return
            ((currentPrice - data.strike) * data.amount * TOKEN_DECIMALS) /
            spotDecimals /
            1e8;
    }

}

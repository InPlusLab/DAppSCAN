pragma solidity 0.8.6;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2021 Hegic
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

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract PriceProviderInvertor is AggregatorV3Interface {
    // string public override description = "Test implementatiln";
    // uint256 public override version = 0;
    AggregatorV3Interface rawPricer;

    constructor(AggregatorV3Interface _rawPricer) {
        rawPricer = _rawPricer;
    }

    function decimals() external view override returns (uint8) {
        return rawPricer.decimals();
    }

    function description() external view override returns (string memory) {
        return rawPricer.description();
    }

    function version() external view override returns (uint256) {
        return rawPricer.version();
    }

    function getRoundData(uint80 i)
        external
        view
        override
        returns (
            uint80 x1,
            int256 price,
            uint256 x2,
            uint256 x3,
            uint80 x4
        )
    {
        (x1, price, x2, x3, x4) = rawPricer.getRoundData(i);
        price = int256(10**(rawPricer.decimals() * 2)) / price;
    }

    function latestAnswer() external view returns (int256 result) {
        (, result, , , ) = latestRoundData();
    }

    function latestRoundData()
        public
        view
        override
        returns (
            uint80 x1,
            int256 answer,
            uint256 x2,
            uint256 x3,
            uint80 x4
        )
    {
        (x1, answer, x2, x3, x4) = rawPricer.latestRoundData();
        answer = int256(10**(rawPricer.decimals() * 2)) / answer;
    }
}

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

contract PriceProviderMock is AggregatorV3Interface {
    uint256 public price;
    uint8 public override decimals = 8;
    string public override description = "Test implementatiln";
    uint256 public override version = 0;

    constructor(uint256 _price) {
        price = _price;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function getRoundData(uint80)
        external
        pure
        override
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        revert("Test implementation");
    }

    function latestAnswer() external view returns (int256 result) {
        (, result, , , ) = latestRoundData();
    }

    function latestRoundData()
        public
        view
        override
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        )
    {
        answer = int256(price);
        return (0, answer, 0, 0, 0);
    }
}

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

import "./HegicPool.sol";

/**
 * @author 0mllwntrmt3
 * @title Hegic Protocol V8888 Call Liquidity Pool Contract
 * @notice The Call Liquidity Pool Contract
 **/
contract HegicCALL is HegicPool {
    /**
     * @param name The pool contract name
     * @param symbol The pool ticker for the ERC721 options
     **/
    constructor(
        IERC20 _token,
        string memory name,
        string memory symbol,
        IOptionsManager manager,
        IPriceCalculator _pricer,
        IHegicStaking _settlementFeeRecipient,
        AggregatorV3Interface _priceProvider
    )
        HegicPool(
            _token,
            name,
            symbol,
            manager,
            _pricer,
            _settlementFeeRecipient,
            _priceProvider
        )
    {}

    function _profitOf(Option memory option)
        internal
        view
        override
        returns (uint256 amount)
    {
        uint256 currentPrice = _currentPrice();
        if (currentPrice < option.strike) return 0;
        return ((currentPrice - option.strike) * option.amount) / currentPrice;
    }
}

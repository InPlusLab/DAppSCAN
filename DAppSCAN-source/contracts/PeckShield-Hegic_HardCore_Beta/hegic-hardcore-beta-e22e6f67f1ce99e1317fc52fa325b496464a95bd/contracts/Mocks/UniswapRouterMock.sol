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

import "./ERC20Mock.sol";
import "@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";

contract UniswapRouterMock {
    ERC20Mock public immutable WBTC;
    ERC20Mock public immutable USDC;
    AggregatorV3Interface public immutable WBTCPriceProvider;
    AggregatorV3Interface public immutable ETHPriceProvider;

    constructor(
        ERC20Mock _wbtc,
        ERC20Mock _usdc,
        AggregatorV3Interface wpp,
        AggregatorV3Interface epp
    ) {
        WBTC = _wbtc;
        USDC = _usdc;
        WBTCPriceProvider = wpp;
        ETHPriceProvider = epp;
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external payable returns (uint256[] memory amounts) {
        require(path.length == 2, "UniswapMock: wrong path");
        require(
            path[1] == address(USDC) || path[1] == address(WBTC),
            "UniswapMock: too small value"
        );
        amounts = getAmountsIn(amountOut, path);
        require(msg.value >= amounts[0], "UniswapMock: too small value");
        if (msg.value > amounts[0])
            payable(msg.sender).transfer(msg.value - amounts[0]);
        ERC20Mock(path[1]).mintTo(to, amountOut);
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        public
        view
        returns (uint256[] memory amounts)
    {
        require(path.length == 2, "UniswapMock: wrong path");
        uint256 amount;
        if (path[1] == address(USDC)) {
            (, int256 ethPrice, , , ) = ETHPriceProvider.latestRoundData();
            amount = (amountOut * 1e8) / uint256(ethPrice);
        } else if (path[1] == address(WBTC)) {
            (, int256 ethPrice, , , ) = ETHPriceProvider.latestRoundData();
            (, int256 wbtcPrice, , , ) = WBTCPriceProvider.latestRoundData();
            amount = (amountOut * uint256(wbtcPrice)) / uint256(ethPrice);
        } else {
            revert("UniswapMock: wrong path");
        }
        amounts = new uint256[](2);
        amounts[0] = (amount * 103) / 100;
        amounts[1] = amountOut;
    }
}

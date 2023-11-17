// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {SafeMath} from '../utils/math/SafeMath.sol';
import {ISimpleOracle} from './ISimpleOracle.sol';
import {IChainlinkOracle} from './IChainlinkOracle.sol';
import {AggregatorV3Interface} from './AggregatorV3Interface.sol';

contract ChainlinkETHUSDPriceConsumer is IChainlinkOracle {
    using SafeMath for uint256;

    /**
     * State variables.
     */

    ISimpleOracle public gmuOracle;
    AggregatorV3Interface internal priceFeed;

    uint256 public priceFeedDecimals = 8;

    /**
     * Constructor.
     */
    constructor(address priceFeed_, ISimpleOracle gmuOracle_) {
        priceFeed = AggregatorV3Interface(priceFeed_);

        gmuOracle = gmuOracle_;
        priceFeedDecimals = priceFeed.decimals();
    }

    /**
     * Publics.
     */

    function getGmuPrice() public view override returns (uint256) {
        // Considering that gmuOracle uses 1e18 as precision.

        uint256 decimalsDiff = uint256(18).sub(priceFeedDecimals);

        return gmuOracle.getPrice().div(10**decimalsDiff);
    }

    function getLatestUSDPrice() public view override returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return uint256(price);
    }

    function getLatestPrice() public view override returns (uint256) {
        return
            getLatestUSDPrice().mul(getGmuPrice()).div(10**priceFeedDecimals);
    }

    function getDecimals() public view override returns (uint8) {
        return priceFeed.decimals();
    }
}

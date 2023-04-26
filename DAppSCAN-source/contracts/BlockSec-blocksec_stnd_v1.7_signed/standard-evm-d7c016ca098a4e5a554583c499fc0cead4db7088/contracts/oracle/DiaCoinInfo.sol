// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./DiaCoinInfoInterface.sol";
import "./interfaces/IPrice.sol";

contract DiaCoinInfo is IPrice {
    DiaCoinInfoInterface internal priceFeed;

    string public name;

    constructor(address _aggregator, string memory _name) public {
        priceFeed = DiaCoinInfoInterface(_aggregator);
        name = _name;
    }

    /**
     * Returns the latest price
     */
    function getThePrice() external view override returns (int256) {
        (
            uint256 price,
            uint256 supply,
            uint256 lastUpdateTimeStamp,
            string memory symbol
        ) = priceFeed.getCoinInfo(name);
        return int256(price);
    }
}

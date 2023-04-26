// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Operator.sol";
import "../interfaces/IOracle.sol";

contract WBNBOracle is Operator, IOracle {
    using SafeMath for uint256;
    address public chainlinkWbnbUsd;

    uint256 private constant PRICE_PRECISION = 1e6;

    constructor(address _chainlinkWbnbUsd) public {
        chainlinkWbnbUsd = _chainlinkWbnbUsd;
    }

    function consult() external view override returns (uint256) {
        AggregatorV3Interface _priceFeed = AggregatorV3Interface(chainlinkWbnbUsd);
        (, int256 _price, , , ) = _priceFeed.latestRoundData();
        uint8 _decimals = _priceFeed.decimals();
        return uint256(_price).mul(PRICE_PRECISION).div(uint256(10)**_decimals);
    }

    function setChainlinkWbnbUsd(address _chainlinkWbnbUsd) external onlyOperator {
        chainlinkWbnbUsd = _chainlinkWbnbUsd;
    }
}

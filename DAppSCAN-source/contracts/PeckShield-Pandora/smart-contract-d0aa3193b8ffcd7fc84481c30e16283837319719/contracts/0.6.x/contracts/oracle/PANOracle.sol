// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Operator.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IPairOracle.sol";

contract PANOracle is Operator, IOracle {
    using SafeMath for uint256;
    address public oraclePANBusd;
    address public oracleBusdUsd;
    address public PAN;

    uint256 private constant PRICE_PRECISION = 1e6;

    constructor(
        address _PAN,
        address _oraclePANBusd,
        address _oracleBusdUsd
    ) public {
        PAN = _PAN;
        oraclePANBusd = _oraclePANBusd;
        oracleBusdUsd = _oracleBusdUsd;
    }

    function consult() external view override returns (uint256) {
        uint256 _priceBusdUsd = IOracle(oracleBusdUsd).consult();
        uint256 _pricePANBusd = IPairOracle(oraclePANBusd).consult(PAN, PRICE_PRECISION);
        return _priceBusdUsd.mul(_pricePANBusd).div(PRICE_PRECISION);
    }

    function setOracleBusdUsd(address _oracleBusdUsd) external onlyOperator {
        oracleBusdUsd = _oracleBusdUsd;
    }

    function setOraclePANBusd(address _oraclePANBusd) external onlyOperator {
        oraclePANBusd = _oraclePANBusd;
    }
}

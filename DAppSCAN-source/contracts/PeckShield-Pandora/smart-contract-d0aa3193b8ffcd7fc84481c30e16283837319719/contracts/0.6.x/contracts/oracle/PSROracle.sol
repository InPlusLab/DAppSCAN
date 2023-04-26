// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Operator.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IPairOracle.sol";

contract PSROracle is Operator, IOracle {
    using SafeMath for uint256;
    address public oraclePSRBusd;
    address public oracleBusdUsd;
    address public PSR;

    uint256 private constant PRICE_PRECISION = 1e6;

    constructor(
        address _PSR,
        address _oraclePSRBusd,
        address _oracleBusdUsd
    ) public {
        PSR = _PSR;
        oracleBusdUsd = _oracleBusdUsd;
        oraclePSRBusd = _oraclePSRBusd;
    }

    function consult() external view override returns (uint256) {
        uint256 _priceBusdUsd = IOracle(oracleBusdUsd).consult();
        uint256 _pricePSRBusd = IPairOracle(oraclePSRBusd).consult(PSR, PRICE_PRECISION);
        return _priceBusdUsd.mul(_pricePSRBusd).div(PRICE_PRECISION);
    }

    function setOracleBusdUsd(address _oracleBusdUsd) external onlyOperator {
        oracleBusdUsd = _oracleBusdUsd;
    }

    function setOraclePSRBusd(address _oraclePSRBusd) external onlyOperator {
        oraclePSRBusd = _oraclePSRBusd;
    }
}

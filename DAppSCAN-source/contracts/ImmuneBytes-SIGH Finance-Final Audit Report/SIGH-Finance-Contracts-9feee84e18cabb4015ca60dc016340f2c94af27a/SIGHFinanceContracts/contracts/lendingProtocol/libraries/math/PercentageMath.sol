// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

/**
 * @title PercentageMath library
 * @author Aave
 * @notice Provides functions to perform percentage calculations
 * @dev Percentages are defined by default with 2 decimals of precision (100.00). The precision is indicated by PERCENTAGE_FACTOR
 * @dev Operations are rounded half up
 **/

library PercentageMath {
    uint256 constant PERCENTAGE_FACTOR = 1e4; //percentage plus two decimals
    uint256 constant HALF_PERCENT = PERCENTAGE_FACTOR / 2;

    /**
    * @dev Executes a percentage multiplication
    * @param value The value of which the percentage needs to be calculated
    * @param percentage The percentage of the value to be calculated
    * @return The percentage of value
    **/
    function percentMul(uint256 value, uint256 percentage) internal pure returns (uint256) {
        if (value == 0 || percentage == 0) {
            return 0;
        }

        require(value <= (type(uint256).max - HALF_PERCENT) / percentage, "Percentage Math : Multiplication error" );
        return (value * percentage + HALF_PERCENT) / PERCENTAGE_FACTOR;
    }

    /**
    * @dev Executes a percentage division
    * @param value The value of which the percentage needs to be calculated
    * @param percentage The percentage of the value to be calculated
    * @return The value divided the percentage
    **/
    function percentDiv(uint256 value, uint256 percentage) internal pure returns (uint256) {
        require(percentage != 0, "MATH DIVISION BY ZERO");
        uint256 halfPercentage = percentage / 2;

        require( value <= (type(uint256).max - halfPercentage) / PERCENTAGE_FACTOR, "Percentage Math : Division error" );
        return (value * PERCENTAGE_FACTOR + halfPercentage) / percentage;
    }
}
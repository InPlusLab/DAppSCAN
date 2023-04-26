// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

/**
 * @title ILendingRateOracle interface
 * @notice Interface for the SIGH Finance's borrow rate oracle.
 * Provides the average market borrow rate to be used as a base for the stable borrow rate calculations
 **/

interface ILendingRateOracle {

  /**
    @dev returns the market borrow rate in ray (1 Ray = 1e27)
    **/
  function getMarketBorrowRate(address asset) external view returns (uint256);

  /**
    @dev sets the market borrow rate. Rate value must be in ray (1 Ray = 1e27)
    **/
  function setMarketBorrowRate(address asset, uint256 rate) external;
}
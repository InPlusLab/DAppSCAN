// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

interface InterestModel {
  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);

  function CEIL_SLOPE_1() external view returns (uint256);

  function CEIL_SLOPE_2() external view returns (uint256);

  function CEIL_SLOPE_3() external view returns (uint256);

  function MAX_INTEREST_SLOPE_1() external view returns (uint256);

  function MAX_INTEREST_SLOPE_2() external view returns (uint256);

  function MAX_INTEREST_SLOPE_3() external view returns (uint256);
}

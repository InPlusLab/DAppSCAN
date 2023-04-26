// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

interface ITripleSlopeModel {
  // Return Utilization.
  function getUtilization(uint256 debt, uint256 floating) external pure returns (uint256);

  // Return the interest rate per year.
  function getInterestRate(
    uint256 debt,
    uint256 floating,
    uint8 decimals
  ) external view returns (uint256);

  function CEIL_SLOPE_1() external view returns (uint256);

  function CEIL_SLOPE_2() external view returns (uint256);

  function CEIL_SLOPE_3() external view returns (uint256);

  function MAX_INTEREST_SLOPE_1() external view returns (uint256);

  function MAX_INTEREST_SLOPE_2() external view returns (uint256);

  function MAX_INTEREST_SLOPE_3() external view returns (uint256);
}

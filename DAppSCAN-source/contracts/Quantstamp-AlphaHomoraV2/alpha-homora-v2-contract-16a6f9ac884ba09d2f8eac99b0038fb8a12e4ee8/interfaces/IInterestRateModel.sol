pragma solidity 0.6.12;

interface IInterestRateModel {
  /// @dev Return the interest rate per year in basis point given the parameters.
  /// @param token The token address to query for interest rate.
  /// @param supply The current total supply value from lenders.
  /// @param borrow The current total borrow value from borrowers.
  /// @param reserve The current unwithdrawn reserve funds.
  function getBorrowRate(
    address token,
    uint supply,
    uint borrow,
    uint reserve
  ) external view returns (uint);
}

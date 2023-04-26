pragma solidity 0.5.11;

interface WhitePaperInterestRateModel {
  function getBorrowRate(uint256 cash, uint256 borrows, uint256 _reserves) external view returns (uint256, uint256);
  function multiplier() external view returns (uint256);
  function baseRate() external view returns (uint256);
  function blocksPerYear() external view returns (uint256);
}

pragma solidity 0.5.11;
import "../interfaces/WhitePaperInterestRateModel.sol";

contract WhitePaperMock is WhitePaperInterestRateModel {
  uint256 public borrowRate;
  uint256 public baseRate;
  uint256 public multiplier;
  uint256 public blocksPerYear;
  constructor() public {
    baseRate = 50000000000000000;
    multiplier = 120000000000000000;
    blocksPerYear = 2102400;
  }
  function getBorrowRate(uint256 cash, uint256 borrows, uint256 _reserves) external view returns (uint256, uint256) {

  }
}

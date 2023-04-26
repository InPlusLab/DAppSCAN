// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TripleSlopeModel is Ownable {
  using SafeMath for uint256;

  uint256 public CEIL_SLOPE_1;
  uint256 public CEIL_SLOPE_2;
  uint256 public CEIL_SLOPE_3;

  uint256 public MAX_INTEREST_SLOPE_1;
  uint256 public MAX_INTEREST_SLOPE_2;
  uint256 public MAX_INTEREST_SLOPE_3;

  constructor(
    uint256 _ceil_1,
    uint256 _ceil_2,
    uint256 _ceil_3,
    uint256 _max_Interest_1,
    uint256 _max_Interest_2,
    uint256 _max_Interest_3
  ) public {
    setParams(_ceil_1, _ceil_2, _ceil_3, _max_Interest_1, _max_Interest_2, _max_Interest_3);
  }

  function setParams(
    uint256 _ceil_1,
    uint256 _ceil_2,
    uint256 _ceil_3,
    uint256 _max_Interest_1,
    uint256 _max_Interest_2,
    uint256 _max_Interest_3
  ) public onlyOwner {
    CEIL_SLOPE_1 = _ceil_1;
    CEIL_SLOPE_2 = _ceil_2;
    CEIL_SLOPE_3 = _ceil_3;
    MAX_INTEREST_SLOPE_1 = _max_Interest_1;
    MAX_INTEREST_SLOPE_2 = _max_Interest_2;
    MAX_INTEREST_SLOPE_3 = _max_Interest_3;
  }

  // Return Utilization.
  function getUtilization(uint256 debt, uint256 floating) external pure returns (uint256) {
    if (debt == 0 && floating == 0) return 0;

    uint256 total = debt.add(floating);
    uint256 utilization = debt.mul(10000).div(total);
    return utilization;
  }

  // Return the interest rate per year.
  function getInterestRate(
    uint256 debt,
    uint256 floating,
    uint8 decimals
  ) external view returns (uint256) {
    if (debt == 0 && floating == 0) return 0;

    uint256 total = debt.add(floating);
    uint256 utilization = debt.mul(10000).div(total);
    uint256 interest1 = MAX_INTEREST_SLOPE_1.mul(10**uint256(decimals - 2));
    uint256 interest2 = MAX_INTEREST_SLOPE_2.mul(10**uint256(decimals - 2));
    uint256 interest3 = MAX_INTEREST_SLOPE_3.mul(10**uint256(decimals - 2));

    if (utilization < CEIL_SLOPE_1) {
      // Less than 50% utilization - 0%-25% APY
      return utilization.mul(interest1).div(CEIL_SLOPE_1).mul(1e18);
    } else if (utilization < CEIL_SLOPE_2) {
      // Between 50% and 90% - 25% APY
      return interest2.mul(1e18);
    } else if (utilization < CEIL_SLOPE_3) {
      // Between 90% and 100% - 25%-100% APY
      return
        ((interest2) +
          (utilization.sub(CEIL_SLOPE_2).mul((interest3.sub(interest2)).div(CEIL_SLOPE_3.sub(CEIL_SLOPE_2))))).mul(
            1e18
          );
    } else {
      // Not possible, but just in case - 100% APY
      return interest3.mul(1e18);
    }
  }
}

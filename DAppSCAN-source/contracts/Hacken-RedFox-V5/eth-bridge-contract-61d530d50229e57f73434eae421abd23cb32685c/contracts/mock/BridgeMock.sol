pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../ETHWAXBRIDGE.sol";

contract BridgeMock is ETHWAXBRIDGE {
  constructor(IERC20 rfoxAddress) public ETHWAXBRIDGE(rfoxAddress){}

  function testOnlyOracleModifier() external view onlyOracle returns (uint256) {
    return 0;
  }

  function addTotalLocked(uint256 amount) external {
    totalLocked = totalLocked.add(amount);
  }

  function internalRelease(address to, uint256 amount) external {
    release(to, amount);
  }
}
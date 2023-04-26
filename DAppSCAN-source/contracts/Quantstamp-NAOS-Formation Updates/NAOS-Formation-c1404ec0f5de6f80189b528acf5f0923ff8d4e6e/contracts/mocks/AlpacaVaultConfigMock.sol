// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

contract AlpacaVaultConfigMock {
  function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256) {
    return 1;
  }

  function getReservePoolBps() external view returns (uint256) {
    return 1;
  }
}
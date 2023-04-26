// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IVaultFarm {
  function syncDeposit(address _user, uint256 _amount, address asset) external;
  function syncWithdraw(address _user, uint256 _amount, address asset) external;
  function syncLiquidate(address _user, address asset) external;

}
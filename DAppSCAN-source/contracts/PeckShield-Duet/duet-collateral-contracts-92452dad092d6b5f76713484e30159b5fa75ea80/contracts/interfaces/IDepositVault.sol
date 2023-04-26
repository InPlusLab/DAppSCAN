// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IDepositVault {

  function deposits(address user) external view returns(uint amount);
  function deposit(address dtoken, uint256 amount) external;
  function depositTo(address dtoken, address to, uint256 amount) external;
  function syncDeposit(address dtoken, uint256 amount, address user) external;

  function withdraw(uint256 amount, bool unpack) external;
  function withdrawTo(address to, uint256 amount, bool unpack) external;

}
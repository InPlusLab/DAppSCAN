// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWETH {
  function approve(address, uint256) external;

  function deposit() external payable;

  function withdraw(uint256) external;
}

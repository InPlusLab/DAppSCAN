// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IDRewards {
  function earned(address account) external view returns (uint256);
}

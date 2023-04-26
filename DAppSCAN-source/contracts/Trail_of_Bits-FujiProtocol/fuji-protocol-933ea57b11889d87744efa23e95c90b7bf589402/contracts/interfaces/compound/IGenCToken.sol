// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGenCToken is IERC20 {
  function redeem(uint256) external returns (uint256);

  function redeemUnderlying(uint256) external returns (uint256);

  function borrow(uint256 borrowAmount) external returns (uint256);

  function exchangeRateCurrent() external returns (uint256);

  function exchangeRateStored() external view returns (uint256);

  function borrowRatePerBlock() external view returns (uint256);

  function balanceOfUnderlying(address owner) external returns (uint256);

  function borrowBalanceCurrent(address account) external returns (uint256);

  function borrowBalanceStored(address account) external view returns (uint256);
}

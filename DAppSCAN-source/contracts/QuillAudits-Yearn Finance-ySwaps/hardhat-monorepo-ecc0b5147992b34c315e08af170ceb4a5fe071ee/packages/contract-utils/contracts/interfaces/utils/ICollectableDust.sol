// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface ICollectableDust {
  event DustSent(address _to, address token, uint256 amount);

  function sendDust(
    address _to,
    address _token,
    uint256 _amount
  ) external;
}

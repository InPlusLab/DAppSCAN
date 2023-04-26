// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICFlashloanReceiver {
  function onFlashLoan(
    address sender,
    address underlying,
    uint256 amount,
    uint256 fee,
    bytes calldata params
  ) external returns (bytes32);
}

//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILiquidateCallee {
  function liquidateDeposit(address borrower, address underlying, uint amount, bytes calldata data) external;
  function liquidateBorrow(address borrower, address underlying, uint amount, bytes calldata data) external;
}
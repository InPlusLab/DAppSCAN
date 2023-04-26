// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

library CommonErrors {
  error ZeroAddress();
  error NotAuthorized();
  error ZeroAmount();
  error ZeroSlippage();
  error IncorrectSwapInformation();
}

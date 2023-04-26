// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import './Keep3rEscrowParameters.sol';

interface IKeep3rEscrowCreditsHandler {
  event AppliedCreditToJob(address _provider, address _liquidity, address _job);

  function applyCreditToJob(
    address _provider,
    address _liquidity,
    address _job
  ) external;
}

abstract contract Keep3rEscrowCreditsHandler is Keep3rEscrowParameters, IKeep3rEscrowCreditsHandler {
  function _applyCreditToJob(
    address _provider,
    address _liquidity,
    address _job
  ) internal {
    keep3rV1.applyCreditToJob(_provider, _liquidity, _job);
    emit AppliedCreditToJob(_provider, _liquidity, _job);
  }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '../../../keep3r/escrow/Keep3rEscrowCreditsHandler.sol';
import './Keep3rEscrowParameters.sol';

contract Keep3rEscrowCreditsHandlerMock is Keep3rEscrowCreditsHandler, Keep3rEscrowParametersMock {
  constructor(
    address _governance,
    IKeep3rV1 _keep3r,
    IERC20 _lpToken
  ) public Keep3rEscrowParametersMock(_governance, _keep3r, _lpToken) {}

  function applyCreditToJob(
    address _provider,
    address _liquidity,
    address _job
  ) public override {
    _applyCreditToJob(_provider, _liquidity, _job);
  }
}

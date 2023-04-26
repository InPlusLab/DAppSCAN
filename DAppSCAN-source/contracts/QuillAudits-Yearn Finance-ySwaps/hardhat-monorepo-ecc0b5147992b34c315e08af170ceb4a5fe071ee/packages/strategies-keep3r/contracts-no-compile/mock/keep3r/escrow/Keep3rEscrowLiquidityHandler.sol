// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '../../../keep3r/escrow/Keep3rEscrowLiquidityHandler.sol';
import './Keep3rEscrowParameters.sol';

contract Keep3rEscrowLiquidityHandlerMock is Keep3rEscrowLiquidityHandler, Keep3rEscrowParametersMock {
  constructor(
    address _governance,
    IKeep3rV1 _keep3r,
    IERC20 _lpToken
  ) public Keep3rEscrowParametersMock(_governance, _keep3r, _lpToken) {}

  function addLiquidityToJob(
    address _liquidity,
    address _job,
    uint256 _amount
  ) public override {
    _addLiquidityToJob(_liquidity, _job, _amount);
  }

  function removeLiquidityFromJob(address _liquidity, address _job) public override {
    _removeLiquidityFromJob(_liquidity, _job);
  }

  function unbondLiquidityFromJob(
    address _liquidity,
    address _job,
    uint256 _amount
  ) public override {
    _unbondLiquidityFromJob(_liquidity, _job, _amount);
  }
}

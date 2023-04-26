// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import './Keep3rEscrowParameters.sol';

interface IKeep3rEscrowLiquidityHandler {
  event LiquidityAddedToJob(address _liquidity, address _job, uint256 _amount);
  event LiquidityRemovedFromJob(address _liquidity, address _job);
  event LiquidityUnbondedFromJob(address _liquidity, address _job, uint256 _amount);

  function addLiquidityToJob(
    address _liquidity,
    address _job,
    uint256 _amount
  ) external;

  function removeLiquidityFromJob(address _liquidity, address _job) external;

  function unbondLiquidityFromJob(
    address _liquidity,
    address _job,
    uint256 _amount
  ) external;
}

abstract contract Keep3rEscrowLiquidityHandler is Keep3rEscrowParameters, IKeep3rEscrowLiquidityHandler {
  function _addLiquidityToJob(
    address _liquidity,
    address _job,
    uint256 _amount
  ) internal {
    lpToken.approve(address(keep3rV1), _amount);
    keep3rV1.addLiquidityToJob(_liquidity, _job, _amount);
  }

  function _removeLiquidityFromJob(address _liquidity, address _job) internal {
    keep3rV1.removeLiquidityFromJob(_liquidity, _job);
  }

  function _unbondLiquidityFromJob(
    address _liquidity,
    address _job,
    uint256 _amount
  ) internal {
    keep3rV1.unbondLiquidityFromJob(_liquidity, _job, _amount);
  }
}

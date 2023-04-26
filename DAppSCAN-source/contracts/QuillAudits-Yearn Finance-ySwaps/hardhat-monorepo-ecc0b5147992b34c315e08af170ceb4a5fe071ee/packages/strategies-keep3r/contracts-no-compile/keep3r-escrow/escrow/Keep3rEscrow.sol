// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@yearn/contract-utils/contracts/abstract/UtilsReady.sol';

import './Keep3rEscrowParameters.sol';
import './Keep3rEscrowMetadata.sol';
import './Keep3rEscrowLiquidityHandler.sol';
import './Keep3rEscrowCreditsHandler.sol';

interface IKeep3rEscrow is IKeep3rEscrowParameters, IKeep3rEscrowMetadata, IKeep3rEscrowLiquidityHandler, IKeep3rEscrowCreditsHandler {}

contract Keep3rEscrow is
  UtilsReady,
  Keep3rEscrowParameters,
  Keep3rEscrowMetadata,
  Keep3rEscrowLiquidityHandler,
  Keep3rEscrowCreditsHandler,
  IKeep3rEscrow
{
  constructor(
    address _governance,
    IKeep3rV1 _keep3r,
    IERC20 _lpToken
  ) public Keep3rEscrowParameters(_governance, _keep3r, _lpToken) UtilsReady() {
    _addProtocolToken(address(_lpToken));
  }

  // Liquidity Handler
  function addLiquidityToJob(
    address _liquidity,
    address _job,
    uint256 _amount
  ) external override onlyGovernor {
    _addLiquidityToJob(_liquidity, _job, _amount);
  }

  function removeLiquidityFromJob(address _liquidity, address _job) external override onlyGovernor {
    _removeLiquidityFromJob(_liquidity, _job);
  }

  function unbondLiquidityFromJob(
    address _liquidity,
    address _job,
    uint256 _amount
  ) external override onlyGovernor {
    _unbondLiquidityFromJob(_liquidity, _job, _amount);
  }

  // Credits Handler
  function applyCreditToJob(
    address _provider,
    address _liquidity,
    address _job
  ) external override onlyGovernor {
    _applyCreditToJob(_provider, _liquidity, _job);
  }

  // Parameters
  function returnLPsToGovernance() external override onlyGovernor {
    _returnLPsToGovernance();
  }

  function setGovernance(address _governance) external override onlyGovernor {
    _setGovernance(_governance);
  }

  function setKeep3rV1(IKeep3rV1 _keep3rV1) external override onlyGovernor {
    _setKeep3rV1(_keep3rV1);
  }

  function setLPToken(IERC20 _lpToken) external override onlyGovernor {
    _setLPToken(_lpToken);
  }
}

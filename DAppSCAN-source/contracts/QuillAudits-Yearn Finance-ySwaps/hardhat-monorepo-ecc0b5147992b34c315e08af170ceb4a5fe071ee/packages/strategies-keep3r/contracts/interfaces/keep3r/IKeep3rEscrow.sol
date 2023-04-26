// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@yearn/contract-utils/contracts/interfaces/abstract/IUtilsReady.sol';

interface IKeep3rEscrow is IUtilsReady {
  function returnLPsToGovernance() external;

  function addLiquidityToJob(
    address liquidity,
    address job,
    uint256 amount
  ) external;

  function applyCreditToJob(
    address provider,
    address liquidity,
    address job
  ) external;

  function unbondLiquidityFromJob(
    address liquidity,
    address job,
    uint256 amount
  ) external;

  function removeLiquidityFromJob(address liquidity, address job) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@yearn/contract-utils/contracts/interfaces/abstract/IUtilsReady.sol';

interface IUniquoteKeep3rEscrow is IUtilsReady {
  function governance() external view returns (address _governance);

  function keep3rV1() external view returns (address _keep3rV1);

  function lpToken() external view returns (address _lpToken);

  function job() external view returns (address _job);

  function keeper() external view returns (address _keeper);

  function returnLPsToGovernance() external;

  function addLiquidityToJob() external;

  function applyCreditToJob() external;

  function unbondLiquidityFromJob() external;

  function removeLiquidityFromJob() external;
}

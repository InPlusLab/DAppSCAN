// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.5;

interface IProposalIncentivesExecutor {
  function execute(
    address[6] memory aTokenImplementations,
    address[6] memory variableDebtImplementation
  ) external;
}

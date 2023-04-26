// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.7.0;

/* solium-disable security/no-block-members */
interface PeriodicPrizeStrategyListener {
  function afterDistributeAwards(uint256 randomNumber, uint256 prizePeriodStartedAt) external;
}

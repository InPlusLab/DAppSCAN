// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

/**
 * @dev Interface used by Unicrypt token locker/vester for premature unlock condition
 */
interface IUnlockCondition {
  function unlockTokens() external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8;
import '../IKeep3rJob.sol';

interface IV2QueueKeep3rJob is IKeep3rJob {
  // event Keep3rSet(address keep3r);

  // Setters
  event StrategyAdded(address _strategy);
  event StrategyRemoved(address _strategy);

  // Actions by Keeper
  event Worked(address _strategy, address _keeper, uint256 _credits);

  // Actions forced by governor
  event ForceWorked(address _strategy);

  // Getters
  function fastGasOracle() external view returns (address _fastGasOracle);

  function strategies() external view returns (address[] memory);

  function strategyQueueList(address _strategy) external view returns (address[] memory _strategies);

  function workable(address _strategy) external view returns (bool);

  // Setters
  function setV2Keep3r(address _v2Keeper) external;

  function setFastGasOracle(address _fastGasOracle) external;

  function setWorkCooldown(uint256 _workCooldown) external;

  function setStrategy(
    address _strategy,
    address[] calldata _strategies,
    uint256[] calldata _requiredAmounts
  ) external;

  function removeStrategy(address _strategy) external;

  // Keeper actions
  function work(address _strategy) external returns (uint256 _credits);

  // Mechanics keeper bypass
  function forceWork(address _strategy) external;

  function forceWorkUnsafe(address _strategy) external;
}

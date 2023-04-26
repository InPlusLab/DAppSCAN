// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IV2DetachedJob {
  error MultiplierExceedsMax();
  error NotZero();
  error StrategyAlreadyAdded();
  error StrategyNotAdded();
  error RequiredAmountsDifferentLength();
  error NotWorkable();

  // Setters
  event StrategyAdded(address _strategy, uint256 _requiredAmount);
  event StrategyModified(address _strategy, uint256 _requiredAmount);
  event StrategyRemoved(address _strategy);

  // Actions by Keeper
  event Worked(address _strategy, address _keeper);

  // Actions forced by governor
  event ForceWorked(address _strategy);

  // Getters
  function v2Keeper() external view returns (address _v2Keeper);

  function strategies() external view returns (address[] memory);

  function workable(address _strategy) external view returns (bool);

  // Setters
  function setV2Keep3r(address _v2Keeper) external;

  function setYOracle(address _v2Keeper) external;

  function setWorkCooldown(uint256 _workCooldown) external;

  function addStrategies(
    address[] calldata _strategy,
    uint256[] calldata _requiredAmount,
    address[] calldata _costTokens,
    address[] calldata _costPairs
  ) external;

  function addStrategy(
    address _strategy,
    uint256 _requiredAmount,
    address _costToken,
    address _costPair
  ) external;

  function updateRequiredAmounts(address[] calldata _strategies, uint256[] calldata _requiredAmounts) external;

  function updateRequiredAmount(address _strategy, uint256 _requiredAmount) external;

  function updateCostTokenAndPair(
    address _strategy,
    address _costToken,
    address _costPair
  ) external;

  function removeStrategy(address _strategy) external;

  // Keeper actions
  function work(address _strategy) external;

  // Mechanics keeper bypass
  function forceWork(address _strategy) external;
}

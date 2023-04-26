// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import './IStrategyKeep3r.sol';

interface IDforceStrategyKeep3r is IStrategyKeep3r {
  event StrategyAdded(address _strategy, uint256 _requiredHarvest);
  event StrategyModified(address _strategy, uint256 _requiredHarvest);
  event StrategyRemoved(address _strategy);

  function isDforceStrategyKeep3r() external pure returns (bool);

  // Setters
  function addStrategy(address _strategy, uint256 _requiredHarvest) external;

  function updateRequiredHarvestAmount(address _strategy, uint256 _requiredHarvest) external;

  function removeStrategy(address _strategy) external;

  // Getters
  function strategies() external view returns (address[] memory _strategies);

  function calculateHarvest(address _strategy) external view returns (uint256 _amount);

  function workable(address _strategy) external view returns (bool);
}

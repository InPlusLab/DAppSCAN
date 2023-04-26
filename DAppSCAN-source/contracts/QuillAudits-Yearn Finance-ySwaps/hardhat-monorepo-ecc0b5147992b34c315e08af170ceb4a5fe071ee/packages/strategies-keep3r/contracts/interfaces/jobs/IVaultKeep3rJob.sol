// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './IKeep3rJob.sol';

interface IVaultKeep3rJob is IKeep3rJob {
  event VaultAdded(address _vault, uint256 _requiredEarn);
  event VaultModified(address _vault, uint256 _requiredEarn);
  event VaultRemoved(address _vault);

  // Actions by Keeper
  event Worked(address _vault, address _keeper, uint256 _credits);

  // Actions forced by Governor
  event ForceWorked(address _vault);

  // Setters
  function addVaults(address[] calldata _vaults, uint256[] calldata _requiredEarns) external;

  function addVault(address _vault, uint256 _requiredEarn) external;

  function updateVaults(address[] calldata _vaults, uint256[] calldata _requiredEarns) external;

  function updateVault(address _vault, uint256 _requiredEarn) external;

  function removeVault(address _vault) external;

  function setEarnCooldown(uint256 _earnCooldown) external;

  // Getters
  function workable(address _vault) external returns (bool);

  function vaults() external view returns (address[] memory _vaults);

  function calculateEarn(address _vault) external view returns (uint256 _amount);

  // Keeper actions
  function work(address _vault) external returns (uint256 _credits);

  // Mechanics keeper bypass
  function forceWork(address _vault) external;
}

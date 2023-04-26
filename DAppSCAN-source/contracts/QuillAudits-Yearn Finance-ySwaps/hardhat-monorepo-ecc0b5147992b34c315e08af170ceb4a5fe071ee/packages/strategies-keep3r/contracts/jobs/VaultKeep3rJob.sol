// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@yearn/contract-utils/contracts/abstract/MachineryReady.sol';
import '@yearn/contract-utils/contracts/keep3r/Keep3rAbstract.sol';
import '../utils/GasPriceLimited.sol';

import '../interfaces/jobs/IVaultKeep3rJob.sol';
import '../interfaces/yearn/IEarnableVault.sol';

contract VaultKeep3rJob is MachineryReady, Keep3r, GasPriceLimited, IVaultKeep3rJob {
  using EnumerableSet for EnumerableSet.AddressSet;

  uint256 public constant PRECISION = 1_000;
  uint256 public constant MAX_REWARD_MULTIPLIER = 1 * PRECISION; // 1x max reward multiplier
  uint256 public override rewardMultiplier = MAX_REWARD_MULTIPLIER;

  mapping(address => uint256) public requiredEarn;
  mapping(address => uint256) public lastEarnAt;
  uint256 public earnCooldown;
  EnumerableSet.AddressSet internal _availableVaults;

  constructor(
    address _mechanicsRegistry,
    address _keep3r,
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA,
    uint256 _earnCooldown,
    uint256 _maxGasPrice
  ) MachineryReady(_mechanicsRegistry) Keep3r(_keep3r) {
    _setKeep3rRequirements(_bond, _minBond, _earned, _age, _onlyEOA);
    _setEarnCooldown(_earnCooldown);
    _setMaxGasPrice(_maxGasPrice);
  }

  // Keep3r Setters
  function setKeep3r(address _keep3r) external override onlyGovernor {
    _setKeep3r(_keep3r);
  }

  function setKeep3rRequirements(
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA
  ) external override onlyGovernor {
    _setKeep3rRequirements(_bond, _minBond, _earned, _age, _onlyEOA);
  }

  function setRewardMultiplier(uint256 _rewardMultiplier) external override onlyGovernorOrMechanic {
    _setRewardMultiplier(_rewardMultiplier);
    emit SetRewardMultiplier(_rewardMultiplier);
  }

  function _setRewardMultiplier(uint256 _rewardMultiplier) internal {
    require(_rewardMultiplier <= MAX_REWARD_MULTIPLIER, 'VaultKeep3rJob::set-reward-multiplier:multiplier-exceeds-max');
    rewardMultiplier = _rewardMultiplier;
  }

  // Setters
  function addVaults(address[] calldata _vaults, uint256[] calldata _requiredEarns) external override onlyGovernorOrMechanic {
    require(_vaults.length == _requiredEarns.length, 'VaultKeep3rJob::add-vaults:vaults-required-earns-different-length');
    for (uint256 i; i < _vaults.length; i++) {
      _addVault(_vaults[i], _requiredEarns[i]);
    }
  }

  function addVault(address _vault, uint256 _requiredEarn) external override onlyGovernorOrMechanic {
    _addVault(_vault, _requiredEarn);
  }

  function _addVault(address _vault, uint256 _requiredEarn) internal {
    require(requiredEarn[_vault] == 0, 'VaultKeep3rJob::add-vault:vault-already-added');
    _setRequiredEarn(_vault, _requiredEarn);
    _availableVaults.add(_vault);
    emit VaultAdded(_vault, _requiredEarn);
  }

  function updateVaults(address[] calldata _vaults, uint256[] calldata _requiredEarns) external override onlyGovernorOrMechanic {
    require(_vaults.length == _requiredEarns.length, 'VaultKeep3rJob::update-vaults:vaults-required-earns-different-length');
    for (uint256 i; i < _vaults.length; i++) {
      _updateVault(_vaults[i], _requiredEarns[i]);
    }
  }

  function updateVault(address _vault, uint256 _requiredEarn) external override onlyGovernorOrMechanic {
    _updateVault(_vault, _requiredEarn);
  }

  function _updateVault(address _vault, uint256 _requiredEarn) internal {
    require(requiredEarn[_vault] > 0, 'VaultKeep3rJob::update-required-earn:vault-not-added');
    _setRequiredEarn(_vault, _requiredEarn);
    emit VaultModified(_vault, _requiredEarn);
  }

  function removeVault(address _vault) external override onlyGovernorOrMechanic {
    require(requiredEarn[_vault] > 0, 'VaultKeep3rJob::remove-vault:vault-not-added');
    requiredEarn[_vault] = 0;
    _availableVaults.remove(_vault);
    emit VaultRemoved(_vault);
  }

  function _setRequiredEarn(address _vault, uint256 _requiredEarn) internal {
    require(_requiredEarn > 0, 'VaultKeep3rJob::set-required-earn:should-not-be-zero');
    requiredEarn[_vault] = _requiredEarn;
  }

  function setEarnCooldown(uint256 _earnCooldown) external override onlyGovernorOrMechanic {
    _setEarnCooldown(_earnCooldown);
  }

  function _setEarnCooldown(uint256 _earnCooldown) internal {
    require(_earnCooldown > 0, 'VaultKeep3rJob::set-earn-cooldown:should-not-be-zero');
    earnCooldown = _earnCooldown;
  }

  // Getters
  function vaults() public view override returns (address[] memory _vaults) {
    _vaults = new address[](_availableVaults.length());
    for (uint256 i; i < _availableVaults.length(); i++) {
      _vaults[i] = _availableVaults.at(i);
    }
  }

  // Keeper view actions
  function calculateEarn(address _vault) public view override returns (uint256 _amount) {
    require(requiredEarn[_vault] > 0, 'VaultKeep3rJob::calculate-earn:vault-not-added');
    return IEarnableVault(_vault).available();
  }

  function workable(address _vault) external override notPaused returns (bool) {
    return _workable(_vault);
  }

  function _workable(address _vault) internal view returns (bool) {
    require(requiredEarn[_vault] > 0, 'VaultKeep3rJob::workable:vault-not-added');
    return (calculateEarn(_vault) >= requiredEarn[_vault] && block.timestamp > lastEarnAt[_vault] + earnCooldown);
  }

  // Keeper actions
  function _work(address _vault) internal returns (uint256 _credits) {
    uint256 _initialGas = gasleft();

    require(_workable(_vault), 'VaultKeep3rJob::earn:not-workable');

    _earn(_vault);

    _credits = _calculateCredits(_initialGas);

    emit Worked(_vault, msg.sender, _credits);
  }

  function work(address _vault) external override notPaused onlyKeeper(msg.sender) returns (uint256 _credits) {
    _credits = _work(_vault);
    _paysKeeperAmount(msg.sender, _credits);
  }

  function _calculateCredits(uint256 _initialGas) internal view returns (uint256 _credits) {
    // Gets default credits from KP3R_Helper and applies job reward multiplier
    return (_getQuoteLimitFor(msg.sender, _initialGas) * rewardMultiplier) / PRECISION;
  }

  // Mechanics Setters
  function setMaxGasPrice(uint256 _maxGasPrice) external override onlyGovernorOrMechanic {
    _setMaxGasPrice(_maxGasPrice);
  }

  // Mechanics keeper bypass
  function forceWork(address _vault) external override onlyGovernorOrMechanic {
    _earn(_vault);
    emit ForceWorked(_vault);
  }

  function _earn(address _vault) internal {
    IEarnableVault(_vault).earn();
    lastEarnAt[_vault] = block.timestamp;
  }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@openzeppelin/contracts/math/SafeMath.sol';

import '@yearn/contract-utils/contracts/utils/Governable.sol';
import '@yearn/contract-utils/contracts/utils/CollectableDust.sol';
import '@yearn/contract-utils/contracts/keep3r/Keep3rAbstract.sol';

import '../interfaces/keep3r/IVaultKeep3r.sol';
import '../interfaces/yearn/IEarnableVault.sol';

contract VaultKeep3r is Governable, CollectableDust, Keep3r, IVaultKeep3r {
  using SafeMath for uint256;

  mapping(address => uint256) public requiredEarn;
  mapping(address => uint256) public lastEarnAt;
  uint256 public earnCooldown;

  EnumerableSet.AddressSet internal availableVaults;

  constructor(
    address _keep3r,
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA,
    uint256 _earnCooldown
  ) public Governable(msg.sender) CollectableDust() Keep3r(_keep3r) {
    _setKeep3rRequirements(_bond, _minBond, _earned, _age, _onlyEOA);
    _setEarnCooldown(_earnCooldown);
  }

  function isVaultKeep3r() external pure override returns (bool) {
    return true;
  }

  // Setters
  function addVault(address _vault, uint256 _requiredEarn) external override onlyGovernor {
    require(requiredEarn[_vault] == 0, 'vault-keep3r::add-vault:vault-already-added');
    _setRequiredEarn(_vault, _requiredEarn);
    availableVaults.add(_vault);
    emit VaultAdded(_vault, _requiredEarn);
  }

  function updateRequiredEarnAmount(address _vault, uint256 _requiredEarn) external override onlyGovernor {
    require(requiredEarn[_vault] > 0, 'vault-keep3r::update-required-earn:vault-not-added');
    _setRequiredEarn(_vault, _requiredEarn);
    emit VaultModified(_vault, _requiredEarn);
  }

  function removeVault(address _vault) external override onlyGovernor {
    require(requiredEarn[_vault] > 0, 'vault-keep3r::remove-vault:vault-not-added');
    requiredEarn[_vault] = 0;
    availableVaults.remove(_vault);
    emit VaultRemoved(_vault);
  }

  function _setRequiredEarn(address _vault, uint256 _requiredEarn) internal {
    require(_requiredEarn > 0, 'vault-keep3r::set-required-earn:should-not-be-zero');
    requiredEarn[_vault] = _requiredEarn;
  }

  function setEarnCooldown(uint256 _earnCooldown) external override onlyGovernor {
    _setEarnCooldown(_earnCooldown);
  }

  function _setEarnCooldown(uint256 _earnCooldown) internal {
    require(_earnCooldown > 0, 'vault-keep3r::set-earn-cooldown:should-not-be-zero');
    earnCooldown = _earnCooldown;
  }

  // Keep3r Setters
  function setKeep3r(address _keep3r) external override onlyGovernor {
    _setKeep3r(_keep3r);
    emit Keep3rSet(_keep3r);
  }

  function setKeep3rRequirements(
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA
  ) external override onlyGovernor {
    _setKeep3rRequirements(_bond, _minBond, _earned, _age, _onlyEOA);
    emit Keep3rRequirementsSet(_bond, _minBond, _earned, _age, _onlyEOA);
  }

  // Getters
  function vaults() public view override returns (address[] memory _vaults) {
    _vaults = new address[](availableVaults.length());
    for (uint256 i; i < availableVaults.length(); i++) {
      _vaults[i] = availableVaults.at(i);
    }
  }

  function calculateEarn(address _vault) public override returns (uint256 _amount) {
    require(requiredEarn[_vault] > 0, 'vault-keep3r::calculate-earn:vault-not-added');
    return IEarnableVault(_vault).available();
  }

  function workable(address _vault) public override returns (bool) {
    require(requiredEarn[_vault] > 0, 'vault-keep3r::workable:vault-not-added');
    return (calculateEarn(_vault) >= requiredEarn[_vault] && block.timestamp > lastEarnAt[_vault].add(earnCooldown));
  }

  // Keep3r actions
  function earn(address _vault) external override onlyKeeper paysKeeper {
    require(workable(_vault), 'vault-keep3r::earn:not-workable');
    _earn(_vault);
    emit EarnByKeeper(_vault);
  }

  // Governor keeper bypass
  function forceEarn(address _vault) external override onlyGovernor {
    _earn(_vault);
    emit EarnByGovernor(_vault);
  }

  function _earn(address _vault) internal {
    IEarnableVault(_vault).earn();
    lastEarnAt[_vault] = block.timestamp;
  }

  // Governable
  function setPendingGovernor(address _pendingGovernor) external override onlyGovernor {
    _setPendingGovernor(_pendingGovernor);
  }

  function acceptGovernor() external override onlyPendingGovernor {
    _acceptGovernor();
  }

  // Collectable Dust
  function sendDust(
    address _to,
    address _token,
    uint256 _amount
  ) external override onlyGovernor {
    _sendDust(_to, _token, _amount);
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '@yearn/contract-utils/contracts/abstract/UtilsReady.sol';
import '../interfaces/yearn/IV2Registry.sol';
import '../interfaces/yearn/IV2Vault.sol';

interface IVaultsRegistryHelper {
  function registry() external view returns (address _registry);

  function getVaults() external view returns (address[] memory _vaults);

  function getVaultStrategies(address _vault) external view returns (address[] memory _strategies);

  function getVaultsAndStrategies() external view returns (address[] memory _vaults, address[] memory _strategies);
}

contract VaultsRegistryHelper is UtilsReady, IVaultsRegistryHelper {
  using Address for address;

  address public immutable override registry;

  constructor(address _registry) UtilsReady() {
    registry = _registry;
  }

  function getVaults() public view override returns (address[] memory _vaults) {
    uint256 _tokensLength = IV2Registry(registry).numTokens();
    // vaults = [];
    address[] memory _vaultsArray = new address[](_tokensLength * 20); // MAX length
    uint256 _vaultIndex = 0;
    for (uint256 i; i < _tokensLength; i++) {
      address _token = IV2Registry(registry).tokens(i);
      for (uint256 j; j < 20; j++) {
        address _vault = IV2Registry(registry).vaults(_token, j);
        if (_vault == address(0)) break;
        _vaultsArray[_vaultIndex] = _vault;
        _vaultIndex++;
      }
    }
    _vaults = new address[](_vaultIndex);
    for (uint256 i; i < _vaultIndex; i++) {
      _vaults[i] = _vaultsArray[i];
    }
  }

  function getVaultStrategies(address _vault) public view override returns (address[] memory _strategies) {
    address[] memory _strategiesArray = new address[](20); // MAX length
    uint256 i;
    for (i; i < 20; i++) {
      address _strategy = IV2Vault(_vault).withdrawalQueue(i);
      if (_strategy == address(0)) break;
      _strategiesArray[i] = _strategy;
    }
    _strategies = new address[](i);
    for (uint256 j; j < i; j++) {
      _strategies[j] = _strategiesArray[j];
    }
  }

  function getVaultsAndStrategies() external view override returns (address[] memory _vaults, address[] memory _strategies) {
    _vaults = getVaults();
    address[] memory _strategiesArray = new address[](_vaults.length * 20); // MAX length
    uint256 _strategiesIndex;
    for (uint256 i; i < _vaults.length; i++) {
      address[] memory _vaultStrategies = getVaultStrategies(_vaults[i]);
      for (uint256 j; j < _vaultStrategies.length; j++) {
        _strategiesArray[_strategiesIndex + j] = _vaultStrategies[j];
      }
      _strategiesIndex += _vaultStrategies.length;
    }

    _strategies = new address[](_strategiesIndex);
    for (uint256 j; j < _strategiesIndex; j++) {
      _strategies[j] = _strategiesArray[j];
    }
  }
}

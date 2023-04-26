// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../interfaces/mechanics/IMechanicsRegistry.sol';
import '../abstract/UtilsReady.sol';

contract MechanicsRegistry is UtilsReady, IMechanicsRegistry {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _mechanics;

  constructor(address _mechanic) {
    _addMechanic(_mechanic);
  }

  // Setters
  function addMechanic(address _mechanic) external override onlyGovernor {
    _addMechanic(_mechanic);
  }

  function removeMechanic(address _mechanic) external override onlyGovernor {
    _removeMechanic(_mechanic);
  }

  function _addMechanic(address _mechanic) internal {
    require(_mechanic != address(0), 'MechanicsRegistry::add-mechanic:mechanic-should-not-be-zero-address');
    require(!_mechanics.contains(_mechanic), 'MechanicsRegistry::add-mechanic:mechanic-already-added');
    _mechanics.add(_mechanic);
    emit MechanicAdded(_mechanic);
  }

  function _removeMechanic(address _mechanic) internal {
    require(_mechanics.contains(_mechanic), 'MechanicsRegistry::remove-mechanic:mechanic-not-found');
    _mechanics.remove(_mechanic);
    emit MechanicRemoved(_mechanic);
  }

  // View helpers
  function isMechanic(address mechanic) public view override returns (bool _isMechanic) {
    return _mechanics.contains(mechanic);
  }

  // Getters
  function mechanics() public view override returns (address[] memory _mechanicsList) {
    _mechanicsList = new address[](_mechanics.length());
    for (uint256 i; i < _mechanics.length(); i++) {
      _mechanicsList[i] = _mechanics.at(i);
    }
  }
}

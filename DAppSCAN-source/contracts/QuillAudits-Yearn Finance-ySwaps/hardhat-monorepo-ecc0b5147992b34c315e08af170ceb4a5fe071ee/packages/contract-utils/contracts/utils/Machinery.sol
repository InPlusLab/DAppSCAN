// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../interfaces/utils/IMachinery.sol';
import '../interfaces/mechanics/IMechanicsRegistry.sol';

contract Machinery is IMachinery {
  using EnumerableSet for EnumerableSet.AddressSet;

  IMechanicsRegistry internal _mechanicsRegistry;

  constructor(address __mechanicsRegistry) {
    _setMechanicsRegistry(__mechanicsRegistry);
  }

  modifier onlyMechanic() {
    require(_mechanicsRegistry.isMechanic(msg.sender), 'Machinery: not mechanic');
    _;
  }

  function setMechanicsRegistry(address __mechanicsRegistry) external virtual override {
    _setMechanicsRegistry(__mechanicsRegistry);
  }

  function _setMechanicsRegistry(address __mechanicsRegistry) internal {
    _mechanicsRegistry = IMechanicsRegistry(__mechanicsRegistry);
  }

  // View helpers
  function mechanicsRegistry() external view override returns (address _mechanicRegistry) {
    return address(_mechanicsRegistry);
  }

  function isMechanic(address _mechanic) public view override returns (bool _isMechanic) {
    return _mechanicsRegistry.isMechanic(_mechanic);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import './UtilsReady.sol';
import '../utils/Machinery.sol';

abstract contract MachineryReady is UtilsReady, Machinery {
  constructor(address _mechanicsRegistry) Machinery(_mechanicsRegistry) UtilsReady() {}

  // Machinery: restricted-access
  function setMechanicsRegistry(address _mechanicsRegistry) external override onlyGovernor {
    _setMechanicsRegistry(_mechanicsRegistry);
  }

  // Machinery: modifiers
  modifier onlyGovernorOrMechanic() {
    require(isGovernor(msg.sender) || isMechanic(msg.sender), 'Machinery::onlyGovernorOrMechanic:invalid-msg-sender');
    _;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import './UtilsReady.sol';
import '../utils/Migratable.sol';

abstract contract MigratableReady is UtilsReady, Migratable {
  constructor() UtilsReady() {}

  // Migratable: restricted-access
  function migrate(address _to) external onlyGovernor {
    _migrated(_to);
  }
}

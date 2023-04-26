// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../interfaces/utils/IMigratable.sol';

abstract contract Migratable is IMigratable {
  address public override migratedTo;

  constructor() {}

  modifier notMigrated() {
    require(migratedTo == address(0), 'migrated');
    _;
  }

  function _migrated(address _to) internal {
    require(migratedTo == address(0), 'already-migrated');
    require(_to != address(0), 'migrate-to-address-0');
    migratedTo = _to;
    emit Migrated(_to);
  }
}

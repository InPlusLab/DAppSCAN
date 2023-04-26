// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IMigratable {
  event Migrated(address _to);

  function migratedTo() external view returns (address _to);
}

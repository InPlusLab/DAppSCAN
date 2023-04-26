// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IMachinery {
  // View helpers
  function mechanicsRegistry() external view returns (address _mechanicsRegistry);

  function isMechanic(address mechanic) external view returns (bool _isMechanic);

  // Setters
  function setMechanicsRegistry(address _mechanicsRegistry) external;
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IMechanicsRegistry {
  event MechanicAdded(address _mechanic);
  event MechanicRemoved(address _mechanic);

  function addMechanic(address _mechanic) external;

  function removeMechanic(address _mechanic) external;

  function mechanics() external view returns (address[] memory _mechanicsList);

  function isMechanic(address mechanic) external view returns (bool _isMechanic);
}

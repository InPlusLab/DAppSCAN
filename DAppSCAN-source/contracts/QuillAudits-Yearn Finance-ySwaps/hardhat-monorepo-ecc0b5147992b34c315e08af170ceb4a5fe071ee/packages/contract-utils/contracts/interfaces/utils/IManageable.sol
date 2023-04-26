// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IManageable {
  event PendingManagerSet(address pendingManager);
  event ManagerAccepted();

  function setPendingManager(address _pendingManager) external;

  function acceptManager() external;

  function manager() external view returns (address _manager);

  function pendingManager() external view returns (address _pendingManager);

  function isManager(address _account) external view returns (bool _isManager);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../interfaces/utils/IManageable.sol';

abstract contract Manageable is IManageable {
  address public override manager;
  address public override pendingManager;

  constructor(address _manager) {
    require(_manager != address(0), 'manageable/manager-should-not-be-zero-address');
    manager = _manager;
  }

  function _setPendingManager(address _pendingManager) internal {
    require(_pendingManager != address(0), 'manageable/pending-manager-should-not-be-zero-addres');
    pendingManager = _pendingManager;
    emit PendingManagerSet(_pendingManager);
  }

  function _acceptManager() internal {
    manager = pendingManager;
    pendingManager = address(0);
    emit ManagerAccepted();
  }

  function isManager(address _account) public view override returns (bool _isManager) {
    return _account == manager;
  }

  modifier onlyManager() {
    require(isManager(msg.sender), 'manageable/only-manager');
    _;
  }

  modifier onlyPendingManager() {
    require(msg.sender == pendingManager, 'manageable/only-pending-manager');
    _;
  }
}

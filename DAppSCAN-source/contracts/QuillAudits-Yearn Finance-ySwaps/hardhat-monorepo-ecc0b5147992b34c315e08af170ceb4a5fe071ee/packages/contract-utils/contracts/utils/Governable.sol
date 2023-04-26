// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../interfaces/utils/IGovernable.sol';

contract Governable is IGovernable {
  address public override governor;
  address public override pendingGovernor;

  constructor(address _governor) {
    require(_governor != address(0), 'governable/governor-should-not-be-zero-address');
    governor = _governor;
  }

  function setPendingGovernor(address _pendingGovernor) external virtual override onlyGovernor {
    _setPendingGovernor(_pendingGovernor);
  }

  function acceptGovernor() external virtual override onlyPendingGovernor {
    _acceptGovernor();
  }

  function _setPendingGovernor(address _pendingGovernor) internal {
    require(_pendingGovernor != address(0), 'governable/pending-governor-should-not-be-zero-addres');
    pendingGovernor = _pendingGovernor;
    emit PendingGovernorSet(_pendingGovernor);
  }

  function _acceptGovernor() internal {
    governor = pendingGovernor;
    pendingGovernor = address(0);
    emit GovernorAccepted();
  }

  function isGovernor(address _account) public view override returns (bool _isGovernor) {
    return _account == governor;
  }

  modifier onlyGovernor() {
    require(isGovernor(msg.sender), 'governable/only-governor');
    _;
  }

  modifier onlyPendingGovernor() {
    require(msg.sender == pendingGovernor, 'governable/only-pending-governor');
    _;
  }
}

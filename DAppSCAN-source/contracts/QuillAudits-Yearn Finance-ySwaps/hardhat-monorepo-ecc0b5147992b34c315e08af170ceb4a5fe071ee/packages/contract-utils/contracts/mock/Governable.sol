// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../utils/Governable.sol';

abstract
contract GovernableMock is Governable {

  uint256 internal _timestamp;

  constructor(address _governor) Governable(_governor) {
    _timestamp = block.timestamp;
  }

  function onlyGovernorAllowed() external onlyGovernor {}
  function onlyPendingGovernorAllowed() external onlyPendingGovernor {}

  function setPendingGovernor(address _pendingGovernor) public override {
    require(_timestamp <= block.timestamp - 1 days, 'lol nope');
    _setPendingGovernor(_pendingGovernor); 
  }

  function acceptGovernor() public override {
    _acceptGovernor();
  }
}

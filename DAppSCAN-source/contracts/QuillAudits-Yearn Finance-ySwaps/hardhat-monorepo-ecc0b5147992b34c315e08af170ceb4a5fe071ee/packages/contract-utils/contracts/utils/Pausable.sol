// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../interfaces/utils/IPausable.sol';

abstract contract Pausable is IPausable {
  bool public paused;

  constructor() {}

  modifier notPaused() {
    require(!paused, 'paused');
    _;
  }

  function _pause(bool _paused) internal {
    require(paused != _paused, 'no-change');
    paused = _paused;
    emit Paused(_paused);
  }
}

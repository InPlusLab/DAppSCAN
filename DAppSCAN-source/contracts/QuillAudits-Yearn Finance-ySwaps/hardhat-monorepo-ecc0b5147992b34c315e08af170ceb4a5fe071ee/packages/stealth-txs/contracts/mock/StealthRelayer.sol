// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import '../StealthRelayer.sol';

contract StealthRelayerMock is StealthRelayer {

  constructor(address _governor, address _stealthVault) StealthRelayer(_stealthVault) {
    // force change governor only for mocked contract
    governor = _governor;
  }

  function onlyValidJobModifier(address _job) external onlyValidJob(_job) {}

}

contract JobMock {
  event Event(bytes _bytes);
  bool public called;
  bool public shouldRevert;
  
  function setShouldRevert(bool _shouldRevert) external {
    shouldRevert = _shouldRevert;
  }

  function work(bytes memory _bytes) external payable returns (bytes memory _returnData) {
    require(!shouldRevert, '!w');
    called = true;
    emit Event(_bytes);
    return bytes('');
  }
}

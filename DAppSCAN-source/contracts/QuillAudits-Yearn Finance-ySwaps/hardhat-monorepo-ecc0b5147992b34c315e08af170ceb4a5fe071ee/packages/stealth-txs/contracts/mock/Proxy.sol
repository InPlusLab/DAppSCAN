// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';

contract ProxyMock {
  using Address for address;

  constructor() {
  }

  function execute(address _to, bytes memory _data) external returns (bytes memory _returnData) {
    return _to.functionCallWithValue(_data, 0, 'Proxy: call reverted');
  }

}

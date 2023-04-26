// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import './AsyncSwapper.sol';

interface IMultipleAsyncSwapper is IAsyncSwapper {
  function swapMultiple(bytes calldata _data) external;
}

abstract contract MultipleAsyncSwapper is IMultipleAsyncSwapper, AsyncSwapper {
  constructor(address _governor, address _tradeFactory) AsyncSwapper(_governor, _tradeFactory) {}
}

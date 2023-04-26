// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../../swappers/sync/SyncSwapper.sol';

contract SyncSwapperMock is SyncSwapper {

  constructor(address _governor, address _tradeFactory) SyncSwapper(_governor, _tradeFactory) {}

  function _executeSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _maxSlippage,
    bytes calldata _data
  ) internal override virtual { }
}

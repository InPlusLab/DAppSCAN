// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../../swappers/async/AsyncSwapper.sol';

contract AsyncSwapperMock is AsyncSwapper {
  uint256 internal _receivedAmount;

  event MyInternalExecuteSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    bytes _data
  );

  constructor(address _governor, address _tradeFactory) AsyncSwapper(_governor, _tradeFactory) {}

  function setReceivedAmount(uint256 __receivedAmount) external {
    _receivedAmount = __receivedAmount;
  }

  function _executeSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    bytes calldata _data
  ) internal override virtual {
    emit MyInternalExecuteSwap(
      _receiver,
      _tokenIn,
      _tokenOut,
      _amountIn,
      _data
    );
  }
}

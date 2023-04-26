// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../Swapper.sol';

interface IAsyncSwapper is ISwapper {
  function swap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _minAmountOut,
    bytes calldata _data
  ) external;
}

abstract contract AsyncSwapper is IAsyncSwapper, Swapper {
  // solhint-disable-next-line var-name-mixedcase
  SwapperType public constant override SWAPPER_TYPE = SwapperType.ASYNC;

  constructor(address _governor, address _tradeFactory) Governable(_governor) Swapper(_tradeFactory) {}

  function _assertPreSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _minAmountOut
  ) internal pure {
    if (_receiver == address(0) || _tokenIn == address(0) || _tokenOut == address(0)) revert CommonErrors.ZeroAddress();
    if (_amountIn == 0) revert CommonErrors.ZeroAmount();
    if (_minAmountOut == 0) revert CommonErrors.ZeroAmount();
  }

  function _executeSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    bytes calldata _data
  ) internal virtual;

  function swap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _minAmountOut,
    bytes calldata _data
  ) external virtual override onlyTradeFactory {
    _assertPreSwap(_receiver, _tokenIn, _tokenOut, _amountIn, _minAmountOut);
    _executeSwap(_receiver, _tokenIn, _tokenOut, _amountIn, _data);
  }
}

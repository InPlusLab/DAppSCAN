// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../Swapper.sol';

interface ISyncSwapper is ISwapper {
  // solhint-disable-next-line func-name-mixedcase
  function SLIPPAGE_PRECISION() external view returns (uint256);

  function swap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _maxSlippage,
    bytes calldata _data
  ) external;
}

abstract contract SyncSwapper is ISyncSwapper, Swapper {
  // solhint-disable-next-line var-name-mixedcase
  uint256 public immutable override SLIPPAGE_PRECISION = 10000; // 1 is 0.0001%, 1_000 is 0.1%

  // solhint-disable-next-line var-name-mixedcase
  SwapperType public constant override SWAPPER_TYPE = SwapperType.SYNC;

  constructor(address _governor, address _tradeFactory) Governable(_governor) Swapper(_tradeFactory) {}

  function _assertPreSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _maxSlippage
  ) internal pure {
    if (_receiver == address(0) || _tokenIn == address(0) || _tokenOut == address(0)) revert CommonErrors.ZeroAddress();
    if (_amountIn == 0) revert CommonErrors.ZeroAmount();
    if (_maxSlippage == 0) revert CommonErrors.ZeroSlippage();
  }

  function _executeSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _maxSlippage,
    bytes calldata _data
  ) internal virtual;

  function swap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _maxSlippage,
    bytes calldata _data
  ) external virtual override onlyTradeFactory {
    _assertPreSwap(_receiver, _tokenIn, _tokenOut, _amountIn, _maxSlippage);
    _executeSwap(_receiver, _tokenIn, _tokenOut, _amountIn, _maxSlippage, _data);
  }
}

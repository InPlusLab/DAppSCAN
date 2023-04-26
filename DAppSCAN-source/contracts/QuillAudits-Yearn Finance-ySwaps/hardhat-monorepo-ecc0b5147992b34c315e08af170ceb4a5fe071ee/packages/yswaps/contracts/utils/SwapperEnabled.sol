// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4 <0.9.0;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './ISwapperEnabled.sol';
import {ITradeFactoryExecutor} from '../TradeFactory/TradeFactoryExecutor.sol';
import {ITradeFactoryPositionsHandler} from '../TradeFactory/TradeFactoryPositionsHandler.sol';

/*
 * SwapperEnabled Abstract
 */
abstract contract SwapperEnabled is ISwapperEnabled {
  using SafeERC20 for IERC20;

  address public override tradeFactory;

  constructor(address _tradeFactory) {
    _setTradeFactory(_tradeFactory);
  }

  // onlyMultisig:
  function _setTradeFactory(address _tradeFactory) internal {
    // strategy should handle disabling all previous trades and creating all new ones
    tradeFactory = _tradeFactory;
  }

  // onlyMultisig or internal use:
  function _enableTrade(address _tokenIn, address _tokenOut) internal {
    IERC20(_tokenIn).approve(tradeFactory, type(uint256).max);
    return ITradeFactoryPositionsHandler(tradeFactory).enable(_tokenIn, _tokenOut);
  }

  function disableTradeCallback(address _tokenIn, address _tokenOut) external override {
    if (msg.sender != tradeFactory) revert NotTradeFactory();
    IERC20(_tokenIn).approve(tradeFactory, 0);
    ITradeFactoryPositionsHandler(tradeFactory).disable(_tokenIn, _tokenOut);
  }

  function _disableTrade(address _tokenIn, address _tokenOut) internal {
    IERC20(_tokenIn).approve(tradeFactory, 0);
    ITradeFactoryPositionsHandler(tradeFactory).disable(_tokenIn, _tokenOut);
  }

  function _executeTrade(
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _maxSlippage
  ) internal returns (uint256 _receivedAmount) {
    return
      ITradeFactoryExecutor(tradeFactory).execute(
        ITradeFactoryExecutor.SyncTradeExecutionDetails(_tokenIn, _tokenOut, _amountIn, _maxSlippage),
        ''
      );
  }

  function _executeTrade(
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _maxSlippage,
    bytes calldata _data
  ) internal returns (uint256 _receivedAmount) {
    return
      ITradeFactoryExecutor(tradeFactory).execute(
        ITradeFactoryExecutor.SyncTradeExecutionDetails(_tokenIn, _tokenOut, _amountIn, _maxSlippage),
        _data
      );
  }
}

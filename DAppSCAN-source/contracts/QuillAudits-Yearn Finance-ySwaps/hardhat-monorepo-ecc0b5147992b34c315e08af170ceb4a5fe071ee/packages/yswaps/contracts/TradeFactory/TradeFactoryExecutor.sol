// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import '@yearn/contract-utils/contracts/utils/Machinery.sol';

import '../swappers/async/AsyncSwapper.sol';
import '../swappers/async/MultipleAsyncSwapper.sol';
import '../swappers/sync/SyncSwapper.sol';

import './TradeFactoryPositionsHandler.sol';

interface ITradeFactoryExecutor {
  event SyncTradeExecuted(address indexed _strategy, uint256 _receivedAmount, address indexed _swapper);

  event AsyncTradeExecuted(uint256 _receivedAmount, address _swapper);

  event MultipleAsyncTradeExecuted(uint256[] _receivedAmount, address _swapper);

  error InvalidAmountOut();

  struct SyncTradeExecutionDetails {
    address _tokenIn;
    address _tokenOut;
    uint256 _amountIn;
    uint256 _maxSlippage;
  }

  struct AsyncTradeExecutionDetails {
    address _strategy;
    address _tokenIn;
    address _tokenOut;
    uint256 _amount;
    uint256 _minAmountOut;
  }

  // Sync execution
  function execute(SyncTradeExecutionDetails calldata _tradeExecutionDetails, bytes calldata _data) external returns (uint256 _receivedAmount);

  // Async execution
  function execute(
    AsyncTradeExecutionDetails calldata _tradeExecutionDetails,
    address _swapper,
    bytes calldata _data
  ) external returns (uint256 _receivedAmount);

  // Multiple async execution
  function execute(
    AsyncTradeExecutionDetails[] calldata _tradesExecutionDetails,
    address _swapper,
    bytes calldata _data
  ) external;
}

abstract contract TradeFactoryExecutor is ITradeFactoryExecutor, TradeFactoryPositionsHandler, Machinery {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;

  constructor(address _mechanicsRegistry) Machinery(_mechanicsRegistry) {}

  // Machinery
  function setMechanicsRegistry(address __mechanicsRegistry) external virtual override onlyRole(MASTER_ADMIN) {
    _setMechanicsRegistry(__mechanicsRegistry);
  }

  // Execute via sync swapper
  function execute(SyncTradeExecutionDetails calldata _tradeExecutionDetails, bytes calldata _data)
    external
    override
    onlyRole(STRATEGY)
    returns (uint256 _receivedAmount)
  {
    address _swapper = strategySyncSwapper[msg.sender];
    if (_tradeExecutionDetails._tokenIn == address(0) || _tradeExecutionDetails._tokenOut == address(0)) revert CommonErrors.ZeroAddress();
    if (_tradeExecutionDetails._amountIn == 0) revert CommonErrors.ZeroAmount();
    // SWC-135-Code With No Effects: L82
    if (_tradeExecutionDetails._maxSlippage == 0) revert CommonErrors.ZeroSlippage();
    IERC20(_tradeExecutionDetails._tokenIn).safeTransferFrom(msg.sender, _swapper, _tradeExecutionDetails._amountIn);
    uint256 _preSwapBalanceOut = IERC20(_tradeExecutionDetails._tokenOut).balanceOf(msg.sender);
    ISyncSwapper(_swapper).swap(
      msg.sender,
      _tradeExecutionDetails._tokenIn,
      _tradeExecutionDetails._tokenOut,
      _tradeExecutionDetails._amountIn,
      _tradeExecutionDetails._maxSlippage,
      _data
    );
    _receivedAmount = IERC20(_tradeExecutionDetails._tokenOut).balanceOf(msg.sender) - _preSwapBalanceOut;
    emit SyncTradeExecuted(msg.sender, _receivedAmount, _swapper);
  }

  // Execute via async swapper
  function execute(
    AsyncTradeExecutionDetails calldata _tradeExecutionDetails,
    address _swapper,
    bytes calldata _data
  ) external override onlyMechanic returns (uint256 _receivedAmount) {
    if (
      !_tokensOutByStrategyAndTokenIn[_tradeExecutionDetails._strategy][_tradeExecutionDetails._tokenIn].contains(
        _tradeExecutionDetails._tokenOut
      )
    ) revert InvalidTrade();
    if (!_swappers.contains(_swapper)) revert InvalidSwapper();
    uint256 _amount = _tradeExecutionDetails._amount != 0
      ? _tradeExecutionDetails._amount
      : IERC20(_tradeExecutionDetails._tokenIn).balanceOf(_tradeExecutionDetails._strategy);
    IERC20(_tradeExecutionDetails._tokenIn).safeTransferFrom(_tradeExecutionDetails._strategy, _swapper, _amount);
    uint256 _preSwapBalanceOut = IERC20(_tradeExecutionDetails._tokenOut).balanceOf(_tradeExecutionDetails._strategy);
    IAsyncSwapper(_swapper).swap(
      _tradeExecutionDetails._strategy,
      _tradeExecutionDetails._tokenIn,
      _tradeExecutionDetails._tokenOut,
      _amount,
      _tradeExecutionDetails._minAmountOut,
      _data
    );
    _receivedAmount = IERC20(_tradeExecutionDetails._tokenOut).balanceOf(_tradeExecutionDetails._strategy) - _preSwapBalanceOut;
    if (_receivedAmount < _tradeExecutionDetails._minAmountOut) revert InvalidAmountOut();
    emit AsyncTradeExecuted(_receivedAmount, _swapper);
  }

  function execute(
    AsyncTradeExecutionDetails[] calldata _tradesExecutionDetails,
    address _swapper,
    bytes calldata _data
  ) external override onlyMechanic {
    // Balance out holder will firstly have the pre swap balance out of each strategy
    uint256[] memory _balanceOutHolder = new uint256[](_tradesExecutionDetails.length);
    if (!_swappers.contains(_swapper)) revert InvalidSwapper();
    for (uint256 i; i < _tradesExecutionDetails.length; i++) {
      if (
        !_tokensOutByStrategyAndTokenIn[_tradesExecutionDetails[i]._strategy][_tradesExecutionDetails[i]._tokenIn].contains(
          _tradesExecutionDetails[i]._tokenOut
        )
      ) revert InvalidTrade();
      uint256 _amount = _tradesExecutionDetails[i]._amount != 0
        ? _tradesExecutionDetails[i]._amount
        : IERC20(_tradesExecutionDetails[i]._tokenIn).balanceOf(_tradesExecutionDetails[i]._strategy);
      IERC20(_tradesExecutionDetails[i]._tokenIn).safeTransferFrom(_tradesExecutionDetails[i]._strategy, _swapper, _amount);
      _balanceOutHolder[i] = IERC20(_tradesExecutionDetails[i]._tokenOut).balanceOf(_tradesExecutionDetails[i]._strategy);
    }
    IMultipleAsyncSwapper(_swapper).swapMultiple(_data);
    for (uint256 i; i < _tradesExecutionDetails.length; i++) {
      // Balance out holder will now store the total received amount of token out per strat
      _balanceOutHolder[i] = IERC20(_tradesExecutionDetails[i]._tokenOut).balanceOf(_tradesExecutionDetails[i]._strategy) - _balanceOutHolder[i];
      if (_tradesExecutionDetails[i]._minAmountOut < _balanceOutHolder[i]) revert InvalidAmountOut();
    }
    emit MultipleAsyncTradeExecuted(_balanceOutHolder, _swapper);
  }
}

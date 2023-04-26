// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import './AsyncSwapper.sol';

interface IAggregationExecutor {
  function callBytes(bytes calldata data) external payable;
}

interface IOneInchExchange {
  struct SwapDescription {
    IERC20 srcToken;
    IERC20 dstToken;
    address srcReceiver;
    address dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
    bytes permit;
  }

  event Swapped(address sender, IERC20 srcToken, IERC20 dstToken, address dstReceiver, uint256 spentAmount, uint256 returnAmount);

  function unoswapWithPermit(
    IERC20 srcToken,
    uint256 amount,
    uint256 minReturn,
    bytes32[] calldata pools,
    bytes calldata permit
  ) external payable returns (uint256 returnAmount);

  function unoswap(
    IERC20 srcToken,
    uint256 amount,
    uint256 minReturn,
    bytes32[] calldata
  ) external payable returns (uint256 returnAmount);

  function discountedSwap(
    IAggregationExecutor caller,
    SwapDescription calldata desc,
    bytes calldata data
  )
    external
    payable
    returns (
      uint256 returnAmount,
      uint256 gasLeft,
      uint256 chiSpent
    );

  function swap(
    IAggregationExecutor caller,
    SwapDescription calldata desc,
    bytes calldata data
  ) external payable returns (uint256 returnAmount, uint256 gasLeft);
}

interface IOneInchAggregatorSwapper is IAsyncSwapper {
  // solhint-disable-next-line func-name-mixedcase
  function AGGREGATION_ROUTER_V3() external view returns (address);
}

contract OneInchAggregatorSwapper is IOneInchAggregatorSwapper, AsyncSwapper {
  using SafeERC20 for IERC20;

  uint256 private constant _SHOULD_CLAIM_FLAG = 0x04;

  // solhint-disable-next-line var-name-mixedcase
  address public immutable override AGGREGATION_ROUTER_V3;

  constructor(
    address _governor,
    address _tradeFactory,
    address _aggregationRouter
  ) AsyncSwapper(_governor, _tradeFactory) {
    AGGREGATION_ROUTER_V3 = _aggregationRouter;
  }

  function _executeSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    bytes calldata _data
  ) internal override {
    (IAggregationExecutor _caller, IOneInchExchange.SwapDescription memory _swapDescription, bytes memory _tradeData) = abi.decode(
      _data[4:],
      (IAggregationExecutor, IOneInchExchange.SwapDescription, bytes)
    );
    if (
      _swapDescription.dstReceiver != _receiver ||
      address(_swapDescription.srcToken) != _tokenIn ||
      address(_swapDescription.dstToken) != _tokenOut ||
      _swapDescription.amount != _amountIn ||
      _swapDescription.flags != _SHOULD_CLAIM_FLAG
    ) revert CommonErrors.IncorrectSwapInformation();
    IERC20(_tokenIn).approve(AGGREGATION_ROUTER_V3, 0);
    IERC20(_tokenIn).approve(AGGREGATION_ROUTER_V3, _amountIn);
    IOneInchExchange(AGGREGATION_ROUTER_V3).swap(_caller, _swapDescription, _tradeData);
  }
}

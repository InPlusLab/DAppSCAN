// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './SyncSwapper.sol';

interface IUniswapV2AnchorSwapper is ISyncSwapper {
  // solhint-disable-next-line func-name-mixedcase
  function WANCHOR() external view returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function WETH() external view returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function FACTORY() external view returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function ROUTER() external view returns (address);
}

contract UniswapV2AnchorSwapper is IUniswapV2AnchorSwapper, SyncSwapper {
  using SafeERC20 for IERC20;

  // solhint-disable-next-line var-name-mixedcase
  address public immutable override WETH;
  // solhint-disable-next-line var-name-mixedcase
  address public immutable override WANCHOR;
  // solhint-disable-next-line var-name-mixedcase
  address public immutable override FACTORY;
  // solhint-disable-next-line var-name-mixedcase
  address public immutable override ROUTER;

  constructor(
    address _governor,
    address _tradeFactory,
    address _weth,
    address _wanchor,
    address _factory,
    address _router
  ) SyncSwapper(_governor, _tradeFactory) {
    WETH = _weth;
    WANCHOR = _wanchor;
    FACTORY = _factory;
    ROUTER = _router;
  }

  function _executeSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _maxSlippage,
    bytes calldata _data
  ) internal override {
    address[] memory _path;
    uint256 _amountOut;
    if (_data.length > 0) {
      _path = abi.decode(_data, (address[]));
      _amountOut = IUniswapV2Router02(ROUTER).getAmountsOut(_amountIn, _path)[_path.length - 1];
    } else {
      (_path, _amountOut) = _getPathAndAmountOut(_tokenIn, _tokenOut, _amountIn);
    }
    IERC20(_path[0]).approve(ROUTER, 0);
    IERC20(_path[0]).approve(ROUTER, _amountIn);
    IUniswapV2Router02(ROUTER).swapExactTokensForTokens(
      _amountIn,
      _amountOut - ((_amountOut * _maxSlippage) / SLIPPAGE_PRECISION / 100), // slippage calcs
      _path,
      _receiver,
      block.timestamp + 1800
    )[_path.length - 1];
  }

  function _getPathAndAmountOut(
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn
  ) internal view returns (address[] memory _path, uint256 _amountOut) {
    uint256 _amountOutByDirectPath;
    address[] memory _directPath;
    if (IUniswapV2Factory(FACTORY).getPair(_tokenIn, _tokenOut) != address(0)) {
      _directPath = new address[](2);
      _directPath[0] = _tokenIn;
      _directPath[1] = _tokenOut;
      _amountOutByDirectPath = IUniswapV2Router02(ROUTER).getAmountsOut(_amountIn, _directPath)[1];
    }

    uint256 _amountOutByWETHHopPath;
    // solhint-disable-next-line var-name-mixedcase
    address[] memory _WETHHopPath;
    if (IUniswapV2Factory(FACTORY).getPair(_tokenIn, WETH) != address(0) && IUniswapV2Factory(FACTORY).getPair(WETH, _tokenOut) != address(0)) {
      _WETHHopPath = new address[](3);
      _WETHHopPath[0] = _tokenIn;
      _WETHHopPath[1] = WETH;
      _WETHHopPath[2] = _tokenOut;
      _amountOutByWETHHopPath = IUniswapV2Router02(ROUTER).getAmountsOut(_amountIn, _WETHHopPath)[2];
    }

    uint256 _amountOutByWANCHORHopPath;
    // solhint-disable-next-line var-name-mixedcase
    address[] memory _WANCHORHopPath;
    if (
      IUniswapV2Factory(FACTORY).getPair(_tokenIn, WANCHOR) != address(0) && IUniswapV2Factory(FACTORY).getPair(WANCHOR, _tokenOut) != address(0)
    ) {
      _WANCHORHopPath = new address[](3);
      _WANCHORHopPath[0] = _tokenIn;
      _WANCHORHopPath[1] = WANCHOR;
      _WANCHORHopPath[2] = _tokenOut;
      _amountOutByWANCHORHopPath = IUniswapV2Router02(ROUTER).getAmountsOut(_amountIn, _WANCHORHopPath)[2];
    }

    if (
      Math.max(Math.max(_amountOutByDirectPath, _amountOutByWETHHopPath), Math.max(_amountOutByDirectPath, _amountOutByWANCHORHopPath)) ==
      _amountOutByDirectPath
    ) {
      return (_directPath, _amountOutByDirectPath);
    }

    if (Math.max(_amountOutByWETHHopPath, _amountOutByWANCHORHopPath) == _amountOutByWETHHopPath) {
      return (_WETHHopPath, _amountOutByWETHHopPath);
    }

    return (_WANCHORHopPath, _amountOutByWANCHORHopPath);
  }
}

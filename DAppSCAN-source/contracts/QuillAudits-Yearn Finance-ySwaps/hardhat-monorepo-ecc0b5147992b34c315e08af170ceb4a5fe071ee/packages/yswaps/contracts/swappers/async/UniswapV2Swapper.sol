// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './AsyncSwapper.sol';

interface IUniswapV2Swapper is IAsyncSwapper {
  // solhint-disable-next-line func-name-mixedcase
  function FACTORY() external view returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function ROUTER() external view returns (address);
}

contract UniswapV2Swapper is IUniswapV2Swapper, AsyncSwapper {
  using SafeERC20 for IERC20;

  // solhint-disable-next-line var-name-mixedcase
  address public immutable override FACTORY;
  // solhint-disable-next-line var-name-mixedcase
  address public immutable override ROUTER;

  constructor(
    address _governor,
    address _tradeFactory,
    address _uniswapFactory,
    address _uniswapRouter
  ) AsyncSwapper(_governor, _tradeFactory) {
    FACTORY = _uniswapFactory;
    ROUTER = _uniswapRouter;
  }

  function _executeSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    bytes calldata _data
  ) internal override {
    address[] memory _path = abi.decode(_data, (address[]));
    if (_tokenIn != _path[0] || _tokenOut != _path[_path.length - 1]) revert CommonErrors.IncorrectSwapInformation();
    IERC20(_path[0]).approve(ROUTER, 0);
    IERC20(_path[0]).approve(ROUTER, _amountIn);
    IUniswapV2Router02(ROUTER).swapExactTokensForTokens(
      _amountIn,
      0, // Slippage protection is done in AsyncSwapper abstract
      _path,
      _receiver,
      block.timestamp
    // SWC-135-Code With No Effects: L53
    )[_path.length - 1];
  }
}

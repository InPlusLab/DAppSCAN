// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import "./interfaces/IFujiAdmin.sol";
import "./interfaces/ISwapper.sol";

contract Swapper is ISwapper {
  address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant SUSHI_ROUTER_ADDR = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

  /**
   * @dev Called by the Vault to harvest farmed tokens at baselayer Protocols
   */
  function getSwapTransaction(
    address assetFrom,
    address assetTo,
    uint256 amount
  ) external view override returns (Transaction memory transaction) {
    require(assetFrom != assetTo, "invalid request");

    if (assetFrom == ETH && assetTo == WETH) {
      transaction.to = WETH;
      transaction.value = amount;
      transaction.data = abi.encodeWithSelector(IWETH.deposit.selector);
    } else if (assetFrom == WETH && assetTo == ETH) {
      transaction.to = WETH;
      transaction.data = abi.encodeWithSelector(IWETH.withdraw.selector, amount);
    } else if (assetFrom == ETH) {
      transaction.to = SUSHI_ROUTER_ADDR;
      address[] memory path = new address[](2);
      path[0] = WETH;
      path[1] = assetTo;
      transaction.value = amount;
      transaction.data = abi.encodeWithSelector(
        IUniswapV2Router01.swapExactETHForTokens.selector,
        0,
        path,
        msg.sender,
        type(uint256).max
      );
    } else if (assetTo == ETH) {
      transaction.to = SUSHI_ROUTER_ADDR;
      address[] memory path = new address[](2);
      path[0] = assetFrom;
      path[1] = WETH;
      transaction.data = abi.encodeWithSelector(
        IUniswapV2Router01.swapExactTokensForETH.selector,
        amount,
        0,
        path,
        msg.sender,
        type(uint256).max
      );
    } else if (assetFrom == WETH || assetTo == WETH) {
      transaction.to = SUSHI_ROUTER_ADDR;
      address[] memory path = new address[](2);
      path[0] = assetFrom;
      path[1] = assetTo;
      transaction.data = abi.encodeWithSelector(
        IUniswapV2Router01.swapExactTokensForTokens.selector,
        amount,
        0,
        path,
        msg.sender,
        type(uint256).max
      );
    } else {
      transaction.to = SUSHI_ROUTER_ADDR;
      address[] memory path = new address[](3);
      path[0] = assetFrom;
      path[1] = WETH;
      path[2] = assetTo;
      transaction.data = abi.encodeWithSelector(
        IUniswapV2Router01.swapExactTokensForTokens.selector,
        amount,
        0,
        path,
        msg.sender,
        type(uint256).max
      );
    }
  }
}

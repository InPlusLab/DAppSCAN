// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

interface IERC20Decimals is IERC20 {
  function decimals() external view returns (uint8);
}

/**
 * DEX Utilities
 */
contract DexUtils {
  using SafeMath for uint256;

  // PancakeSwap: 0x10ED43C718714eb63d5aA57B78B54704E256024E
  // Uniswap V2: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
  IUniswapV2Router02 uniswapV2Router;
  IUniswapV2Factory uniswapV2Factory;

  address public wrappedNative;
  address public stableToken;

  constructor(
    address _dexRouter,
    address _wrappedNative,
    address _stableToken
  ) {
    uniswapV2Router = IUniswapV2Router02(_dexRouter);
    uniswapV2Factory = IUniswapV2Factory(uniswapV2Router.factory());
    wrappedNative = _wrappedNative;
    stableToken = _stableToken;
  }

  // returns token pair price against stable (i.e. USDT) adjusted to 18 decimals
  // NOTE: assumes the primary DEX pair for main token is wrapped native
  function getTokenPriceViaNativePair(address token)
    external
    view
    returns (uint256)
  {
    (
      uint256 mnPriceAdjusted,
      address mnToken0,
      address mnToken1
    ) = _getTokenPrice(token, wrappedNative);
    (
      uint256 nsPriceAdjusted,
      address nsToken0,
      address nsToken1
    ) = _getTokenPrice(wrappedNative, stableToken);

    // *** WHAT WE WANT***: stable / main
    // *** REMEMBER ***: _getTokenPrice returns the priceAdjusted as reserves1 / reserves0
    if (mnToken0 == nsToken0) {
      // Scenario A: 1. main / native -- 2. stable / native
      // (stable / native) / (main / native) = stable / main
      return nsPriceAdjusted.mul(10**18).div(mnPriceAdjusted);
    } else if (mnToken1 == nsToken1) {
      // Scenario B: 1. native / main -- 2. native / stable
      // (native / main) / (native / stable) = stable / main
      return mnPriceAdjusted.mul(10**18).div(nsPriceAdjusted);
    } else if (mnToken1 == nsToken0) {
      // Scenario C: 1. native / main -- 2. stable / native
      // (native / main) * (stable / native) = stable / main
      // NOTE each price is adjusted by 10^18, so need to offset by 10^18
      return nsPriceAdjusted.mul(mnPriceAdjusted).div(uint256(10**18));
    }

    // Scenario D: 1. main / native -- 2. native / stable
    // 1 / ((native / stable) * (main / native)) = stable / main
    // NOTE: each price is adjusted by 10^18, so need to offset by 10^36, then add 18 decimals (hence 10^54)
    return uint256(10**54).div(nsPriceAdjusted.mul(mnPriceAdjusted));
  }

  // returns uniswap pair price moved to 18 decimals
  function _getTokenPrice(address _t0, address _t1)
    private
    view
    returns (
      uint256,
      address,
      address
    )
  {
    IUniswapV2Pair dexPair = IUniswapV2Pair(uniswapV2Factory.getPair(_t0, _t1));
    (uint112 res0, uint112 res1, ) = dexPair.getReserves();
    address t0 = dexPair.token0();
    uint8 t0Dec = IERC20Decimals(t0).decimals();
    address t1 = dexPair.token1();
    uint8 t1Dec = IERC20Decimals(t1).decimals();

    return (
      uint256(res1).mul(10**18).mul(10**t0Dec).div(uint256(res0)).div(
        10**t1Dec
      ),
      t0,
      t1
    );
  }
}

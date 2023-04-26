// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';
import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';

contract VPoolWrapperMock is IVPoolWrapper {
    mapping(int24 => mapping(int24 => IVPoolWrapper.WrapperValuesInside)) _getValuesInside;
    uint24 public uniswapFeePips; // fee collected by Uniswap
    uint24 public liquidityFeePips; // fee paid to liquidity providers, in 1e6
    uint24 public protocolFeePips; // fee paid to DAO treasury

    struct LiquidityRate {
        uint256 vQuotePerLiquidity;
        uint256 vTokenPerLiquidity;
    }
    mapping(int24 => mapping(int24 => LiquidityRate)) internal _liquidityRates;

    IUniswapV3Pool public vPool;

    function initialize(InitializeVPoolWrapperParams calldata params) external {}

    function updateGlobalFundingState(bool useZeroFundingRate) public {}

    function getValuesInside(int24 tickLower, int24 tickUpper)
        public
        view
        returns (WrapperValuesInside memory wrapperValuesInside)
    {
        return _getValuesInside[tickLower][tickUpper];
    }

    function getExtrapolatedValuesInside(int24 tickLower, int24 tickUpper)
        public
        view
        returns (WrapperValuesInside memory wrapperValuesInside)
    {
        return _getValuesInside[tickLower][tickUpper];
    }

    function setValuesInside(
        int24 tickLower,
        int24 tickUpper,
        int256 sumAX128,
        int256 sumBInsideX128,
        int256 sumFpInsideX128,
        uint256 sumFeeInsideX128
    ) external {
        _getValuesInside[tickLower][tickUpper] = IVPoolWrapper.WrapperValuesInside(
            sumAX128,
            sumBInsideX128,
            sumFpInsideX128,
            sumFeeInsideX128
        );
    }

    function setVPool(address vPoolAddress) external {
        vPool = IUniswapV3Pool(vPoolAddress);
    }

    uint256 _liquidity;

    function setLiquidityRates(
        int24 tickLower,
        int24 tickUpper,
        uint256 vQuotePerLiquidity,
        uint256 vTokenPerLiquidity
    ) external {
        LiquidityRate storage liquidityRate = _liquidityRates[tickLower][tickUpper];
        liquidityRate.vQuotePerLiquidity = vQuotePerLiquidity;
        liquidityRate.vTokenPerLiquidity = vTokenPerLiquidity;
    }

    function mint(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        external
        returns (
            uint256 vTokenAmount,
            uint256 vQuoteAmount,
            WrapperValuesInside memory wrapperValuesInside
        )
    {
        _liquidity += liquidity;

        vTokenAmount = _liquidityRates[tickLower][tickUpper].vTokenPerLiquidity * liquidity;
        vQuoteAmount = _liquidityRates[tickLower][tickUpper].vQuotePerLiquidity * liquidity;
        wrapperValuesInside = getValuesInside(tickLower, tickUpper);
    }

    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        external
        returns (
            uint256 vTokenAmount,
            uint256 vQuoteAmount,
            WrapperValuesInside memory wrapperValuesInside
        )
    {
        _liquidity -= liquidity;

        vQuoteAmount = _liquidityRates[tickLower][tickUpper].vQuotePerLiquidity * liquidity;
        vTokenAmount = _liquidityRates[tickLower][tickUpper].vTokenPerLiquidity * liquidity;
        wrapperValuesInside = getValuesInside(tickLower, tickUpper);
    }

    function getSumAX128() external pure returns (int256) {
        return 20 * (1 << 128);
    }

    function getExtrapolatedSumAX128() external pure returns (int256) {
        return 20 * (1 << 128);
    }

    function swapTokenAmount(int256 vTokenAmount) external pure returns (int256) {
        return vTokenAmount * (-4000);
    }

    function swap(
        bool swapVTokenForVQuote, // zeroForOne
        int256 amountSpecified,
        uint160
    ) public pure returns (SwapResult memory swapResult) {
        if (amountSpecified > 0 == swapVTokenForVQuote) {
            // ETH exactIn || ETH exactOut
            swapResult.vTokenIn = amountSpecified;
            swapResult.vQuoteIn = -amountSpecified * 4000;
        } else {
            // USDC exactIn || USDC exactOut
            swapResult.vTokenIn = -amountSpecified / 4000;
            swapResult.vQuoteIn = amountSpecified;
        }
    }

    function swapTokenNotional(int256 vTokenNotional) external pure returns (int256) {
        return vTokenNotional / (4000);
    }

    function collectAccruedProtocolFee() external pure returns (uint256 accruedProtocolFeeLast) {
        accruedProtocolFeeLast = 0;
    }
}

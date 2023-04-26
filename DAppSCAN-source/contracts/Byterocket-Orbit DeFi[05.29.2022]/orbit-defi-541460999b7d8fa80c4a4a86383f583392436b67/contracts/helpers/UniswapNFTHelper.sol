// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol';
import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol';

///@title library to interact with NFT token and do some useful function with it
library UniswapNFTHelper {
    ///@notice get the pool address
    ///@param factory address of the UniswapV3Factory
    ///@param token0 address of the token0
    ///@param token1 address of the token1
    ///@param fee fee tier of the pool
    ///@return address address of the pool
    function _getPool(
        address factory,
        address token0,
        address token1,
        uint24 fee
    ) internal pure returns (address) {
        return PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(token0, token1, fee));
    }

    ///@notice get the address of the pool from the tokenId
    ///@param tokenId id of the position (NFT)
    ///@param nonfungiblePositionManager instance of the nonfungiblePositionManager given by the caller (address)
    ///@param factory address of the UniswapV3Factory
    ///@return address address of the pool
    function _getPoolFromTokenId(
        uint256 tokenId,
        INonfungiblePositionManager nonfungiblePositionManager,
        address factory
    ) internal view returns (address) {
        (, , address token0, address token1, uint24 fee, , , , , , , ) = nonfungiblePositionManager.positions(tokenId);

        return _getPool(factory, token0, token1, fee);
    }

    ///@notice get the address of the tpkens from the tokenId
    ///@param tokenId id of the position (NFT)
    ///@param nonfungiblePositionManager instance of the nonfungiblePositionManager given by the caller (address)
    ///@return token0address address of the token0
    ///@return token1address address of the token1
    ///@return fee fee tier of the pool
    ///@return tickLower of position
    ///@return tickUpper of position
    function _getTokens(uint256 tokenId, INonfungiblePositionManager nonfungiblePositionManager)
        internal
        view
        returns (
            address token0address,
            address token1address,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper
        )
    {
        (, , token0address, token1address, fee, tickLower, tickUpper, , , , , ) = nonfungiblePositionManager.positions(
            tokenId
        );
    }

    ///@notice get the amount of tokens in a position
    ///@param tokenId id of the position (NFT)
    ///@param nonfungiblePositionManager instance of the nonfungiblePositionManager given by the caller (address)
    ///@param factory address of the UniswapV3Factory
    ///@return uint256 amount of token0
    ///@return uint256 amount of token1
    function _getAmountsfromTokenId(
        uint256 tokenId,
        INonfungiblePositionManager nonfungiblePositionManager,
        address factory
    ) internal view returns (uint256, uint256) {
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(
            tokenId
        );
        return
            _getAmountsFromLiquidity(
                liquidity,
                tickLower,
                tickUpper,
                _getPoolFromTokenId(tokenId, nonfungiblePositionManager, factory)
            );
    }

    ///@notice get the amount of tokens from liquidity and tick ranges
    ///@param liquidity amount of liquidity to convert
    ///@param tickLower lower tick range
    ///@param tickUpper upper tick range
    ///@param poolAddress address of the pool
    ///@return uint256 amount of token0
    ///@return uint256 amount of token1
    function _getAmountsFromLiquidity(
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper,
        address poolAddress
    ) internal view returns (uint256, uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
    }

    ///@notice Computes the amount of liquidity for a given amount of token0, token1
    ///@param token0 The amount of token0 being sent in
    ///@param token1 The amount of token1 being sent in
    ///@param tickLower lower tick range
    ///@param tickUpper upper tick range
    ///@param poolAddress The address of the pool
    ///@return uint128 The amount of liquidity received
    function _getLiquidityFromAmounts(
        uint256 token0,
        uint256 token1,
        int24 tickLower,
        int24 tickUpper,
        address poolAddress
    ) internal view returns (uint128) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        return
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                token0,
                token1
            );
    }
}

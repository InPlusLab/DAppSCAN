// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '../../helpers/UniswapNFTHelper.sol';

contract MockUniswapNFTHelper {
    ///@notice contract to interact with NFT helper for testing

    ///@notice get the pool address
    ///@param factory address of the UniswapV3Factory
    ///@param token0 address of the token0
    ///@param token1 address of the token1
    ///@param fee fee tier of the pool
    ///@return address address of the pool
    function getPool(
        address factory,
        address token0,
        address token1,
        uint24 fee
    ) public pure returns (address) {
        return UniswapNFTHelper._getPool(factory, token0, token1, fee);
    }

    ///@notice get the address of the pool from the tokenId
    ///@param tokenId id of the position (NFT)
    ///@param nonfungiblePositionManager instance of the nonfungiblePositionManager given by the caller (address)
    ///@param factory address of the UniswapV3Factory
    ///@return address address of the pool
    function getPoolFromTokenId(
        uint256 tokenId,
        INonfungiblePositionManager nonfungiblePositionManager,
        address factory
    ) public view returns (address) {
        return UniswapNFTHelper._getPoolFromTokenId(tokenId, nonfungiblePositionManager, factory);
    }

    ///@notice get the address of the tpkens from the tokenId
    ///@param tokenId id of the position (NFT)
    ///@param nonfungiblePositionManager instance of the nonfungiblePositionManager given by the caller (address)
    ///@return token0address address of the token0
    ///@return token1address address of the token1
    ///@return fee fee tier of the pool
    ///@return tickLower of position
    ///@return tickUpper of position
    function getTokens(uint256 tokenId, INonfungiblePositionManager nonfungiblePositionManager)
        public
        view
        returns (
            address token0address,
            address token1address,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper
        )
    {
        return UniswapNFTHelper._getTokens(tokenId, nonfungiblePositionManager);
    }

    ///@notice get the amount of tokens in a position
    ///@param tokenId id of the position (NFT)
    ///@param nonfungiblePositionManager instance of the nonfungiblePositionManager given by the caller (address)
    ///@param factory address of the UniswapV3Factory
    ///@return uint256 amount of token0
    ///@return uint256 amount of token1
    function getAmountsfromTokenId(
        uint256 tokenId,
        INonfungiblePositionManager nonfungiblePositionManager,
        address factory
    ) public view returns (uint256, uint256) {
        return UniswapNFTHelper._getAmountsfromTokenId(tokenId, nonfungiblePositionManager, factory);
    }

    ///@notice get the amount of tokens from liquidity and tick ranges
    ///@param liquidity amount of liquidity to convert
    ///@param tickLower lower tick range
    ///@param tickUpper upper tick range
    ///@param poolAddress address of the pool
    ///@return uint256 amount of token0
    ///@return uint256 amount of token1
    function getAmountsFromLiquidity(
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper,
        address poolAddress
    ) public view returns (uint256, uint256) {
        return UniswapNFTHelper._getAmountsFromLiquidity(liquidity, tickLower, tickUpper, poolAddress);
    }

    ///@notice Computes the amount of liquidity for a given amount of token0, token1
    ///@param token0 The amount of token0 being sent in
    ///@param token1 The amount of token1 being sent in
    ///@param tickLower lower tick range
    ///@param tickUpper upper tick range
    ///@param poolAddress The address of the pool
    ///@return uint128 The amount of liquidity received
    function getLiquidityFromAmounts(
        uint256 token0,
        uint256 token1,
        int24 tickLower,
        int24 tickUpper,
        address poolAddress
    ) public view returns (uint128) {
        return UniswapNFTHelper._getLiquidityFromAmounts(token0, token1, tickLower, tickUpper, poolAddress);
    }
}

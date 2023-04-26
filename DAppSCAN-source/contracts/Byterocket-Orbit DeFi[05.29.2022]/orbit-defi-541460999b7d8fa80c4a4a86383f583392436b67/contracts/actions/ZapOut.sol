// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '../helpers/UniswapNFTHelper.sol';
import '../helpers/ERC20Helper.sol';
import '../utils/Storage.sol';
import '../../interfaces/IPositionManager.sol';
import '../../interfaces/actions/IZapOut.sol';

///@notice ZapOut allows users to close positions and withdraw to a single output token
contract ZapOut is IZapOut {
    ///@notice emitted when a UniswapNFT is zapped out
    ///@param positionManager address of PositionManager
    ///@param tokenId Id of zapped token
    ///@param tokenOut address of token zapped out
    ///@param amountOut amount of tokenOut zapped out
    event ZappedOut(address indexed positionManager, uint256 tokenId, address tokenOut, uint256 amountOut);

    ///@notice burns a uni NFT with a single output token, the output token can be different from the two position tokens
    ///@param tokenId id of the NFT to burn
    ///@param tokenOut address of output token
    ///@return uint256 amount of tokenOut withdrawn
    function zapOut(uint256 tokenId, address tokenOut) public override returns (uint256) {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();
        INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(
            Storage.uniswapAddressHolder.nonfungiblePositionManagerAddress()
        );

        (address token0, address token1, , , ) = UniswapNFTHelper._getTokens(tokenId, nonfungiblePositionManager);

        (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);

        nonfungiblePositionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 120
            })
        );

        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: 2**128 - 1,
                amount1Max: 2**128 - 1
            })
        );

        nonfungiblePositionManager.burn(tokenId);
        IPositionManager(address(this)).removePositionId(tokenId);

        if (tokenOut != token0) {
            amount0 = _swapToTokenOut(tokenOut, token0, amount0);
        }

        if (tokenOut != token1) {
            amount1 = _swapToTokenOut(tokenOut, token1, amount1);
        }

        ERC20Helper._approveToken(tokenOut, address(this), amount0 + amount1);
        ERC20Helper._withdrawTokens(tokenOut, Storage.owner, amount0 + amount1);

        emit ZappedOut(address(this), tokenId, tokenOut, amount0 + amount1);
        return amount0 + amount1;
    }

    ///@notice performs the swap to tokenOut
    ///@param tokenOut address of output token
    ///@param tokenIn address of input token
    ///@param amountIn amount of input token
    ///@return amountOut of output token
    function _swapToTokenOut(
        address tokenOut,
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();

        ERC20Helper._approveToken(tokenIn, Storage.uniswapAddressHolder.swapRouterAddress(), amountIn);

        ISwapRouter swapRouter = ISwapRouter(Storage.uniswapAddressHolder.swapRouterAddress());
        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: _findBestFee(tokenIn, tokenOut),
                recipient: address(this),
                deadline: block.timestamp + 120,
                amountIn: amountIn,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
        );
    }

    ///@notice finds the best fee tier on which to perform a swap
    ///@param token0 address of first token
    ///@param token1 address of second token
    ///@return fee suggested fee tier
    function _findBestFee(address token0, address token1) internal view returns (uint24 fee) {
        uint128 bestLiquidity = 0;
        uint16[4] memory fees = [100, 500, 3000, 10000];

        for (uint8 i = 0; i < 4; i++) {
            try this.getPoolLiquidity(token0, token1, uint24(fees[i])) returns (uint128 nextLiquidity) {
                if (nextLiquidity > bestLiquidity) {
                    bestLiquidity = nextLiquidity;
                    fee = fees[i];
                }
            } catch {
                //pass
            }
        }

        if (bestLiquidity == 0) {
            revert('ZapOut::_findBestFee: No pool found with desired tokens');
        }
    }

    ///@notice wrapper of getPoolLiquidity to use try/catch statement
    ///@param token0 address of first token
    ///@param token1 address of second token
    ///@param fee pool fee tier
    ///@return liquidity of the pool
    function getPoolLiquidity(
        address token0,
        address token1,
        uint24 fee
    ) public view returns (uint128 liquidity) {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();
        return
            IUniswapV3Pool(
                UniswapNFTHelper._getPool(Storage.uniswapAddressHolder.uniswapV3FactoryAddress(), token0, token1, fee)
            ).liquidity();
    }
}

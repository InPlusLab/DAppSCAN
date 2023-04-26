// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '../helpers/ERC20Helper.sol';
import '../utils/Storage.sol';
import '../../interfaces/actions/ISwap.sol';

contract Swap is ISwap {
    ///@notice emitted when a swap is performed
    ///@param positionManager address of the position manager which performed the swap
    ///@param tokenIn address of the token being swapped in
    ///@param tokenOut address of the token being swapped out
    ///@param amountIn amount of the token being swapped in
    ///@param amountOut amount of the token being swapped out
    event Swapped(
        address indexed positionManager,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    ///@notice swaps token0 for token1 on uniswap
    ///@param token0Address address of first token
    ///@param token1Address address of second token
    ///@param fee fee tier of the pool
    ///@param amount0In amount of token0 to swap
    function swap(
        address token0Address,
        address token1Address,
        uint24 fee,
        uint256 amount0In
    ) public override returns (uint256 amount1Out) {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();
        ISwapRouter swapRouter = ISwapRouter(Storage.uniswapAddressHolder.swapRouterAddress());

        ERC20Helper._approveToken(token0Address, address(swapRouter), 2**256 - 1);
        ERC20Helper._approveToken(token1Address, address(swapRouter), 2**256 - 1);

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: token0Address,
            tokenOut: token1Address,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp + 120,
            amountIn: amount0In,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        amount1Out = swapRouter.exactInputSingle(swapParams);
        emit Swapped(address(this), token0Address, token1Address, amount0In, amount1Out);
    }
}
